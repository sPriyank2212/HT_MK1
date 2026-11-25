"""ResultsTable — QTableView + filter toolbar + summary footer."""

from __future__ import annotations
import csv
import io
from dataclasses import replace

from PyQt6.QtCore import Qt, QSortFilterProxyModel, QModelIndex
from PyQt6.QtGui import QColor, QPainter, QBrush, QPen, QFont
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QTableView,
    QComboBox, QLineEdit, QPushButton, QLabel,
    QHeaderView, QMenu, QStyledItemDelegate, QStyleOptionViewItem,
    QApplication,
)

from core.result_model import (
    ResultModel,
    COL_NUM, COL_STATUS, COL_PIN_A, COL_PIN_A_NAME, COL_PIN_B, COL_PIN_B_NAME,
    COL_CONN_ID, COL_CONN_ID_B, COL_PART_NUMBER, COL_PART_NUMBER_B,
    COL_SOURCE, COL_DEST,
    HEADERS,
)
from core.data_types import TestResult

# Column proportional weights (used with ResizeMode.Stretch so all columns
# scale together), positional — must track HEADERS in core.result_model:
#   Test#, Source, PartNumber, ConnID, SrcLabel, SrcPin#,
#   Status, DstPin#, DstLabel, ConnID, PartNumber, Dest,
#   Colour, AWG, Length, HarnessNo
_COL_WIDTHS = [45, 90, 120, 75, 120, 65, 75, 65, 120, 75, 120, 90, 80, 50, 65, 80]

_STATUS_OPTS = ["All", "CONNECTED", "NOT CONNECTED"]


class _StatusDelegate(QStyledItemDelegate):
    """Draws the Status column as a coloured badge."""

    _BADGE_COLORS = {
        "CONNECTED":    QColor("#28A745"),
        "NOT CONNECTED": QColor("#DC3545"),
    }

    def paint(self, painter: QPainter, option: QStyleOptionViewItem, index: QModelIndex) -> None:
        text = index.data(Qt.ItemDataRole.DisplayRole) or ""
        color = self._BADGE_COLORS.get(text, QColor("#888888"))

        painter.save()
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        # Badge rect — centred, 80% wide, 70% tall
        rect = option.rect.adjusted(4, 3, -4, -3)

        # Background row colour from model
        bg = index.data(Qt.ItemDataRole.BackgroundRole)
        if bg:
            painter.fillRect(option.rect, bg)

        painter.setBrush(QBrush(color))
        painter.setPen(Qt.PenStyle.NoPen)
        painter.drawRoundedRect(rect, 4, 4)

        painter.setPen(QPen(QColor("white")))
        font = QFont()
        font.setPointSize(8)
        font.setBold(True)
        painter.setFont(font)
        painter.drawText(rect, Qt.AlignmentFlag.AlignCenter, text)
        painter.restore()


class _ResultsFilterProxy(QSortFilterProxyModel):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._status_filter = "All"
        self._cross_continuity = False
        self.setFilterCaseSensitivity(Qt.CaseSensitivity.CaseInsensitive)
        self.setFilterKeyColumn(-1)   # search all columns

    def set_status_filter(self, value: str) -> None:
        self._status_filter = value
        self.invalidateFilter()

    def set_cross_continuity(self, enabled: bool) -> None:
        self._cross_continuity = enabled

    def _composite_key(self, model, row: int, parent: QModelIndex):
        """Return a tuple for cross-continuity matrix ordering."""
        def _int(model, r, c):
            try:
                return int(model.data(model.index(r, c, parent)))
            except (ValueError, TypeError):
                return 0
        def _str(model, r, c):
            return str(model.data(model.index(r, c, parent)) or "")
        return (
            _str(model, row, COL_CONN_ID).lower(),
            _int(model, row, COL_PIN_A),
            _str(model, row, COL_CONN_ID_B).lower(),
            _int(model, row, COL_PIN_B),
            _int(model, row, COL_NUM),
        )

    def lessThan(self, left: QModelIndex, right: QModelIndex) -> bool:
        model = self.sourceModel()
        if self._cross_continuity:
            return self._composite_key(model, left.row(), left.parent()) < \
                   self._composite_key(model, right.row(), right.parent())

        if left.column() in (COL_NUM, COL_PIN_A, COL_PIN_B):
            try:
                return int(model.data(left)) < int(model.data(right))
            except (ValueError, TypeError):
                pass
        if left.column() == COL_CONN_ID:
            # Group by source connector, then preserve test order within group
            conn_left  = model.data(model.index(left.row(), COL_CONN_ID, left.parent())) or ""
            conn_right = model.data(model.index(right.row(), COL_CONN_ID, right.parent())) or ""
            if conn_left != conn_right:
                return conn_left < conn_right
            try:
                num_left  = int(model.data(model.index(left.row(), COL_NUM, left.parent())))
                num_right = int(model.data(model.index(right.row(), COL_NUM, right.parent())))
                return num_left < num_right
            except (ValueError, TypeError):
                pass
        return super().lessThan(left, right)

    def filterAcceptsRow(self, source_row: int, source_parent: QModelIndex) -> bool:
        model = self.sourceModel()

        if self._status_filter != "All":
            status_idx = model.index(source_row, COL_STATUS, source_parent)
            if model.data(status_idx) != self._status_filter:
                return False

        # Text search across pin names
        if self.filterRegularExpression().pattern():
            for col in (COL_PIN_A_NAME, COL_PIN_B_NAME):
                idx = model.index(source_row, col, source_parent)
                txt = model.data(idx) or ""
                if self.filterRegularExpression().match(txt).hasMatch():
                    return True
            return False

        return True


class ResultsTable(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._model  = ResultModel(self)
        self._proxy  = _ResultsFilterProxy(self)
        self._proxy.setSourceModel(self._model)
        self._auto_scroll = True
        self._build_ui()

    # ------------------------------------------------------------------
    # UI
    # ------------------------------------------------------------------

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(2)

        # Filter toolbar
        filter_bar = QHBoxLayout()
        filter_bar.setContentsMargins(4, 2, 4, 2)

        self._cb_status = QComboBox()
        self._cb_status.addItems(_STATUS_OPTS)
        self._cb_status.setToolTip("Filter by result status")
        self._cb_status.setAccessibleName("Status filter")
        self._cb_status.currentTextChanged.connect(self._proxy.set_status_filter)

        self._search = QLineEdit()
        self._search.setPlaceholderText("Search pin name or net…")
        self._search.setToolTip("Filter by pin name or net name")
        self._search.setAccessibleName("Search filter")
        self._search.textChanged.connect(self._proxy.setFilterFixedString)

        btn_clear = QPushButton("Clear Filters")
        btn_clear.setToolTip("Reset all filters")
        btn_clear.setAccessibleName("Clear filters button")
        btn_clear.clicked.connect(self._clear_filters)

        filter_bar.addWidget(QLabel("Status:"))
        filter_bar.addWidget(self._cb_status)
        filter_bar.addWidget(self._search, 1)
        filter_bar.addWidget(btn_clear)
        layout.addLayout(filter_bar)

        # Table
        self._table = QTableView()
        self._table.setModel(self._proxy)
        self._table.setSortingEnabled(True)
        self._table.sortByColumn(COL_CONN_ID, Qt.SortOrder.AscendingOrder)
        self._table.setAlternatingRowColors(False)
        self._table.setSelectionBehavior(QTableView.SelectionBehavior.SelectRows)
        self._table.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self._table.customContextMenuRequested.connect(self._show_context_menu)
        self._table.setItemDelegateForColumn(COL_STATUS, _StatusDelegate(self))

        hdr = self._table.horizontalHeader()
        hdr.setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        hdr.setStretchLastSection(False)
        for i, w in enumerate(_COL_WIDTHS):
            self._table.setColumnWidth(i, w)
        hdr.setSectionsClickable(True)

        self._table.verticalHeader().setVisible(False)
        self._table.setShowGrid(False)
        self._table.setWordWrap(False)

        # Detect manual scroll to disable auto-scroll
        self._table.verticalScrollBar().valueChanged.connect(self._on_scroll)

        layout.addWidget(self._table, 1)

        # Summary footer
        self._summary_label = QLabel("Total: 0 | CONNECTED: 0 | NOT CONNECTED: 0")
        self._summary_label.setContentsMargins(4, 2, 4, 2)
        layout.addWidget(self._summary_label)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    @property
    def model(self) -> ResultModel:
        return self._model

    @property
    def is_cross_continuity(self) -> bool:
        return self._model._cross_continuity

    def set_cross_continuity(self, enabled: bool) -> None:
        """Switch result display to cross-continuity matrix order and verbose labels."""
        self._model.set_cross_continuity(enabled)
        self._proxy.set_cross_continuity(enabled)
        if enabled:
            # Hide redundant pin/connector columns; Source & Destination are verbose
            for col in (COL_CONN_ID, COL_PART_NUMBER, COL_PIN_A_NAME, COL_PIN_A,
                        COL_PIN_B, COL_PIN_B_NAME, COL_CONN_ID_B, COL_PART_NUMBER_B):
                self._table.setColumnHidden(col, True)
            self._table.sortByColumn(COL_SOURCE, Qt.SortOrder.AscendingOrder)
        else:
            for col in range(self._model.columnCount()):
                self._table.setColumnHidden(col, False)
            self._table.sortByColumn(COL_CONN_ID, Qt.SortOrder.AscendingOrder)

    def sort_cross_continuity(self) -> None:
        """Apply cross-continuity matrix ordering if enabled."""
        if self._model._cross_continuity:
            self._table.sortByColumn(COL_SOURCE, Qt.SortOrder.AscendingOrder)

    def renumber_cross_continuity(self) -> None:
        """Reassign Test # so it matches the sorted matrix order (1..N)."""
        if not self._model._cross_continuity:
            return
        for proxy_row in range(self._proxy.rowCount()):
            source_idx = self._proxy.mapToSource(self._proxy.index(proxy_row, 0))
            self._model.set_test_num(source_idx.row(), proxy_row + 1)

    def display_ordered_results(self) -> list[TestResult]:
        """Return results in the current display order with sequential Test #.

        Use this for CSV/PDF export so reports match the on-screen table.
        """
        rows: list[TestResult] = []
        for proxy_row in range(self._proxy.rowCount()):
            source_idx = self._proxy.mapToSource(self._proxy.index(proxy_row, 0))
            row = self._model._rows[source_idx.row()]
            rows.append(replace(row, test_num=proxy_row + 1))
        return rows

    def append_result(self, result) -> None:
        self._model.append_result(result)
        self._update_summary()
        if self._auto_scroll:
            self._table.scrollToBottom()

    def clear(self) -> None:
        self._model.clear()
        self._update_summary()

    def set_dark_theme(self, dark: bool) -> None:
        self._model.set_dark_theme(dark)

    # ------------------------------------------------------------------
    # Slots
    # ------------------------------------------------------------------

    def _clear_filters(self) -> None:
        self._cb_status.setCurrentIndex(0)
        self._search.clear()

    def _on_scroll(self, value: int) -> None:
        sb = self._table.verticalScrollBar()
        self._auto_scroll = (value == sb.maximum())

    def _show_context_menu(self, pos) -> None:
        menu = QMenu(self)
        copy_action   = menu.addAction("Copy to Clipboard as CSV")
        export_action = menu.addAction("Export Selected as PDF")
        detail_action = menu.addAction("Show Pin Detail")
        action = menu.exec(self._table.viewport().mapToGlobal(pos))
        if action == copy_action:
            self._copy_selection_as_csv()

    def _copy_selection_as_csv(self) -> None:
        rows = sorted({idx.row() for idx in self._table.selectedIndexes()})
        if not rows:
            return
        # Build a header list that matches the visible columns only.
        visible_cols = [c for c in range(self._proxy.columnCount())
                        if not self._table.isColumnHidden(c)]
        buf = io.StringIO()
        writer = csv.writer(buf)
        writer.writerow([HEADERS[c] for c in visible_cols])
        for proxy_row in rows:
            row_data = [
                self._proxy.data(self._proxy.index(proxy_row, col))
                for col in visible_cols
            ]
            writer.writerow(row_data)
        QApplication.clipboard().setText(buf.getvalue())

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _update_summary(self) -> None:
        s = self._model.summary()
        self._summary_label.setText(
            f"Total: {s['total']} | CONNECTED: {s['connected']} | "
            f"NOT CONNECTED: {s['not_connected']}"
        )
