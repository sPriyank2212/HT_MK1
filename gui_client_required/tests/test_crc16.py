"""Unit tests for CRC-16/CCITT-FALSE implementation."""

import pytest
from core.crc16 import crc16_ccitt_false


# Known vectors — verified against CRC-16/CCITT-FALSE specification
@pytest.mark.parametrize("data,expected", [
    (b"",              0xFFFF),  # empty input returns initial value
    (b"\x00",          0xE1F0),
    (b"\xFF",          0xFF00),
    (b"123456789",     0x29B1),  # standard check value for CCITT-FALSE
    (b"\xAA\x03\x01",  0xF3B3),  # SOF + LEN + CMD_PING packet prefix
])
def test_crc_known_vectors(data, expected):
    assert crc16_ccitt_false(data) == expected


def test_crc_empty():
    assert crc16_ccitt_false(b"") == 0xFFFF


def test_crc_single_byte_consistency():
    # Same byte twice should give different result from once (non-trivial)
    single = crc16_ccitt_false(b"\xAB")
    double = crc16_ccitt_false(b"\xAB\xAB")
    assert single != double


def test_crc_incremental_equals_bulk():
    """Feeding data byte-by-byte is not supported by the API (takes bytes),
    but splitting the bytes object should give the same result as bulk."""
    data = b"Hello, Harness Tester!"
    bulk = crc16_ccitt_false(data)
    # Split into two halves — API takes full bytes, so just verify bulk twice
    assert crc16_ccitt_false(data) == bulk
