#!/usr/bin/env python3
"""Generate harness-scenario netlists: every connector type, every joint.

Where `generate_connector_test_netlists.py` pins the connector-layout *guess*
(TN-01..06), these files exercise the whole wiring-diagram pipeline end to end
— connector shapes, the two harness ends, and every way wires can meet:

    plain point-to-point     one row
    crossed pins             Connector Detail "crossed pin 5 -> 8"
    Y branch (1 -> N)        N rows with the SAME Net name and source pin
    merge (N -> 1)           N rows with the SAME Net name and destination pin
    multi-drop (N -> M)      rows sharing a Net name on both ends (a bus)
    inline splice            Connector Detail "inline butt splice"
    twisted pair / shield    labels + Connector Detail, display only
    spare pins               connector pins that nothing is wired to

All use the full `required_format` column set (`Net`, `Source`, `Conn ID`,
`Part Number`, `Src Pin Label`, `Src Pin #`, `Dst Pin #`, `Dst Pin Label`,
`Conn ID B`, `Part Number B`, `Destination`, `Connector Detail`, `Harness ID`),
so `netlist_file.dart` has real `Conn ID` / `Part Number` / label / detail data.

Pin numbers are FLAT within each end — the connectors of one end are numbered
one after another (`DB9` 1..9, `DB15` 10..24, ...), exactly like the real
`example_netlist27072026.xlsx`. Side A is the HI space, Side B the LO space;
they are numbered independently.

Run from the repository root:
    python test_netlists/generate_harness_scenarios.py
"""

import zipfile
from pathlib import Path

from openpyxl import Workbook

HEADER = [
    "Net", "Source", "Conn ID", "Part Number", "Src Pin Label", "Src Pin #",
    "Dst Pin #", "Dst Pin Label", "Conn ID B", "Part Number B", "Destination",
    "Connector Detail", "Harness ID",
]

OUT = Path(__file__).parent


def _fix_worksheet_rel_target(path: Path) -> None:
    """openpyxl writes the worksheet relationship Target as a package-absolute
    path, which the GUI's `excel` package (4.0.6) cannot resolve — same fix as
    the other generators in this folder (kept inline so this script has no
    dependency on them)."""
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


class End:
    """One end of the harness: an ordered list of connectors, flat-numbered."""

    def __init__(self, conns):
        # conns: list of (conn_id, part_number, pin_count)
        self.conns = {}
        self.order = []
        base = 0
        for cid, part, pins in conns:
            if cid in self.conns:
                raise ValueError(f"duplicate connector id {cid} on one end")
            self.conns[cid] = (part, pins, base)
            self.order.append(cid)
            base += pins
        self.total = base

    def pin(self, cid, n):
        part, pins, base = self.conns[cid]
        if not 1 <= n <= pins:
            raise ValueError(f"{cid} has {pins} pins, asked for {n}")
        return base + n

    def part(self, cid):
        return self.conns[cid][0]


class Harness:
    def __init__(self, name, a: End, b: End):
        self.name = name
        self.a = a
        self.b = b
        self.rows = []
        self._used_pairs = set()

    # a / b are (conn_id, local_pin)
    def _row(self, net, a, b, la, lb, detail):
        ha, hb = self.a.pin(*a), self.b.pin(*b)
        if (ha, hb) in self._used_pairs:
            raise ValueError(f"{self.name}: duplicate pair {a} -> {b}")
        self._used_pairs.add((ha, hb))
        self.rows.append((
            net, "Side-A", a[0], self.a.part(a[0]), la, ha,
            hb, lb, b[0], self.b.part(b[0]), "Side-B", detail, self.name,
        ))

    def wire(self, net, a, b, label=None, label_b=None, detail="straight"):
        """A plain wire."""
        self._row(net, a, b, label or net, label_b or label or net, detail)

    def crossed(self, net, a, b, label=None):
        self._row(net, a, b, label or net, label or net,
                  f"crossed pin {self.a.pin(*a)} -> {self.b.pin(*b)}")

    def splice(self, net, a, b, label=None):
        """An inline butt splice somewhere along a point-to-point run."""
        self._row(net, a, b, label or net, label or net, "inline butt splice")

    def y(self, net, a, dsts, label=None, labels=None):
        """One source pin branching to several destinations (1 -> N)."""
        for i, b in enumerate(dsts, 1):
            lb = labels[i - 1] if labels else f"{label or net}_{i}"
            self._row(net, a, b, label or net, lb, f"Y branch {i} of {len(dsts)}")

    def merge(self, net, srcs, b, label=None, labels=None):
        """Several source pins converging on one destination (N -> 1)."""
        for i, a in enumerate(srcs, 1):
            la = labels[i - 1] if labels else f"{label or net}_{i}"
            self._row(net, a, b, la, label or net, f"Y merge {i} of {len(srcs)}")

    def bus(self, net, srcs, dsts, label=None):
        """A multi-drop bus: every source and every destination on one node.
        Written as a spanning star (each source to the first destination, the
        first source to every other destination), which is enough to prove the
        whole node is continuous."""
        detail = f"multi-drop bus {len(srcs)}x{len(dsts)}"
        for a in srcs:
            self._row(net, a, dsts[0], label or net, label or net, detail)
        for b in dsts[1:]:
            self._row(net, srcs[0], b, label or net, label or net, detail)

    def write(self, filename):
        wb = Workbook()
        ws = wb.active
        ws.title = "NETLIST"
        ws.append(HEADER)
        for r in self.rows:
            ws.append(list(r))
        path = OUT / filename
        wb.save(path)
        _fix_worksheet_rel_target(path)
        nets = len({r[0] for r in self.rows})
        print(f"wrote {path.name:48s} {len(self.rows):4d} rows  {nets:4d} nets  "
              f"A:{self.a.total:3d} pins  B:{self.b.total:3d} pins")


# ---------------------------------------------------------------------------
# HW-01  the D-sub family, mated pairs (the same designator at both ends)
# ---------------------------------------------------------------------------
def hw01():
    sizes = [("DB9", 9), ("DB15", 15), ("DB25", 25), ("DB37", 37), ("DB50", 50)]
    a = End([(f"{n}-1", f"{n}-M-{p}P", p) for n, p in sizes])
    b = End([(f"{n}-1", f"{n}-F-{p}S", p) for n, p in sizes])
    h = Harness("HW-01", a, b)
    for n, p in sizes:
        cid = f"{n}-1"
        for pin in range(1, p + 1):
            if n == "DB9" and pin in (2, 3):          # null-modem: TX/RX crossed
                other = 5 - pin
                h.crossed(f"{n}_P{pin}", (cid, pin), (cid, other),
                          "RXD" if pin == 2 else "TXD")
            elif n == "DB9" and pin in (7, 8):         # RTS/CTS crossed
                other = 15 - pin
                h.crossed(f"{n}_P{pin}", (cid, pin), (cid, other),
                          "RTS" if pin == 7 else "CTS")
            else:
                h.wire(f"{n}_P{pin}", (cid, pin), (cid, pin))
    return h, "HW-01_dsub_family_mated_pairs.xlsx"


# ---------------------------------------------------------------------------
# HW-02  circular connectors: MIL-DTL-38999, MS3116, M12, M8
# ---------------------------------------------------------------------------
def hw02():
    a = End([
        ("J1", "MS3116F14-19S", 19),
        ("J2", "D38999/26WB35SN", 22),
        ("J3", "M12-A-8P-FEMALE", 8),
        ("J4", "M8-3P-FEMALE", 3),
    ])
    b = End([
        ("P1", "MS3126F14-19P", 19),
        ("P2", "D38999/26WB35PN", 22),
        ("P3", "M12-A-8P-MALE", 8),
        ("P4", "M8-3P-MALE", 3),
    ])
    h = Harness("HW-02", a, b)
    # MS3116 power + signal
    h.y("PWR_28V", ("J1", 1), [("P1", 1), ("P2", 20)], "PWR_28V",
        ["PWR_28V_A", "PWR_28V_B"])
    h.y("GND_RET", ("J1", 2), [("P1", 2), ("P2", 21), ("P3", 8)], "GND_RET",
        ["GND_A", "GND_B", "GND_SENSOR"])
    for pin, sig in zip(range(3, 11), ["ARINC_A_HI", "ARINC_A_LO", "ARINC_B_HI",
                                       "ARINC_B_LO", "DISC_1", "DISC_2",
                                       "DISC_3", "DISC_4"]):
        h.wire(sig, ("J1", pin), ("P1", pin))
    for pin in range(11, 20):
        h.wire(f"SPARE_J1_{pin}", ("J1", pin), ("P1", pin), f"SPARE_{pin}")
    # MIL-38999: two plain signals first, then twisted pairs and a shield
    h.wire("ENG_A", ("J2", 1), ("P2", 1))
    h.wire("ENG_B", ("J2", 2), ("P2", 2))
    for i, (hi, lo) in enumerate([(3, 4), (5, 6), (7, 8), (9, 10)], 1):
        h.wire(f"TP{i}_HI", ("J2", hi), ("P2", hi), f"TP{i}_HI",
               detail=f"twisted pair {i}")
        h.wire(f"TP{i}_LO", ("J2", lo), ("P2", lo), f"TP{i}_LO",
               detail=f"twisted pair {i}")
    h.wire("SHIELD_DRAIN", ("J2", 11), ("P2", 11), "SHIELD",
           detail="shield drain wire")
    for pin in range(12, 20):
        h.wire(f"SIG_{pin}", ("J2", pin), ("P2", pin))
    # M12 sensor
    for pin, sig in zip(range(1, 8), ["+24V", "SIG_A", "GND", "SIG_B", "SHLD",
                                       "SIG_C", "SIG_D"]):
        h.wire(f"M12_{sig}", ("J3", pin), ("P3", pin), sig)
    # M8 proximity: crossed 2<->3
    h.wire("M8_BROWN", ("J4", 1), ("P4", 1), "BROWN_+V")
    h.crossed("M8_BLACK", ("J4", 2), ("P4", 3), "BLACK_OUT")
    h.crossed("M8_BLUE", ("J4", 3), ("P4", 2), "BLUE_0V")
    return h, "HW-02_circular_connectors.xlsx"


# ---------------------------------------------------------------------------
# HW-03  rectangular connectors, box-to-box (different connectors each end)
# ---------------------------------------------------------------------------
def hw03():
    a = End([
        ("J1", "TE-CPC-16", 16),
        ("J2", "MOLEX-MINIFIT-12", 12),
        ("J3", "DEUTSCH-DT06-12S", 12),
        ("J4", "JST-XH-8", 8),
        ("J5", "AMPHENOL-RECT-24", 24),
    ])
    b = End([
        ("P1", "TE-CPC-24", 24),
        ("P2", "DEUTSCH-DT04-24P", 24),
        ("P3", "AMPHENOL-RECT-24B", 24),
    ])
    h = Harness("HW-03", a, b)
    # five connectors gather into three: TE-CPC-16 + JST-XH-8 -> P1
    for pin in range(1, 17):
        h.wire(f"CPC_{pin}", ("J1", pin), ("P1", pin))
    for pin in range(1, 9):
        h.wire(f"JST_{pin}", ("J4", pin), ("P1", 16 + pin))
    # Mini-Fit + Deutsch DT -> P2
    for pin in range(1, 13):
        h.wire(f"MINIFIT_{pin}", ("J2", pin), ("P2", pin))
    for pin in range(1, 13):
        h.wire(f"DT_{pin}", ("J3", pin), ("P2", 12 + pin))
    # the big Amphenol -> P3, with three Y splices on the supply pins
    h.y("RECT_28V", ("J5", 1), [("P3", 1), ("P3", 2), ("P3", 3)], "28V",
        ["28V_A", "28V_B", "28V_C"])
    h.y("RECT_GND", ("J5", 2), [("P3", 4), ("P3", 5)], "GND", ["GND_A", "GND_B"])
    for pin in range(3, 22):
        h.wire(f"RECT_{pin}", ("J5", pin), ("P3", pin + 3))
    return h, "HW-03_rectangular_connectors.xlsx"


# ---------------------------------------------------------------------------
# HW-04  terminal blocks and modular jacks (RJ45, RJ11, USB)
# ---------------------------------------------------------------------------
def hw04():
    a = End([
        ("TB1", "PHOENIX-MSTB-2.5/12-TERMINAL", 12),
        ("TB2", "WAGO-TERMINAL-8", 8),
        ("ETH1", "RJ45-8P8C-JACK", 8),
        ("ETH2", "RJ45-8P8C-JACK", 8),
        ("TEL1", "RJ11-6P4C-JACK", 6),
        ("USB1", "USB-A-4P", 4),
    ])
    b = End([
        ("TB3", "PHOENIX-MSTB-2.5/16-TERMINAL", 16),
        ("TB4", "WAGO-TERMINAL-12", 12),
        ("ETH3", "RJ45-8P8C-PLUG", 8),
        ("ETH4", "RJ45-8P8C-PLUG", 8),
        ("TEL2", "RJ11-6P4C-PLUG", 6),
        ("USB2", "USB-B-4P", 4),
    ])
    h = Harness("HW-04", a, b)
    for pin in range(1, 13):
        h.wire(f"TB_{pin}", ("TB1", pin), ("TB3", pin), f"CH{pin}")
    for pin in range(1, 9):
        h.wire(f"WAGO_{pin}", ("TB2", pin), ("TB4", pin), f"IO{pin}")
    # Ethernet T568B: pairs 1-2, 3-6, 4-5, 7-8 — straight, and a crossover
    pairs = [(1, 2, "TX"), (3, 6, "RX"), (4, 5, "P3"), (7, 8, "P4")]
    for tag, (p, q, nm) in enumerate(pairs, 1):
        h.wire(f"ETH1_{nm}_P", ("ETH1", p), ("ETH3", p), f"{nm}+",
               detail=f"twisted pair {tag} (T568B straight)")
        h.wire(f"ETH1_{nm}_N", ("ETH1", q), ("ETH3", q), f"{nm}-",
               detail=f"twisted pair {tag} (T568B straight)")
    # crossover cable: TX pair <-> RX pair
    h.crossed("ETH2_TXP", ("ETH2", 1), ("ETH4", 3), "TX+")
    h.crossed("ETH2_TXN", ("ETH2", 2), ("ETH4", 6), "TX-")
    h.crossed("ETH2_RXP", ("ETH2", 3), ("ETH4", 1), "RX+")
    h.crossed("ETH2_RXN", ("ETH2", 6), ("ETH4", 2), "RX-")
    h.wire("ETH2_P3P", ("ETH2", 4), ("ETH4", 4), "P3+")
    h.wire("ETH2_P3N", ("ETH2", 5), ("ETH4", 5), "P3-")
    h.wire("ETH2_P4P", ("ETH2", 7), ("ETH4", 7), "P4+")
    h.wire("ETH2_P4N", ("ETH2", 8), ("ETH4", 8), "P4-")
    for pin in range(1, 7):
        h.wire(f"TEL_{pin}", ("TEL1", pin), ("TEL2", pin))
    for pin, nm in zip(range(1, 5), ["VBUS", "D-", "D+", "GND"]):
        h.wire(f"USB_{nm}", ("USB1", pin), ("USB2", pin), nm)
    return h, "HW-04_terminal_blocks_and_modular_jacks.xlsx"


# ---------------------------------------------------------------------------
# HW-05  Y joints: 1 -> N branches, N -> 1 merges, at several fan-outs
# ---------------------------------------------------------------------------
def hw05():
    a = End([
        ("TB-IN", "PHOENIX-MSTB-2.5/16-TERMINAL", 16),
        ("DB25-A", "DB25-M-25P", 25),
    ])
    b = End([
        ("DB37-B", "DB37-F-37S", 37),
        ("CIRC-B", "MS3116F18-32S", 32),
        ("TB-OUT", "WAGO-TERMINAL-16", 16),
    ])
    h = Harness("HW-05", a, b)
    # supply fans out to loads on every output connector: 1 -> 4
    h.y("PWR_28V", ("TB-IN", 1),
        [("DB37-B", 1), ("DB37-B", 2), ("CIRC-B", 1), ("TB-OUT", 1)],
        "28V_IN", ["28V_DB37_1", "28V_DB37_2", "28V_CIRC", "28V_TB"])
    # ground bus: 1 -> 6
    h.y("GND_BUS", ("TB-IN", 2),
        [("DB37-B", 3), ("DB37-B", 4), ("DB37-B", 5), ("CIRC-B", 2),
         ("CIRC-B", 3), ("TB-OUT", 2)],
        "GND_IN", [f"GND_{i}" for i in range(1, 7)])
    # 5 V sense: 1 -> 3
    h.y("SENSE_5V", ("TB-IN", 3),
        [("DB37-B", 6), ("CIRC-B", 4), ("TB-OUT", 3)],
        "5V_IN", ["5V_A", "5V_B", "5V_C"])
    # a 1 -> 2 shield drain
    h.y("SHIELD", ("TB-IN", 4), [("CIRC-B", 5), ("TB-OUT", 4)],
        "SHLD_IN", ["SHLD_A", "SHLD_B"])
    # merges: several sensor returns into one common (N -> 1)
    h.merge("RTN_SENSORS", [("DB25-A", 1), ("DB25-A", 2), ("DB25-A", 3)],
            ("DB37-B", 7), "RTN_COMMON", ["RTN_S1", "RTN_S2", "RTN_S3"])
    h.merge("RTN_VALVES", [("DB25-A", 4), ("DB25-A", 5), ("DB25-A", 6),
                           ("DB25-A", 7), ("DB25-A", 8)],
            ("CIRC-B", 6), "RTN_VALVE_COMMON",
            [f"RTN_V{i}" for i in range(1, 6)])
    # plain signals around them
    for i, pin in enumerate(range(9, 26)):
        h.wire(f"SIG_{i + 1:02d}", ("DB25-A", pin), ("DB37-B", 8 + i), f"SIG{i + 1}")
    for i, pin in enumerate(range(5, 17)):
        h.wire(f"IO_{i + 1:02d}", ("TB-IN", pin), ("TB-OUT", 5 + i), f"IO{i + 1}")
    return h, "HW-05_y_joints_branch_and_merge.xlsx"


# ---------------------------------------------------------------------------
# HW-06  inline splices, crossed wires, spare pins
# ---------------------------------------------------------------------------
def hw06():
    a = End([("DB15-A", "DB15-M-15P", 15), ("DB9-A", "DB9-M-9P", 9)])
    b = End([("DB15-B", "DB15-F-15S", 15), ("DB9-B", "DB9-F-9S", 9)])
    h = Harness("HW-06", a, b)
    for pin in (1, 2, 3, 4):
        h.splice(f"SPLICE_P{pin}", ("DB15-A", pin), ("DB15-B", pin),
                 f"SIG{pin}")
    h.crossed("SWAP_5_6", ("DB15-A", 5), ("DB15-B", 6), "SWAP_A")
    h.crossed("SWAP_6_5", ("DB15-A", 6), ("DB15-B", 5), "SWAP_B")
    h.crossed("SWAP_7_9", ("DB15-A", 7), ("DB15-B", 9), "SWAP_C")
    h.crossed("SWAP_9_7", ("DB15-A", 9), ("DB15-B", 7), "SWAP_D")
    h.wire("PLAIN_8", ("DB15-A", 8), ("DB15-B", 8))
    # pins 10-15 deliberately left unwired (spares)
    for pin in range(1, 6):
        h.splice(f"SPLICE_9_{pin}", ("DB9-A", pin), ("DB9-B", pin), f"S{pin}")
    for pin in (6, 7):
        h.wire(f"DB9_{pin}", ("DB9-A", pin), ("DB9-B", pin))
    # pins 8-9 spare
    return h, "HW-06_inline_splices_crossed_and_spares.xlsx"


# ---------------------------------------------------------------------------
# HW-07  multi-drop buses
# ---------------------------------------------------------------------------
def hw07():
    a = End([("NODE1", "DB9-M-9P", 9), ("NODE2", "DB9-M-9P", 9)])
    b = End([("NODE3", "DB9-F-9S", 9), ("NODE4", "DB9-F-9S", 9),
             ("NODE5", "DB9-F-9S", 9)])
    h = Harness("HW-07", a, b)
    # CAN: 2 nodes on one side, 3 on the other, all on one node (2 x 3)
    h.bus("CAN_H", [("NODE1", 7), ("NODE2", 7)],
          [("NODE3", 7), ("NODE4", 7), ("NODE5", 7)], "CAN_H")
    h.bus("CAN_L", [("NODE1", 2), ("NODE2", 2)],
          [("NODE3", 2), ("NODE4", 2), ("NODE5", 2)], "CAN_L")
    # RS-485 A/B: 1 master, 3 slaves (1 x 3 = a Y)
    h.bus("RS485_A", [("NODE1", 3)],
          [("NODE3", 3), ("NODE4", 3), ("NODE5", 3)], "RS485_A")
    h.bus("RS485_B", [("NODE1", 8)],
          [("NODE3", 8), ("NODE4", 8), ("NODE5", 8)], "RS485_B")
    # CAN shield, and ground: everyone to everyone
    h.bus("GND_BUS", [("NODE1", 5), ("NODE2", 5)],
          [("NODE3", 5), ("NODE4", 5), ("NODE5", 5)], "GND")
    # +24 V distribution, 2 x 2
    h.bus("PWR_24V", [("NODE1", 9), ("NODE2", 9)],
          [("NODE3", 9), ("NODE4", 9)], "24V")
    # one spare link so NODE5's pin 1 is wired too
    h.wire("SPARE_LINK", ("NODE2", 3), ("NODE5", 1), "SPARE")
    # the unshared pins stay plain
    for node_a, node_b in (("NODE1", "NODE3"), ("NODE2", "NODE4")):
        for pin in (1, 4, 6):
            h.wire(f"{node_a}_{pin}", (node_a, pin), (node_b, pin))
    return h, "HW-07_multidrop_buses.xlsx"


# ---------------------------------------------------------------------------
# HW-08  a mixed avionics harness: every connector type, every joint
# ---------------------------------------------------------------------------
def hw08():
    a = End([
        ("J1", "D38999/26WB35SN", 22),         # circular, engine bay
        ("J2", "DB37-M-37P", 37),              # D-sub, airframe
        ("J3", "TE-CPC-24", 24),               # rectangular, power
        ("J4", "PHOENIX-MSTB-2.5/12-TERMINAL", 12),   # terminal, test points
        ("J5", "RJ45-8P8C-JACK", 8),           # modular, ethernet
    ])
    b = End([
        ("P1", "D38999/26WB35PN", 22),
        ("P2", "DB37-F-37S", 37),
        ("P3", "TE-CPC-24-RCPT", 24),
        ("P4", "WAGO-TERMINAL-12", 12),
        ("P5", "RJ45-8P8C-PLUG", 8),
        ("P6", "M12-A-8P-MALE", 8),            # a branch that only B reaches
    ])
    h = Harness("HW-08", a, b)
    # power, fans out to three loads
    h.y("PWR_28V_A", ("J3", 1), [("P3", 1), ("P3", 2), ("P4", 1)], "28V_A",
        ["28V_A1", "28V_A2", "28V_A3"])
    h.y("PWR_28V_B", ("J3", 2), [("P3", 3), ("P6", 1)], "28V_B",
        ["28V_B1", "28V_B2"])
    # grounds merge into the return
    h.merge("GND_RET", [("J3", 4), ("J3", 5), ("J3", 6)], ("P3", 5), "GND",
            ["GND_1", "GND_2", "GND_3"])
    h.wire("ENG_A", ("J1", 1), ("P1", 1), "ENG_A")
    h.wire("ENG_B", ("J1", 2), ("P1", 2), "ENG_B")
    # ARINC twisted pair, plain
    h.wire("ARINC_A_HI", ("J1", 3), ("P1", 3), detail="twisted pair 1")
    h.wire("ARINC_A_LO", ("J1", 4), ("P1", 4), detail="twisted pair 1")
    h.splice("FUEL_LVL", ("J1", 5), ("P1", 5), "FUEL_LVL")
    h.splice("OIL_PRESS", ("J1", 6), ("P1", 6), "OIL_PRESS")
    h.crossed("LAMP_CMD", ("J1", 7), ("P1", 8), "LAMP_CMD")
    h.crossed("LAMP_RET", ("J1", 8), ("P1", 7), "LAMP_RET")
    h.y("FIRE_LOOP", ("J1", 9), [("P1", 9), ("P6", 2)], "FIRE_LOOP",
        ["FIRE_A", "FIRE_B"])
    h.wire("SHIELD", ("J1", 10), ("P1", 10), detail="shield drain wire")
    # CAN bus between the D-sub nodes (multi-drop)
    h.bus("CAN_H", [("J2", 7), ("J2", 8)], [("P2", 7), ("P2", 8), ("P4", 7)], "CAN_H")
    h.bus("CAN_L", [("J2", 9), ("J2", 10)], [("P2", 9), ("P2", 10), ("P4", 8)], "CAN_L")
    for pin in range(1, 7):
        h.wire(f"DISC_{pin}", ("J2", pin), ("P2", pin), f"DISC{pin}")
    for pin in range(11, 38):
        h.wire(f"SIG_{pin}", ("J2", pin), ("P2", pin), f"SIG{pin}")
    # test points straight to terminals
    for pin, target in zip(range(1, 7), [2, 3, 4, 5, 6, 9]):
        h.wire(f"TP_{pin}", ("J4", pin), ("P4", target), f"TP{pin}")
    # ethernet
    for tag, (p, q) in enumerate([(1, 2), (3, 6), (4, 5), (7, 8)], 1):
        h.wire(f"ETH_P{tag}_P", ("J5", p), ("P5", p), detail=f"twisted pair {tag}")
        h.wire(f"ETH_P{tag}_N", ("J5", q), ("P5", q), detail=f"twisted pair {tag}")
    return h, "HW-08_mixed_avionics_harness.xlsx"


# ---------------------------------------------------------------------------
# HW-09  density stress: ~250 pairs across eleven connectors of five types
# ---------------------------------------------------------------------------
def hw09():
    a = End([
        ("A-DSUB", "DB50-M-50P", 50),
        ("A-CIRC", "D38999/24WE35SN", 64),
        ("A-RECT", "AMPHENOL-RECT-64", 64),
        ("A-TERM", "PHOENIX-MSTB-TERMINAL-32", 32),
        ("A-MOD", "RJ45-8P8C-JACK", 8),
    ])  # 218 pins
    b = End([
        ("B-DSUB1", "DB37-F-37S", 37),
        ("B-DSUB2", "DB25-F-25S", 25),
        ("B-CIRC", "D38999/24WE35PN", 64),
        ("B-RECT1", "TE-CPC-48", 48),
        ("B-RECT2", "MOLEX-MINIFIT-32", 32),
        ("B-TERM", "WAGO-TERMINAL-42", 42),
        ("B-MOD", "RJ45-8P8C-PLUG", 8),
    ])  # 262 pins
    h = Harness("HW-09", a, b)
    # walk the A pins in order, landing them on B pins in order; every 9th A
    # pin is a Y to two B pins, every 31st a Y to three
    bpins = [(cid, n) for cid in b.order for n in range(1, b.conns[cid][1] + 1)]
    bi = 0
    k = 0
    for cid in a.order:
        for pin in range(1, a.conns[cid][1] + 1):
            k += 1
            if bi >= len(bpins):
                break
            fan = 3 if k % 31 == 0 else 2 if k % 9 == 0 else 1
            fan = min(fan, len(bpins) - bi)
            dsts = bpins[bi:bi + fan]
            bi += fan
            if fan == 1:
                h.wire(f"N{k:03d}", (cid, pin), dsts[0], f"S{k}")
            else:
                h.y(f"Y{k:03d}", (cid, pin), dsts, f"S{k}")
    return h, "HW-09_density_stress_5_types.xlsx"


def main():
    for fn in (hw01, hw02, hw03, hw04, hw05, hw06, hw07, hw08, hw09):
        h, filename = fn()
        h.write(filename)


if __name__ == "__main__":
    main()
