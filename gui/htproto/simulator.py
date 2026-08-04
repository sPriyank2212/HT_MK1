"""HT_MK1 instrument simulator (brief section 4).

Speaks the section 3 protocol over a TCP socket so the GUI can be developed
and regression-tested without hardware. The scenario is chosen at launch and
represents the *physical harness* plugged into the machine; commands and
replies are byte-exact per the contract.

Scenarios:
    pass            clean pass on every test
    opens_shorts    continuity: two opens and one short
    res_fail        resistance: fail_high and fail_low nets
    insul_fail      insulation: one low-leakage net + !FAULT F04
    disconnect      transport drops mid-run, no !DONE

Run (from gui/):
    python -m htproto.simulator --scenario pass --port 46000
"""

from __future__ import annotations

import argparse
import socket
import threading
import time
import traceback
from dataclasses import dataclass

from .codec import ContStatus, Fixture, InsulStatus, ResStatus, State

FW_VERSION = "1.0.0"
PROTO_VERSION = 1

#: Simulator defaults, standing in for instrument configuration.
DEFAULT_LIMIT_R_MAX_MOHM = 1000
DEFAULT_LIMIT_INS_MIN_MOHM = 100
DEFAULT_CAL_CURRENT_UA = 1000
DEFAULT_CAL_GAIN = 16
DEFAULT_CAL_RREF_MOHM = 100_000

#: HV rail range accepted by HV SET (500 V in millivolts).
HV_MAX_MV = 500_000

#: Discover mode scans 256 pins and reports nets as they are found.
DISCOVER_PINS = 256


@dataclass(frozen=True)
class NetOutcome:
    """One physical net of the simulated harness."""

    hi: int
    lo: int
    cont: ContStatus = ContStatus.PASS
    res_mohm: int = 50
    res_status: ResStatus = ResStatus.PASS
    insul_leak_mohm: int = 500
    insul_status: InsulStatus = InsulStatus.PASS


@dataclass(frozen=True)
class Scenario:
    name: str
    nets: tuple[NetOutcome, ...]
    #: fraction of a run after which the transport drops (disconnect scenario)
    disconnect_at: float | None = None


def _good_nets(count: int) -> list[NetOutcome]:
    return [NetOutcome(hi=2 * i + 1, lo=2 * i + 2) for i in range(count)]


def make_scenario(name: str, nets: int = 12) -> Scenario:
    base = _good_nets(nets)
    if nets < 4:
        raise ValueError("need at least 4 nets for scenarios")
    if name == "pass":
        return Scenario(name, tuple(base))
    if name == "opens_shorts":
        base[0] = NetOutcome(base[0].hi, base[0].lo, cont=ContStatus.OPEN)
        base[1] = NetOutcome(base[1].hi, base[1].lo, cont=ContStatus.OPEN)
        base[2] = NetOutcome(base[2].hi, base[2].lo, cont=ContStatus.SHORT)
        return Scenario(name, tuple(base))
    if name == "res_fail":
        base[0] = NetOutcome(base[0].hi, base[0].lo, res_mohm=2500,
                             res_status=ResStatus.FAIL_HIGH)
        base[1] = NetOutcome(base[1].hi, base[1].lo, res_mohm=2,
                             res_status=ResStatus.FAIL_LOW)
        return Scenario(name, tuple(base))
    if name == "insul_fail":
        base[2] = NetOutcome(base[2].hi, base[2].lo, insul_leak_mohm=5,
                             insul_status=InsulStatus.FAIL)
        return Scenario(name, tuple(base))
    if name == "disconnect":
        return Scenario(name, tuple(base), disconnect_at=0.4)
    raise ValueError(f"unknown scenario {name!r}")


SCENARIO_NAMES = ("pass", "opens_shorts", "res_fail", "insul_fail", "disconnect")


@dataclass
class _InstrumentState:
    state: State = State.IDLE
    fixture: Fixture = Fixture.NONE
    hv_mv: int = 0
    netlist: list[tuple[int, int]] | None = None  # uploaded by GUI; None = not uploaded
    _netlist_staging: list[tuple[int, int]] | None = None
    r_max_mohm: int = DEFAULT_LIMIT_R_MAX_MOHM
    ins_min_mohm: int = DEFAULT_LIMIT_INS_MIN_MOHM
    cal_current_ua: int = DEFAULT_CAL_CURRENT_UA
    cal_gain: int = DEFAULT_CAL_GAIN
    cal_rref_mohm: int = DEFAULT_CAL_RREF_MOHM


class InstrumentSim:
    """Protocol state machine. Transport feeds it lines and it sends lines back."""

    def __init__(self, scenario: Scenario, interval: float = 0.02,
                 send=None, on_drop=None) -> None:
        self.scenario = scenario
        self.interval = interval
        self._send = send          # callable(str) -> None, one full line with \n
        self._on_drop = on_drop    # callable() -> None, hard transport drop
        self._st = _InstrumentState()
        self._run_stop = threading.Event()
        self._run_thread: threading.Thread | None = None
        self._deferred = None      # callable run after the current reply is sent

    # -- transport interface -------------------------------------------------

    def handle_line(self, line: str) -> None:
        """Process one received command line (without trailing newline)."""
        line = line.rstrip("\r")
        if line.startswith(">"):
            line = line[1:]  # leading '>' is optional on commands (appendix B)
        tokens = line.split(" ")
        reply = self._dispatch(tokens)
        if reply is not None:
            self._emit_reply(reply)
        if self._deferred is not None:
            deferred, self._deferred = self._deferred, None
            threading.Thread(target=deferred, daemon=True).start()

    def close(self) -> None:
        """Client went away: stop any run, disarm nothing (state is unknown to GUI)."""
        self._run_stop.set()
        t = self._run_thread
        if t is not None and t is not threading.current_thread():
            t.join(timeout=2)

    # -- emit helpers ---------------------------------------------------------

    def _emit_reply(self, body: str) -> None:
        self._send("<" + body + "\n")

    def _emit_event(self, body: str) -> None:
        try:
            self._send("!" + body + "\n")
        except OSError:
            self._run_stop.set()  # client vanished mid-run

    def _set_state(self, state: State) -> None:
        self._st.state = state
        self._emit_event(f"STATE {state.value}")

    def _set_hv(self, mv: int) -> None:
        if abs(mv - self._st.hv_mv) > 10:
            self._st.hv_mv = mv
            self._emit_event(f"HV {mv}")

    def _ramp_hv(self, target: int) -> None:
        step = max(10, abs(target - self._st.hv_mv) // 20)
        while self._st.hv_mv != target and not self._run_stop.is_set():
            cur = self._st.hv_mv
            nxt = target if abs(target - cur) <= step else cur + (step if target > cur else -step)
            self._set_hv(nxt)
            time.sleep(min(self.interval, 0.005))

    # -- command dispatch ------------------------------------------------------

    def _dispatch(self, t: list[str]) -> str | None:
        head = t[0]
        try:
            if head == "PING" and len(t) == 1:
                return "PONG"
            if head == "ID" and len(t) == 1:
                return f"ID HT_MK1 fw={FW_VERSION} proto={PROTO_VERSION}"
            if head == "STATUS" and len(t) == 1:
                s = self._st
                return f"STATUS state={s.state.value} fixture={s.fixture.value} hv_mv={s.hv_mv}"
            if head == "SAFE" and len(t) == 1:
                self._force_safe()
                return "OK"
            if head == "ABORT" and len(t) == 1:
                self._force_safe()
                return "OK"
            if head == "FIXTURE" and len(t) == 2 and t[1] in ("none", "mtx", "hv"):
                self._st.fixture = Fixture(t[1])
                self._emit_event(f"FIXTURE {t[1]}")
                return "OK"
            if head == "NETLIST":
                return self._netlist(t[1:])
            if head == "CONT" and len(t) == 3 and t[1] == "RUN" and t[2] in ("verify", "discover"):
                return self._start_run("cont", t[2])
            if head == "RES" and len(t) == 2 and t[1] == "RUN":
                return self._start_run("res", None)
            if head == "INSUL" and len(t) == 2 and t[1] == "ARM":
                return self._insul_arm()
            if head == "INSUL" and len(t) == 2 and t[1] == "RUN":
                return self._start_run("insul", None)
            if head == "HV" and len(t) == 3 and t[1] == "SET":
                return self._hv_set(t[2])
            if head == "MANUAL" and len(t) == 4 and t[1] == "PATH":
                int(t[2]); int(t[3])
                return "OK"
            if head == "MANUAL" and len(t) == 5 and t[1] == "RELAY":
                # Refused by design (brief section 0).
                return "ERR EHW manual relay control refused by design"
            if head == "MANUAL" and len(t) == 2 and t[1] == "OFF":
                return "OK"
            if head == "CAL" and len(t) == 2 and t[1] == "GET":
                s = self._st
                return f"CAL current_ua={s.cal_current_ua} gain={s.cal_gain} rref_mohm={s.cal_rref_mohm}"
            if head == "LIMITS" and len(t) == 2 and t[1] == "GET":
                return f"LIMITS r_max_mohm={self._st.r_max_mohm} ins_min_mohm={self._st.ins_min_mohm}"
            if head == "LIMITS" and len(t) == 4 and t[1] == "SET":
                return self._limits_set(t[2], t[3])
        except (ValueError, IndexError):
            pass
        return f"ERR ESYNTAX unrecognised command: {' '.join(t)}"

    def _netlist(self, t: list[str]) -> str:
        if t[:1] == ["BEGIN"] and len(t) == 2:
            self._st._netlist_staging = []
            return "OK"
        if t[:1] == ["ADD"] and len(t) == 3:
            if self._st._netlist_staging is None:
                return "ERR ESYNTAX NETLIST ADD without BEGIN"
            self._st._netlist_staging.append((int(t[1]), int(t[2])))
            return "OK"
        if t[:1] == ["END"] and len(t) == 1:
            staging = self._st._netlist_staging or []
            self._st.netlist = list(staging)
            self._st._netlist_staging = None
            return f"OK loaded={len(staging)}"
        if t[:1] == ["GET"] and len(t) == 1:
            # One command, one reply sequence per 3.2: header first, then
            # one <NET line per entry, all before the next command's reply.
            nets = self._st.netlist or []
            self._emit_reply(f"NETLIST {len(nets)}")
            for hi, lo in nets:
                self._emit_reply(f"NET {hi} {lo}")
            return None
        return "ERR ESYNTAX unrecognised NETLIST command"

    def _limits_set(self, r_tok: str, ins_tok: str) -> str:
        if not r_tok.startswith("r_max_mohm=") or not ins_tok.startswith("ins_min_mohm="):
            return "ERR ESYNTAX expected r_max_mohm=<int> ins_min_mohm=<int>"
        self._st.r_max_mohm = int(r_tok.split("=", 1)[1])
        self._st.ins_min_mohm = int(ins_tok.split("=", 1)[1])
        return "OK"

    def _hv_set(self, mv_tok: str) -> str:
        mv = int(mv_tok)
        if mv > HV_MAX_MV:
            return f"ERR ERANGE hv setpoint {mv} mV exceeds {HV_MAX_MV} mV"
        # Reply goes out first; the ramp streams !HV events afterwards (3.4).
        self._deferred = lambda: self._ramp_hv(mv)
        return "OK"

    def _insul_arm(self) -> str:
        if self._st.state is State.RUNNING:
            return "ERR EBUSY test in progress"
        if self._st.fixture is not Fixture.HV:
            return f"ERR EFIXTURE harness is on the {self._st.fixture.value} fixture"
        self._set_state(State.HV_ARMED)
        return "OK armed"

    # -- runs -------------------------------------------------------------------

    def _start_run(self, kind: str, mode: str | None) -> str:
        if self._st.state is State.RUNNING:
            return "ERR EBUSY test in progress"
        if kind == "insul" and self._st.state is not State.HV_ARMED:
            return "ERR ENOTARMED insulation not armed"
        self._run_stop.clear()
        self._st.state = State.RUNNING
        target = {"cont": self._run_cont, "res": self._run_res, "insul": self._run_insul}[kind]

        def begin() -> None:
            # After the <OK started reply: state event, then the run thread.
            self._emit_event(f"STATE {State.RUNNING.value}")
            self._run_thread = threading.Thread(target=target, args=(mode,), daemon=True)
            self._run_thread.start()

        self._deferred = begin
        return "OK started"

    def _force_safe(self) -> None:
        self._run_stop.set()
        t = self._run_thread
        if t is not None and t is not threading.current_thread():
            try:
                t.join(timeout=2)
            except RuntimeError:
                pass  # run thread created but not started yet (abort race)
        self._run_thread = None
        self._ramp_hv(0)
        self._st.hv_mv = 0
        self._emit_event("SAFE")
        self._set_state(State.IDLE)

    def _finish_run(self, kind: str, passed: int, failed: int) -> None:
        if kind == "insul":
            # Rail back to 0 before the run is reported finished.
            self._ramp_hv(0)
            self._st.hv_mv = 0
        self._emit_event(f"DONE {kind} {passed} {failed}")
        self._set_state(State.IDLE)

    def _maybe_disconnect(self, idx: int, total: int) -> bool:
        """disconnect scenario: hard-drop the transport part-way through a run."""
        at = self.scenario.disconnect_at
        if at is not None and total >= 3 and idx >= int(total * at) and self._on_drop is not None:
            self._on_drop()
            return True
        return False

    def _run_cont(self, mode: str | None) -> None:
        outcomes = { (n.hi, n.lo): n for n in self.scenario.nets }
        if mode == "verify":
            nets = self._st.netlist if self._st.netlist is not None else [ (n.hi, n.lo) for n in self.scenario.nets ]
            total = len(nets)
            passed = failed = 0
            for i, (hi, lo) in enumerate(nets):
                if self._run_stop.is_set() or self._maybe_disconnect(i, total):
                    return
                outcome = outcomes.get((hi, lo))
                status = outcome.cont if outcome else ContStatus.OPEN
                self._emit_event(f"CONT {hi} {lo} {status.value}")
                self._emit_event(f"PROGRESS {i + 1} {total}")
                if status is ContStatus.PASS:
                    passed += 1
                else:
                    failed += 1
                time.sleep(self.interval)
            self._finish_run("cont", passed, failed)
        else:  # discover: scan pins, report nets as found
            by_hi = {}
            for n in self.scenario.nets:
                by_hi.setdefault(n.hi, []).append(n)
            total = DISCOVER_PINS
            passed = 0
            for pin in range(1, total + 1):
                if self._run_stop.is_set() or self._maybe_disconnect(pin, total):
                    return
                for n in by_hi.get(pin, []):
                    self._emit_event(f"CONT {n.hi} {n.lo} {n.cont.value}")
                    if n.cont is ContStatus.PASS:
                        passed += 1
                self._emit_event(f"PROGRESS {pin} {total}")
                time.sleep(self.interval)
            failed = sum(1 for n in self.scenario.nets if n.cont is not ContStatus.PASS)
            self._finish_run("cont", passed, failed)

    def _run_res(self, _mode: str | None) -> None:
        nets = self.scenario.nets
        total = len(nets)
        passed = failed = 0
        for i, n in enumerate(nets):
            if self._run_stop.is_set() or self._maybe_disconnect(i, total):
                return
            self._emit_event(f"RES {n.hi} {n.lo} {n.res_mohm} {n.res_status.value}")
            self._emit_event(f"PROGRESS {i + 1} {total}")
            if n.res_status is ResStatus.PASS:
                passed += 1
            else:
                failed += 1
            time.sleep(self.interval)
        self._finish_run("res", passed, failed)

    def _run_insul(self, _mode: str | None) -> None:
        self._ramp_hv(HV_MAX_MV)
        nets = self.scenario.nets
        total = len(nets)
        passed = failed = 0
        for i, n in enumerate(nets):
            if self._run_stop.is_set() or self._maybe_disconnect(i, total):
                return
            self._emit_event(f"INSUL {i + 1} {n.insul_leak_mohm} {n.insul_status.value}")
            self._emit_event(f"PROGRESS {i + 1} {total}")
            if n.insul_status is InsulStatus.PASS:
                passed += 1
            else:
                failed += 1
                self._emit_event(f"FAULT F04 insulation low on net {i + 1}")
            time.sleep(self.interval)
        self._finish_run("insul", passed, failed)


class SimulatorServer:
    """TCP front-end: one client at a time, one InstrumentSim per scenario."""

    def __init__(self, scenario: Scenario, host: str = "127.0.0.1", port: int = 0,
                 interval: float = 0.02) -> None:
        self.scenario = scenario
        self.interval = interval
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.bind((host, port))
        self._sock.listen(1)
        self.host, self.port = self._sock.getsockname()[:2]
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._client: socket.socket | None = None

    def start(self) -> "SimulatorServer":
        self._thread = threading.Thread(target=self._serve, daemon=True)
        self._thread.start()
        return self

    def stop(self) -> None:
        self._stop.set()
        # accept() times out every 0.2 s, so the serve thread exits on its
        # own; no nudge connection needed. A second Ctrl-C during shutdown
        # must not turn into a traceback.
        if self._thread is not None:
            try:
                self._thread.join(timeout=2)
            except KeyboardInterrupt:
                pass
        self._sock.close()

    def _serve(self) -> None:
        self._sock.settimeout(0.2)
        while not self._stop.is_set():
            try:
                client, _ = self._sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            self._client = client
            try:
                self._handle_client(client)
            except Exception:
                # A bad client session must never kill the simulator.
                traceback.print_exc()
            finally:
                self._client = None
                try:
                    client.close()
                except OSError:
                    pass

    def _handle_client(self, client: socket.socket) -> None:
        send_lock = threading.Lock()

        def send(line: str) -> None:
            with send_lock:
                client.sendall(line.encode("ascii"))

        def drop() -> None:
            # Mid-run disconnect scenario: hard-close the transport.
            try:
                client.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                client.close()
            except OSError:
                pass

        sim = InstrumentSim(self.scenario, interval=self.interval, send=send, on_drop=drop)
        send("# HT_MK1 simulator scenario=" + self.scenario.name + "\n")
        buf = b""
        try:
            while True:
                data = client.recv(4096)
                if not data:
                    break
                buf += data
                while b"\n" in buf:
                    raw, buf = buf.split(b"\n", 1)
                    sim.handle_line(raw.decode("ascii", errors="replace"))
        except OSError:
            pass
        finally:
            sim.close()


def main() -> None:
    ap = argparse.ArgumentParser(description="HT_MK1 instrument simulator")
    ap.add_argument("--scenario", choices=SCENARIO_NAMES, default="pass")
    ap.add_argument("--nets", type=int, default=12, help="number of nets in the harness")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=46000)
    ap.add_argument("--interval", type=float, default=0.02,
                    help="delay between streamed result events, seconds")
    args = ap.parse_args()
    server = SimulatorServer(make_scenario(args.scenario, args.nets),
                             host=args.host, port=args.port, interval=args.interval).start()
    print(f"HT_MK1 simulator: scenario={args.scenario} nets={args.nets} "
          f"listening on {server.host}:{server.port}")
    print("Ctrl-C to stop. Connect the GUI, or test by hand: nc 127.0.0.1 "
          f"{server.port}")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nstopping...")
    finally:
        server.stop()


if __name__ == "__main__":
    main()
