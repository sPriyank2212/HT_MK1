"""
GUI Simulator for Harness Tester — tests the GUI without real hardware.

Patches SerialWorker with a mock that streams realistic continuity results
through Qt signals on configurable timing.

Usage
-----
    # Interactive — click Connect then Start manually
    python tools/gui_sim.py

    # Fully automatic — drives the GUI without any clicks
    python tools/gui_sim.py --auto

    # All pass, fast
    python tools/gui_sim.py --auto --all-pass --delay-ms 10

    # Specific failures
    python tools/gui_sim.py --auto --fail-pins 5,23,37

Options
-------
    --fail-rate   FLOAT   Fraction of continuity pairs that fail  (default 0.08)
    --fail-pins   LIST    Comma-separated Side-A pin numbers to force-fail continuity
    --miswire-pins LIST   Comma-separated Side-A pin numbers to force unexpected connections
    --delay-ms    INT     Milliseconds between streamed results    (default 40)
    --all-pass            Force every result to PASS (overrides rates and pins)
    --auto                Automatically connect, load netlist, and start test
"""

from __future__ import annotations
import argparse
import os
import random
import sys

# Add project root to path so all modules resolve
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from PyQt6.QtCore import QObject, QTimer, pyqtSignal

from core.data_types import (
    Cmd,
    ContResult,
    FirmwareStatus, ScanSummary,
    ResultStatus,
)

# ---------------------------------------------------------------------------
# Simulated harness layout
# ---------------------------------------------------------------------------

def _cont_pairs() -> list[tuple[int, int]]:
    """37 straight pairs: pin N on Side A wired to pin N on Side B."""
    return [(i, i) for i in range(1, 38)]


# ---------------------------------------------------------------------------
# MockSerialWorker
# ---------------------------------------------------------------------------

class MockSerialWorker(QObject):
    """Drop-in replacement for SerialWorker — emits signals via QTimer, no serial port needed."""

    # Exact same signal set as SerialWorker
    statusReceived      = pyqtSignal(object)
    contResultReceived  = pyqtSignal(object)
    scanComplete        = pyqtSignal(object)
    progressUpdate      = pyqtSignal(int, int)
    ackReceived         = pyqtSignal(bytes)
    nackReceived        = pyqtSignal(int)
    connectionLost      = pyqtSignal()
    rawPacketLogged     = pyqtSignal(str, str)

    def __init__(self, port: str, baud: int, *,
                 fail_rate: float = 0.08,
                 forced_fail_pins: set[int] | None = None,
                 forced_miswire_pins: set[int] | None = None,
                 delay_ms: int = 40,
                 cont_pairs: list[tuple[int, int]] | None = None,
                 parent=None):
        super().__init__(parent)
        self._port        = port
        self._baud        = baud
        self._fail_rate   = fail_rate
        self._forced_fail = forced_fail_pins or set()
        self._forced_miswire = forced_miswire_pins or set()
        self._delay_ms    = delay_ms

        self._cont_pairs  = cont_pairs if cont_pairs is not None else _cont_pairs()
        self._auto_pairs: list[tuple[int, int]] = []
        self._idx         = 0
        self._phase       = "idle"   # "cont" | "auto" | "done"

        self._timer = QTimer(self)
        self._timer.timeout.connect(self._tick)

    # ------------------------------------------------------------------
    # QThread-compatible interface (called by MainWindow)
    # ------------------------------------------------------------------

    def start(self) -> None:
        self.rawPacketLogged.emit("INFO",
            f"[SIM] Mock worker started — port={self._port}  baud={self._baud}")
        QTimer.singleShot(400, self._emit_status)

    def stop(self) -> None:
        self._timer.stop()

    def wait(self, _ms: int = 3000) -> bool:
        return True

    def send_packet(self, cmd: int, payload: bytes = b"") -> None:  # noqa: ARG002
        if cmd == Cmd.GET_STATUS:
            QTimer.singleShot(100, self._emit_status)

        elif cmd in (Cmd.SET_PARAM, Cmd.SET_NETLIST):
            QTimer.singleShot(20, lambda: self.ackReceived.emit(b"\x00\x00"))

        elif cmd == Cmd.CALIBRATE:
            # ACK with 2-byte calibration offset = 30 mΩ
            QTimer.singleShot(600, lambda: self.ackReceived.emit(b"\x00\x1e"))
            self.rawPacketLogged.emit("INFO", "[SIM] Calibration running…")

        elif cmd == Cmd.START_CONT:
            self.rawPacketLogged.emit("INFO",
                f"[SIM] Starting continuity scan  ({len(self._cont_pairs)} pairs)")
            self._phase = "cont"
            self._idx   = 0
            self._timer.start(self._delay_ms)

        elif cmd == Cmd.START_CROSS_CONT:
            self.rawPacketLogged.emit("INFO",
                f"[SIM] Starting cross-continuity scan  ({len(self._cont_pairs)} expected pairs)")
            self._phase = "cross"
            self._idx   = 0
            self._cc_total = 0
            self._cc_passed = 0
            self._cc_failed = 0
            self._timer.start(self._delay_ms)

        elif cmd == Cmd.AUTO_SCAN:
            # Discovery scan — only emit PASS results for physically-connected pairs (1-37)
            discovered = [(a, b) for a, b in self._cont_pairs if 1 <= a <= 37 and 1 <= b <= 37]
            if not discovered:
                discovered = [(1, 1), (3, 3), (5, 5)]   # fallback: 3 demo connections
            self._auto_pairs = discovered
            self._phase = "auto"
            self._idx   = 0
            self.rawPacketLogged.emit("INFO",
                f"[SIM] AUTO_SCAN — discovering {len(discovered)} connection(s) in 37×37 matrix")
            self._timer.start(self._delay_ms)

        elif cmd == Cmd.ABORT:
            self._timer.stop()
            self._phase = "idle"
            self.rawPacketLogged.emit("INFO", "[SIM] Scan aborted")

    # ------------------------------------------------------------------
    # Result streaming
    # ------------------------------------------------------------------

    def _emit_status(self) -> None:
        self.statusReceived.emit(
            FirmwareStatus(state=0, flags=0, fw_version="1.0.0", cal_offset_mohm=30)
        )
        self.rawPacketLogged.emit("INFO",
            "[SIM] FW v1.0.0  cal_offset=30 mΩ  (simulated)")

    def _tick(self) -> None:
        if self._phase == "cont":
            self._stream_cont()
        elif self._phase == "cross":
            self._stream_cross_cont()
        elif self._phase == "auto":
            self._stream_auto()

    def _stream_cont(self) -> None:
        pairs = self._cont_pairs

        if self._idx >= len(pairs):
            self._timer.stop()
            self._phase = "done"
            self.scanComplete.emit(ScanSummary(total=len(pairs), pass_count=0, fail_count=0))
            self.rawPacketLogged.emit("INFO",
                f"[SIM] Scan complete — {len(pairs)} pairs tested")
            return

        pin_a, pin_b = pairs[self._idx]
        is_fail = (pin_a in self._forced_fail) or (random.random() < self._fail_rate)

        if is_fail:
            result = ContResult(pin_a, pin_b, 0.0, ResultStatus.FAIL)
        else:
            result = ContResult(pin_a, pin_b,
                                round(random.uniform(12.0, 460.0), 1),
                                ResultStatus.PASS)
        self.contResultReceived.emit(result)

        done = self._idx + 1
        if done % 16 == 0 or done == len(pairs):
            self.progressUpdate.emit(done, len(pairs))

        self._idx += 1

    def _stream_cross_cont(self) -> None:
        """Cross-continuity: one Side-A pin to all Side-B pins."""
        expected = set(self._cont_pairs)
        max_idx = 37 * 37

        if self._idx >= max_idx:
            self._timer.stop()
            self._phase = "done"
            self.scanComplete.emit(ScanSummary(
                total=self._cc_total,
                pass_count=self._cc_passed,
                fail_count=self._cc_failed,
            ))
            self.rawPacketLogged.emit("INFO", "[SIM] Cross-continuity scan complete")
            return

        a = (self._idx // 37) + 1
        b = (self._idx % 37) + 1
        self._idx += 1

        is_expected = (a, b) in expected
        is_open = is_expected and (a in self._forced_fail)
        is_miswire = (not is_expected) and (a in self._forced_miswire)

        if is_expected and not is_open:
            result = ContResult(a, b,
                                round(random.uniform(12.0, 460.0), 1),
                                ResultStatus.PASS)
            self.contResultReceived.emit(result)
            self._cc_passed += 1
        elif is_open:
            result = ContResult(a, b, 0.0, ResultStatus.OPEN)
            self.contResultReceived.emit(result)
            self._cc_failed += 1
        elif is_miswire:
            result = ContResult(a, b,
                                round(random.uniform(12.0, 460.0), 1),
                                ResultStatus.MISWIRE)
            self.contResultReceived.emit(result)
            self._cc_failed += 1
        else:
            # No connection expected and none found — report so GUI shows full matrix
            result = ContResult(a, b, 0.0, ResultStatus.NOT_CONNECTED)
            self.contResultReceived.emit(result)

        self._cc_total += 1

        done = self._idx
        if done % 37 == 0 or done == max_idx:
            self.progressUpdate.emit(done // 37, 37)

    def _stream_auto(self) -> None:
        """AUTO_SCAN: emit only PASS results for discovered (connected) pairs."""
        if self._idx >= len(self._auto_pairs):
            self._timer.stop()
            self._phase = "done"
            n = len(self._auto_pairs)
            self.scanComplete.emit(ScanSummary(total=n, pass_count=n, fail_count=0))
            self.rawPacketLogged.emit("INFO",
                f"[SIM] AUTO_SCAN complete — {n} connection(s) discovered")
            return

        pin_a, pin_b = self._auto_pairs[self._idx]
        result = ContResult(pin_a, pin_b,
                            round(random.uniform(12.0, 200.0), 1),
                            ResultStatus.PASS)
        self.contResultReceived.emit(result)
        self.progressUpdate.emit(self._idx + 1, len(self._auto_pairs))
        self._idx += 1


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def _parse_pin_list(s: str) -> set[int]:
    return {int(x.strip()) for x in s.split(",") if x.strip()}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Harness Tester GUI Simulator — no hardware required",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--fail-rate",  type=float, default=0.08,
                        metavar="FLOAT", help="Continuity fail rate 0–1  (default 0.08)")
    parser.add_argument("--fail-pins",  type=str,   default="",
                        metavar="LIST",  help="Force-fail Side-A pins, e.g. 5,23,37")
    parser.add_argument("--miswire-pins", type=str, default="",
                        metavar="LIST",  help="Force miswire Side-A pins, e.g. 7,12")
    parser.add_argument("--delay-ms",   type=int,   default=40,
                        metavar="INT",   help="ms between results  (default 40)")
    parser.add_argument("--all-pass",   action="store_true",
                        help="Force every result to PASS")
    parser.add_argument("--auto",       action="store_true",
                        help="Auto-connect, load netlist, and start test without user input")
    parser.add_argument("--netlist",    type=str,   default="",
                        metavar="PATH", help="Netlist JSON to auto-load (default: sample.json)")
    args = parser.parse_args()

    fail_rate  = 0.0 if args.all_pass else args.fail_rate
    fail_pins  = set() if args.all_pass else _parse_pin_list(args.fail_pins)
    miswire_pins = set() if args.all_pass else _parse_pin_list(args.miswire_pins)

    # ----------------------------------------------------------------
    # Pre-load netlist pairs so MockSerialWorker streams matching pairs
    # ----------------------------------------------------------------
    sim_cont_pairs: list[tuple[int, int]] | None = None

    netlist_path = os.path.normpath(args.netlist) if args.netlist else ""
    if netlist_path and os.path.isfile(netlist_path):
        try:
            from core.netlist import load_netlist
            _nl = load_netlist(netlist_path)
            sim_cont_pairs = []
            for _net in _nl.nets:
                _nums = sorted(p.number for p in _net.pins)
                _pairs = [(_nums[i], _nums[j])
                          for i in range(len(_nums))
                          for j in range(i + 1, len(_nums))]
                sim_cont_pairs.extend(_pairs)
        except Exception as _exc:
            print(f"[SIM] Warning: could not pre-load netlist pairs: {_exc}")

    # ----------------------------------------------------------------
    # Patch SerialWorker BEFORE importing main_window
    # ----------------------------------------------------------------
    import core.serial_comm as _comm

    def _worker_factory(port: str, baud: int, parent=None) -> MockSerialWorker:
        return MockSerialWorker(
            port, baud,
            fail_rate=fail_rate,
            forced_fail_pins=fail_pins,
            forced_miswire_pins=miswire_pins,
            delay_ms=args.delay_ms,
            cont_pairs=sim_cont_pairs,
            parent=parent,
        )

    _comm.SerialWorker = _worker_factory  # type: ignore[assignment]

    # ----------------------------------------------------------------
    # Launch app
    # ----------------------------------------------------------------
    from PyQt6.QtWidgets import QApplication
    app = QApplication(sys.argv)

    from ui.main_window import MainWindow
    win = MainWindow()
    win.setWindowTitle("Harness Tester v0.1.0  —  [SIMULATOR MODE]")
    win.show()

    # Simulator banner in log
    log = win._log_panel
    log.append_line("WARN", "━" * 60)
    log.append_line("WARN",  "[SIM] SIMULATOR MODE — no hardware required")
    log.append_line("INFO",
        f"[SIM] fail_rate={fail_rate*100:.0f}%  delay={args.delay_ms} ms")
    if fail_pins:
        log.append_line("INFO", f"[SIM] Force-fail cont pins: {sorted(fail_pins)}")
    if args.auto:
        log.append_line("INFO", "[SIM] Auto mode — connecting and starting in 1.5 s…")
    else:
        log.append_line("INFO",
            "[SIM] Select any port, click Connect, load a netlist, then Start Test")
    log.append_line("WARN", "━" * 60)

    # ----------------------------------------------------------------
    # Auto mode — drive the GUI programmatically
    # ----------------------------------------------------------------
    if args.auto:
        if args.netlist:
            sample_netlist = os.path.normpath(args.netlist)
        else:
            sample_netlist = os.path.normpath(
                os.path.join(os.path.dirname(__file__), "..", "netlists", "sample.json")
            )

        def _auto_connect() -> None:
            log.append_line("INFO", "[SIM][AUTO] Connecting on virtual port SIM…")
            win._on_connect_requested("SIM", 115200)

        def _auto_start() -> None:
            if not win._connected:
                log.append_line("WARN", "[SIM][AUTO] Not connected yet, retrying…")
                QTimer.singleShot(500, _auto_start)
                return
            log.append_line("INFO", f"[SIM][AUTO] Loading netlist: {os.path.basename(sample_netlist)}")
            win._on_netlist_browsed(sample_netlist)
            QTimer.singleShot(300, win._on_start_requested)

        QTimer.singleShot(1500, _auto_connect)
        QTimer.singleShot(2800, _auto_start)   # status arrives ~400ms after connect

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
