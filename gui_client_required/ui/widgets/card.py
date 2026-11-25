"""Card — rounded panel container with optional title."""

from __future__ import annotations

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QColor, QPainter, QPaintEvent, QBrush, QPen
from PyQt6.QtWidgets import QWidget, QVBoxLayout, QLabel


class Card(QWidget):
    """A rounded rectangular card with a subtle border and optional header."""

    def __init__(
        self,
        title: str = "",
        parent: QWidget | None = None,
        radius: int = 10,
        bg_color: str = "#141621",
        border_color: str = "#2A2E42",
    ):
        super().__init__(parent)
        self._radius = radius
        self._bg_color = QColor(bg_color)
        self._border_color = QColor(border_color)
        self._title = title

        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(14, 14, 14, 14)
        self._layout.setSpacing(10)

        if title:
            self._title_label = QLabel(title.upper())
            self._title_label.setObjectName("cardTitle")
            self._title_label.setStyleSheet(
                "color: #94A3B8; font-size: 10px; font-weight: bold; letter-spacing: 1px;"
            )
            self._layout.addWidget(self._title_label, alignment=Qt.AlignmentFlag.AlignLeft)

    def layout(self) -> QVBoxLayout:
        return self._layout

    def paintEvent(self, event: QPaintEvent) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        rect = self.rect().adjusted(1, 1, -1, -1)

        # Background
        painter.setBrush(QBrush(self._bg_color))
        painter.setPen(Qt.PenStyle.NoPen)
        painter.drawRoundedRect(rect, self._radius, self._radius)

        # Border
        pen = QPen(self._border_color)
        pen.setWidth(1)
        painter.setPen(pen)
        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.drawRoundedRect(rect, self._radius, self._radius)

        painter.end()
