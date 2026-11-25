"""IconButton — compact square button that displays an SVG icon."""

from __future__ import annotations
import os

from PyQt6.QtCore import Qt, QSize
from PyQt6.QtGui import QIcon
from PyQt6.QtWidgets import QPushButton


class IconButton(QPushButton):
    """A small icon-only button for toolbars and compact actions."""

    def __init__(
        self,
        icon_name: str = "",
        tooltip: str = "",
        size: int = 28,
        parent=None,
    ):
        super().__init__(parent)
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self.setFixedSize(size, size)
        self.setToolTip(tooltip)
        self.setObjectName("iconButton")

        if icon_name:
            self._load_icon(icon_name)

        self.setStyleSheet(
            f"""
            IconButton {{
                background-color: transparent;
                border: 1px solid #2A2E42;
                border-radius: {size // 4}px;
                padding: 4px;
            }}
            IconButton:hover {{
                background-color: rgba(255,255,255,0.08);
                border-color: #3B82F6;
            }}
            IconButton:pressed {{
                background-color: rgba(255,255,255,0.14);
            }}
            IconButton:disabled {{
                background-color: transparent;
                border-color: #1E2130;
            }}
            """
        )

    def _load_icon(self, icon_name: str) -> None:
        base = os.path.join(os.path.dirname(__file__), "..", "..", "resources", "icons")
        path = os.path.join(base, icon_name)
        if not os.path.exists(path):
            # Try with .svg extension
            path = os.path.join(base, f"{icon_name}.svg")
        if os.path.exists(path):
            self.setIcon(QIcon(path))
            self.setIconSize(QSize(self.width() - 10, self.height() - 10))
