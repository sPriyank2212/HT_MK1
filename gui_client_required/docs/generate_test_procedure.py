#!/usr/bin/env python3
"""
generate_test_procedure.py
Generates: FTP-HT-MK0-v1.0.docx  — Functional Test Procedure, Harness Tester MK0
Run from anywhere; output drops into the same folder as this script.
"""

import os
import tempfile
import urllib.request

from docx import Document
from docx.shared import Pt, Cm, RGBColor, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
OUTPUT_PATH = os.path.join(SCRIPT_DIR, "FTP-HT-MK0-v1.0.docx")
LOGO_PATH   = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "resources", "company_logo.jpeg"))
GUI_SS_DIR  = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "..", "GUI_SS"))

def gui_ss(filename):
    """Return absolute path to a GUI screenshot, or None if missing."""
    p = os.path.join(GUI_SS_DIR, filename)
    return p if os.path.exists(p) else None

BOARD_IMAGE_URL = (
    "https://os.mbed.com/media/cache/platforms/"
    "Nucleo144_perf_logo_1024_-_NO_ETHERNET_Ceqzy5i.jpg.250x250_q85.jpg"
)

# ---------------------------------------------------------------------------
# Design tokens
# ---------------------------------------------------------------------------
FONT_NAME  = "Calibri"
SZ_BODY    = 14
SZ_H1      = 18
SZ_H2      = 16
SZ_H3      = 14
SZ_TABLE   = 13
SZ_CAPTION = 12
SZ_FOOTER  = 11

C_NAVY      = RGBColor(0x1F, 0x35, 0x64)
C_MID_BLUE  = RGBColor(0x2E, 0x74, 0xB5)
C_WARN      = RGBColor(0xFF, 0xF2, 0xCC)
C_NOTE      = RGBColor(0xE2, 0xEF, 0xDA)
C_PASS      = RGBColor(0xE2, 0xEF, 0xDA)
C_FAIL      = RGBColor(0xFF, 0xCC, 0xCC)
C_WHITE     = RGBColor(0xFF, 0xFF, 0xFF)
C_BLACK     = RGBColor(0x00, 0x00, 0x00)
C_LGRAY     = RGBColor(0xF2, 0xF2, 0xF2)
C_DGRAY     = RGBColor(0x60, 0x60, 0x60)
C_YELLOW    = RGBColor(0xFF, 0xFF, 0xCC)

# ---------------------------------------------------------------------------
# Image download helper
# ---------------------------------------------------------------------------

def download_image(url, suffix=".jpg"):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
            tmp.write(resp.read())
            tmp.close()
            return tmp.name
    except Exception:
        return None

# ---------------------------------------------------------------------------
# Low-level XML helpers
# ---------------------------------------------------------------------------

def set_cell_bg(cell, rgb: RGBColor):
    tc   = cell._tc
    tcPr = tc.get_or_add_tcPr()
    shd  = OxmlElement("w:shd")
    shd.set(qn("w:val"),   "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"),  f"{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}")
    tcPr.append(shd)


def set_cell_border(cell, **borders):
    tc   = cell._tc
    tcPr = tc.get_or_add_tcPr()
    tcBorders = OxmlElement("w:tcBorders")
    for edge, val in borders.items():
        bd = OxmlElement(f"w:{edge}")
        bd.set(qn("w:val"),   val.get("val",   "single"))
        bd.set(qn("w:sz"),    val.get("sz",    "4"))
        bd.set(qn("w:space"), val.get("space", "0"))
        bd.set(qn("w:color"), val.get("color", "auto"))
        tcBorders.append(bd)
    tcPr.append(tcBorders)


def add_page_break(doc):
    doc.add_page_break()


def add_footer_page_num(doc, doc_number: str):
    section = doc.sections[-1]
    section.footer_distance = Cm(1.27)
    footer  = section.footer
    ft_para = footer.paragraphs[0]
    ft_para.clear()
    ft_para.alignment = WD_ALIGN_PARAGRAPH.LEFT
    run = ft_para.add_run(doc_number + "    ")
    run.font.name = FONT_NAME; run.font.size = Pt(SZ_FOOTER); run.font.color.rgb = C_DGRAY
    run2 = ft_para.add_run()
    run2.font.name = FONT_NAME; run2.font.size = Pt(SZ_FOOTER); run2.font.color.rgb = C_DGRAY
    fldChar1  = OxmlElement("w:fldChar"); fldChar1.set(qn("w:fldCharType"), "begin")
    instrText = OxmlElement("w:instrText"); instrText.text = "PAGE"
    fldChar2  = OxmlElement("w:fldChar"); fldChar2.set(qn("w:fldCharType"), "end")
    run2._r.append(fldChar1); run2._r.append(instrText); run2._r.append(fldChar2)


def hr_line(doc):
    para = doc.add_paragraph()
    pPr  = para._p.get_or_add_pPr()
    pBdr = OxmlElement("w:pBdr")
    bot  = OxmlElement("w:bottom")
    bot.set(qn("w:val"),   "single"); bot.set(qn("w:sz"), "6")
    bot.set(qn("w:space"), "1"); bot.set(qn("w:color"), "1F3564")
    pBdr.append(bot); pPr.append(pBdr)
    return para

# ---------------------------------------------------------------------------
# Style helpers
# ---------------------------------------------------------------------------

def _run_font(run, size, bold=False, italic=False, color=None):
    run.font.name = FONT_NAME; run.font.size = Pt(size)
    run.font.bold = bold; run.font.italic = italic
    if color: run.font.color.rgb = color


def body_para(doc, text, bold=False, italic=False, color=None):
    p = doc.add_paragraph()
    p.paragraph_format.space_after  = Pt(6)
    p.paragraph_format.space_before = Pt(0)
    run = p.add_run(text)
    _run_font(run, SZ_BODY, bold=bold, italic=italic, color=color or C_BLACK)
    return p


def bullet_para(doc, text, level=0, bold=False):
    p = doc.add_paragraph(style="List Bullet")
    p.paragraph_format.space_after = Pt(3)
    p.paragraph_format.left_indent = Cm(0.63 + level * 0.63)
    run = p.add_run(text)
    _run_font(run, SZ_BODY, bold=bold)
    return p


def numbered_para(doc, text, bold=False):
    p = doc.add_paragraph(style="List Number")
    p.paragraph_format.space_after = Pt(4)
    run = p.add_run(text)
    _run_font(run, SZ_BODY, bold=bold)
    return p


def h1(doc, text):
    p   = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(18)
    p.paragraph_format.space_after  = Pt(6)
    run = p.add_run(text)
    _run_font(run, SZ_H1, bold=True, color=C_NAVY)
    hr_line(doc)
    return p


def h2(doc, text):
    p   = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(12)
    p.paragraph_format.space_after  = Pt(4)
    run = p.add_run(text)
    _run_font(run, SZ_H2, bold=True, color=C_NAVY)
    return p


def h3(doc, text):
    p   = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(8)
    p.paragraph_format.space_after  = Pt(3)
    run = p.add_run(text)
    _run_font(run, SZ_H3, bold=True, color=C_MID_BLUE)
    return p


def warning_box(doc, text):
    tbl  = doc.add_table(rows=1, cols=1)
    cell = tbl.cell(0, 0)
    set_cell_bg(cell, C_WARN)
    para = cell.paragraphs[0]
    run  = para.add_run("⚠  " + text)
    run.font.name = FONT_NAME; run.font.size = Pt(SZ_BODY)
    run.font.bold = True; run.font.color.rgb = RGBColor(0x7F, 0x60, 0x00)
    cell.paragraphs[0].paragraph_format.space_before = Pt(4)
    cell.paragraphs[0].paragraph_format.space_after  = Pt(4)
    doc.add_paragraph()


def note_box(doc, text):
    tbl  = doc.add_table(rows=1, cols=1)
    cell = tbl.cell(0, 0)
    set_cell_bg(cell, C_NOTE)
    para = cell.paragraphs[0]
    run  = para.add_run("NOTE:  " + text)
    run.font.name = FONT_NAME; run.font.size = Pt(SZ_BODY)
    run.font.color.rgb = RGBColor(0x37, 0x5A, 0x1F)
    cell.paragraphs[0].paragraph_format.space_before = Pt(4)
    cell.paragraphs[0].paragraph_format.space_after  = Pt(4)
    doc.add_paragraph()


def insert_image(doc, img_path, caption, width_cm=14.0):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.add_run().add_picture(img_path, width=Cm(width_cm))
    cap = doc.add_paragraph()
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = cap.add_run(caption)
    r.font.name = FONT_NAME; r.font.size = Pt(SZ_CAPTION)
    r.font.italic = True; r.font.color.rgb = C_DGRAY
    doc.add_paragraph()


def screenshot_placeholder(doc, instruction, height_cm=6.0):
    tbl  = doc.add_table(rows=1, cols=1)
    cell = tbl.cell(0, 0)
    set_cell_bg(cell, C_LGRAY)
    bdr = {s: {"val": "dashed", "sz": "6", "color": "888888"}
           for s in ("top", "bottom", "left", "right")}
    set_cell_border(cell, **bdr)
    para = cell.paragraphs[0]
    para.alignment = WD_ALIGN_PARAGRAPH.CENTER
    para.paragraph_format.space_before = Pt(int(height_cm * 6))
    para.paragraph_format.space_after  = Pt(int(height_cm * 6))
    run  = para.add_run(f"[ SCREENSHOT — {instruction} ]")
    run.font.name = FONT_NAME; run.font.size = Pt(SZ_CAPTION)
    run.font.italic = True; run.font.color.rgb = C_DGRAY
    doc.add_paragraph()


def table_header_row(row, *col_texts, bg=C_NAVY, fg=C_WHITE):
    for i, txt in enumerate(col_texts):
        cell = row.cells[i]
        set_cell_bg(cell, bg)
        para = cell.paragraphs[0]
        para.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run  = para.add_run(txt)
        run.font.name = FONT_NAME; run.font.size = Pt(SZ_TABLE)
        run.font.bold = True; run.font.color.rgb = fg


def table_data_row(row, *col_texts, bg=None):
    for i, txt in enumerate(col_texts):
        cell = row.cells[i]
        if bg: set_cell_bg(cell, bg)
        run = cell.paragraphs[0].add_run(str(txt))
        run.font.name = FONT_NAME; run.font.size = Pt(SZ_TABLE)


def test_case_table(doc, tc_id, title, objective, preconditions, steps, expected, result_field=True):
    """Render a single test case as a bordered table."""
    h3(doc, f"{tc_id}  —  {title}")

    # Header row: TC ID + title (merged)
    tbl = doc.add_table(rows=1, cols=2)
    tbl.style = "Table Grid"
    hdr = tbl.rows[0]
    set_cell_bg(hdr.cells[0], C_NAVY)
    set_cell_bg(hdr.cells[1], C_NAVY)
    r0 = hdr.cells[0].paragraphs[0].add_run("Test Case ID")
    r0.font.name = FONT_NAME; r0.font.size = Pt(SZ_TABLE); r0.font.bold = True; r0.font.color.rgb = C_WHITE
    r1 = hdr.cells[1].paragraphs[0].add_run(tc_id)
    r1.font.name = FONT_NAME; r1.font.size = Pt(SZ_TABLE); r1.font.bold = True; r1.font.color.rgb = C_WHITE

    def add_row(label, content, bg=None):
        row = tbl.add_row()
        if bg: set_cell_bg(row.cells[0], bg); set_cell_bg(row.cells[1], bg)
        la = row.cells[0].paragraphs[0].add_run(label)
        la.font.name = FONT_NAME; la.font.size = Pt(SZ_TABLE); la.font.bold = True
        co = row.cells[1].paragraphs[0].add_run(content)
        co.font.name = FONT_NAME; co.font.size = Pt(SZ_TABLE)

    add_row("Objective",       objective,     bg=C_LGRAY)
    add_row("Pre-conditions",  preconditions)

    # Steps
    steps_row = tbl.add_row()
    set_cell_bg(steps_row.cells[0], C_LGRAY)
    set_cell_bg(steps_row.cells[1], C_LGRAY)
    la = steps_row.cells[0].paragraphs[0].add_run("Steps")
    la.font.name = FONT_NAME; la.font.size = Pt(SZ_TABLE); la.font.bold = True
    cell = steps_row.cells[1]
    cell.paragraphs[0].clear()
    for idx, step in enumerate(steps, start=1):
        p = cell.add_paragraph() if idx > 1 else cell.paragraphs[0]
        r = p.add_run(f"{idx}. {step}")
        r.font.name = FONT_NAME; r.font.size = Pt(SZ_TABLE)

    add_row("Expected Result", expected)

    if result_field:
        result_row = tbl.add_row()
        set_cell_bg(result_row.cells[0], C_YELLOW)
        set_cell_bg(result_row.cells[1], C_YELLOW)
        la = result_row.cells[0].paragraphs[0].add_run("Actual Result / Pass-Fail")
        la.font.name = FONT_NAME; la.font.size = Pt(SZ_TABLE); la.font.bold = True
        co = result_row.cells[1].paragraphs[0].add_run("PASS  /  FAIL  (circle one)     Notes: ________________________________")
        co.font.name = FONT_NAME; co.font.size = Pt(SZ_TABLE)

    doc.add_paragraph()

# ---------------------------------------------------------------------------
# Page setup
# ---------------------------------------------------------------------------

def setup_page(doc):
    for section in doc.sections:
        section.page_height   = Cm(29.7)
        section.page_width    = Cm(21.0)
        section.left_margin   = Cm(2.54)
        section.right_margin  = Cm(2.54)
        section.top_margin    = Cm(2.54)
        section.bottom_margin = Cm(2.54)

# ---------------------------------------------------------------------------
# Cover page
# ---------------------------------------------------------------------------

def add_cover_page(doc):
    section = doc.sections[0]
    section.different_first_page_header_footer = True

    if os.path.exists(LOGO_PATH):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
        p.add_run().add_picture(LOGO_PATH, height=Cm(2.0))
    else:
        p = doc.add_paragraph("[COMPANY LOGO]")
        p.runs[0].font.size = Pt(14); p.runs[0].font.color.rgb = C_DGRAY

    doc.add_paragraph(); doc.add_paragraph(); doc.add_paragraph()
    hr_line(doc)

    p = doc.add_paragraph()
    run = p.add_run("FUNCTIONAL TEST PROCEDURE")
    run.font.name = FONT_NAME; run.font.size = Pt(13)
    run.font.bold = True; run.font.color.rgb = C_MID_BLUE

    p = doc.add_paragraph()
    run = p.add_run("Harness Tester")
    run.font.name = FONT_NAME; run.font.size = Pt(32)
    run.font.bold = True; run.font.color.rgb = C_NAVY

    p = doc.add_paragraph()
    run = p.add_run("MK0  |  Proof of Concept  |  Nucleo-F303ZE")
    run.font.name = FONT_NAME; run.font.size = Pt(18); run.font.color.rgb = C_MID_BLUE

    hr_line(doc)
    for _ in range(6): doc.add_paragraph()

    tbl  = doc.add_table(rows=7, cols=2)
    tbl.alignment = WD_TABLE_ALIGNMENT.LEFT
    info = [
        ("Document Number",  "FTP-HT-MK0-v1.0"),
        ("Version",          "1.0"),
        ("Date",             "July 2026"),
        ("Status",           "Released"),
        ("Product",          "Harness Tester MK0 (Nucleo-F303ZE POC)"),
        ("Firmware Version", "v2.0.0"),
        ("Prepared by",      "Engineering Team"),
    ]
    for i, (label, value) in enumerate(info):
        row = tbl.rows[i]
        row.cells[0].width = Cm(5.5); row.cells[1].width = Cm(10.0)
        r0 = row.cells[0].paragraphs[0].add_run(label)
        r0.font.name = FONT_NAME; r0.font.size = Pt(SZ_BODY)
        r0.font.bold = True; r0.font.color.rgb = C_NAVY
        r1 = row.cells[1].paragraphs[0].add_run(value)
        r1.font.name = FONT_NAME; r1.font.size = Pt(SZ_BODY); r1.font.color.rgb = C_BLACK

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Document control
# ---------------------------------------------------------------------------

def add_doc_control(doc):
    h1(doc, "1.  Document Control")

    h2(doc, "1.1  Revision History")
    tbl = doc.add_table(rows=2, cols=5)
    tbl.style = "Table Grid"
    table_header_row(tbl.rows[0], "Version", "Date", "Author", "Section(s)", "Description")
    table_data_row(tbl.rows[1], "1.0", "July 2026", "Engineering Team", "All", "Initial release")
    doc.add_paragraph()

    h2(doc, "1.2  Related Documents")
    tbl2 = doc.add_table(rows=4, cols=3)
    tbl2.style = "Table Grid"
    table_header_row(tbl2.rows[0], "Document Number", "Title", "Version")
    refs = [
        ("UM-HT-MK0-v1.0",  "User Manual, Harness Tester MK0",              "1.0"),
        ("FFP-HT-MK0-v1.0", "Firmware Flash Procedure, Harness Tester MK0", "1.0"),
        ("UM1974",           "STM32 Nucleo-144 Boards User Manual",          "Latest"),
    ]
    for i, row_data in enumerate(refs, start=1):
        table_data_row(tbl2.rows[i], *row_data)
    doc.add_paragraph()
    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 2 — Introduction
# ---------------------------------------------------------------------------

def add_section_2(doc):
    h1(doc, "2.  Introduction")

    h2(doc, "2.1  Purpose")
    body_para(doc,
        "This document defines the functional test procedure for the Harness Tester "
        "MK0 system. It describes the test cases to be executed to verify that the "
        "firmware, GUI, and communication protocol are operating correctly after "
        "firmware installation or any software update.")

    h2(doc, "2.2  Scope")
    body_para(doc,
        "This procedure covers the following test areas:")
    bullet_para(doc, "Firmware communication (PING, STATUS, firmware version)")
    bullet_para(doc, "Calibration command")
    bullet_para(doc, "Continuity test — PASS scenario (connections present)")
    bullet_para(doc, "Continuity test — OPEN FAULT scenario (connection missing)")
    bullet_para(doc, "Short circuit test — SHORT FAULT scenario")
    bullet_para(doc, "Auto-scan (no netlist required)")
    bullet_para(doc, "CSV report generation")
    bullet_para(doc, "PDF report generation")
    doc.add_paragraph()

    warning_box(doc,
        "MK0 does not support resistance measurement or HV insulation testing. "
        "Do not select these modes during testing. They are out of scope for this "
        "procedure.")

    h2(doc, "2.3  Test Environment")
    body_para(doc,
        "All tests are performed on the bench with the Nucleo-F303ZE board connected "
        "via USB to a PC running Windows 10 or Windows 11. Jumper wires are used to "
        "simulate harness connections directly on the Morpho headers. No live harness "
        "or external voltages are required.")

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 3 — Equipment and Materials
# ---------------------------------------------------------------------------

def add_section_3(doc, board_img_path):
    h1(doc, "3.  Equipment and Materials")

    h2(doc, "3.1  Hardware")
    tbl = doc.add_table(rows=5, cols=3)
    tbl.style = "Table Grid"
    table_header_row(tbl.rows[0], "Item", "Description", "Qty")
    hw = [
        ("NUCLEO-F303ZE",       "STM32F303ZE Nucleo-144 board, firmware v2.0.0 installed", "1"),
        ("USB cable",           "USB-A to USB-B Mini", "1"),
        ("PC",                  "Windows 10/11, 64-bit, one free USB-A port", "1"),
        ("Jumper wires (DuPont)","2.54 mm female-to-female Dupont wires, 150 mm length", "10"),
    ]
    for i, row_data in enumerate(hw, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        table_data_row(tbl.rows[i], *row_data, bg=bg)
    doc.add_paragraph()

    if board_img_path:
        insert_image(doc, board_img_path,
                     "Figure 1 — NUCLEO-F303ZE development board used for MK0 testing "
                     "(source: mbed.com)", width_cm=12.0)
    else:
        screenshot_placeholder(doc,
            "Photo of the NUCLEO-F303ZE Nucleo-144 board with Morpho headers "
            "CN7 and CN10 labelled, jumper wires installed for test case TC-003.",
            height_cm=6.0)

    h2(doc, "3.2  Software")
    tbl2 = doc.add_table(rows=3, cols=2)
    tbl2.style = "Table Grid"
    table_header_row(tbl2.rows[0], "Software", "Version / Notes")
    sw = [
        ("HarnessTester.exe", "Pre-built GUI executable (or run via python main.py)"),
        ("Test netlist file",  "poc_1wire_test.json — located in netlists\\ folder"),
    ]
    for i, row_data in enumerate(sw, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        table_data_row(tbl2.rows[i], *row_data, bg=bg)
    doc.add_paragraph()

    h2(doc, "3.3  Test Wiring Reference")
    body_para(doc,
        "The table below lists the Morpho header pin pairs used in the test cases. "
        "Use female DuPont jumper wires to connect Side A pins to Side B pins "
        "as instructed by each test case.")

    tbl3 = doc.add_table(rows=6, cols=4)
    tbl3.style = "Table Grid"
    table_header_row(tbl3.rows[0], "Harness Pin #", "Side A GPIO", "Side B GPIO", "Test Used In")
    wiring = [
        ("1",  "PC8  (CN10 pin 2)",   "PC11 (CN7 pin 1)",   "TC-003, TC-004, TC-006"),
        ("2",  "PC9  (CN10 pin 1)",   "PC10 (CN7 pin 2)",   "TC-003, TC-005, TC-006"),
        ("3",  "PC6  (CN10 pin 4)",   "PD2  (CN7 pin 4)",   "TC-003"),
        ("4",  "PB8  (CN10 pin 3)",   "PC12 (CN7 pin 3)",   "TC-003"),
        ("5",  "PA12 (CN10 pin 12)",  "PC1  (CN10 pin 15)", "TC-003"),
    ]
    for i, row_data in enumerate(wiring, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        table_data_row(tbl3.rows[i], *row_data, bg=bg)
    doc.add_paragraph()
    note_box(doc,
        "Morpho header pin positions are approximate. Verify against UM1974 "
        "Table 16/17 for the exact physical location before inserting jumpers.")
    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 4 — Pre-Test Setup
# ---------------------------------------------------------------------------

def add_section_4(doc):
    h1(doc, "4.  Pre-Test Setup")

    h2(doc, "4.1  Hardware Setup")
    numbered_para(doc, "Place the Nucleo-F303ZE board on a clean, static-free work surface.")
    numbered_para(doc, "Confirm firmware v2.0.0 is installed. If not, follow FFP-HT-MK0-v1.0.")
    numbered_para(doc, "Connect the USB cable from CN1 to the PC. Wait for LD1 (green) to go solid ON.")
    numbered_para(doc,
        "Confirm the boot LED sequence: all three LEDs (LD1, LD2, LD3) blink "
        "three times together, then LD1 stays green. If this does not occur, "
        "reflash the firmware before continuing.")

    h2(doc, "4.2  Software Setup")
    numbered_para(doc,
        "Launch HarnessTester.exe on the PC. The GUI opens showing the "
        "not-connected state.")

    _ideal = gui_ss("GUI_IDEAL.png")
    if _ideal:
        insert_image(doc, _ideal,
                     "Figure 2 — Harness Tester GUI at launch: not connected, "
                     "no netlist loaded.", width_cm=14.0)
    else:
        screenshot_placeholder(doc,
            "Harness Tester GUI — initial not-connected state.", height_cm=5.0)

    numbered_para(doc,
        "In the Connection group box, click Refresh and select the STLink "
        "Virtual COM Port.")
    numbered_para(doc, "Set baud rate to 921600 and click Connect.")
    numbered_para(doc,
        "Confirm status shows 'CONNECTED — FW v2.0.0'. If it shows a "
        "different version, stop and reflash the correct firmware.")

    _conn = gui_ss("GUI_Connect.png")
    if _conn:
        insert_image(doc, _conn,
                     "Figure 3 — GUI after successful connection: status bar shows "
                     "'CONNECTED — FW v1.0.0' and the STLink COM port is selected.",
                     width_cm=14.0)
    else:
        screenshot_placeholder(doc,
            "Harness Tester GUI connected state — 'CONNECTED — FW v2.0.0'.",
            height_cm=5.0)

    h2(doc, "4.3  Loading the Test Netlist")
    numbered_para(doc,
        "Click Browse in the Netlist group box. The Load Netlist dialog "
        "opens as shown below.")

    _dlg = gui_ss("Load_netlist_1.png")
    if _dlg:
        insert_image(doc, _dlg,
                     "Figure 4 — Load Netlist file browser dialog. Navigate to "
                     "the netlists\\ folder and select the .json or .xlsx file.",
                     width_cm=13.0)
    else:
        screenshot_placeholder(doc,
            "Load Netlist dialog — file browser open.", height_cm=4.0)

    numbered_para(doc,
        "Navigate to netlists\\poc_1wire_test.json (or poc_test_4pairs.xlsx "
        "for multi-pair tests) and click Open.")
    numbered_para(doc,
        "Confirm the netlist tree in the left panel populates with the "
        "expected net names and the Connector View shows the wiring diagram.")

    _loaded = gui_ss("Loaded_netlist_2.png")
    if _loaded:
        insert_image(doc, _loaded,
                     "Figure 5 — GUI with netlist loaded: Connector View shows "
                     "Side A and Side B pins with the expected wire connections.",
                     width_cm=14.0)
    else:
        screenshot_placeholder(doc,
            "GUI Connector View with netlist loaded — wiring diagram visible.",
            height_cm=5.0)

    numbered_para(doc,
        "Ensure only Continuity and Short Circuit are checked in the "
        "Test Modes group box. Leave Resistance and HV Insulation unchecked.")

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 5 — Test Cases
# ---------------------------------------------------------------------------

def add_section_5(doc):
    h1(doc, "5.  Test Cases")

    # TC-001
    test_case_table(doc,
        tc_id="TC-001",
        title="Firmware Ping and Version Check",
        objective="Verify that the GUI can connect to the firmware and read the correct version number.",
        preconditions="Board powered. HarnessTester.exe running. No harness wired.",
        steps=[
            "Connect the GUI to the STLink Virtual COM Port at 921600 baud.",
            "Observe the status label in the Connection group box.",
            "Click the Info tab (or open Info panel) in the GUI.",
            "Record the Firmware Version, Board type, and State values shown.",
        ],
        expected=(
            "Status shows 'CONNECTED — FW v2.0.0'. "
            "Info tab shows: Firmware Version = v2.0.0, State = IDLE. "
            "No error dialogs appear."
        ),
    )

    # TC-002
    test_case_table(doc,
        tc_id="TC-002",
        title="Calibration Command",
        objective="Verify the calibration command executes successfully and returns a calibration offset.",
        preconditions="GUI connected (TC-001 passed). No harness wired.",
        steps=[
            "In the GUI, click the Calibrate button (or Test → Calibrate).",
            "Observe LD2 (blue) on the board — it should blink rapidly for approximately 500 ms.",
            "Observe the calibration offset value displayed in the GUI after calibration completes.",
        ],
        expected=(
            "LD2 blinks fast blue for ~500 ms then stops. "
            "GUI displays a calibration offset value of 120 mΩ (±10 mΩ). "
            "State returns to IDLE after calibration."
        ),
    )

    # TC-003
    test_case_table(doc,
        tc_id="TC-003",
        title="Continuity Test — PASS (All Connections Present)",
        objective="Verify the continuity scan correctly identifies all expected connections as PASS.",
        preconditions=(
            "GUI connected. poc_1wire_test.json loaded (defines pairs: A1↔B1, A2↔B2, A3↔B3, A4↔B4, A5↔B5). "
            "Install jumper wires: PC8↔PC11, PC9↔PC10, PC6↔PD2, PB8↔PC12, PA12↔PC1."
        ),
        steps=[
            "Install all five jumper wires per the wiring table in Section 3.3.",
            "In the GUI, select Continuity mode and click START TEST.",
            "Wait for the scan to complete (LD2 blinks blue during scan).",
            "Inspect the Results Table: check the Status column for all five pairs.",
            "Check the overall verdict displayed on the left panel.",
        ],
        expected=(
            "All five pairs (A1↔B1 through A5↔B5) show Status = PASS. "
            "Overall verdict is PASS (green). "
            "LD1 (green) blinks twice. No OPEN or SHORT faults reported."
        ),
    )

    _result = gui_ss("test_result.png")
    if _result:
        insert_image(doc, _result,
                     "Figure 6 — Results Table showing a completed continuity test. "
                     "Row 1 shows PASS (green); rows 2–4 show FAIL (red) — "
                     "expected when only one wire is installed during initial testing.",
                     width_cm=15.0)
    else:
        screenshot_placeholder(doc,
            "Results Table after TC-003 run — all pairs showing PASS status.",
            height_cm=4.0)

    # TC-004
    test_case_table(doc,
        tc_id="TC-004",
        title="Continuity Test — OPEN FAULT (Connection Missing)",
        objective="Verify the continuity scan correctly flags a missing connection as OPEN FAULT.",
        preconditions=(
            "GUI connected. poc_1wire_test.json loaded. "
            "Start with all five jumper wires installed (TC-003 passed)."
        ),
        steps=[
            "Remove the jumper wire between PC8 (A1) and PC11 (B1).",
            "Keep the remaining four jumper wires in place.",
            "Click START TEST (Continuity mode).",
            "Inspect the Results Table.",
        ],
        expected=(
            "Pair A1↔B1 shows Status = OPEN (or OPEN_FAULT). "
            "Pairs A2↔B2 through A5↔B5 show Status = PASS. "
            "Overall verdict is FAIL (red). LD3 (red) blinks twice."
        ),
    )

    add_page_break(doc)

    # TC-005
    test_case_table(doc,
        tc_id="TC-005",
        title="Short Circuit Test — SHORT FAULT (Unexpected Connection)",
        objective="Verify the short circuit scan correctly flags an unexpected connection.",
        preconditions=(
            "GUI connected. poc_1wire_test.json loaded (A1↔B1, A2↔B2, ...). "
            "Install the five correct jumper wires from TC-003."
        ),
        steps=[
            "Add a sixth jumper wire between PC9 (Side A, pin 2) and PC11 (Side B, pin 1). "
            "This creates an unexpected cross-connection: A2 shorted to B1.",
            "Select Short Circuit mode and click START TEST.",
            "Inspect the Results Table for SHORT entries.",
            "Remove the extra jumper wire after recording results.",
        ],
        expected=(
            "At least one SHORT FAULT reported for the unexpected pair A2↔B1 "
            "(or equivalent notation). "
            "Overall verdict is FAIL (red)."
        ),
    )

    # TC-006
    test_case_table(doc,
        tc_id="TC-006",
        title="Auto-Scan (No Netlist Required)",
        objective="Verify auto-scan discovers connections without a netlist and reports them correctly.",
        preconditions=(
            "GUI connected. Install two jumper wires: PC8↔PC11 (A1↔B1) and PC9↔PC10 (A2↔B2). "
            "No netlist loaded (or dismiss any loaded netlist)."
        ),
        steps=[
            "Click the Auto-Scan button in the GUI, or press the blue B1 button on the Nucleo board.",
            "Wait for the scan to complete.",
            "Inspect the Results Table.",
            "Remove both jumper wires and run Auto-Scan again.",
        ],
        expected=(
            "First scan: A1↔B1 and A2↔B2 appear in the Results Table as CONNECTED. "
            "No other pairs reported. "
            "Second scan (no jumpers): Results Table is empty; no connections detected."
        ),
    )

    # TC-007
    test_case_table(doc,
        tc_id="TC-007",
        title="CSV Report Generation",
        objective="Verify a CSV report is automatically saved after each completed test.",
        preconditions="GUI connected. TC-003 (PASS test) has been completed.",
        steps=[
            "After TC-003 completes, open Windows Explorer and navigate to the "
            "profiles\\results\\ folder next to HarnessTester.exe.",
            "Locate the most recent CSV file (filename format: report_YYYYMMDD_HHMMSS_<DUT_ID>.csv).",
            "Open the file in Excel or a text editor.",
            "Inspect the column headers and data rows.",
        ],
        expected=(
            "CSV file exists and was created within 5 seconds of test completion. "
            "Columns present: Timestamp, DUT_ID, Operator, Pin_A, Pin_B, Net_Name, Status. "
            "Five data rows present, all with Status = PASS."
        ),
    )

    add_page_break(doc)

    # TC-008
    test_case_table(doc,
        tc_id="TC-008",
        title="PDF Report Generation",
        objective="Verify a PDF report can be generated and contains the required content.",
        preconditions="GUI connected. A completed test result is loaded in the GUI.",
        steps=[
            "In the GUI, select File → Export PDF Report.",
            "In the save dialog, choose a filename and save location. Click Save.",
            "Wait for the PDF generation to complete (notification or status bar update).",
            "Open the PDF file in any PDF viewer.",
            "Inspect the cover page and results table.",
        ],
        expected=(
            "PDF file is created within 10 seconds. "
            "Cover page shows DUT ID, date, operator name, and overall verdict. "
            "Results table lists all tested pairs. "
            "No Python errors or GUI crash occurs."
        ),
    )

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 6 — Acceptance Criteria
# ---------------------------------------------------------------------------

def add_section_6(doc):
    h1(doc, "6.  Acceptance Criteria")

    body_para(doc,
        "The Harness Tester MK0 system is considered functionally verified when all "
        "test cases listed in Section 5 achieve the expected result. The table below "
        "summarises the mandatory pass requirements.")

    tbl = doc.add_table(rows=9, cols=4)
    tbl.style = "Table Grid"
    table_header_row(tbl.rows[0], "Test Case", "Title", "Mandatory", "Result")
    cases = [
        ("TC-001", "Firmware Ping and Version Check",            "Yes", ""),
        ("TC-002", "Calibration Command",                        "Yes", ""),
        ("TC-003", "Continuity Test — PASS",                     "Yes", ""),
        ("TC-004", "Continuity Test — OPEN FAULT",               "Yes", ""),
        ("TC-005", "Short Circuit Test — SHORT FAULT",           "Yes", ""),
        ("TC-006", "Auto-Scan",                                  "Yes", ""),
        ("TC-007", "CSV Report Generation",                      "Yes", ""),
        ("TC-008", "PDF Report Generation",                      "Yes", ""),
    ]
    for i, row_data in enumerate(cases, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        tbl_row = tbl.rows[i]
        if bg:
            for cell in tbl_row.cells: set_cell_bg(cell, bg)
        for j, txt in enumerate(row_data):
            run = tbl_row.cells[j].paragraphs[0].add_run(str(txt))
            run.font.name = FONT_NAME; run.font.size = Pt(SZ_TABLE)

    doc.add_paragraph()
    note_box(doc,
        "Any TC marked Mandatory that does not achieve the Expected Result "
        "must be investigated and resolved before the system is released for "
        "harness testing use.")
    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 7 — Test Record
# ---------------------------------------------------------------------------

def add_section_7(doc):
    h1(doc, "7.  Test Record")

    body_para(doc,
        "Complete this form upon finishing the functional test procedure. "
        "One form per test session.")

    tbl = doc.add_table(rows=12, cols=2)
    tbl.style = "Table Grid"
    fields = [
        ("Date",                  ""),
        ("Tester Name",           ""),
        ("PC Hostname",           ""),
        ("Board Serial Number",   "(ST-Link SN shown in STM32CubeProgrammer)"),
        ("Firmware Version",      "v2.0.0  (confirm from Info tab)"),
        ("HarnessTester.exe ver", ""),
        ("TC-001 Result",         "PASS  /  FAIL"),
        ("TC-002 Result",         "PASS  /  FAIL"),
        ("TC-003 Result",         "PASS  /  FAIL"),
        ("TC-004 Result",         "PASS  /  FAIL"),
        ("TC-005 Result",         "PASS  /  FAIL"),
        ("TC-006 / 007 / 008",    "PASS  /  FAIL  /  PASS  /  FAIL  /  PASS  /  FAIL"),
    ]
    for i, (label, hint) in enumerate(fields):
        row = tbl.rows[i]
        bg = C_LGRAY if i % 2 == 0 else None
        if bg:
            set_cell_bg(row.cells[0], bg)
            set_cell_bg(row.cells[1], bg)
        la = row.cells[0].paragraphs[0].add_run(label)
        la.font.name = FONT_NAME; la.font.size = Pt(SZ_TABLE); la.font.bold = True
        hi = row.cells[1].paragraphs[0].add_run(hint)
        hi.font.name = FONT_NAME; hi.font.size = Pt(SZ_TABLE); hi.font.italic = bool(hint)

    doc.add_paragraph()

    # Overall verdict row
    verdict_tbl = doc.add_table(rows=1, cols=2)
    verdict_tbl.style = "Table Grid"
    set_cell_bg(verdict_tbl.rows[0].cells[0], C_NAVY)
    r = verdict_tbl.rows[0].cells[0].paragraphs[0].add_run("Overall Verdict")
    r.font.name = FONT_NAME; r.font.size = Pt(SZ_BODY + 2); r.font.bold = True; r.font.color.rgb = C_WHITE
    v = verdict_tbl.rows[0].cells[1].paragraphs[0].add_run("PASS  /  FAIL  (circle one)")
    v.font.name = FONT_NAME; v.font.size = Pt(SZ_BODY + 2); v.font.bold = True
    doc.add_paragraph()

    body_para(doc, "Tester Signature: _________________________________    Date: ___________")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("Downloading board image...")
    board_img = download_image(BOARD_IMAGE_URL, suffix=".jpg")
    if board_img:
        print(f"  Board image downloaded: {board_img}")
    else:
        print("  Board image download failed — placeholder will be used.")

    doc = Document()
    setup_page(doc)
    add_cover_page(doc)
    add_footer_page_num(doc, "FTP-HT-MK0-v1.0")
    add_doc_control(doc)
    add_section_2(doc)
    add_section_3(doc, board_img)
    add_section_4(doc)
    add_section_5(doc)
    add_section_6(doc)
    add_section_7(doc)

    doc.save(OUTPUT_PATH)
    print(f"Saved: {OUTPUT_PATH}")

    if board_img and os.path.exists(board_img):
        os.unlink(board_img)


if __name__ == "__main__":
    main()
