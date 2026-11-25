"""Connector pin map: which firmware channel each connector pin is wired to.

The firmware owns channel -> MCU pin (SIDE_A / SIDE_B in harness.c, fixed at
build time) and only ever speaks channel numbers.  Which connector pin sits
on which channel is decided by how the fixture is wired, and is configured
here — in the GUI only — via connector_config.xlsx, the single source of
truth for this mapping:

    Channel | Src Conn ID | Dst Conn ID | Connector Name | Src Pin | Dest Pin
    20      | J2          | X2          | J2 (DB15)      | 5       |

(Sheets headed Connector ID / Dest Connector ID / Conn Pin, as older builds wrote
them, are read as well.)

Channel, Src Conn ID and Src Pin are required and define the mapping used.
Dst Conn ID is optional: it is the name the Side-B (destination) end of
the connector is shown under, e.g. J1 on the tester fixture is plugged into X1
of the harness.  Blank means the same name as Src Conn ID.  It is only a
label: wires still join the same channel and the same pin number.
Side A MCU / Side B MCU columns, in sheets that still carry them (the master
netlists/connector_config.xlsx), are optional free-text notes for whoever wired
the board.  The GUI does not show, save or export them: the Configuration tab
drops them on import, and the config it keeps is stripped of them
(strip_mcu_columns), so the customer never sees which MCU pin drives a channel.
They are NOT checked against the firmware.  Where present they are checked
only against a small static list of pins the Nucleo board itself reserves
(SWD, LEDs, button, ST-Link UART, clock input) and against each other for
duplicates within the sheet.

Dest Pin is also optional.  Fill it in when Side B is wired differently from
Side A, e.g. one DB37 on Side A facing X1 / X2 (DB15) and X3 (DB9) on Side B:
every row then says which Side-B connector (Dst Conn ID) and pin the
channel ends on.  A netlist is then written in connector pins - Conn ID +
Src Pin # for Side A, Conn ID B + Dst Pin # for Side B - and the GUI turns
each end into a channel.

With a Dest Pin in the sheet the two sides are independent: a channel's Side-A
GPIO and its Side-B GPIO each have their own pigtail to a connector pin, or
none.  An end that is wired needs both of its fields (Src Conn ID + Src Pin,
Dst Conn ID + Dest Pin); an end with no pigtail leaves both blank.

Channels may be listed in any order, and unused channels may be left out —
a netlist referencing a channel this sheet does not define is flagged by
core.netlist / MainWindow, since there is nothing here to say what connector
pin (or whether a real one at all) that channel corresponds to.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

_PIN_RE = re.compile(r"^P([A-G])(1[0-5]|[0-9])$")

# Pins the Nucleo-F303ZE board itself reserves, regardless of how channels
# are mapped: SWD, on-board LEDs, user button, ST-Link VCP UART, HSE input.
# Fixed properties of the board, not of the firmware's channel table.
RESERVED = {
    "PA13": "SWDIO", "PA14": "SWCLK",
    "PB0": "LD1 LED", "PB7": "LD2 LED", "PB14": "LD3 LED",
    "PC13": "user button", "PC14": "LSE", "PC15": "LSE",
    "PD8": "USART3 TX (ST-Link VCP)", "PD9": "USART3 RX (ST-Link VCP)",
    "PF0": "HSE clock input",
}

# Pins commonly used for another on-board function — allowed, but a fault on
# one of these channels may be that function interfering, not the harness.
SHARED = {
    "PE2": "TPIU trace (TRACECLK)", "PE3": "TPIU trace (TRACED0)",
    "PE4": "TPIU trace (TRACED1)", "PE5": "TPIU trace (TRACED2)",
    "PE6": "TPIU trace (TRACED3)",
    "PB3": "SWO", "PA15": "JTDI", "PB4": "NJTRST",
    "PA11": "USB DM", "PA12": "USB DP", "PB2": "BOOT1",
    "PG6": "USB power switch",
}


@dataclass(frozen=True)
class Channel:
    number: int            # channel number the firmware protocol uses
    connector_id: str
    connector_name: str
    conn_pin: int | str | None   # pin number on the physical connector (the Src Pin column)
    side_a: str = ""       # MCU pin note, e.g. "PC9" — documentation only; never shown in the GUI
    side_b: str = ""
    connector_id_b: str = ""   # name of the Side-B end of the connector; "" = same
    dest_pin: int | str | None = None   # pin on the Side-B connector; None = same as conn_pin

    @property
    def end_a(self) -> tuple[str, int] | None:
        """(connector, pin) the Side-A GPIO is wired to; None if it has no pigtail."""
        if self.connector_id and isinstance(self.conn_pin, int):
            return self.connector_id, self.conn_pin
        return None

    @property
    def end_b(self) -> tuple[str, int] | None:
        """(connector, pin) the Side-B GPIO is wired to, once a Dest Pin is in use;
        None if it has no pigtail."""
        if self.connector_id_b and isinstance(self.dest_pin, int):
            return self.connector_id_b, self.dest_pin
        return None


@dataclass
class PinMap:
    channels: list[Channel]          # sorted by channel number
    warnings: list[str]

    def by_channel(self) -> dict[int, Channel]:
        return {c.number: c for c in self.channels}

    def dest_labels(self) -> dict[str, str]:
        """{connector_id: name of its Side-B end}; the same name when none is set."""
        return dest_labels(self.channels)

    @property
    def has_dest_pins(self) -> bool:
        """True when Side B has its own connectors / pin numbers (a Dest Pin is set)."""
        return has_dest_pins(self.channels)

    def summary(self) -> str:
        """e.g. 'J1: 15 pins, J2: 15 pins, J3: 7 pins'; with Dest Pins, the
        Side-A and Side-B connectors are both listed."""
        def count(names) -> str:
            counts: dict[str, int] = {}
            for n in names:
                counts[n] = counts.get(n, 0) + 1
            return ", ".join(f"{k}: {v} pins" for k, v in counts.items())

        if not self.has_dest_pins:
            return count(c.connector_id for c in self.channels)
        side_a = count(c.end_a[0] for c in self.channels if c.end_a)
        side_b = count(c.end_b[0] for c in self.channels if c.end_b)
        return f"Side A  {side_a or 'none'}  |  Side B  {side_b or 'none'}"


def dest_labels(channels) -> dict[str, str]:
    """{connector_id: Side-B name}.  The first non-blank Dst Conn ID of a
    connector's rows wins; load_pinmap rejects rows that disagree."""
    out: dict[str, str] = {}
    for c in channels:
        out.setdefault(c.connector_id, "")
        if not out[c.connector_id] and c.connector_id_b:
            out[c.connector_id] = c.connector_id_b
    return {k: v or k for k, v in out.items()}


def has_dest_pins(channels) -> bool:
    return any(isinstance(c.dest_pin, int) for c in channels)


def normalise_pin(name) -> str:
    return str(name or "").strip().upper().replace("_", "").replace(" ", "")


def _norm_header(h) -> str:
    return str(h).strip().lower().replace(" ", "_").replace("-", "_") if h is not None else ""


_ALIASES = {
    "channel":        ["channel", "ch", "channel_#", "channel_no"],
    "connector_id":   ["src_conn_id", "connector_id", "conn_id", "connector"],
    "connector_id_b": ["dst_conn_id", "dest_connector_id", "dest_conn_id", "connector_id_b",
                       "conn_id_b", "side_b_connector_id"],
    "connector_name": ["connector_name", "conn_name"],
    "conn_pin":       ["src_pin", "conn_pin", "connector_pin", "conn_pin_#"],
    "dest_pin":       ["dest_pin", "dest_conn_pin", "dst_pin", "side_b_pin"],
    "side_a":         ["side_a_mcu", "side_a", "mcu_a"],
    "side_b":         ["side_b_mcu", "side_b", "mcu_b"],
}


def is_pinmap_sheet(headers: list) -> bool:
    """True for the per-channel sheet; False for the legacy
    Connector ID / Start Pin / End Pin range sheet."""
    norm = {_norm_header(h) for h in headers}
    return any(a in norm for a in _ALIASES["channel"]) and \
           any(a in norm for a in _ALIASES["conn_pin"])


def load_pinmap(path: str) -> PinMap:
    """Read and validate a per-channel connector_config.xlsx.

    Raises ValueError listing every problem, so the sheet can be fixed in
    one pass.  Validation is entirely self-contained to this file: no
    firmware source is read or assumed.
    """
    import openpyxl
    wb = openpyxl.load_workbook(path, data_only=True)
    rows = list(wb.active.iter_rows(values_only=True))
    if not rows:
        raise ValueError("Connector config is empty")

    headers = [_norm_header(h) for h in rows[0]]
    col: dict[str, int] = {}
    for field, names in _ALIASES.items():
        for n in names:
            if n in headers:
                col[field] = headers.index(n)
                break
    missing = [f for f in ("channel", "connector_id", "conn_pin") if f not in col]
    if missing:
        raise ValueError(f"Connector config missing column(s): {', '.join(missing)}")

    def cell(row, field):
        i = col.get(field)
        return row[i] if i is not None and i < len(row) else None

    errors: list[str] = []
    channels: list[Channel] = []
    seen_ch: dict[int, int] = {}
    seen_pin: dict[tuple[str, int], int] = {}
    dest_ends: list[tuple[int, str, int]] = []   # row, Side-B connector, Side-B pin
    seen_mcu: dict[str, int] = {}
    dest_rows: list[tuple[int, str, str]] = []

    # With a Dest Pin anywhere, Side A and Side B are independent and either end
    # of a channel may have no pigtail (both of its fields blank).
    dest_mode = any(cell(row, "dest_pin") not in (None, "") for row in rows[1:])

    for r, row in enumerate(rows[1:], start=2):
        if all(v in (None, "") for v in row):
            continue
        try:
            ch = int(float(cell(row, "channel")))
            blank_pin = dest_mode and cell(row, "conn_pin") in (None, "")
            conn_pin = None if blank_pin else int(float(cell(row, "conn_pin")))
        except (TypeError, ValueError):
            errors.append(f"Row {r}: Channel and Src Pin must be numbers")
            continue
        dest_pin = None
        raw_dest = cell(row, "dest_pin")
        if raw_dest not in (None, ""):
            try:
                dest_pin = int(float(raw_dest))
            except (TypeError, ValueError):
                errors.append(f"Row {r}: Dest Pin must be a number")
                continue
            if dest_pin < 1:
                errors.append(f"Row {r}: Dest Pin must be 1 or greater")
                continue
        if ch < 1:
            errors.append(f"Row {r}: channel must be 1 or greater")
            continue
        conn_id = str(cell(row, "connector_id") or "").strip()
        dest_id = str(cell(row, "connector_id_b") or "").strip()
        if dest_mode:
            if bool(conn_id) != (conn_pin is not None):
                errors.append(f"Row {r}: Src Conn ID and Src Pin must both be filled, "
                              f"or both left blank if Side A has no pigtail")
                continue
            if bool(dest_id) != (dest_pin is not None):
                errors.append(f"Row {r}: Dst Conn ID and Dest Pin must both be filled, "
                              f"or both left blank if Side B has no pigtail")
                continue
            if not conn_id and not dest_id:
                errors.append(f"Row {r}: channel {ch} is wired on neither side")
                continue
        elif not conn_id:
            errors.append(f"Row {r}: missing Src Conn ID")
            continue
        if ch in seen_ch:
            errors.append(f"Row {r}: channel {ch} already used on row {seen_ch[ch]}")
            continue
        if conn_id and (conn_id, conn_pin) in seen_pin:
            errors.append(f"Row {r}: {conn_id} pin {conn_pin} already on row "
                          f"{seen_pin[(conn_id, conn_pin)]}")
            continue
        seen_ch[ch] = r
        if conn_id:
            seen_pin[(conn_id, conn_pin)] = r

        side_a = normalise_pin(cell(row, "side_a"))
        side_b = normalise_pin(cell(row, "side_b"))
        for side, name in (("A", side_a), ("B", side_b)):
            if not name:
                continue
            if not _PIN_RE.match(name):
                errors.append(f"Row {r}: channel {ch} Side {side} ('{name}') is not "
                              f"a recognisable MCU pin name (expected PA0 .. PG15)")
                continue
            if name in RESERVED:
                errors.append(f"Row {r}: channel {ch} Side {side} ({name}) is "
                              f"reserved on this board ({RESERVED[name]})")
            if name in seen_mcu:
                errors.append(f"Row {r}: channel {ch} Side {side} ({name}) is "
                              f"already used on row {seen_mcu[name]}")
            else:
                seen_mcu[name] = r

        channels.append(Channel(ch, conn_id,
                                str(cell(row, "connector_name") or "").strip(),
                                conn_pin, side_a, side_b, dest_id, dest_pin))
        dest_rows.append((r, conn_id, dest_id))
        if channels[-1].end_b:
            dest_ends.append((r, *channels[-1].end_b))

    if has_dest_pins(channels):
        # Side B has its own connectors and pins: a Side-B connector pin can
        # only be one channel.
        seen_b: dict[tuple[str, int], int] = {}
        for r, name, pin in dest_ends:
            if (name, pin) in seen_b:
                errors.append(f"Row {r}: Side-B {name} pin {pin} already on row "
                              f"{seen_b[(name, pin)]}")
            else:
                seen_b[(name, pin)] = r
    else:
        # A connector has one Side-B name, and two connectors cannot share one.
        first_dest: dict[str, tuple[int, str]] = {}
        for r, conn_id, dest in dest_rows:
            if not dest:
                continue
            if conn_id not in first_dest:
                first_dest[conn_id] = (r, dest)
            elif first_dest[conn_id][1] != dest:
                errors.append(f"Row {r}: {conn_id} has Dst Conn ID '{dest}' but row "
                              f"{first_dest[conn_id][0]} gives '{first_dest[conn_id][1]}'")
        if not errors:
            by_label: dict[str, str] = {}
            for conn_id, label in dest_labels(channels).items():
                if label in by_label:
                    errors.append(f"{by_label[label]} and {conn_id} both use Side-B name '{label}'")
                by_label[label] = conn_id

    if errors:
        raise ValueError("\n".join(errors))

    channels.sort(key=lambda c: c.number)
    warnings = []
    for c in channels:
        for side, pin, end in (("A", c.side_a, c.end_a),
                               ("B", c.side_b, c.end_b if dest_mode else c.end_a)):
            if pin in SHARED:
                where = f"{end[0]} pin {end[1]}" if end else "no connector pin"
                warnings.append(f"{where} (channel {c.number} side {side}) is noted "
                                f"as {pin}, shared with {SHARED[pin]}")
    return PinMap(channels, warnings)


def read_rows(path: str) -> list[list[str]]:
    """Read a per-channel sheet as raw text rows, without validating it.

    Returns [channel, connector_id, dest_connector_id, connector_name, conn_pin,
    dest_pin] per non-empty row.  Used to import a sheet into the Configuration
    tab, where a broken sheet still has to load so it can be fixed.  The MCU
    pin columns of a sheet are left out on purpose: they are not shown to or
    kept for the user.
    """
    import openpyxl
    wb = openpyxl.load_workbook(path, data_only=True)
    rows = list(wb.active.iter_rows(values_only=True))
    if not rows:
        return []
    headers = [_norm_header(h) for h in rows[0]]
    col: dict[str, int] = {}
    for field, names in _ALIASES.items():
        for n in names:
            if n in headers:
                col[field] = headers.index(n)
                break

    def text(row, field) -> str:
        i = col.get(field)
        v = row[i] if i is not None and i < len(row) else None
        if v is None:
            return ""
        if isinstance(v, float) and v.is_integer():
            v = int(v)
        return str(v).strip()

    fields = ("channel", "connector_id", "connector_id_b", "connector_name",
              "conn_pin", "dest_pin")
    out = []
    for row in rows[1:]:
        if all(v in (None, "") for v in row):
            continue
        out.append([text(row, f) for f in fields])
    return out


# Connector IDs the default config used before it switched to the J-numbers
# that are printed next to the connectors on the fixture.
LEGACY_IDS = {"DB15-1": ("J1", "J1 (DB15)"),
              "DB15-2": ("J2", "J2 (DB15)"),
              "DB9":    ("J3", "J3 (DB9)")}
_LEGACY_NAMES = {"DB15 Connector 1", "DB15 Connector 2", "DB9 Connector"}


def migrate_legacy_ids(path: str) -> bool:
    """Rename DB15-1 / DB15-2 / DB9 to J1 / J2 / J3 in a saved config.

    A config copied out of an older build still carries the old IDs; without
    this the user would have to press 'Reset to Default' to see the new names.
    Returns True if the file was changed.
    """
    import openpyxl
    wb = openpyxl.load_workbook(path)
    ws = wb.active
    headers = [_norm_header(c.value) for c in ws[1]]
    try:
        id_col = next(i for i, h in enumerate(headers) if h in _ALIASES["connector_id"])
    except StopIteration:
        return False
    name_col = next((i for i, h in enumerate(headers) if h in _ALIASES["connector_name"]), None)
    changed = False
    for row in ws.iter_rows(min_row=2):
        new = LEGACY_IDS.get(str(row[id_col].value or "").strip())
        if not new:
            continue
        row[id_col].value = new[0]
        if name_col is not None and str(row[name_col].value or "").strip() in _LEGACY_NAMES:
            row[name_col].value = new[1]
        changed = True
    if changed:
        wb.save(path)
    return changed


NOTES = [
    "Connector configuration - how the tester's channels map to connector pins",
    "",
    "One row per channel.  The tester only ever talks in channel numbers; this",
    "sheet is what turns a channel into 'J2 pin 9' on screen and in reports.",
    "",
    "Channel          The tester's channel number.  Netlists use these numbers in",
    "                 their Src Pin # / Dst Pin # columns.  Must be unique.",
    "Src Conn ID      Which connector this channel belongs to (J1, J2, J3).",
    "Dst Conn ID      Optional.  The name of the same connector on the Side-B",
    "                 (destination) end, e.g. X1.  Blank = same as Src Conn ID.",
    "                 Pin numbers and channels stay as they are; only the name",
    "                 shown on screen and in reports changes.  One name per",
    "                 connector, and no two connectors may share a name.",
    "Connector Name   Free text shown in the netlist tree.",
    "Src Pin          The pin number on that connector (1, 2, 3 ...).",
    "Dest Pin         Optional.  The pin number on the Side-B connector.  Fill it in",
    "                 when Side B is wired differently from Side A, e.g. one DB37 on",
    "                 Side A facing X1 / X2 (DB15) and X3 (DB9) on Side B.  Then every",
    "                 row says which Side-B connector (Dst Conn ID) and pin it",
    "                 ends on, and a netlist is written in connector pins: Conn ID +",
    "                 Src Pin # on Side A, Conn ID B + Dst Pin # on Side B.  Leave the",
    "                 column empty and netlists keep using channel numbers.",
    "                 With a Dest Pin in the sheet the two sides are independent: a",
    "                 channel's Side-A and Side-B GPIO each have a pigtail, or none.",
    "                 A wired end needs both its fields (Src Conn ID + Src Pin,",
    "                 Dst Conn ID + Dest Pin); an end with no pigtail leaves",
    "                 both blank.  A netlist may not use an end that has no pigtail.",
    "",
    "Rules checked on load (errors block Start):",
    "  - a channel number or a connector pin listed twice",
    "  - without Dest Pin: a connector given two different Dst Conn IDs, or",
    "    two connectors given the same one",
    "  - with Dest Pin: a Side-B connector pin listed twice",
    "A netlist that uses a channel not listed here is also refused.",
    "",
    "Editing: change Src Conn ID / Src Pin to say where a channel is wired, save,",
    "then press 'Config...' in the GUI and pick this file.  No firmware change needed.",
]


def _add_notes_sheet(wb) -> None:
    """A second sheet for whoever edits the file.  The tester reads only the
    first sheet, so this can be changed freely."""
    from openpyxl.styles import Font
    notes = wb.create_sheet("Notes")
    for line in NOTES:
        notes.append([line])
    notes["A1"].font = Font(bold=True, size=12)
    notes.column_dimensions["A"].width = 110


def write_pinmap_xlsx(path: str, channels: list[Channel]) -> None:
    """Write the sheet the GUI keeps and exports.  The MCU pin columns are not
    written, whatever the channels carry."""
    import openpyxl
    from openpyxl.styles import Font
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Connector Config"
    ws.append(["Channel", "Src Conn ID", "Dst Conn ID", "Connector Name",
               "Src Pin", "Dest Pin"])
    for c in ws[1]:
        c.font = Font(bold=True)
    for ch in channels:
        ws.append([ch.number, ch.connector_id or None, ch.connector_id_b or None,
                   ch.connector_name,
                   None if ch.conn_pin in ("", None) else ch.conn_pin,
                   ch.dest_pin or None])
    for letter, width in zip("ABCDEF", (9, 14, 18, 20, 10, 10)):
        ws.column_dimensions[letter].width = width
    ws.freeze_panes = "A2"
    _add_notes_sheet(wb)
    wb.save(path)


_HEADER_TITLES = {"connector_id": "Src Conn ID", "connector_id_b": "Dst Conn ID",
                  "conn_pin": "Src Pin"}


def strip_mcu_columns(path: str) -> bool:
    """Remove the Side A MCU / Side B MCU columns from a saved config, give its
    headers their current names, and bring its Notes sheet up to date.
    Returns True if the file was changed.

    The app's own copy of the config is seeded from the master sheet, which
    carries the MCU pins; this keeps them out of the file the user can open.
    """
    import openpyxl
    wb = openpyxl.load_workbook(path)
    ws = wb.worksheets[0]
    headers = [_norm_header(c.value) for c in ws[1]]
    mcu = _ALIASES["side_a"] + _ALIASES["side_b"]
    cols = [i + 1 for i, h in enumerate(headers) if h in mcu]
    if not cols:
        return False
    for c in sorted(cols, reverse=True):
        ws.delete_cols(c)
    for cell in ws[1]:
        for field, title in _HEADER_TITLES.items():
            if _norm_header(cell.value) in _ALIASES[field]:
                cell.value = title
    if "Notes" in wb.sheetnames:
        del wb["Notes"]
    _add_notes_sheet(wb)
    wb.save(path)
    return True
