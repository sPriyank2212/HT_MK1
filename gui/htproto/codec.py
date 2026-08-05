"""Wire codec for the HT_MK1 protocol (brief section 3).

Line-based ASCII, one message per line ending ``\\n``, fields space-separated.

- GUI -> instrument lines start with ``>`` (command)
- instrument -> GUI lines start with ``<`` (reply), ``!`` (event) or ``#`` (log)

The encoders in ``commands`` produce the exact bytes a command must occupy on
the wire, including the leading ``>`` and trailing ``\\n``. ``parse_line``
validates instrument lines strictly: wrong prefix, wrong field count, wrong
field order or a non-integer where the contract says integer all raise
``ProtocolError``. Anything that fails to parse must be surfaced by the
caller, never silently dropped (brief section 6, failure handling).
"""

from __future__ import annotations

import re
from enum import Enum

NEWLINE = b"\n"
CMD_PREFIX = ">"
REPLY_PREFIX = "<"
EVENT_PREFIX = "!"
LOG_PREFIX = "#"


class ProtocolError(ValueError):
    """A line violated the section 3 contract."""


class State(str, Enum):
    IDLE = "idle"
    RUNNING = "running"
    FAULT = "fault"
    HV_ARMED = "hv_armed"


class Fixture(str, Enum):
    NONE = "none"
    MTX = "mtx"
    HV = "hv"


class ContMode(str, Enum):
    VERIFY = "verify"
    DISCOVER = "discover"


class ContStatus(str, Enum):
    PASS = "pass"
    OPEN = "open"
    SHORT = "short"


class ResStatus(str, Enum):
    PASS = "pass"
    FAIL_HIGH = "fail_high"
    FAIL_LOW = "fail_low"


class InsulStatus(str, Enum):
    PASS = "pass"
    FAIL = "fail"


class TestKind(str, Enum):
    CONT = "cont"
    RES = "res"
    INSUL = "insul"


#: Error codes defined by the contract (3.2). Unknown codes are still parsed
#: (the firmware may add some) but callers can check membership here.
ERROR_CODES = frozenset({"EBUSY", "EFIXTURE", "ENOTARMED", "ERANGE", "EHW", "ESYNTAX"})

_UINT_RE = re.compile(r"[0-9]+")
_INT_RE = re.compile(r"-?[0-9]+")
_SEMVER_RE = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")


def _uint(token: str, what: str) -> int:
    if not _UINT_RE.fullmatch(token):
        raise ProtocolError(f"{what}: expected unsigned integer, got {token!r}")
    return int(token)


def _int(token: str, what: str) -> int:
    # The firmware prints measurement values with %ld from int32_t, so a
    # negative reading is a legal wire value for these fields (brief 8.4
    # finding 2). Pins, counts and progress stay unsigned.
    if not _INT_RE.fullmatch(token):
        raise ProtocolError(f"{what}: expected integer, got {token!r}")
    return int(token)


def _enum(enum_cls, token: str, what: str):
    try:
        return enum_cls(token)
    except ValueError:
        raise ProtocolError(f"{what}: unexpected value {token!r}") from None


def _kv(token: str, key: str, what: str) -> str:
    prefix = key + "="
    if not token.startswith(prefix):
        raise ProtocolError(f"{what}: expected field {prefix}<...>, got {token!r}")
    return token[len(prefix):]


def _kv_uint(token: str, key: str, what: str) -> int:
    return _uint(_kv(token, key, what), what)


def _kv_int(token: str, key: str, what: str) -> int:
    return _int(_kv(token, key, what), what)


# ---------------------------------------------------------------------------
# Command encoders (GUI -> instrument). Each returns the full wire line.
# ---------------------------------------------------------------------------


class commands:
    """Byte-exact encoders for every command in section 3.2."""

    @staticmethod
    def _line(body: str) -> bytes:
        return (CMD_PREFIX + body + "\n").encode("ascii")

    @staticmethod
    def ping() -> bytes:
        return commands._line("PING")

    @staticmethod
    def identify() -> bytes:
        return commands._line("ID")

    @staticmethod
    def status() -> bytes:
        return commands._line("STATUS")

    @staticmethod
    def safe() -> bytes:
        return commands._line("SAFE")

    @staticmethod
    def abort() -> bytes:
        return commands._line("ABORT")

    @staticmethod
    def fault_clear() -> bytes:
        # Forces safe, then clears the fault latch. Accepted while faulted,
        # which nothing else is. Deliberate operator action only.
        return commands._line("FAULT CLEAR")

    @staticmethod
    def netlist_begin(n: int) -> bytes:
        return commands._line(f"NETLIST BEGIN {_check_uint(n, 'n')}")

    @staticmethod
    def netlist_add(hi: int, lo: int) -> bytes:
        return commands._line(
            f"NETLIST ADD {_check_pin(hi, 'hi')} {_check_pin(lo, 'lo')}")

    @staticmethod
    def netlist_end() -> bytes:
        return commands._line("NETLIST END")

    @staticmethod
    def netlist_get() -> bytes:
        return commands._line("NETLIST GET")

    @staticmethod
    def cont_run(mode: ContMode) -> bytes:
        return commands._line(f"CONT RUN {_enum(ContMode, mode, 'mode').value}")

    @staticmethod
    def res_run() -> bytes:
        return commands._line("RES RUN")

    @staticmethod
    def insul_arm() -> bytes:
        return commands._line("INSUL ARM")

    @staticmethod
    def insul_run() -> bytes:
        return commands._line("INSUL RUN")

    @staticmethod
    def hv_set(millivolts: int) -> bytes:
        return commands._line(f"HV SET {_check_uint(millivolts, 'millivolts')}")

    @staticmethod
    def fixture(f: Fixture) -> bytes:
        return commands._line(f"FIXTURE {_enum(Fixture, f, 'fixture').value}")

    @staticmethod
    def manual_path(hi: int, lo: int) -> bytes:
        return commands._line(
            f"MANUAL PATH {_check_pin(hi, 'hi')} {_check_pin(lo, 'lo')}")

    @staticmethod
    def manual_relay(board: int, n: int, on: bool) -> bytes:
        # The firmware refuses this outright with ERR EHW (brief section 0).
        # Encoded only so the refusal can be exercised; the GUI must not
        # offer this control to the operator.
        return commands._line(
            f"MANUAL RELAY {_check_uint(board, 'board')} {_check_uint(n, 'n')} {1 if on else 0}"
        )

    @staticmethod
    def manual_off() -> bytes:
        return commands._line("MANUAL OFF")

    @staticmethod
    def cal_get() -> bytes:
        return commands._line("CAL GET")

    @staticmethod
    def limits_get() -> bytes:
        return commands._line("LIMITS GET")

    @staticmethod
    def limits_set(r_max_mohm: int, ins_min_mohm: int) -> bytes:
        return commands._line(
            f"LIMITS SET r_max_mohm={_check_uint(r_max_mohm, 'r_max_mohm')}"
            f" ins_min_mohm={_check_uint(ins_min_mohm, 'ins_min_mohm')}"
        )


def _check_uint(value: int, what: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ProtocolError(f"{what}: expected non-negative int, got {value!r}")
    return value


#: Pins are 1-based, valid range 1..256 (brief 8.1 answer 1). Out of range is
#: ERR ERANGE on the wire; the codec refuses to send it at all.
def _check_pin(value: int, what: str) -> int:
    _check_uint(value, what)
    if not 1 <= value <= 256:
        raise ProtocolError(f"{what}: pin out of range 1..256: {value!r}")
    return value


# ---------------------------------------------------------------------------
# Line framer: bytes in, lines out.
# ---------------------------------------------------------------------------


class LineFramer:
    """Feeds a byte stream, yields complete lines without the trailing \\n.

    A trailing ``\\r`` is stripped defensively: the contract says ``\\n``
    only, and real firmware honours that, but a stray CR from a terminal
    session must not turn every line into a parse error.
    """

    def __init__(self) -> None:
        self._buf = bytearray()

    def feed(self, data: bytes) -> list[str]:
        self._buf += data
        lines: list[str] = []
        while True:
            idx = self._buf.find(NEWLINE)
            if idx < 0:
                break
            raw = bytes(self._buf[:idx])
            del self._buf[: idx + 1]
            if raw.endswith(b"\r"):
                raw = raw[:-1]
            lines.append(raw.decode("ascii", errors="strict"))
        return lines

    @property
    def pending(self) -> bytes:
        return bytes(self._buf)


# ---------------------------------------------------------------------------
# Parsers (instrument -> GUI).
# ---------------------------------------------------------------------------


def parse_line(line: str) -> object:
    """Parse one instrument line (no trailing newline) into a message.

    Raises ProtocolError on anything that does not match section 3 exactly.
    """
    from . import messages as m

    if not line:
        raise ProtocolError("empty line")
    prefix, body = line[0], line[1:]
    if prefix == LOG_PREFIX:
        return m.LogLine(body)
    if prefix not in (REPLY_PREFIX, EVENT_PREFIX):
        raise ProtocolError(f"bad prefix {prefix!r}: {line!r}")
    tokens = body.split(" ")
    if prefix == REPLY_PREFIX:
        return _parse_reply(tokens, line, m)
    return _parse_event(tokens, line, m)


def _parse_reply(tokens: list[str], line: str, m) -> object:
    head = tokens[0]
    if head == "PONG" and len(tokens) == 1:
        return m.Pong()
    if head == "ID" and len(tokens) == 4:
        if tokens[1] != "HT_MK1":
            raise ProtocolError(f"ID: expected HT_MK1, got {tokens[1]!r}")
        fw = _kv(tokens[2], "fw", "ID")
        if not _SEMVER_RE.fullmatch(fw):
            raise ProtocolError(f"ID: bad semver {fw!r}")
        proto = _kv_uint(tokens[3], "proto", "ID")
        return m.IdReply(fw=fw, proto=proto)
    if head == "STATUS" and len(tokens) == 4:
        return m.StatusReply(
            state=_enum(State, _kv(tokens[1], "state", "STATUS"), "STATUS"),
            fixture=_enum(Fixture, _kv(tokens[2], "fixture", "STATUS"), "STATUS"),
            hv_mv=_kv_int(tokens[3], "hv_mv", "STATUS"),
        )
    if head == "OK":
        return m.Ok(detail=" ".join(tokens[1:]))
    if head == "ERR" and len(tokens) >= 2:
        return m.ErrReply(code=tokens[1], text=" ".join(tokens[2:]))
    if head == "NETLIST" and len(tokens) == 2:
        return m.NetlistReply(count=_uint(tokens[1], "NETLIST"))
    if head == "NET" and len(tokens) == 3:
        return m.NetEntry(hi=_uint(tokens[1], "NET hi"), lo=_uint(tokens[2], "NET lo"))
    if head == "CAL" and len(tokens) == 4:
        return m.CalReply(
            current_ua=_kv_uint(tokens[1], "current_ua", "CAL"),
            gain=_kv_uint(tokens[2], "gain", "CAL"),
            rref_mohm=_kv_uint(tokens[3], "rref_mohm", "CAL"),
        )
    if head == "LIMITS" and len(tokens) == 3:
        return m.LimitsReply(
            r_max_mohm=_kv_int(tokens[1], "r_max_mohm", "LIMITS"),
            ins_min_mohm=_kv_int(tokens[2], "ins_min_mohm", "LIMITS"),
        )
    raise ProtocolError(f"unrecognised reply: {line!r}")


def _parse_event(tokens: list[str], line: str, m) -> object:
    head = tokens[0]
    if head == "PROGRESS" and len(tokens) == 3:
        return m.Progress(done=_uint(tokens[1], "PROGRESS done"),
                          total=_uint(tokens[2], "PROGRESS total"))
    if head == "CONT" and len(tokens) == 4:
        return m.ContResult(
            hi=_uint(tokens[1], "CONT hi"),
            lo=_uint(tokens[2], "CONT lo"),
            status=_enum(ContStatus, tokens[3], "CONT status"),
        )
    if head == "RES" and len(tokens) == 5:
        return m.ResResult(
            hi=_uint(tokens[1], "RES hi"),
            lo=_uint(tokens[2], "RES lo"),
            milliohms=_int(tokens[3], "RES milliohms"),
            status=_enum(ResStatus, tokens[4], "RES status"),
        )
    if head == "INSUL" and len(tokens) == 4:
        return m.InsulResult(
            net=_uint(tokens[1], "INSUL net"),
            leak_mohm=_int(tokens[2], "INSUL leak_mohm"),
            status=_enum(InsulStatus, tokens[3], "INSUL status"),
        )
    if head == "FAULT" and len(tokens) >= 3:
        return m.Fault(code=tokens[1], text=" ".join(tokens[2:]))
    if head == "DONE" and len(tokens) == 4:
        return m.Done(
            kind=_enum(TestKind, tokens[1], "DONE kind"),
            passed=_uint(tokens[2], "DONE passed"),
            failed=_uint(tokens[3], "DONE failed"),
        )
    if head == "STATE" and len(tokens) == 2:
        return m.StateEvent(state=_enum(State, tokens[1], "STATE"))
    if head == "FIXTURE" and len(tokens) == 2:
        return m.FixtureEvent(fixture=_enum(Fixture, tokens[1], "FIXTURE"))
    if head == "HV" and len(tokens) == 2:
        return m.HvEvent(millivolts=_int(tokens[1], "HV"))
    if head == "SAFE" and len(tokens) == 1:
        return m.SafeEvent()
    raise ProtocolError(f"unrecognised event: {line!r}")
