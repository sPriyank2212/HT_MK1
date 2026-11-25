"""Colour, AWG, Length and Harness No: netlist -> results -> CSV / PDF, and the
Excel netlist that Use as Netlist writes."""

import openpyxl

from core.data_types import ResultStatus, TestResult, TestType
from core.netlist import (
    Net, NetPin, Netlist, load_netlist, save_netlist, save_netlist_xlsx,
)
from core.pinmap import Channel, load_pinmap, write_pinmap_xlsx
from core.report import ReportMetadata, generate_pdf
from core.result_model import (
    COL_AWG, COL_COLOUR, COL_HARNESS_NO, COL_LENGTH, HEADERS, ResultModel,
)


def _sheet(tmp_path, headers, rows):
    path = str(tmp_path / "nl.xlsx")
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.append(headers)
    for r in rows:
        ws.append(r)
    wb.save(path)
    return path


def test_wire_columns_are_read_from_excel(tmp_path):
    path = _sheet(tmp_path,
                  ["Net", "Src Pin #", "Dst Pin #", "Colour", "AWG", "Length", "Harness No"],
                  [["W1", 1, 2, "Red", 22, 150.0, "H-01"],
                   ["W2", 3, 4, "Blue/White", 20.5, "2 m", "H-02"],
                   ["W3", 5, 6, None, None, None, None]])
    nets = load_netlist(path).nets
    assert (nets[0].wire_colour, nets[0].awg, nets[0].length, nets[0].harness_no) == \
        ("Red", "22", "150", "H-01")           # 22.0 / 150.0 read as typed
    assert (nets[1].wire_colour, nets[1].awg, nets[1].length) == ("Blue/White", "20.5", "2 m")
    assert (nets[2].wire_colour, nets[2].awg, nets[2].length, nets[2].harness_no) == ("",) * 4


def test_alternative_header_names(tmp_path):
    path = _sheet(tmp_path,
                  ["Net", "Src Pin #", "Dst Pin #", "Color", "Wire Gauge", "Wire Length", "Harness #"],
                  [["W1", 1, 2, "Green", 18, 90, "H-7"]])
    n = load_netlist(path).nets[0]
    assert (n.wire_colour, n.awg, n.length, n.harness_no) == ("Green", "18", "90", "H-7")


def test_netlist_without_the_columns_still_loads(tmp_path):
    path = _sheet(tmp_path, ["Net", "Src Pin #", "Dst Pin #"], [["W1", 1, 2]])
    n = load_netlist(path).nets[0]
    assert (n.wire_colour, n.awg, n.length, n.harness_no) == ("",) * 4


def test_json_round_trip(tmp_path):
    nl = Netlist(nets=[Net("W1", [NetPin(1), NetPin(2)], wire_colour="Red", awg="22",
                           length="150", harness_no="H-01")])
    path = str(tmp_path / "nl.json")
    save_netlist(nl, path)
    n = load_netlist(path).nets[0]
    assert (n.wire_colour, n.awg, n.length, n.harness_no) == ("Red", "22", "150", "H-01")


def test_xlsx_round_trip(tmp_path):
    nl = Netlist(nets=[
        Net("WIRE_01", [NetPin(3, "A03"), NetPin(7, "B07")], connector_id="J1",
            connector_id_b="J1", source="Side-A", destination="Side-B"),
        Net("W2", [NetPin(1), NetPin(2), NetPin(3)], wire_colour="Red", awg="22",
            length="150", harness_no="H-01"),
    ], harness_id="HRN-1")
    path = str(tmp_path / "out.xlsx")
    save_netlist_xlsx(nl, path)
    ws = openpyxl.load_workbook(path).active
    assert [c.value for c in ws[1]][-5:] == ["Colour", "AWG", "Length", "Harness No", "Harness ID"]
    back = load_netlist(path)
    assert back.harness_id == "HRN-1"
    assert [(n.name, n.pins[0].number, n.pins[1].number) for n in back.nets] == \
        [("WIRE_01", 3, 7), ("W2", 1, 2), ("W2", 1, 3)]       # a 3-pin net: one row per destination
    assert back.nets[0].connector_id == "J1" and back.nets[0].pins[0].name == "A03"
    assert back.nets[1].wire_colour == "Red" and back.nets[2].harness_no == "H-01"


def test_results_model_columns():
    assert HEADERS[COL_COLOUR:] == ["Colour", "AWG", "Length", "Harness No"]
    model = ResultModel()
    model.append_result(TestResult(1, 1, 2, TestType.CONTINUITY, ResultStatus.PASS,
                                   wire_colour="Red", awg="22", length="150", harness_no="H-01"))
    shown = [model.data(model.index(0, c)) for c in (COL_COLOUR, COL_AWG, COL_LENGTH, COL_HARNESS_NO)]
    assert shown == ["Red", "22", "150", "H-01"]


def test_pdf_has_the_columns(tmp_path):
    from reportlab import rl_config
    rl_config.pageCompression = 0          # keep the page text readable in the file
    res = [TestResult(1, 1, 2, TestType.CONTINUITY, ResultStatus.PASS,
                      wire_colour="Crimson", awg="22", length="150", harness_no="H-01")]
    out = tmp_path / "r.pdf"
    generate_pdf(out, res, ReportMetadata(dut_id="D1", verdict="PASS"))
    raw = out.read_bytes().decode("latin-1")
    for word in ("Colour", "AWG", "Length", "Harness No", "Crimson", "H-01"):
        assert f"({word})" in raw


def test_config_headers_old_and_new_names(tmp_path):
    new = str(tmp_path / "new.xlsx")
    write_pinmap_xlsx(new, [Channel(1, "J1", "J1", 1, connector_id_b="X1", dest_pin=1)])
    ws = openpyxl.load_workbook(new).active
    assert [c.value for c in ws[1]][:3] == ["Channel", "Src Conn ID", "Dst Conn ID"]

    old = str(tmp_path / "old.xlsx")        # a sheet written by an earlier build
    wb = openpyxl.Workbook()
    wb.active.append(["Channel", "Connector ID", "Dest Connector ID", "Connector Name",
                      "Conn Pin", "Dest Pin"])
    wb.active.append([1, "J1", "X1", "J1", 1, 1])
    wb.save(old)
    assert load_pinmap(old).by_channel()[1].end_b == ("X1", 1)
    assert load_pinmap(new).by_channel()[1].end_a == ("J1", 1)


def test_config_has_src_pin_and_no_mcu_columns(tmp_path):
    """The sheet the GUI writes heads the pin column Src Pin and carries no MCU pins,
    even when the channels do; an older sheet's Conn Pin and MCU columns are still read."""
    from core.pinmap import read_rows, strip_mcu_columns
    new = str(tmp_path / "new.xlsx")
    write_pinmap_xlsx(new, [Channel(1, "J1", "J1", 1, side_a="PC9", side_b="PC10")])
    ws = openpyxl.load_workbook(new).worksheets[0]
    assert [c.value for c in ws[1]] == ["Channel", "Src Conn ID", "Dst Conn ID",
                                        "Connector Name", "Src Pin", "Dest Pin"]
    assert "MCU" not in " ".join(str(c.value) for row in openpyxl.load_workbook(new)["Notes"].iter_rows()
                                 for c in row if c.value)

    old = str(tmp_path / "old.xlsx")
    wb = openpyxl.Workbook()
    wb.active.append(["Channel", "Connector ID", "Connector Name", "Conn Pin", "Side A MCU", "Side B MCU"])
    wb.active.append([1, "J1", "J1", 3, "PC9", "PC10"])
    wb.save(old)
    assert load_pinmap(old).by_channel()[1].conn_pin == 3
    assert read_rows(old) == [["1", "J1", "", "J1", "3", ""]]          # import drops the MCU pins

    assert strip_mcu_columns(old) is True
    ws = openpyxl.load_workbook(old).worksheets[0]
    assert [c.value for c in ws[1]] == ["Channel", "Src Conn ID", "Connector Name", "Src Pin"]
    assert [c.value for c in ws[2]] == [1, "J1", "J1", 3]
    assert strip_mcu_columns(old) is False                              # nothing left to strip


def test_configuration_tab_shows_six_columns(tmp_path, monkeypatch):
    import os
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PyQt6.QtWidgets import QApplication
    from core import paths
    from ui.config_panel import ConfigPanel
    app = QApplication.instance() or QApplication([])
    cfg = str(tmp_path / "c.xlsx")
    wb = openpyxl.Workbook()
    wb.active.append(["Channel", "Connector ID", "Connector Name", "Conn Pin", "Side A MCU", "Side B MCU"])
    wb.active.append([1, "J1", "J1", 1, "PC9", "PC10"])
    wb.save(cfg)
    monkeypatch.setattr(paths, "active_connector_config", lambda: cfg)
    panel = ConfigPanel()
    t = panel._table
    assert [t.horizontalHeaderItem(i).text() for i in range(t.columnCount())] == \
        ["Channel", "Src Conn ID", "Dst Conn ID", "Connector Name", "Src Pin", "Dest Pin"]
    out = str(tmp_path / "out.xlsx")
    write_pinmap_xlsx(out, panel._channels())
    ws = openpyxl.load_workbook(out).worksheets[0]
    assert ws.max_column == 6 and [c.value for c in ws[2]] == [1, "J1", None, "J1", 1, None]
