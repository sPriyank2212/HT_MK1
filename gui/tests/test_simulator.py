"""Simulator integration tests: every command round-trips over a real socket,
and all five scenarios are reproducible (brief section 5, task 1)."""

import socket
import unittest

from htproto.codec import LineFramer
from htproto.simulator import SimulatorServer, make_scenario

NETS = 12


class Client:
    """Minimal line-based test client."""

    def __init__(self, host, port, timeout=5.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.framer = LineFramer()
        self._queue = []

    def send(self, data: bytes) -> None:
        self.sock.sendall(data)

    def readline(self) -> str | None:
        """One line without the newline; None on clean/forced close."""
        while not self._queue:
            try:
                data = self.sock.recv(4096)
            except (ConnectionResetError, OSError):
                return None
            if not data:
                return None
            self._queue.extend(self.framer.feed(data))
        return self._queue.pop(0)

    def readlines_until(self, prefix: str, limit: int = 5000) -> list[str]:
        out = []
        for _ in range(limit):
            line = self.readline()
            assert line is not None, f"connection closed before {prefix!r}"
            out.append(line)
            if line.startswith(prefix):
                return out
        raise AssertionError(f"no line starting {prefix!r} within {limit} lines")

    def exchange(self, command: bytes) -> str:
        """Send one command, return the next '<' reply (skipping events/logs)."""
        self.send(command)
        while True:
            line = self.readline()
            assert line is not None, f"connection closed awaiting reply to {command!r}"
            if line.startswith("<"):
                return line

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


class SimFixture(unittest.TestCase):
    scenario = "pass"

    @classmethod
    def setUpClass(cls):
        cls.server = SimulatorServer(make_scenario(cls.scenario, NETS),
                                     port=0, interval=0.0).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.stop()

    def setUp(self):
        self.client = Client(self.server.host, self.server.port)
        banner = self.client.readline()
        self.assertTrue(banner.startswith("#"), banner)  # display-only banner

    def tearDown(self):
        self.client.close()

    def upload_netlist(self, nets):
        self.assertEqual(self.client.exchange(
            f">NETLIST BEGIN {len(nets)}\n".encode()), "<OK")
        for hi, lo in nets:
            self.assertEqual(self.client.exchange(f">NETLIST ADD {hi} {lo}\n".encode()),
                             "<OK")
        self.assertEqual(self.client.exchange(b">NETLIST END\n"),
                         f"<OK loaded={len(nets)}")

    def upload_default_netlist(self):
        """The scenario harness as a netlist: (1,2), (3,4), ... """
        self.upload_netlist([(2 * i + 1, 2 * i + 2) for i in range(NETS)])


class TestCommandRoundTrips(SimFixture):
    """Each command in 3.2 produces its contract reply, byte-for-byte."""

    def test_ping_id_status(self):
        self.assertEqual(self.client.exchange(b">PING\n"), "<PONG")
        self.assertEqual(self.client.exchange(b">ID\n"), "<ID HT_MK1 fw=1.0.0 proto=1")
        self.assertEqual(self.client.exchange(b">STATUS\n"),
                         "<STATUS state=idle fixture=none hv_mv=0")

    def test_optional_prefix(self):
        # Appendix B: the leading '>' is optional (terminal bring-up).
        self.assertEqual(self.client.exchange(b"PING\n"), "<PONG")

    def test_safe_abort(self):
        self.assertEqual(self.client.exchange(b">SAFE\n"), "<OK")
        self.assertEqual(self.client.exchange(b">ABORT\n"), "<OK")

    def test_cal_and_limits(self):
        self.assertEqual(self.client.exchange(b">CAL GET\n"),
                         "<CAL current_ua=1000 gain=16 rref_mohm=100000")
        self.assertEqual(self.client.exchange(b">LIMITS GET\n"),
                         "<LIMITS r_max_mohm=1000 ins_min_mohm=100")
        self.assertEqual(self.client.exchange(
            b">LIMITS SET r_max_mohm=750 ins_min_mohm=250\n"), "<OK")
        self.assertEqual(self.client.exchange(b">LIMITS GET\n"),
                         "<LIMITS r_max_mohm=750 ins_min_mohm=250")

    def test_netlist_upload_download(self):
        self.assertEqual(self.client.exchange(b">NETLIST BEGIN 2\n"), "<OK")
        self.assertEqual(self.client.exchange(b">NETLIST ADD 1 2\n"), "<OK")
        self.assertEqual(self.client.exchange(b">NETLIST ADD 3 4\n"), "<OK")
        self.assertEqual(self.client.exchange(b">NETLIST END\n"), "<OK loaded=2")
        self.client.send(b">NETLIST GET\n")
        self.assertEqual(self.client.readline(), "<NETLIST 2")
        self.assertEqual(self.client.readline(), "<NET 1 2")
        self.assertEqual(self.client.readline(), "<NET 3 4")

    def test_fixture_command(self):
        self.assertEqual(self.client.exchange(b">FIXTURE mtx\n"), "<OK")
        self.assertEqual(self.client.exchange(b">STATUS\n"),
                         "<STATUS state=idle fixture=mtx hv_mv=0")

    def test_manual(self):
        self.assertEqual(self.client.exchange(b">MANUAL PATH 1 2\n"), "<OK")
        self.assertEqual(self.client.exchange(b">MANUAL OFF\n"), "<OK")

    def test_manual_relay_refused(self):
        # Refused by design (brief section 0): always ERR EHW.
        self.assertEqual(self.client.exchange(b">MANUAL RELAY 0 3 1\n"),
                         "<ERR EHW manual relay control refused by design")

    def test_hv_set_range(self):
        self.assertEqual(self.client.exchange(b">HV SET 600000\n").split(" ")[:2],
                         ["<ERR", "ERANGE"])

    def test_hv_set_requires_armed(self):
        # 8.1 answer 2: non-zero HV SET while not armed -> ENOTARMED; 0 is OK.
        reply = self.client.exchange(b">HV SET 500000\n")
        self.assertTrue(reply.startswith("<ERR ENOTARMED"), reply)
        self.assertEqual(self.client.exchange(b">HV SET 0\n"), "<OK")

    def test_hv_set_ramps(self):
        self.client.exchange(b">FIXTURE hv\n")
        self.client.exchange(b">INSUL ARM\n")
        self.assertEqual(self.client.exchange(b">HV SET 500000\n"), "<OK")
        lines = self.client.readlines_until("!HV 500000")
        self.assertTrue(all(l.startswith("!HV ") for l in lines))
        self.assertEqual(lines[-1], "!HV 500000")

    def test_insul_arm_requires_hv_fixture(self):
        reply = self.client.exchange(b">INSUL ARM\n")
        self.assertTrue(reply.startswith("<ERR EFIXTURE"), reply)
        self.client.exchange(b">FIXTURE mtx\n")
        reply = self.client.exchange(b">INSUL ARM\n")
        self.assertTrue(reply.startswith("<ERR EFIXTURE"), reply)
        self.client.exchange(b">FIXTURE hv\n")
        self.assertEqual(self.client.exchange(b">INSUL ARM\n"), "<OK armed")
        self.assertEqual(self.client.exchange(b">STATUS\n"),
                         "<STATUS state=hv_armed fixture=hv hv_mv=0")

    def test_insul_run_requires_armed(self):
        reply = self.client.exchange(b">INSUL RUN\n")
        self.assertTrue(reply.startswith("<ERR ENOTARMED"), reply)

    def test_pin_range(self):
        # 8.1 answer 1: pins are 1..256; out of range -> ERR ERANGE.
        self.assertEqual(self.client.exchange(b">NETLIST BEGIN 1\n"), "<OK")
        self.assertEqual(self.client.exchange(b">NETLIST ADD 0 5\n"),
                         "<ERR ERANGE pin out of range")
        self.assertEqual(self.client.exchange(b">NETLIST ADD 1 257\n"),
                         "<ERR ERANGE pin out of range")
        self.assertEqual(self.client.exchange(b">NETLIST ADD 1 256\n"), "<OK")
        self.assertEqual(self.client.exchange(b">MANUAL PATH 0 1\n"),
                         "<ERR ERANGE pin out of range")
        self.assertEqual(self.client.exchange(b">MANUAL PATH 1 256\n"), "<OK")

    def test_verify_without_netlist_refused(self):
        # 8.1 answer 4: no golden-harness fallback.
        self.assertEqual(self.client.exchange(b">CONT RUN verify\n"),
                         "<ERR ERANGE no netlist")

    def test_fixture_change_drops_arm(self):
        # 8.1 answer 6: fixture change forces safe; !HV 0 / !SAFE precede !FIXTURE.
        self.client.exchange(b">FIXTURE hv\n")
        self.assertEqual(self.client.exchange(b">INSUL ARM\n"), "<OK armed")
        self.assertEqual(self.client.exchange(b">HV SET 100000\n"), "<OK")
        self.client.readlines_until("!HV 100000")
        # The force-safe events precede the <OK reply, so read raw lines.
        self.client.send(b">FIXTURE mtx\n")
        lines = []
        while True:
            line = self.client.readline()
            self.assertIsNotNone(line)
            if line == "<OK":
                break
            lines.append(line)
        self.assertIn("!HV 0", lines)
        self.assertIn("!SAFE", lines)
        self.assertLess(lines.index("!HV 0"), lines.index("!SAFE"))
        self.assertLess(lines.index("!SAFE"), lines.index("!FIXTURE mtx"))
        # Arm is gone: insulation is locked again.
        reply = self.client.exchange(b">INSUL RUN\n")
        self.assertTrue(reply.startswith("<ERR ENOTARMED"), reply)
        self.assertEqual(self.client.exchange(b">STATUS\n"),
                         "<STATUS state=idle fixture=mtx hv_mv=0")

    def test_syntax_error(self):
        reply = self.client.exchange(b">FROBNICATE\n")
        self.assertTrue(reply.startswith("<ERR ESYNTAX"), reply)


class TestScenarioPass(SimFixture):
    scenario = "pass"

    def test_full_sequence(self):
        # The operator flow end to end: upload netlist, fixture mtx -> verify
        # -> resistance -> fixture hv -> arm -> insulation. Clean pass.
        self.upload_default_netlist()
        self.client.exchange(b">FIXTURE mtx\n")
        self.assertEqual(self.client.exchange(b">CONT RUN verify\n"), "<OK started")
        lines = self.client.readlines_until("!DONE")
        conts = [l for l in lines if l.startswith("!CONT ")]
        self.assertEqual(len(conts), NETS)
        self.assertTrue(all(l.endswith(" pass") for l in conts))
        self.assertEqual(lines[-1], f"!DONE cont {NETS} 0")
        self.assertIn(f"!PROGRESS {NETS} {NETS}", lines)

        self.assertEqual(self.client.exchange(b">RES RUN\n"), "<OK started")
        lines = self.client.readlines_until("!DONE")
        res = [l for l in lines if l.startswith("!RES ")]
        self.assertEqual(len(res), NETS)
        self.assertTrue(all(l.endswith(" pass") for l in res))
        self.assertEqual(lines[-1], f"!DONE res {NETS} 0")

        self.client.exchange(b">FIXTURE hv\n")
        self.assertEqual(self.client.exchange(b">INSUL ARM\n"), "<OK armed")
        self.assertEqual(self.client.exchange(b">INSUL RUN\n"), "<OK started")
        lines = self.client.readlines_until("!DONE")
        insul = [l for l in lines if l.startswith("!INSUL ")]
        self.assertEqual(len(insul), NETS)
        self.assertTrue(all(l.endswith(" pass") for l in insul))
        self.assertEqual(lines[-1], f"!DONE insul {NETS} 0")
        self.assertFalse(any(l.startswith("!FAULT") for l in lines))
        # 8.1 answer 7: discharge, !SAFE, !STATE idle, and !DONE always last.
        self.assertIn("!HV 0", lines)
        self.assertIn("!SAFE", lines)
        self.assertLess(lines.index("!HV 0"), lines.index("!SAFE"))
        self.assertLess(lines.index("!SAFE"), lines.index("!STATE idle"))
        self.assertEqual(self.client.exchange(b">STATUS\n"),
                         "<STATUS state=idle fixture=hv hv_mv=0")

    def test_discover(self):
        self.assertEqual(self.client.exchange(b">CONT RUN discover\n"), "<OK started")
        lines = self.client.readlines_until("!DONE", limit=10000)
        conts = [l for l in lines if l.startswith("!CONT ")]
        self.assertEqual(len(conts), NETS)
        self.assertEqual(lines[-1], f"!DONE cont {NETS} 0")
        self.assertIn("!PROGRESS 256 256", lines)

    def test_abort_mid_run(self):
        self.assertEqual(self.client.exchange(b">CONT RUN discover\n"), "<OK started")
        # 8.1 answer 3: ABORT replies immediately; the run then stops within
        # ~one measurement point and ends !SAFE, !STATE idle, !DONE (last).
        self.assertEqual(self.client.exchange(b">ABORT\n"), "<OK")
        lines = self.client.readlines_until("!DONE")
        self.assertIn("!SAFE", lines)
        self.assertLess(lines.index("!SAFE"), lines.index("!STATE idle"))
        self.assertTrue(lines[-1].startswith("!DONE cont "), lines[-1])
        status = self.client.exchange(b">STATUS\n")
        self.assertEqual(status, "<STATUS state=idle fixture=none hv_mv=0")


class TestScenarioOpensShorts(SimFixture):
    scenario = "opens_shorts"

    def test_two_opens_one_short(self):
        self.upload_default_netlist()
        self.assertEqual(self.client.exchange(b">CONT RUN verify\n"), "<OK started")
        lines = self.client.readlines_until("!DONE")
        conts = [l for l in lines if l.startswith("!CONT ")]
        self.assertEqual(sum(l.endswith(" open") for l in conts), 2)
        self.assertEqual(sum(l.endswith(" short") for l in conts), 1)
        self.assertEqual(sum(l.endswith(" pass") for l in conts), NETS - 3)
        self.assertEqual(lines[-1], f"!DONE cont {NETS - 3} 3")


class TestScenarioResFail(SimFixture):
    scenario = "res_fail"

    def test_resistance_failures(self):
        self.assertEqual(self.client.exchange(b">RES RUN\n"), "<OK started")
        lines = self.client.readlines_until("!DONE")
        res = [l for l in lines if l.startswith("!RES ")]
        self.assertEqual(sum(l.endswith(" fail_high") for l in res), 1)
        self.assertEqual(sum(l.endswith(" fail_low") for l in res), 1)
        self.assertEqual(sum(l.endswith(" pass") for l in res), NETS - 2)
        self.assertEqual(lines[-1], f"!DONE res {NETS - 2} 2")


class TestScenarioInsulFail(SimFixture):
    scenario = "insul_fail"

    def test_insulation_failure_with_fault(self):
        self.client.exchange(b">FIXTURE hv\n")
        self.client.exchange(b">INSUL ARM\n")
        self.assertEqual(self.client.exchange(b">INSUL RUN\n"), "<OK started")
        lines = self.client.readlines_until("!DONE")
        insul = [l for l in lines if l.startswith("!INSUL ")]
        self.assertEqual(sum(l.endswith(" fail") for l in insul), 1)
        faults = [l for l in lines if l.startswith("!FAULT ")]
        self.assertEqual(faults, ["!FAULT F04 insulation low on net 3"])
        self.assertEqual(lines[-1], f"!DONE insul {NETS - 1} 1")


class TestScenarioDisconnect(unittest.TestCase):
    """Mid-run disconnect: transport drops with no !DONE (3.5.3 test hook)."""

    def test_transport_drops_mid_run(self):
        server = SimulatorServer(make_scenario("disconnect", NETS), port=0,
                                 interval=0.001).start()
        try:
            client = Client(server.host, server.port)
            client.readline()  # banner
            client.exchange(f">NETLIST BEGIN {NETS}\n".encode())
            for i in range(NETS):
                client.exchange(f">NETLIST ADD {2 * i + 1} {2 * i + 2}\n".encode())
            client.exchange(b">NETLIST END\n")
            self.assertEqual(client.exchange(b">CONT RUN verify\n"), "<OK started")
            saw_cont = False
            while True:
                line = client.readline()
                if line is None:
                    break  # transport dropped
                if line.startswith("!CONT "):
                    saw_cont = True
                self.assertFalse(line.startswith("!DONE"),
                                 "disconnect scenario must never finish the run")
            self.assertTrue(saw_cont, "expected partial results before the drop")
            # Server keeps listening: a reconnect must succeed (3.5.4 path).
            client2 = Client(server.host, server.port)
            client2.readline()
            self.assertEqual(client2.exchange(b">STATUS\n").split(" ")[0], "<STATUS")
            client2.close()
            client.close()
        finally:
            server.stop()


if __name__ == "__main__":
    unittest.main()
