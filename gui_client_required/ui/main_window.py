"""MainWindow — Harness Tester GUI."""

from __future__ import annotations
import csv
import json
import os
import time
from datetime import datetime

from PyQt6.QtCore import Qt, QSize, QTimer, QUrl
from PyQt6.QtGui import QAction, QKeySequence, QCloseEvent, QShortcut, QPixmap, QIcon, QDesktopServices
from PyQt6.QtWidgets import (
    QMainWindow, QSplitter, QWidget, QVBoxLayout,
    QTabWidget, QLabel, QMessageBox,
    QApplication, QFileDialog, QDialog,
)

from version import APP_VERSION
from ui.left_panel import LeftPanel
from ui.test_control_bar import TestControlBar
from ui.connector_view import ConnectorView
from ui.matrix_view import PinState
from ui.results_table import ResultsTable
from ui.log_panel import LogPanel
from ui.netlist_editor import NetlistEditorDialog
from ui.golden_sample import GoldenSampleWizard
from ui.info_panel import InfoPanel
from ui.config_panel import ConfigPanel
from core.serial_comm import SerialWorker
from core.test_engine import TestEngine
from core.data_types import (
    Cmd, TestState, Verdict, TestModes,
    ContResult, FirmwareStatus,
    ScanSummary, ResultStatus, TestType, TestResult,
)
from core.report import ReportMetadata, run_pdf_worker
from core.result_model import COL_CONN_ID
from core import paths

SETTINGS_PATH = paths.settings_path()
RESULTS_DIR   = paths.results_dir()
LOGO_PATH     = os.path.join(os.path.dirname(__file__), "..", "resources", "company_logo.jpeg")


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()

        # Runtime state
        self._worker: SerialWorker | None = None
        self._engine: TestEngine | None   = None
        self._pdf_thread = None   # kept alive while a PDF export runs
        self._pdf_worker = None
        self._connected     = False
        self._has_netlist   = False
        self._netlist_path  = ""
        self._netlist       = None   # loaded Netlist object for connector lookups
        self._test_counter  = 0
        self._pass_count    = 0
        self._fail_count    = 0
        self._progress_done = 0
        self._progress_total = 0
        self._scan_start_time = 0.0
        self._is_auto_test  = False
        self._last_verdict  = ""
        self._last_dut_id   = ""      # DUT ID of the last test; the field itself moves on after each test
        self._fw_version_str = ""
        self._last_duration_s = 0.0

        # Auto-reconnect state
        self._reconnect_port  = ""
        self._reconnect_baud  = 115200
        self._reconnect_count = 0
        self._reconnect_timer = QTimer(self)
        self._reconnect_timer.setSingleShot(True)
        self._reconnect_timer.timeout.connect(self._do_reconnect)
        # Name of the port that has returned a valid RSP_STATUS at least once
        # in this session.  Retrying is worthwhile only for such a port; one
        # that has never answered (a legacy COM1, a Bluetooth RFCOMM node)
        # never will.  This deliberately outlives an individual attempt — a
        # device that has been working and drops out still deserves its
        # retries.
        self._validated_port  = ""
        # Workers detached mid-teardown; kept referenced so Qt does not collect
        # a QThread that is still inside run().
        self._zombie_workers: list = []

        # Non-empty while the connector config or the netlist cannot be
        # tested safely — Start stays disabled (see _validate_connector_config).
        self._config_error  = ""
        self._netlist_error = ""
        # {channel: (Side-B connector, pin)}; empty unless the connector config
        # gives Side B connectors of its own (a Dest Pin).
        self._pin_map_b: dict[int, tuple[str, int]] = {}
        # (side A channel, side B channel) pairs found by the last Auto-Scan
        self._auto_scan_pairs: list[tuple[int, int]] = []

        # Setup
        self._setup_window()
        self._build_menu_bar()
        self._build_central_widget()
        self._build_status_bar()
        self._setup_shortcuts()
        self._wire_left_panel()
        self._restore_geometry()

        os.makedirs(RESULTS_DIR, exist_ok=True)
        self._validate_connector_config()

        # Elapsed timer
        self._elapsed_timer = QTimer(self)
        self._elapsed_timer.setInterval(100)
        self._elapsed_timer.timeout.connect(self._tick_elapsed)

    # ------------------------------------------------------------------
    # Window setup
    # ------------------------------------------------------------------

    def _setup_window(self) -> None:
        self.setWindowTitle(f"Harness Tester v{APP_VERSION} — [No Profile]")
        self.setMinimumSize(QSize(1024, 640))
        self.resize(1280, 800)
        icon_pixmap = QPixmap(LOGO_PATH)
        if not icon_pixmap.isNull():
            self.setWindowIcon(QIcon(icon_pixmap))

    def _make_logo_label(self, height: int) -> QLabel:
        lbl = QLabel()
        pixmap = QPixmap(LOGO_PATH)
        if not pixmap.isNull():
            lbl.setPixmap(
                pixmap.scaledToHeight(height, Qt.TransformationMode.SmoothTransformation)
            )
        lbl.setContentsMargins(4, 2, 4, 2)
        return lbl

    # ------------------------------------------------------------------
    # Menu bar
    # ------------------------------------------------------------------

    def _build_menu_bar(self) -> None:
        mb = self.menuBar()
        # mb.setCornerWidget(self._make_logo_label(40), Qt.Corner.TopLeftCorner)

        # --- File ---
        file_menu = mb.addMenu("&File")
        act_load = self._add_action(file_menu, "Load Netlist…", "Ctrl+O")
        act_load.triggered.connect(self._on_menu_load_netlist)
        self._act_save_csv = self._add_action(file_menu, "Save Results as CSV…", "Ctrl+S")
        self._act_save_csv.triggered.connect(self._on_save_results_csv)
        self._act_export_pdf = self._add_action(file_menu, "Export PDF Report…", "Ctrl+P")
        self._act_export_pdf.triggered.connect(self._on_export_pdf)
        self._add_action(file_menu, "Save Netlist As…").triggered.connect(self._on_save_netlist_as)
        file_menu.addSeparator()
        self._add_action(file_menu, "Open Results Folder…").triggered.connect(self._open_results_folder)
        file_menu.addSeparator()
        exit_action = self._add_action(file_menu, "Exit", "Alt+F4")
        exit_action.triggered.connect(self.close)

        # --- View ---
        view_menu = mb.addMenu("&View")
        theme_menu = view_menu.addMenu("Theme")
        self._add_action(theme_menu, "Dark").triggered.connect(self._on_theme_dark)
        self._add_action(theme_menu, "Light").triggered.connect(self._on_theme_light)
        view_menu.addSeparator()
        self._act_show_log    = self._add_action(view_menu, "Show Log",     "Ctrl+L")
        self._act_show_matrix = self._add_action(view_menu, "Show Matrix",  "Ctrl+M")
        self._act_show_result = self._add_action(view_menu, "Show Results", "Ctrl+R")

        # --- Help ---
        help_menu = mb.addMenu("&Help")
        self._add_action(help_menu, "About").triggered.connect(self._show_about)

    @staticmethod
    def _add_action(menu, label: str, shortcut: str = "") -> QAction:
        action = QAction(label, menu)
        if shortcut:
            action.setShortcut(QKeySequence(shortcut))
        menu.addAction(action)
        return action

    # ------------------------------------------------------------------
    # Central widget
    # ------------------------------------------------------------------

    def _build_central_widget(self) -> None:
        splitter = QSplitter(Qt.Orientation.Horizontal)
        splitter.setHandleWidth(4)

        self._left_panel    = LeftPanel()
        self._test_bar      = TestControlBar()
        self._matrix_view   = ConnectorView()
        self._results_table = ResultsTable()
        self._log_panel     = LogPanel()
        self._info_panel    = InfoPanel()
        self._config_panel  = ConfigPanel()

        self.addToolBar(self._test_bar)

        centre = QWidget()
        centre_layout = QVBoxLayout(centre)
        centre_layout.setContentsMargins(0, 0, 0, 0)
        self._tabs = QTabWidget()
        self._tabs.addTab(self._matrix_view,   "Connector View")
        self._tabs.addTab(self._results_table, "Results Table")
        self._tabs.addTab(self._log_panel,     "Log")
        self._tabs.addTab(self._info_panel,    "Info")
        self._tabs.addTab(self._config_panel,  "Configuration")
        centre_layout.addWidget(self._tabs)

        splitter.addWidget(self._left_panel)
        splitter.addWidget(centre)
        splitter.setStretchFactor(0, 0)
        splitter.setStretchFactor(1, 1)

        self.setCentralWidget(splitter)

        self._act_show_log.triggered.connect(self._show_log_tab)
        self._act_show_matrix.triggered.connect(self._show_matrix_tab)
        self._act_show_result.triggered.connect(self._show_results_tab)
        self._info_panel.refresh_button.clicked.connect(self._on_refresh_fw_info)

        self._log_panel.append_line("INFO", f"Harness Tester v{APP_VERSION} started")
        self._log_panel.append_line("INFO", "Connect a device to begin testing")

    # ------------------------------------------------------------------
    # Status bar
    # ------------------------------------------------------------------

    # ------------------------------------------------------------------
    # Keyboard shortcuts
    # ------------------------------------------------------------------

    def _build_status_bar(self) -> None:
        sb = self.statusBar()
        sb_brand = QLabel("Designed and developed by Infinity Integrations Private Limited")
        sb_brand.setStyleSheet("color: #888; font-size: 14px; padding: 0 6px;")
        sb.addPermanentWidget(sb_brand)
        sb.addPermanentWidget(self._make_logo_label(40))

    # ------------------------------------------------------------------
    # Keyboard shortcuts
    # ------------------------------------------------------------------

    def _setup_shortcuts(self) -> None:
        QShortcut(QKeySequence("F5"), self).activated.connect(self._on_start_requested)
        QShortcut(QKeySequence("F6"), self).activated.connect(self._on_stop_requested)
        QShortcut(QKeySequence("F7"), self).activated.connect(self._on_calibrate)

    # ------------------------------------------------------------------
    # Wire left panel signals
    # ------------------------------------------------------------------

    def _wire_left_panel(self) -> None:
        lp = self._left_panel
        lp.connectRequested.connect(self._on_connect_requested)
        lp.disconnectRequested.connect(self._on_disconnect_requested)
        lp.netlistBrowsed.connect(self._on_netlist_browsed)
        lp.useAutoScanAsNetlist.connect(self._on_use_auto_scan_as_netlist)
        self._config_panel.configChanged.connect(self._on_connector_config_changed)
        lp.autoModeChanged.connect(self._test_bar.set_auto_mode)
        self._test_bar.startRequested.connect(self._on_start_requested)
        self._test_bar.stopRequested.connect(self._on_stop_requested)

    # ------------------------------------------------------------------
    # Named slots
    # ------------------------------------------------------------------

    def _on_theme_dark(self)    -> None: self._apply_theme("dark")
    def _on_theme_light(self)   -> None: self._apply_theme("light")
    def _show_log_tab(self)     -> None: self._tabs.setCurrentIndex(2)
    def _show_matrix_tab(self)  -> None: self._tabs.setCurrentIndex(0)
    def _show_results_tab(self) -> None: self._tabs.setCurrentIndex(1)

    # ------------------------------------------------------------------
    # Connection handlers
    # ------------------------------------------------------------------

    def _create_worker(self, port: str, baud: int) -> SerialWorker:
        """The thread that talks to the tester.  The demo build overrides this."""
        return SerialWorker(port, baud)

    def _on_connect_requested(self, port: str, baud: int) -> None:
        if self._worker is not None:
            # Say so rather than swallowing the click — a worker stuck in a
            # blocking driver call used to make the GUI look dead for minutes.
            self._log_panel.append_line(
                "WARN",
                f"Already connecting to {self._worker._port} — wait for it to "
                f"finish or press Disconnect first")
            return
        self._reconnect_port = port
        self._reconnect_baud = baud

        self._worker = self._create_worker(port, baud)
        self._engine = TestEngine(self._worker)

        self._worker.statusReceived.connect(self._on_status_received)
        self._worker.contResultReceived.connect(self._on_cont_result)
        self._worker.progressUpdate.connect(self._on_progress)
        self._worker.nackReceived.connect(self._on_nack_received)
        self._worker.faultReceived.connect(self._on_fault_received)
        self._worker.connectionLost.connect(self._on_connection_lost)
        self._worker.rawPacketLogged.connect(self._log_panel.append_line)

        self._engine.stateChanged.connect(self.on_state_changed)
        self._engine.verdictReady.connect(self._on_verdict_ready)
        self._engine.calibrationComplete.connect(self._on_calibration_complete)
        self._engine.autoTestComplete.connect(self._on_auto_test_complete)

        self._worker.start()
        self._log_panel.append_line("INFO", f"Connecting to {port} @ {baud} baud…")

    def _on_disconnect_requested(self) -> None:
        self._reconnect_timer.stop()
        self._reconnect_count = 0
        self._teardown_worker()
        self._log_panel.append_line("INFO", "Disconnected")

    def _teardown_worker(self) -> None:
        if self._worker:
            worker = self._worker
            # Release the slot immediately so the next Connect is never blocked
            # by a worker that is wedged in the serial driver.
            self._worker = None
            worker.blockSignals(True)     # a zombie must not touch the UI
            worker.stop()
            # Short wait only: run() polls _stop_flag every 10 ms, so a healthy
            # worker exits at once.  One stuck in a blocking write/close is left
            # to unwind on its own rather than freezing the GUI for seconds.
            if not worker.wait(500):
                self._zombie_workers.append(worker)
            self._zombie_workers = [w for w in self._zombie_workers if w.isRunning()]
        self._engine = None
        self._connected = False
        self._fw_version_str = ""
        self._left_panel.set_connection_status(False)
        self._update_start_enabled()
        self._info_panel.set_connected(False)

    def _on_status_received(self, status: FirmwareStatus) -> None:
        self._reconnect_count = 0        # successful (re)connect — stop retrying
        self._reconnect_timer.stop()
        self._connected = True
        # Remember the port itself, not just "an attempt succeeded" — this has
        # to survive later failed attempts so a dropout still gets retried.
        if self._worker is not None:
            self._validated_port = self._worker._port
        self._left_panel.set_connection_status(True, status.fw_version)
        self._update_start_enabled()
        port = self._worker._port if self._worker else "?"
        baud = self._worker._baud if self._worker else 0
        self._fw_version_str = f"v{status.fw_version}"
        # STATUS flags bit 0 = DBGMCU_CR.TRACE_IOEN was set when the firmware
        # reclaimed the pads.  Surfaced on the connect line so a log from a
        # remote site shows immediately whether the debug block is stealing
        # B20/B22/B23/B24/B31 (PE2..PE6) and A18 (PB3).
        trace_on   = bool(status.flags & 0x01)
        trace_held = bool(status.flags & 0x02)
        self._log_panel.append_line(
            "INFO",
            f"Connected — FW v{status.fw_version}, cal offset "
            f"{status.cal_offset_mohm} mΩ, TRACE={'ON' if trace_on else 'OFF'}",
        )
        if trace_on or trace_held:
            self._log_panel.append_line(
                "WARN",
                "Debug trace port was active — B20/B22/B23/B24/B31 (PE2..PE6) "
                "and A18 (PB3) may read stuck HIGH. Close any debug session "
                "and power-cycle the board (a reset will not clear it)."
                + ("  Firmware built with -DHT_KEEP_TRACE, so it is not "
                   "reclaiming those pads." if trace_held else ""),
            )
        self._info_panel.set_connected(True)
        self._info_panel.update_firmware_status(
            status.fw_version, status.state, status.flags,
            status.cal_offset_mohm, port, baud,
        )

    def _on_connection_lost(self) -> None:
        self._teardown_worker()
        port = self._reconnect_port

        # Retry only a port that has answered at least once this session.  One
        # that has never returned RSP_STATUS — a legacy COM1, a Bluetooth
        # RFCOMM node — will not start answering now, and five 8-second
        # attempts just look like a hung application.  Note this compares the
        # port name, so a device that worked and then dropped out still gets
        # its retries.
        if port != self._validated_port:
            self._reconnect_count = 0
            self._reconnect_timer.stop()
            self._log_panel.append_line(
                "ERROR",
                f"{port} opened but never responded — not retrying. Rescanning "
                f"ports: an ST-Link that re-enumerates comes back on a "
                f"different COM number, so pick the one marked * and retry.")
            self._left_panel.rescan_ports()
            self.statusBar().showMessage(
                f"{port} did not respond — check the port selection", 8000)
            return

        self._log_panel.append_line("ERROR", "Serial connection lost")
        self._reconnect_count += 1
        _MAX = 5
        if self._reconnect_port and self._reconnect_count <= _MAX:
            delay_ms = min(1000 + (self._reconnect_count - 1) * 2000, 5000)
            self.statusBar().showMessage(
                f"Connection lost — reconnecting in {delay_ms // 1000}s "
                f"(attempt {self._reconnect_count}/{_MAX})…", 0)
            self._reconnect_timer.start(delay_ms)
        else:
            # Retries exhausted.  Forget the port and rescan — by this point
            # the likeliest cause is that the device re-enumerated onto a
            # different COM number, so retrying this name forever is futile.
            self._reconnect_count = 0
            self._reconnect_timer.stop()
            self._validated_port = ""
            self._left_panel.rescan_ports()
            self._log_panel.append_line(
                "ERROR",
                f"Gave up reconnecting to {self._reconnect_port} after {_MAX} "
                f"attempts — ports rescanned, select the device and reconnect.")
            self.statusBar().showMessage(
                "Connection lost — ports rescanned, reconnect manually", 8000)

    def _do_reconnect(self) -> None:
        if self._connected:
            self._reconnect_count = 0
            return
        self._log_panel.append_line("INFO",
            f"Auto-reconnect attempt {self._reconnect_count}: "
            f"{self._reconnect_port} @ {self._reconnect_baud}")
        self._on_connect_requested(self._reconnect_port, self._reconnect_baud)

    # ------------------------------------------------------------------
    # Connector config — connector pin <-> firmware channel, GUI side only
    # ------------------------------------------------------------------

    def _validate_connector_config(self) -> None:
        """Check connector_config.xlsx and report it; an invalid sheet blocks
        Start, since results would be shown against the wrong connector pins."""
        from core.netlist import _config_is_pinmap
        from core.pinmap import load_pinmap
        cfg_path = self._config_panel.config_path()
        self._config_error = ""
        if cfg_path and os.path.exists(cfg_path):
            name = os.path.basename(cfg_path)
            try:
                if _config_is_pinmap(cfg_path):
                    pm = load_pinmap(cfg_path)
                    self._log_panel.append_line(
                        "INFO", f"Connector config {name}: {len(pm.channels)} channels — {pm.summary()}")
                    if pm.warnings:
                        self._log_panel.append_line(
                            "WARN", f"{len(pm.warnings)} connector pin(s) sit on MCU pins shared "
                                    f"with another function; a fault there may be the tester:")
                        for w in pm.warnings:
                            self._log_panel.append_line("WARN", f"  {w}")
                else:
                    self._log_panel.append_line(
                        "INFO", f"Connector config {name}: legacy Start/End pin ranges")
            except Exception as exc:
                self._config_error = str(exc)
                self._log_panel.append_line(
                    "ERROR", f"Connector config {name} is invalid — Start is blocked until it is fixed:")
                for line in str(exc).splitlines():
                    self._log_panel.append_line("ERROR", f"  {line}")
        self._update_start_enabled()

    def _on_connector_config_changed(self, path: str) -> None:
        self._validate_connector_config()
        if self._netlist_path:
            self._on_netlist_browsed(self._netlist_path)

    # ------------------------------------------------------------------
    # Netlist
    # ------------------------------------------------------------------

    def _on_menu_load_netlist(self) -> None:
        self._left_panel._browse_netlist()

    def _on_netlist_browsed(self, path: str) -> None:
        # Validate the netlist loads cleanly before accepting it
        try:
            from core.netlist import load_netlist, apply_connector_config, PinRefError
            netlist = load_netlist(path)
        except Exception as exc:
            QMessageBox.critical(self, "Netlist Error",
                f"Could not load netlist:\n{exc}\n\nPlease fix the file and try again.")
            self._has_netlist = False
            self._netlist_path = ""
            self._update_start_enabled()
            return

        # Apply the connector configuration mapping.  connector_config.xlsx is
        # the only source of truth for which channels exist and which
        # connector pin each one is — nothing here is checked against the
        # firmware, so a netlist channel the config doesn't list is unknown
        # to us and blocks Start rather than risking a silent false PASS.
        cfg_path = self._config_panel.config_path()
        self._connector_pin_map: dict[int, tuple[str, int]] = {}
        self._pin_map_b: dict[int, tuple[str, int]] = {}
        self._dest_labels: dict[str, str] = {}
        self._netlist_error = ""
        if cfg_path and os.path.exists(cfg_path):
            try:
                apply_connector_config(netlist, cfg_path)
                self._connector_pin_map = self._build_connector_pin_map(cfg_path)
                self._log_panel.append_line(
                    "INFO", f"Connector config applied: {os.path.basename(cfg_path)}"
                )
                # With Dest Pins each wire end was looked up in the config when
                # the connector pins were turned into channels (see PinRefError).
                unmapped = [] if self._pin_map_b else sorted(
                    {p.number for n in netlist.nets for p in n.pins}
                    - set(self._connector_pin_map))
                if unmapped:
                    self._netlist_error = f"channels {unmapped} not in connector config"
                    self._log_panel.append_line(
                        "ERROR",
                        f"Netlist uses channel(s) {', '.join(map(str, unmapped))} that "
                        f"{os.path.basename(cfg_path)} does not list. Add them to the "
                        f"connector config, or fix the netlist — Start is blocked "
                        f"until this is resolved.")
            except PinRefError as exc:
                # The netlist names connector pins the config does not have, so
                # its numbers were not turned into channels.  Testing it would
                # use the wrong channels.
                self._netlist_error = "wire ends not in connector config"
                self._log_panel.append_line(
                    "ERROR",
                    f"Netlist does not match {os.path.basename(cfg_path)} — Start is "
                    f"blocked until this is resolved:")
                for line in str(exc).splitlines():
                    self._log_panel.append_line("ERROR", f"  {line}")
            except Exception as exc:
                self._log_panel.append_line(
                    "WARN", f"Connector config failed: {exc}"
                )

        self._netlist_path = path
        self._netlist      = netlist
        self._has_netlist  = True
        self._update_start_enabled()
        hid_info = f"  [Harness: {netlist.harness_id}]" if netlist.harness_id else ""
        self._log_panel.append_line(
            "INFO", f"Netlist loaded: {os.path.basename(path)}{hid_info} — {len(netlist.nets)} net(s)"
        )
        if netlist.warnings:
            for w in netlist.warnings:
                self._log_panel.append_line("WARN", f"  {w}")
        self._load_wiring_diagram(netlist)

    def _build_connector_pin_map(self, cfg_path: str) -> dict[int, tuple[str, int]]:
        from core.netlist import connector_pin_mapping, connector_pin_mapping_b, dest_labels
        self._dest_labels = dest_labels(cfg_path)
        # Side B has connectors of its own only when the config has a Dest Pin.
        self._pin_map_b = connector_pin_mapping_b(cfg_path)
        return connector_pin_mapping(cfg_path)

    def _dest(self, conn_id: str) -> str:
        """Name a connector goes by at the Side-B end (Dst Conn ID)."""
        return getattr(self, "_dest_labels", {}).get(conn_id, conn_id)

    def _display_pins(self, pin_a: int, pin_b: int) -> tuple[int, int]:
        """Return local display pin numbers for a global pin pair."""
        mapping = getattr(self, "_connector_pin_map", {})
        mapping_b = getattr(self, "_pin_map_b", None) or mapping
        da = mapping.get(pin_a, ("", pin_a))[1]
        db = mapping_b.get(pin_b, ("", pin_b))[1]
        return da, db

    def _load_wiring_diagram(self, netlist) -> None:
        cont_pairs: list[tuple] = []

        for net in netlist.nets:
            # Pin order is significant — see Netlist.ordered_pairs().  Sorting
            # by pin number here would drag the lower-numbered pin into the
            # Source column and carry the wrong connector's label with it.
            pins = net.pins
            for i in range(len(pins)):
                for j in range(i + 1, len(pins)):
                    pa, pb = pins[i], pins[j]
                    disp_a, disp_b = self._display_pins(pa.number, pb.number)
                    conn_id = net.connector_id or ""
                    # Group by connector in the wiring diagram
                    display_net = f"{conn_id} / {net.name}" if conn_id else net.name
                    # Destination connector of THIS pair.  Looked up per pin
                    # from the connector config so multi-pin nets work; falls
                    # back to the netlist's own Conn ID B.  A different
                    # connector than the source makes this an interconnect
                    # wire, drawn in its own section by ConnectorView.
                    conn_b = (getattr(self, "_pin_map_b", None)
                              or getattr(self, "_connector_pin_map", {})
                              ).get(pb.number, ("", 0))[0] \
                        or net.connector_id_b or conn_id
                    cont_pairs.append((
                        pa.number, pb.number, display_net,
                        pa.name or f"Pin {disp_a}",
                        pb.name or f"Pin {disp_b}",
                        net.source, net.destination,
                        disp_a, disp_b,
                        net.connector_part_number,
                        net.connector_part_number_b,
                        conn_id,
                        conn_b,
                        net.wire_colour,
                    ))

        # Sort by connector, then by global pin numbers
        cont_pairs.sort(key=lambda x: (x[2], x[0], x[1]))

        # Every connector in the config, with all its pins, so the Single view
        # can show all of them on both sides even where the netlist uses few.
        layout = None
        pin_map = getattr(self, "_connector_pin_map", {})
        if pin_map:
            by_conn: dict[str, list[tuple[int, int]]] = {}
            for ch, (conn, local) in pin_map.items():
                by_conn.setdefault(conn, []).append((ch, local))
            part_a: dict[str, str] = {}
            part_b: dict[str, str] = {}
            for net in netlist.nets:
                if net.connector_part_number:
                    part_a.setdefault(net.connector_id, net.connector_part_number)
                if net.connector_part_number_b:
                    part_b.setdefault(net.connector_id_b, net.connector_part_number_b)
            layout = [
                {"conn": conn, "pins": sorted(pins),
                 "part_a": part_a.get(conn, ""), "part_b": part_b.get(conn, "")}
                for conn, pins in sorted(by_conn.items(),
                                         key=lambda kv: min(ch for ch, _ in kv[1]))
            ]

        # Side-B connectors of their own (a Dest Pin in the config): drawn as
        # separate blocks, each with the Side-B pin numbers.
        layout_b = None
        pin_map_b = getattr(self, "_pin_map_b", {})
        if layout and pin_map_b:
            by_conn_b: dict[str, list[tuple[int, int]]] = {}
            for ch, (conn, local) in pin_map_b.items():
                by_conn_b.setdefault(conn, []).append((ch, local))
            layout_b = [
                {"conn": conn, "pins": sorted(pins, key=lambda cp: cp[1]),
                 "part_b": part_b.get(conn, "")}
                for conn, pins in sorted(by_conn_b.items(),
                                         key=lambda kv: min(ch for ch, _ in kv[1]))
            ]

        self._matrix_view.set_connections(cont_pairs, layout=layout,
                                          dest_labels=getattr(self, "_dest_labels", {}),
                                          layout_b=layout_b)
        self._log_panel.append_line(
            "INFO",
            f"Wiring diagram: {len(cont_pairs)} continuity pairs across {len(netlist.nets)} nets",
        )

    # ------------------------------------------------------------------
    # Test start / stop
    # ------------------------------------------------------------------

    def _on_start_requested(self) -> None:
        if not self._connected or self._engine is None:
            return

        # Refresh connector pin mapping in case the config changed
        self._config_panel.flush()
        cfg_path = self._config_panel.config_path()
        self._dest_labels = {}
        self._pin_map_b = {}
        self._connector_pin_map = (
            self._build_connector_pin_map(cfg_path)
            if cfg_path and os.path.exists(cfg_path) else {}
        )

        dut_id   = self._left_panel.get_dut_id()
        self._last_dut_id = dut_id
        profile  = self._left_panel.get_current_profile_name()
        self.setWindowTitle(f"Harness Tester v{APP_VERSION} — {profile} — {dut_id}")
        modes = self._test_bar.get_test_modes()

        if self._left_panel.is_auto_test_mode():
            self._is_auto_test = True
            self._auto_scan_pairs = []
            self._left_panel.set_auto_scan_result_available(False)
            # Reset display for fresh auto test run
            self._test_counter = 0
            self._pass_count   = 0
            self._fail_count   = 0
            self._scan_start_time = time.monotonic()
            self._elapsed_timer.start()
            self._results_table.set_cross_continuity(False)
            self._results_table.clear()
            self._matrix_view.reset()
            self._matrix_view.set_connections([], [])  # clear old netlist diagram during auto scan
            self._test_bar.set_verdict("")
            self._log_panel.append_line(
                "INFO",
                "Auto-Scan started — CMD_AUTO_SCAN: probing all 37 × 37 pairs, showing only connected pins",
            )
            self._engine.start_auto_test(modes)
        else:
            self._is_auto_test = False
            if not (modes.continuity or modes.cross_continuity):
                QMessageBox.warning(self, "No Test Mode Selected",
                    "Please select Continuity or Cross Continuity before starting.")
                return
            if not self._has_netlist:
                self._log_panel.append_line(
                    "INFO",
                    "No netlist loaded — firmware will scan 37 default straight pairs (A1↔B1 … A37↔B37)",
                )
                self.statusBar().showMessage("Default scan: 37 straight pairs (no netlist)", 5000)
            self._test_counter   = 0
            self._pass_count     = 0
            self._fail_count     = 0
            self._progress_done  = 0
            self._progress_total = 0
            self._scan_start_time = time.monotonic()
            self._elapsed_timer.start()
            self._results_table.set_cross_continuity(modes.cross_continuity)
            self._results_table.clear()
            self._matrix_view.reset()
            self._test_bar.set_verdict("")
            mode_name = "Cross Continuity" if modes.cross_continuity else "Continuity"
            self._log_panel.append_line("INFO", f"{mode_name} test started")
            # Upload the netlist as loaded (connector pins already turned into
            # channels), not the file again, which still has the connector pins.
            self._engine.start_test(self._netlist_path, modes,
                                    self._netlist if self._has_netlist else None)

    def _on_stop_requested(self) -> None:
        if self._engine:
            self._engine.abort()

    # ------------------------------------------------------------------
    # State machine → UI
    # ------------------------------------------------------------------

    def on_state_changed(self, state: TestState) -> None:
        is_idle   = state in (TestState.IDLE, TestState.COMPLETE)
        is_active = state in (TestState.UPLOADING, TestState.CALIBRATING,
                              TestState.SCANNING)

        if state == TestState.UPLOADING and not self._is_auto_test:
            self._test_counter   = 0
            self._pass_count     = 0
            self._fail_count     = 0
            self._progress_done  = 0
            self._progress_total = 0
            self._scan_start_time = time.monotonic()
            self._elapsed_timer.start()
            self._results_table.clear()
            self._matrix_view.reset()
            self._test_bar.set_verdict("")

        if is_idle:
            self._elapsed_timer.stop()
            if self._scan_start_time:
                self._last_duration_s = time.monotonic() - self._scan_start_time
            self._test_bar.set_controls_enabled(True)
            self._update_start_enabled()

        if is_active:
            self._test_bar.set_controls_enabled(False)

    def _update_start_enabled(self) -> None:
        engine_ready = (self._engine is None or
                        self._engine.state in (TestState.IDLE, TestState.COMPLETE))
        self._test_bar.set_start_enabled(
            self._connected and engine_ready
            and not self._config_error and not self._netlist_error
        )

    # ------------------------------------------------------------------
    # Live result handlers
    # ------------------------------------------------------------------

    def _lookup_net_info(self, pin_a: int, pin_b: int, defaults: dict) -> tuple:
        """Return (net_name, pin_a_name, pin_b_name, connector_id, connector_id_b,
        connector_part_number, connector_part_number_b, connector_detail,
        source, destination).

        Fields missing from the netlist (or absent when no netlist is loaded / Auto-Scan
        mode) are filled from *defaults* — the values configured in the GUI.
        """
        def_conn   = defaults.get("connector_id", "")
        def_conn_b = defaults.get("connector_id_b", "")
        def_src    = defaults.get("source", "")
        def_dst    = defaults.get("destination", "")

        if self._netlist is None:
            return "", "", "", def_conn, def_conn_b, "", "", "", def_src, def_dst

        net = self._netlist.net_for_pins(pin_a, pin_b)
        if net is None:
            return "", "", "", def_conn, def_conn_b, "", "", "", def_src, def_dst

        if pin_a == pin_b:
            # Same-index straight-through net: first pin = A-side, second = B-side
            pa_name = net.pins[0].name if net.pins else ""
            pb_name = net.pins[1].name if len(net.pins) > 1 else ""
        else:
            pa_name = next((p.name for p in net.pins if p.number == pin_a), "")
            pb_name = next((p.name for p in net.pins if p.number == pin_b), "")
        return (
            net.name,
            pa_name,
            pb_name,
            net.connector_id     or def_conn,
            net.connector_id_b   or def_conn_b,
            net.connector_part_number,
            net.connector_part_number_b,
            net.connector_detail,
            net.source           or def_src,
            net.destination      or def_dst,
        )

    def _wire_info(self, pin_a: int, pin_b: int) -> dict:
        """Colour, AWG, length and harness no. the netlist gives this wire."""
        net = self._netlist.net_for_pins(pin_a, pin_b) if self._netlist else None
        if net is None:
            return {}
        return {"wire_colour": net.wire_colour, "awg": net.awg,
                "length": net.length, "harness_no": net.harness_no}

    def _on_cont_result(self, result: ContResult) -> None:
        self._test_counter += 1
        defaults = self._left_panel.get_connector_defaults()
        (net_name, pa_name, pb_name, conn_id, conn_id_b,
         conn_part_number, conn_part_number_b, conn_detail, src, dst) = self._lookup_net_info(
            result.pin_a, result.pin_b, defaults
        )
        disp_a, disp_b = self._display_pins(result.pin_a, result.pin_b)
        if getattr(self, "_pin_map_b", None):
            # Side B has its own connectors: name both ends from the config, so
            # a wire found where the netlist has none is labelled correctly too.
            conn_id = self._connector_pin_map.get(result.pin_a, ("", 0))[0] or conn_id
            conn_id_b = self._pin_map_b.get(result.pin_b, ("", 0))[0] or conn_id_b
        tr = TestResult(
            test_num=self._test_counter,
            pin_a=result.pin_a,
            pin_b=result.pin_b,
            test_type=TestType.CONTINUITY,
            status=result.status,
            resistance_mohm=result.resistance_mohm,
            net_name=net_name,
            pin_a_name=pa_name,
            pin_b_name=pb_name,
            connector_id=conn_id,
            connector_id_b=self._dest(conn_id_b),
            connector_detail=conn_detail,
            connector_part_number=conn_part_number,
            connector_part_number_b=conn_part_number_b,
            source=src,
            destination=dst,
            timestamp=datetime.now(),
            display_pin_a=disp_a,
            display_pin_b=disp_b,
            **self._wire_info(result.pin_a, result.pin_b),
        )
        # In Auto-Scan mode only record and display connections (PASS); skip open/fail noise
        if not self._is_auto_test or result.status == ResultStatus.PASS:
            self._results_table.append_result(tr)
            pin_state = PinState.PASS if result.status == ResultStatus.PASS else PinState.FAIL
            self._matrix_view.update_pin(result.pin_a, result.pin_b, pin_state)

        if result.status == ResultStatus.PASS:
            self._pass_count += 1
        elif result.status != ResultStatus.NOT_CONNECTED and not self._is_auto_test:
            # open/miswire results are expected in auto-scan — not failures
            self._fail_count += 1

        if self._engine:
            self._engine.count_result(result.status)

    def _on_progress(self, done: int, total: int) -> None:
        self._progress_done  = done
        self._progress_total = total
        elapsed = time.monotonic() - self._scan_start_time if self._scan_start_time else 0.0
        self._test_bar.set_progress(done, total, elapsed)

    def _on_verdict_ready(self, verdict: Verdict) -> None:
        labels = {
            Verdict.PASS:         "PASS",
            Verdict.FAIL:         "FAIL",
            Verdict.INCONCLUSIVE: "INCONCLUSIVE",
        }
        text = labels.get(verdict, "")
        self._last_verdict = text
        self._test_bar.set_verdict(text)
        self._log_panel.append_line(
            "INFO" if verdict == Verdict.PASS else "WARN",
            f"Test complete — {text}  (PASS: {self._pass_count}, FAIL: {self._fail_count})",
        )

        # If firmware did not stream every pair, fill in the missing NOT_CONNECTED rows
        # so the cross-continuity matrix is complete.
        if self._results_table.is_cross_continuity:
            self._expand_cross_continuity_not_connected()

        # Final sort for cross-continuity matrix order
        self._results_table.sort_cross_continuity()
        self._results_table.renumber_cross_continuity()

        # Auto-save results to CSV
        self._auto_save_results(text)

        # Auto-increment DUT ID for the next test
        self._left_panel.increment_dut_id()

        if verdict == Verdict.FAIL:
            self._tabs.setCurrentIndex(1)

    def _expand_cross_continuity_not_connected(self) -> None:
        """Generate NOT_CONNECTED rows for every missing pair in the cross-continuity matrix.

        This lets the GUI display the full matrix even when the firmware only reports
        PASS/OPEN/MISWIRE pairs and omits the correct open pairs.
        """
        existing = {
            (r.pin_a, r.pin_b)
            for r in self._results_table.model.all_results()
        }
        defaults = self._left_panel.get_connector_defaults()
        pins = sorted(self._connector_pin_map.keys()) if self._connector_pin_map else list(range(1, 38))
        # Side B has its own pigtails when the config has Dest Pins.
        pins_b = sorted(self._pin_map_b) if self._pin_map_b else pins

        generated = 0
        for a in pins:
            for b in pins_b:
                if (a, b) in existing:
                    continue
                self._test_counter += 1
                (net_name, pa_name, pb_name, _conn_id, _conn_id_b,
                 _conn_part_number, _conn_part_number_b, conn_detail, src, dst) = self._lookup_net_info(a, b, defaults)
                disp_a, disp_b = self._display_pins(a, b)
                # Use connector config mapping if available so verbose labels show connector names
                conn_id   = self._connector_pin_map.get(a, (_conn_id, disp_a))[0] or _conn_id
                conn_id_b = ((getattr(self, "_pin_map_b", None) or self._connector_pin_map)
                             .get(b, (_conn_id_b, disp_b))[0] or _conn_id_b)
                tr = TestResult(
                    test_num=self._test_counter,
                    pin_a=a,
                    pin_b=b,
                    test_type=TestType.CONTINUITY,
                    status=ResultStatus.NOT_CONNECTED,
                    resistance_mohm=0.0,
                    net_name=net_name,
                    pin_a_name=pa_name,
                    pin_b_name=pb_name,
                    connector_id=conn_id,
                    connector_id_b=self._dest(conn_id_b),
                    connector_detail=conn_detail,
                    connector_part_number=_conn_part_number,
                    connector_part_number_b=_conn_part_number_b,
                    source=src,
                    destination=dst,
                    timestamp=datetime.now(),
                    display_pin_a=disp_a,
                    display_pin_b=disp_b,
                    **self._wire_info(a, b),
                )
                self._results_table.append_result(tr)
                generated += 1

        if generated:
            self._log_panel.append_line(
                "INFO",
                f"Cross-continuity matrix completed — added {generated} NOT CONNECTED pair(s)"
            )

    def _on_auto_test_complete(self) -> None:
        self._is_auto_test = False
        # All results in auto mode are already PASS-only; just read the table
        discovered = [
            (r.pin_a, r.pin_b)
            for r in self._results_table.model.all_results()
        ]

        n = len(discovered)
        self._log_panel.append_line(
            "INFO",
            f"Auto-Scan complete — {n} connection{'s' if n != 1 else ''} discovered"
            + (f": {', '.join(f'A{a}→B{b}' for a, b in discovered)}" if n else ""),
        )
        self.statusBar().showMessage(f"Auto-Scan complete — {n} connection(s) found", 6000)

        # Rebuild connector view with discovered pairs only.  Drawn from the
        # same netlist "Use as Netlist" would load, so pins get their
        # connector names and per-connector numbers from the config.
        self._auto_scan_pairs = sorted(set(discovered))
        if self._auto_scan_pairs:
            self._load_wiring_diagram(self._auto_scan_netlist())
            for pa, pb in self._auto_scan_pairs:
                self._matrix_view.update_pin(pa, pb, PinState.PASS)
        else:
            self._matrix_view.set_connections([], [])
        self._left_panel.set_auto_scan_result_available(bool(self._auto_scan_pairs))

        # Switch to Connector View tab
        self._tabs.setCurrentIndex(0)
        # verdictReady (emitted right after this) will handle save + DUT increment

    def _auto_scan_netlist(self, resolved: bool = True):
        """Netlist with one wire per pair found by the last Auto-Scan.

        When Side B has its own connectors (a Dest Pin in the config) a netlist
        file is written in connector pins, which the config turns back into
        channels on load.  resolved=False gives that file form; resolved=True
        gives the channel form the wiring diagram is drawn from.
        """
        from core.netlist import Net, NetPin, Netlist, apply_connector_config
        pin_map = getattr(self, "_connector_pin_map", {})
        pin_map_b = getattr(self, "_pin_map_b", {})

        def end(side: str, ch: int) -> tuple[str, int]:
            return (pin_map_b if side == "B" and pin_map_b else pin_map).get(ch, ("", ch))

        def make(i: int, pa: int, pb: int) -> Net:
            (conn_a, pin_a), (conn_b, pin_b) = end("A", pa), end("B", pb)
            net = Net(name=f"WIRE_{i:02d}",
                      pins=[NetPin(pa, f"A{pin_a:02d}"), NetPin(pb, f"B{pin_b:02d}")],
                      source="Side-A", destination="Side-B")
            if pin_map_b:
                net.pins[0].number, net.pins[1].number = pin_a, pin_b
                net.connector_id, net.connector_id_b = conn_a, conn_b
            return net

        netlist = Netlist(nets=[make(i, pa, pb) for i, (pa, pb)
                                in enumerate(self._auto_scan_pairs, start=1)])
        cfg_path = self._config_panel.config_path()
        if resolved and cfg_path and os.path.exists(cfg_path):
            try:
                apply_connector_config(netlist, cfg_path)
            except Exception:
                pass   # an invalid config is already reported and blocks Start
        return netlist

    def _on_use_auto_scan_as_netlist(self) -> None:
        """Save the last Auto-Scan result as a netlist file and load it."""
        if not self._auto_scan_pairs:
            return
        from core.netlist import save_netlist_xlsx
        os.makedirs(paths.netlists_dir(), exist_ok=True)
        path = os.path.join(paths.netlists_dir(),
                            f"autoscan_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx")
        try:
            save_netlist_xlsx(self._auto_scan_netlist(resolved=not self._pin_map_b), path)
        except OSError as exc:
            QMessageBox.critical(self, "Save Error", f"Could not save the netlist:\n{exc}")
            return
        self._on_netlist_browsed(path)
        if self._has_netlist and self._netlist_path == path:
            self._left_panel.show_netlist(path, self._netlist)
            self._log_panel.append_line(
                "INFO", f"Auto-Scan result loaded as netlist → {path}")
            self.statusBar().showMessage(
                f"Auto-Scan result is now the netlist ({len(self._auto_scan_pairs)} wires) "
                f"— Standard mode selected", 6000)

    def _on_save_netlist_as(self) -> None:
        """File -> Save Netlist As… — keep the active netlist as a JSON file."""
        if not self._netlist:
            QMessageBox.information(self, "No Netlist", "No netlist is loaded.")
            return
        default = self._netlist_path or os.path.join(paths.netlists_dir(), "netlist.json")
        if not default.lower().endswith(".json"):
            default = os.path.splitext(default)[0] + ".json"
        path, _ = QFileDialog.getSaveFileName(
            self, "Save Netlist As", default, "JSON (*.json);;All files (*)")
        if not path:
            return
        if not path.lower().endswith(".json"):
            path += ".json"
        from core.netlist import save_netlist
        try:
            save_netlist(self._netlist, path)
        except OSError as exc:
            QMessageBox.critical(self, "Save Error", f"Could not save the netlist:\n{exc}")
            return
        self._log_panel.append_line("INFO", f"Netlist saved → {path}")

    def _on_nack_received(self, rejected_cmd: int) -> None:
        self._log_panel.append_line("WARN", f"Firmware rejected command 0x{rejected_cmd:02X}")

    _FAULT_STUCK_PINS = 0x01

    def _on_fault_received(self, code: int, data: int) -> None:
        if code != self._FAULT_STUCK_PINS:
            self._log_panel.append_line(
                "ERROR", f"Firmware fault 0x{code:02X}, data 0x{data:08X}")
            return

        # data packs the first four offending pin numbers, one per byte.
        pins = [b for b in data.to_bytes(4, "big") if b]
        names = ", ".join(f"B{p}" for p in pins)
        more = " (and others)" if len(pins) == 4 else ""
        self._log_panel.append_line(
            "ERROR",
            f"Stuck input(s) before the scan: {names}{more}. These read HIGH "
            f"with every Side-A pin driven LOW, so they would report a "
            f"connection to every pin. Results are not trustworthy until this "
            f"is resolved — check for a short to 3V3 on those channels.")
        self.statusBar().showMessage(
            f"Stuck input(s): {names}{more} — results unreliable", 0)

    # ------------------------------------------------------------------
    # Calibration
    # ------------------------------------------------------------------

    def _on_refresh_fw_info(self) -> None:
        if self._worker and self._connected:
            self._worker.send_packet(Cmd.GET_STATUS)

    def _on_calibrate(self) -> None:
        if self._engine and self._connected:
            self._engine.calibrate()
            self._log_panel.append_line("INFO", "Calibration started…")
        else:
            self.statusBar().showMessage("Not connected — cannot calibrate", 3000)

    def _on_netlist_editor(self) -> None:
        """Tools -> Netlist Editor."""
        netlist = None
        path = ""
        if self._has_netlist and self._netlist:
            from copy import deepcopy
            netlist = deepcopy(self._netlist)
            path = self._netlist_path
        dialog = NetlistEditorDialog(self, netlist=netlist, path=path)
        if dialog.exec() == QDialog.DialogCode.Accepted:
            saved_path = dialog.netlist_path()
            if saved_path:
                self._on_netlist_browsed(saved_path)
                self._log_panel.append_line("INFO", f"Netlist saved and loaded → {saved_path}")

    def _on_golden_sample(self) -> None:
        """Tools -> Golden Sample Learning."""
        results = self._results_table.model.all_results()
        if not results:
            QMessageBox.information(
                self, "No Auto-Scan Results",
                "Run Auto-Scan first, then use this wizard to save the discovered connections as a netlist."
            )
            return

        pairs = [(r.pin_a, r.pin_b) for r in results if r.status == ResultStatus.PASS]
        if not pairs:
            QMessageBox.information(self, "No Connections", "No PASS connections were discovered.")
            return

        harness_id = ""
        if self._netlist:
            harness_id = self._netlist.harness_id

        wizard = GoldenSampleWizard(self, pairs=pairs, harness_id=harness_id)
        wizard.exec()
        saved_path = wizard.saved_path()
        if saved_path:
            self._on_netlist_browsed(saved_path)
            self._log_panel.append_line("INFO", f"Golden sample netlist saved and loaded → {saved_path}")

    def _on_calibration_complete(self, offset_mohm: int) -> None:
        self._log_panel.append_line("INFO", f"Calibration complete — offset {offset_mohm} mΩ")
        QMessageBox.information(self, "Calibration Complete",
            f"Calibration offset: {offset_mohm} mΩ\n"
            "The offset has been applied to resistance measurements.")

    # ------------------------------------------------------------------
    # Result persistence
    # ------------------------------------------------------------------

    def _auto_save_results(self, verdict: str) -> None:
        """Save the current results to a timestamped CSV in profiles/results/."""
        results = self._results_table.display_ordered_results()
        if not results:
            return
        dut_id   = self._left_panel.get_dut_id()
        operator = self._left_panel.get_operator()
        ts       = datetime.now().strftime("%Y%m%d_%H%M%S")
        fname    = f"report_{ts}_{dut_id}.csv"
        path     = os.path.join(RESULTS_DIR, fname)

        try:
            self._write_results_csv(path, results, dut_id, operator, verdict)
            self._log_panel.append_line("INFO", f"Results saved → {fname}")
            self.statusBar().showMessage(f"Results saved: {fname}", 4000)
        except OSError as exc:
            self._log_panel.append_line("WARN", f"Could not auto-save results: {exc}")

    def _write_results_csv(self, path: str, results, dut_id: str,
                           operator: str, verdict: str) -> None:
        # Cross-connection layout: source side → Status → destination side.
        _CSV_HEADERS = [
            "Test #", "Source", "Part Number", "Conn ID",
            "Src Pin Label", "Src Pin #",
            "Status",
            "Dst Pin #", "Dst Pin Label",
            "Conn ID", "Part Number", "Destination",
            "Colour", "AWG", "Length", "Harness No",
        ]
        _STATUS_STR = {1: "CONNECTED", 2: "NOT CONNECTED", 3: "NOT CONNECTED", 4: "NOT CONNECTED"}
        with open(path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["# Harness Tester Results"])
            writer.writerow(["# DUT ID",    dut_id])
            writer.writerow(["# Operator",  operator])
            writer.writerow(["# Netlist",   os.path.basename(self._netlist_path)])
            writer.writerow(["# Verdict",   verdict])
            writer.writerow(["# Date/Time", datetime.now().strftime("%Y-%m-%d %H:%M:%S")])
            writer.writerow([])
            writer.writerow(_CSV_HEADERS)
            for r in results:
                disp_a = r.display_pin_a or r.pin_a
                disp_b = r.display_pin_b or r.pin_b
                writer.writerow([
                    r.test_num,
                    r.source,
                    r.connector_part_number,
                    r.connector_id,
                    r.pin_a_name or f"Pin {disp_a}",
                    disp_a,
                    _STATUS_STR.get(int(r.status), ""),
                    disp_b,
                    r.pin_b_name or f"Pin {disp_b}",
                    r.connector_id_b,
                    r.connector_part_number_b,
                    r.destination,
                    r.wire_colour,
                    r.awg,
                    r.length,
                    r.harness_no,
                ])

    def _on_save_results_csv(self) -> None:
        """File → Save Results as CSV — manual save with file chooser."""
        results = self._results_table.display_ordered_results()
        if not results:
            QMessageBox.information(self, "No Results", "No test results to save yet.")
            return
        dut_id = self._last_dut_id or self._left_panel.get_dut_id()
        default = os.path.join(RESULTS_DIR,
                               f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{dut_id}.csv")
        path, _ = QFileDialog.getSaveFileName(
            self, "Save Results", default,
            "CSV files (*.csv);;All files (*)"
        )
        if not path:
            return
        try:
            self._write_results_csv(path, results, dut_id,
                                    self._left_panel.get_operator(), self._last_verdict or "—")
            self._log_panel.append_line("INFO", f"Results manually saved → {path}")
        except OSError as exc:
            QMessageBox.critical(self, "Save Error", f"Could not save file:\n{exc}")

    def _open_results_folder(self) -> None:
        os.makedirs(RESULTS_DIR, exist_ok=True)
        QDesktopServices.openUrl(QUrl.fromLocalFile(os.path.abspath(RESULTS_DIR)))

    def _on_export_pdf(self) -> None:
        """File -> Export PDF Report."""
        results = self._results_table.display_ordered_results()
        if not results:
            QMessageBox.information(self, "No Results", "No test results to export yet.")
            return

        dut_id = self._last_dut_id or self._left_panel.get_dut_id()
        default = os.path.join(
            RESULTS_DIR,
            f"report_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{dut_id}.pdf"
        )
        path, _ = QFileDialog.getSaveFileName(
            self, "Export PDF Report", default,
            "PDF files (*.pdf);;All files (*)"
        )
        if not path:
            return

        metadata = ReportMetadata(
            dut_id=dut_id,
            operator=self._left_panel.get_operator(),
            profile=self._left_panel.get_current_profile_name(),
            netlist_name=os.path.basename(self._netlist_path) if self._netlist_path else "",
            fw_version=self._fw_version_str,
            verdict=self._last_verdict,
            timestamp=datetime.now(),
            duration_s=self._last_duration_s,
        )

        self._log_panel.append_line("INFO", f"Exporting PDF report → {os.path.basename(path)}")
        # Keep references on self so the QThread/worker are not garbage-collected
        # mid-run (otherwise the export silently dies before the file is written).
        thread, worker = run_pdf_worker(path, results, metadata, LOGO_PATH, parent=self)
        self._pdf_thread = thread
        self._pdf_worker = worker
        worker.finished.connect(lambda p: self._log_panel.append_line("INFO", f"PDF exported → {p}"))
        worker.error.connect(lambda e: QMessageBox.critical(self, "PDF Export Error", f"Could not export PDF:\n{e}"))
        thread.finished.connect(self._on_pdf_thread_finished)

    def _on_pdf_thread_finished(self) -> None:
        """Release the PDF export thread/worker references once it is done."""
        self._pdf_thread = None
        self._pdf_worker = None

    # ------------------------------------------------------------------
    # Elapsed timer tick
    # ------------------------------------------------------------------

    def _tick_elapsed(self) -> None:
        elapsed = time.monotonic() - self._scan_start_time
        self._test_bar.set_progress(
            self._progress_done, self._progress_total, elapsed
        )

    # ------------------------------------------------------------------
    # Theming
    # ------------------------------------------------------------------

    def _apply_theme(self, name: str) -> None:
        qss_path = os.path.join(
            os.path.dirname(__file__), "..", "resources", f"{name}_theme.qss"
        )
        if os.path.exists(qss_path):
            with open(qss_path, encoding="utf-8") as f:
                QApplication.instance().setStyleSheet(f.read())
        if hasattr(self, "_results_table"):
            self._results_table.set_dark_theme(name == "dark")
        self._save_setting("theme", name)

    # ------------------------------------------------------------------
    # Geometry persistence
    # ------------------------------------------------------------------

    def _restore_geometry(self) -> None:
        settings = self._load_settings()
        geom = settings.get("geometry")
        if geom:
            self.setGeometry(
                geom.get("x", 100), geom.get("y", 100),
                geom.get("w", 1280), geom.get("h", 800),
            )
        self._apply_theme(settings.get("theme", "dark"))

    def closeEvent(self, event: QCloseEvent) -> None:
        self._config_panel.flush()
        if self._worker:
            if self._engine:
                self._engine.abort()
            self._worker.stop()
            self._worker.wait(2000)
        g = self.geometry()
        self._save_setting("geometry",
            {"x": g.x(), "y": g.y(), "w": g.width(), "h": g.height()})
        super().closeEvent(event)

    # ------------------------------------------------------------------
    # Settings helpers
    # ------------------------------------------------------------------

    def _load_settings(self) -> dict:
        try:
            with open(SETTINGS_PATH, encoding="utf-8") as f:
                return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            return {}

    def _save_setting(self, key: str, value) -> None:
        settings = self._load_settings()
        settings[key] = value
        os.makedirs(os.path.dirname(SETTINGS_PATH), exist_ok=True)
        with open(SETTINGS_PATH, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=2)

    # ------------------------------------------------------------------
    # Dialogs
    # ------------------------------------------------------------------

    def _show_about(self) -> None:
        import PyQt6.QtCore as qtcore
        msg = QMessageBox(self)
        msg.setWindowTitle("About Harness Tester")
        msg.setText(
            f"<b>Harness Tester</b><br>"
            f"Version: {APP_VERSION}<br>"
            f"Protocol: v1.0<br>"
            f"Qt: {qtcore.qVersion()}<br>"
            f"Python: {__import__('sys').version.split()[0]}"
        )
        msg.exec()


def _sep() -> QLabel:
    s = QLabel("|")
    s.setStyleSheet("color: #555;")
    return s
