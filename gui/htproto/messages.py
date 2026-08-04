"""Message types for the HT_MK1 protocol (brief sections 3.2-3.4)."""

from __future__ import annotations

from dataclasses import dataclass


# ---- Replies (instrument -> GUI, '<' prefix) ----


@dataclass(frozen=True)
class Pong:
    """<PONG"""


@dataclass(frozen=True)
class IdReply:
    """<ID HT_MK1 fw=<semver> proto=1"""

    fw: str
    proto: int


@dataclass(frozen=True)
class StatusReply:
    """<STATUS state=<state> fixture=<fixture> hv_mv=<int>"""

    state: "State"
    fixture: "Fixture"
    hv_mv: int


@dataclass(frozen=True)
class Ok:
    """<OK [detail...]  e.g. <OK started, <OK armed, <OK loaded=12"""

    detail: str = ""


@dataclass(frozen=True)
class ErrReply:
    """<ERR <code> <text>"""

    code: str
    text: str


@dataclass(frozen=True)
class NetlistReply:
    """<NETLIST <n>  (header of a NETLIST GET response)"""

    count: int


@dataclass(frozen=True)
class NetEntry:
    """<NET <hi> <lo>  (one line of a NETLIST GET response)"""

    hi: int
    lo: int


@dataclass(frozen=True)
class CalReply:
    """<CAL current_ua=<int> gain=<int> rref_mohm=<int>"""

    current_ua: int
    gain: int
    rref_mohm: int


@dataclass(frozen=True)
class LimitsReply:
    """<LIMITS r_max_mohm=<int> ins_min_mohm=<int>"""

    r_max_mohm: int
    ins_min_mohm: int


# ---- Events (instrument -> GUI, '!' prefix) ----


@dataclass(frozen=True)
class Progress:
    """!PROGRESS <done> <total>"""

    done: int
    total: int


@dataclass(frozen=True)
class ContResult:
    """!CONT <hi> <lo> <pass|open|short>"""

    hi: int
    lo: int
    status: "ContStatus"


@dataclass(frozen=True)
class ResResult:
    """!RES <hi> <lo> <milliohms> <pass|fail_high|fail_low>"""

    hi: int
    lo: int
    milliohms: int
    status: "ResStatus"


@dataclass(frozen=True)
class InsulResult:
    """!INSUL <net> <leak_mohm> <pass|fail>"""

    net: int
    leak_mohm: int
    status: "InsulStatus"


@dataclass(frozen=True)
class Fault:
    """!FAULT <code> <text>"""

    code: str
    text: str


@dataclass(frozen=True)
class Done:
    """!DONE <cont|res|insul> <passed> <failed>"""

    kind: "TestKind"
    passed: int
    failed: int


@dataclass(frozen=True)
class StateEvent:
    """!STATE <idle|running|fault|hv_armed>"""

    state: "State"


@dataclass(frozen=True)
class FixtureEvent:
    """!FIXTURE <none|mtx|hv>"""

    fixture: "Fixture"


@dataclass(frozen=True)
class HvEvent:
    """!HV <millivolts>"""

    millivolts: int


@dataclass(frozen=True)
class SafeEvent:
    """!SAFE"""


# ---- Log lines (instrument -> GUI, '#' prefix): display, do not parse ----


@dataclass(frozen=True)
class LogLine:
    """# <free text>"""

    text: str


# Late imports for the string annotations above.
from .codec import ContStatus, Fixture, InsulStatus, ResStatus, State, TestKind  # noqa: E402
