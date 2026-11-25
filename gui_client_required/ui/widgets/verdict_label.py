"""VerdictLabel — large, animated PASS/FAIL indicator."""

from __future__ import annotations

from PyQt6.QtCore import Qt, QPropertyAnimation, QEasingCurve, pyqtProperty
from PyQt6.QtGui import QColor, QPainter, QPaintEvent, QBrush, QPen, QFont
from PyQt6.QtWidgets import QWidget


class VerdictLabel(QWidget):
    """A large verdict badge with background color animation."""

    _PALETTE = {
        "PASS":         ("#22C55E", "#14532D"),
        "FAIL":         ("#EF4444", "#7F1D1D"),
        "INCONCLUSIVE": ("#F59E0B", "#78350F"),
        "FAULT":        ("#F59E0B", "#78350F"),
        "":             ("#475569", "#1E293B"),
    }

    def __init__(self, parent=None):
        super().__init__(parent)
        self._verdict = ""
        self._fg_color = QColor("#F1F5F9")
        self._bg_color = QColor("#475569")
        self._glow_color = QColor("#475569")
        self._glow_alpha = 0.0

        self.setMinimumHeight(64)
        self.setMaximumHeight(90)
        self.setMinimumWidth(160)

        self._anim_color = QPropertyAnimation(self, b"glow_alpha")
        self._anim_color.setDuration(400)
        self._anim_color.setEasingCurve(QEasingCurve.Type.InOutQuad)

    def set_verdict(self, verdict: str | None) -> None:
        verdict = (verdict or "").upper()
        if verdict not in self._PALETTE:
            verdict = ""
        self._verdict = verdict
        fg, bg = self._PALETTE[verdict]
        self._fg_color = QColor(fg)
        self._bg_color = QColor(bg)
        self._glow_color = QColor(fg)

        self._anim_color.stop()
        self._anim_color.setStartValue(0.0)
        self._anim_color.setEndValue(0.45)
        self._anim_color.setKeyValueAt(0.5, 0.6)
        self._anim_color.start()
        self.update()

    @pyqtProperty(float)
    def glow_alpha(self) -> float:
        return self._glow_alpha

    @glow_alpha.setter
    def glow_alpha(self, value: float) -> None:
        self._glow_alpha = value
        self.update()

    def paintEvent(self, event: QPaintEvent) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        rect = self.rect().adjusted(2, 2, -2, -2)
        radius = 12

        # Glow
        if self._glow_alpha > 0:
            glow_rect = rect.adjusted(-6, -6, 6, 6)
            glow_color = QColor(self._glow_color)
            glow_color.setAlphaF(self._glow_alpha)
            pen = QPen(glow_color)
            pen.setWidth(8)
            painter.setPen(pen)
            painter.setBrush(Qt.BrushStyle.NoBrush)
            painter.drawRoundedRect(glow_rect, radius + 4, radius + 4)

        # Background
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(QBrush(self._bg_color))
        painter.drawRoundedRect(rect, radius, radius)

        # Text
        painter.setPen(QPen(self._fg_color))
        font = QFont()
        font.setPointSize(22)
        font.setBold(True)
        painter.setFont(font)
        text = self._verdict if self._verdict else "—"
        painter.drawText(rect, Qt.AlignmentFlag.AlignCenter, text)

        painter.end()
