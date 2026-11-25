"""Shared dataclasses and enums used across core and UI modules."""

from dataclasses import dataclass, field
from enum import IntEnum, auto
from datetime import datetime


# ---------------------------------------------------------------------------
# Protocol command / response IDs
# ---------------------------------------------------------------------------

class Cmd(IntEnum):
    PING            = 0x01
    GET_STATUS      = 0x02
    SET_NETLIST     = 0x03
    SET_PARAM       = 0x04
    START_CONT       = 0x05
    ABORT            = 0x08
    CALIBRATE        = 0x09
    GET_RESULT       = 0x0A
    AUTO_SCAN        = 0x0B
    START_CROSS_CONT = 0x0C


class Rsp(IntEnum):
    ACK             = 0x81
    NACK            = 0x82
    STATUS          = 0x83
    RESULT_CONT     = 0x84
    RESULT_SHORT    = 0x85
    RESULT_HV       = 0x86
    SCAN_DONE       = 0x87
    PROGRESS        = 0x88
    FAULT           = 0x89


# ---------------------------------------------------------------------------
# Test state machine
# ---------------------------------------------------------------------------

class TestState(IntEnum):
    IDLE        = auto()
    UPLOADING   = auto()
    CALIBRATING = auto()
    SCANNING    = auto()
    COMPLETE    = auto()


class Verdict(IntEnum):
    NONE         = auto()
    PASS         = auto()
    FAIL         = auto()
    INCONCLUSIVE = auto()


# ---------------------------------------------------------------------------
# Result types
# ---------------------------------------------------------------------------

class TestType(IntEnum):
    CONTINUITY  = auto()


class ResultStatus(IntEnum):
    PASS         = auto()
    FAIL         = auto()
    OPEN         = auto()
    MISWIRE      = auto()
    NOT_CONNECTED = auto()


@dataclass
class TestResult:
    test_num: int
    pin_a: int
    pin_b: int
    test_type: TestType
    status: ResultStatus
    resistance_mohm: float = 0.0
    ir_mohm: float = 0.0
    net_name: str = ""
    pin_a_name: str = ""
    pin_b_name: str = ""
    connector_id: str = ""
    connector_id_b: str = ""
    connector_detail: str = ""
    connector_part_number: str = ""
    connector_part_number_b: str = ""
    source: str = ""
    destination: str = ""
    wire_colour: str = ""
    awg: str = ""
    length: str = ""
    harness_no: str = ""
    timestamp: datetime = field(default_factory=datetime.now)
    # Optional display-time local pin numbers (per-connector numbering)
    display_pin_a: int = 0
    display_pin_b: int = 0


@dataclass
class ContResult:
    pin_a: int
    pin_b: int
    resistance_mohm: float
    status: ResultStatus


@dataclass
class ScanSummary:
    total: int
    pass_count: int
    fail_count: int


@dataclass
class FirmwareStatus:
    state: int
    flags: int
    fw_version: str
    cal_offset_mohm: int


@dataclass
class TestModes:
    continuity:       bool  = True
    cross_continuity: bool  = False
    r_limit_mohm:     float = 500.0
    ir_limit_mohm:    float = 100.0
