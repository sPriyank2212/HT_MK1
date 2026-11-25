"""PDF report generation for Harness Tester results."""

from __future__ import annotations

import os
import traceback
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable
from xml.sax.saxutils import escape

from PyQt6.QtCore import QObject, QThread, pyqtSignal
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter, landscape
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.pdfgen.canvas import Canvas
from reportlab.platypus import (
    Image,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

from .data_types import ResultStatus, TestResult
from .result_model import (
    HEADERS,
    COL_NUM, COL_SOURCE, COL_CONN_ID, COL_PART_NUMBER, COL_PIN_A_NAME, COL_PIN_A,
    COL_STATUS, COL_PIN_B, COL_PIN_B_NAME, COL_CONN_ID_B, COL_PART_NUMBER_B, COL_DEST,
    COL_COLOUR, COL_AWG, COL_LENGTH, COL_HARNESS_NO,
)


@dataclass
class ReportMetadata:
    dut_id: str = ""
    operator: str = ""
    profile: str = ""
    netlist_name: str = ""
    fw_version: str = ""
    verdict: str = ""
    timestamp: datetime | None = None
    duration_s: float = 0.0


def _safe(val):
    """Return a string safe for PDF cells."""
    if val is None:
        return ""
    return str(val)


_LABEL_STYLE = ParagraphStyle("pin_label", fontName="Helvetica", fontSize=6,
                              leading=7, alignment=1)   # 1 = centred


def _label(text: str) -> Paragraph:
    """A pin label that wraps inside its cell instead of running into the next one."""
    return Paragraph(escape(text), _LABEL_STYLE)


class _NumberedCanvas(Canvas):
    """Canvas that prints "Page n of N" at the foot of every page.

    N is only known once the last page exists, so each page is held back until
    save() and drawn then.
    """

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_pages: list[dict] = []

    def showPage(self):
        self._saved_pages.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        total = len(self._saved_pages)
        for state in self._saved_pages:
            self.__dict__.update(state)
            self.setFont("Helvetica", 8)
            self.setFillColor(colors.grey)
            self.drawCentredString(self._pagesize[0] / 2, 0.4 * inch,
                                   f"Page {self._pageNumber} of {total}")
            super().showPage()
        super().save()


def _end_of_report() -> list:
    """The closing line that tells the reader nothing follows."""
    style = ParagraphStyle("EndOfReport", fontName="Helvetica-Bold", fontSize=9,
                           textColor=colors.HexColor("#1F4E79"), alignment=1)
    return [Spacer(1, 0.25 * inch), Paragraph("End of the report", style)]


def _fmt_duration(seconds: float) -> str:
    """Format elapsed seconds as a human-readable string."""
    if seconds <= 0:
        return "—"
    if seconds < 1:
        return f"{int(seconds * 1000)} ms"
    if seconds < 60:
        return f"{seconds:.2f} s"
    m, s = divmod(int(seconds), 60)
    return f"{m}m {s:02d}s"


def generate_pdf(path: str | Path,
                 results: Iterable[TestResult],
                 metadata: ReportMetadata,
                 logo_path: str | Path | None = None) -> None:
    """Generate a PDF test report at *path*."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)

    # Landscape: the table has 16 columns, which do not fit a portrait page.
    doc = SimpleDocTemplate(
        str(path),
        pagesize=landscape(letter),
        rightMargin=0.4 * inch,
        leftMargin=0.4 * inch,
        topMargin=0.8 * inch,
        bottomMargin=0.8 * inch,
    )

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        "ReportTitle",
        parent=styles["Heading1"],
        fontSize=20,
        textColor=colors.HexColor("#1F4E79"),
        alignment=1,  # center
        spaceAfter=16,
    )
    subtitle_style = ParagraphStyle(
        "ReportSubtitle",
        parent=styles["Normal"],
        fontSize=12,
        textColor=colors.HexColor("#4472C4"),
        alignment=1,
        spaceAfter=20,
    )
    section_style = ParagraphStyle(
        "ReportSection",
        parent=styles["Heading2"],
        fontSize=13,
        textColor=colors.HexColor("#1F4E79"),
        spaceBefore=14,
        spaceAfter=8,
    )
    verdict_pass = ParagraphStyle("VerdictPass", parent=styles["Normal"], textColor=colors.green, fontSize=14, alignment=1)
    verdict_fail = ParagraphStyle("VerdictFail", parent=styles["Normal"], textColor=colors.red, fontSize=14, alignment=1)

    story = []

    # Logo / header — logo is square (1600x1600), render at equal width/height
    if logo_path and Path(logo_path).exists():
        img = Image(str(logo_path), width=1.2 * inch, height=1.2 * inch)
        img.hAlign = "CENTER"
        story.append(img)
    story.append(Spacer(1, 0.2 * inch))

    story.append(Paragraph("Harness Tester Test Report", title_style))
    story.append(Paragraph(f"DUT: {_safe(metadata.dut_id)}", subtitle_style))

    # Verdict banner
    verdict_para = Paragraph(
        f"VERDICT: {metadata.verdict or '—'}",
        verdict_pass if metadata.verdict == "PASS" else verdict_fail,
    )
    story.append(verdict_para)
    story.append(Spacer(1, 0.2 * inch))

    # Metadata table
    ts = metadata.timestamp or datetime.now()
    results = list(results)
    meta_data = [
        ["Date/Time:", ts.strftime("%Y-%m-%d %H:%M:%S")],
        ["Operator:", _safe(metadata.operator)],
        ["Profile:", _safe(metadata.profile)],
        ["Netlist:", _safe(metadata.netlist_name) or "(none / auto-scan)"],
        ["Test Duration:", _fmt_duration(metadata.duration_s)],
        ["Total Pins Tested:", str(len(results))],
    ]

    meta_table = Table(meta_data, colWidths=[1.6 * inch, 4.5 * inch])
    meta_table.setStyle(TableStyle([
        ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
        ("FONTNAME", (1, 0), (1, -1), "Helvetica"),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    story.append(meta_table)

    # Summary counts
    story.append(Paragraph("Summary", section_style))
    connected_count = sum(1 for r in results if r.status == ResultStatus.PASS)
    not_connected_count = sum(1 for r in results if r.status != ResultStatus.PASS)
    summary_data = [
        ["Total", "CONNECTED", "NOT CONNECTED"],
        [str(len(results)), str(connected_count), str(not_connected_count)],
    ]
    summary_table = Table(summary_data, colWidths=[1.73 * inch] * 3)
    summary_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1F4E79")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.whitesmoke),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("FONTSIZE", (0, 0), (-1, -1), 11),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
        ("BACKGROUND", (1, 1), (1, 1), colors.HexColor("#D5E8D4")),
        ("BACKGROUND", (2, 1), (2, 1), colors.HexColor("#F8CECC")),
    ]))
    story.append(summary_table)

    if not results:
        story.append(Spacer(1, 0.3 * inch))
        story.append(Paragraph("No results to display.", styles["Normal"]))
        story.extend(_end_of_report())
        doc.build(story, canvasmaker=_NumberedCanvas)
        return

    # Results table — cross-connection layout: source side → Status → destination side.
    story.append(Paragraph("Results", section_style))
    pdf_headers = [
        HEADERS[COL_NUM],
        HEADERS[COL_SOURCE],
        HEADERS[COL_PART_NUMBER],
        HEADERS[COL_CONN_ID],
        HEADERS[COL_PIN_A_NAME],
        HEADERS[COL_PIN_A],
        HEADERS[COL_STATUS],
        HEADERS[COL_PIN_B],
        HEADERS[COL_PIN_B_NAME],
        HEADERS[COL_CONN_ID_B],
        HEADERS[COL_PART_NUMBER_B],
        HEADERS[COL_DEST],
        HEADERS[COL_COLOUR],
        HEADERS[COL_AWG],
        HEADERS[COL_LENGTH],
        HEADERS[COL_HARNESS_NO],
    ]
    _STATUS_LABELS = {
        ResultStatus.PASS:          "CONNECTED",
        ResultStatus.FAIL:          "NOT CONNECTED",
        ResultStatus.OPEN:          "NOT CONNECTED",
        ResultStatus.MISWIRE:       "NOT CONNECTED",
        ResultStatus.NOT_CONNECTED: "NOT CONNECTED",
    }
    table_data = [pdf_headers]
    status_col = 6  # index of the Status column in the row layout above
    for r in results:
        status = _STATUS_LABELS.get(r.status, "")
        disp_a = r.display_pin_a or r.pin_a
        disp_b = r.display_pin_b or r.pin_b
        table_data.append([
            str(r.test_num),
            _safe(r.source),
            _safe(r.connector_part_number),
            _safe(r.connector_id),
            _label(_safe(r.pin_a_name) or f"Pin {disp_a}"),
            str(disp_a),
            status,
            str(disp_b),
            _label(_safe(r.pin_b_name) or f"Pin {disp_b}"),
            _safe(r.connector_id_b),
            _safe(r.connector_part_number_b),
            _safe(r.destination),
            _safe(r.wire_colour),
            _safe(r.awg),
            _safe(r.length),
            _safe(r.harness_no),
        ])

    # Landscape letter leaves 10.2 in between the margins.
    results_table = Table(
        table_data,
        colWidths=[
            0.40 * inch,  # Test #
            0.55 * inch,  # Source
            1.00 * inch,  # Part Number
            0.50 * inch,  # Conn ID
            0.85 * inch,  # Src Pin Label
            0.45 * inch,  # Src Pin #
            0.95 * inch,  # Status
            0.45 * inch,  # Dst Pin #
            0.85 * inch,  # Dst Pin Label
            0.50 * inch,  # Conn ID
            1.00 * inch,  # Part Number B
            0.60 * inch,  # Destination
            0.55 * inch,  # Colour
            0.40 * inch,  # AWG
            0.50 * inch,  # Length
            0.65 * inch,  # Harness No
        ],
        repeatRows=1,
    )
    style_cmds = [
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1F4E79")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.whitesmoke),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, 0), 7),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("FONTSIZE", (0, 1), (-1, -1), 7.5),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("LEFTPADDING", (0, 0), (-1, -1), 3),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3),
    ]
    # Colour-code the Status cell per row (green PASS, red otherwise).
    for i, r in enumerate(results, start=1):
        bg = colors.HexColor("#D5E8D4") if r.status == ResultStatus.PASS else colors.HexColor("#F8CECC")
        style_cmds.append(("BACKGROUND", (status_col, i), (status_col, i), bg))
        style_cmds.append(("FONTNAME", (status_col, i), (status_col, i), "Helvetica-Bold"))
    results_table.setStyle(TableStyle(style_cmds))
    story.append(results_table)
    story.extend(_end_of_report())

    doc.build(story, canvasmaker=_NumberedCanvas)


class ReportWorker(QObject):
    """Runs PDF generation in a background thread."""
    finished = pyqtSignal(str)
    error = pyqtSignal(str)

    def __init__(self, path: str, results, metadata: ReportMetadata, logo_path: str | None = None):
        super().__init__()
        self._path = path
        self._results = results
        self._metadata = metadata
        self._logo_path = logo_path

    def run(self) -> None:
        try:
            generate_pdf(self._path, self._results, self._metadata, self._logo_path)
            self.finished.emit(self._path)
        except Exception as exc:
            self.error.emit(f"{exc}\n{traceback.format_exc()}")


def run_pdf_worker(path: str,
                   results,
                   metadata: ReportMetadata,
                   logo_path: str | None = None,
                   parent=None) -> QThread:
    """Start a background thread that generates the PDF. Returns the QThread."""
    thread = QThread(parent)
    worker = ReportWorker(path, results, metadata, logo_path)
    worker.moveToThread(thread)
    thread.started.connect(worker.run)
    worker.finished.connect(thread.quit)
    worker.finished.connect(worker.deleteLater)
    thread.finished.connect(thread.deleteLater)
    worker.error.connect(thread.quit)
    worker.error.connect(worker.deleteLater)
    thread.start()
    return thread, worker
