"""The virtual tester (demo build) speaks the firmware's protocol, and Start Test
uploads channels, not connector pins."""

import json
import random
import struct
import time

import pytest
from PyQt6.QtCore import QCoreApplication

from core.data_types import Cmd, Rsp, TestModes
from core.netlist import Net, NetPin, Netlist, apply_connector_config
from core.packet_codec import PacketDecoder, encode_packet
from core.pinmap import Channel, write_pinmap_xlsx
from core.test_engine import TestEngine
from core.virtual_device import VirtualHarness, VirtualTester


class Link:
    """Drives a VirtualTester the way SerialWorker does and collects what it says."""

    def __init__(self, tester: VirtualTester):
        self.tester = tester.open()
        self.packets: list[tuple[int, bytes]] = []
        self._dec = PacketDecoder(lambda c, p: self.packets.append((c, p)))

    def send(self, cmd, payload=b""):
        self.tester.write(encode_packet(cmd, payload))
        return self

    def wait_done(self, timeout=5.0):
        t0 = time.time()
        while not self.of(Rsp.SCAN_DONE):
            self.pump()
            assert time.time() - t0 < timeout, "scan never finished"
            time.sleep(0.002)
        return self

    def pump(self):
        data = self.tester.read(self.tester.in_waiting)
        self._dec.feed(data)

    def of(self, rsp):
        self.pump()
        return [p for c, p in self.packets if c == rsp]

    def results(self):
        return [struct.unpack(">BBIB", p) for p in self.of(Rsp.RESULT_CONT)]


def netlist_bytes(*nets):
    return json.dumps({"nets": [{"name": f"N{i}", "pins": [{"n": n, "l": ""} for n in pins]}
                                for i, pins in enumerate(nets, 1)]}).encode()


def make_tester(wires=None):
    t = VirtualTester(step_s=0.0)
    if wires is not None:
        t.harness.set_wires(wires)
    return t


def test_ping_status_and_unknown_command():
    link = Link(make_tester())
    link.send(Cmd.PING).send(Cmd.GET_STATUS).send(0x7E)
    assert len(link.of(Rsp.ACK)) == 1 and len(link.of(Rsp.NACK)) == 1
    state, flags, major, minor, patch, cal = struct.unpack_from(">BBBBBH", link.of(Rsp.STATUS)[0], 0)
    assert (state, (major, minor, patch), cal) == (0, (2, 2, 0), 120)


def test_netlist_upload_in_chunks_then_continuity():
    link = Link(make_tester([(1, 1), (2, 2), (3, 9)]))
    data = netlist_bytes([1, 1], [2, 2], [3, 9], [4, 4])        # A4->B4 is not plugged in
    chunks = [data[i:i + 20] for i in range(0, len(data), 20)]
    for seq, c in enumerate(chunks):
        link.send(Cmd.SET_NETLIST, struct.pack(">HH", seq, len(chunks)) + c)
    assert len(link.of(Rsp.ACK)) == len(chunks)
    link.send(Cmd.START_CONT).wait_done()
    assert link.results() == [(1, 1, 500, 0), (2, 2, 500, 0), (3, 9, 500, 0), (4, 4, 500000, 1)]
    assert struct.unpack(">HHH", link.of(Rsp.SCAN_DONE)[0]) == (4, 3, 1)
    assert struct.unpack(">HH", link.of(Rsp.PROGRESS)[-1]) == (4, 4)


def test_bad_netlist_chunk_is_refused():
    link = Link(make_tester())
    link.send(Cmd.SET_NETLIST, b"\x00")                          # too short
    link.send(Cmd.SET_NETLIST, struct.pack(">HH", 5, 3))         # seq >= total
    link.send(Cmd.SET_NETLIST, struct.pack(">HH", 0, 0))         # no chunks
    assert len(link.of(Rsp.NACK)) == 3


def test_no_netlist_scans_37_straight_pairs():
    link = Link(make_tester())
    link.send(Cmd.START_CONT).wait_done()
    assert [(a, b) for a, b, *_ in link.results()] == [(i, i) for i in range(1, 38)]


def test_cannot_start_a_second_scan_or_calibrate_while_scanning():
    t = VirtualTester(step_s=0.05)
    link = Link(t)
    link.send(Cmd.START_CONT)
    link.send(Cmd.START_CONT).send(Cmd.CALIBRATE)
    assert len(link.of(Rsp.NACK)) == 2
    link.send(Cmd.ABORT)
    link.wait_done()


def test_calibrate_acks_the_offset():
    link = Link(VirtualTester(step_s=0.0))
    link.send(Cmd.CALIBRATE)
    t0 = time.time()
    while not link.of(Rsp.ACK) and time.time() - t0 < 3:
        time.sleep(0.02)
    assert struct.unpack(">H", link.of(Rsp.ACK)[0]) == (120,)


def test_cross_continuity_reports_every_pair_with_all_four_statuses():
    t = make_tester([(1, 1), (2, 2)])
    t.harness.inject_open(1)                                     # one of the two wires breaks
    broken = t.harness.open_wires[0]
    t.harness._extra.append((5, 6))                              # a stray wire
    link = Link(t)
    link.send(Cmd.SET_NETLIST, struct.pack(">HH", 0, 1) + netlist_bytes([1, 1], [2, 2]))
    link.send(Cmd.START_CROSS_CONT).wait_done()
    res = {(a, b): s for a, b, _r, s in link.results()}
    assert len(res) == 37 * 37
    good = ({(1, 1), (2, 2)} - {broken}).pop()
    assert res[good] == 0 and res[broken] == 1 and res[(5, 6)] == 2 and res[(9, 9)] == 3
    assert (3, 3) in res and res[(2, 1)] == 3                    # no "reversed pair is expected" quirk


def test_auto_scan_reports_only_what_is_plugged_in():
    link = Link(make_tester([(1, 5), (2, 7), (2, 8)]))                # (2,7) and (2,8): a Y joint
    link.send(Cmd.AUTO_SCAN).wait_done()
    assert sorted((a, b) for a, b, _r, s in link.results() if s == 0) == [(1, 5), (2, 7), (2, 8)]
    assert struct.unpack(">HHH", link.of(Rsp.SCAN_DONE)[0]) == (3, 3, 0)


def test_stray_wire_joins_nets_like_the_real_thing():
    h = VirtualHarness(random.Random(1))
    h.set_wires([(1, 1), (2, 2)])
    h._extra.append((1, 2))                                      # A1 now also reaches B2, and A2 reaches B1
    assert h.connections() == {1: {1, 2}, 2: {1, 2}}


def test_faults_are_cleared_when_a_new_harness_is_plugged_in():
    h = VirtualHarness(random.Random(2))
    h.set_wires([(i, i) for i in range(1, 6)])
    assert len(h.inject_open(2)) == 2 and len(h.inject_miswire(1)) == 1 and h.has_faults
    h.clear_faults()
    assert not h.has_faults and h.connections()[3] == {3}
    h.inject_open(1)
    h.set_wires([(1, 1)])
    assert not h.has_faults


def test_start_test_uploads_channels_not_connector_pins(tmp_path):
    """The netlist file says J1 pin 20 -> X2 pin 5 (connector pins); the tester has to be
    told channel 20 -> channel 20, as resolved through the config."""
    rows = [Channel(i, "J1", "J1", i, connector_id_b="X1" if i <= 15 else "X2",
                    dest_pin=i if i <= 15 else i - 15) for i in range(1, 31)]
    cfg = str(tmp_path / "cfg.xlsx")
    write_pinmap_xlsx(cfg, rows)
    nl = Netlist(nets=[Net("W1", [NetPin(20), NetPin(5)], connector_id="J1", connector_id_b="X2")])
    apply_connector_config(nl, cfg)
    assert [p.number for p in nl.nets[0].pins] == [20, 20]       # J1 pin 20 -> X2 pin 5 = channel 20

    QCoreApplication.instance() or QCoreApplication([])
    t = VirtualTester(step_s=0.0)
    link = Link(t)

    class Worker:                                                # what TestEngine needs of SerialWorker
        sent: list = []
        class Sig:
            def connect(self, *_): pass
        ackReceived = nackReceived = scanComplete = connectionLost = Sig()

        def send_packet(self, cmd, payload=b""):
            self.sent.append((cmd, payload))
            t.write(encode_packet(cmd, payload))

    w = Worker()
    eng = TestEngine(w)
    eng.start_test("netlist.xlsx", TestModes(), nl)
    uploaded = b"".join(p[4:] for c, p in w.sent if c == Cmd.SET_NETLIST)
    assert [(p["n"]) for net in json.loads(uploaded)["nets"] for p in net["pins"]] == [20, 20]
