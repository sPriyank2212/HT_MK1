"""InfoPanel — static GUI info + live firmware status tab."""

from __future__ import annotations
from datetime import datetime

from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QGroupBox,
    QLabel, QPushButton, QFormLayout, QSizePolicy,
)

from version import APP_VERSION, PROTOCOL_VERSION

# build_info.py is written by HarnessTester.spec each time the exe is built,
# so this is when the program was built, not when it is run.  A run from
# source has no such file.
try:
    from build_info import BUILD_DATETIME
except ImportError:
    BUILD_DATETIME = ""


def _value_label(text: str = "—") -> QLabel:
    lbl = QLabel(text)
    lbl.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
    return lbl


class InfoPanel(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._build_ui()

    # ------------------------------------------------------------------
    # UI construction
    # ------------------------------------------------------------------

    def _build_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setContentsMargins(16, 16, 16, 16)
        root.setSpacing(12)

        root.addWidget(self._build_gui_group())
        root.addWidget(self._build_fw_group())
        root.addStretch()

    def _build_gui_group(self) -> QGroupBox:
        grp = QGroupBox("GUI / Application")
        form = QFormLayout(grp)
        form.setLabelAlignment(Qt.AlignmentFlag.AlignRight)
        form.setHorizontalSpacing(16)

        form.addRow("App version:",      _value_label(APP_VERSION))
        form.addRow("Protocol version:", _value_label(PROTOCOL_VERSION))
        form.addRow("Build date:",       _value_label(
            BUILD_DATETIME or "not a packaged build (running from source)"))
        form.addRow("Build:",            _value_label(__import__('sys').version.split()[0] + " (Python)"))
        form.addRow("Started:",          _value_label(datetime.now().strftime("%Y-%m-%d %H:%M")))
        return grp

    def _build_fw_group(self) -> QGroupBox:
        grp = QGroupBox("Firmware / Device")
        outer = QVBoxLayout(grp)

        form = QFormLayout()
        form.setLabelAlignment(Qt.AlignmentFlag.AlignRight)
        form.setHorizontalSpacing(16)

        self._lbl_fw_version   = _value_label()
        self._lbl_fw_state     = _value_label()
        self._lbl_fw_flags     = _value_label()
        self._lbl_fw_cal       = _value_label()
        self._lbl_fw_port      = _value_label()
        self._lbl_fw_baud      = _value_label()
        self._lbl_fw_refreshed = _value_label()

        form.addRow("FW version:",     self._lbl_fw_version)
        form.addRow("Device state:",   self._lbl_fw_state)
        # form.addRow("Flags:",          self._lbl_fw_flags)
        # form.addRow("Cal offset:",     self._lbl_fw_cal)
        form.addRow("Port:",           self._lbl_fw_port)
        form.addRow("Baud:",           self._lbl_fw_baud)
        form.addRow("Last refreshed:", self._lbl_fw_refreshed)
        outer.addLayout(form)

        btn_row = QHBoxLayout()
        self._btn_refresh = QPushButton("Refresh Firmware Info")
        self._btn_refresh.setToolTip("Send GET_STATUS to firmware and update this panel")
        self._btn_refresh.setEnabled(False)
        self._btn_refresh.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        btn_row.addWidget(self._btn_refresh)
        btn_row.addStretch()
        outer.addLayout(btn_row)

        return grp

    # ------------------------------------------------------------------
    # Public API — called by MainWindow
    # ------------------------------------------------------------------

    @property
    def refresh_button(self) -> QPushButton:
        """Expose button so MainWindow can connect its clicked signal."""
        return self._btn_refresh

    def set_connected(self, connected: bool) -> None:
        self._btn_refresh.setEnabled(connected)
        if not connected:
            for lbl in (self._lbl_fw_version, self._lbl_fw_state, self._lbl_fw_flags,
                        self._lbl_fw_cal, self._lbl_fw_port, self._lbl_fw_baud):
                lbl.setText("—")

    def update_firmware_status(self, fw_version: str, state: int, flags: int,
                               cal_offset_mohm: int, port: str, baud: int) -> None:
        _STATE_NAMES = {0: "IDLE", 1: "UPLOADING", 2: "CALIBRATING", 3: "SCANNING", 4: "COMPLETE"}
        self._lbl_fw_version.setText(f"v{fw_version}")
        self._lbl_fw_state.setText(_STATE_NAMES.get(state, f"0x{state:02X}"))
        self._lbl_fw_flags.setText(f"0x{flags:02X}")
        self._lbl_fw_cal.setText(f"{cal_offset_mohm} mΩ")
        self._lbl_fw_port.setText(port)
        self._lbl_fw_baud.setText(str(baud))
        self._lbl_fw_refreshed.setText(datetime.now().strftime("%H:%M:%S"))
