"""LogPanel — read-only monospace log with colour-coded levels."""

from __future__ import annotations
import os
from datetime import datetime

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFont, QTextCharFormat, QColor, QTextCursor
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QPlainTextEdit,
    QPushButton, QSpinBox, QLabel, QFileDialog, QToolBar,
)

_LEVEL_COLORS: dict[str, str] = {
    "INFO":  "",          # default foreground
    "WARN":  "#FFA500",
    "ERROR": "#FF4444",
    "FAULT": "#FF4444",
    "TX":    "#6699FF",
    "RX":    "#66CC66",
    "DEBUG": "#888888",
}

DEFAULT_MAX_LINES = 10_000


class LogPanel(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._max_lines = DEFAULT_MAX_LINES
        self._auto_scroll = True
        self._build_ui()

    # ------------------------------------------------------------------
    # UI
    # ------------------------------------------------------------------

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(2)

        # Toolbar
        toolbar = QHBoxLayout()
        toolbar.setContentsMargins(4, 2, 4, 2)

        btn_clear = QPushButton("Clear Log")
        btn_clear.clicked.connect(self.clear)
        btn_save  = QPushButton("Save Log…")
        btn_save.clicked.connect(self._save_log)

        lbl_max = QLabel("Max lines:")
        self._spin_max = QSpinBox()
        self._spin_max.setRange(100, 100_000)
        self._spin_max.setValue(DEFAULT_MAX_LINES)
        self._spin_max.setSingleStep(1000)
        self._spin_max.setToolTip("Maximum number of log lines retained")
        self._spin_max.setAccessibleName("Max log lines")
        self._spin_max.valueChanged.connect(self._on_max_changed)

        toolbar.addWidget(btn_clear)
        toolbar.addWidget(btn_save)
        toolbar.addStretch()
        toolbar.addWidget(lbl_max)
        toolbar.addWidget(self._spin_max)

        layout.addLayout(toolbar)

        # Log text
        self._text = QPlainTextEdit()
        self._text.setReadOnly(True)
        self._text.setLineWrapMode(QPlainTextEdit.LineWrapMode.NoWrap)
        font = QFont("Consolas")
        if not font.exactMatch():
            font = QFont("Courier New")
        font.setPointSize(9)
        self._text.setFont(font)
        self._text.setToolTip("Serial log output")
        self._text.setAccessibleName("Serial log")
        layout.addWidget(self._text)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def append_line(self, level: str, text: str) -> None:
        ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        line = f"[{ts}] [{level}] {text}"
        color_hex = _LEVEL_COLORS.get(level.upper(), "")

        cursor = self._text.textCursor()
        cursor.movePosition(QTextCursor.MoveOperation.End)

        fmt = QTextCharFormat()
        if color_hex:
            fmt.setForeground(QColor(color_hex))

        cursor.insertText(line + "\n", fmt)

        # Enforce max-lines limit
        doc = self._text.document()
        while doc.blockCount() > self._max_lines + 1:
            cursor2 = QTextCursor(doc.begin())
            cursor2.select(QTextCursor.SelectionType.BlockUnderCursor)
            cursor2.removeSelectedText()
            cursor2.deleteChar()   # remove the trailing newline

        if self._auto_scroll:
            self._text.ensureCursorVisible()

    def clear(self) -> None:
        self._text.clear()

    # ------------------------------------------------------------------
    # Slots / events
    # ------------------------------------------------------------------

    def _on_max_changed(self, value: int) -> None:
        self._max_lines = value

    def _save_log(self) -> None:
        path, _ = QFileDialog.getSaveFileName(
            self, "Save Log", "", "Text files (*.txt);;All files (*)"
        )
        if path:
            with open(path, "w", encoding="utf-8") as f:
                f.write(self._text.toPlainText())
