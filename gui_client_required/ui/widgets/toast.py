"""Toast — non-blocking slide-in notification widget."""

from __future__ import annotations

from PyQt6.QtCore import Qt, QTimer, QPropertyAnimation, QEasingCurve, pyqtProperty, QPoint
from PyQt6.QtGui import QColor, QPainter, QPaintEvent, QBrush, QPen, QFont
from PyQt6.QtWidgets import QWidget, QHBoxLayout, QLabel, QApplication


class Toast(QWidget):
    """A short-lived floating notification that slides in from the bottom."""

    _PALETTE = {
        "info":  ("#3B82F6", "#FFFFFF"),
        "success": ("#22C55E", "#FFFFFF"),
        "warning": ("#F59E0B", "#1C1C1C"),
        "error":   ("#EF4444", "#FFFFFF"),
    }

    def __init__(self, text: str, level: str = "info", duration_ms: int = 3000, parent=None):
        super().__init__(parent or QApplication.activeWindow())
        self.setWindowFlags(Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)

        bg, fg = self._PALETTE.get(level, self._PALETTE["info"])
        self._bg_color = QColor(bg)
        self._fg_color = QColor(fg)
        self._opacity = 0.0

        layout = QHBoxLayout(self)
        layout.setContentsMargins(16, 10, 16, 10)
        self._label = QLabel(text)
        self._label.setStyleSheet(f"color: {fg}; font-size: 10pt;")
        layout.addWidget(self._label)

        self.setMinimumWidth(240)
        self.adjustSize()

        self._fade_in = QPropertyAnimation(self, b"opacity")
        self._fade_in.setDuration(200)
        self._fade_in.setStartValue(0.0)
        self._fade_in.setEndValue(1.0)
        self._fade_in.setEasingCurve(QEasingCurve.Type.OutQuad)

        self._fade_out = QPropertyAnimation(self, b"opacity")
        self._fade_out.setDuration(250)
        self._fade_out.setStartValue(1.0)
        self._fade_out.setEndValue(0.0)
        self._fade_out.setEasingCurve(QEasingCurve.Type.InQuad)
        self._fade_out.finished.connect(self.close)

        QTimer.singleShot(duration_ms, self._fade_out.start)

    @pyqtProperty(float)
    def opacity(self) -> float:
        return self._opacity

    @opacity.setter
    def opacity(self, value: float) -> None:
        self._opacity = value
        self.update()

    def showEvent(self, event):
        self._fade_in.start()
        super().showEvent(event)

    def paintEvent(self, event: QPaintEvent) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.setOpacity(self._opacity)

        rect = self.rect().adjusted(1, 1, -1, -1)
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(QBrush(self._bg_color))
        painter.drawRoundedRect(rect, 10, 10)

        # Subtle border
        pen = QPen(QColor("#FFFFFF"))
        pen.setWidth(1)
        pen.setColor(QColor(255, 255, 255, 40))
        painter.setPen(pen)
        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.drawRoundedRect(rect, 10, 10)

        painter.end()
