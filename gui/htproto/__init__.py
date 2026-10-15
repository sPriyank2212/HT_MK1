"""HT_MK1 GUI-side protocol library (brief section 3).

Transport-agnostic: encodes commands to bytes and parses instrument lines.
The connection manager (task 2) owns sockets/serial; this package owns the
wire format, byte-for-byte per the contract.
"""

from .codec import (
    ContMode,
    ContStatus,
    Fixture,
    InsulStatus,
    ProtocolError,
    ResStatus,
    State,
    TestKind,
    commands,
    parse_line,
    LineFramer,
)
from .connection import (
    CommandTimeoutError,
    ConnectionManager,
    LinkLostError,
    LinkState,
    NotConnectedError,
)
from .messages import (
    CalReply,
    ContResult,
    Done,
    ErrReply,
    Fault,
    FixtureEvent,
    HvEvent,
    IdReply,
    InsulResult,
    LimitsReply,
    LogLine,
    NetEntry,
    NetlistReply,
    Ok,
    Pong,
    Progress,
    ResResult,
    SafeEvent,
    StateEvent,
    StatusReply,
)

__all__ = [
    "ContMode", "ContStatus", "Fixture", "InsulStatus", "ProtocolError",
    "ResStatus", "State", "TestKind", "commands", "parse_line", "LineFramer",
    "CommandTimeoutError", "ConnectionManager", "LinkLostError", "LinkState",
    "NotConnectedError",
    "CalReply", "ContResult", "Done", "ErrReply", "Fault", "FixtureEvent",
    "HvEvent", "IdReply", "InsulResult", "LimitsReply", "LogLine", "NetEntry",
    "NetlistReply", "Ok", "Pong", "Progress", "ResResult", "SafeEvent",
    "StateEvent", "StatusReply",
]
