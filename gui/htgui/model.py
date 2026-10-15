"""Instrument state model — everything the screens read, and the safety rules.

Deliberately free of any Tk import. The rules in brief §2 and §3.5 are the part
that must not be wrong, so they live here where they can be tested without a
display.

Two rules drive most of the design:

- **"Safe" is a state the instrument must TELL us.** It is never inferred from
  a run finishing, from an ordering of events, or from silence. Anything we did
  not hear is ``UNKNOWN`` (brief §2 rule 4).
- **Arming is fragile on purpose.** Any fixture change, any ``!SAFE``, any drop
  to idle, and any link trouble clears it (§3.5 rule 8).
"""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass, field
from enum import Enum

from htproto import (
    ContResult,
    Done,
    Fault,
    FixtureEvent,
    HvEvent,
    InsulResult,
    LogLine,
    Progress,
    ResResult,
    SafeEvent,
    StateEvent,
    StatusReply,
)
from htproto.codec import Fixture, State, TestKind

#: Rail at or above this is live (brief §3.5 rule 2, firmware PROTO_HV_LIVE_MV).
HV_LIVE_MV = 50_000


class Handling(Enum):
    """Whether it is safe to touch the harness."""

    UNKNOWN = "unknown"    # we have not been told — never present this as safe
    SAFE = "safe"          # !SAFE received, nothing since has raised the rail
    LIVE = "live"          # rail up, armed, or a run in progress


@dataclass
class RunRecord:
    kind: str
    passed: int
    failed: int
    started: float
    finished: float

    @property
    def total(self) -> int:
        return self.passed + self.failed

    @property
    def yield_pct(self) -> float:
        return 100.0 * self.passed / self.total if self.total else 0.0


@dataclass
class InstrumentModel:
    """Aggregates the event stream. Every mutator is under one lock."""

    link_ok: bool = False
    link_detail: str = "not connected"
    state: State | None = None
    fixture: Fixture | None = None
    hv_mv: int = 0
    armed: bool = False
    _handling: Handling = Handling.UNKNOWN

    run_kind: str | None = None
    run_started: float = 0.0
    progress_done: int = 0
    progress_total: int = 0

    cont: list[ContResult] = field(default_factory=list)
    res: list[ResResult] = field(default_factory=list)
    insul: list[InsulResult] = field(default_factory=list)
    faults: list[tuple[float, Fault]] = field(default_factory=list)
    logs: list[str] = field(default_factory=list)
    history: list[RunRecord] = field(default_factory=list)

    netlist: list[tuple[int, int]] = field(default_factory=list)
    cal: object | None = None
    limits: object | None = None

    _lock: threading.RLock = field(default_factory=threading.RLock, repr=False)
    _listeners: list = field(default_factory=list, repr=False)

    # -- observation -----------------------------------------------------------

    def subscribe(self, fn) -> None:
        with self._lock:
            self._listeners.append(fn)

    def _notify(self) -> None:
        for fn in list(self._listeners):
            fn()

    # -- derived safety state --------------------------------------------------

    @property
    def handling(self) -> Handling:
        with self._lock:
            if not self.link_ok:
                return Handling.UNKNOWN     # §2 rule 4: never "safe" on a dead link
            return self._handling

    @property
    def hv_live(self) -> bool:
        with self._lock:
            return self.hv_mv >= HV_LIVE_MV

    @property
    def running(self) -> bool:
        with self._lock:
            return self.run_kind is not None

    @property
    def insulation_allowed(self) -> bool:
        """§2 rule 5 — locked until the instrument says the harness is on HV."""
        with self._lock:
            return self.link_ok and self.fixture is Fixture.HV

    @property
    def can_energise(self) -> bool:
        """Anything that could put voltage on the harness needs all of this."""
        with self._lock:
            return self.link_ok and self.fixture is Fixture.HV and self.armed

    def status_text(self) -> str:
        with self._lock:
            if not self.link_ok:
                return f"LINK LOST — state unknown ({self.link_detail})"
            bits = [f"state={self.state.value if self.state else '?'}",
                    f"fixture={self.fixture.value if self.fixture else '?'}",
                    f"rail={self.hv_mv/1000.0:.1f} V"]
            if self.armed:
                bits.append("ARMED")
            return "   ".join(bits)

    # -- link ------------------------------------------------------------------

    def set_link(self, ok: bool, detail: str) -> None:
        with self._lock:
            self.link_ok = ok
            self.link_detail = detail
            if not ok:
                # We can no longer know anything. Drop the arm and stop claiming
                # a run is in flight; do NOT claim safety.
                self.armed = False
                self._handling = Handling.UNKNOWN
                self.run_kind = None
        self._notify()

    def apply_status(self, st: StatusReply) -> None:
        """Fold in a >STATUS reply (reconnect handshake, §3.5 rule 4)."""
        with self._lock:
            self.state = st.state
            self.fixture = st.fixture
            self.hv_mv = st.hv_mv
            self.armed = st.state is State.HV_ARMED
            # STATUS says nothing about whether the harness is safe to touch,
            # and it cannot report `running` at all (§3.2) — so stay UNKNOWN
            # until an event tells us otherwise.
            self._handling = Handling.LIVE if (self.armed or st.hv_mv > 0) \
                else Handling.UNKNOWN
        self._notify()

    # -- events ----------------------------------------------------------------

    def apply_event(self, msg) -> None:
        with self._lock:
            self._apply_locked(msg)
        self._notify()

    def _apply_locked(self, msg) -> None:
        if isinstance(msg, LogLine):
            self.logs.append(msg.text)
            del self.logs[:-500]
            return

        if isinstance(msg, HvEvent):
            self.hv_mv = msg.millivolts
            if msg.millivolts > 0:
                self._handling = Handling.LIVE
            return

        if isinstance(msg, SafeEvent):
            # The one and only source of "safe to handle" (§3.3).
            self._handling = Handling.SAFE
            self.armed = False
            self.hv_mv = 0
            return

        if isinstance(msg, FixtureEvent):
            # Any fixture change invalidates arming — solicited or not
            # (§3.5 rule 8). The instrument has already dropped it.
            if msg.fixture is not self.fixture:
                self.armed = False
            self.fixture = msg.fixture
            return

        if isinstance(msg, StateEvent):
            self.state = msg.state
            if msg.state is State.HV_ARMED:
                self.armed = True
                self._handling = Handling.LIVE
            elif msg.state is State.RUNNING:
                self._handling = Handling.LIVE
            elif msg.state is State.IDLE:
                self.armed = False
            elif msg.state is State.FAULT:
                self.armed = False
                self._handling = Handling.UNKNOWN
            return

        if isinstance(msg, Progress):
            self.progress_done, self.progress_total = msg.done, msg.total
            return

        if isinstance(msg, ContResult):
            self.cont.append(msg)
            return
        if isinstance(msg, ResResult):
            self.res.append(msg)
            return
        if isinstance(msg, InsulResult):
            self.insul.append(msg)
            return

        if isinstance(msg, Fault):
            self.faults.append((time.time(), msg))
            return

        if isinstance(msg, Done):
            # !DONE closes the run and nothing else. It says nothing about
            # whether the hardware is safe — only !SAFE does (§3.3).
            #
            # Continuity and resistance runs never emit !SAFE, so at this point
            # we have no evidence either way: drop LIVE to UNKNOWN rather than
            # keep claiming "energised", which would be asserting something we
            # were never told. An insulation run has already sent !SAFE, and
            # that must not be downgraded.
            if self._handling is Handling.LIVE and self.hv_mv == 0 and not self.armed:
                self._handling = Handling.UNKNOWN
            self.history.append(RunRecord(
                kind=msg.kind.value, passed=msg.passed, failed=msg.failed,
                started=self.run_started, finished=time.time()))
            self.run_kind = None
            self.progress_done = self.progress_total = 0
            return

    # -- GUI-driven bookkeeping ------------------------------------------------

    def note_run_started(self, kind: str) -> None:
        with self._lock:
            self.run_kind = kind
            self.run_started = time.time()
            self.progress_done = self.progress_total = 0
            self._handling = Handling.LIVE
            if kind == TestKind.CONT.value:
                self.cont.clear()
            elif kind == TestKind.RES.value:
                self.res.clear()
            elif kind == TestKind.INSUL.value:
                self.insul.clear()
        self._notify()

    def clear_results(self) -> None:
        with self._lock:
            self.cont.clear()
            self.res.clear()
            self.insul.clear()
            self.faults.clear()
        self._notify()
