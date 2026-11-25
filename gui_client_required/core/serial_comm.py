"""SerialWorker — QThread that owns the serial port and the packet decoder.

All incoming packets are parsed and emitted as typed Qt signals so the GUI
(main thread) never touches the serial port directly.
"""

from __future__ import annotations
import queue
import struct
import time

from PyQt6.QtCore import QThread, pyqtSignal

from .packet_codec import encode_packet, PacketDecoder
from .data_types import (
    Cmd, Rsp,
    FirmwareStatus, ContResult,
    ScanSummary, ResultStatus,
)

HEARTBEAT_INTERVAL_S = 2.0
MISSED_ACK_LIMIT = 3
READ_TIMEOUT_S = 0.1


class SerialWorker(QThread):
    # --- signals emitted on the main thread ---
    statusReceived      = pyqtSignal(object)   # FirmwareStatus
    contResultReceived  = pyqtSignal(object)   # ContResult
    scanComplete        = pyqtSignal(object)   # ScanSummary
    progressUpdate      = pyqtSignal(int, int) # done, total
    ackReceived         = pyqtSignal(bytes)    # RSP_ACK payload (used by TestEngine)
    nackReceived        = pyqtSignal(int)      # RSP_NACK — last command rejected; arg = cmd byte that was sent (0 if unknown)
    faultReceived       = pyqtSignal(int, int) # RSP_FAULT — (code, data)
    connectionLost      = pyqtSignal()
    rawPacketLogged     = pyqtSignal(str, str) # direction ("TX"/"RX"), hex string

    def __init__(self, port: str, baud: int, parent=None, opener=None):
        super().__init__(parent)
        self._port = port
        self._baud = baud
        # opener(port, baud, timeout=...) returns a serial-like object; None
        # means a real port.  The demo build passes a simulated tester here.
        self._opener = opener
        self._tx_queue: queue.Queue[bytes] = queue.Queue()
        self._stop_flag = False
        self._missed_acks = 0
        self._waiting_ack = False
        self._last_cmd = 0          # tracks most-recently sent command for NACK attribution
        self._decoder = PacketDecoder(
            on_packet=self._on_packet,
            on_crc_error=self._on_crc_error,
        )

    # ------------------------------------------------------------------
    # Public API (called from main thread — thread-safe via queue)
    # ------------------------------------------------------------------

    def send_packet(self, cmd: int, payload: bytes = b"") -> None:
        self._last_cmd = cmd
        frame = encode_packet(cmd, payload)
        self._tx_queue.put(frame)

    def stop(self) -> None:
        self._stop_flag = True

    # ------------------------------------------------------------------
    # QThread.run — executes on worker thread
    # ------------------------------------------------------------------

    def run(self) -> None:
        import serial  # imported here so the module loads without pyserial on path

        try:
            open_port = self._opener or serial.Serial
            ser = open_port(self._port, self._baud, timeout=READ_TIMEOUT_S)
        except serial.SerialException as exc:
            self.rawPacketLogged.emit("ERROR", f"Cannot open {self._port}: {exc}")
            self.connectionLost.emit()
            return

        last_heartbeat = time.monotonic()
        self.rawPacketLogged.emit("INFO", f"Opened {self._port} @ {self._baud}")

        # Brief settle delay — lets the ST-Link VCP stabilise after port open
        time.sleep(0.05)

        # Request firmware status immediately
        self.send_packet(Cmd.GET_STATUS)

        while not self._stop_flag:
            # --- TX ---
            while not self._tx_queue.empty():
                try:
                    frame = self._tx_queue.get_nowait()
                    ser.write(frame)
                    self.rawPacketLogged.emit("TX", frame.hex(" ").upper())
                except queue.Empty:
                    break
                except serial.SerialException:
                    self._handle_disconnect()
                    ser.close()
                    return

            # --- RX ---
            try:
                waiting = ser.in_waiting
                if waiting:
                    data = ser.read(waiting)
                    self.rawPacketLogged.emit("RX", data.hex(" ").upper())
                    self._decoder.feed(data)
            except serial.SerialException:
                self._handle_disconnect()
                ser.close()
                return

            # --- Heartbeat (real elapsed time, not loop-count proxy) ---
            now = time.monotonic()
            if (now - last_heartbeat) >= HEARTBEAT_INTERVAL_S:
                last_heartbeat = now
                if not self._waiting_ack:
                    self._waiting_ack = True
                    self.send_packet(Cmd.PING)
                else:
                    self._missed_acks += 1
                    if self._missed_acks >= MISSED_ACK_LIMIT:
                        self._handle_disconnect()
                        ser.close()
                        return

            # Throttle loop — prevents 100% CPU spin and gives OS time to
            # deliver incoming bytes before the next in_waiting check.
            time.sleep(0.010)

        ser.close()

    # ------------------------------------------------------------------
    # Packet handler (called on worker thread — emits signals to main thread)
    # ------------------------------------------------------------------

    def _on_packet(self, cmd: int, payload: bytes) -> None:
        if cmd == Rsp.ACK:
            self._waiting_ack = False
            self._missed_acks = 0
            self.ackReceived.emit(payload)

        elif cmd == Rsp.NACK:
            self.rawPacketLogged.emit("WARN", f"NACK — firmware rejected cmd 0x{self._last_cmd:02X}")
            self.nackReceived.emit(self._last_cmd)

        elif cmd == Rsp.STATUS and len(payload) >= 8:
            state, flags = struct.unpack_from(">BB", payload, 0)
            major, minor, patch = struct.unpack_from(">BBB", payload, 2)
            cal_offset = struct.unpack_from(">H", payload, 5)[0]
            fw_ver = f"{major}.{minor}.{patch}"
            self.statusReceived.emit(FirmwareStatus(state, flags, fw_ver, cal_offset))

        elif cmd == Rsp.RESULT_CONT and len(payload) >= 6:
            pin_a, pin_b = struct.unpack_from(">BB", payload, 0)
            res_raw = struct.unpack_from(">I", payload, 2)[0]
            status_byte = payload[6] if len(payload) > 6 else 0
            res_mohm = res_raw / 10.0
            if status_byte == 0:
                status = ResultStatus.PASS
            elif status_byte == 2:
                status = ResultStatus.MISWIRE
            elif status_byte == 3:
                status = ResultStatus.NOT_CONNECTED
            elif status_byte == 1 or res_mohm >= 10_000.0:  # ≥10 Ω sentinel — open circuit, not a real resistance failure
                status = ResultStatus.OPEN
            else:
                status = ResultStatus.FAIL
            self.contResultReceived.emit(ContResult(pin_a, pin_b, res_mohm, status))

        elif cmd == Rsp.SCAN_DONE and len(payload) >= 6:
            total, passed, failed = struct.unpack_from(">HHH", payload, 0)
            self.scanComplete.emit(ScanSummary(total, passed, failed))

        elif cmd == Rsp.FAULT and len(payload) >= 5:
            code = payload[0]
            data = struct.unpack_from(">I", payload, 1)[0]
            self.faultReceived.emit(code, data)

        elif cmd == Rsp.PROGRESS and len(payload) >= 4:
            done, total = struct.unpack_from(">HH", payload, 0)
            self.progressUpdate.emit(done, total)

    def _on_crc_error(self, cmd: int, payload: bytes) -> None:
        self.rawPacketLogged.emit("ERROR", f"CRC error on response cmd=0x{cmd:02X}")

    def _handle_disconnect(self) -> None:
        # MainWindow._on_connection_lost does the logging — it knows whether
        # the port ever validated and can give a more useful message.
        self.connectionLost.emit()
