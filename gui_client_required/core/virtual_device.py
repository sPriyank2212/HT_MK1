"""A tester without the hardware: the firmware's UART behaviour, in-process.

VirtualTester stands in for serial.Serial.  SerialWorker writes protocol
frames to it and reads protocol frames back, exactly as it would from the
STM32 (see firmware/Core/Src/harness.c), so every part of the GUI above the
serial port runs unchanged.

What the tester measures comes from a VirtualHarness: the wires that are
"plugged in", in tester channels.  A scan drives a Side-A channel and reads
the Side-B channels that are electrically joined to it, so a stray wire
shows up the way it does on the bench: as an extra connection on every
channel it touches.
"""

from __future__ import annotations

import json
import random
import struct
import threading
import time

from .data_types import Cmd, Rsp
from .packet_codec import PacketDecoder, encode_packet

HARNESS_PINS = 37            # channels per side (HARNESS_PINS in harness.h)
FW_VERSION = (2, 2, 0)       # FW_MAJOR / FW_MINOR / FW_PATCH in harness.h
CAL_OFFSET = 120             # CAL_OFFSET_DEFAULT

MAX_NL_BYTES = 4096          # limits of the firmware's netlist buffer
MAX_NL_PAIRS = 256
MAX_NL_CHUNKS = 64
MAX_NET_PINS = 64

RES_CONNECTED = 500          # 50.0 mohm, as the firmware reports a closed wire
RES_OPEN = 500000

# Firmware states (harness.h)
ST_IDLE, ST_UPLOADING, ST_CALIBRATING, ST_SCANNING, ST_COMPLETE = 0, 1, 2, 3, 5

# Seconds the demo waits per pair (continuity) or per Side-A pin (cross
# continuity, Auto-Scan).  "Fast" is about what the real tester takes.
SPEEDS = {"Fast": 0.005, "Normal": 0.04, "Slow": 0.15}


class VirtualHarness:
    """The harness plugged into the tester: wires between Side-A and Side-B channels."""

    def __init__(self, rng: random.Random | None = None):
        self._lock = threading.Lock()
        self._rng = rng or random.Random()
        self._wires: list[tuple[int, int]] = []
        self._open: set[int] = set()                   # indexes into _wires that are broken
        self._extra: list[tuple[int, int]] = []        # stray wires

    # -- what is plugged in ------------------------------------------------

    def set_wires(self, pairs) -> None:
        """Plug in a new harness.  Faults of the old one go with it."""
        seen: set[tuple[int, int]] = set()
        wires = []
        for a, b in pairs:
            if (a, b) not in seen:
                seen.add((a, b))
                wires.append((a, b))
        with self._lock:
            self._wires, self._open, self._extra = wires, set(), []

    @property
    def wires(self) -> list[tuple[int, int]]:
        with self._lock:
            return list(self._wires)

    @property
    def open_wires(self) -> list[tuple[int, int]]:
        with self._lock:
            return [self._wires[i] for i in sorted(self._open)]

    @property
    def extra_wires(self) -> list[tuple[int, int]]:
        with self._lock:
            return list(self._extra)

    # -- faults ------------------------------------------------------------

    def inject_open(self, count: int = 1) -> list[tuple[int, int]]:
        """Break `count` wires that are still good.  Returns the wires broken."""
        with self._lock:
            good = [i for i in range(len(self._wires)) if i not in self._open]
            hit = self._rng.sample(good, min(count, len(good)))
            self._open.update(hit)
            return [self._wires[i] for i in sorted(hit)]

    def inject_miswire(self, count: int = 1) -> list[tuple[int, int]]:
        """Add `count` stray wires between channels that were not connected.
        Returns the wires added."""
        added: list[tuple[int, int]] = []
        for _ in range(count):
            conn = self.connections()
            used_a = sorted({a for a, _ in self.wires if 1 <= a <= HARNESS_PINS}) \
                or list(range(1, HARNESS_PINS + 1))
            options = [(a, b) for a in used_a for b in range(1, HARNESS_PINS + 1)
                       if b not in conn.get(a, ())]
            if not options:
                break
            wire = self._rng.choice(options)
            with self._lock:
                self._extra.append(wire)
            added.append(wire)
        return added

    def clear_faults(self) -> None:
        with self._lock:
            self._open, self._extra = set(), []

    @property
    def has_faults(self) -> bool:
        with self._lock:
            return bool(self._open or self._extra)

    # -- what a scan sees --------------------------------------------------

    def connections(self) -> dict[int, set[int]]:
        """{Side-A channel: Side-B channels that read HIGH when it is driven}.

        Wires join nets; every Side-B channel on the same net as a driven
        Side-A channel reads HIGH.
        """
        with self._lock:
            live = [w for i, w in enumerate(self._wires) if i not in self._open]
            live += self._extra
        parent: dict[tuple[str, int], tuple[str, int]] = {}

        def find(x):
            parent.setdefault(x, x)
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        for a, b in live:
            if 1 <= a <= HARNESS_PINS and 1 <= b <= HARNESS_PINS:
                parent[find(("A", a))] = find(("B", b))
        members: dict[tuple[str, int], set[int]] = {}
        for node in list(parent):
            if node[0] == "B":
                members.setdefault(find(node), set()).add(node[1])
        return {node[1]: set(members.get(find(node), ()))
                for node in list(parent) if node[0] == "A"}


class VirtualTester:
    """Serial-like object (write / read / in_waiting / close) that answers the way the firmware does."""

    def __init__(self, harness: VirtualHarness | None = None, step_s: float = SPEEDS["Normal"]):
        self.harness = harness or VirtualHarness()
        self.harness.set_wires([(i, i) for i in range(1, HARNESS_PINS + 1)])  # nl_default
        self.step_s = step_s

        self._rx = bytearray()
        self._rx_lock = threading.Lock()
        self._decoder = PacketDecoder(self._on_packet)
        self.is_open = False

        self._state = ST_IDLE
        self._abort = threading.Event()
        self._thread: threading.Thread | None = None

        # Netlist as the firmware holds it: pairs of channels.
        self._pairs: list[tuple[int, int]] = []
        self._nl_chunks: dict[int, bytes] = {}
        self._nl_total = 0
        self.r_limit_mohm = 500
        self.ir_limit_mohm = 100

    # -- serial.Serial interface --------------------------------------------

    def open(self, port: str = "DEMO", baud: int = 115200, timeout=None) -> "VirtualTester":
        """What SerialWorker calls instead of serial.Serial(...)."""
        self._abort.set()
        self._join()
        with self._rx_lock:
            self._rx.clear()
        self._decoder = PacketDecoder(self._on_packet)
        self._state = ST_IDLE
        self._abort.clear()
        self.is_open = True
        return self

    @property
    def in_waiting(self) -> int:
        with self._rx_lock:
            return len(self._rx)

    def read(self, size: int = 1) -> bytes:
        with self._rx_lock:
            data = bytes(self._rx[:size])
            del self._rx[:size]
        return data

    def write(self, data: bytes) -> int:
        if self.is_open:
            self._decoder.feed(data)
        return len(data)

    def close(self) -> None:
        self.is_open = False
        self._abort.set()
        self._join()

    # -- helpers ---------------------------------------------------------------

    def _join(self) -> None:
        t = self._thread
        if t and t.is_alive() and t is not threading.current_thread():
            t.join(timeout=2.0)

    def _send(self, cmd: int, payload: bytes = b"") -> None:
        if not self.is_open:
            return
        frame = encode_packet(cmd, payload)
        with self._rx_lock:
            self._rx += frame

    def _ack(self, payload: bytes = b"") -> None:
        self._send(Rsp.ACK, payload)

    def _nack(self) -> None:
        self._send(Rsp.NACK)

    def _status(self) -> None:
        self._send(Rsp.STATUS, struct.pack(">BBBBBH", self._state, 0, *FW_VERSION, CAL_OFFSET) + b"\x00")

    def _result(self, a: int, b: int, res_raw: int, status: int) -> None:
        self._send(Rsp.RESULT_CONT, struct.pack(">BBIB", a, b, res_raw, status))

    def _progress(self, done: int, total: int) -> None:
        self._send(Rsp.PROGRESS, struct.pack(">HH", done, total))

    def _scan_done(self, total: int, passed: int, failed: int) -> None:
        self._send(Rsp.SCAN_DONE, struct.pack(">HHH", total, passed, failed))

    # -- command dispatch (dispatch_command in harness.c) --------------------------

    def _on_packet(self, cmd: int, payload: bytes) -> None:
        idle = self._state in (ST_IDLE, ST_COMPLETE)
        if cmd == Cmd.PING:
            self._ack()
        elif cmd in (Cmd.GET_STATUS, Cmd.GET_RESULT):
            self._status()
        elif cmd == Cmd.SET_NETLIST:
            self._set_netlist(payload)
        elif cmd == Cmd.SET_PARAM:
            if len(payload) >= 4:
                self.r_limit_mohm, self.ir_limit_mohm = struct.unpack_from(">HH", payload, 0)
            self._ack()
        elif cmd == Cmd.CALIBRATE:
            if self._state == ST_IDLE:
                self._state = ST_CALIBRATING
                self._ack_later(0.5, struct.pack(">H", CAL_OFFSET))
            else:
                self._nack()
        elif cmd in (Cmd.START_CONT, Cmd.START_CROSS_CONT, Cmd.AUTO_SCAN):
            if idle:
                self._abort.clear()
                self._state = ST_SCANNING
                self._ack()
                scan = {Cmd.START_CONT: self._scan_continuity,
                        Cmd.START_CROSS_CONT: self._scan_cross,
                        Cmd.AUTO_SCAN: self._scan_auto}[Cmd(cmd)]
                self._thread = threading.Thread(target=self._run, args=(scan,), daemon=True)
                self._thread.start()
            else:
                self._nack()
        elif cmd == Cmd.ABORT:
            self._abort.set()
            self._ack()
            self._state = ST_IDLE
        else:
            self._nack()

    def _ack_later(self, delay: float, payload: bytes) -> None:
        def done() -> None:
            if self.is_open and self._state == ST_CALIBRATING:
                self._ack(payload)
                self._state = ST_IDLE
        t = threading.Timer(delay, done)
        t.daemon = True
        t.start()

    # -- netlist upload (handle_set_netlist / nl_parse_json) -------------------------

    def _set_netlist(self, payload: bytes) -> None:
        if len(payload) < 4:
            return self._nack()
        seq, total = struct.unpack_from(">HH", payload, 0)
        if total == 0 or total > MAX_NL_CHUNKS or seq >= total:
            return self._nack()
        if self._nl_total == 0 or total != self._nl_total:
            self._nl_chunks.clear()
            self._pairs = []
            self._nl_total = total
        chunk = payload[4:]
        if seq not in self._nl_chunks and sum(map(len, self._nl_chunks.values())) + len(chunk) <= MAX_NL_BYTES:
            self._nl_chunks[seq] = chunk
        self._ack()
        if len(self._nl_chunks) >= self._nl_total:
            data = b"".join(self._nl_chunks[i] for i in sorted(self._nl_chunks))
            self._pairs = self._parse_netlist(data)
            self._nl_chunks.clear()
            self._nl_total = 0
            self._state = ST_IDLE
        else:
            self._state = ST_UPLOADING

    @staticmethod
    def _parse_netlist(data: bytes) -> list[tuple[int, int]]:
        """Every two pins of a net, in list order: the pairs the firmware tests."""
        try:
            nets = json.loads(data).get("nets", [])
        except ValueError:
            return []
        pairs: list[tuple[int, int]] = []
        for net in nets:
            pins = [p["n"] for p in net.get("pins", []) if 1 <= p.get("n", 0) <= 255][:MAX_NET_PINS]
            for i in range(len(pins)):
                for j in range(i + 1, len(pins)):
                    if len(pairs) < MAX_NL_PAIRS:
                        pairs.append((pins[i], pins[j]))
        return pairs

    @property
    def pairs(self) -> list[tuple[int, int]]:
        """What the next scan tests: the uploaded netlist, else A[n] <-> B[n]."""
        return list(self._pairs) or [(i, i) for i in range(1, HARNESS_PINS + 1)]

    # -- scans (run_continuity_scan / run_cross_continuity_scan / run_auto_scan) ------

    def _run(self, scan) -> None:
        try:
            scan()
        finally:
            if self._state == ST_SCANNING:
                self._state = ST_COMPLETE

    def _wait(self) -> bool:
        """Pace the scan; False when it has been aborted."""
        return not self._abort.wait(self.step_s)

    def _scan_continuity(self) -> None:
        pairs = self.pairs
        conn = self.harness.connections()
        total, passed, failed = len(pairs), 0, 0
        for i, (a, b) in enumerate(pairs):
            if self._abort.is_set():
                break
            if not self._wait():
                break
            if not (1 <= a <= HARNESS_PINS and 1 <= b <= HARNESS_PINS):
                passed += 1
                continue
            if b in conn.get(a, ()):
                passed += 1
                self._result(a, b, RES_CONNECTED, 0)
            else:
                failed += 1
                self._result(a, b, RES_OPEN, 1)
            if (i + 1) % 4 == 0 or i + 1 == total:
                self._progress(i + 1, total)
        self._scan_done(total, passed, failed)

    def _scan_cross(self) -> None:
        # harness.c's is_expected() also accepts the reversed pair (A9->B5 for a
        # listed A5->B9).  That is a different physical path, so the demo does
        # not: only the pairs the netlist lists are expected.
        expected = set(self.pairs)
        conn = self.harness.connections()
        total = passed = failed = 0
        for a in range(1, HARNESS_PINS + 1):
            if self._abort.is_set() or not self._wait():
                break
            for b in range(1, HARNESS_PINS + 1):
                high = b in conn.get(a, ())
                want = (a, b) in expected
                total += 1
                if want and high:
                    passed += 1
                    self._result(a, b, RES_CONNECTED, 0)
                elif want:
                    failed += 1
                    self._result(a, b, RES_OPEN, 1)
                elif high:
                    failed += 1
                    self._result(a, b, RES_OPEN, 2)
                else:
                    self._result(a, b, RES_OPEN, 3)
            if a % 4 == 0 or a == HARNESS_PINS:
                self._progress(a, HARNESS_PINS)
        self._scan_done(total, passed, failed)

    def _scan_auto(self) -> None:
        conn = self.harness.connections()
        found = swept = 0
        for a in range(1, HARNESS_PINS + 1):
            if self._abort.is_set() or not self._wait():
                break
            for b in sorted(conn.get(a, ())):
                self._result(a, b, RES_CONNECTED, 0)
                found += 1
            swept += 1
            if a % 4 == 0 or a == HARNESS_PINS:
                self._progress(swept, HARNESS_PINS)
        self._scan_done(found, found, 0)
