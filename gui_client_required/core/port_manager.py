"""Serial port discovery and ranking.

Enumeration is pulled out of the GUI thread because Windows COM enumeration
walks SetupAPI and can block for seconds when Bluetooth virtual ports are
present.  Ranking exists because plain enumeration order puts legacy ports
like COM1 first: COM1 opens successfully, never answers, and the connection
only fails eight seconds later on a missed-heartbeat timeout.
"""

from __future__ import annotations
from dataclasses import dataclass

from PyQt6.QtCore import QThread, pyqtSignal

try:
    import serial.tools.list_ports as _list_ports
    _SERIAL_AVAILABLE = True
except ImportError:            # pragma: no cover - pyserial always present in app
    _SERIAL_AVAILABLE = False


# Substrings that identify a USB-serial bridge worth talking to.  ST-Link is
# what the Nucleo enumerates as; the rest are common bench adapters.
_KNOWN_BRIDGES = ("STLink", "ST-Link", "STMicroelectronics",
                  "CH340", "CP210", "FTDI", "Virtual")

# Descriptions that are almost never the instrument.  Bluetooth RFCOMM ports
# are the worst offenders: opening one can block in the driver for ~30 s.
_UNLIKELY = ("Bluetooth", "BthModem")


@dataclass(frozen=True)
class PortInfo:
    device: str
    description: str = ""
    hwid: str = ""

    @property
    def is_known_bridge(self) -> bool:
        return any(k.lower() in self.description.lower() for k in _KNOWN_BRIDGES)

    @property
    def is_unlikely(self) -> bool:
        return any(k.lower() in self.description.lower() for k in _UNLIKELY)

    @property
    def rank(self) -> int:
        """Sort key — lower is more likely to be the harness tester."""
        if self.is_known_bridge:
            return 0
        if self.is_unlikely:
            return 2
        return 1

    def label(self) -> str:
        star = "* " if self.is_known_bridge else ""
        return f"{star}{self.device} - {self.description or self.device}"


def enumerate_ports() -> list[PortInfo]:
    """Return every serial port, best candidate first.

    Blocking — call from a worker thread, or via PortScanner.
    """
    if not _SERIAL_AVAILABLE:
        return []
    ports = [
        PortInfo(device=p.device,
                 description=p.description or p.device,
                 hwid=p.hwid or "")
        for p in _list_ports.comports()
    ]
    # Stable sort: rank first, then natural device order within a rank.
    return sorted(ports, key=lambda p: (p.rank, p.device))


def preferred_port(ports: list[PortInfo]) -> PortInfo | None:
    """Return the port that should be selected by default, if any."""
    return ports[0] if ports else None


class PortScanner(QThread):
    """Runs enumerate_ports() off the GUI thread."""

    portsReady = pyqtSignal(object)   # list[PortInfo]

    def run(self) -> None:
        try:
            self.portsReady.emit(enumerate_ports())
        except Exception:
            self.portsReady.emit([])
