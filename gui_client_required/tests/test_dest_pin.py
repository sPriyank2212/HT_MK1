"""Dest Pin: Side B with connectors and pin numbers of its own.

One DB37 (J1) on Side A facing X1 / X2 (DB15) and X3 (DB9) on Side B.  A
netlist is written in connector pins and the config turns each end into a
tester channel.
"""

import openpyxl
import pytest

from core.netlist import (
    Net, NetPin, Netlist, PinRefError, apply_connector_config,
    connector_pin_mapping, connector_pin_mapping_b, dest_labels, load_netlist,
)
from core.pinmap import Channel, load_pinmap, write_pinmap_xlsx

# channel -> (Side-B connector, pin): X1 = 1-15, X2 = 16-30, X3 = 31-37
def _b_end(ch):
    if ch <= 15:
        return "X1", ch
    if ch <= 30:
        return "X2", ch - 15
    return "X3", ch - 30


def _channels():
    return [Channel(ch, "J1", "J1 (DB37)", ch, "", "", _b_end(ch)[0], _b_end(ch)[1])
            for ch in range(1, 38)]


@pytest.fixture
def config(tmp_path):
    path = str(tmp_path / "config.xlsx")
    write_pinmap_xlsx(path, _channels())
    return path


def _netlist(*wires):
    """wires: (conn, pin, conn_b, pin_b)"""
    return Netlist(nets=[
        Net(name=f"W{i}", pins=[NetPin(a, ""), NetPin(b, "")],
            connector_id=ca, connector_id_b=cb)
        for i, (ca, a, cb, b) in enumerate(wires, start=1)])


def test_config_round_trips_dest_pin(config):
    pm = load_pinmap(config)
    assert pm.has_dest_pins
    assert pm.by_channel()[33].end_b == ("X3", 3)
    assert "J1: 37 pins" in pm.summary() and "X3: 7 pins" in pm.summary()


def test_sheet_without_dest_pin_is_unchanged(tmp_path):
    path = str(tmp_path / "plain.xlsx")
    write_pinmap_xlsx(path, [Channel(1, "J1", "J1", 1, connector_id_b="X1"),
                             Channel(2, "J1", "J1", 2)])
    pm = load_pinmap(path)
    assert not pm.has_dest_pins
    assert dest_labels(path) == {"J1": "X1"}
    assert connector_pin_mapping_b(path) == {}


def test_connector_pins_become_channels(config):
    nl = _netlist(("J1", 1, "X3", 3), ("J1", 2, "X2", 12), ("J1", 3, "X1", 5))
    apply_connector_config(nl, config)
    assert [(n.pins[0].number, n.pins[1].number) for n in nl.nets] == [(1, 33), (2, 27), (3, 5)]
    assert [n.connector_id_b for n in nl.nets] == ["X3", "X2", "X1"]
    assert nl.nets[0].connector_id == "J1"
    assert nl.nets[0].connector_detail == "J1 (DB37) -> X3"


def test_connector_names_must_match_exactly(config):
    nl = _netlist(("j1", 1, "x2", 1))
    with pytest.raises(PinRefError) as err:
        apply_connector_config(nl, config)
    assert "'j1' is not a Side-A connector" in str(err.value)
    assert "'x2' is not a Side-B connector" in str(err.value)


def test_blank_conn_ids_are_refused(config):
    for wire in (("", 4, "X1", 4), ("J1", 4, "", 4)):
        with pytest.raises(PinRefError, match="is empty"):
            apply_connector_config(_netlist(wire), config)


def test_unknown_pin_is_refused_and_nothing_changes(config):
    nl = _netlist(("J1", 1, "X3", 3), ("J1", 2, "X3", 9), ("J1", 38, "X1", 1))
    with pytest.raises(PinRefError) as err:
        apply_connector_config(nl, config)
    assert "W2" in str(err.value) and "W3" in str(err.value) and "W1" not in str(err.value)
    assert nl.nets[0].pins[1].number == 3          # untouched


def test_side_b_maps(config):
    assert connector_pin_mapping(config)[33] == ("J1", 33)
    assert connector_pin_mapping_b(config)[33] == ("X3", 3)
    assert dest_labels(config) == {}


def test_duplicate_side_b_pin_is_an_error(tmp_path):
    channels = _channels()
    channels[1] = Channel(2, "J1", "J1 (DB37)", 2, "", "", "X1", 1)   # X1 pin 1 twice
    path = str(tmp_path / "dup.xlsx")
    write_pinmap_xlsx(path, channels)
    with pytest.raises(ValueError, match="Side-B X1 pin 1 already"):
        load_pinmap(path)


def test_bad_dest_pin_is_an_error(tmp_path):
    path = str(tmp_path / "bad.xlsx")
    write_pinmap_xlsx(path, _channels())
    wb = openpyxl.load_workbook(path)
    ws = wb.active
    ws["F2"] = "abc"
    wb.save(path)
    with pytest.raises(ValueError, match="Dest Pin must be a number"):
        load_pinmap(path)


def test_example_files_load_together():
    import os
    here = os.path.dirname(__file__)
    nets = os.path.join(here, "..", "..", "netlists")
    cfg = os.path.join(nets, "connector_config_db37_x1x2x3.xlsx")
    wl = os.path.join(nets, "example_db37_to_db15_db15_db9.xlsx")
    if not (os.path.exists(cfg) and os.path.exists(wl)):
        pytest.skip("example files not present")
    nl = load_netlist(wl)
    apply_connector_config(nl, cfg)
    sa = [n.pins[0].number for n in nl.nets]
    sb = [n.pins[1].number for n in nl.nets]
    assert len(set(sa)) == len(sa) == 30 and len(set(sb)) == len(sb) == 30


# --- Side A and Side B are independent: either end may have no pigtail ----------------

def _write(tmp_path, rows):
    path = str(tmp_path / "ends.xlsx")
    write_pinmap_xlsx(path, rows)
    return path


def test_side_a_37_pins_side_b_30_pins(tmp_path):
    rows = [Channel(i, "J1", "J1 (DB37)", i, connector_id_b="X1" if i <= 15 else "X2",
                    dest_pin=i if i <= 15 else i - 15) for i in range(1, 31)]
    rows += [Channel(i, "J1", "J1 (DB37)", i) for i in range(31, 38)]     # no Side-B pigtail
    path = _write(tmp_path, rows)
    pm = load_pinmap(path)
    assert "J1: 37 pins" in pm.summary() and "X2: 15 pins" in pm.summary()
    assert len(connector_pin_mapping(path)) == 37
    assert len(connector_pin_mapping_b(path)) == 30
    apply_connector_config(_netlist(("J1", 37, "X2", 15)), path)          # both ends exist
    with pytest.raises(PinRefError, match="'X3' is not a Side-B connector"):
        apply_connector_config(_netlist(("J1", 37, "X3", 1)), path)


def test_unwired_end_cannot_be_used_in_a_netlist(tmp_path):
    rows = [Channel(1, "J1", "J1", 1, connector_id_b="X1", dest_pin=1),
            Channel(2, "J1", "J1", 2),                                    # Side B not wired
            Channel(3, "", "", None, connector_id_b="X1", dest_pin=2)]    # Side A not wired
    path = _write(tmp_path, rows)
    assert connector_pin_mapping(path) == {1: ("J1", 1), 2: ("J1", 2)}
    assert connector_pin_mapping_b(path) == {1: ("X1", 1), 3: ("X1", 2)}
    nl = _netlist(("J1", 1, "X1", 2))
    apply_connector_config(nl, path)
    assert (nl.nets[0].pins[0].number, nl.nets[0].pins[1].number) == (1, 3)   # A ch 1 -> B ch 3
    with pytest.raises(PinRefError, match="X1 pin 3 has no pigtail on Side B"):
        apply_connector_config(_netlist(("J1", 1, "X1", 3)), path)
    with pytest.raises(PinRefError, match="J1 pin 3 has no pigtail on Side A"):
        apply_connector_config(_netlist(("J1", 3, "X1", 1)), path)


def test_y_joints_with_few_pins_in_use(tmp_path):
    path = _write(tmp_path, [Channel(i, "J1", "J1", i, connector_id_b="X1", dest_pin=i)
                             for i in range(1, 38)])
    nl = _netlist(("J1", 1, "X1", 1), ("J1", 2, "X1", 1), ("J1", 3, "X1", 1),   # 3 A pins -> 1 B pin
                  ("J1", 4, "X1", 2), ("J1", 4, "X1", 3))                        # 1 A pin -> 2 B pins
    apply_connector_config(nl, path)
    assert [(n.pins[0].number, n.pins[1].number) for n in nl.nets] ==         [(1, 1), (2, 1), (3, 1), (4, 2), (4, 3)]


@pytest.mark.parametrize("a, b, message", [
    (("J1", None), ("X1", 1), "Src Conn ID and Src Pin must both be filled"),
    (("", 1),      ("X1", 1), "Src Conn ID and Src Pin must both be filled"),
    (("J1", 1),    ("X1", None), "Dst Conn ID and Dest Pin must both be filled"),
    (("J1", 1),    ("", 1), "Dst Conn ID and Dest Pin must both be filled"),
    (("", None),   ("", None), "wired on neither side"),
])
def test_half_filled_ends_are_errors(tmp_path, a, b, message):
    good = Channel(1, "J1", "J1", 1, connector_id_b="X1", dest_pin=1)   # puts the sheet in Dest Pin mode
    bad = Channel(2, a[0], "", a[1], connector_id_b=b[0], dest_pin=b[1])
    with pytest.raises(ValueError, match=message):
        load_pinmap(_write(tmp_path, [good, bad]))
