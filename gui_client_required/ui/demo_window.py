"""The Harness Tester window without the hardware.

Everything is the real MainWindow.  The only difference is the cable: Connect
opens a VirtualTester (core/virtual_device.py) instead of a COM port, so
connecting, calibrating, uploading, Continuity, Cross Continuity, Auto-Scan,
the Results Table, the Log, the PDF and CSV reports and "Use as Netlist" all
run the same code as with a tester on the bench.

The Demo menu decides what is "plugged in": by default a harness that matches
the loaded netlist (so a test passes), and a few clicks to break wires or add
stray ones so the failing cases can be shown too.
"""

from __future__ import annotations

from PyQt6.QtGui import QAction, QActionGroup
from PyQt6.QtWidgets import (
    QFileDialog, QInputDialog, QLabel, QMessageBox,
)

from core.serial_comm import SerialWorker
from core.virtual_device import SPEEDS, VirtualTester
from ui.main_window import MainWindow

DEMO_TAG = "DEMO - virtual tester, no hardware"


class DemoMainWindow(MainWindow):
    _follow_netlist = True            # the virtual harness matches the loaded netlist
    _virtual_tester: VirtualTester | None = None

    # ------------------------------------------------------------------
    # The virtual tester
    # ------------------------------------------------------------------

    @property
    def _tester(self) -> VirtualTester:
        if self._virtual_tester is None:
            self._virtual_tester = VirtualTester()
        return self._virtual_tester

    def _create_worker(self, port: str, baud: int) -> SerialWorker:
        return SerialWorker(port, baud, opener=self._tester.open)

    def setWindowTitle(self, title: str) -> None:       # noqa: N802
        super().setWindowTitle(title if "DEMO" in title else f"{title}   [{DEMO_TAG}]")

    # ------------------------------------------------------------------
    # Menu and banner
    # ------------------------------------------------------------------

    def _build_menu_bar(self) -> None:
        super()._build_menu_bar()
        mb = self.menuBar()
        help_action = next((a for a in mb.actions()
                            if a.text().replace("&", "") == "Help"), None)
        menu = mb.addMenu("&Demo")
        if help_action is not None:
            mb.removeAction(menu.menuAction())
            mb.insertMenu(help_action, menu)

        self._act_follow = QAction("Harness follows the loaded netlist", menu, checkable=True)
        self._act_follow.setChecked(True)
        self._act_follow.setToolTip("Loading a netlist plugs in a harness that matches it")
        self._act_follow.toggled.connect(self._on_follow_toggled)
        menu.addAction(self._act_follow)
        act = QAction("Plug in a harness from a netlist file…", menu)
        act.triggered.connect(self._on_plug_in_file)
        menu.addAction(act)
        menu.addSeparator()

        for text, slot in (("Break wire(s)…", self._on_break_wires),
                           ("Add stray wire(s) (miswire)…", self._on_add_stray),
                           ("Remove all faults", self._on_clear_faults),
                           ("Show what is plugged in", self._on_show_harness)):
            act = QAction(text, menu)
            act.triggered.connect(slot)
            menu.addAction(act)
        menu.addSeparator()

        speed_menu = menu.addMenu("Scan speed")
        group = QActionGroup(self)
        for name, step in SPEEDS.items():
            act = QAction(f"{name} ({step * 1000:.0f} ms per step)", speed_menu, checkable=True)
            act.setChecked(name == "Normal")
            act.triggered.connect(lambda _=False, s=step: self._set_speed(s))
            group.addAction(act)
            speed_menu.addAction(act)
        menu.addSeparator()
        act = QAction("About Demo mode", menu)
        act.triggered.connect(self._on_about_demo)
        menu.addAction(act)

    def _build_status_bar(self) -> None:
        super()._build_status_bar()
        banner = QLabel(f"  {DEMO_TAG}  ")
        banner.setStyleSheet("background:#B26A00; color:white; font-weight:bold; "
                             "border-radius:3px; padding:1px 6px;")
        self.statusBar().insertPermanentWidget(0, banner)

    # ------------------------------------------------------------------
    # What is plugged in
    # ------------------------------------------------------------------

    def _on_netlist_browsed(self, path: str) -> None:
        super()._on_netlist_browsed(path)
        if self._follow_netlist and self._has_netlist and not self._netlist_error:
            self._plug_in_netlist(self._netlist, announce=True)

    def _plug_in_netlist(self, netlist, announce: bool = False) -> None:
        pairs = [(a, b) for a, b, _net in netlist.ordered_pairs()]
        self._tester.harness.set_wires(pairs)
        if announce:
            self._log_panel.append_line(
                "INFO", f"DEMO: a harness that matches the netlist is plugged in "
                        f"({len(pairs)} wire(s), no faults)")

    def _on_follow_toggled(self, on: bool) -> None:
        self._follow_netlist = on
        if on and self._has_netlist and not self._netlist_error:
            self._plug_in_netlist(self._netlist, announce=True)

    def _on_plug_in_file(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self, "Netlist describing the harness to plug in", "",
            "Netlist files (*.json *.xlsx *.csv);;All files (*)")
        if not path:
            return
        from core.netlist import apply_connector_config, load_netlist
        try:
            netlist = load_netlist(path)
            cfg = self._config_panel.config_path()
            if cfg:
                apply_connector_config(netlist, cfg)
        except Exception as exc:
            QMessageBox.critical(self, "Netlist Error", f"Could not use that netlist:\n{exc}")
            return
        self._act_follow.setChecked(False)          # the harness is now this file, not the netlist
        self._plug_in_netlist(netlist)
        self._log_panel.append_line(
            "INFO", f"DEMO: harness from {path.replace(chr(92), '/').rsplit('/', 1)[-1]} plugged in "
                    f"({len(self._tester.harness.wires)} wire(s)); the loaded netlist is only "
                    f"what the tester is told to expect")

    # -- faults ---------------------------------------------------------------

    def _on_break_wires(self) -> None:
        if not self._tester.harness.wires:
            QMessageBox.information(self, "Nothing plugged in", "The virtual harness has no wires.")
            return
        count, ok = QInputDialog.getInt(self, "Break wires", "How many wires?", 1, 1, 50)
        if not ok:
            return
        for a, b in self._tester.harness.inject_open(count):
            self._log_panel.append_line("WARN", f"DEMO: wire broken - {self._wire_name(a, b)}")

    def _on_add_stray(self) -> None:
        count, ok = QInputDialog.getInt(self, "Stray wires", "How many stray wires?", 1, 1, 50)
        if not ok:
            return
        for a, b in self._tester.harness.inject_miswire(count):
            self._log_panel.append_line("WARN", f"DEMO: stray wire added - {self._wire_name(a, b)}")

    def _on_clear_faults(self) -> None:
        self._tester.harness.clear_faults()
        self._log_panel.append_line("INFO", "DEMO: all faults removed")

    def _on_show_harness(self) -> None:
        h = self._tester.harness
        lines = [f"{len(h.wires)} wire(s) plugged in "
                 f"({'follows the netlist' if self._follow_netlist else 'from a file'})."]
        for title, wires in (("Broken", h.open_wires), ("Stray", h.extra_wires)):
            if wires:
                lines.append(f"\n{title} wire(s):")
                lines += [f"  {self._wire_name(a, b)}" for a, b in wires]
        if len(lines) == 1:
            lines.append("No faults.")
        QMessageBox.information(self, "Virtual harness", "\n".join(lines))

    def _wire_name(self, a: int, b: int) -> str:
        """'J1 pin 5 -> X2 pin 6' for a pair of channels, from the connector config."""
        src = self._connector_pin_map.get(a) if getattr(self, "_connector_pin_map", None) else None
        side_b = getattr(self, "_pin_map_b", None) or getattr(self, "_connector_pin_map", None) or {}
        dst = side_b.get(b)
        left = f"{src[0]} pin {src[1]}" if src else f"A{a}"
        right = f"{self._dest(dst[0])} pin {dst[1]}" if dst else f"B{b}"
        return f"{left} -> {right}  (channels A{a} -> B{b})"

    # -- speed / about --------------------------------------------------------------

    def _set_speed(self, step_s: float) -> None:
        self._tester.step_s = step_s

    def _on_about_demo(self) -> None:
        QMessageBox.information(
            self, "About Demo mode",
            "This is the Harness Tester program with a simulated tester instead of the "
            "hardware.\n\n"
            "Press Connect to plug the virtual tester in. Load a netlist and run Continuity, "
            "Cross Continuity or Auto-Scan as usual.\n\n"
            "By default the harness that is plugged in matches the loaded netlist, so tests "
            "pass. Use the Demo menu to break wires or add stray ones, or to plug in a "
            "different harness from a netlist file. Auto-Scan finds whatever is plugged in.\n\n"
            "Nothing here touches a real tester. The demo keeps its own profiles and "
            "results, separate from the real program's.")
