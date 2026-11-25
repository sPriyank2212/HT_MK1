"""Netlist — load, validate, and serialise test netlists (JSON / Excel / CSV)."""

from __future__ import annotations
import csv
import json
from dataclasses import dataclass, field


@dataclass
class NetPin:
    number: int
    name: str = ""


@dataclass
class Net:
    name: str
    pins: list[NetPin] = field(default_factory=list)
    connector_id: str = ""
    connector_id_b: str = ""
    connector_detail: str = ""
    connector_part_number: str = ""
    connector_part_number_b: str = ""
    source: str = ""
    destination: str = ""
    # Wire details, free text as written in the netlist.  Shown in the results
    # table, the CSV and the PDF; the colour is also named in the Sections view.
    wire_colour: str = ""
    awg: str = ""
    length: str = ""
    harness_no: str = ""
    r_min_mohm: float = 0.0
    r_max_mohm: float = 500.0
    hv_enabled: bool = False
    hv_voltage_v: int = 500
    hv_soak_ms: int = 1000
    hv_min_ir_mohm: float = 100.0


@dataclass
class Netlist:
    nets: list[Net] = field(default_factory=list)
    path: str = ""
    harness_id: str = ""
    warnings: list[str] = field(default_factory=list)

    def pin_name(self, number: int) -> str:
        """Return the name for a pin number, falling back to 'Pin N'."""
        for net in self.nets:
            for p in net.pins:
                if p.number == number:
                    return p.name or f"Pin {number}"
        return f"Pin {number}"

    def ordered_pairs(self) -> list[tuple[int, int, Net]]:
        """Return every (side_a_pin, side_b_pin, net) triple.

        Pin order within a net is significant: pins are stored source-first,
        and the firmware expands each net the same way — every i<j combination
        by *list position*, not by pin number (see nl_parse_json in harness.c).

        Never sort these.  pin_a and pin_b share the 1..37 number space but
        address different physical sides, so reordering them silently swaps
        source and destination.
        """
        out: list[tuple[int, int, Net]] = []
        for net in self.nets:
            nums = [p.number for p in net.pins]
            for i in range(len(nums)):
                for j in range(i + 1, len(nums)):
                    out.append((nums[i], nums[j], net))
        return out

    def net_for_pins(self, pin_a: int, pin_b: int) -> Net | None:
        """Return the Net wiring pin_a (side A) to pin_b (side B), or None.

        Direction-sensitive.  A netlist may legitimately contain both A1→B6
        and A6→B1 as two separate wires, so matching {pin_a, pin_b} as an
        unordered set picks the wrong net roughly half the time.
        """
        for a, b, net in self.ordered_pairs():
            if a == pin_a and b == pin_b:
                return net
        return None

    def all_pairs(self) -> list[tuple[int, int]]:
        """Return all expected (pin_a, pin_b) pairs across all nets."""
        return [(a, b) for a, b, _net in self.ordered_pairs()]


# ---------------------------------------------------------------------------
# Load / save
# ---------------------------------------------------------------------------

def load_netlist(path: str) -> Netlist:
    """Load a netlist from a JSON, Excel (.xlsx), or CSV file."""
    ext = path.lower().rsplit(".", 1)[-1]
    if ext in ("xlsx", "xls"):
        return _load_netlist_excel(path)
    if ext == "csv":
        return _load_netlist_csv(path)
    return _load_netlist_json(path)


def _load_netlist_json(path: str) -> Netlist:
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)

    harness_id = str(raw.get("harness_id", "")).strip()
    nets = []
    for n in raw.get("nets", []):
        pins = [NetPin(p["number"], p.get("name", "")) for p in n.get("pins", [])]
        nets.append(Net(
            name=n.get("name", "NET"),
            pins=pins,
            connector_id=str(n.get("connector_id", "")).strip(),
            connector_id_b=str(n.get("connector_id_b", "")).strip(),
            connector_detail=str(n.get("connector_detail", "")).strip(),
            connector_part_number=str(n.get("connector_part_number", "")).strip(),
            connector_part_number_b=str(n.get("connector_part_number_b", "")).strip(),
            source=str(n.get("source", "")).strip(),
            destination=str(n.get("destination", "")).strip(),
            wire_colour=_cell_text(n.get("wire_colour")),
            awg=_cell_text(n.get("awg")),
            length=_cell_text(n.get("length")),
            harness_no=_cell_text(n.get("harness_no")),
            r_min_mohm=float(n.get("r_min_mohm", 0)),
            r_max_mohm=float(n.get("r_max_mohm", 500)),
            hv_enabled=bool(n.get("hv_enabled", False)),
            hv_voltage_v=int(n.get("hv_voltage_v", 500)),
            hv_soak_ms=int(n.get("hv_soak_ms", 1000)),
            hv_min_ir_mohm=float(n.get("hv_min_ir_mohm", 100)),
        ))

    nl = Netlist(nets=nets, path=path, harness_id=harness_id)
    errors = validate_netlist(nl)
    if errors:
        raise ValueError("\n".join(errors))
    return nl


# ---------------------------------------------------------------------------
# Column-based (Excel / CSV) loader helpers
# ---------------------------------------------------------------------------
# Flat format — one row per net, columns mirror the GUI Results Table:
#
#   Net | Source | Conn ID | Src Pin Label | Src Pin # |
#   Harness ID | Dst Pin # | Dst Pin Label | Conn ID B |
#   Destination | Connector Detail | Colour | AWG | Length | Harness No
#
# Column matching is case-insensitive; spaces and underscores are equivalent.


def _cell_text(v) -> str:
    """A cell as text.  Excel hands back 22 as 22.0; show it the way it was typed."""
    if v is None:
        return ""
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v).strip()


_COL_ALIASES: dict[str, list[str]] = {
    "net":              ["net", "net_name", "network", "netname"],
    "source":           ["source", "src"],
    "connector_id":     ["conn_id", "connector_id", "src_conn_id"],
    "src_pin_name":     ["src_pin_label", "src_pin_name"],
    "src_pin_number":   ["src_pin_#", "src_pin_no", "src_pin_num", "src_pin_number"],
    "dst_pin_number":   ["dst_pin_#", "dst_pin_no", "dst_pin_num", "dst_pin_number"],
    "dst_pin_name":     ["dst_pin_label", "dst_pin_name"],
    "connector_id_b":   ["conn_id_b", "connector_id_b", "dst_conn_id"],
    "destination":      ["destination", "dest"],
    "connector_detail":        ["connector_detail", "conn_detail"],
    "connector_part_number":   ["part_number", "part_no", "part#", "conn_part_number"],
    "connector_part_number_b": ["part_number_b", "part_no_b", "part#_b", "conn_part_number_b"],
    "harness_id":              ["harness_id", "harness_num"],
    "wire_colour":      ["colour", "color", "wire_colour", "wire_color"],
    "awg":              ["awg", "wire_gauge", "gauge"],
    "length":           ["length", "wire_length"],
    "harness_no":       ["harness_no", "harness_no.", "harness_#", "harness_number"],
    "r_min_mohm":       ["r_min_mohm", "r_min"],
    "r_max_mohm":       ["r_max_mohm", "r_max"],
    "hv_enabled":       ["hv_enabled", "hv"],
    "hv_voltage_v":     ["hv_voltage_v", "hv_voltage"],
    "hv_soak_ms":       ["hv_soak_ms", "hv_soak"],
    "hv_min_ir_mohm":   ["hv_min_ir_mohm", "hv_ir_min"],
}


def _map_columns(headers: list[str]) -> dict[str, int]:
    """Return {field: column_index} for recognised headers."""
    normalised = [h.strip().lower().replace(" ", "_") for h in headers]
    col_map: dict[str, int] = {}
    for field, aliases in _COL_ALIASES.items():
        for i, h in enumerate(normalised):
            if h in aliases:
                col_map[field] = i
                break
    return col_map


def _rows_to_netlist(rows: list[list], col_map: dict[str, int], path: str) -> Netlist:
    """Flat format: one row = one net with source pin and destination pin."""
    if "net" not in col_map:
        raise ValueError("Netlist must have a 'Net' column")
    if "src_pin_number" not in col_map:
        raise ValueError("Netlist must have a 'Src Pin #' column")
    if "dst_pin_number" not in col_map:
        raise ValueError("Netlist must have a 'Dst Pin #' column")

    nets: list[Net] = []
    skipped: list[str] = []
    file_harness_id = ""

    def _get(row, field, default=None):
        idx = col_map.get(field)
        if idx is None or idx >= len(row):
            return default
        v = row[idx]
        return v if v not in (None, "") else default

    def _flt(row, field, default):
        v = _get(row, field)
        if v is None:
            return default
        try:
            return float(str(v))
        except (ValueError, TypeError):
            return default

    def _boo(row, field):
        v = _get(row, field)
        if v is None:
            return False
        if isinstance(v, bool):
            return v
        return str(v).strip().lower() in ("true", "1", "yes")

    for idx, row in enumerate(rows, start=2):
        if not file_harness_id:
            hid = _get(row, "harness_id")
            if hid is not None:
                file_harness_id = str(hid).strip()

        net_name = _get(row, "net")
        if not net_name:
            # Only warn if the row has at least some data; completely empty rows are normal padding
            if any(v not in (None, "") for v in row):
                skipped.append(f"Row {idx}: missing Net name")
            continue
        net_name = str(net_name).strip()

        try:
            src_num = int(float(str(_get(row, "src_pin_number", 0))))
            dst_num = int(float(str(_get(row, "dst_pin_number", 0))))
        except (ValueError, TypeError):
            skipped.append(f"Row {idx}: invalid Src/Dst Pin #")
            continue

        src_label = str(_get(row, "src_pin_name", "")).strip()
        dst_label = str(_get(row, "dst_pin_name", "")).strip()

        nets.append(Net(
            name=net_name,
            pins=[NetPin(src_num, src_label), NetPin(dst_num, dst_label)],
            connector_id=str(_get(row, "connector_id", "")).strip(),
            connector_id_b=str(_get(row, "connector_id_b", "")).strip(),
            connector_detail=str(_get(row, "connector_detail", "")).strip(),
            connector_part_number=str(_get(row, "connector_part_number", "")).strip(),
            connector_part_number_b=str(_get(row, "connector_part_number_b", "")).strip(),
            source=str(_get(row, "source", "")).strip(),
            destination=str(_get(row, "destination", "")).strip(),
            wire_colour=_cell_text(_get(row, "wire_colour")),
            awg=_cell_text(_get(row, "awg")),
            length=_cell_text(_get(row, "length")),
            harness_no=_cell_text(_get(row, "harness_no")),
            r_min_mohm=_flt(row, "r_min_mohm", 0.0),
            r_max_mohm=_flt(row, "r_max_mohm", 500.0),
            hv_enabled=_boo(row, "hv_enabled"),
            hv_voltage_v=int(_flt(row, "hv_voltage_v", 500.0)),
            hv_soak_ms=int(_flt(row, "hv_soak_ms", 1000.0)),
            hv_min_ir_mohm=_flt(row, "hv_min_ir_mohm", 100.0),
        ))

    nl = Netlist(nets=nets, path=path, harness_id=file_harness_id, warnings=skipped)
    errors = validate_netlist(nl)
    if errors:
        raise ValueError("\n".join(errors))
    return nl


def _load_netlist_excel(path: str) -> Netlist:
    try:
        import openpyxl
    except ImportError:
        raise ImportError("openpyxl is required for Excel support: pip install openpyxl")

    wb = openpyxl.load_workbook(path, data_only=True)
    ws = wb.active
    all_rows = list(ws.iter_rows(values_only=True))
    if not all_rows:
        raise ValueError("Excel file is empty")

    headers = [str(c) if c is not None else "" for c in all_rows[0]]
    col_map = _map_columns(headers)
    data_rows = [list(r) for r in all_rows[1:]]
    return _rows_to_netlist(data_rows, col_map, path)


def _load_netlist_csv(path: str) -> Netlist:
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        all_rows = list(reader)
    if not all_rows:
        raise ValueError("CSV file is empty")

    headers = all_rows[0]
    col_map = _map_columns(headers)
    return _rows_to_netlist(all_rows[1:], col_map, path)


def save_netlist(netlist: Netlist, path: str) -> None:
    raw = {
        "harness_id": netlist.harness_id,
        "nets": [
            {
                "name": n.name,
                "connector_id": n.connector_id,
                "connector_id_b": n.connector_id_b,
                "connector_detail": n.connector_detail,
                "connector_part_number": n.connector_part_number,
                "connector_part_number_b": n.connector_part_number_b,
                "source": n.source,
                "destination": n.destination,
                "wire_colour": n.wire_colour,
                "awg": n.awg,
                "length": n.length,
                "harness_no": n.harness_no,
                "pins": [{"number": p.number, "name": p.name} for p in n.pins],
                "r_min_mohm": n.r_min_mohm,
                "r_max_mohm": n.r_max_mohm,
                "hv_enabled": n.hv_enabled,
                "hv_voltage_v": n.hv_voltage_v,
                "hv_soak_ms": n.hv_soak_ms,
                "hv_min_ir_mohm": n.hv_min_ir_mohm,
            }
            for n in netlist.nets
        ]
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(raw, f, indent=2)


XLSX_HEADERS = ["Net", "Source", "Conn ID", "Part Number", "Src Pin Label", "Src Pin #",
                "Dst Pin #", "Dst Pin Label", "Conn ID B", "Part Number B", "Destination",
                "Connector Detail", "Colour", "AWG", "Length", "Harness No"]


def save_netlist_xlsx(netlist: Netlist, path: str) -> None:
    """Write the netlist as an Excel sheet in the flat one-wire-per-row format
    that load_netlist reads back.  A net with more than two pins gets one row
    per destination, all from the first pin."""
    import openpyxl
    from openpyxl.styles import Font
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Netlist"
    headers = list(XLSX_HEADERS)
    if netlist.harness_id:
        headers.append("Harness ID")
    ws.append(headers)
    for c in ws[1]:
        c.font = Font(bold=True)
    for n in netlist.nets:
        src = n.pins[0]
        for dst in n.pins[1:]:
            row = [n.name, n.source, n.connector_id, n.connector_part_number,
                   src.name, src.number, dst.number, dst.name,
                   n.connector_id_b, n.connector_part_number_b, n.destination,
                   n.connector_detail, n.wire_colour, n.awg, n.length, n.harness_no]
            if netlist.harness_id:
                row.append(netlist.harness_id)
            ws.append(row)
    for i, h in enumerate(headers, start=1):
        ws.column_dimensions[openpyxl.utils.get_column_letter(i)].width = max(10, len(h) + 4)
    ws.freeze_panes = "A2"
    wb.save(path)


def netlist_to_bytes(netlist: Netlist) -> bytes:
    """Serialise netlist to compact JSON bytes for firmware upload."""
    raw = {
        "nets": [
            {
                "name": n.name,
                "pins": [{"n": p.number, "l": p.name} for p in n.pins],
                "rmax": int(n.r_max_mohm),
                "hv": n.hv_enabled,
            }
            for n in netlist.nets
        ]
    }
    return json.dumps(raw, separators=(",", ":")).encode("utf-8")


def _normalise_header(h: str) -> str:
    return h.strip().lower().replace(" ", "_").replace("-", "_")


def _config_is_pinmap(path: str) -> bool:
    """True if *path* is the per-channel pin-map format (see core.pinmap)."""
    import openpyxl
    from .pinmap import is_pinmap_sheet
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    try:
        first = next(wb.active.iter_rows(max_row=1, values_only=True), ())
    finally:
        wb.close()
    return is_pinmap_sheet(list(first))


def load_connector_config(path: str) -> list[dict]:
    """Load a legacy range-style connector Excel and return [{connector_id, connector_name, start_pin, end_pin}]."""
    try:
        import openpyxl
    except ImportError as exc:
        raise ImportError("openpyxl is required for Excel support: pip install openpyxl") from exc

    wb = openpyxl.load_workbook(path, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    if not rows:
        raise ValueError("Connector config Excel is empty")

    headers = [_normalise_header(str(c)) if c is not None else "" for c in rows[0]]
    col = {h: i for i, h in enumerate(headers)}

    required = {"connector_id", "start_pin", "end_pin"}
    missing = required - set(col.keys())
    if missing:
        raise ValueError(f"Connector config missing columns: {missing}")

    def _int_cell(row, name):
        idx = col.get(name)
        if idx is None or idx >= len(row):
            return None
        v = row[idx]
        if v is None or v == "":
            return None
        try:
            return int(float(str(v)))
        except (ValueError, TypeError):
            return None

    configs = []
    for row in rows[1:]:
        cid = str(row[col["connector_id"]]) if col["connector_id"] < len(row) and row[col["connector_id"]] is not None else ""
        if not cid:
            continue
        cname = str(row[col.get("connector_name", -1)]) if "connector_name" in col and col["connector_name"] < len(row) and row[col["connector_name"]] is not None else ""
        start = _int_cell(row, "start_pin")
        end = _int_cell(row, "end_pin")
        if start is None or end is None:
            raise ValueError(f"Connector '{cid}' missing Start Pin or End Pin")
        configs.append({
            "connector_id": cid,
            "connector_name": cname,
            "start_pin": start,
            "end_pin": end,
        })
    return configs


class PinRefError(ValueError):
    """A netlist wire names a connector pin the connector config does not have."""


def uses_dest_pins(config_path: str) -> bool:
    """True if the config gives Side B its own connectors / pins (a Dest Pin)."""
    if not _config_is_pinmap(config_path):
        return False
    from .pinmap import load_pinmap
    return load_pinmap(config_path).has_dest_pins


def channel_table(config_path: str) -> dict[int, dict]:
    """Return {channel: {connector_id, connector_id_b, connector_name, conn_pin,
    dest_pin}}.

    connector_id_b is the name of the connector's Side-B end (the same as
    connector_id unless the config gives a Dst Conn ID).  With a Dest Pin
    in the config each channel names its own Side-B connector and pin, and an
    end with no pigtail has connector "" and pin None; otherwise dest_pin is
    conn_pin.

    Reads either the per-channel sheet (core.pinmap, channels in any order)
    or the legacy Connector ID / Start Pin / End Pin range sheet.
    """
    if _config_is_pinmap(config_path):
        from .pinmap import load_pinmap
        pm = load_pinmap(config_path)
        if pm.has_dest_pins:
            def end(e):
                return e if e else ("", None)
            return {c.number: {"connector_id": end(c.end_a)[0],
                               "connector_id_b": end(c.end_b)[0],
                               "connector_name": c.connector_name,
                               "conn_pin": end(c.end_a)[1],
                               "dest_pin": end(c.end_b)[1]}
                    for c in pm.channels}
        labels = pm.dest_labels()
        return {c.number: {"connector_id": c.connector_id,
                           "connector_id_b": labels[c.connector_id],
                           "connector_name": c.connector_name,
                           "conn_pin": c.conn_pin,
                           "dest_pin": c.conn_pin}
                for c in pm.channels}
    table: dict[int, dict] = {}
    for cfg in load_connector_config(config_path):
        for local, ch in enumerate(range(cfg["start_pin"], cfg["end_pin"] + 1), start=1):
            table[ch] = {"connector_id": cfg["connector_id"],
                         "connector_id_b": cfg["connector_id"],
                         "connector_name": cfg["connector_name"],
                         "conn_pin": local,
                         "dest_pin": local}
    return table


def _resolve_pin_refs(netlist: "Netlist", table: dict[int, dict]) -> None:
    """Turn a netlist written in connector pins into channel numbers.

    With a Dest Pin in the config a wire says "J1 pin 20 -> X2 pin 6": Conn ID
    + Src Pin # on Side A, Conn ID B + Dst Pin # on Side B.  Each end is looked
    up in the config; the first pin of a net is a Side-A end and the rest are
    Side-B ends.  Names must match the config exactly and every end must be a
    pin that has a pigtail.  Raises PinRefError listing every end that does
    not, and changes nothing in that case.
    """
    ends_a = {(t["connector_id"], t["conn_pin"]): ch
              for ch, t in table.items() if t["conn_pin"] is not None}
    ends_b = {(t["connector_id_b"], t["dest_pin"]): ch
              for ch, t in table.items() if t["dest_pin"] is not None}
    names_a = sorted({name for name, _ in ends_a})
    names_b = sorted({name for name, _ in ends_b})

    errors: list[str] = []
    plan: list[tuple] = []
    for net in netlist.nets:
        chans: list[int] = []
        for i, pin in enumerate(net.pins):
            side_b = i > 0
            column = "Conn ID B" if side_b else "Conn ID"
            name = (net.connector_id_b if side_b else net.connector_id).strip()
            ends, names = (ends_b, names_b) if side_b else (ends_a, names_a)
            ch = ends.get((name, pin.number))
            if ch is None:
                side = "B" if side_b else "A"
                if not name:
                    errors.append(f"{net.name}: {column} is empty")
                elif name not in names:
                    errors.append(f"{net.name}: {column} '{name}' is not a Side-{side} "
                                  f"connector in the config ({', '.join(names) or 'none'})")
                else:
                    errors.append(f"{net.name}: {name} pin {pin.number} has no pigtail "
                                  f"on Side {side} in the config")
            chans.append(ch)
        plan.append((net, chans))
    if errors:
        raise PinRefError("\n".join(errors))

    for net, chans in plan:
        for pin, ch in zip(net.pins, chans):
            pin.number = ch
        first, last = table[chans[0]], table[chans[-1]]
        net.connector_id = first["connector_id"]
        net.connector_id_b = last["connector_id_b"]
        net.connector_detail = (f"{first['connector_name'] or first['connector_id']}"
                                f" -> {last['connector_id_b']}")


def apply_connector_config(netlist: Netlist, config_path: str) -> None:
    """Update *netlist* connector_id / connector_id_b / connector_detail from an Excel config.

    When the config has a Dest Pin the netlist is in connector pins and its
    pin numbers are replaced by channel numbers (see _resolve_pin_refs).
    """
    table = channel_table(config_path)
    if not table:
        raise ValueError("Connector config contains no entries")
    if uses_dest_pins(config_path):
        _resolve_pin_refs(netlist, table)
        return

    for net in netlist.nets:
        pins = net.pins
        if len(pins) < 2:
            continue

        src_pin = pins[0].number
        dst_pin = pins[1].number
        src_cfg = table.get(src_pin)
        dst_cfg = table.get(dst_pin)

        if src_cfg:
            net.connector_id = src_cfg["connector_id"]
            net.connector_detail = src_cfg["connector_name"] or src_cfg["connector_id"]
        if dst_cfg:
            net.connector_id_b = dst_cfg["connector_id"]

        if src_cfg and dst_cfg and src_cfg["connector_id"] != dst_cfg["connector_id"]:
            src_detail = src_cfg["connector_name"] or src_cfg["connector_id"]
            dst_detail = dst_cfg["connector_name"] or dst_cfg["connector_id"]
            if dst_cfg["connector_id_b"] != dst_cfg["connector_id"]:
                dst_detail = dst_cfg["connector_id_b"]
            net.connector_detail = f"{src_detail} -> {dst_detail}"


def dest_labels(config_path: str) -> dict[str, str]:
    """Return {connector_id: name of its Side-B end} from a config Excel.

    Empty when the config has a Dest Pin: Side B then has connectors of its
    own (see connector_pin_mapping_b) rather than renamed copies of Side A's.
    """
    if uses_dest_pins(config_path):
        return {}
    return {t["connector_id"]: t["connector_id_b"]
            for t in channel_table(config_path).values()}


def connector_pin_mapping(config_path: str) -> dict[int, tuple[str, int]]:
    """Return {global_pin: (connector_id, local_pin_number)} from a config Excel."""
    return {ch: (t["connector_id"], t["conn_pin"])
            for ch, t in channel_table(config_path).items() if t["conn_pin"] is not None}


def connector_pin_mapping_b(config_path: str) -> dict[int, tuple[str, int]]:
    """Return {channel: (Side-B connector, Side-B pin)}; empty unless the config
    has a Dest Pin, since otherwise Side B is Side A under its Dst Conn ID."""
    if not uses_dest_pins(config_path):
        return {}
    return {ch: (t["connector_id_b"], t["dest_pin"])
            for ch, t in channel_table(config_path).items() if t["dest_pin"] is not None}


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def pairs_to_netlist(pairs: list[tuple[int, int]],
                     harness_id: str = "",
                     name_prefix: str = "WIRE_") -> Netlist:
    """Convert a list of (pin_a, pin_b) pairs into a Netlist."""
    nets = [
        Net(
            name=f"{name_prefix}{i}",
            pins=[NetPin(pa, f"A{pa}"), NetPin(pb, f"B{pb}")],
            source="Side A",
            destination="Side B",
        )
        for i, (pa, pb) in enumerate(pairs, start=1)
    ]
    return Netlist(nets=nets, harness_id=harness_id)


def validate_netlist(netlist: Netlist) -> list[str]:
    """Return a list of validation error strings (empty = valid)."""
    errors: list[str] = []

    if not netlist.nets:
        errors.append("Netlist contains no nets")
        return errors

    for i, net in enumerate(netlist.nets):
        if not net.name:
            errors.append(f"Net {i + 1}: name is empty")
        if len(net.pins) < 2:
            errors.append(f"Net '{net.name}': must have at least 2 pins (has {len(net.pins)})")
        for pin in net.pins:
            if not (1 <= pin.number <= 256):
                errors.append(f"Net '{net.name}': pin number {pin.number} out of range (1–256)")
        if net.r_max_mohm <= 0:
            errors.append(f"Net '{net.name}': r_max_mohm must be > 0")
        if net.hv_enabled:
            if not (100 <= net.hv_voltage_v <= 1000):
                errors.append(f"Net '{net.name}': hv_voltage_v {net.hv_voltage_v}V out of range (100–1000)")
            if net.hv_soak_ms < 100:
                errors.append(f"Net '{net.name}': hv_soak_ms {net.hv_soak_ms} too short (min 100)")

    return errors
