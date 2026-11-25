"""TestControlBar — QToolBar with test-mode selector and action buttons."""
from __future__ import annotations

from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (
    QToolBar, QLabel, QPushButton, QProgressBar, QComboBox,
)


class TestControlBar(QToolBar):
    startRequested = pyqtSignal()
    stopRequested  = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__("Test Controls", parent)
        self.setMovable(False)
        self.setFloatable(False)
        self._build()

    def _build(self) -> None:
        self.addWidget(QLabel("  Mode: "))

        self._cb_mode = QComboBox()
        self._cb_mode.addItem("Continuity (one-to-one)",       "continuity")
        self._cb_mode.addItem("Cross Continuity (one-to-many)", "cross")
        self._cb_mode.setToolTip(
            "Continuity: checks expected netlist pairs sequentially.\n"
            "Cross Continuity: drives each Side-A pin and reads all Side-B pins."
        )
        self._cb_mode.setMinimumWidth(210)
        self.addWidget(self._cb_mode)

        self.addSeparator()

        btn_font = QFont()
        btn_font.setPointSize(10)
        btn_font.setBold(True)

        self._btn_start = QPushButton("  START TEST  ")
        self._btn_start.setFont(btn_font)
        self._btn_start.setMinimumHeight(30)
        self._btn_start.setToolTip("Start test sequence (F5)")
        self._btn_start.setAccessibleName("Start test button")
        self._btn_start.setStyleSheet(
            "QPushButton { background-color: #1a6b2a; color: white;"
            " border-radius: 4px; padding: 0 8px; }"
            "QPushButton:hover { background-color: #28a745; }"
            "QPushButton:disabled { background-color: #3a4a3a; color: #666; }"
        )
        self._btn_start.setEnabled(False)
        self._btn_start.clicked.connect(self.startRequested)
        self.addWidget(self._btn_start)

        self._btn_stop = QPushButton("  STOP / ABORT  ")
        self._btn_stop.setFont(btn_font)
        self._btn_stop.setMinimumHeight(30)
        self._btn_stop.setToolTip("Stop or abort the current test (F6)")
        self._btn_stop.setAccessibleName("Stop test button")
        self._btn_stop.setStyleSheet(
            "QPushButton { background-color: #6b1a1a; color: white;"
            " border-radius: 4px; padding: 0 8px; }"
            "QPushButton:hover { background-color: #dc3545; }"
            "QPushButton:disabled { background-color: #4a3a3a; color: #666; }"
        )
        self._btn_stop.setEnabled(False)
        self._btn_stop.clicked.connect(self.stopRequested)
        self.addWidget(self._btn_stop)

        self.addSeparator()

        self._progress = QProgressBar()
        self._progress.setRange(0, 100)
        self._progress.setValue(0)
        self._progress.setTextVisible(True)
        self._progress.setMinimumWidth(160)
        self._progress.setMaximumWidth(220)
        self._progress.setToolTip("Test progress")
        self._progress.setAccessibleName("Test progress bar")
        self._progress.setVisible(False)
        self.addWidget(self._progress)

        self._lbl_duration = QLabel("  Duration: —  ")
        self.addWidget(self._lbl_duration)

        self.addSeparator()

        verdict_font = QFont()
        verdict_font.setPointSize(13)
        verdict_font.setBold(True)
        self._lbl_verdict = QLabel("  —  ")
        self._lbl_verdict.setFont(verdict_font)
        self._lbl_verdict.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._lbl_verdict.setMinimumWidth(110)
        self._lbl_verdict.setToolTip("Test verdict")
        self._lbl_verdict.setAccessibleName("Verdict display")
        self._lbl_verdict.setStyleSheet(
            "QLabel { background-color: #555; color: #ccc;"
            " border-radius: 4px; padding: 2px 10px; }"
        )
        self.addWidget(self._lbl_verdict)

    # ------------------------------------------------------------------
    # Public API (same interface as before)
    # ------------------------------------------------------------------

    def set_verdict(self, verdict: str) -> None:
        colors = {
            "PASS":         ("white",   "#28a745"),
            "FAIL":         ("white",   "#dc3545"),
            "INCONCLUSIVE": ("#1c1c1c", "#fd7e14"),
        }
        fg, bg = colors.get(verdict, ("#ccc", "#555"))
        self._lbl_verdict.setText(f"  {verdict or '—'}  ")
        self._lbl_verdict.setStyleSheet(
            f"QLabel {{ background-color: {bg}; color: {fg};"
            " border-radius: 4px; padding: 2px 10px; }"
        )

    @staticmethod
    def _fmt_duration(elapsed_s: float) -> str:
        """Return a human-friendly duration string using µs, ms, or s as appropriate."""
        if elapsed_s < 0.001:
            return f"{int(elapsed_s * 1_000_000):,} µs"
        if elapsed_s < 1.0:
            return f"{elapsed_s * 1000:.1f} ms"
        return f"{elapsed_s:.2f} s"

    def set_progress(self, done: int, total: int, elapsed_s: float = 0) -> None:
        if total > 0:
            pct = int(done * 100 / total)
            self._progress.setValue(pct)
            self._progress.setFormat(f"{pct}%  ({done}/{total})")
        self._lbl_duration.setText(f"  Duration: {self._fmt_duration(elapsed_s)}  ")

    def set_controls_enabled(self, idle: bool) -> None:
        self._btn_stop.setEnabled(not idle)
        self._progress.setVisible(not idle)
        if not idle:
            self._btn_start.setEnabled(False)

    def set_start_enabled(self, enabled: bool) -> None:
        self._btn_start.setEnabled(enabled)

    def set_auto_mode(self, is_auto: bool) -> None:
        """Disable Cross Continuity option when Auto-Scan mode is active."""
        model = self._cb_mode.model()
        cross_item = model.item(1)
        cross_item.setEnabled(not is_auto)
        if is_auto and self._cb_mode.currentIndex() == 1:
            self._cb_mode.setCurrentIndex(0)

    def get_test_modes(self):
        from core.data_types import TestModes
        mode = self._cb_mode.currentData()
        return TestModes(
            continuity=(mode == "continuity"),
            cross_continuity=(mode == "cross"),
            r_limit_mohm=0.0,
        )
