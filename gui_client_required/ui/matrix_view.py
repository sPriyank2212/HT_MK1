"""MatrixView — 16×16 grid of pin-pair result indicators.

Each cell (row r, col c) represents the test result for the connection between
connector-A pin (r+1) and connector-B pin (c+1).  256 cells total.
"""

from __future__ import annotations
from enum import IntEnum

from PyQt6.QtCore import Qt, QPoint, QRect, QTimer, pyqtSignal
from PyQt6.QtGui import QColor, QPainter, QPen, QBrush, QFont
from PyQt6.QtWidgets import QWidget, QToolTip, QSizePolicy

GRID_SIZE = 16          # 16×16
MIN_CIRCLE = 16         # px
MAX_CIRCLE = 48         # px
GAP = 4                 # px between circles
AXIS_MARGIN = 22        # px reserved for axis labels
LEGEND_H = 28           # px for legend bar at bottom


class PinState(IntEnum):
    UNTESTED    = 0
    IN_PROGRESS = 1
    PASS        = 2
    FAIL        = 3
    # HV_RESULT   = 4


_STATE_COLOR: dict[PinState, QColor] = {
    PinState.UNTESTED:    QColor("#808080"),
    PinState.IN_PROGRESS: QColor("#FFD700"),
    PinState.PASS:        QColor("#28A745"),
    PinState.FAIL:        QColor("#DC3545"),
    # PinState.HV_RESULT:   QColor("#0000FF"),
}

_STATE_LABEL = {
    PinState.UNTESTED:    "UNTESTED",
    PinState.IN_PROGRESS: "IN PROGRESS",
    PinState.PASS:        "CONNECTED",
    PinState.FAIL:        "NOT CONNECTED",
    # PinState.HV_RESULT:   "HV RESULT",
}

_LEGEND_ORDER = [
    PinState.UNTESTED,
    PinState.IN_PROGRESS,
    PinState.PASS,
    PinState.FAIL,
    # PinState.HV_RESULT,
]


class MatrixView(QWidget):
    pinClicked = pyqtSignal(int, int)   # (pin_a 1-16, pin_b 1-16)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._states: list[list[PinState]] = [
            [PinState.UNTESTED] * GRID_SIZE for _ in range(GRID_SIZE)
        ]
        self._dirty   = False
        self._dut_id  = ""
        self._progress = ""

        self.setMouseTracking(True)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        self.setMinimumSize(
            AXIS_MARGIN + GRID_SIZE * (MIN_CIRCLE + GAP),
            AXIS_MARGIN + GRID_SIZE * (MIN_CIRCLE + GAP) + LEGEND_H,
        )

        # 100 ms batch-repaint timer (GUI-MX-002)
        self._batch_timer = QTimer(self)
        self._batch_timer.setInterval(100)
        self._batch_timer.timeout.connect(self._flush)
        self._batch_timer.start()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def update_pin(self, pin_a: int, pin_b: int, state: PinState) -> None:
        """Mark a cell dirty — repaint is batched by the 100 ms timer (GUI-MX-002)."""
        r, c = pin_a - 1, pin_b - 1
        if 0 <= r < GRID_SIZE and 0 <= c < GRID_SIZE:
            self._states[r][c] = state
            self._dirty = True

    def _flush(self) -> None:
        if self._dirty:
            self._dirty = False
            self.update()

    def batch_update(self, updates: list[tuple[int, int, PinState]]) -> None:
        for pin_a, pin_b, state in updates:
            r, c = pin_a - 1, pin_b - 1
            if 0 <= r < GRID_SIZE and 0 <= c < GRID_SIZE:
                self._states[r][c] = state
        self._dirty = True

    def reset(self) -> None:
        self._states = [[PinState.UNTESTED] * GRID_SIZE for _ in range(GRID_SIZE)]
        self._dut_id = ""
        self._progress = ""
        self._dirty = True

    def set_header(self, dut_id: str, progress: str) -> None:
        self._dut_id = dut_id
        self._progress = progress
        self.update()

    # ------------------------------------------------------------------
    # Painting
    # ------------------------------------------------------------------

    def paintEvent(self, event) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        w = self.width()
        h = self.height() - LEGEND_H

        # Compute circle size to fit the available space
        avail_w = w - AXIS_MARGIN
        avail_h = h - AXIS_MARGIN
        cell = min(avail_w // GRID_SIZE, avail_h // GRID_SIZE)
        cell = max(MIN_CIRCLE + GAP, min(MAX_CIRCLE + GAP, cell))
        diameter = cell - GAP

        # Grid origin (top-left of first circle centre row)
        origin_x = AXIS_MARGIN + (avail_w - GRID_SIZE * cell) // 2
        origin_y = AXIS_MARGIN + (avail_h - GRID_SIZE * cell) // 2

        self._cell = cell
        self._diameter = diameter
        self._origin_x = origin_x
        self._origin_y = origin_y

        # Axis labels
        axis_font = QFont()
        axis_font.setPointSize(7)
        painter.setFont(axis_font)
        painter.setPen(QColor("#888888"))
        for i in range(GRID_SIZE):
            label = str(i + 1)
            cx = origin_x + i * cell + cell // 2
            cy = origin_y + i * cell + cell // 2
            # Column header (A-side)
            painter.drawText(QRect(cx - cell // 2, 2, cell, AXIS_MARGIN - 4),
                             Qt.AlignmentFlag.AlignCenter, label)
            # Row header (B-side)
            painter.drawText(QRect(2, cy - cell // 2, AXIS_MARGIN - 4, cell),
                             Qt.AlignmentFlag.AlignCenter, label)

        # Circles
        for r in range(GRID_SIZE):
            for c in range(GRID_SIZE):
                state = self._states[r][c]
                color = _STATE_COLOR[state]
                cx = origin_x + c * cell
                cy = origin_y + r * cell
                painter.setBrush(QBrush(color))
                if state == PinState.IN_PROGRESS:
                    painter.setPen(QPen(QColor("white"), 2))
                else:
                    painter.setPen(Qt.PenStyle.NoPen)
                painter.drawEllipse(cx, cy, diameter, diameter)

        # Legend
        self._draw_legend(painter, w, self.height())

    def _draw_legend(self, painter: QPainter, w: int, total_h: int) -> None:
        y = total_h - LEGEND_H + 4
        swatch = 12
        gap = 6
        font = QFont()
        font.setPointSize(7)
        painter.setFont(font)

        # Measure total legend width to centre it
        fm = painter.fontMetrics()
        items = [(s, _STATE_LABEL[s]) for s in _LEGEND_ORDER]
        total_w = sum(swatch + gap + fm.horizontalAdvance(lbl) + 14 for _, lbl in items)
        x = (w - total_w) // 2

        for state, lbl in items:
            color = _STATE_COLOR[state]
            painter.setBrush(QBrush(color))
            painter.setPen(Qt.PenStyle.NoPen)
            painter.drawEllipse(x, y + 1, swatch, swatch)
            painter.setPen(QColor("#CCCCCC"))
            painter.drawText(x + swatch + gap, y + swatch, lbl)
            x += swatch + gap + fm.horizontalAdvance(lbl) + 14

    # ------------------------------------------------------------------
    # Mouse events
    # ------------------------------------------------------------------

    def mouseMoveEvent(self, event) -> None:
        pin_a, pin_b = self._pin_at(event.pos())
        if pin_a is not None:
            state = self._states[pin_a - 1][pin_b - 1]
            tip = (
                f"A-Pin {pin_a}  ×  B-Pin {pin_b}\n"
                f"State: {_STATE_LABEL[state]}"
            )
            QToolTip.showText(event.globalPosition().toPoint(), tip, self)
        else:
            QToolTip.hideText()
        super().mouseMoveEvent(event)

    def mousePressEvent(self, event) -> None:
        if event.button() == Qt.MouseButton.LeftButton:
            pin_a, pin_b = self._pin_at(event.pos())
            if pin_a is not None:
                self.pinClicked.emit(pin_a, pin_b)
        super().mousePressEvent(event)

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _pin_at(self, pos: QPoint) -> tuple[int | None, int | None]:
        """Return (pin_a, pin_b) 1-indexed for the circle under pos, or (None, None)."""
        if not hasattr(self, "_cell"):
            return None, None
        x, y = pos.x() - self._origin_x, pos.y() - self._origin_y
        c = x // self._cell
        r = y // self._cell
        if 0 <= r < GRID_SIZE and 0 <= c < GRID_SIZE:
            # Check within the circle itself
            cx = c * self._cell + self._diameter / 2
            cy = r * self._cell + self._diameter / 2
            dx, dy = x - cx, y - cy
            if dx * dx + dy * dy <= (self._diameter / 2) ** 2:
                return r + 1, c + 1
        return None, None
