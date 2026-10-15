"""Codec conformance tests: byte-exact commands and strict parsing (3.1-3.4)."""

import unittest

from htproto import commands, parse_line, LineFramer, ProtocolError
from htproto import messages as m
from htproto.codec import ContMode, ContStatus, Fixture, InsulStatus, ResStatus, State, TestKind


class TestCommandEncoding(unittest.TestCase):
    """Every command in section 3.2, byte-for-byte including '>' and '\\n'."""

    def test_exact_bytes(self):
        cases = [
            (commands.ping(), b">PING\n"),
            (commands.identify(), b">ID\n"),
            (commands.status(), b">STATUS\n"),
            (commands.safe(), b">SAFE\n"),
            (commands.abort(), b">ABORT\n"),
            (commands.netlist_begin(3), b">NETLIST BEGIN 3\n"),
            (commands.netlist_add(10, 20), b">NETLIST ADD 10 20\n"),
            (commands.netlist_end(), b">NETLIST END\n"),
            (commands.netlist_get(), b">NETLIST GET\n"),
            (commands.cont_run(ContMode.VERIFY), b">CONT RUN verify\n"),
            (commands.cont_run(ContMode.DISCOVER), b">CONT RUN discover\n"),
            (commands.res_run(), b">RES RUN\n"),
            (commands.insul_arm(), b">INSUL ARM\n"),
            (commands.insul_run(), b">INSUL RUN\n"),
            (commands.hv_set(0), b">HV SET 0\n"),
            (commands.hv_set(500000), b">HV SET 500000\n"),
            (commands.fixture(Fixture.NONE), b">FIXTURE none\n"),
            (commands.fixture(Fixture.MTX), b">FIXTURE mtx\n"),
            (commands.fixture(Fixture.HV), b">FIXTURE hv\n"),
            (commands.manual_path(1, 2), b">MANUAL PATH 1 2\n"),
            (commands.manual_relay(0, 3, True), b">MANUAL RELAY 0 3 1\n"),
            (commands.manual_relay(2, 15, False), b">MANUAL RELAY 2 15 0\n"),
            (commands.manual_off(), b">MANUAL OFF\n"),
            (commands.cal_get(), b">CAL GET\n"),
            (commands.limits_get(), b">LIMITS GET\n"),
            (commands.limits_set(1000, 100),
             b">LIMITS SET r_max_mohm=1000 ins_min_mohm=100\n"),
        ]
        for got, want in cases:
            with self.subTest(want=want):
                self.assertEqual(got, want)

    def test_rejects_bad_arguments(self):
        for bad in (-1, 1.5, "3", True, None):
            with self.subTest(bad=bad):
                with self.assertRaises(ProtocolError):
                    commands.hv_set(bad)
        with self.assertRaises(ProtocolError):
            commands.cont_run("Verify")  # not a ContMode

    def test_pin_range(self):
        # 8.1 answer 1: pins are 1-based, valid range 1..256.
        self.assertEqual(commands.netlist_add(1, 256), b">NETLIST ADD 1 256\n")
        self.assertEqual(commands.manual_path(256, 1), b">MANUAL PATH 256 1\n")
        for bad in (0, 257, -1):
            with self.subTest(bad=bad):
                with self.assertRaises(ProtocolError):
                    commands.netlist_add(bad, 5)
                with self.assertRaises(ProtocolError):
                    commands.manual_path(5, bad)


class TestReplyParsing(unittest.TestCase):
    def test_pong(self):
        self.assertEqual(parse_line("<PONG"), m.Pong())

    def test_id(self):
        self.assertEqual(parse_line("<ID HT_MK1 fw=1.4.2 proto=1"),
                         m.IdReply(fw="1.4.2", proto=1))

    def test_status(self):
        self.assertEqual(parse_line("<STATUS state=hv_armed fixture=hv hv_mv=500000"),
                         m.StatusReply(State.HV_ARMED, Fixture.HV, 500000))

    def test_ok_variants(self):
        self.assertEqual(parse_line("<OK"), m.Ok(""))
        self.assertEqual(parse_line("<OK started"), m.Ok("started"))
        self.assertEqual(parse_line("<OK armed"), m.Ok("armed"))
        self.assertEqual(parse_line("<OK loaded=12"), m.Ok("loaded=12"))

    def test_err(self):
        self.assertEqual(parse_line("<ERR EFIXTURE harness is on the matrix fixture"),
                         m.ErrReply("EFIXTURE", "harness is on the matrix fixture"))

    def test_netlist(self):
        self.assertEqual(parse_line("<NETLIST 2"), m.NetlistReply(2))
        self.assertEqual(parse_line("<NET 5 9"), m.NetEntry(5, 9))

    def test_cal(self):
        self.assertEqual(parse_line("<CAL current_ua=1000 gain=16 rref_mohm=100000"),
                         m.CalReply(1000, 16, 100000))

    def test_limits(self):
        self.assertEqual(parse_line("<LIMITS r_max_mohm=1000 ins_min_mohm=100"),
                         m.LimitsReply(1000, 100))


class TestEventParsing(unittest.TestCase):
    def test_progress(self):
        self.assertEqual(parse_line("!PROGRESS 37 256"), m.Progress(37, 256))

    def test_cont(self):
        self.assertEqual(parse_line("!CONT 1 2 pass"), m.ContResult(1, 2, ContStatus.PASS))
        self.assertEqual(parse_line("!CONT 3 4 open"), m.ContResult(3, 4, ContStatus.OPEN))
        self.assertEqual(parse_line("!CONT 5 6 short"), m.ContResult(5, 6, ContStatus.SHORT))

    def test_res(self):
        self.assertEqual(parse_line("!RES 1 2 48 pass"), m.ResResult(1, 2, 48, ResStatus.PASS))
        self.assertEqual(parse_line("!RES 3 4 2500 fail_high"),
                         m.ResResult(3, 4, 2500, ResStatus.FAIL_HIGH))
        self.assertEqual(parse_line("!RES 5 6 2 fail_low"),
                         m.ResResult(5, 6, 2, ResStatus.FAIL_LOW))

    def test_insul(self):
        self.assertEqual(parse_line("!INSUL 7 500 pass"), m.InsulResult(7, 500, InsulStatus.PASS))
        self.assertEqual(parse_line("!INSUL 8 5 fail"), m.InsulResult(8, 5, InsulStatus.FAIL))

    def test_fault(self):
        self.assertEqual(parse_line("!FAULT F04 insulation low on net 37"),
                         m.Fault("F04", "insulation low on net 37"))

    def test_done(self):
        self.assertEqual(parse_line("!DONE cont 11 1"), m.Done(TestKind.CONT, 11, 1))
        self.assertEqual(parse_line("!DONE res 0 12"), m.Done(TestKind.RES, 0, 12))
        self.assertEqual(parse_line("!DONE insul 12 0"), m.Done(TestKind.INSUL, 12, 0))

    def test_state_fixture_hv_safe(self):
        self.assertEqual(parse_line("!STATE running"), m.StateEvent(State.RUNNING))
        self.assertEqual(parse_line("!FIXTURE mtx"), m.FixtureEvent(Fixture.MTX))
        self.assertEqual(parse_line("!HV 500000"), m.HvEvent(500000))
        self.assertEqual(parse_line("!SAFE"), m.SafeEvent())

    def test_signed_measurement_values(self):
        # Brief 8.4 finding 2 (GUI-02): the firmware prints these with %ld
        # from int32_t; a negative reading is a legal wire value.
        self.assertEqual(parse_line("!RES 12 34 -5 pass"),
                         m.ResResult(12, 34, -5, ResStatus.PASS))
        self.assertEqual(parse_line("!INSUL 3 -5 fail"),
                         m.InsulResult(3, -5, InsulStatus.FAIL))
        self.assertEqual(parse_line("!HV -1"), m.HvEvent(-1))
        self.assertEqual(parse_line("<STATUS state=idle fixture=mtx hv_mv=-5"),
                         m.StatusReply(State.IDLE, Fixture.MTX, -5))
        self.assertEqual(parse_line("<LIMITS r_max_mohm=-1 ins_min_mohm=100"),
                         m.LimitsReply(-1, 100))

    def test_log_line(self):
        self.assertEqual(parse_line("# boot ok, cards: mtx=1 hv=2"),
                         m.LogLine(" boot ok, cards: mtx=1 hv=2"))


class TestMalformed(unittest.TestCase):
    """Anything off-contract must raise ProtocolError, never parse silently."""

    def test_bad(self):
        bad = [
            "",
            "PONG",                 # missing prefix
            "?PONG",                # unknown prefix
            "<PONG ",               # extra field (trailing space)
            "<PONG extra",
            "<ID HT_MK1 fw=1.4.2",  # missing proto field
            "<ID OTHER fw=1.0.0 proto=1",
            "<ID HT_MK1 proto=1 fw=1.4.2",   # reordered fields
            "<ID HT_MK1 fw=14 proto=1",      # not semver
            "<STATUS fixture=mtx state=idle hv_mv=0",  # reordered
            "<STATUS state=bogus fixture=mtx hv_mv=0",
            "<STATUS state=idle fixture=mtx hv_mv=5 ",  # extra field
            "<NET 1",               # missing field
            "<NET 1 2 3",           # extra field
            "<NET -1 2",            # pins stay unsigned
            "<CAL gain=16 current_ua=1000 rref_mohm=100000",  # reordered
            "<LIMITS r_max_mohm=abc ins_min_mohm=100",
            "<WAT 1 2 3",
            "!PROGRESS 1",          # missing total
            "!PROGRESS 1 2 3",      # extra field
            "!PROGRESS -1 256",     # progress stays unsigned
            "!CONT -1 2 pass",      # pins stay unsigned
            "!CONT 1 2 connected",  # status not in contract
            "!CONT 1 2 PASS",       # case-sensitive
            "!RES 1 2 48 fail",     # not a ResStatus
            "!INSUL 7 500 ok",
            "!DONE cont 1",         # missing count
            "!DONE continuity 1 0", # kind not in contract
            "!STATE online",
            "!FIXTURE matrix",
            "!HV 5V",
            "!SAFE now",
            "!FAULT F04",           # code but no text
        ]
        for line in bad:
            with self.subTest(line=line):
                with self.assertRaises(ProtocolError):
                    parse_line(line)


class TestFramer(unittest.TestCase):
    def test_split_across_chunks(self):
        f = LineFramer()
        self.assertEqual(f.feed(b"<PO"), [])
        self.assertEqual(f.feed(b"NG\n!SA"), ["<PONG"])
        self.assertEqual(f.feed(b"FE\n"), ["!SAFE"])
        self.assertEqual(f.pending, b"")

    def test_multiple_lines_one_chunk(self):
        f = LineFramer()
        self.assertEqual(f.feed(b"<OK\n!HV 500000\n# hi\n"),
                         ["<OK", "!HV 500000", "# hi"])

    def test_crlf_tolerated(self):
        f = LineFramer()
        self.assertEqual(f.feed(b"<PONG\r\n"), ["<PONG"])


if __name__ == "__main__":
    unittest.main()
