"""ResultModel — QAbstractTableModel backing the Results Table view."""

from __future__ import annotations
from datetime import datetime

from PyQt6.QtCore import Qt, QAbstractTableModel, QModelIndex, QSortFilterProxyModel
from PyQt6.QtGui import QColor

from .data_types import TestResult, ResultStatus

# Column indices — wiring diagram order: Source side → Status → Destination side.
COL_NUM               = 0
COL_SOURCE            = 1
COL_PART_NUMBER       = 2
COL_CONN_ID           = 3
COL_PIN_A_NAME        = 4
COL_PIN_A             = 5
COL_STATUS            = 6
COL_PIN_B             = 7
COL_PIN_B_NAME        = 8
COL_CONN_ID_B         = 9
COL_PART_NUMBER_B     = 10
COL_DEST              = 11
COL_COLOUR            = 12
COL_AWG               = 13
COL_LENGTH            = 14
COL_HARNESS_NO        = 15

# Source side reads outward-to-inward (Source, Part Number, Conn ID, pin) and
# the destination side mirrors it inward-to-outward, so the two connectors are
# laid out symmetrically about the Status column.  The wire details from the
# netlist follow the Destination.
HEADERS = [
    "Test #", "Source", "Part Number", "Conn ID",
    "Src Pin Label", "Src Pin #",
    "Status",
    "Dst Pin #", "Dst Pin Label",
    "Conn ID", "Part Number", "Destination",
    "Colour", "AWG", "Length", "Harness No",
]

# Dark theme row colors
_DARK_PASS = QColor(40, 80, 40)
_DARK_FAIL = QColor(80, 30, 30)

# Light theme row colors
_LIGHT_PASS = QColor(0xCC, 0xFF, 0xCC)
_LIGHT_FAIL = QColor(0xFF, 0xCC, 0xCC)

_STATUS_LABELS = {
    ResultStatus.PASS:          "CONNECTED",
    ResultStatus.FAIL:          "NOT CONNECTED",
    ResultStatus.OPEN:          "NOT CONNECTED",
    ResultStatus.MISWIRE:       "NOT CONNECTED",
    ResultStatus.NOT_CONNECTED: "NOT CONNECTED",
}


class ResultModel(QAbstractTableModel):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._rows: list[TestResult] = []
        self._dark_theme = True
        self._cross_continuity = False

    def set_cross_continuity(self, enabled: bool) -> None:
        self._cross_continuity = enabled
        if self._rows:
            self.dataChanged.emit(
                self.index(0, 0),
                self.index(len(self._rows) - 1, self.columnCount() - 1),
                [Qt.ItemDataRole.DisplayRole],
            )

    def set_dark_theme(self, dark: bool) -> None:
        self._dark_theme = dark
        if self._rows:
            self.dataChanged.emit(
                self.index(0, 0),
                self.index(len(self._rows) - 1, self.columnCount() - 1),
                [Qt.ItemDataRole.BackgroundRole],
            )

    # ------------------------------------------------------------------
    # QAbstractTableModel interface
    # ------------------------------------------------------------------

    def rowCount(self, parent=QModelIndex()) -> int:
        return len(self._rows)

    def columnCount(self, parent=QModelIndex()) -> int:
        return len(HEADERS)

    def headerData(self, section: int, orientation, role=Qt.ItemDataRole.DisplayRole):
        if role == Qt.ItemDataRole.DisplayRole and orientation == Qt.Orientation.Horizontal:
            return HEADERS[section]
        return None

    def data(self, index: QModelIndex, role=Qt.ItemDataRole.DisplayRole):
        if not index.isValid() or index.row() >= len(self._rows):
            return None
        row = self._rows[index.row()]
        col = index.column()

        if role == Qt.ItemDataRole.DisplayRole:
            return self._display(row, col)

        if role == Qt.ItemDataRole.TextAlignmentRole:
            return self._alignment(col)

        if role == Qt.ItemDataRole.BackgroundRole:
            return self._background(row)

        if role == Qt.ItemDataRole.ForegroundRole and col == COL_STATUS:
            return self._status_color(row.status)

        return None

    def sort(self, column: int, order=Qt.SortOrder.AscendingOrder) -> None:
        reverse = order == Qt.SortOrder.DescendingOrder

        if self._cross_continuity:
            # Order: source connector, source pin, dest connector, dest pin, test num
            def key(r: TestResult):
                return (
                    r.connector_id.lower(),
                    r.display_pin_a or r.pin_a,
                    r.connector_id_b.lower(),
                    r.display_pin_b or r.pin_b,
                    r.test_num,
                )
            self.layoutAboutToBeChanged.emit()
            self._rows.sort(key=key, reverse=reverse)
            self.layoutChanged.emit()
            return

        key = {
            COL_NUM:        lambda r: r.test_num,
            COL_SOURCE:     lambda r: r.source.lower(),
            COL_CONN_ID:    lambda r: r.connector_id.lower(),
            COL_PIN_A_NAME: lambda r: r.pin_a_name.lower(),
            COL_PIN_A:      lambda r: r.pin_a,
            COL_STATUS:     lambda r: int(r.status),
            COL_PIN_B:      lambda r: r.pin_b,
            COL_PIN_B_NAME: lambda r: r.pin_b_name.lower(),
            COL_CONN_ID_B:  lambda r: r.connector_id_b.lower(),
            COL_DEST:       lambda r: r.destination.lower(),
            COL_COLOUR:     lambda r: r.wire_colour.lower(),
            COL_AWG:        lambda r: r.awg.lower(),
            COL_LENGTH:     lambda r: r.length.lower(),
            COL_HARNESS_NO: lambda r: r.harness_no.lower(),
        }.get(column)
        if key:
            self.layoutAboutToBeChanged.emit()
            self._rows.sort(key=key, reverse=reverse)
            self.layoutChanged.emit()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def append_result(self, result: TestResult) -> None:
        row = len(self._rows)
        self.beginInsertRows(QModelIndex(), row, row)
        self._rows.append(result)
        self.endInsertRows()

    def clear(self) -> None:
        self.beginResetModel()
        self._rows.clear()
        self.endResetModel()

    def all_results(self) -> list[TestResult]:
        return list(self._rows)

    def set_test_num(self, row: int, test_num: int) -> None:
        """Update the displayed test number for a specific source row."""
        if 0 <= row < len(self._rows):
            self._rows[row].test_num = test_num
            self.dataChanged.emit(
                self.index(row, COL_NUM),
                self.index(row, COL_NUM),
                [Qt.ItemDataRole.DisplayRole],
            )

    def summary(self) -> dict[str, int]:
        counts: dict[str, int] = {"total": 0, "connected": 0, "not_connected": 0}
        for r in self._rows:
            counts["total"] += 1
            if r.status == ResultStatus.PASS:
                counts["connected"] += 1
            else:
                counts["not_connected"] += 1
        return counts

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _display(self, row: TestResult, col: int):
        if col == COL_NUM:        return str(row.test_num)
        if col == COL_SOURCE:
            if self._cross_continuity:
                return self._verbose_source(row)
            return row.source
        if col == COL_CONN_ID:    return row.connector_id
        if col == COL_PART_NUMBER: return row.connector_part_number
        if col == COL_PIN_A_NAME: return row.pin_a_name or f"Pin {row.display_pin_a or row.pin_a}"
        if col == COL_PIN_A:      return str(row.display_pin_a or row.pin_a)
        if col == COL_STATUS:     return _STATUS_LABELS.get(row.status, "")
        if col == COL_PIN_B:      return str(row.display_pin_b or row.pin_b)
        if col == COL_PIN_B_NAME: return row.pin_b_name or f"Pin {row.display_pin_b or row.pin_b}"
        if col == COL_CONN_ID_B:  return row.connector_id_b
        if col == COL_PART_NUMBER_B: return row.connector_part_number_b
        if col == COL_DEST:
            if self._cross_continuity:
                return self._verbose_destination(row)
            return row.destination
        if col == COL_COLOUR:     return row.wire_colour
        if col == COL_AWG:        return row.awg
        if col == COL_LENGTH:     return row.length
        if col == COL_HARNESS_NO: return row.harness_no
        return None

    @staticmethod
    def _verbose_source(row: TestResult) -> str:
        side = (row.source or "Side-A").replace("-", " ")
        conn = row.connector_id or ""
        pin = row.display_pin_a or row.pin_a
        return f"{side} of {conn} pin {pin}" if conn else f"{side} pin {pin}"

    @staticmethod
    def _verbose_destination(row: TestResult) -> str:
        side = (row.destination or "Side-B").replace("-", " ")
        conn = row.connector_id_b or ""
        pin = row.display_pin_b or row.pin_b
        return f"{side} of {conn} pin {pin}" if conn else f"{side} pin {pin}"

    @staticmethod
    def _alignment(col: int):
        center = Qt.AlignmentFlag.AlignCenter
        left   = Qt.AlignmentFlag.AlignLeft  | Qt.AlignmentFlag.AlignVCenter
        align_map = {
            COL_NUM: center, COL_PIN_A: center, COL_PIN_B: center,
            COL_CONN_ID: center, COL_CONN_ID_B: center, COL_STATUS: center,
            COL_PART_NUMBER: center, COL_PART_NUMBER_B: center,
            COL_AWG: center, COL_LENGTH: center, COL_HARNESS_NO: center,
        }
        return align_map.get(col, left)

    def _background(self, row: TestResult) -> QColor | None:
        is_pass = row.status == ResultStatus.PASS
        is_fail = row.status in (ResultStatus.FAIL, ResultStatus.OPEN, ResultStatus.MISWIRE)
        if self._dark_theme:
            if is_pass: return _DARK_PASS
            if is_fail: return _DARK_FAIL
        else:
            if is_pass: return _LIGHT_PASS
            if is_fail: return _LIGHT_FAIL
        return None

    @staticmethod
    def _status_color(status: ResultStatus) -> QColor:
        if status == ResultStatus.PASS:
            return QColor("#A6E3A1")
        return QColor("#F38BA8")
