"""LeftPanel — vertical stack of collapsible group boxes (control & navigation)."""

from __future__ import annotations
import os
import json

from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtGui import QColor
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QScrollArea,
    QGroupBox, QLabel, QPushButton, QComboBox,
    QLineEdit,
    QTreeWidget, QTreeWidgetItem, QFileDialog,
    QInputDialog, QMessageBox, QButtonGroup, QRadioButton,
)

from core import paths
from core.port_manager import PortScanner, _SERIAL_AVAILABLE

class LeftPanel(QWidget):
    connectRequested    = pyqtSignal(str, int)
    disconnectRequested = pyqtSignal()
    netlistBrowsed      = pyqtSignal(str)
    profileChanged      = pyqtSignal(str)   # profile name
    autoModeChanged     = pyqtSignal(bool)  # True = Auto-Scan, False = Standard
    useAutoScanAsNetlist = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumWidth(240)
        self.setMaximumWidth(380)
        self._netlist_path = ""
        self._port_scanner: PortScanner | None = None
        self._build_ui()
        self._scan_ports()
        self._load_profiles_into_combo()

    # ------------------------------------------------------------------
    # UI construction
    # ------------------------------------------------------------------

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setFrameShape(QScrollArea.Shape.NoFrame)

        inner = QWidget()
        layout = QVBoxLayout(inner)
        layout.setContentsMargins(6, 6, 6, 6)
        layout.setSpacing(6)

        layout.addWidget(self._build_connection_group())
        layout.addWidget(self._build_netlist_group())
        layout.addWidget(self._build_profile_group())
        layout.addStretch()

        scroll.setWidget(inner)
        outer.addWidget(scroll)

    # --- Connection group ---

    def _build_connection_group(self) -> QGroupBox:
        grp = QGroupBox("Connection")
        lay = QVBoxLayout(grp)
        lay.setSpacing(4)

        row1 = QHBoxLayout()
        self._cb_port = QComboBox()
        self._cb_port.setToolTip("Select serial port")
        self._cb_port.setAccessibleName("COM port selector")
        self._cb_port.setMinimumWidth(90)
        btn_scan = QPushButton("Refresh")
        btn_scan.setToolTip("Rescan available serial ports")
        btn_scan.setAccessibleName("Refresh ports button")
        btn_scan.clicked.connect(self._scan_ports)
        row1.addWidget(QLabel("Port:"), 0)
        row1.addWidget(self._cb_port, 1)
        row1.addWidget(btn_scan, 0)
        lay.addLayout(row1)

        row2 = QHBoxLayout()
        self._cb_baud = QComboBox()
        self._cb_baud.addItems(["9600", "115200", "921600"])
        self._cb_baud.setCurrentText("115200")   # match firmware (main.c MX_USART3_UART_Init)
        self._cb_baud.setToolTip("Select baud rate")
        self._cb_baud.setAccessibleName("Baud rate selector")
        row2.addWidget(QLabel("Baud:"), 0)
        row2.addWidget(self._cb_baud, 1)
        lay.addLayout(row2)

        row3 = QHBoxLayout()
        self._btn_connect = QPushButton("● Connect")
        self._btn_connect.setToolTip("Open serial port and connect to firmware")
        self._btn_connect.setAccessibleName("Connect button")
        self._btn_connect.clicked.connect(self._on_connect)
        self._btn_disconnect = QPushButton("○ Disconnect")
        self._btn_disconnect.setToolTip("Disconnect from firmware")
        self._btn_disconnect.setAccessibleName("Disconnect button")
        self._btn_disconnect.setEnabled(False)
        self._btn_disconnect.clicked.connect(self.disconnectRequested)
        row3.addWidget(self._btn_connect)
        row3.addWidget(self._btn_disconnect)
        lay.addLayout(row3)

        self._lbl_conn_status = QLabel("Not connected")
        self._lbl_conn_status.setStyleSheet("color: #888;")
        self._lbl_conn_status.setToolTip("Current connection status")
        self._lbl_conn_status.setAccessibleName("Connection status")
        lay.addWidget(self._lbl_conn_status)

        return grp

    # --- Netlist group ---

    def _build_netlist_group(self) -> QGroupBox:
        grp = QGroupBox("Netlist / Test Mode")
        lay = QVBoxLayout(grp)
        lay.setSpacing(4)

        # Mode selector — Standard vs Auto-Scan
        mode_row = QHBoxLayout()
        self._rb_standard  = QRadioButton("Standard (file)")
        self._rb_auto_test = QRadioButton("Auto-Scan")
        self._rb_standard.setChecked(True)
        self._rb_standard.setToolTip("Load a netlist file and test expected connections")
        self._rb_auto_test.setToolTip(
            "Scan all 37×37 pin combinations — discovers which pins are physically connected"
        )
        self._mode_group = QButtonGroup(self)
        self._mode_group.addButton(self._rb_standard,  0)
        self._mode_group.addButton(self._rb_auto_test, 1)
        self._mode_group.idToggled.connect(self._on_mode_toggled)
        mode_row.addWidget(self._rb_standard)
        mode_row.addWidget(self._rb_auto_test)
        lay.addLayout(mode_row)

        lay.addWidget(_hline())

        # Harness ID display (shown after a netlist with harness_id is loaded)
        self._lbl_harness_id = QLabel("")
        self._lbl_harness_id.setStyleSheet(
            "color: #CBA6F7; font-weight: bold; font-size: 9pt; padding: 2px 0;"
        )
        self._lbl_harness_id.setToolTip("Harness ID from loaded netlist")
        self._lbl_harness_id.setVisible(False)
        lay.addWidget(self._lbl_harness_id)

        # Standard mode widgets (browse + tree)
        self._std_widget = QWidget()
        std_lay = QVBoxLayout(self._std_widget)
        std_lay.setContentsMargins(0, 0, 0, 0)
        std_lay.setSpacing(4)

        row = QHBoxLayout()
        self._btn_browse = QPushButton("Browse…")
        self._btn_browse.setToolTip("Load a netlist file (JSON, Excel .xlsx, or CSV)")
        self._btn_browse.setAccessibleName("Browse netlist button")
        self._btn_browse.clicked.connect(self._browse_netlist)
        self._lbl_netlist_file = QLabel("No netlist loaded")
        self._lbl_netlist_file.setWordWrap(True)
        self._lbl_netlist_file.setToolTip("Currently loaded netlist file")
        row.addWidget(self._btn_browse)
        row.addWidget(self._lbl_netlist_file, 1)
        std_lay.addLayout(row)

        self._tree_netlist = QTreeWidget()
        self._tree_netlist.setHeaderHidden(True)
        self._tree_netlist.setMaximumHeight(120)
        self._tree_netlist.setToolTip("Netlist tree — nets and pins")
        self._tree_netlist.setAccessibleName("Netlist tree")
        self._show_tree_placeholder()
        std_lay.addWidget(self._tree_netlist)

        lay.addWidget(self._std_widget)

        # Auto-Scan info label (shown instead of browse/tree in auto mode)
        self._auto_info = QLabel(
            "Auto-Scan: probes all 37 × 37 pin pairs,\n"
            "showing only the connections that are present."
        )
        self._auto_info.setStyleSheet("color:#89DCEB; font-size:9pt; padding:4px;")
        self._auto_info.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._auto_info.setVisible(False)
        lay.addWidget(self._auto_info)

        self._btn_use_as_netlist = QPushButton("Use as Netlist")
        self._btn_use_as_netlist.setToolTip(
            "Load the connections found by the last Auto-Scan as the active netlist "
            "and switch to Standard mode, ready to test the next harness"
        )
        self._btn_use_as_netlist.setAccessibleName("Use Auto-Scan result as netlist button")
        self._btn_use_as_netlist.setEnabled(False)
        self._btn_use_as_netlist.setVisible(False)
        self._btn_use_as_netlist.clicked.connect(self.useAutoScanAsNetlist)
        lay.addWidget(self._btn_use_as_netlist)

        # ── Connection Defaults ──────────────────────────────────────────
        lay.addWidget(_hline())
        def_header = QLabel("Connection Defaults")
        def_header.setStyleSheet("color:#888; font-size:8pt;")
        def_header.setToolTip(
            "Fallback values used in the Results table when a netlist field is empty "
            "or in Auto-Scan mode (no netlist loaded)"
        )
        lay.addWidget(def_header)

        def _def_row(label_text, placeholder, tip):
            row = QHBoxLayout()
            lbl = QLabel(f"{label_text}:")
            lbl.setFixedWidth(68)
            edit = QLineEdit()
            edit.setPlaceholderText(placeholder)
            edit.setToolTip(tip)
            row.addWidget(lbl)
            row.addWidget(edit, 1)
            lay.addLayout(row)
            return edit

        self._edit_def_connector = _def_row(
            "Connector", "e.g. X1",
            "Default Connector ID when the net has none or no netlist is loaded"
        )
        self._edit_def_source = _def_row(
            "Source", "e.g. Side A",
            "Default Source label when the net has none or no netlist is loaded"
        )
        self._edit_def_dest = _def_row(
            "Destination", "e.g. Side B",
            "Default Destination label when the net has none or no netlist is loaded"
        )

        return grp

    def _show_tree_placeholder(self) -> None:
        self._tree_netlist.clear()
        item = QTreeWidgetItem(["(No netlist loaded)"])
        item.setForeground(0, QColor("#888"))
        self._tree_netlist.addTopLevelItem(item)

    def _populate_netlist_tree(self, netlist) -> None:
        """Populate tree from a loaded Netlist object."""
        # Harness ID banner
        if netlist.harness_id:
            self._lbl_harness_id.setText(f"Harness ID: {netlist.harness_id}")
            self._lbl_harness_id.setVisible(True)
        else:
            self._lbl_harness_id.setVisible(False)

        self._tree_netlist.clear()
        for net in netlist.nets:
            pin_count = len(net.pins)

            # Build the top-level label with connector info when present
            parts = [f"NET: {net.name}"]
            if net.connector_id:
                parts.append(f"[{net.connector_id}]")
            if net.source and net.destination:
                parts.append(f"{net.source} → {net.destination}")
            elif net.source:
                parts.append(f"from {net.source}")
            elif net.destination:
                parts.append(f"to {net.destination}")
            parts.append(f"({pin_count} pin{'s' if pin_count != 1 else ''})")
            label = "  ".join(parts)

            net_item = QTreeWidgetItem([label])

            if net.connector_detail:
                detail_item = QTreeWidgetItem([f"  Type: {net.connector_detail}"])
                detail_item.setForeground(0, QColor("#888"))
                net_item.addChild(detail_item)

            for pin in sorted(net.pins, key=lambda p: p.number):
                pin_label = f"Pin {pin.number}" + (f"  {pin.name}" if pin.name else "")
                net_item.addChild(QTreeWidgetItem([pin_label]))
            self._tree_netlist.addTopLevelItem(net_item)
        self._tree_netlist.expandAll()

    # --- Test Profile group ---

    def _build_profile_group(self) -> QGroupBox:
        grp = QGroupBox("Test Profile")
        lay = QVBoxLayout(grp)
        lay.setSpacing(4)

        row1 = QHBoxLayout()
        self._cb_profile = QComboBox()
        self._cb_profile.setToolTip("Select test profile")
        self._cb_profile.setAccessibleName("Profile selector")
        self._cb_profile.currentTextChanged.connect(self._on_profile_selected)
        row1.addWidget(QLabel("Profile:"))
        row1.addWidget(self._cb_profile, 1)
        lay.addLayout(row1)

        row2 = QHBoxLayout()
        self._edit_operator = QLineEdit()
        self._edit_operator.setPlaceholderText("Operator name")
        self._edit_operator.setToolTip("Operator name for this test session")
        self._edit_operator.setAccessibleName("Operator name field")
        row2.addWidget(QLabel("Operator:"))
        row2.addWidget(self._edit_operator, 1)
        lay.addLayout(row2)

        row2b = QHBoxLayout()
        self._edit_session_harness_id = QLineEdit()
        self._edit_session_harness_id.setPlaceholderText("e.g. HRN-2024-001")
        self._edit_session_harness_id.setToolTip(
            "Harness ID for this session — used when the netlist file has no harness_id"
        )
        self._edit_session_harness_id.setAccessibleName("Session harness ID field")
        row2b.addWidget(QLabel("Harness ID:"))
        row2b.addWidget(self._edit_session_harness_id, 1)
        lay.addLayout(row2b)

        row3 = QHBoxLayout()
        self._edit_dut_id = QLineEdit()
        self._edit_dut_id.setText("HT-0001")
        self._edit_dut_id.setToolTip("DUT identifier (auto-increments after each test)")
        self._edit_dut_id.setAccessibleName("DUT ID field")
        row3.addWidget(QLabel("DUT ID:"))
        row3.addWidget(self._edit_dut_id, 1)
        lay.addLayout(row3)

        row4 = QHBoxLayout()
        self._btn_save_profile   = QPushButton("Save")
        self._btn_new_profile    = QPushButton("New")
        self._btn_delete_profile = QPushButton("Delete")
        self._btn_save_profile.setToolTip("Save current settings to the selected profile")
        self._btn_new_profile.setToolTip("Create a new profile")
        self._btn_delete_profile.setToolTip("Delete the selected profile")
        self._btn_save_profile.clicked.connect(self._on_save_profile)
        self._btn_new_profile.clicked.connect(self._on_new_profile)
        self._btn_delete_profile.clicked.connect(self._on_delete_profile)
        for btn in (self._btn_save_profile, self._btn_new_profile, self._btn_delete_profile):
            row4.addWidget(btn)
        lay.addLayout(row4)

        return grp

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def set_connection_status(self, connected: bool, fw_version: str = "") -> None:
        if connected:
            self._lbl_conn_status.setText(f"CONNECTED — FW v{fw_version}")
            self._lbl_conn_status.setStyleSheet("color: #28a745; font-weight: bold;")
            self._btn_connect.setEnabled(False)
            self._btn_disconnect.setEnabled(True)
        else:
            self._lbl_conn_status.setText("Not connected")
            self._lbl_conn_status.setStyleSheet("color: #888;")
            self._btn_connect.setEnabled(True)
            self._btn_disconnect.setEnabled(False)

    def get_netlist_path(self) -> str:
        return self._netlist_path

    def is_auto_test_mode(self) -> bool:
        return self._rb_auto_test.isChecked()

    def set_auto_scan_result_available(self, available: bool) -> None:
        self._btn_use_as_netlist.setEnabled(available)

    def show_netlist(self, path: str, netlist) -> None:
        """Show *path* as the loaded netlist and switch to Standard mode —
        for a netlist loaded by the app rather than through Browse."""
        self._netlist_path = path
        self._lbl_netlist_file.setText(os.path.basename(path))
        self._lbl_netlist_file.setToolTip(path)
        self._populate_netlist_tree(netlist)
        self._rb_standard.setChecked(True)

    def get_dut_id(self) -> str:
        return self._edit_dut_id.text().strip() or "HT-0001"

    def get_operator(self) -> str:
        return self._edit_operator.text().strip()

    def increment_dut_id(self) -> None:
        """Auto-increment trailing numeric part of DUT ID after a test."""
        text = self._edit_dut_id.text().strip()
        i = len(text)
        while i > 0 and text[i - 1].isdigit():
            i -= 1
        prefix, num_str = text[:i], text[i:]
        if num_str:
            new_num = int(num_str) + 1
            self._edit_dut_id.setText(f"{prefix}{new_num:0{len(num_str)}d}")
        else:
            self._edit_dut_id.setText(text + "-2")

    def get_connector_defaults(self) -> dict:
        return {
            "connector_id": self._edit_def_connector.text().strip(),
            "source":       self._edit_def_source.text().strip(),
            "destination":  self._edit_def_dest.text().strip(),
        }

    def get_current_profile_name(self) -> str:
        return self._cb_profile.currentText()

    # ------------------------------------------------------------------
    # Slots
    # ------------------------------------------------------------------

    def _on_mode_toggled(self, _id: int, checked: bool) -> None:
        if not checked:
            return
        auto = self._rb_auto_test.isChecked()
        self._std_widget.setVisible(not auto)
        self._auto_info.setVisible(auto)
        self._btn_use_as_netlist.setVisible(auto)
        self.autoModeChanged.emit(auto)

    def rescan_ports(self) -> None:
        """Public hook — refresh the port list (e.g. after a connection drop,
        when the device may have re-enumerated onto a different COM number)."""
        self._scan_ports()

    def _scan_ports(self) -> None:
        """Start an off-thread port scan — _on_ports_ready fills the combo.

        Enumeration runs on a worker because Windows COM enumeration can block
        for seconds when Bluetooth virtual ports are present.
        """
        if not _SERIAL_AVAILABLE:
            self._cb_port.clear()
            for p in ["COM3", "COM4", "COM10"]:
                self._cb_port.addItem(p, p)
            return

        if self._port_scanner is not None and self._port_scanner.isRunning():
            return

        self._cb_port.setEnabled(False)
        self._port_scanner = PortScanner(self)
        self._port_scanner.portsReady.connect(self._on_ports_ready)
        self._port_scanner.start()

    def _on_ports_ready(self, ports: list) -> None:
        previous = self._cb_port.currentData()
        self._cb_port.clear()
        for p in ports:
            self._cb_port.addItem(p.label(), p.device)
        if not ports:
            self._cb_port.addItem("No ports found")

        # Preserve the operator's choice across a refresh; otherwise select the
        # best-ranked port, so a legacy COM1 is never the silent default.
        idx = self._cb_port.findData(previous) if previous else -1
        self._cb_port.setCurrentIndex(idx if idx >= 0 else 0)
        self._cb_port.setEnabled(True)

    def _on_connect(self) -> None:
        port = self._cb_port.currentData() or self._cb_port.currentText().split(" ")[0]
        baud = int(self._cb_baud.currentText())
        self.connectRequested.emit(port, baud)

    def _browse_netlist(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self, "Load Netlist", "",
            "Netlist files (*.json *.xlsx *.csv);;JSON (*.json);;Excel (*.xlsx);;CSV (*.csv);;All files (*)"
        )
        if not path:
            return
        self._netlist_path = path
        basename = os.path.basename(path)
        self._lbl_netlist_file.setText(basename)
        self._lbl_netlist_file.setToolTip(path)

        # Populate the netlist tree with actual net/pin data
        try:
            from core.netlist import load_netlist
            netlist = load_netlist(path)
            self._populate_netlist_tree(netlist)
        except Exception as exc:
            self._show_tree_placeholder()
            self._lbl_netlist_file.setText(f"{basename} ⚠ parse error")

        self.netlistBrowsed.emit(path)

    # ------------------------------------------------------------------
    # Profile management
    # ------------------------------------------------------------------

    def _profiles_dir(self) -> str:
        return paths.profiles_dir()

    def _profile_path(self, name: str) -> str:
        return os.path.join(self._profiles_dir(), f"{name}.json")

    def _load_profiles_into_combo(self) -> None:
        """Populate combobox from profiles/ directory. Always includes Default."""
        self._cb_profile.blockSignals(True)
        current = self._cb_profile.currentText()
        self._cb_profile.clear()
        self._cb_profile.addItem("Default")

        d = self._profiles_dir()
        if os.path.isdir(d):
            for fname in sorted(os.listdir(d)):
                if fname.endswith(".json") and not fname.startswith("app_"):
                    name = fname[:-5]
                    if name != "Default":
                        self._cb_profile.addItem(name)

        idx = self._cb_profile.findText(current)
        if idx >= 0:
            self._cb_profile.setCurrentIndex(idx)
        self._cb_profile.blockSignals(False)

    def _on_profile_selected(self, name: str) -> None:
        """Load profile settings into the UI fields."""
        path = self._profile_path(name)
        if not os.path.exists(path):
            return
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError):
            return

        if "operator" in data:
            self._edit_operator.setText(data["operator"])
        if "dut_id" in data:
            self._edit_dut_id.setText(data["dut_id"])
        if "netlist_path" in data and data["netlist_path"]:
            p = data["netlist_path"]
            if os.path.exists(p):
                self._netlist_path = p
                self._lbl_netlist_file.setText(os.path.basename(p))
                self._lbl_netlist_file.setToolTip(p)
                try:
                    from core.netlist import load_netlist
                    self._populate_netlist_tree(load_netlist(p))
                except Exception:
                    pass
                self.netlistBrowsed.emit(p)
        if "baud" in data:
            self._cb_baud.setCurrentText(str(data["baud"]))
        self.profileChanged.emit(name)

    def _on_save_profile(self) -> None:
        name = self._cb_profile.currentText()
        data = {
            "name":         name,
            "operator":     self._edit_operator.text().strip(),
            "dut_id":       self._edit_dut_id.text().strip(),
            "netlist_path": self._netlist_path,
            "baud":         int(self._cb_baud.currentText()),
        }
        os.makedirs(self._profiles_dir(), exist_ok=True)
        with open(self._profile_path(name), "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)

        # Flash button green briefly
        self._btn_save_profile.setText("Saved ✓")
        from PyQt6.QtCore import QTimer
        QTimer.singleShot(1500, lambda: self._btn_save_profile.setText("Save"))

    def _on_new_profile(self) -> None:
        name, ok = QInputDialog.getText(self, "New Profile", "Profile name:")
        if not ok or not name.strip():
            return
        name = name.strip()
        if name in ("Default", "app_settings"):
            QMessageBox.warning(self, "Invalid Name", f'"{name}" is a reserved name.')
            return
        self._cb_profile.addItem(name)
        self._cb_profile.setCurrentText(name)
        self._on_save_profile()

    def _on_delete_profile(self) -> None:
        name = self._cb_profile.currentText()
        if name == "Default":
            QMessageBox.warning(self, "Cannot Delete", "The Default profile cannot be deleted.")
            return
        reply = QMessageBox.question(
            self, "Delete Profile",
            f'Delete profile "{name}"? This cannot be undone.',
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply == QMessageBox.StandardButton.Yes:
            path = self._profile_path(name)
            if os.path.exists(path):
                os.remove(path)
            idx = self._cb_profile.currentIndex()
            self._cb_profile.removeItem(idx)


def _hline() -> QWidget:
    line = QWidget()
    line.setFixedHeight(1)
    line.setStyleSheet("background-color: #45475A;")
    return line
