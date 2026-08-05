"""Connection manager tests (brief 3.5, task 2).

Happy paths run against the real simulator; failure paths use small stub
servers that reply once then go silent, or send garbage.
"""

import socket
import tempfile
import threading
import time
import unittest

from htproto import commands, messages as m
from htproto.codec import ContMode
from htproto.connection import (
    CommandTimeoutError,
    ConnectionManager,
    LinkLostError,
    LinkState,
    NotConnectedError,
    TcpTransport,
)
from htproto.simulator import SimulatorServer, make_scenario

# Short timeouts keep the failure-path tests fast; the defaults (2 s / 5 s)
# are the contract values and are what the GUI will use.
CMD_TIMEOUT = 0.3
LINK_TIMEOUT = 0.8


class StubServer:
    """Minimal TCP server with scripted behaviour.

    handler(client_socket, line) -> response line (str) or None (stay silent).
    """

    def __init__(self, handler, banner: str | None = None):
        self.handler = handler
        self.banner = banner
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.bind(("127.0.0.1", 0))
        self._sock.listen(1)
        self.host, self.port = self._sock.getsockname()[:2]
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._serve, daemon=True)

    def start(self):
        self._thread.start()
        return self

    def stop(self):
        self._stop.set()
        self._sock.close()
        self._thread.join(timeout=2)

    def _serve(self):
        self._sock.settimeout(0.2)
        while not self._stop.is_set():
            try:
                client, _ = self._sock.accept()
            except (socket.timeout, OSError):
                continue
            threading.Thread(target=self._client, args=(client,),
                             daemon=True).start()

    def _client(self, client):
        try:
            if self.banner is not None:
                client.sendall(self.banner.encode() + b"\n")
            buf = b""
            while not self._stop.is_set():
                data = client.recv(4096)
                if not data:
                    return
                buf += data
                while b"\n" in buf:
                    raw, buf = buf.split(b"\n", 1)
                    reply = self.handler(client, raw.decode().rstrip("\r"))
                    if reply is not None:
                        client.sendall(reply.encode() + b"\n")
        except OSError:
            pass
        finally:
            try:
                client.close()
            except OSError:
                pass


def make_manager(**kw) -> ConnectionManager:
    kw.setdefault("command_timeout", CMD_TIMEOUT)
    kw.setdefault("link_timeout", LINK_TIMEOUT)
    kw.setdefault("log_dir", tempfile.mkdtemp(prefix="htproto-sessions-"))
    return ConnectionManager(**kw)


def upload_netlist(cm: ConnectionManager, nets) -> None:
    cm.execute(commands.netlist_begin(len(nets)))
    for hi, lo in nets:
        cm.execute(commands.netlist_add(hi, lo))
    cm.execute(commands.netlist_end())


DEFAULT_NETS = [(2 * i + 1, 2 * i + 2) for i in range(6)]


class TestHappyPath(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = SimulatorServer(make_scenario("pass", 6), port=0,
                                     interval=0.0).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.stop()

    def setUp(self):
        self.events = []
        self.link_states = []
        self.proto_errors = []
        self.cm = make_manager(on_event=self.events.append,
                               on_link_state=lambda s, d: self.link_states.append((s, d)),
                               on_protocol_error=lambda r, e: self.proto_errors.append((r, e)))

    def tearDown(self):
        self.cm.disconnect()

    def test_connect_handshakes_status(self):
        status = self.cm.connect(self.server.host, self.server.port)
        self.assertIsInstance(status, m.StatusReply)
        self.assertEqual(self.cm.state, LinkState.CONNECTED)
        # Never assume idle: the handshake returned the instrument's own words.
        self.assertEqual(status.state.value, "idle")

    def test_command_round_trip(self):
        self.cm.connect(self.server.host, self.server.port)
        self.assertEqual(self.cm.execute(commands.ping()), m.Pong())
        cal = self.cm.execute(commands.cal_get())
        self.assertIsInstance(cal, m.CalReply)

    def test_events_streamed(self):
        self.cm.connect(self.server.host, self.server.port)
        upload_netlist(self.cm, DEFAULT_NETS)
        self.assertEqual(self.cm.execute(commands.cont_run(ContMode.VERIFY)),
                         m.Ok("started"))
        deadline = time.time() + 5
        while not any(isinstance(e, m.Done) for e in self.events):
            self.assertLess(time.time(), deadline)
            time.sleep(0.01)
        conts = [e for e in self.events if isinstance(e, m.ContResult)]
        self.assertEqual(len(conts), 6)

    def test_netlist_get_multi_line_reply(self):
        self.cm.connect(self.server.host, self.server.port)
        self.assertEqual(self.cm.execute(commands.netlist_begin(2)), m.Ok())
        self.assertEqual(self.cm.execute(commands.netlist_add(5, 9)), m.Ok())
        self.assertEqual(self.cm.execute(commands.netlist_add(7, 11)), m.Ok())
        self.assertEqual(self.cm.execute(commands.netlist_end()), m.Ok("loaded=2"))
        self.assertEqual(self.cm.netlist_get(), [m.NetEntry(5, 9), m.NetEntry(7, 11)])

    def test_disconnect(self):
        self.cm.connect(self.server.host, self.server.port)
        self.cm.disconnect()
        self.assertEqual(self.cm.state, LinkState.DISCONNECTED)
        with self.assertRaises(NotConnectedError):
            self.cm.execute(commands.ping())


class TestCommandTimeout(unittest.TestCase):
    """3.5.1: no reply within the timeout -> surfaced, link -> unknown."""

    def test_silent_instrument_times_out(self):
        # Replies to STATUS (so connect succeeds), then never replies again.
        def handler(client, line):
            if "STATUS" in line:
                return "<STATUS state=idle fixture=none hv_mv=0"
            return None  # silence

        server = StubServer(handler).start()
        try:
            cm = make_manager()
            cm.connect(server.host, server.port)
            with self.assertRaises(CommandTimeoutError):
                cm.execute(commands.ping())
            # A lost reply breaks reply ordering: degrade to unknown.
            self.assertEqual(cm.state, LinkState.LINK_LOST)
            with self.assertRaises(LinkLostError):
                cm.execute(commands.ping())
            cm.disconnect()
        finally:
            server.stop()


class TestSendFailure(unittest.TestCase):
    """GUI-01 (brief 8.4 finding 1): a send() that raises OSError must
    surface LinkLostError and drop the link — not deadlock the caller.

    Regression: _link_lost was invoked with _io_lock held; the lock is not
    reentrant, so execute() hung forever on the ordinary plug-pull path.
    The execute call runs in a thread so a regression fails this test
    instead of hanging the suite.
    """

    def test_send_failure_raises_and_drops_link(self):
        class FlakySendTransport(TcpTransport):
            armed = False

            def send(self, data):
                if self.armed:
                    raise OSError("port vanished mid-command")
                super().send(data)

        def handler(client, line):
            if "STATUS" in line:
                return "<STATUS state=idle fixture=none hv_mv=0"
            if "PING" in line:
                return "<PONG"
            return None

        server = StubServer(handler).start()
        transport = FlakySendTransport()
        try:
            cm = make_manager(transport_factory=lambda: transport)
            cm.connect(server.host, server.port)
            self.assertEqual(cm.execute(commands.ping()), m.Pong())

            transport.armed = True
            outcome = []

            def call():
                try:
                    cm.execute(commands.ping())
                    outcome.append("returned")
                except Exception as exc:
                    outcome.append(exc)

            t = threading.Thread(target=call, daemon=True)
            t.start()
            t.join(timeout=10 * CMD_TIMEOUT)
            self.assertFalse(t.is_alive(), "execute() deadlocked on send failure")
            self.assertEqual(len(outcome), 1)
            self.assertIsInstance(outcome[0], LinkLostError)
            self.assertEqual(cm.state, LinkState.LINK_LOST)
            cm.disconnect()
        finally:
            server.stop()


class TestLinkLoss(unittest.TestCase):
    """3.5.3: port closes, or no traffic for the link timeout."""

    def test_silence_trips_watchdog(self):
        # Answers commands but never says anything on its own.
        def handler(client, line):
            if "STATUS" in line:
                return "<STATUS state=idle fixture=none hv_mv=0"
            if "PING" in line:
                return "<PONG"
            return None

        server = StubServer(handler).start()
        states = []
        try:
            cm = make_manager(on_link_state=lambda s, d: states.append((s, d)))
            cm.connect(server.host, server.port)
            cm.execute(commands.ping())
            deadline = time.time() + 10 * LINK_TIMEOUT
            while cm.state is LinkState.CONNECTED:
                self.assertLess(time.time(), deadline, "watchdog never fired")
                time.sleep(0.02)
            self.assertEqual(cm.state, LinkState.LINK_LOST)
            self.assertTrue(any(s is LinkState.LINK_LOST for s, _ in states))
            cm.disconnect()
        finally:
            server.stop()

    def test_mid_run_disconnect(self):
        # The disconnect scenario: transport drops mid-run without !DONE.
        server = SimulatorServer(make_scenario("disconnect", 6), port=0,
                                 interval=0.01).start()
        states = []
        events = []
        try:
            cm = make_manager(on_event=events.append,
                              on_link_state=lambda s, d: states.append((s, d)))
            cm.connect(server.host, server.port)
            upload_netlist(cm, DEFAULT_NETS)
            cm.execute(commands.cont_run(ContMode.VERIFY))
            deadline = time.time() + 5
            while cm.state is LinkState.CONNECTED:
                self.assertLess(time.time(), deadline)
                time.sleep(0.01)
            self.assertEqual(cm.state, LinkState.LINK_LOST)
            # Partial results arrived, then the link dropped: state unknown.
            self.assertTrue(any(isinstance(e, m.ContResult) for e in events))
            self.assertFalse(any(isinstance(e, m.Done) for e in events))
            with self.assertRaises(LinkLostError):
                cm.execute(commands.ping())

            # 3.5.4: reconnect re-issues STATUS before controls come back.
            status = cm.connect(server.host, server.port)
            self.assertIsInstance(status, m.StatusReply)
            self.assertEqual(cm.state, LinkState.CONNECTED)
            self.assertEqual(cm.execute(commands.ping()), m.Pong())
            cm.disconnect()
        finally:
            server.stop()


class TestMalformed(unittest.TestCase):
    def test_garbage_line_is_surfaced_not_fatal(self):
        def handler(client, line):
            if "STATUS" in line:
                return "<STATUS state=idle fixture=none hv_mv=0"
            if "PING" in line:
                client.sendall(b"this is not protocol\n")  # no valid prefix
                return "<PONG"
            return None

        server = StubServer(handler).start()
        errors = []
        try:
            cm = make_manager(on_protocol_error=lambda r, e: errors.append((r, e)))
            cm.connect(server.host, server.port)
            self.assertEqual(cm.execute(commands.ping()), m.Pong())
            self.assertEqual(len(errors), 1)
            self.assertIn("not protocol", errors[0][0])
            self.assertEqual(cm.state, LinkState.CONNECTED)
            cm.disconnect()
        finally:
            server.stop()


class TestSessionLog(unittest.TestCase):
    """3.5.5: every line sent and received lands in the session file."""

    def test_log_records_both_directions(self):
        import tempfile
        from pathlib import Path

        server = SimulatorServer(make_scenario("pass", 4), port=0,
                                 interval=0.0).start()
        try:
            with tempfile.TemporaryDirectory() as tmp:
                cm = make_manager(log_dir=tmp)
                cm.connect(server.host, server.port)
                cm.execute(commands.ping())
                cm.disconnect()
                logs = list(Path(tmp).glob("session-*.log"))
                self.assertEqual(len(logs), 1)
                text = logs[0].read_text()
                self.assertIn("[tx] >PING", text)
                self.assertIn("[rx] <PONG", text)
                self.assertIn("[gui]", text)  # connect/disconnect meta lines
        finally:
            server.stop()


if __name__ == "__main__":
    unittest.main()
