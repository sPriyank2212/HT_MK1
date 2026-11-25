"""ConnectorView — DB-style wiring diagram visualization.

One section per connector (e.g. J1, J2, J3), stacked in a single
scroll area.  Each section has its own Side A and Side B connector bodies:

  ╔═══════════╗                              ╔═══════════╗
  ║  SIDE A   ║                              ║  SIDE B   ║
  ╠═══════════╣  ─── NET: GROUND ─────────  ╠═══════════╣
  ║ 1  GND  ● ╠══════════════════════════════╣ ●  15  GND_RTN ║  PASS
  ║ 2  CAN_H● ╠═══════(red, FAIL)════════════╣ ●   3  CAN_L   ║  FAIL
  ╚═══════════╝                              ╚═══════════╝

Side A pins are listed in ascending order.
Side B pins are aligned to their Side A partner (reordered by connection).
Lines are coloured by test result.
"""

from __future__ import annotations
from dataclasses import dataclass, field
from itertools import groupby

from PyQt6.QtCore import Qt, QRect, QRectF, QPoint, QTimer, QSize, QEvent
from PyQt6.QtGui import (
    QColor, QPainter, QPen, QBrush, QFont, QPainterPath,
)
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QScrollArea,
    QSizePolicy, QStackedWidget, QPushButton, QButtonGroup, QToolTip,
)

from ui.matrix_view import PinState, _STATE_COLOR, _STATE_LABEL

# ── Layout constants ──────────────────────────────────────────────────────────
CONN_W     = 190    # width of each connector body panel
PIN_R      = 8      # pin circle radius
ROW_H      = 26     # height of each connection row
NET_HDR_H  = 20     # height of net name separator bar
V_PAD      = 14     # top / bottom padding inside canvas
MIN_W      = 750    # minimum canvas width

# Colours
_C_BODY_BG    = QColor("#0F0F1E")
_C_BODY_BORD  = QColor("#4444AA")
_C_TITLE_BG   = QColor("#1A1A3A")
_C_TITLE_FG   = QColor("#8888CC")
_C_PART_FG    = QColor("#6A6A99")
_C_NET_BG     = QColor("#1C1C35")
_C_NET_FG     = QColor("#7777BB")
_C_LABEL_FG   = QColor("#BBBBBB")

# Priority used to decide which state "wins" when a pin gets multiple results
_PRIORITY: dict[PinState, int] = {
    PinState.UNTESTED: 0, PinState.IN_PROGRESS: 1,
    PinState.PASS: 2,    # PinState.HV_RESULT: 3,
    PinState.FAIL: 3,
}


# ── Data types ────────────────────────────────────────────────────────────────

@dataclass
class _Net:
    name: str
    colour: str = ""     # wire colour from the netlist, named on the header


@dataclass
class _Row:
    pin_a: int
    pin_b: int
    net: str
    name_a: str = ""
    name_b: str = ""
    display_pin_a: int = 0
    display_pin_b: int = 0


@dataclass
class _YNet:
    """A net whose single source pin fans out to two or more destinations.

    Drawn as one trunk from the source to a junction node, then a branch to
    each destination — an actual Y split rather than N unrelated straight
    lines.  branches holds (pin_b, name_b, display_pin_b).
    """
    net: str
    pin_a: int
    name_a: str = ""
    display_pin_a: int = 0
    branches: list[tuple[int, str, int]] = field(default_factory=list)


@dataclass
class _Gap:
    """Visual spacer between connector groups."""
    pass


# ── WiringCanvas ─────────────────────────────────────────────────────────────

class _TipCanvas(QWidget):
    """Canvas that shows a hover tooltip over regions recorded while painting.

    Pin labels show the pin number on its own connector; the tester channel
    behind it is only in this tooltip, e.g. "J2  Side-A — pin 3 (channel 18)".
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        self._tips: list[tuple[QRect, str]] = []

    def _add_pin_tip(self, rect: QRect, connector: str, disp: int, channel: int) -> None:
        self._tips.append((rect, f"{connector} — pin {disp}  (channel {channel})"))

    def event(self, e) -> bool:  # noqa: N802
        if e.type() == QEvent.Type.ToolTip:
            pos = e.pos()
            text = next((t for r, t in self._tips if r.contains(pos)), "")
            if text:
                QToolTip.showText(e.globalPos(), text, self)
            else:
                QToolTip.hideText()
                e.ignore()
            return True
        return super().event(e)


class WiringCanvas(_TipCanvas):
    """Custom-painted scrollable canvas — one section (cont or HV)."""

    def __init__(self, section_title: str, hv: bool = False, parent=None):
        super().__init__(parent)
        self._title         = section_title
        self._hv            = hv
        self._side_a_label  = "Source"
        self._side_b_label  = "Destination"
        self._side_a_part   = ""      # connector part number, from the netlist
        self._side_b_part   = ""
        self._items: list[_Net | _Row | _Gap] = []    # ordered draw list
        self._states: dict[tuple[int, int], PinState] = {}
        self._dirty   = False

        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        self.setMinimumWidth(MIN_W)
        self._recompute_height()

        self._flush_timer = QTimer(self)
        self._flush_timer.setInterval(100)
        self._flush_timer.timeout.connect(self._flush)
        self._flush_timer.start()

    # ── Public API ────────────────────────────────────────────────────────────

    def set_connections(self, rows: list[_Net | _Row | _Gap],
                        side_a_label: str = "", side_b_label: str = "",
                        side_a_part: str = "", side_b_part: str = "") -> None:
        """Replace the current connection list and reset all states."""
        if side_a_label:
            self._side_a_label = side_a_label
        if side_b_label:
            self._side_b_label = side_b_label
        self._side_a_part = side_a_part
        self._side_b_part = side_b_part
        self._items = rows
        self._states.clear()
        self._recompute_height()
        self.update()

    def update_state(self, pin_a: int, pin_b: int, state: PinState) -> None:
        # Keyed on the ordered (side-A pin, side-B pin) tuple only.  Also
        # writing the reversed key would make A1→B6 and A6→B1 — two distinct
        # wires that both exist in poc_harness_v6 — share a single state slot,
        # so one wire's result would repaint the other wire's row.
        key = (pin_a, pin_b)
        current = self._states.get(key, PinState.UNTESTED)
        if _PRIORITY.get(state, 0) > _PRIORITY.get(current, 0):
            self._states[key] = state
            self._dirty = True

    def reset_states(self) -> None:
        self._states.clear()
        self._dirty = True

    # ── Internal ──────────────────────────────────────────────────────────────

    def _recompute_height(self) -> None:
        h = V_PAD
        for item in self._items:
            if isinstance(item, _Net):
                h += NET_HDR_H
            elif isinstance(item, _Gap):
                h += ROW_H * 2  # two-row gap
            elif isinstance(item, _YNet):
                h += ROW_H * max(1, len(item.branches))
            else:
                h += ROW_H
        h += V_PAD
        self.setFixedHeight(max(120, h))

    def _flush(self) -> None:
        if self._dirty:
            self._dirty = False
            self.update()

    # ── Paint ─────────────────────────────────────────────────────────────────

    def paintEvent(self, _event) -> None:  # noqa: N802
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        w, h = self.width(), self.height()
        self._tips.clear()

        if not self._items:
            p.setPen(QColor("#555577"))
            f = QFont(); f.setPointSize(10)
            p.setFont(f)
            p.drawText(QRect(0, 0, w, h), Qt.AlignmentFlag.AlignCenter,
                       "Load a netlist to see the wiring diagram")
            return

        conn_w    = min(CONN_W, max(120, (w - 100) // 3))
        a_left    = 0
        b_left    = w - conn_w
        line_x0   = conn_w            # right edge of Side A body
        line_x1   = b_left            # left edge of Side B body

        # Draw connector bodies (full canvas height)
        self._draw_connector_body(p, a_left, 0, conn_w, h, side='A')
        self._draw_connector_body(p, b_left, 0, conn_w, h, side='B')

        # Draw each item
        fonts = self._make_fonts()
        y = V_PAD

        for item in self._items:
            if isinstance(item, _Net):
                self._draw_net_header(p, item.name, y, line_x0, line_x1, fonts, item.colour)
                y += NET_HDR_H
            elif isinstance(item, _Gap):
                y += ROW_H * 2  # visual gap between connector groups
            elif isinstance(item, _YNet):
                self._draw_ynet(p, item, y, conn_w, a_left, b_left,
                                line_x0, line_x1, fonts)
                y += ROW_H * max(1, len(item.branches))
            else:
                cy    = y + ROW_H // 2
                state = self._states.get((item.pin_a, item.pin_b), PinState.UNTESTED)
                color = _STATE_COLOR[state]

                self._draw_row(p, item, cy, color, conn_w, a_left, b_left,
                               line_x0, line_x1, fonts)
                y += ROW_H

    # ── Draw helpers ──────────────────────────────────────────────────────────

    def _make_fonts(self):
        f_label = QFont(); f_label.setPointSize(7)
        f_pin   = QFont(); f_pin.setPointSize(5)
        f_title = QFont(); f_title.setPointSize(7); f_title.setBold(True)
        f_net   = QFont(); f_net.setPointSize(7);   f_net.setItalic(True)
        return {"label": f_label, "pin": f_pin, "title": f_title, "net": f_net}

    def _draw_connector_body(self, p: QPainter, x: int, y: int,
                              w: int, h: int, side: str) -> None:
        notch = 16
        path = QPainterPath()
        if side == 'A':
            # Right side opens toward the wiring area; left side has DB chamfer
            path.moveTo(x,         y + notch)
            path.lineTo(x + notch, y)
            path.lineTo(x + w,     y)
            path.lineTo(x + w,     y + h)
            path.lineTo(x + notch, y + h)
            path.lineTo(x,         y + h - notch)
        else:
            # Left side opens toward the wiring area; right side has DB chamfer
            path.moveTo(x + w,         y + notch)
            path.lineTo(x + w - notch, y)
            path.lineTo(x,             y)
            path.lineTo(x,             y + h)
            path.lineTo(x + w - notch, y + h)
            path.lineTo(x + w,         y + h - notch)
        path.closeSubpath()

        p.fillPath(path, QBrush(_C_BODY_BG))
        p.setPen(QPen(_C_BODY_BORD, 2))
        p.drawPath(path)

        # connector body top label — uses dynamic source/destination names
        p.setPen(_C_TITLE_FG)
        f = QFont(); f.setPointSize(7); f.setBold(True)
        p.setFont(f)
        txt = self._side_a_label if side == 'A' else self._side_b_label
        p.drawText(QRect(x, y + 2, w, 14), Qt.AlignmentFlag.AlignCenter, txt)

        # Connector part number from the netlist, on a second line beneath.
        part = self._side_a_part if side == 'A' else self._side_b_part
        if part:
            p.setPen(_C_PART_FG)
            fp = QFont(); fp.setPointSize(6)
            p.setFont(fp)
            p.drawText(QRect(x + 2, y + 15, w - 4, 12),
                       Qt.AlignmentFlag.AlignCenter, part)

    def _draw_net_header(self, p: QPainter, name: str,
                          y: int, x0: int, x1: int, fonts: dict,
                          colour: str = "") -> None:
        bar_w = x1 - x0
        p.fillRect(x0, y, bar_w, NET_HDR_H, _C_NET_BG)

        # The header names the wire's colour when the netlist gives one, so it
        # needs more room than the bare net name.
        text = f"▸  {name}" + (f"   ·   {colour}" if colour else "")
        p.setFont(fonts["net"])
        text_w = p.fontMetrics().horizontalAdvance(text) if colour else 0
        gap = max(120, text_w + 24)

        # Dashed separator lines on each side
        pen = QPen(_C_NET_FG, 1, Qt.PenStyle.DashLine)
        p.setPen(pen)
        cy = y + NET_HDR_H // 2
        p.drawLine(x0 + 4, cy, x0 + (bar_w - gap) // 2, cy)
        p.drawLine(x0 + (bar_w + gap) // 2, cy, x1 - 4, cy)

        # Net name
        p.setPen(_C_NET_FG)
        p.setFont(fonts["net"])
        p.drawText(QRect(x0, y, bar_w, NET_HDR_H),
                   Qt.AlignmentFlag.AlignCenter, text)

    def _trunk_state(self, states: list[PinState]) -> PinState:
        """Verdict for a Y trunk: red if any branch failed, green only when
        every branch passed, otherwise untested."""
        if not states:
            return PinState.UNTESTED
        if any(s == PinState.FAIL for s in states):
            return PinState.FAIL
        if all(s == PinState.PASS for s in states):
            return PinState.PASS
        if any(s == PinState.IN_PROGRESS for s in states):
            return PinState.IN_PROGRESS
        return PinState.UNTESTED

    def _draw_ynet(self, p: QPainter, ynet: _YNet, y: int,
                   conn_w: int, a_left: int, b_left: int,
                   line_x0: int, line_x1: int, fonts: dict) -> None:
        """Draw one source pin fanning out to N destinations as a Y split."""
        n = max(1, len(ynet.branches))
        group_h  = ROW_H * n
        src_cy   = y + group_h // 2
        junc_x   = line_x0 + (line_x1 - line_x0) // 3

        states = [self._states.get((ynet.pin_a, b[0]), PinState.UNTESTED)
                  for b in ynet.branches]
        trunk_state = self._trunk_state(states)
        trunk_color = _STATE_COLOR[trunk_state]
        trunk_style = (Qt.PenStyle.DashLine if trunk_state == PinState.UNTESTED
                       else Qt.PenStyle.SolidLine)

        # ── Source pin circle, vertically centred on the whole group ─────────
        pin_a_x = line_x0 - PIN_R - 4
        p.setBrush(QBrush(trunk_color))
        p.setPen(QPen(QColor("#111"), 1))
        p.drawEllipse(QPoint(pin_a_x, src_cy), PIN_R, PIN_R)

        p.setPen(QColor("#111") if trunk_color.lightness() > 100 else QColor("#EEE"))
        p.setFont(fonts["pin"])
        p.drawText(QRect(pin_a_x - PIN_R, src_cy - PIN_R, PIN_R * 2, PIN_R * 2),
                   Qt.AlignmentFlag.AlignCenter,
                   str(ynet.display_pin_a or ynet.pin_a))

        p.setPen(_C_LABEL_FG)
        p.setFont(fonts["label"])
        disp_a = ynet.display_pin_a or ynet.pin_a
        label_a = f"{disp_a}"
        if ynet.name_a:
            label_a += f"  {ynet.name_a}"
        self._add_pin_tip(QRect(a_left, src_cy - ROW_H // 2, line_x0 - a_left, ROW_H),
                          self._side_a_label, disp_a, ynet.pin_a)
        p.drawText(
            QRect(a_left + 18, src_cy - ROW_H // 2,
                  pin_a_x - a_left - 18 - PIN_R - 6, ROW_H),
            Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignRight,
            label_a,
        )

        # ── Trunk: source → junction ─────────────────────────────────────────
        p.setPen(QPen(trunk_color, 3, trunk_style))
        p.drawLine(line_x0, src_cy, junc_x, src_cy)

        # ── Spine: vertical run linking every branch take-off point ──────────
        first_cy = y + ROW_H // 2
        last_cy  = y + group_h - ROW_H // 2
        p.setPen(QPen(trunk_color, 3, trunk_style))
        p.drawLine(junc_x, first_cy, junc_x, last_cy)

        # Junction node
        p.setBrush(QBrush(trunk_color))
        p.setPen(QPen(QColor("#111"), 1))
        p.drawEllipse(QPoint(junc_x, src_cy), 4, 4)

        # ── Branches: junction → each destination pin ────────────────────────
        for k, (pin_b, name_b, disp_b) in enumerate(ynet.branches):
            cy    = y + ROW_H * k + ROW_H // 2
            state = states[k]
            color = _STATE_COLOR[state]
            style = (Qt.PenStyle.DashLine if state == PinState.UNTESTED
                     else Qt.PenStyle.SolidLine)

            p.setPen(QPen(color, 2, style))
            p.drawLine(junc_x, cy, line_x1, cy)

            badge_x = (junc_x + line_x1) // 2
            p.setPen(QPen(color, 1))
            p.setFont(fonts["pin"])
            p.drawText(QRect(badge_x - 20, cy - 8, 40, 14),
                       Qt.AlignmentFlag.AlignCenter, _STATE_LABEL[state])

            pin_b_x = line_x1 + PIN_R + 4
            p.setBrush(QBrush(color))
            p.setPen(QPen(QColor("#111"), 1))
            p.drawEllipse(QPoint(pin_b_x, cy), PIN_R, PIN_R)

            p.setPen(QColor("#111") if color.lightness() > 100 else QColor("#EEE"))
            p.setFont(fonts["pin"])
            p.drawText(QRect(pin_b_x - PIN_R, cy - PIN_R, PIN_R * 2, PIN_R * 2),
                       Qt.AlignmentFlag.AlignCenter, str(disp_b or pin_b))

            p.setPen(_C_LABEL_FG)
            p.setFont(fonts["label"])
            label_b = f"{name_b}  {disp_b or pin_b}" if name_b else f"{disp_b or pin_b}"
            label_b_x = pin_b_x + PIN_R + 4
            self._add_pin_tip(QRect(line_x1, cy - ROW_H // 2,
                                    b_left + conn_w - line_x1, ROW_H),
                              self._side_b_label, disp_b or pin_b, pin_b)
            p.drawText(
                QRect(label_b_x, cy - ROW_H // 2,
                      (b_left + conn_w - 18) - label_b_x, ROW_H),
                Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignLeft,
                label_b,
            )

    def _draw_row(self, p: QPainter, row: _Row, cy: int, color: QColor,
                   conn_w: int, a_left: int, b_left: int,
                   line_x0: int, line_x1: int, fonts: dict) -> None:
        row_top = cy - ROW_H // 2

        # ── Pin A circle (on the right inner edge of Side A body) ────────────
        pin_a_x = line_x0 - PIN_R - 4
        p.setBrush(QBrush(color))
        p.setPen(QPen(QColor("#111"), 1))
        p.drawEllipse(QPoint(pin_a_x, cy), PIN_R, PIN_R)

        # Pin number inside A circle (use display pin if available)
        p.setPen(QColor("#111") if color.lightness() > 100 else QColor("#EEE"))
        p.setFont(fonts["pin"])
        p.drawText(QRect(pin_a_x - PIN_R, cy - PIN_R, PIN_R * 2, PIN_R * 2),
                   Qt.AlignmentFlag.AlignCenter, str(row.display_pin_a or row.pin_a))

        # Label inside Side A body: "pin_num  name"
        p.setPen(_C_LABEL_FG)
        p.setFont(fonts["label"])
        disp_a = row.display_pin_a or row.pin_a
        label_a = f"{disp_a}"
        if row.name_a:
            label_a += f"  {row.name_a}"
        self._add_pin_tip(QRect(a_left, row_top, line_x0 - a_left, ROW_H),
                          self._side_a_label, disp_a, row.pin_a)
        p.drawText(
            QRect(a_left + 18, row_top, pin_a_x - a_left - 18 - PIN_R - 6, ROW_H),
            Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignRight,
            label_a,
        )

        # ── Connection line ───────────────────────────────────────────────────
        # Dashed while no result has arrived, so "not tested yet" is visually
        # distinct from a tested wire rather than just a dimmer solid line.
        state = self._states.get((row.pin_a, row.pin_b), PinState.UNTESTED)
        style = (Qt.PenStyle.DashLine if state == PinState.UNTESTED
                 else Qt.PenStyle.SolidLine)
        p.setPen(QPen(color, 2, style))
        p.drawLine(line_x0, cy, line_x1, cy)

        # State badge (right of centre)
        badge_x = (line_x0 + line_x1) // 2
        p.setPen(QPen(color, 1))
        p.setFont(fonts["pin"])
        p.drawText(QRect(badge_x - 20, cy - 8, 40, 14),
                   Qt.AlignmentFlag.AlignCenter, _STATE_LABEL[state])

        # ── Pin B circle (on the left inner edge of Side B body) ─────────────
        pin_b_x = line_x1 + PIN_R + 4
        p.setBrush(QBrush(color))
        p.setPen(QPen(QColor("#111"), 1))
        p.drawEllipse(QPoint(pin_b_x, cy), PIN_R, PIN_R)

        # Pin number inside B circle (use display pin if available)
        p.setPen(QColor("#111") if color.lightness() > 100 else QColor("#EEE"))
        p.setFont(fonts["pin"])
        p.drawText(QRect(pin_b_x - PIN_R, cy - PIN_R, PIN_R * 2, PIN_R * 2),
                   Qt.AlignmentFlag.AlignCenter, str(row.display_pin_b or row.pin_b))

        # Label inside Side B body: "name  pin_num"
        p.setPen(_C_LABEL_FG)
        p.setFont(fonts["label"])
        disp_b = row.display_pin_b or row.pin_b
        label_b = f"{disp_b}"
        if row.name_b:
            label_b = f"{row.name_b}  {label_b}"
        self._add_pin_tip(QRect(line_x1, row_top, b_left + conn_w - line_x1, ROW_H),
                          self._side_b_label, disp_b, row.pin_b)
        label_b_x = pin_b_x + PIN_R + 4
        p.drawText(
            QRect(label_b_x, row_top,
                  (b_left + conn_w - 18) - label_b_x, ROW_H),
            Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignLeft,
            label_b,
        )


# ── Scroll area that caps its sizeHint so the splitter can share space ────────

class _CanvasScrollArea(QScrollArea):
    """QScrollArea whose sizeHint height is capped so a QSplitter sibling
    is never completely starved of space by a tall canvas."""
    _MAX_HINT_H = 480

    def sizeHint(self) -> QSize:
        sh = super().sizeHint()
        return QSize(sh.width(), min(sh.height(), self._MAX_HINT_H))

    def minimumSizeHint(self) -> QSize:
        return QSize(MIN_W // 2, 120)


# ── SectionWidget — title bar + scroll area wrapping a WiringCanvas ──────────

class _SectionWidget(QWidget):
    def __init__(self, title: str, title_style: str, hv: bool = False, parent=None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        self._hdr = QLabel(title)
        self._hdr.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._hdr.setFixedHeight(24)
        self._hdr.setStyleSheet(title_style)
        f = QFont(); f.setPointSize(8); f.setBold(True)
        self._hdr.setFont(f)
        layout.addWidget(self._hdr)

        self.canvas = WiringCanvas(title, hv=hv)

        scroll = _CanvasScrollArea()
        scroll.setWidget(self.canvas)
        scroll.setWidgetResizable(False)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        scroll.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        scroll.setFrameShape(QScrollArea.Shape.NoFrame)
        layout.addWidget(scroll)

    def set_title(self, title: str) -> None:
        self._hdr.setText(title)


# ── ConnectorSection — title bar + canvas, no scroll of its own ──────────────

class _ConnectorSection(QWidget):
    """One connector's block inside ConnectorView's shared scroll area."""

    def __init__(self, title: str, title_style: str, parent=None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        hdr = QLabel(title)
        hdr.setAlignment(Qt.AlignmentFlag.AlignCenter)
        hdr.setFixedHeight(24)
        hdr.setStyleSheet(title_style)
        f = QFont(); f.setPointSize(8); f.setBold(True)
        hdr.setFont(f)
        layout.addWidget(hdr)

        self.canvas = WiringCanvas(title)
        layout.addWidget(self.canvas)


# ── CombinedCanvas — every connector on both sides in ONE diagram ─────────────

@dataclass
class _CPin:
    channel: int
    disp: int          # pin number on its own connector
    name: str


@dataclass
class _CBlock:
    title: str         # e.g. "J1  Side-A"
    part: str
    pins: list[_CPin]
    y: int = 0         # top of the block, set by layout
    conn: str = ""     # connector id, so both sides' copies line up


@dataclass
class _CWire:
    pin_a: int
    pin_b: int
    cross: bool        # leaves its connector


def _lane_order(spans: list[tuple[float, float]]) -> list[int]:
    """Order the vertical runs of the Single view's wires, left to right.

    spans[i] is wire i's (y at Side A, y at Side B).  A wire leaves Side A
    horizontally, runs vertically in its own lane, then goes horizontally into
    Side B.  Which lane each wire gets decides how many wires cross, so start
    from a sensible order and swap neighbours while that removes a crossing or
    an overlap.
    Returns the wire indices, leftmost lane first.
    """
    def inside(y: float, a: float, b: float) -> bool:
        return min(a, b) < y < max(a, b)

    def cost(i: int, j: int) -> int:
        # crossings if wire i sits in a lane left of wire j
        (ya_i, yb_i), (ya_j, yb_j) = spans[i], spans[j]
        # A crossing is drawn with a hop and is easy to read.  Two runs lying
        # on the same row merge into one line, which is not: wire i's Side-B
        # run and wire j's Side-A run share the stretch between their lanes
        # when i's end row is j's start row.
        return (inside(ya_j, ya_i, yb_i)       # j's Side-A run passes i's lane
                + inside(yb_i, ya_j, yb_j)     # i's Side-B run passes j's lane
                + 3 * (yb_i == ya_j))          # i's Side-B run overlaps j's Side-A run

    def total(order: list[int]) -> int:
        return sum(cost(order[a], order[b])
                   for a in range(len(order)) for b in range(a + 1, len(order)))

    # Wires that all step the same way have a clean order: going down, the one
    # starting lowest takes the leftmost lane (and the mirror image going up),
    # so a wire's Side-B run never lands on the next wire's Side-A run.
    down = sorted((i for i, (a, b) in enumerate(spans) if b > a),
                  key=lambda i: (-spans[i][0], -spans[i][1]))
    up = sorted((i for i, (a, b) in enumerate(spans) if b < a),
                key=lambda i: (spans[i][0], spans[i][1]))
    order = min((down + up, up + down, sorted(range(len(spans)),
                                              key=lambda i: sum(spans[i]))),
                key=total)
    for _ in range(len(order) + 1):
        swapped = False
        for k in range(len(order) - 1):
            i, j = order[k], order[k + 1]
            if cost(j, i) < cost(i, j):
                order[k], order[k + 1] = j, i
                swapped = True
        if not swapped:
            break
    return order


def _hop_line(path: QPainterPath, x0: float, x1: float, y: float,
              cuts: list[float], r: float) -> None:
    """Add a horizontal run x0 -> x1 at y, hopping over each x in cuts."""
    step = 1 if x1 >= x0 else -1
    for cx in sorted((c for c in cuts if min(x0, x1) + r < c < max(x0, x1) - r),
                     reverse=step < 0):
        path.lineTo(cx - step * r, y)
        # a half circle over the top; clockwise going right, anticlockwise going left
        path.arcTo(QRectF(cx - r, y - r, 2 * r, 2 * r),
                   180 if step > 0 else 0, -180 * step)
    path.lineTo(x1, y)


class CombinedCanvas(_TipCanvas):
    """The single-diagram view: Side A on the left, Side B on the right.

    Each side has its own copy of every connector (J1, J2, J3 on Side A and
    J1, J2, J3 on Side B — six bodies in all), and a wire joins each Side-A
    pin to its Side-B pin, routed at right angles with a hop wherever two
    wires cross.  Given a layout
    (the connector config) every connector is drawn on both sides with ALL
    its pins, used or not; without one, only the connectors and pins the
    netlist mentions are drawn.  A wire that ends on a different connector
    than it starts on is routed through a lane in the middle; wires that stay
    on their connector run straight across.
    """

    HDR_H     = 34    # connector title + part number
    BLOCK_GAP = 14

    def __init__(self, parent=None):
        super().__init__(parent)
        self._left:  list[_CBlock] = []
        self._right: list[_CBlock] = []
        self._wires: list[_CWire] = []
        self._ya: dict[int, int] = {}     # side-A channel -> row centre y
        self._yb: dict[int, int] = {}     # side-B channel -> row centre y
        self._lane: dict[int, int] = {}   # wire index -> lane (0 = leftmost)
        self._states: dict[tuple[int, int], PinState] = {}
        self._dirty = False

        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        self.setMinimumWidth(MIN_W)
        self._relayout()

        self._flush_timer = QTimer(self)
        self._flush_timer.setInterval(100)
        self._flush_timer.timeout.connect(self._flush)
        self._flush_timer.start()

    # ── Public API ────────────────────────────────────────────────────────────

    def set_data(self, pairs: list[tuple], layout: list[dict] | None = None,
                 dest_labels: dict[str, str] | None = None,
                 layout_b: list[dict] | None = None) -> None:
        """Same pair tuples as ConnectorView.set_connections.

        dest_labels renames a connector on the Side-B end ({"J1": "X1"}); a
        block still lines up with its Side-A twin through its connector id.

        layout: [{"conn": id, "pins": [(channel, connector_pin), ...],
                  "part_a": str, "part_b": str}, ...] in display order.

        layout_b: the Side-B connectors when they are not copies of Side A's
        (one DB37 facing X1, X2 and X3): same shape as layout, each entry
        giving the Side-B connector's own name, pins and "part_b".  Each side
        then stacks its connectors on its own.
        """
        lefts:  dict[str, dict[int, _CPin]] = {}
        rights: dict[str, dict[int, _CPin]] = {}
        parts_l: dict[str, str] = {}
        parts_r: dict[str, str] = {}
        names_a: dict[int, str] = {}
        names_b: dict[int, str] = {}
        label_a = label_b = ""
        wires: list[_CWire] = []

        for pair in _source_pairs_only(pairs):
            src = (pair[11] if len(pair) >= 12 and pair[11]
                   else _connector_prefix(pair[2]))
            dst = pair[12] if len(pair) >= 13 and pair[12] else src
            if len(pair) >= 7:
                label_a = label_a or pair[5]
                label_b = label_b or pair[6]
            disp_a = pair[7] if len(pair) >= 9 and pair[7] else pair[0]
            disp_b = pair[8] if len(pair) >= 9 and pair[8] else pair[1]
            names_a.setdefault(pair[0], pair[3])
            names_b.setdefault(pair[1], pair[4])
            lefts.setdefault(src, {}).setdefault(
                pair[0], _CPin(pair[0], disp_a, pair[3]))
            rights.setdefault(dst, {}).setdefault(
                pair[1], _CPin(pair[1], disp_b, pair[4]))
            if len(pair) >= 11:
                parts_l.setdefault(src, pair[9])
                parts_r.setdefault(dst, pair[10])
            wires.append(_CWire(pair[0], pair[1], src != dst))

        side_a = label_a or "Source"
        side_b = label_b or "Destination"

        labels = dest_labels or {}

        def title(conn: str, side: str, b: bool = False) -> str:
            if b:
                conn = labels.get(conn, conn)
            return f"{conn}  {side}" if conn else side

        if layout:
            # Every configured connector on both sides, every pin listed.
            self._left = [
                _CBlock(title(c["conn"], side_a), c.get("part_a") or parts_l.get(c["conn"], ""),
                        [_CPin(ch, pin, names_a.get(ch, "")) for ch, pin in c["pins"]],
                        conn=c["conn"])
                for c in layout]
            self._right = [
                _CBlock(title(c["conn"], side_b, True), c.get("part_b") or parts_r.get(c["conn"], ""),
                        [_CPin(ch, pin, names_b.get(ch, "")) for ch, pin in c["pins"]],
                        conn=c["conn"])
                for c in (layout_b or layout)]
            # A netlist pin the layout does not know still has to be drawn.
            for used, blocks, side, parts, b in ((lefts, self._left, side_a, parts_l, False),
                                                 (rights, self._right, side_b, parts_r, True)):
                for conn, pins in used.items():
                    block = next((x for x in blocks if x.conn == conn), None)
                    if block is None:
                        block = _CBlock(title(conn, side, b), parts.get(conn, ""), [], conn=conn)
                        blocks.append(block)
                    known = {pin.channel for pin in block.pins}
                    block.pins.extend(pin for ch, pin in pins.items() if ch not in known)
                    block.pins.sort(key=lambda pin: pin.channel)
        else:
            def blocks(groups, parts, side, b):
                out = []
                for conn in sorted(groups, key=lambda c: min(groups[c])):
                    pins = [groups[conn][ch] for ch in sorted(groups[conn])]
                    out.append(_CBlock(title(conn, side, b), parts.get(conn, ""), pins, conn=conn))
                return out

            self._left = blocks(lefts, parts_l, side_a, False)
            self._right = blocks(rights, parts_r, side_b, True)

        self._wires = wires
        self._states.clear()
        self._relayout()
        self.update()

    def update_state(self, pin_a: int, pin_b: int, state: PinState) -> None:
        key = (pin_a, pin_b)
        if _PRIORITY.get(state, 0) > _PRIORITY.get(self._states.get(key, PinState.UNTESTED), 0):
            self._states[key] = state
            self._dirty = True

    def reset_states(self) -> None:
        self._states.clear()
        self._dirty = True

    # ── Layout ────────────────────────────────────────────────────────────────

    def _relayout(self) -> None:
        # Side A and Side B each stack their connectors top to bottom.  A
        # connector sits at the same height on both sides, so pin n of J2 on
        # Side A faces pin n of J2 on Side B and a straight wire stays straight.
        self._ya.clear(); self._yb.clear()
        left = {b.conn or ("a", i): b for i, b in enumerate(self._left)}
        right = {b.conn or ("b", i): b for i, b in enumerate(self._right)}
        yl = yr = V_PAD
        for key in list(left) + [k for k in right if k not in left]:
            lb, rb = left.get(key), right.get(key)
            y = max(yl if lb else 0, yr if rb else 0)
            for blk, rows in ((lb, self._ya), (rb, self._yb)):
                if blk is None:
                    continue
                blk.y = y
                for i, pin in enumerate(blk.pins):
                    rows[pin.channel] = y + self.HDR_H + i * ROW_H + ROW_H // 2
            end = lambda blk: (y + self.HDR_H + len(blk.pins) * ROW_H + 8
                               + self.BLOCK_GAP)
            yl = end(lb) if lb else yl
            yr = end(rb) if rb else yr
        self.setFixedHeight(max(120, max(yl, yr) + V_PAD - self.BLOCK_GAP))

        # Wires that change row need a lane for their vertical run.
        bent = {i: (self._ya[w.pin_a], self._yb[w.pin_b])
                for i, w in enumerate(self._wires)
                if w.pin_a in self._ya and w.pin_b in self._yb
                and self._ya[w.pin_a] != self._yb[w.pin_b]}
        keys = list(bent)
        self._lane = {keys[pos]: lane for lane, pos
                      in enumerate(_lane_order([bent[k] for k in keys]))}

    def _flush(self) -> None:
        if self._dirty:
            self._dirty = False
            self.update()

    # ── Paint ─────────────────────────────────────────────────────────────────

    def paintEvent(self, _event) -> None:  # noqa: N802
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        w, h = self.width(), self.height()
        self._tips.clear()

        if not self._wires:
            p.setPen(QColor("#555577"))
            f = QFont(); f.setPointSize(10)
            p.setFont(f)
            p.drawText(QRect(0, 0, w, h), Qt.AlignmentFlag.AlignCenter,
                       "Load a netlist to see the wiring diagram")
            return

        conn_w = min(CONN_W, max(120, (w - 100) // 3))
        x_a = conn_w                    # right edge of the Side-A bodies
        x_b = w - conn_w                # left edge of the Side-B bodies
        fonts = {"label": QFont(), "pin": QFont(), "title": QFont()}
        fonts["label"].setPointSize(7)
        fonts["pin"].setPointSize(5)
        fonts["title"].setPointSize(7); fonts["title"].setBold(True)

        for b in self._left:
            self._draw_body(p, b, 0, conn_w, "A", fonts)
        for b in self._right:
            self._draw_body(p, b, x_b, conn_w, "B", fonts)

        pin_state_a: dict[int, PinState] = {}
        pin_state_b: dict[int, PinState] = {}

        # Wires are drawn like a wiring diagram: out of Side A, along a lane of
        # their own, into Side B, hopping over any wire they cross.
        margin = 14.0
        spacing = max(4.0, min(18.0, (x_b - x_a - 2 * margin) / max(1, len(self._lane))))
        hop = max(1.5, min(5.0, spacing / 2 - 1.0))
        band_x = (x_a + x_b - spacing * len(self._lane)) / 2     # lanes sit mid-gap
        lane_x = lambda i: band_x + (self._lane[i] + 0.5) * spacing
        runs = [(lane_x(i), min(self._ya[w.pin_a], self._yb[w.pin_b]),
                 max(self._ya[w.pin_a], self._yb[w.pin_b]))
                for i, w in enumerate(self._wires) if i in self._lane]

        # Cross-connector wires last so they sit on top.
        for idx, wire in sorted(enumerate(self._wires), key=lambda iw: iw[1].cross):
            ya = self._ya.get(wire.pin_a)
            yb = self._yb.get(wire.pin_b)
            if ya is None or yb is None:
                continue
            state = self._states.get((wire.pin_a, wire.pin_b), PinState.UNTESTED)
            color = _STATE_COLOR[state]
            for d, ch in ((pin_state_a, wire.pin_a), (pin_state_b, wire.pin_b)):
                if _PRIORITY.get(state, 0) >= _PRIORITY.get(d.get(ch, PinState.UNTESTED), 0):
                    d[ch] = state

            def crossed(y: float) -> list[float]:
                return [x for x, lo, hi in runs if lo < y < hi]

            path = QPainterPath()
            path.moveTo(x_a, ya)
            if idx in self._lane:
                lx = lane_x(idx)
                _hop_line(path, x_a, lx, ya, crossed(ya), hop)
                path.lineTo(lx, yb)
                _hop_line(path, lx, x_b, yb, crossed(yb), hop)
            else:
                _hop_line(path, x_a, x_b, ya, crossed(ya), hop)

            style = (Qt.PenStyle.DashLine if state == PinState.UNTESTED
                     else Qt.PenStyle.SolidLine)
            p.setPen(QPen(color, 2, style, Qt.PenCapStyle.FlatCap,
                          Qt.PenJoinStyle.MiterJoin))
            p.drawPath(path)

        # Pin circles and labels on top of the wires.
        for b in self._left:
            self._draw_pins(p, b, "A", conn_w, x_b, pin_state_a, fonts)
        for b in self._right:
            self._draw_pins(p, b, "B", conn_w, x_b, pin_state_b, fonts)

    def _draw_body(self, p: QPainter, b: _CBlock, x: int, w: int,
                   side: str, fonts: dict) -> None:
        h = self.HDR_H + len(b.pins) * ROW_H + 8
        y, notch = b.y, 12
        path = QPainterPath()
        if side == "A":
            path.moveTo(x, y + notch); path.lineTo(x + notch, y)
            path.lineTo(x + w, y);     path.lineTo(x + w, y + h)
            path.lineTo(x + notch, y + h); path.lineTo(x, y + h - notch)
        else:
            path.moveTo(x + w, y + notch); path.lineTo(x + w - notch, y)
            path.lineTo(x, y);             path.lineTo(x, y + h)
            path.lineTo(x + w - notch, y + h); path.lineTo(x + w, y + h - notch)
        path.closeSubpath()
        p.fillPath(path, QBrush(_C_BODY_BG))
        p.setPen(QPen(_C_BODY_BORD, 2))
        p.drawPath(path)

        p.setPen(_C_TITLE_FG)
        p.setFont(fonts["title"])
        p.drawText(QRect(x, y + 3, w, 14), Qt.AlignmentFlag.AlignCenter, b.title)
        if b.part:
            p.setPen(_C_PART_FG)
            fp = QFont(); fp.setPointSize(6)
            p.setFont(fp)
            p.drawText(QRect(x + 2, y + 17, w - 4, 12),
                       Qt.AlignmentFlag.AlignCenter, b.part)

    def _draw_pins(self, p: QPainter, b: _CBlock, side: str, conn_w: int,
                   x_b: int, pin_state: dict, fonts: dict) -> None:
        rows = self._ya if side == "A" else self._yb
        for pin in b.pins:
            cy = rows[pin.channel]
            state = pin_state.get(pin.channel, PinState.UNTESTED)
            color = _STATE_COLOR[state]
            cx = conn_w - PIN_R - 4 if side == "A" else x_b + PIN_R + 4

            p.setBrush(QBrush(color))
            p.setPen(QPen(QColor("#111"), 1))
            p.drawEllipse(QPoint(cx, cy), PIN_R, PIN_R)
            p.setPen(QColor("#111") if color.lightness() > 100 else QColor("#EEE"))
            p.setFont(fonts["pin"])
            p.drawText(QRect(cx - PIN_R, cy - PIN_R, PIN_R * 2, PIN_R * 2),
                       Qt.AlignmentFlag.AlignCenter, str(pin.disp))

            p.setPen(_C_LABEL_FG)
            p.setFont(fonts["label"])
            if side == "A":
                self._add_pin_tip(QRect(0, cy - ROW_H // 2, conn_w, ROW_H),
                                  b.title, pin.disp, pin.channel)
            else:
                self._add_pin_tip(QRect(x_b, cy - ROW_H // 2, conn_w, ROW_H),
                                  b.title, pin.disp, pin.channel)
            if side == "A":
                text = f"{pin.disp}  {pin.name}" if pin.name else f"{pin.disp}"
                p.drawText(QRect(18, cy - ROW_H // 2, cx - 18 - PIN_R - 6, ROW_H),
                           Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignRight, text)
            else:
                text = f"{pin.name}  {pin.disp}" if pin.name else f"{pin.disp}"
                lx = cx + PIN_R + 4
                p.drawText(QRect(lx, cy - ROW_H // 2, (x_b + conn_w - 14) - lx, ROW_H),
                           Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignLeft, text)


# ── ConnectorView — top-level widget (drop-in for MatrixView) ─────────────────

class ConnectorView(QWidget):
    """DB-style wiring diagram with two views, switched by the buttons on top.

    Single view   all six connectors in one diagram — J1, J2, J3 on
                  Side A and again on Side B — with a wire from each Side-A
                  pin to its Side-B pin.
    Sections      one section per connector (Side A / Side B), plus one per
                  interconnect.

    The Sections view:

    Wires that stay inside one connector (J1 pin 1 -> J1 pin 1) are
    grouped into a section per connector, e.g. J1, J2, J3.  Wires
    that leave a connector (J1 pin 5 -> J2 pin 9) are drawn in their
    own INTERCONNECT section for that pair, e.g. "J1 ➜ J2", with the
    source connector body on the left and the destination connector body on
    the right.  All sections stack in a single scroll area.

    Call set_connections(cont_pairs) after loading a netlist, then
    update_pin(pin_a, pin_b, state) as results arrive.
    """

    _HDR_STYLE = ("background:#1F3864; color:#FFFFFF; border-radius:0px;"
                  " padding:2px 6px;")
    _LINK_HDR_STYLE = ("background:#5B3A8A; color:#FFFFFF; border-radius:0px;"
                       " padding:2px 6px;")

    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(2, 2, 2, 2)
        layout.setSpacing(2)

        self._container = QWidget()
        self._stack = QVBoxLayout(self._container)
        self._stack.setContentsMargins(0, 0, 0, 0)
        self._stack.setSpacing(6)
        self._stack.addStretch()

        scroll = QScrollArea()
        scroll.setWidget(self._container)
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        scroll.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        scroll.setFrameShape(QScrollArea.Shape.NoFrame)

        # First page: all connectors on both sides in a single diagram.
        self._combined = CombinedCanvas()
        combined_scroll = QScrollArea()
        combined_scroll.setWidget(self._combined)
        combined_scroll.setWidgetResizable(True)
        combined_scroll.setFrameShape(QScrollArea.Shape.NoFrame)

        self._pages = QStackedWidget()
        self._pages.addWidget(combined_scroll)     # 0 = Single view
        self._pages.addWidget(scroll)              # 1 = Sections

        bar = QHBoxLayout()
        bar.setContentsMargins(4, 0, 4, 0)
        bar.setSpacing(4)
        bar.addWidget(QLabel("View:"))
        group = QButtonGroup(self)
        for idx, (text, tip) in enumerate((
                ("Single view", "Side A and Side B connectors facing each "
                                "other, one wire per Side-A pin to Side-B pin"),
                ("Sections", "One section per connector (Side A / Side B), "
                             "plus one per connector-to-connector interconnect"))):
            btn = QPushButton(text)
            btn.setCheckable(True)
            btn.setToolTip(tip)
            btn.setChecked(idx == 0)
            btn.clicked.connect(lambda _c, i=idx: self._pages.setCurrentIndex(i))
            group.addButton(btn)
            bar.addWidget(btn)
        bar.addStretch()

        layout.addLayout(bar)
        layout.addWidget(self._pages, 1)
        layout.addWidget(self._build_legend())

        self._sections: list[_ConnectorSection] = []
        self._dest_labels: dict[str, str] = {}
        self._rebuild_sections([("", "", [])])

    # ── Public API ────────────────────────────────────────────────────────────

    def set_connections(self, cont_pairs: list[tuple],
                        hv_pairs: list[tuple] | None = None,
                        layout: list[dict] | None = None,
                        dest_labels: dict[str, str] | None = None,
                        layout_b: list[dict] | None = None) -> None:
        """
        dest_labels renames a connector on the Side-B end ({"J1": "X1"}); it
        changes only what is shown, not how wires are grouped.

        layout_b lists the Side-B connectors when they differ from Side A's
        (see CombinedCanvas.set_data); each pair's conn_id_b then names one of
        them.

        Each pair: (pin_a, pin_b, net_name, pin_a_name, pin_b_name, source,
        destination, display_pin_a, display_pin_b, part_a, part_b, conn_id,
        conn_id_b, wire_colour).  Shorter tuples are accepted (5, 7, 9, 11,
        12 or 13 elements); without an explicit conn_id the "CONN / net"
        prefix of net_name is used, and a missing conn_id_b means "same
        connector".  A wire_colour is named on the net's header in the
        Sections view.

        hv_pairs is accepted for API compatibility with callers that pass a
        second list (e.g. insulation pairs) but is ignored by this view.

        layout lists every connector and its pins (see CombinedCanvas.set_data)
        so the Single view can draw all of them on both sides even where the
        netlist uses only some.
        """
        same: dict[str, list[tuple]] = {}
        links: dict[tuple[str, str], list[tuple]] = {}
        first_pin: dict[str, int] = {}     # connector -> lowest channel seen

        for pair in _source_pairs_only(cont_pairs):
            src = (pair[11] if len(pair) >= 12 and pair[11]
                   else _connector_prefix(pair[2]))
            dst = pair[12] if len(pair) >= 13 and pair[12] else src
            if src:
                first_pin[src] = min(first_pin.get(src, pair[0]), pair[0])
            if dst:
                first_pin[dst] = min(first_pin.get(dst, pair[1]), pair[1])
            # The section title already names the connector, so drop the
            # "CONN / " prefix from the per-net header inside it.
            if src and pair[2].startswith(f"{src} / "):
                pair = pair[:2] + (pair[2][len(src) + 3:],) + pair[3:]
            if dst == src:
                same.setdefault(src, []).append(pair)
            else:
                links.setdefault((src, dst), []).append(pair)

        order = lambda c: first_pin.get(c, 0)   # noqa: E731
        sections = [(c, c, same[c]) for c in sorted(same, key=order)]
        sections += [(s_, d_, links[(s_, d_)])
                     for s_, d_ in sorted(links, key=lambda k: (order(k[0]), order(k[1])))]
        self._dest_labels = dest_labels or {}
        self._rebuild_sections(sections or [("", "", [])])
        self._combined.set_data(cont_pairs, layout, self._dest_labels, layout_b)

    def update_pin(self, pin_a: int, pin_b: int, state: PinState) -> None:
        for sec in self._sections:
            sec.canvas.update_state(pin_a, pin_b, state)
        self._combined.update_state(pin_a, pin_b, state)

    def reset(self) -> None:
        for sec in self._sections:
            sec.canvas.reset_states()
        self._combined.reset_states()

    def batch_update(self, updates: list[tuple[int, int, PinState]]) -> None:
        for pin_a, pin_b, state in updates:
            self.update_pin(pin_a, pin_b, state)

    def set_header(self, dut_id: str, progress: str) -> None:
        pass

    # ── Internal ──────────────────────────────────────────────────────────────

    def _rebuild_sections(self, groups: list[tuple[str, str, list[tuple]]]) -> None:
        for sec in self._sections:
            self._stack.removeWidget(sec)
            sec.deleteLater()
        self._sections = []

        for src, dst, pairs in groups:
            src_label = dst_label = src_part = dst_part = ""
            for pair in pairs:
                if len(pair) >= 7:
                    src_label = src_label or pair[5]
                    dst_label = dst_label or pair[6]
                if len(pair) >= 11:
                    src_part = src_part or pair[9]
                    dst_part = dst_part or pair[10]

            side_a = src_label or "Source"
            side_b = dst_label or "Destination"
            dst_name = self._dest_labels.get(dst, dst)
            if src and dst and src != dst:
                title = f"INTERCONNECT   {src}  ➜  {dst_name}   —   {side_a}  ↔  {side_b}"
                style = self._LINK_HDR_STYLE
            elif src:
                head = f"{src}  ➜  {dst_name}" if dst_name != src else src
                title = f"{head}   —   {side_a}  ↔  {side_b}"
                style = self._HDR_STYLE
            else:
                title = "CONTINUITY   (Source Pins  ↔  Destination Pins)"
                style = self._HDR_STYLE

            sec = _ConnectorSection(title, style)
            sec.canvas.set_connections(
                _build_rows(pairs),
                f"{src}  {side_a}" if src else side_a,
                f"{dst_name}  {side_b}" if dst else side_b,
                src_part, dst_part)
            self._stack.insertWidget(self._stack.count() - 1, sec)
            self._sections.append(sec)

    # ── Legend ────────────────────────────────────────────────────────────────

    def _build_legend(self) -> QWidget:
        from ui.matrix_view import _LEGEND_ORDER
        w = QWidget()
        w.setFixedHeight(22)
        from PyQt6.QtWidgets import QHBoxLayout
        lay = QHBoxLayout(w)
        lay.setContentsMargins(8, 0, 8, 0)
        lay.setSpacing(12)
        lay.addStretch()
        for state in _LEGEND_ORDER:
            dot = QLabel("●")
            dot.setStyleSheet(
                f"color:{_STATE_COLOR[state].name()}; font-size:13px;")
            lbl = QLabel(_STATE_LABEL[state])
            lbl.setStyleSheet("font-size:9px; color:#999;")
            lay.addWidget(dot)
            lay.addWidget(lbl)
        lay.addStretch()
        return w


# ── Helper ─────────────────────────────────────────────────────────────────────

def _connector_prefix(net_name: str) -> str:
    if " / " in net_name:
        return net_name.split(" / ", 1)[0]
    return ""


def _source_pairs_only(pairs: list[tuple]) -> list[tuple]:
    """Keep only the pairs that are real wires.

    A net with one source pin and several destinations expands (in firmware
    and in the GUI) to every pin combination, including destination-to-
    destination pairs that are not physical wires.  They must be dropped
    *before* pairs are split up per connector, or a dst-to-dst pair between
    two different connectors would surface as a phantom interconnect.
    Mirrors the Y-joint rule in _build_rows.
    """
    kept: list[tuple] = []
    for _net, grp in groupby(pairs, key=lambda pr: pr[2]):
        group = list(grp)
        src_pin = group[0][0]
        branches = [pr for pr in group if pr[0] == src_pin]
        kept.extend(branches if len(branches) >= 2 else group)
    return kept


def _build_rows(pairs: list[tuple]) -> list[_Net | _Row | _Gap]:
    """Convert sorted pair list → interleaved net headers + connection rows.

    Accepts 5-element (pin_a, pin_b, net, name_a, name_b),
    7-element (…, source, destination),
    9-element (…, display_pin_a, display_pin_b),
    11-element (…, part_number_a, part_number_b) or
    14-element (…, conn_id, conn_id_b, wire_colour) tuples.
    Inserts a visual gap when the connector prefix of the net name changes.
    """
    rows: list[_Net | _Row | _YNet | _Gap] = []
    current_conn = None

    # Pairs arrive sorted by net (see MainWindow._load_wiring_diagram), so a
    # net's pairs are always contiguous.
    for net_name, grp in groupby(pairs, key=lambda pr: pr[2]):
        group = list(grp)
        conn = _connector_prefix(net_name)
        if current_conn is not None and conn and conn != current_conn:
            rows.append(_Gap())
        rows.append(_Net(net_name, group[0][13] if len(group[0]) >= 14 else ""))
        current_conn = conn

        src_pin  = group[0][0]
        branches = [pr for pr in group if pr[0] == src_pin]

        if len(branches) >= 2:
            # Y-joint.  Only pairs that involve the source are real wires —
            # the destination-to-destination combinations the firmware also
            # expands for a 3+ pin net are not physical connections and are
            # deliberately not drawn.
            first = branches[0]
            rows.append(_YNet(
                net=net_name,
                pin_a=src_pin,
                name_a=first[3],
                display_pin_a=first[7] if len(first) >= 9 else 0,
                branches=[(pr[1], pr[4], pr[8] if len(pr) >= 9 else 0)
                          for pr in branches],
            ))
        else:
            for pr in group:
                rows.append(_Row(pr[0], pr[1], net_name, pr[3], pr[4],
                                 pr[7] if len(pr) >= 9 else 0,
                                 pr[8] if len(pr) >= 9 else 0))
    return rows
