"""StatusBadge — coloured pill label for PASS / FAIL / WARN / INFO."""

from __future__ import annotations
from enum import Enum, auto

from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import QLabel, QSizePolicy


class BadgeType(Enum):
    PASS = auto()
    FAIL = auto()
    WARN = auto()
    INFO = auto()
    NEUTRAL = auto()


class StatusBadge(QLabel):
    """A rounded pill badge that shows a status word."""

    _PALETTE = {
        BadgeType.PASS:    ("#22C55E", "#FFFFFF"),
        BadgeType.FAIL:    ("#EF4444", "#FFFFFF"),
        BadgeType.WARN:    ("#F59E0B", "#1C1C1C"),
        BadgeType.INFO:    ("#38BDF8", "#0B0C15"),
        BadgeType.NEUTRAL: ("#475569", "#F1F5F9"),
    }

    def __init__(
        self,
        text: str = "",
        badge_type: BadgeType = BadgeType.NEUTRAL,
        parent: QWidget | None = None,
    ):
        super().__init__(text, parent)
        self._badge_type = badge_type
        self.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        self._update_style()

    def set_badge_type(self, badge_type: BadgeType) -> None:
        self._badge_type = badge_type
        self._update_style()

    def set_text(self, text: str) -> None:
        self.setText(text)

    def _update_style(self) -> None:
        bg, fg = self._PALETTE.get(self._badge_type, self._PALETTE[BadgeType.NEUTRAL])
        self.setStyleSheet(
            f"""
            StatusBadge {{
                background-color: {bg};
                color: {fg};
                border-radius: 10px;
                padding: 3px 10px;
                font-size: 9pt;
                font-weight: bold;
                min-width: 44px;
                max-width: 120px;
            }}
            """
        )
