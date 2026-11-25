"""ModernButton — styled button with role-based colors and hover animation."""

from __future__ import annotations
from enum import Enum, auto

from PyQt6.QtCore import Qt, QPropertyAnimation, QEasingCurve, pyqtProperty
from PyQt6.QtGui import QColor
from PyQt6.QtWidgets import QPushButton


class ButtonRole(Enum):
    PRIMARY = auto()
    DANGER = auto()
    GHOST = auto()
    SECONDARY = auto()


class ModernButton(QPushButton):
    """A QPushButton with a modern flat style and animated background."""

    _PALETTE = {
        ButtonRole.PRIMARY:   ("#22C55E", "#16A34A", "#15803D", "#FFFFFF"),
        ButtonRole.DANGER:    ("#EF4444", "#DC2626", "#B91C1C", "#FFFFFF"),
        ButtonRole.SECONDARY: ("#3B82F6", "#2563EB", "#1D4ED8", "#FFFFFF"),
        ButtonRole.GHOST:     ("transparent", "rgba(255,255,255,0.08)", "rgba(255,255,255,0.14)", "#F1F5F9"),
    }

    def __init__(
        self,
        text: str = "",
        role: ButtonRole = ButtonRole.GHOST,
        parent=None,
    ):
        super().__init__(text, parent)
        self._role = role
        self._normal, self._hover, self._pressed, self._fg = self._PALETTE[role]

        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self.setMinimumHeight(32)
        self.setObjectName("modernButton")

        # Animated background opacity for hover feedback
        self._hover_value = 0.0
        self._anim = QPropertyAnimation(self, b"hover_value")
        self._anim.setDuration(120)
        self._anim.setEasingCurve(QEasingCurve.Type.InOutQuad)

        self._update_style()

    @pyqtProperty(float)
    def hover_value(self) -> float:
        return self._hover_value

    @hover_value.setter
    def hover_value(self, value: float) -> None:
        self._hover_value = value
        self._update_style()

    def enterEvent(self, event):
        self._anim.stop()
        self._anim.setStartValue(self._hover_value)
        self._anim.setEndValue(1.0)
        self._anim.start()
        super().enterEvent(event)

    def leaveEvent(self, event):
        self._anim.stop()
        self._anim.setStartValue(self._hover_value)
        self._anim.setEndValue(0.0)
        self._anim.start()
        super().leaveEvent(event)

    def set_role(self, role: ButtonRole) -> None:
        self._role = role
        self._normal, self._hover, self._pressed, self._fg = self._PALETTE[role]
        self._update_style()

    def _update_style(self) -> None:
        normal = self._normal
        hover = self._hover
        pressed = self._pressed
        fg = self._fg
        border = "#3B82F6" if self._role == ButtonRole.GHOST else "transparent"

        self.setStyleSheet(
            f"""
            ModernButton {{
                background-color: {normal};
                color: {fg};
                border: 1px solid {border};
                border-radius: 8px;
                padding: 6px 14px;
                font-size: 9pt;
                font-weight: bold;
            }}
            ModernButton:hover {{
                background-color: {hover};
            }}
            ModernButton:pressed {{
                background-color: {pressed};
            }}
            ModernButton:disabled {{
                background-color: #2A2E42;
                color: #64748B;
                border-color: transparent;
            }}
            """
        )
