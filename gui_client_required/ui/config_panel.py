"""ConfigPanel — the Configuration tab: connector pin <-> tester channel map.

Edits the same per-channel table as connector_config.xlsx (see core.pinmap)
directly in the GUI.  The table is kept in the app's own copy of the sheet
(paths.active_connector_config), so everything that reads the config by path
keeps working; Import / Export move it to and from any other xlsx.

Edits are saved shortly after the last change and configChanged is emitted,
so the netlist and wiring diagram pick them up without a restart.  An invalid
table is still saved (so no typing is lost) — MainWindow then blocks Start
until it is fixed, exactly as for a bad xlsx.
"""

from __future__ import annotations

import os

from PyQt6.QtCore import Qt, QTimer, pyqtSignal
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QPushButton,
    QTableWidget, QTableWidgetItem, QHeaderView, QFileDialog, QMessageBox,
    QAbstractItemView,
)

from core import paths
from core.pinmap import Channel, load_pinmap, read_rows, write_pinmap_xlsx

HEADERS = ["Channel", "Src Conn ID", "Dst Conn ID", "Connector Name",
           "Src Pin", "Dest Pin"]


class ConfigPanel(QWidget):
    configChanged = pyqtSignal(str)   # path of the saved config

    def __init__(self, parent=None):
        super().__init__(parent)
        self._path = paths.active_connector_config()

        self._save_timer = QTimer(self)
        self._save_timer.setSingleShot(True)
        self._save_timer.setInterval(800)
        self._save_timer.timeout.connect(self._save)

        lay = QVBoxLayout(self)
        lay.setContentsMargins(6, 6, 6, 6)
        lay.setSpacing(6)

        intro = QLabel(
            "Connector configuration — which connector pin each tester channel is "
            "wired to. Netlists use channel numbers; this table turns a channel into "
            "e.g. 'J2 pin 3' on screen and in reports. Dst Conn ID is optional: "
            "the name of the same connector at the Side-B (destination) end, e.g. X2. "
            "Dest Pin is optional too: fill it in when Side B has its own connectors "
            "and pin numbers (e.g. a DB37 facing X1, X2 and X3); netlists are then "
            "written in connector pins, and a channel's Side-A and Side-B pins may "
            "each be left blank (both fields) if they have no pigtail. Edit the cells directly, "
            "or import an existing connector_config.xlsx. Changes apply automatically."
        )
        intro.setWordWrap(True)
        intro.setStyleSheet("color:#888;")
        lay.addWidget(intro)

        bar = QHBoxLayout()
        buttons = (
            ("Add Row",       "Add a channel at the end of the table", self._add_row),
            ("Remove Row(s)", "Remove the selected channel rows",      self._remove_rows),
            ("Import xlsx…",  "Replace the table with a connector_config.xlsx", self._import),
            ("Export xlsx…",  "Save the table to an xlsx file",        self._export),
            ("Reset to Default", "Replace the table with the built-in configuration",
             self._reset_default),
        )
        for text, tip, slot in buttons:
            btn = QPushButton(text)
            btn.setToolTip(tip)
            btn.clicked.connect(slot)
            bar.addWidget(btn)
        bar.addStretch()
        lay.addLayout(bar)

        self._table = QTableWidget(0, len(HEADERS))
        self._table.setHorizontalHeaderLabels(HEADERS)
        self._table.verticalHeader().setVisible(False)
        self._table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self._table.horizontalHeader().setSectionResizeMode(
            QHeaderView.ResizeMode.Stretch)
        self._table.itemChanged.connect(self._on_item_changed)
        lay.addWidget(self._table, 1)

        self._lbl_status = QLabel("")
        self._lbl_status.setWordWrap(True)
        self._lbl_status.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        lay.addWidget(self._lbl_status)

        self._load_rows(self._read(self._path))
        self._update_status()

    # ── Public API ────────────────────────────────────────────────────────────

    def config_path(self) -> str:
        return self._path

    def flush(self) -> None:
        """Save now if an edit is still waiting on the save timer."""
        if self._save_timer.isActive():
            self._save_timer.stop()
            self._save()

    # ── Table <-> file ────────────────────────────────────────────────────────

    @staticmethod
    def _read(path: str) -> list[list[str]]:
        """Rows from either sheet format; the legacy Start/End pin range sheet
        is expanded to one row per channel."""
        if not path or not os.path.exists(path):
            return []
        from core.netlist import _config_is_pinmap, channel_table
        if _config_is_pinmap(path):
            return read_rows(path)
        return [[str(ch), t["connector_id"], "", t["connector_name"], str(t["conn_pin"]), ""]
                for ch, t in sorted(channel_table(path).items())]

    def _load_rows(self, rows: list[list[str]]) -> None:
        self._table.blockSignals(True)
        self._table.setRowCount(0)
        for values in rows:
            self._append(values)
        self._table.blockSignals(False)

    def _append(self, values: list[str]) -> None:
        r = self._table.rowCount()
        self._table.insertRow(r)
        for c in range(len(HEADERS)):
            text = values[c] if c < len(values) else ""
            self._table.setItem(r, c, QTableWidgetItem(text))

    def _channels(self) -> list[Channel]:
        def cell(r, c):
            item = self._table.item(r, c)
            text = item.text().strip() if item else ""
            return int(text) if text.isdigit() else text

        out = []
        for r in range(self._table.rowCount()):
            vals = [cell(r, c) for c in range(len(HEADERS))]
            if all(v == "" for v in vals):
                continue
            out.append(Channel(vals[0], str(vals[1]), str(vals[3]), vals[4],
                               connector_id_b=str(vals[2]),
                               dest_pin=vals[5] if vals[5] != "" else None))
        return out

    def _save(self) -> None:
        try:
            write_pinmap_xlsx(self._path, self._channels())
        except OSError as exc:
            self._lbl_status.setText(f"⚠ Could not save configuration: {exc}")
            self._lbl_status.setStyleSheet("color:#F38BA8;")
            return
        self._update_status()
        self.configChanged.emit(self._path)

    def _update_status(self) -> None:
        try:
            pm = load_pinmap(self._path)
        except Exception as exc:
            self._lbl_status.setText(
                "⚠ Configuration has errors — Start is blocked until they are fixed:\n"
                + str(exc))
            self._lbl_status.setStyleSheet("color:#F38BA8;")
            return
        self._lbl_status.setText(
            f"✓ {len(pm.channels)} channels — {pm.summary()}   (saved to {self._path})")
        self._lbl_status.setStyleSheet("color:#28a745;")

    # ── Slots ─────────────────────────────────────────────────────────────────

    def _on_item_changed(self, _item) -> None:
        self._save_timer.start()

    def _add_row(self) -> None:
        # Next free channel number, as a convenience.
        used = [c.number for c in self._channels() if isinstance(c.number, int)]
        self._table.blockSignals(True)
        self._append([str(max(used, default=0) + 1), "", "", "", "", ""])
        self._table.blockSignals(False)
        self._table.scrollToBottom()
        self._table.editItem(self._table.item(self._table.rowCount() - 1, 1))
        self._save_timer.start()

    def _remove_rows(self) -> None:
        rows = sorted({i.row() for i in self._table.selectedIndexes()}, reverse=True)
        if not rows:
            return
        for r in rows:
            self._table.removeRow(r)
        self._save_timer.start()

    def _import(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self, "Import Connector Configuration", "",
            "Excel files (*.xlsx);;All files (*)")
        if not path:
            return
        try:
            rows = self._read(path)
        except Exception as exc:
            QMessageBox.critical(self, "Import Failed", f"Could not read {path}:\n{exc}")
            return
        self._load_rows(rows)
        self._save()

    def _export(self) -> None:
        self.flush()
        path, _ = QFileDialog.getSaveFileName(
            self, "Export Connector Configuration", "connector_config.xlsx",
            "Excel files (*.xlsx)")
        if not path:
            return
        if not path.lower().endswith(".xlsx"):
            path += ".xlsx"
        try:
            write_pinmap_xlsx(path, self._channels())
        except OSError as exc:
            QMessageBox.critical(self, "Export Failed", str(exc))

    def _reset_default(self) -> None:
        reply = QMessageBox.question(
            self, "Reset Configuration",
            "Replace the whole table with the built-in connector configuration?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        if reply != QMessageBox.StandardButton.Yes:
            return
        self._load_rows(self._read(paths.default_connector_config()))
        self._save()
