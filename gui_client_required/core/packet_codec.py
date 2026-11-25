"""UART packet encode / decode for the Harness Tester protocol.

Packet frame (SRS COMM-PKT-001):
  [SOF 0xAA] [LEN 1B] [CMD 1B] [PAYLOAD 0..255 B] [CRC_HI] [CRC_LO]
  CRC covers CMD + PAYLOAD (not SOF, not LEN).
"""

from __future__ import annotations
from typing import Callable
from .crc16 import crc16_ccitt_false

SOF = 0xAA
MAX_PAYLOAD = 255


def encode_packet(cmd: int, payload: bytes = b"") -> bytes:
    if len(payload) > MAX_PAYLOAD:
        raise ValueError(f"Payload too large: {len(payload)} > {MAX_PAYLOAD}")
    crc_data = bytes([cmd]) + payload
    crc = crc16_ccitt_false(crc_data)
    return bytes([SOF, len(payload), cmd]) + payload + bytes([crc >> 8, crc & 0xFF])


class PacketDecoder:
    """Stateful byte-stream decoder. Call feed() with raw bytes; completed
    packets are delivered via the on_packet callback(cmd, payload)."""

    _S_WAIT_SOF = 0
    _S_WAIT_LEN = 1
    _S_WAIT_CMD = 2
    _S_PAYLOAD  = 3
    _S_CRC_HI   = 4
    _S_CRC_LO   = 5

    def __init__(self, on_packet: Callable[[int, bytes], None],
                 on_crc_error: Callable[[int, bytes], None] | None = None):
        self._on_packet = on_packet
        self._on_crc_error = on_crc_error
        self._state = self._S_WAIT_SOF
        self._len = 0
        self._cmd = 0
        self._payload = bytearray()
        self._crc_hi = 0

    def feed(self, data: bytes) -> None:
        for byte in data:
            self._process(byte)

    def _process(self, byte: int) -> None:  # noqa: C901
        s = self._state
        if s == self._S_WAIT_SOF:
            if byte == SOF:
                self._state = self._S_WAIT_LEN
        elif s == self._S_WAIT_LEN:
            self._len = byte
            self._payload = bytearray()
            self._state = self._S_WAIT_CMD
        elif s == self._S_WAIT_CMD:
            self._cmd = byte
            if self._len == 0:
                self._state = self._S_CRC_HI
            else:
                self._state = self._S_PAYLOAD
        elif s == self._S_PAYLOAD:
            self._payload.append(byte)
            if len(self._payload) == self._len:
                self._state = self._S_CRC_HI
        elif s == self._S_CRC_HI:
            self._crc_hi = byte
            self._state = self._S_CRC_LO
        elif s == self._S_CRC_LO:
            received_crc = (self._crc_hi << 8) | byte
            crc_data = bytes([self._cmd]) + self._payload
            expected_crc = crc16_ccitt_false(crc_data)
            self._state = self._S_WAIT_SOF
            if received_crc == expected_crc:
                self._on_packet(self._cmd, bytes(self._payload))
            elif self._on_crc_error:
                self._on_crc_error(self._cmd, bytes(self._payload))
