"""Unit tests for packet encode / decode round-trip."""

import pytest
from core.packet_codec import encode_packet, PacketDecoder, SOF
from core.data_types import Cmd, Rsp


# ---------------------------------------------------------------------------
# encode_packet
# ---------------------------------------------------------------------------

def test_encode_starts_with_sof():
    frame = encode_packet(Cmd.PING)
    assert frame[0] == SOF


def test_encode_length_byte():
    payload = b"\x01\x02\x03"
    frame = encode_packet(Cmd.GET_STATUS, payload)
    assert frame[1] == len(payload)


def test_encode_cmd_byte():
    frame = encode_packet(Cmd.ABORT)
    assert frame[2] == Cmd.ABORT


def test_encode_no_payload_total_length():
    # SOF(1) + LEN(1) + CMD(1) + CRC(2) = 5
    frame = encode_packet(Cmd.PING)
    assert len(frame) == 5


def test_encode_with_payload_total_length():
    payload = b"\xDE\xAD\xBE\xEF"
    frame = encode_packet(Cmd.SET_PARAM, payload)
    assert len(frame) == 5 + len(payload)


def test_encode_payload_too_large_raises():
    with pytest.raises(ValueError):
        encode_packet(Cmd.SET_NETLIST, bytes(256))


# ---------------------------------------------------------------------------
# PacketDecoder — happy path
# ---------------------------------------------------------------------------

def _collect_packets(frames: bytes):
    received = []
    decoder = PacketDecoder(on_packet=lambda cmd, pl: received.append((cmd, pl)))
    decoder.feed(frames)
    return received


def test_decode_ping_no_payload():
    frame = encode_packet(Cmd.PING)
    packets = _collect_packets(frame)
    assert len(packets) == 1
    assert packets[0] == (Cmd.PING, b"")


def test_decode_with_payload():
    payload = b"\x01\x02\x03\x04"
    frame = encode_packet(Cmd.SET_PARAM, payload)
    packets = _collect_packets(frame)
    assert packets[0] == (Cmd.SET_PARAM, payload)


def test_decode_all_commands():
    for cmd in Cmd:
        frame = encode_packet(int(cmd), b"\xAB")
        packets = _collect_packets(frame)
        assert packets[0][0] == int(cmd)


def test_decode_two_packets_in_sequence():
    frame = encode_packet(Cmd.PING) + encode_packet(Cmd.GET_STATUS)
    packets = _collect_packets(frame)
    assert len(packets) == 2
    assert packets[0][0] == Cmd.PING
    assert packets[1][0] == Cmd.GET_STATUS


def test_decode_fragmented_input():
    """Bytes arriving in small chunks must still decode correctly."""
    frame = encode_packet(Cmd.ABORT, b"\xFF\xFE")
    received = []
    decoder = PacketDecoder(on_packet=lambda cmd, pl: received.append((cmd, pl)))
    for byte in frame:
        decoder.feed(bytes([byte]))
    assert len(received) == 1
    assert received[0] == (Cmd.ABORT, b"\xFF\xFE")


def test_decode_garbage_before_sof_is_ignored():
    garbage = b"\x00\x11\x22\x33"
    frame = encode_packet(Cmd.PING)
    packets = _collect_packets(garbage + frame)
    assert len(packets) == 1
    assert packets[0][0] == Cmd.PING


# ---------------------------------------------------------------------------
# PacketDecoder — CRC error
# ---------------------------------------------------------------------------

def test_crc_mismatch_not_delivered():
    frame = bytearray(encode_packet(Cmd.PING))
    frame[-1] ^= 0xFF  # corrupt last CRC byte
    received = []
    decoder = PacketDecoder(on_packet=lambda cmd, pl: received.append((cmd, pl)))
    decoder.feed(bytes(frame))
    assert received == []


def test_crc_error_callback_called():
    frame = bytearray(encode_packet(Cmd.PING))
    frame[-1] ^= 0xFF
    errors = []
    decoder = PacketDecoder(
        on_packet=lambda cmd, pl: None,
        on_crc_error=lambda cmd, pl: errors.append(cmd),
    )
    decoder.feed(bytes(frame))
    assert len(errors) == 1
    assert errors[0] == Cmd.PING
