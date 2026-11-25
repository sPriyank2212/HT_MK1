"""A report belongs to the test that was run: its DUT ID is the one used for that test,
not the one the field has moved on to (it counts up after every test)."""

import csv
import os
import time
from unittest.mock import MagicMock

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PyQt6.QtWidgets import QApplication, QFileDialog, QMessageBox

from core import paths, port_manager
from core.data_types import ResultStatus, TestResult, TestType
from core.report import ReportMetadata, generate_pdf


@pytest.fixture
def demo_window(tmp_path, monkeypatch):
    app = QApplication.instance() or QApplication([])
    monkeypatch.setattr(paths, "_data_dir", str(tmp_path))
    os.makedirs(tmp_path / "profiles", exist_ok=True)
    monkeypatch.setattr(port_manager, "_SERIAL_AVAILABLE", True)
    monkeypatch.setattr(port_manager, "enumerate_ports",
                        lambda: [port_manager.PortInfo("DEMO", "Virtual")])
    for n in ("information", "warning", "critical", "question"):
        monkeypatch.setattr(QMessageBox, n, staticmethod(lambda *a, **k: QMessageBox.StandardButton.Ok))
    from ui.demo_window import DemoMainWindow
    w = DemoMainWindow()

    def pump(cond, t=20):
        t0 = time.time()
        while not cond():
            app.processEvents()
            time.sleep(0.005)
            assert time.time() - t0 < t, "timed out"
        app.processEvents()

    w.pump = pump
    w._left_panel._scan_ports()
    pump(lambda: w._left_panel._cb_port.isEnabled())
    w._tester.step_s = 0.0
    w._left_panel._on_connect()
    pump(lambda: w._connected)
    yield w
    w.close()
    app.processEvents()


def test_reports_use_the_dut_id_of_the_test_not_the_next_one(demo_window, tmp_path, monkeypatch):
    w = demo_window
    w._left_panel._edit_dut_id.setText("HT-0001")
    w._last_verdict = ""
    w._test_bar.startRequested.emit()
    w.pump(lambda: w._last_verdict != "")
    assert w._last_verdict == "PASS"
    assert w._left_panel.get_dut_id() == "HT-0002"          # the field has moved on

    csv_path = str(tmp_path / "manual.csv")
    monkeypatch.setattr(QFileDialog, "getSaveFileName", staticmethod(lambda *a, **k: (csv_path, "")))
    w._on_save_results_csv()
    rows = list(csv.reader(open(csv_path, encoding="utf-8")))
    assert ["# DUT ID", "HT-0001"] in rows
    assert ["# Verdict", "PASS"] in rows

    seen = {}
    monkeypatch.setattr("ui.main_window.run_pdf_worker",
                        lambda path, results, meta, logo, parent=None: (seen.update(meta=meta), (MagicMock(), MagicMock()))[1])
    pdf_path = str(tmp_path / "r.pdf")
    monkeypatch.setattr(QFileDialog, "getSaveFileName", staticmethod(lambda *a, **k: (pdf_path, "")))
    w._on_export_pdf()
    assert seen["meta"].dut_id == "HT-0001" and seen["meta"].verdict == "PASS"


def test_pdf_pin_labels_and_part_numbers_are_kept_whole(tmp_path):
    from reportlab import rl_config
    rl_config.pageCompression = 0
    res = [TestResult(1, 1, 1, TestType.CONTINUITY, ResultStatus.PASS,
                      connector_part_number="172-E37-102R001", connector_part_number_b="164X11949X",
                      pin_a_name="PWM_SERVO7 LAUNCH & <Test>", pin_b_name="MPU_SERVICE_TX")]
    out = tmp_path / "r.pdf"
    generate_pdf(out, res, ReportMetadata(dut_id="D1", verdict="PASS"))
    raw = out.read_bytes().decode("latin-1")
    assert "(172-E37-102R001)" in raw and "(164X11949X)" in raw      # one cell, not split
    assert "(MPU_SERVICE_TX)" in raw                                  # fits its cell without splitting


def test_pdf_has_page_x_of_n_on_every_page_and_ends_with_end_of_report(tmp_path):
    import re
    from reportlab import rl_config
    rl_config.pageCompression = 0
    many = [TestResult(i, i % 37 + 1, i % 37 + 1, TestType.CONTINUITY, ResultStatus.PASS)
            for i in range(1, 151)]                                   # spills over several pages
    for name, res in (("many", many), ("none", [])):
        out = tmp_path / f"{name}.pdf"
        generate_pdf(out, res, ReportMetadata(dut_id="D1", verdict="PASS"))
        raw = out.read_bytes().decode("latin-1")
        pages = len(re.findall(r"/Type /Page\b", raw))
        labels = re.findall(r"\(Page (\d+) of (\d+)\)", raw)
        assert [int(a) for a, _ in labels] == list(range(1, pages + 1))
        assert {b for _, b in labels} == {str(pages)}
        assert raw.count("(End of the report)") == 1
        if name == "many":
            assert pages > 1
            assert raw.rfind("(End of the report)") > raw.rfind(f"(Page {pages - 1} of {pages})")
