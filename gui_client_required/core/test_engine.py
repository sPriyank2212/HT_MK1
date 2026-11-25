"""TestEngine — orchestrates the test sequence and manages the state machine.

Lives on the main thread.  All serial I/O is delegated to SerialWorker via
send_packet(); all incoming data arrives as Qt signals (queued connections).
"""

from __future__ import annotations
import struct

from PyQt6.QtCore import QObject, QTimer, pyqtSignal

from .data_types import (
    Cmd, TestState, Verdict, TestModes,
    ContResult, ScanSummary,
    ResultStatus,
)

HARNESS_PINS = 37  # must match firmware HARNESS_PINS


class TestEngine(QObject):
    stateChanged        = pyqtSignal(object)  # TestState
    verdictReady        = pyqtSignal(object)  # Verdict
    calibrationComplete = pyqtSignal(int)     # cal_offset_mohm
    autoTestComplete    = pyqtSignal()

    def __init__(self, worker, parent=None):
        super().__init__(parent)
        self._worker = worker
        self._state  = TestState.IDLE
        self._modes  = TestModes()

        # Upload bookkeeping
        self._upload_chunks: list[bytes] = []
        self._upload_index  = 0
        self._upload_timer  = QTimer(self)
        self._upload_timer.setSingleShot(True)
        self._upload_timer.timeout.connect(self._start_scanning)

        # Result counters (for verdict)
        self._pass_count = 0
        self._fail_count = 0

        # Auto-test state
        self._is_auto  = False

        # Wire incoming worker signals
        worker.ackReceived.connect(self._on_ack)
        worker.nackReceived.connect(self._on_nack)
        worker.scanComplete.connect(self._on_scan_complete)
        worker.connectionLost.connect(self._on_connection_lost)

    # ------------------------------------------------------------------
    # Public read
    # ------------------------------------------------------------------

    @property
    def state(self) -> TestState:
        return self._state

    # ------------------------------------------------------------------
    # Public commands
    # ------------------------------------------------------------------

    def start_test(self, netlist_path: str, modes: TestModes, netlist=None) -> None:
        """netlist is the loaded Netlist with its connector pins already turned
        into channels; it is what gets uploaded.  Without it the file at
        netlist_path is read as it stands (its numbers are taken as channels)."""
        if self._state not in (TestState.IDLE, TestState.COMPLETE):
            return
        self._is_auto    = False
        self._modes      = modes
        self._pass_count = 0
        self._fail_count = 0

        self._send_params()

        if netlist is not None:
            from .netlist import netlist_to_bytes
            self._begin_upload_bytes(netlist_to_bytes(netlist))
        elif netlist_path:
            self._begin_upload(netlist_path)
        else:
            self._start_scanning()

    def start_auto_test(self, modes: TestModes) -> None:
        """Auto-discover connections: single CMD_AUTO_SCAN covers all 37×37 pairs."""
        if self._state not in (TestState.IDLE, TestState.COMPLETE):
            return
        self._is_auto    = True
        self._modes      = modes
        self._pass_count = 0
        self._fail_count = 0
        self._send_params()
        self._set_state(TestState.SCANNING)
        self._worker.send_packet(Cmd.AUTO_SCAN)

    def fallback_auto_test(self) -> None:
        """Called when CMD_AUTO_SCAN is rejected — re-run in auto mode using CMD_START_CONT."""
        if self._state != TestState.IDLE:
            return
        self._is_auto = True
        self._set_state(TestState.SCANNING)
        self._worker.send_packet(Cmd.START_CONT)

    def abort(self) -> None:
        self._upload_timer.stop()
        self._worker.send_packet(Cmd.ABORT)
        self._set_state(TestState.IDLE)

    def calibrate(self) -> None:
        if self._state != TestState.IDLE:
            return
        self._set_state(TestState.CALIBRATING)
        self._worker.send_packet(Cmd.CALIBRATE)

    def count_result(self, status: ResultStatus) -> None:
        """Called by MainWindow for each incoming result (keeps verdict accurate)."""
        if status == ResultStatus.PASS:
            self._pass_count += 1
        elif status != ResultStatus.NOT_CONNECTED:
            self._fail_count += 1

    # ------------------------------------------------------------------
    # Private — state helpers
    # ------------------------------------------------------------------

    def _set_state(self, state: TestState) -> None:
        self._state = state
        self.stateChanged.emit(state)

    # ------------------------------------------------------------------
    # Private — upload
    # ------------------------------------------------------------------

    def _send_params(self) -> None:
        payload = struct.pack(
            ">HH",
            int(self._modes.r_limit_mohm),
            int(self._modes.ir_limit_mohm),
        )
        self._worker.send_packet(Cmd.SET_PARAM, payload)

    def _begin_upload(self, path: str) -> None:
        try:
            from .netlist import load_netlist, netlist_to_bytes
            data = netlist_to_bytes(load_netlist(path))
        except (OSError, ValueError):
            self._start_scanning()
            return
        self._begin_upload_bytes(data)

    def _begin_upload_bytes(self, data: bytes) -> None:
        chunk_size = 250
        chunks = [data[i:i+chunk_size] for i in range(0, max(len(data), 1), chunk_size)]
        self._set_state(TestState.UPLOADING)
        total = len(chunks)
        for seq, chunk in enumerate(chunks):
            payload = struct.pack(">HH", seq, total) + chunk
            self._worker.send_packet(Cmd.SET_NETLIST, payload)
        self._upload_timer.start(max(200, 50 * total))

    # ------------------------------------------------------------------
    # Private — scan
    # ------------------------------------------------------------------

    def _start_scanning(self) -> None:
        self._set_state(TestState.SCANNING)
        if self._modes.cross_continuity:
            self._worker.send_packet(Cmd.START_CROSS_CONT)
        elif self._modes.continuity:
            self._worker.send_packet(Cmd.START_CONT)
        else:
            self._finalise(0, 0)

    # ------------------------------------------------------------------
    # Private — incoming signal handlers
    # ------------------------------------------------------------------

    def _on_ack(self, payload: bytes) -> None:
        if self._state == TestState.CALIBRATING:
            offset = struct.unpack_from(">H", payload, 0)[0] if len(payload) >= 2 else 0
            self.calibrationComplete.emit(offset)
            self._set_state(TestState.IDLE)

    def _on_scan_complete(self, summary: ScanSummary) -> None:
        if self._state != TestState.SCANNING:
            return
        if self._is_auto:
            self._is_auto = False
            self._set_state(TestState.COMPLETE)
            self.autoTestComplete.emit()
            self.verdictReady.emit(Verdict.PASS)
            return
        passed = self._pass_count if (self._pass_count + self._fail_count) > 0 else summary.pass_count
        failed = self._fail_count if (self._pass_count + self._fail_count) > 0 else summary.fail_count
        self._finalise(passed, failed)

    def _finalise(self, passed: int, failed: int) -> None:
        verdict = Verdict.PASS if failed == 0 else Verdict.FAIL
        self._set_state(TestState.COMPLETE)
        self.verdictReady.emit(verdict)

    def _on_nack(self, _rejected_cmd: int) -> None:
        """Firmware rejected a command — abort any active scan so the engine doesn't hang."""
        if self._state in (TestState.SCANNING, TestState.UPLOADING):
            self._upload_timer.stop()
            self._is_auto = False
            self._set_state(TestState.IDLE)

    def _on_connection_lost(self) -> None:
        self._upload_timer.stop()
        self._set_state(TestState.IDLE)
