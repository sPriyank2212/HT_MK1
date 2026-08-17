#!/usr/bin/env python3
"""Generate MTX test netlists for continuity / resistance testing.

The Flutter GUI parses netlists from .xlsx files with HI/LO pin columns.
These files are the MTX equivalent of the canned HV netlist entries in the
HV picker modal: sample harness definitions that can be browsed and loaded
for continuity and resistance runs.

Run this script from the repository root:
    python test_netlists/generate_test_netlists.py
"""

import zipfile
from pathlib import Path
from openpyxl import Workbook

# Names used by the demo harness in lib/design/model.dart.
# Extended with NET_023, NET_024, ... when needed.
DEMO_NAMES = [
    "PWR_28V_A", "PWR_28V_B", "GND_RET", "ARINC_A_HI", "ARINC_A_LO",
    "LAMP_CMD", "LAMP_RET", "SENSE_RTD_1", "SENSE_RTD_2", "FUEL_LVL",
    "OIL_PRESS", "FIRE_LOOP_A", "FIRE_LOOP_B", "STARTER_CMD", "GEN_FIELD",
    "BUS_TIE", "PITOT_HEAT", "NAV_LT", "BEACON", "STROBE",
    "INTERCOM_HI", "INTERCOM_LO",
]


def net_name(index: int) -> str:
    """Return the demo harness name for net index (0-based)."""
    if index < len(DEMO_NAMES):
        return DEMO_NAMES[index]
    return f"NET_{index + 1:03d}"


def make_netlist(nets: int) -> list[tuple[str, int, int]]:
    """Return (name, hi, lo) rows matching the simulator's _goodNets()."""
    rows = []
    for i in range(nets):
        hi = 2 * i + 1
        lo = 2 * i + 2
        rows.append((net_name(i), hi, lo))
    return rows


def _fix_worksheet_rel_target(path: Path) -> None:
    """openpyxl writes the worksheet relationship's Target as an absolute
    package path (`/xl/worksheets/sheet1.xml`), while styles.xml and
    theme1.xml in the same workbook.xml.rels use relative targets. Both
    forms are valid OPC, but the Flutter GUI's `excel` package (4.0.6)
    naively resolves every worksheet target as `xl/$target` and hits a null
    check when that lookup misses `xl//xl/worksheets/sheet1.xml` — which it
    always does for the absolute form. Rewriting it to the relative form
    (matching what openpyxl already does for the other two rels) keeps the
    file spec-valid and lets it parse in both Excel and the GUI.
    """
    rels_name = "xl/_rels/workbook.xml.rels"
    with zipfile.ZipFile(path, "r") as zin:
        entries = {name: zin.read(name) for name in zin.namelist()}
    rels = entries[rels_name].decode("utf-8")
    fixed = rels.replace('Target="/xl/worksheets/', 'Target="worksheets/')
    if fixed == rels:
        raise RuntimeError(f"{path}: expected an absolute worksheet Target to fix")
    entries[rels_name] = fixed.encode("utf-8")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zout:
        for name, data in entries.items():
            zout.writestr(name, data)


def write_xlsx(path: Path, rows: list[tuple[str, int, int]]) -> None:
    """Write a netlist .xlsx with NET, HI, LO columns."""
    wb = Workbook()
    ws = wb.active
    if ws is None:
        raise RuntimeError("openpyxl did not create a default sheet")
    ws.title = "NETLIST"
    ws.append(["NET", "HI", "LO"])
    for name, hi, lo in rows:
        ws.append([name, hi, lo])
    path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(path)
    _fix_worksheet_rel_target(path)
    print(f"wrote {path}  ({len(rows)} nets)")


def main() -> None:
    out_dir = Path(__file__).resolve().parent

    # 12 nets — matches the simulator default (--nets 12) and the small
    # scenarios (pass, opens_shorts, res_fail, insul_fail, disconnect).
    write_xlsx(out_dir / "AV-880_MTX_12net.xlsx", make_netlist(12))

    # 24 nets — a medium harness for layout/regression tests.
    write_xlsx(out_dir / "AV-880_MTX_24net.xlsx", make_netlist(24))

    # 118 nets — matches the full demo harness built by buildNets() in
    # lib/design/model.dart; the same count used by the HV netlist entries.
    write_xlsx(out_dir / "AV-880_MTX_118net.xlsx", make_netlist(118))


if __name__ == "__main__":
    main()
