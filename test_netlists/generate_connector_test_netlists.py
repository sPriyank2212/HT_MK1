#!/usr/bin/env python3
"""Generate netlists that exercise connector-layout guessing.

Unlike `generate_test_netlists.py` (plain NET/HI/LO, no connector info), these
files use the full `required_format` column set (`Net`, `Source`, `Conn ID`,
`Part Number`, `Src Pin Label`, `Src Pin #`, `Dst Pin #`, `Dst Pin Label`,
`Conn ID B`, `Part Number B`, `Destination`, `Connector Detail`, `Harness ID`
— see `gui_flutter/required_format/example_netlist27072026.xlsx`), so
`netlist_file.dart`'s connector-layout guess (`_guessFixture`/`_guessShape`)
has real `Conn ID`/`Part Number` data to work from. Each file below is built
to land on a different code path in that guess.

Run from the repository root:
    python test_netlists/generate_connector_test_netlists.py
"""

import zipfile
from pathlib import Path
from openpyxl import Workbook

HEADER = [
    "Net", "Source", "Conn ID", "Part Number", "Src Pin Label", "Src Pin #",
    "Dst Pin #", "Dst Pin Label", "Conn ID B", "Part Number B", "Destination",
    "Connector Detail", "Harness ID",
]


def _fix_worksheet_rel_target(path: Path) -> None:
    """Same fix as generate_test_netlists.py — openpyxl writes the worksheet
    relationship Target as a package-absolute path, which the GUI's `excel`
    package (4.0.6) can't resolve. See that file's docstring for the full
    explanation; kept in sync here rather than imported, so this script has
    no dependency on the other one.
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


def write_xlsx(path: Path, rows: list[tuple]) -> None:
    wb = Workbook()
    ws = wb.active
    if ws is None:
        raise RuntimeError("openpyxl did not create a default sheet")
    ws.title = "NETLIST"
    ws.append(HEADER)
    for row in rows:
        ws.append(list(row))
    path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(path)
    _fix_worksheet_rel_target(path)
    print(f"wrote {path}  ({len(rows)} nets)")


def row(net, src_conn, src_part, src_label, src_pin, dst_pin, dst_label,
        dst_conn, dst_part, harness):
    return (
        net, "Side-A", src_conn, src_part, src_label, src_pin,
        dst_pin, dst_label, dst_conn, dst_part, "Side-B", "straight", harness,
    )


def gen_symmetric_dsub_pair() -> list[tuple]:
    """TN-01 — one mating connector pair per block, same Conn ID on both
    Source and Destination (a single in-line connector, not box-to-box) —
    the ordinary case `example_netlist27072026.xlsx` itself uses. Exercises
    the "side ambiguous" fallback in `_guessFixture`/`_fixtureFromGuess`
    (GuessedConnector.side ends up null, one shared base sequence).
    Two connectors: DB9 (9 pins) then DB37 (37 pins), straight-through.
    """
    rows = []
    pin = 0
    names = ["PWR_28V", "PWR_RTN", "CAN_H", "CAN_L", "WAKE", "IGN_SENSE",
              "FAULT_OUT", "SPARE_1", "SHIELD"]
    for n in names:  # pins 1..9 — globally flat, same convention every
        pin += 1      # required_format file uses (see the README note below)
        rows.append(row(f"W_{n}", "DB9-1", "DB9-M-9P", n, pin, pin, n,
                         "DB9-1", "DB9-F-9S", "TN01-SYM"))
    for i in range(37):  # pins 10..46 — continues the same flat sequence,
        pin += 1          # not a restart to 1..37
        n = f"SIG_{pin:02d}"
        rows.append(row(f"W_{n}", "DB37-1", "DB37-M-37P", n, pin, pin, n,
                         "DB37-1", "DB37-F-37S", "TN01-SYM"))
    return rows


def gen_distinct_src_dst() -> list[tuple]:
    """TN-02 — box-to-box harness: Source and Destination are genuinely
    different connectors, not a mating pair. Source: DB9 (dsub) + a 37-pin
    circular MIL connector (circ). Destination: one 46-pin rectangular
    connector (rect). Exercises `allSided=true` (GUI-23's separate baseL/
    baseR sequences) and all three shape guesses in one file.

    Part number note: `_guessShape` (netlist_file.dart) treats ANY part
    number containing "AMPHENOL" as circular, not rectangular — Amphenol
    also makes rectangular connectors in reality, so a real Amphenol
    rectangular part number would misguess here. Avoided deliberately below
    (TE Connectivity's CPC series instead) so this file's "rect" case
    actually lands on 'rect', not a false 'circ'.
    """
    rows = []
    pin = 0
    for i in range(9):
        pin += 1
        n = f"CTRL_{pin:02d}"
        rows.append(row(f"W_{n}", "J1-DB9", "DB9-M-9P", n, pin, pin, n,
                         "J3-RECT", "TE-CPC-46S", "TN02-DIST"))
    for i in range(37):
        pin += 1
        n = f"SENSE_{pin:02d}"
        rows.append(row(f"W_{n}", "J2-CIRC", "MS3116F14-19S", n, pin, pin, n,
                         "J3-RECT", "TE-CPC-46S", "TN02-DIST"))
    return rows


def gen_many_small_connectors() -> list[tuple]:
    """TN-03 — six small DB9 mating pairs (54 pins total), same Conn ID on
    both sides per block (ambiguous side, like TN-01) — stresses block-
    boundary inference across many consecutive small connectors instead of
    just one or two.
    """
    rows = []
    pin = 0
    for block in range(6):
        conn = f"DB9-{block + 1}"
        for i in range(9):
            pin += 1
            n = f"CH{block + 1}_{i + 1:02d}"
            rows.append(row(f"W_{n}", conn, "DB9-M-9P", n, pin, pin, n,
                             conn, "DB9-F-9S", "TN03-MANY"))
    return rows


def gen_single_large_connector() -> list[tuple]:
    """TN-04 — one 100-pin rectangular connector, same Conn ID both sides —
    the "everything is one block" edge, no boundary inference needed at all.
    """
    rows = []
    for i in range(100):
        pin = i + 1
        n = f"PIN_{pin:03d}"
        rows.append(row(f"W_{n}", "J1-BIG", "TE-CPC-100S", n, pin,
                         pin, n, "J1-BIG", "TE-CPC-100S", "TN04-BIG"))
    return rows


def gen_partial_unused_pins() -> list[tuple]:
    """TN-05 — a real DB9 (9 physical pins) with only 6 wired, followed by a
    DB37 (37 pins, only 20 wired) — exercises `_fixtureFromGuess`'s "extend
    the last connector to cover every pin actually referenced" handling and
    `_guessFixture`'s block-boundary inference when a connector's own
    max-observed pin undershoots its next-door neighbour's start.
    """
    rows = []
    names = ["PWR_28V", "PWR_RTN", "CAN_H", "CAN_L", "WAKE", "FAULT_OUT"]
    for i, n in enumerate(names):  # only 6 of DB9's 9 real pins wired
        pin = i + 1
        rows.append(row(f"W_{n}", "DB9-1", "DB9-M-9P", n, pin, pin, n,
                         "DB9-1", "DB9-F-9S", "TN05-PARTIAL"))
    for i in range(20):  # only 20 of DB37's 37 real pins wired
        pin = 10 + i
        n = f"SIG_{pin:02d}"
        rows.append(row(f"W_{n}", "DB37-1", "DB37-M-37P", n, pin, pin, n,
                         "DB37-1", "DB37-F-37S", "TN05-PARTIAL"))
    return rows


def gen_conflicting_connector_id() -> list[tuple]:
    """TN-06 — a real bug report, turned into a permanent regression case.
    `DB37-1` is used two different ways in the same file: as its own mated
    pair for pins 10..46 (native, straight-through, like TN-01), AND as the
    Destination for `DB9-1`'s pins 1..9 (a genuine box-to-box wire, like
    TN-02) - the same designator standing for two different physical roles.

    Before the fix (netlist_file.dart's `_ConnObs`/`_guessFixture`), the
    src/dst observations for `DB37-1` were merged into one min/max range,
    which corrupted its guessed pin count (46 instead of 37) and pushed its
    `base` offset up by 9 - so pins 1..9's Destination side could no longer
    resolve to `DB37-1` at all, and silently fell back to resolving to
    `DB9-1` instead. Both ends of that net then pointed at the same
    connector/pin, which drew as a zero-length "wire" - looking exactly
    like an open/not-connected net despite passing electrically.

    After the fix, `DB37-1`'s own native block (10..46, 37 pins) is
    unaffected by the foreign reference, and `GuessedConnector.conflicting`
    is true for `DB37-1` so the operator gets a clear warning instead of a
    silently wrong diagram.
    """
    rows = []
    names = ["PWR_28V", "PWR_RTN", "CAN_H", "CAN_L", "WAKE", "IGN_SENSE",
              "FAULT_OUT", "SPARE_1", "SHIELD"]
    for i, n in enumerate(names):  # pins 1..9, Destination points at the
        pin = i + 1                # OTHER connector's native id - the conflict
        rows.append(row(f"W_{n}", "DB9-1", "DB9-M-9P", n, pin, pin, n,
                         "DB37-1", "DB37-F-37S", "TN06-CONFLICT"))
    pin = 9
    for i in range(37):  # pins 10..46, DB37-1's own real mated pair
        pin += 1
        n = f"SIG_{pin:02d}"
        rows.append(row(f"W_{n}", "DB37-1", "DB37-M-37P", n, pin, pin, n,
                         "DB37-1", "DB37-F-37S", "TN06-CONFLICT"))
    return rows


def main() -> None:
    out_dir = Path(__file__).resolve().parent
    write_xlsx(out_dir / "TN-01_symmetric_dsub_pair.xlsx", gen_symmetric_dsub_pair())
    write_xlsx(out_dir / "TN-02_distinct_src_dst_connectors.xlsx", gen_distinct_src_dst())
    write_xlsx(out_dir / "TN-03_many_small_connectors.xlsx", gen_many_small_connectors())
    write_xlsx(out_dir / "TN-04_single_large_connector.xlsx", gen_single_large_connector())
    write_xlsx(out_dir / "TN-05_partial_unused_pins.xlsx", gen_partial_unused_pins())
    write_xlsx(out_dir / "TN-06_conflicting_connector_id.xlsx", gen_conflicting_connector_id())


if __name__ == "__main__":
    main()
