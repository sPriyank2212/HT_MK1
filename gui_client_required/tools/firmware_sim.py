"""
Harness Tester — Firmware Simulator

Simulates the STM32F303ZE firmware over a real serial port so the PC GUI
can be tested end-to-end without hardware. Uses the exact UART protocol:
SOF 0xAA / LEN / CMD / PAYLOAD / CRC-16.

Requirements
    pip install pyserial

Setup — virtual serial port pair
    Windows (com0com):  create a pair e.g. COM10 <-> COM11
        python tools/firmware_sim.py --port COM10
        GUI connects to COM11

    Linux (socat):
        socat -d -d pty,raw,echo=0 pty,raw,echo=0
        python tools/firmware_sim.py --port /dev/pts/2
        GUI connects to /dev/pts/3

Options
    --port          PORT    Serial port to listen on           (required)
    --baud          INT     Baud rate                          (default 115200)
    --netlist       PATH    JSON netlist to preload (skips SET_NETLIST from GUI)
    --fail-rate     FLOAT   Continuity fail rate 0-1           (default 0.06)
    --fail-pins     LIST    Force-fail continuity, e.g. 5,23,37
    --miswire-pins  LIST    Force unexpected connections, e.g. 7,12
    --interval-ms   INT     Milliseconds between result packets (default 30)
    --all-pass             Force every result to PASS
    --no-color             Disable ANSI colour output
"""

from __future__ import annotations

import argparse
import json
import os
import random
import struct
import sys
import threading
import time
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import serial
from core.crc16 import crc16_ccitt_false  # noqa: F401 — kept for dep-check parity with SerialWorker
from core.data_types import Cmd, Rsp
from core.packet_codec import PacketDecoder, encode_packet

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SIM_FW_VERSION  = (1, 0, 0)
SIM_CAL_OFFSET  = 120          # mΩ×10 sent in STATUS response

# Default demo pairs used when no netlist is loaded (37 straight pairs)
_DEFAULT_CONT_PAIRS: list[tuple[int, int]] = [(i, i) for i in range(1, 38)]

# ---------------------------------------------------------------------------
# ANSI colour helpers
# ---------------------------------------------------------------------------

_USE_COLOR = True

def _c(code: str, text: str) -> str:
    if not _USE_COLOR:
        return text
    return f"\033[{code}m{text}\033[0m"

def _green(t: str)    -> str: return _c("32", t)
def _red(t: str)      -> str: return _c("31", t)
def _yellow(t: str)   -> str: return _c("33", t)
def _cyan(t: str)     -> str: return _c("36", t)
def _blue(t: str)     -> str: return _c("34", t)
def _bold(t: str)     -> str: return _c("1",  t)
def _grey(t: str)     -> str: return _c("90", t)

def _ts() -> str:
    return _grey(datetime.now().strftime("%H:%M:%S.%f")[:-3])

def _log(tag: str, msg: str) -> None:
    print(f"{_ts()} {tag} {msg}", flush=True)

# ---------------------------------------------------------------------------
# Packet helpers (mirror of GUI's packet_codec but for the firmware side)
# ---------------------------------------------------------------------------

def _make(cmd: int, payload: bytes = b"") -> bytes:
    return encode_packet(cmd, payload)

def _make_ack(payload: bytes = b"") -> bytes:
    return _make(Rsp.ACK, payload)

def _make_status(state: int = 0) -> bytes:
    maj, min_, pat = SIM_FW_VERSION
    return _make(Rsp.STATUS,
                 struct.pack(">BBBBBH", state, 0x00, maj, min_, pat, SIM_CAL_OFFSET))

def _make_cont(pin_a: int, pin_b: int, res_raw: int, fail: bool) -> bytes:
    status = 0x01 if fail else 0x00
    return _make(Rsp.RESULT_CONT, struct.pack(">BBIB", pin_a, pin_b, res_raw, status))

def _make_progress(done: int, total: int) -> bytes:
    return _make(Rsp.PROGRESS, struct.pack(">HH", done, total))

def _make_scan_done(total: int, passed: int, failed: int) -> bytes:
    return _make(Rsp.SCAN_DONE, struct.pack(">HHH", total, passed, failed))

# ---------------------------------------------------------------------------
# Netlist parsing (compact wire format sent by the GUI)
# ---------------------------------------------------------------------------

def _parse_compact_netlist(json_bytes: bytes) -> list[tuple[int, int]]:
    """Return cont_pairs from the compact JSON the GUI uploads."""
    raw = json.loads(json_bytes)
    pairs: list[tuple[int, int]] = []
    for net in raw.get("nets", []):
        pins = sorted(p["n"] for p in net.get("pins", []))
        for i in range(len(pins)):
            for j in range(i + 1, len(pins)):
                pairs.append((pins[i], pins[j]))
    return pairs


def _load_json_netlist(path: str) -> list[tuple[int, int]]:
    """Load the full (non-compact) JSON netlist from a file path."""
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)
    pairs: list[tuple[int, int]] = []
    for net in raw.get("nets", []):
        pins = sorted(p["number"] for p in net.get("pins", []))
        for i in range(len(pins)):
            for j in range(i + 1, len(pins)):
                pairs.append((pins[i], pins[j]))
    return pairs


# ---------------------------------------------------------------------------
# FirmwareSimulator
# ---------------------------------------------------------------------------

class FirmwareSimulator:

    def __init__(self, port: str, baud: int, *,
                 preload_netlist: str | None = None,
                 fail_rate: float = 0.06,
                 forced_fail_pins: set[int] | None = None,
                 miswire_pins: set[int] | None = None,
                 interval_ms: int = 30,
                 all_pass: bool = False):
        self._port       = port
        self._baud       = baud
        self._fail_rate  = 0.0 if all_pass else fail_rate
        self._fail_pins  = forced_fail_pins or set()
        self._miswire_pins = miswire_pins or set()
        self._interval_s = interval_ms / 1000.0
        self._all_pass   = all_pass

        # Serial port (set in run())
        self._ser: serial.Serial | None = None
        self._write_lock = threading.Lock()

        # Netlist state
        self._cont_pairs: list[tuple[int, int]] = _DEFAULT_CONT_PAIRS[:]

        if preload_netlist:
            self._load_file_netlist(preload_netlist)

        # SET_NETLIST chunk reassembly
        self._nl_chunks:       dict[int, bytes] = {}
        self._nl_total_chunks: int = 0

        # Streaming control
        self._scan_stop  = threading.Event()
        self._scan_thread: threading.Thread | None = None

        # Packet decoder (FSM-based, CRC-verified)
        self._decoder = PacketDecoder(
            on_packet=self._on_packet,
            on_crc_error=lambda cmd, _: _log(_red("[CRC!]"), f"cmd=0x{cmd:02X}"),
        )

    # ------------------------------------------------------------------
    # Entry point
    # ------------------------------------------------------------------

    def run(self) -> None:
        try:
            self._ser = serial.Serial(self._port, self._baud, timeout=0.05)
        except serial.SerialException as exc:
            print(_red(f"[SIM] Cannot open {self._port}: {exc}"))
            return

        _log(_bold("[SIM]"), f"Listening on {_cyan(self._port)} @ {self._baud} baud")
        _log(_bold("[SIM]"), (
            f"fail_rate={self._fail_rate*100:.0f}%  "
            f"interval={int(self._interval_s*1000)} ms"
        ))
        _log(_bold("[SIM]"), f"Netlist: {len(self._cont_pairs)} continuity pairs")
        _log(_grey("[SIM]"), "Waiting for GUI connection… (Ctrl+C to stop)")

        try:
            while True:
                data = self._ser.read(256)
                if data:
                    self._decoder.feed(data)
        except KeyboardInterrupt:
            _log(_yellow("[SIM]"), "Stopping…")
        except serial.SerialException as exc:
            _log(_red("[SIM]"), f"Serial error: {exc}")
        finally:
            self._scan_stop.set()
            if self._scan_thread:
                self._scan_thread.join(timeout=2.0)
            if self._ser:
                self._ser.close()
            _log(_bold("[SIM]"), "Stopped.")

    # ------------------------------------------------------------------
    # Write
    # ------------------------------------------------------------------

    def _send(self, data: bytes) -> None:
        with self._write_lock:
            if self._ser and self._ser.is_open:
                self._ser.write(data)

    # ------------------------------------------------------------------
    # Packet dispatch (called by PacketDecoder — runs on main thread)
    # ------------------------------------------------------------------

    def _on_packet(self, cmd: int, payload: bytes) -> None:
        try:
            cmd_name = Cmd(cmd).name
        except ValueError:
            cmd_name = "?"
        _log(_blue(f"[RX cmd=0x{cmd:02X} {cmd_name:12s}]"),
             _grey(f"payload({len(payload)}B) = {payload[:16].hex(' ').upper()}"
                   + ("…" if len(payload) > 16 else "")))

        if cmd == Cmd.PING:
            self._send(_make_ack())
            _log(_cyan("[TX ACK ]"), "PING → ACK")

        elif cmd == Cmd.GET_STATUS:
            pkt = _make_status()
            self._send(pkt)
            maj, min_, pat = SIM_FW_VERSION
            _log(_cyan("[TX STS ]"), f"FW v{maj}.{min_}.{pat}  cal={SIM_CAL_OFFSET} mΩ×10")

        elif cmd == Cmd.SET_NETLIST:
            self._handle_set_netlist(payload)

        elif cmd == Cmd.SET_PARAM:
            self._send(_make_ack())
            _log(_cyan("[TX ACK ]"), "SET_PARAM accepted")

        elif cmd == Cmd.CALIBRATE:
            def _do_cal() -> None:
                time.sleep(0.5)
                cal_payload = struct.pack(">H", SIM_CAL_OFFSET)
                self._send(_make_ack(cal_payload))
                _log(_cyan("[TX ACK ]"), f"CALIBRATE done  offset={SIM_CAL_OFFSET} mΩ×10")
            threading.Thread(target=_do_cal, daemon=True).start()

        elif cmd == Cmd.START_CONT:
            self._send(_make_ack())
            _log(_cyan("[TX ACK ]"), "START_CONT — launching scan thread")
            self._start_scan()

        elif cmd == Cmd.START_CROSS_CONT:
            self._send(_make_ack())
            _log(_cyan("[TX ACK ]"), "START_CROSS_CONT — launching cross-continuity scan thread")
            self._start_scan(cross=True)

        elif cmd == Cmd.AUTO_SCAN:
            self._send(_make_ack())
            _log(_cyan("[TX ACK ]"), "AUTO_SCAN — launching 37×37 discovery scan")
            self._start_scan(auto=True)

        elif cmd == Cmd.ABORT:
            self._scan_stop.set()
            self._send(_make_ack())
            _log(_yellow("[TX ACK ]"), "ABORT — scan stopped")

        else:
            self._send(_make_ack())
            _log(_cyan("[TX ACK ]"), f"Unknown cmd 0x{cmd:02X} — ACK'd")

    # ------------------------------------------------------------------
    # SET_NETLIST chunk reassembly
    # ------------------------------------------------------------------

    def _handle_set_netlist(self, payload: bytes) -> None:
        if len(payload) < 4:
            self._send(_make(Rsp.NACK))
            _log(_red("[TX NAK ]"), "SET_NETLIST payload too short")
            return

        seq, total = struct.unpack_from(">HH", payload, 0)
        chunk = payload[4:]
        self._nl_total_chunks = total
        self._nl_chunks[seq] = chunk
        self._send(_make_ack())
        _log(_cyan("[TX ACK ]"),
             f"SET_NETLIST chunk {seq+1}/{total} ({len(chunk)} B)")

        if len(self._nl_chunks) == total:
            json_bytes = b"".join(
                self._nl_chunks[i] for i in range(total)
            )
            self._nl_chunks.clear()
            self._apply_netlist(json_bytes)

    def _apply_netlist(self, json_bytes: bytes) -> None:
        try:
            self._cont_pairs = _parse_compact_netlist(json_bytes)
            _log(_green("[SIM] "),
                 f"Netlist applied — {len(self._cont_pairs)} continuity pairs")
        except Exception as exc:
            _log(_red("[SIM] "), f"Netlist parse error: {exc}")

    def _load_file_netlist(self, path: str) -> None:
        try:
            self._cont_pairs = _load_json_netlist(path)
            _log(_green("[SIM] "), (
                f"Pre-loaded '{os.path.basename(path)}' — "
                f"{len(self._cont_pairs)} continuity pairs"
            ))
        except Exception as exc:
            _log(_red("[SIM] "), f"Could not load netlist '{path}': {exc}")

    # ------------------------------------------------------------------
    # Scan thread management
    # ------------------------------------------------------------------

    def _start_scan(self, *, auto: bool = False, cross: bool = False) -> None:
        if self._scan_thread and self._scan_thread.is_alive():
            self._scan_stop.set()
            self._scan_thread.join(timeout=1.0)

        self._scan_stop.clear()
        self._scan_thread = threading.Thread(
            target=self._stream_all,
            kwargs={"auto": auto, "cross": cross},
            daemon=True,
        )
        self._scan_thread.start()

    # ------------------------------------------------------------------
    # Result streaming
    # ------------------------------------------------------------------

    def _stream_all(self, *, auto: bool = False, cross: bool = False) -> None:
        if cross:
            self._stream_cross_cont()
            return

        if auto:
            # AUTO_SCAN: only PASS results for physically-connected pairs within 1-37
            discovered = [(a, b) for a, b in self._cont_pairs if 1 <= a <= 37 and 1 <= b <= 37]
            _log(_bold("[SIM] "), f"AUTO_SCAN: streaming {len(discovered)} discovered pair(s)")
            for pin_a, pin_b in discovered:
                if self._scan_stop.is_set():
                    return
                res_raw = random.randint(10, 4500)
                self._send(_make_cont(pin_a, pin_b, res_raw, fail=False))
                _log("[TX AUTO]", f"A{pin_a:2d}→B{pin_b:2d}  {res_raw/10.0:.1f} mΩ  {_green('PASS')}")
                time.sleep(self._interval_s)
            self._send(_make_scan_done(len(discovered), len(discovered), 0))
            _log(_bold("[SIM] "), f"AUTO_SCAN complete — {len(discovered)} connection(s) found")
            return

        total = len(self._cont_pairs)
        if total == 0:
            _log(_yellow("[SIM] "), "No pairs to test — scan skipped")
            return

        _log(_bold("[SIM] "), f"Scan start — {total} continuity pairs")

        passed = 0
        failed = 0

        for idx, (pin_a, pin_b) in enumerate(self._cont_pairs):
            if self._scan_stop.is_set():
                _log(_yellow("[SIM] "), "Scan aborted")
                return

            fail = ((pin_a in self._fail_pins) or
                    (not self._all_pass and random.random() < self._fail_rate))

            if fail:
                res_raw = random.randint(5001, 15000)   # 500.1 – 1500.0 mΩ (above limit)
                failed += 1
                status_label = _red("FAIL")
            else:
                res_raw = random.randint(10, 4500)       # 1 – 450 mΩ
                passed += 1
                status_label = _green("PASS")

            self._send(_make_cont(pin_a, pin_b, res_raw, fail))
            _log(f"[TX CONT]",
                 f"A{pin_a:3d}→B{pin_b:3d}  {res_raw/10.0:7.1f} mΩ  {status_label}")

            done = idx + 1
            if done % 8 == 0 or done == total:
                self._send(_make_progress(done, total))

            time.sleep(self._interval_s)

        self._send(_make_scan_done(total, passed, failed))

        verdict = _bold(_green("ALL PASS")) if failed == 0 else _bold(_red(f"{failed} FAIL"))
        _log(_bold("[SIM] "),
             f"Scan complete — {total} pairs  passed={passed}  failed={failed}  {verdict}")

    def _stream_cross_cont(self) -> None:
        """Cross-continuity scan: one Side-A pin to all Side-B pins."""
        expected = set(self._cont_pairs)
        total = 0
        passed = 0
        failed = 0

        _log(_bold("[SIM] "), f"Cross-continuity scan start — {len(expected)} expected pairs")

        for a in range(1, 38):
            if self._scan_stop.is_set():
                _log(_yellow("[SIM] "), "Cross-continuity scan aborted")
                return

            for b in range(1, 38):
                is_expected = (a, b) in expected
                is_open = (a in self._fail_pins) and is_expected
                is_miswire = (a in self._miswire_pins) and not is_expected

                if is_expected and not is_open:
                    res_raw = random.randint(10, 4500)
                    self._send(_make_cont(a, b, res_raw, False))
                    _log("[TX XCON]", f"A{a:3d}→B{b:3d}  {res_raw/10.0:7.1f} mΩ  {_green('PASS')}")
                    passed += 1
                    total += 1
                elif is_expected and is_open:
                    res_raw = random.randint(5001, 15000)
                    self._send(_make_cont(a, b, res_raw, True))
                    _log("[TX XCON]", f"A{a:3d}→B{b:3d}  {res_raw/10.0:7.1f} mΩ  {_red('OPEN')}")
                    failed += 1
                    total += 1
                elif is_miswire:
                    res_raw = random.randint(5001, 15000)
                    # status 2 = MISWIRE: encode via fail=True but the GUI will also check status byte
                    self._send(_make(Rsp.RESULT_CONT, struct.pack(">BBIB", a, b, res_raw, 2)))
                    _log("[TX XCON]", f"A{a:3d}→B{b:3d}  {res_raw/10.0:7.1f} mΩ  {_red('MISWIRE')}")
                    failed += 1
                    total += 1
                else:
                    # No connection expected and none found — report so GUI shows full matrix
                    res_raw = 500000
                    self._send(_make(Rsp.RESULT_CONT, struct.pack(">BBIB", a, b, res_raw, 3)))
                    _log("[TX XCON]", f"A{a:3d}→B{b:3d}  {res_raw/10.0:7.1f} mΩ  NOT_CONNECTED")
                    total += 1

            if (a % 4 == 0) or (a == 37):
                self._send(_make_progress(a, 37))
            time.sleep(self._interval_s)

        self._send(_make_scan_done(total, passed, failed))
        verdict = _bold(_green("ALL PASS")) if failed == 0 else _bold(_red(f"{failed} FAIL"))
        _log(_bold("[SIM] "),
             f"Cross-continuity scan complete — {total} results  passed={passed}  failed={failed}  {verdict}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def _pin_list(s: str) -> set[int]:
    return {int(x.strip()) for x in s.split(",") if x.strip()} if s else set()


def main() -> None:
    global _USE_COLOR

    parser = argparse.ArgumentParser(
        description="Harness Tester firmware simulator — real UART protocol, no hardware needed",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--port",        required=True,               help="Serial port to listen on")
    parser.add_argument("--baud",        type=int,   default=115200,  help="Baud rate (default 115200)")
    parser.add_argument("--netlist",     default="",                  help="Pre-load a JSON netlist file")
    parser.add_argument("--fail-rate",   type=float, default=0.06,    help="Continuity fail rate 0-1 (default 0.06)")
    parser.add_argument("--fail-pins",    default="",                  help="Force-fail pins e.g. 5,23,37")
    parser.add_argument("--miswire-pins", default="",                  help="Force miswire (unexpected connection) pins e.g. 7,12")
    parser.add_argument("--interval-ms",  type=int,   default=30,      help="ms between result packets (default 30)")
    parser.add_argument("--all-pass",    action="store_true",         help="Force every result to PASS")
    parser.add_argument("--no-color",    action="store_true",         help="Disable ANSI colour output")
    args = parser.parse_args()

    if args.no_color:
        _USE_COLOR = False

    # Enable ANSI on Windows
    if sys.platform == "win32" and _USE_COLOR:
        import ctypes
        kernel32 = ctypes.windll.kernel32
        kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)

    FirmwareSimulator(
        port=args.port,
        baud=args.baud,
        preload_netlist=args.netlist or None,
        fail_rate=args.fail_rate,
        forced_fail_pins=_pin_list(args.fail_pins),
        miswire_pins=_pin_list(args.miswire_pins),
        interval_ms=args.interval_ms,
        all_pass=args.all_pass,
    ).run()


if __name__ == "__main__":
    main()
