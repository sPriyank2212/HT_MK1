"""GaugeProgress — modern rounded progress bar with percentage text."""

from __future__ import annotations

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QColor, QPainter, QPaintEvent, QBrush, QPen, QFont
from PyQt6.QtWidgets import QWidget


class GaugeProgress(QWidget):
    """A custom progress gauge with rounded ends and a text label."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._value = 0
        self._maximum = 100
        self._text = "0%"
        self.setMinimumHeight(24)
        self.setMaximumHeight(28)
        self.setMinimumWidth(160)

    def setValue(self, value: int) -> None:
        self._value = max(0, min(value, self._maximum))
        self._text = f"{self._value}%"
        self.update()

    def setMaximum(self, maximum: int) -> None:
        self._maximum = max(1, maximum)
        self.update()

    def setFormat(self, text: str) -> None:
        self._text = text
        self.update()

    def value(self) -> int:
        return self._value

    def paintEvent(self, event: QPaintEvent) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        rect = self.rect().adjusted(1, 1, -1, -1)
        radius = rect.height() // 2

        # Track
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(QBrush(QColor("#1E2130")))
        painter.drawRoundedRect(rect, radius, radius)

        # Border
        pen = QPen(QColor("#2A2E42"))
        pen.setWidth(1)
        painter.setPen(pen)
        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.drawRoundedRect(rect, radius, radius)

        # Fill
        if self._maximum > 0:
            ratio = self._value / self._maximum
            fill_width = max(radius * 2, int(rect.width() * ratio))
            fill_rect = rect.adjusted(0, 0, -(rect.width() - fill_width), 0)
            painter.setPen(Qt.PenStyle.NoPen)
            gradient = QColor("#3B82F6")
            painter.setBrush(QBrush(gradient))
            painter.drawRoundedRect(fill_rect, radius, radius)

        # Text
        painter.setPen(QColor("#F1F5F9"))
        font = QFont()
        font.setPointSize(8)
        font.setBold(True)
        painter.setFont(font)
        painter.drawText(rect, Qt.AlignmentFlag.AlignCenter, self._text)

        painter.end()
