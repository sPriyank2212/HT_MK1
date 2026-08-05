"""Connection manager for the HT_MK1 GUI (brief 3.5, task 2).

Owns the transport and the session log; delegates the wire format to
``htproto.codec``. Implements the rules in section 3.5:

1. Every command waits for its ``<`` reply; a 2 s timeout is surfaced
   (``CommandTimeoutError``) and the link drops to LINK_LOST — after a lost
   reply the reply ordering can no longer be trusted, so the safe assumption
   is "unknown", never "still fine".
2. HV indication from ``!HV`` events is the GUI's job; this layer delivers
   every event verbatim via ``on_event``.
3. Port closed, or ``link_timeout`` (5 s) with no traffic: state becomes
   LINK_LOST ("link lost - state unknown") and every command raises.
4. ``connect()`` — including reconnect — issues ``>STATUS`` and only reports
   CONNECTED after the reply arrives. Never assume idle.
5. Every byte sent and received goes to a session log file.

Callbacks (``on_event``, ``on_link_state``, ``on_protocol_error``) fire from
reader/watchdog threads — the GUI must marshal them onto its UI thread.

Transport is pluggable: anything with ``open(address)``, ``send(bytes)``,
``recv(n)`` and ``close()`` works. ``TcpTransport`` talks to the simulator;
a serial transport (115200 8N1 USB VCP) slots in for real hardware without
touching this class.
"""

from __future__ import annotations

import socket
import threading
import time
from collections import deque
from datetime import datetime
from enum import Enum
from pathlib import Path

from .codec import LineFramer, ProtocolError, commands, parse_line
from .messages import NetEntry, NetlistReply, StatusReply

DEFAULT_COMMAND_TIMEOUT = 2.0  # seconds, per 3.5.1
DEFAULT_LINK_TIMEOUT = 5.0     # seconds, per 3.5.3


class LinkState(Enum):
    DISCONNECTED = "disconnected"
    CONNECTED = "connected"
    LINK_LOST = "link_lost"    # "state unknown" — never presented as safe


class ConnectionError_(Exception):
    """Base for connection-manager failures."""


class NotConnectedError(ConnectionError_):
    """Command attempted while DISCONNECTED."""


class LinkLostError(ConnectionError_):
    """Command attempted after the link dropped; reconnect required."""


class CommandTimeoutError(ConnectionError_, TimeoutError):
    """No < reply within the command timeout (3.5.1)."""


class TcpTransport:
    """TCP transport — the simulator's side of the wire."""

    def __init__(self) -> None:
        self._sock: socket.socket | None = None

    def open(self, address) -> None:
        host, port = address
        self._sock = socket.create_connection((host, port), timeout=5)
        self._sock.settimeout(None)

    def send(self, data: bytes) -> None:
        self._sock.sendall(data)

    def recv(self, n: int) -> bytes:
        return self._sock.recv(n)

    def close(self) -> None:
        if self._sock is not None:
            try:
                self._sock.close()
            finally:
                self._sock = None


class SessionLogger:
    """Every line sent and received, timestamped, flushed immediately (3.5.5).

    Field failures get diagnosed from this file, so nothing is buffered.
    """

    def __init__(self, log_dir: str | Path) -> None:
        self._dir = Path(log_dir)
        self._file = None
        self._lock = threading.Lock()
        self.path: Path | None = None

    def open(self) -> None:
        self._dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        self.path = self._dir / f"session-{stamp}.log"
        self._file = open(self.path, "a", encoding="utf-8")
        self.meta("session log opened")

    def _write(self, tag: str, text: str) -> None:
        with self._lock:
            if self._file is None:
                return
            stamp = datetime.now().isoformat(timespec="milliseconds")
            self._file.write(f"{stamp} [{tag}] {text}\n")
            self._file.flush()

    def tx(self, line: str) -> None:
        self._write("tx", line)

    def rx(self, line: str) -> None:
        self._write("rx", line)

    def meta(self, text: str) -> None:
        self._write("gui", text)

    def close(self) -> None:
        with self._lock:
            if self._file is not None:
                self._file.close()
                self._file = None


class _Pending:
    """One in-flight command awaiting its reply.

    Most commands expect exactly one reply line. ``>NETLIST GET`` expects a
    ``<NETLIST <n>`` header followed by n ``<NET`` lines (3.2); the header
    sets ``expect`` and the same entry keeps consuming replies until the
    sequence is complete — so <NET lines can never be mistaken for replies
    to some other command.
    """

    __slots__ = ("done", "error", "lines", "is_netlist", "expect")

    def __init__(self, is_netlist: bool = False) -> None:
        self.done = threading.Event()
        self.error: Exception | None = None
        self.lines: list[object] = []
        self.is_netlist = is_netlist
        self.expect: int | None = None  # total lines; set by the NETLIST header


class ConnectionManager:
    def __init__(self, *, on_event=None, on_link_state=None, on_protocol_error=None,
                 command_timeout: float = DEFAULT_COMMAND_TIMEOUT,
                 link_timeout: float = DEFAULT_LINK_TIMEOUT,
                 log_dir: str | Path = "sessions",
                 transport_factory=TcpTransport) -> None:
        self._on_event = on_event or (lambda msg: None)
        self._on_link_state = on_link_state or (lambda state, detail: None)
        self._on_protocol_error = on_protocol_error or (lambda raw, exc: None)
        self.command_timeout = command_timeout
        self.link_timeout = link_timeout
        self._transport_factory = transport_factory
        self._transport = None
        self._state = LinkState.DISCONNECTED
        self._state_lock = threading.Lock()
        self._io_lock = threading.Lock()       # serialises append+send (reply order)
        self._pending: deque[_Pending] = deque()
        self._reader: threading.Thread | None = None
        self._watchdog: threading.Thread | None = None
        self._stop = threading.Event()
        self._last_rx = 0.0
        self.logger = SessionLogger(log_dir)

    # -- lifecycle -------------------------------------------------------------

    @property
    def state(self) -> LinkState:
        with self._state_lock:
            return self._state

    def connect(self, host: str = "127.0.0.1", port: int = 46000) -> StatusReply:
        """Open the link and handshake with >STATUS (3.5.4).

        Returns the instrument's STATUS reply; controls may only be enabled
        from what it says. Raises on any failure — never assume idle.
        """
        self.disconnect()
        self._stop.clear()
        transport = self._transport_factory()
        transport.open((host, port))  # OSError propagates; still DISCONNECTED
        self._transport = transport
        self.logger.open()
        self.logger.meta(f"connected {host}:{port}")
        self._last_rx = time.monotonic()
        with self._state_lock:
            self._state = LinkState.CONNECTED
        self._reader = threading.Thread(target=self._read_loop, daemon=True,
                                        name="htproto-reader")
        self._reader.start()
        self._watchdog = threading.Thread(target=self._watchdog_loop, daemon=True,
                                          name="htproto-watchdog")
        self._watchdog.start()
        try:
            status = self.execute(commands.status())
        except ConnectionError_:
            self.disconnect()
            raise
        if not isinstance(status, StatusReply):
            self.disconnect()
            raise ConnectionError_(f"STATUS handshake got unexpected reply {status!r}")
        self._on_link_state(self.state, f"connected {host}:{port}")
        return status

    def disconnect(self) -> None:
        self._stop.set()
        transport, self._transport = self._transport, None
        if transport is not None:
            try:
                transport.close()
            except OSError:
                pass
        for t in (self._reader, self._watchdog):
            if t is not None and t is not threading.current_thread():
                t.join(timeout=2)
        self._reader = self._watchdog = None
        self._fail_all_pending(NotConnectedError("disconnected"))
        with self._state_lock:
            changed = self._state is not LinkState.DISCONNECTED
            self._state = LinkState.DISCONNECTED
        if changed:
            self.logger.meta("disconnected")
            self._on_link_state(LinkState.DISCONNECTED, "disconnected")
        self.logger.close()

    # -- commands ----------------------------------------------------------------

    def execute(self, command: bytes) -> object:
        """Send one command, wait for its parsed reply. Raises on timeout."""
        entry = self._execute(command)
        return entry.lines[0]

    def netlist_get(self) -> list[NetEntry]:
        """>NETLIST GET: header reply followed by n <NET lines (3.2)."""
        entry = self._execute(commands.netlist_get(), is_netlist=True)
        header, entries = entry.lines[0], entry.lines[1:]
        if not isinstance(header, NetlistReply) or len(entries) != header.count:
            raise ConnectionError_(f"malformed NETLIST GET sequence: {entry.lines!r}")
        return entries

    def _execute(self, command: bytes, is_netlist: bool = False) -> _Pending:
        entry = _Pending(is_netlist=is_netlist)
        send_error: OSError | None = None
        with self._io_lock:
            self._require_ready()
            self._pending.append(entry)
            try:
                self._send_line(command)
            except OSError as exc:
                self._pending.remove(entry)
                send_error = exc
        if send_error is not None:
            # _link_lost re-acquires _io_lock via _fail_all_pending, and
            # threading.Lock is not reentrant: it must run AFTER the with
            # block, or the calling thread deadlocks (GUI-01).
            self._link_lost(f"send failed: {send_error}")
            raise LinkLostError(f"send failed: {send_error}") from send_error
        if not entry.done.wait(self.command_timeout):
            with self._io_lock:
                if entry in self._pending:
                    self._pending.remove(entry)
            self._link_lost(f"command timeout after {self.command_timeout:.1f}s: "
                            f"{command!r}")
            raise CommandTimeoutError(
                f"no reply within {self.command_timeout:.1f}s: {command!r}")
        if entry.error is not None:
            raise entry.error
        return entry

    # -- receive path ------------------------------------------------------------

    def _send_line(self, command: bytes) -> None:
        self._transport.send(command)
        self.logger.tx(command.decode("ascii").rstrip("\n"))

    def _read_loop(self) -> None:
        framer = LineFramer()
        try:
            while not self._stop.is_set():
                data = self._transport.recv(4096)
                if not data:
                    self._link_lost("port closed by instrument")
                    return
                self._last_rx = time.monotonic()
                for line in framer.feed(data):
                    self._handle_incoming(line)
        except OSError as exc:
            if not self._stop.is_set():
                self._link_lost(f"port error: {exc}")
        except UnicodeDecodeError as exc:
            self._on_protocol_error("<non-ascii bytes>", exc)

    def _handle_incoming(self, line: str) -> None:
        self.logger.rx(line)
        try:
            msg = parse_line(line)
        except ProtocolError as exc:
            # Malformed line: surface it, keep the link, let timeouts decide.
            self._on_protocol_error(line, exc)
            return
        if line.startswith("<"):
            self._match_reply(msg, line)
        else:  # '!' event or '#' log line
            self._on_event(msg)

    def _match_reply(self, msg: object, raw: str) -> None:
        with self._io_lock:
            if not self._pending:
                self._on_protocol_error(
                    raw, ProtocolError("reply with no command in flight"))
                return
            entry = self._pending[0]
            entry.lines.append(msg)
            finished = True
            if entry.is_netlist:
                first = entry.lines[0]
                if not isinstance(first, NetlistReply):
                    entry.error = ConnectionError_(
                        f"NETLIST GET: expected <NETLIST header, got {first!r}")
                elif not isinstance(msg, (NetlistReply, NetEntry)):
                    entry.error = ProtocolError(
                        f"NETLIST GET: expected <NET, got {msg!r}")
                elif len(entry.lines) < 1 + first.count:
                    finished = False  # more <NET lines to come
            if finished:
                self._pending.popleft()
                entry.done.set()

    def _watchdog_loop(self) -> None:
        # 3.5.3: 5 s with no traffic -> link lost, state unknown.
        while not self._stop.wait(min(self.link_timeout / 4, 0.5)):
            if self.state is LinkState.CONNECTED and \
                    time.monotonic() - self._last_rx > self.link_timeout:
                self._link_lost(f"no traffic for {self.link_timeout:.1f}s")
                return

    # -- failure handling ----------------------------------------------------------

    def _require_ready(self) -> None:
        state = self.state
        if state is LinkState.DISCONNECTED:
            raise NotConnectedError("not connected")
        if state is LinkState.LINK_LOST:
            raise LinkLostError("link lost - state unknown; reconnect required")

    def _link_lost(self, detail: str) -> None:
        with self._state_lock:
            if self._state is not LinkState.CONNECTED:
                return
            self._state = LinkState.LINK_LOST
        self.logger.meta(f"LINK LOST: {detail}")
        self._fail_all_pending(LinkLostError(f"link lost: {detail}"))
        # The bytes can no longer be trusted; force a clean reconnect.
        transport, self._transport = self._transport, None
        if transport is not None:
            try:
                transport.close()
            except OSError:
                pass
        self._on_link_state(LinkState.LINK_LOST, detail)

    def _fail_all_pending(self, exc: Exception) -> None:
        with self._io_lock:
            pending = list(self._pending)
            self._pending.clear()
        for entry in pending:
            entry.error = exc
            entry.done.set()
