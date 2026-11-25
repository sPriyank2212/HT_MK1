# -*- coding: utf-8 -*-
"""Capture the GUI screenshots used in the customer-package documents.

Runs the real MainWindow against a throw-away data folder (so nobody's own
profiles leak in) and feeds it the same result objects the serial worker would
emit.  No hardware is needed.  Output: assets/shots/*.png
"""
import os
import shutil
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
GUI = os.path.abspath(os.path.join(HERE, "..", ".."))
REPO = os.path.abspath(os.path.join(GUI, ".."))
OUT = os.path.join(HERE, "assets", "shots")
sys.path.insert(0, GUI)

tmp = tempfile.mkdtemp(prefix="ht_doc_")
from core import paths                     # noqa: E402
paths._data_dir = tmp                      # isolate profiles / results / settings

from PyQt6.QtCore import QPoint, Qt        # noqa: E402
from PyQt6.QtWidgets import QApplication, QGroupBox, QMessageBox   # noqa: E402
from core.data_types import (ContResult, FirmwareStatus, ResultStatus,  # noqa: E402
                             Verdict)
from ui.main_window import MainWindow      # noqa: E402
from ui.matrix_view import PinState        # noqa: E402

os.makedirs(OUT, exist_ok=True)
app = QApplication([])
win = MainWindow()
win.resize(1560, 880)
win.show()


def pump(sec=0.4):
    end = time.time() + sec
    while time.time() < end:
        app.processEvents()


def save(widget, name):
    widget.grab().save(os.path.join(OUT, name))
    print("saved", name)


class _FakeWorker:
    _port, _baud = "COM5", 115200


pump(1.0)
win._apply_theme("light")
pump(0.5)

# ── Idle, not connected ──────────────────────────────────────────────────────
def stlink_port():
    cb = win._left_panel._cb_port
    cb.clear()
    cb.addItem("* COM5 - STMicroelectronics STLink Virtual COM Port", "COM5")


stlink_port()
pump(0.2)
save(win._left_panel, "panel_left_idle.png")
save(win._test_bar, "toolbar_idle.png")

# ── Connect (as the firmware would answer) ────────────────────────────────────────
win._worker = _FakeWorker()
win._on_status_received(FirmwareStatus(0, 0, "2.2.0", 120))
stlink_port()
win._update_start_enabled()
pump(0.3)
win._left_panel._edit_operator.setText("Operator 1")
win._left_panel._edit_session_harness_id.setText("HRN-0001")
pump(0.2)

# ── Load the demonstration netlist ─────────────────────────────────────────────────
NL = os.path.join(REPO, "netlists", "example_cross_connector_test.xlsx")
win._left_panel._netlist_path = NL
win._left_panel._lbl_netlist_file.setText(os.path.basename(NL))
from core.netlist import load_netlist      # noqa: E402
netlist = load_netlist(NL)
win._left_panel._populate_netlist_tree(netlist)
win._on_netlist_browsed(NL)
pump(0.8)
win._tabs.setCurrentIndex(0)
save(win._left_panel, "panel_left_loaded.png")
for gb in win._left_panel.findChildren(QGroupBox):
    save(gb, "grp_" + gb.title().split()[0].lower() + ".png")
save(win._test_bar, "toolbar_ready.png")
pump(0.3)
save(win._matrix_view, "view_single_loaded.png")
leg = win._matrix_view.layout().itemAt(win._matrix_view.layout().count() - 1).widget()
save(leg, "legend.png")
bar = win._matrix_view.layout().itemAt(0).layout()
save(win._matrix_view, "view_bar_probe.png") if False else None

# ── Run a Mode 1 test, all wires present ──────────────────────────────────────────────
pairs = netlist.all_pairs()
win._results_table.clear()
win._matrix_view.reset()
for pa, pb in pairs:
    win._on_cont_result(ContResult(pa, pb, 50.0, ResultStatus.PASS))
win._on_progress(len(pairs), len(pairs))
pump(0.3)
win._test_bar.set_controls_enabled(False)
pump(0.2)
save(win._test_bar, "toolbar_running.png")
win._test_bar.set_controls_enabled(True)
win._update_start_enabled()
win._on_verdict_ready(Verdict.PASS)
win._test_bar.set_progress(len(pairs), len(pairs), 0.213)
win._tabs.setCurrentIndex(0)
pump(0.6)
save(win._matrix_view, "view_single_pass.png")
win.resize(1180, 880); pump(0.6)
save(win._matrix_view._combined, "diagram_pass.png")
win.resize(1560, 880); pump(0.4)
save(win._test_bar, "toolbar_pass.png")
save(win, "window_pass.png")
win._matrix_view._pages.setCurrentIndex(1)
pump(0.4)
save(win._matrix_view, "view_sections_pass.png")
win.resize(1180, 880); pump(0.6)
save(win._matrix_view._container, "view_sections_full.png")
win.resize(1560, 880); pump(0.4)
win._matrix_view._pages.setCurrentIndex(0)
win._tabs.setCurrentIndex(1)
pump(0.4)
save(win._results_table, "results_pass.png")
win._tabs.setCurrentIndex(2)
pump(0.3)
save(win._log_panel, "log_pass.png")
win._tabs.setCurrentIndex(3)
pump(0.3)
save(win._info_panel, "info_connected.png")
win._tabs.setCurrentIndex(4)
pump(0.5)
save(win._config_panel, "config_tab.png")

# ── Run with two open wires ───────────────────────────────────────────────────────────
win._tabs.setCurrentIndex(0)
win._results_table.clear()
win._matrix_view.reset()
win._test_counter = win._pass_count = win._fail_count = 0
for i, (pa, pb) in enumerate(pairs):
    st = ResultStatus.OPEN if i in (2, 9) else ResultStatus.PASS
    win._on_cont_result(ContResult(pa, pb, 500000.0 if st != ResultStatus.PASS else 50.0, st))
win._on_verdict_ready(Verdict.FAIL)
win._test_bar.set_progress(len(pairs), len(pairs), 0.221)
pump(0.6)
save(win._results_table, "results_fail.png")
win._tabs.setCurrentIndex(0)
pump(0.4)
save(win._matrix_view, "view_single_fail.png")
win.resize(1180, 880); pump(0.6)
save(win._matrix_view._combined, "diagram_fail.png")
win.resize(1560, 880); pump(0.4)
save(win._test_bar, "toolbar_fail.png")
win._tabs.setCurrentIndex(2)
pump(0.3)
save(win._log_panel, "log_fail.png")

# ── Cross continuity: the firmware reports every one of the 37 x 37 pairs ──────────────────────
STRAIGHT = os.path.join(REPO, "netlists", "example_straight_only.xlsx")
win._on_netlist_browsed(STRAIGHT)
straight = load_netlist(STRAIGHT)
win._tabs.setCurrentIndex(1)
win._results_table.set_cross_continuity(True)
win._results_table.clear()
win._test_counter = win._pass_count = win._fail_count = 0
defined = set(straight.all_pairs())
for a in range(1, 38):
    for b in range(1, 38):
        if (a, b) in defined:
            st = ResultStatus.PASS
        elif (a, b) == (3, 8):
            st = ResultStatus.MISWIRE
        else:
            st = ResultStatus.NOT_CONNECTED
        win._on_cont_result(ContResult(a, b, 50.0 if st == ResultStatus.PASS else 500000.0, st))
win._on_verdict_ready(Verdict.FAIL)
pump(0.6)
win._tabs.setCurrentIndex(1)
win._results_table._table.scrollToBottom()
pump(0.5)
save(win._results_table, "results_cross.png")
win._results_table._table.scrollToTop()
pump(0.4)
save(win._results_table, "results_cross_top.png")
win._results_table.set_cross_continuity(False)
win._on_netlist_browsed(NL)
pump(0.4)

# ── Auto-Scan ───────────────────────────────────────────────────────────────────────────
win._left_panel._rb_auto_test.setChecked(True)
pump(0.3)
save(win._left_panel.findChildren(QGroupBox)[1], "grp_netlist_auto.png")
win._is_auto_test = True
win._results_table.clear()
win._matrix_view.reset()
found = [(1, 1), (2, 2), (3, 3), (4, 4), (5, 24), (6, 32), (7, 7), (8, 8),
         (16, 16), (17, 17), (31, 31), (33, 33)]
for pa, pb in found:
    win._on_cont_result(ContResult(pa, pb, 50.0, ResultStatus.PASS))
win._on_auto_test_complete()
pump(0.8)
save(win._left_panel, "panel_left_autoscan.png")
save(win._matrix_view, "view_autoscan.png")
win.resize(1180, 880); pump(0.6)
save(win._matrix_view._combined, "diagram_autoscan.png")
win.resize(1560, 880); pump(0.4)
win._tabs.setCurrentIndex(1)
pump(0.3)
save(win._results_table, "results_autoscan.png")
win._left_panel._rb_standard.setChecked(True)
pump(0.2)
win._tabs.setCurrentIndex(0)

# ── Dialogs ───────────────────────────────────────────────────────────────────────────────
def dialog(name, icon, title, text):
    box = QMessageBox(win)
    box.setIcon(icon)
    box.setWindowTitle(title)
    box.setText(text)
    box.show()
    pump(0.4)
    save(box, name)
    box.close()


dialog("dlg_netlist_error.png", QMessageBox.Icon.Critical, "Netlist Error",
       "Could not load netlist:\nNetlist must have a 'Src Pin #' column\n\n"
       "Please fix the file and try again.")
dialog("dlg_no_mode.png", QMessageBox.Icon.Warning, "No Test Mode Selected",
       "Please select Continuity or Cross Continuity before starting.")
dialog("dlg_no_results.png", QMessageBox.Icon.Information, "No Results",
       "No test results to export yet.")
dialog("dlg_cal.png", QMessageBox.Icon.Information, "Calibration Complete",
       "Calibration offset: 120 mΩ\nThe offset has been applied to resistance measurements.")

# About box
import PyQt6.QtCore as qtcore     # noqa: E402
from version import APP_VERSION   # noqa: E402
box = QMessageBox(win)
box.setWindowTitle("About Harness Tester")
box.setText(f"<b>Harness Tester</b><br>Version: {APP_VERSION}<br>Protocol: v1.0<br>"
            f"Qt: {qtcore.qVersion()}<br>Python: {sys.version.split()[0]}")
box.show(); pump(0.4); save(box, "dlg_about.png"); box.close()

# ── Menus ───────────────────────────────────────────────────────────────────────────────
mb = win.menuBar()
for act in mb.actions():
    menu = act.menu()
    if menu is None:
        continue
    name = act.text().replace("&", "").lower()
    menu.popup(win.mapToGlobal(QPoint(10, 30)))
    pump(0.4)
    save(menu, f"menu_{name}.png")
    menu.close()
    for sub in menu.actions():
        if sub.menu() is not None:
            sub.menu().popup(win.mapToGlobal(QPoint(200, 60)))
            pump(0.3)
            save(sub.menu(), f"menu_{name}_{sub.text().replace('&', '').lower()}.png")
            sub.menu().close()

# ── PDF report page 1 ───────────────────────────────────────────────────────────────────────
from datetime import datetime          # noqa: E402
from core.report import ReportMetadata, generate_pdf   # noqa: E402
win._tabs.setCurrentIndex(1)
win._results_table.clear()
win._results_table.set_cross_continuity(False)
win._test_counter = 0
for i, (pa, pb) in enumerate(pairs):
    st = ResultStatus.OPEN if i in (2, 9) else ResultStatus.PASS
    win._on_cont_result(ContResult(pa, pb, 500000.0 if st != ResultStatus.PASS else 50.0, st))
pdf = os.path.join(tmp, "report.pdf")
generate_pdf(pdf, win._results_table.display_ordered_results(),
             ReportMetadata(dut_id="HT-0001", operator="Operator 1", profile="Default",
                            netlist_name=os.path.basename(NL), fw_version="v2.2.0",
                            verdict="FAIL", timestamp=datetime(2026, 10, 28, 11, 30),
                            duration_s=0.221),
             os.path.join(GUI, "resources", "company_logo.jpeg"))
import fitz                             # noqa: E402
doc = fitz.open(pdf)
doc[0].get_pixmap(dpi=110).save(os.path.join(OUT, "report_pdf_page1.png"))
print("saved report_pdf_page1.png", len(doc), "pages")

# Crop the small controls to their content so they print large enough to read.
from PIL import Image                  # noqa: E402
CROPS = {"toolbar_idle": (0, 0, 745, None), "toolbar_ready": (0, 0, 745, None),
         "toolbar_running": (0, 0, 745, None), "toolbar_pass": (0, 0, 745, None),
         "toolbar_fail": (0, 0, 745, None), "info_connected": (0, 0, 520, 345),
         "log_pass": (0, 0, 1264, 345), "log_fail": (0, 0, 1264, 372)}
for name, (l, t, r, b) in CROPS.items():
    path = os.path.join(OUT, name + ".png")
    im = Image.open(path).convert("RGB")
    im.crop((l, t, min(r, im.width), b or im.height)).save(path)

shutil.copy(os.path.join(tmp, "profiles", "connector_config.xlsx"),
            os.path.join(OUT, "_config_used.xlsx"))
win.close()
os._exit(0)
