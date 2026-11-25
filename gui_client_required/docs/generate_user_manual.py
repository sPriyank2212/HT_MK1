#!/usr/bin/env python3
"""
generate_user_manual.py
Generates: UM-HT-MK0-v1.2.docx  — User Manual, Harness Tester MK0
Run from anywhere; output drops into the same folder as this script.
"""

import os
from docx import Document
from docx.shared import Pt, Cm, RGBColor, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
OUTPUT_PATH = os.path.join(SCRIPT_DIR, "UM-HT-MK0-v1.2.docx")
LOGO_PATH   = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "resources", "company_logo.jpeg"))

# ---------------------------------------------------------------------------
# Design tokens  (change here → changes everywhere)
# ---------------------------------------------------------------------------
FONT_NAME   = "Calibri"
SZ_BODY     = 14       # pt — minimum per spec
SZ_H1       = 20
SZ_H2       = 16
SZ_H3       = 14
SZ_TABLE    = 13       # tightest allowed in cells
SZ_CAPTION  = 12
SZ_FOOTER   = 11

C_NAVY      = RGBColor(0x1F, 0x35, 0x64)
C_MID_BLUE  = RGBColor(0x2E, 0x74, 0xB5)
C_LIGHT_BLU = RGBColor(0xD6, 0xE4, 0xF0)
C_WARN      = RGBColor(0xFF, 0xF2, 0xCC)
C_NOTE      = RGBColor(0xE2, 0xEF, 0xDA)
C_FAIL      = RGBColor(0xFF, 0xCC, 0xCC)
C_WHITE     = RGBColor(0xFF, 0xFF, 0xFF)
C_BLACK     = RGBColor(0x00, 0x00, 0x00)
C_LGRAY     = RGBColor(0xF2, 0xF2, 0xF2)
C_DGRAY     = RGBColor(0x60, 0x60, 0x60)

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


def add_section_break(doc):
    """Continuous section break — used to isolate the cover page."""
    para    = doc.add_paragraph()
    pPr     = para._p.get_or_add_pPr()
    sectPr  = OxmlElement("w:sectPr")
    typ     = OxmlElement("w:type")
    typ.set(qn("w:val"), "nextPage")
    sectPr.append(typ)
    pPr.append(sectPr)
    return para


def add_footer_page_num(doc, doc_number: str):
    """Add a footer with doc number (left) and page number (right)."""
    section = doc.sections[-1]
    section.footer_distance = Cm(1.27)
    footer  = section.footer
    ft_para = footer.paragraphs[0]
    ft_para.clear()
    ft_para.alignment = WD_ALIGN_PARAGRAPH.LEFT

    # Left: doc number
    run = ft_para.add_run(doc_number + "    ")
    run.font.name = FONT_NAME
    run.font.size = Pt(SZ_FOOTER)
    run.font.color.rgb = C_DGRAY

    # Right: page number (tab-stop trick via XML)
    run2 = ft_para.add_run()
    run2.font.name = FONT_NAME
    run2.font.size = Pt(SZ_FOOTER)
    run2.font.color.rgb = C_DGRAY
    fldChar1 = OxmlElement("w:fldChar")
    fldChar1.set(qn("w:fldCharType"), "begin")
    instrText = OxmlElement("w:instrText")
    instrText.text = "PAGE"
    fldChar2 = OxmlElement("w:fldChar")
    fldChar2.set(qn("w:fldCharType"), "end")
    run2._r.append(fldChar1)
    run2._r.append(instrText)
    run2._r.append(fldChar2)


def hr_line(doc):
    """Thin horizontal rule."""
    para = doc.add_paragraph()
    pPr  = para._p.get_or_add_pPr()
    pBdr = OxmlElement("w:pBdr")
    bot  = OxmlElement("w:bottom")
    bot.set(qn("w:val"),   "single")
    bot.set(qn("w:sz"),    "6")
    bot.set(qn("w:space"), "1")
    bot.set(qn("w:color"), "1F3564")
    pBdr.append(bot)
    pPr.append(pBdr)
    return para

# ---------------------------------------------------------------------------
# Style helpers
# ---------------------------------------------------------------------------

def _run_font(run, size, bold=False, italic=False, color=None):
    run.font.name  = FONT_NAME
    run.font.size  = Pt(size)
    run.font.bold  = bold
    run.font.italic = italic
    if color:
        run.font.color.rgb = color


def body_para(doc, text, bold=False, italic=False, indent=False, color=None):
    p = doc.add_paragraph()
    p.paragraph_format.space_after  = Pt(6)
    p.paragraph_format.space_before = Pt(0)
    if indent:
        p.paragraph_format.left_indent = Cm(0.63)
    run = p.add_run(text)
    _run_font(run, SZ_BODY, bold=bold, italic=italic, color=color or C_BLACK)
    return p


def bullet_para(doc, text, level=0, bold=False):
    p = doc.add_paragraph(style="List Bullet")
    p.paragraph_format.space_after  = Pt(3)
    p.paragraph_format.left_indent  = Cm(0.63 + level * 0.63)
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
    """Yellow-background single-cell table used as a callout."""
    tbl  = doc.add_table(rows=1, cols=1)
    cell = tbl.cell(0, 0)
    cell.width = Inches(6.3)
    set_cell_bg(cell, C_WARN)
    para = cell.paragraphs[0]
    run  = para.add_run("⚠  " + text)
    run.font.name  = FONT_NAME
    run.font.size  = Pt(SZ_BODY)
    run.font.bold  = True
    run.font.color.rgb = RGBColor(0x7F, 0x60, 0x00)
    cell.paragraphs[0].paragraph_format.space_before = Pt(4)
    cell.paragraphs[0].paragraph_format.space_after  = Pt(4)
    doc.add_paragraph()   # spacer


def note_box(doc, text):
    """Green-tint note callout."""
    tbl  = doc.add_table(rows=1, cols=1)
    cell = tbl.cell(0, 0)
    set_cell_bg(cell, C_NOTE)
    para = cell.paragraphs[0]
    run  = para.add_run("NOTE:  " + text)
    run.font.name  = FONT_NAME
    run.font.size  = Pt(SZ_BODY)
    run.font.color.rgb = RGBColor(0x37, 0x5A, 0x1F)
    cell.paragraphs[0].paragraph_format.space_before = Pt(4)
    cell.paragraphs[0].paragraph_format.space_after  = Pt(4)
    doc.add_paragraph()


def screenshot_placeholder(doc, instruction: str, height_cm: float = 7.0):
    """Dashed-border box standing in for a screenshot."""
    tbl  = doc.add_table(rows=1, cols=1)
    cell = tbl.cell(0, 0)
    set_cell_bg(cell, C_LGRAY)
    bdr  = {"top":    {"val": "dashed", "sz": "6", "color": "888888"},
            "bottom": {"val": "dashed", "sz": "6", "color": "888888"},
            "left":   {"val": "dashed", "sz": "6", "color": "888888"},
            "right":  {"val": "dashed", "sz": "6", "color": "888888"}}
    set_cell_border(cell, **bdr)
    para = cell.paragraphs[0]
    para.alignment = WD_ALIGN_PARAGRAPH.CENTER
    para.paragraph_format.space_before = Pt(int(height_cm * 6))
    para.paragraph_format.space_after  = Pt(int(height_cm * 6))
    run  = para.add_run(f"[ SCREENSHOT — {instruction} ]")
    run.font.name   = FONT_NAME
    run.font.size   = Pt(SZ_CAPTION)
    run.font.italic = True
    run.font.color.rgb = C_DGRAY
    doc.add_paragraph()


def table_header_row(row, *col_texts, bg=C_NAVY, fg=C_WHITE):
    for i, txt in enumerate(col_texts):
        cell = row.cells[i]
        set_cell_bg(cell, bg)
        para = cell.paragraphs[0]
        para.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run  = para.add_run(txt)
        run.font.name  = FONT_NAME
        run.font.size  = Pt(SZ_TABLE)
        run.font.bold  = True
        run.font.color.rgb = fg


def table_data_row(row, *col_texts, bg=None, align=None):
    for i, txt in enumerate(col_texts):
        cell = row.cells[i]
        if bg:
            set_cell_bg(cell, bg)
        para = cell.paragraphs[0]
        if align:
            para.alignment = align[i] if isinstance(align, list) else align
        run  = para.add_run(str(txt))
        run.font.name = FONT_NAME
        run.font.size = Pt(SZ_TABLE)

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
    section.different_first_page_header_footer = True  # no footer on cover

    # Logo
    if os.path.exists(LOGO_PATH):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
        run = p.add_run()
        run.add_picture(LOGO_PATH, height=Cm(2.0))
    else:
        p = doc.add_paragraph("[COMPANY LOGO]")
        p.runs[0].font.size = Pt(14)
        p.runs[0].font.color.rgb = C_DGRAY

    doc.add_paragraph()
    doc.add_paragraph()
    doc.add_paragraph()

    # Big horizontal rule
    hr_line(doc)

    # Document type label
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    run = p.add_run("USER MANUAL")
    run.font.name  = FONT_NAME
    run.font.size  = Pt(13)
    run.font.bold  = True
    run.font.color.rgb = C_MID_BLUE
    p.paragraph_format.space_after = Pt(4)

    # Main title
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    run = p.add_run("Harness Tester")
    run.font.name  = FONT_NAME
    run.font.size  = Pt(32)
    run.font.bold  = True
    run.font.color.rgb = C_NAVY
    p.paragraph_format.space_after = Pt(4)

    # Sub-title
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    run = p.add_run("MK0  |  Proof of Concept")
    run.font.name  = FONT_NAME
    run.font.size  = Pt(20)
    run.font.bold  = False
    run.font.color.rgb = C_MID_BLUE
    p.paragraph_format.space_after = Pt(2)

    hr_line(doc)
    doc.add_paragraph()
    doc.add_paragraph()
    doc.add_paragraph()
    doc.add_paragraph()
    doc.add_paragraph()

    # Document info table (no borders)
    tbl = doc.add_table(rows=7, cols=2)
    tbl.alignment = WD_TABLE_ALIGNMENT.LEFT
    info = [
        ("Document Number",  "UM-HT-MK0-v1.0"),
        ("Version",          "1.0"),
        ("Date",             "May 2026"),
        ("Status",           "Released"),
        ("Product",          "Harness Tester MK0 (Nucleo-F303ZE POC)"),
        ("Firmware Version", "v1.0.0"),
        ("Prepared by",      "Engineering Team"),
    ]
    for i, (label, value) in enumerate(info):
        row = tbl.rows[i]
        row.cells[0].width = Cm(5.5)
        row.cells[1].width = Cm(10.0)
        r0 = row.cells[0].paragraphs[0].add_run(label)
        r0.font.name = FONT_NAME;  r0.font.size = Pt(SZ_BODY)
        r0.font.bold = True;       r0.font.color.rgb = C_NAVY
        r1 = row.cells[1].paragraphs[0].add_run(value)
        r1.font.name = FONT_NAME;  r1.font.size = Pt(SZ_BODY)
        r1.font.color.rgb = C_BLACK

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Document control table
# ---------------------------------------------------------------------------

def add_doc_control(doc):
    h1(doc, "Document Control")

    h2(doc, "Revision History")
    tbl = doc.add_table(rows=2, cols=5)
    tbl.style = "Table Grid"
    tbl.alignment = WD_TABLE_ALIGNMENT.LEFT
    table_header_row(tbl.rows[0], "Version", "Date", "Author", "Section(s)", "Description of Change")
    table_data_row(tbl.rows[1], "1.0", "May 2026", "Engineering Team", "All", "Initial release")

    doc.add_paragraph()

    h2(doc, "Applicability")
    body_para(doc, "This manual applies to Harness Tester MK0 only. The MK0 is a proof-of-concept "
                   "system based on the STMicroelectronics Nucleo-F303ZE development board. "
                   "MK1 and MK2 are separate products with their own dedicated GUI applications "
                   "and hardware. Do not use this manual for MK1 or MK2 hardware.")

    h2(doc, "Related Documents")
    tbl2 = doc.add_table(rows=4, cols=3)
    tbl2.style = "Table Grid"
    table_header_row(tbl2.rows[0], "Document Number", "Title", "Version")
    refs = [
        ("SOW-HT-MK0-v2.0", "Statement of Work, Harness Tester MK0", "2.0"),
        ("GOM-HT-MK0-v1.0", "GUI Operating Manual, Harness Tester MK0", "1.0"),
        ("FTP-HT-MK0-v1.0", "Functional Test Procedure, Harness Tester MK0", "1.0"),
    ]
    for i, row_data in enumerate(refs, start=1):
        table_data_row(tbl2.rows[i], *row_data)

    doc.add_paragraph()
    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 1 — Introduction & POC Scope
# ---------------------------------------------------------------------------

def add_section_1(doc):
    h1(doc, "1.  Introduction and POC Scope")

    body_para(doc, "The Harness Tester MK0 is the proof-of-concept build of a production wire "
                   "harness testing system. Rather than waiting for custom PCBs to be manufactured, "
                   "MK0 runs entirely on a standard STMicroelectronics Nucleo-F303ZE development "
                   "board. It uses 74 GPIO pins in total, with 37 Source pins on Side A and 37 Destination pins "
                   "on Side B, all wired directly to the harness under test via jumper cables on "
                   "the board's Morpho headers. Communication with the PC happens over the USB "
                   "cable that also powers the board, using the Nucleo's built-in ST-Link USB bridge.")

    body_para(doc, "The purpose of MK0 is to prove that the end-to-end workflow is sound: load a "
                   "netlist describing the expected wiring, run a scan, compare the results, display "
                   "a pass or fail verdict, and save a test report. The core concepts validated here, "
                   "including the UART protocol, the JSON netlist format, and the CSV and PDF reports, "
                   "inform the design of MK1 and MK2. Each product version has its own dedicated "
                   "GUI application suited to its hardware capabilities.")

    h2(doc, "1.1  What MK0 Does")
    body_para(doc, "MK0 is capable of the following two test functions:")
    bullet_para(doc, "Continuity Test: checks whether each expected connection in the netlist "
                     "is present. A connection is detected when a GPIO Source pin on Side A drives HIGH "
                     "and the corresponding Side B Destination pin reads HIGH. Any expected connection that is "
                     "not found is reported as an OPEN FAULT.")
    bullet_para(doc, "Short Circuit Test: checks for unintended connections between any two pins "
                     "that are not supposed to be linked. If Side A Source pin N drives HIGH and any Side B "
                     "Destination pin other than its expected partner reads HIGH, that pair is flagged as a "
                     "SHORT FAULT.")
    body_para(doc, "Both tests run against a 37-pin harness, either one DB37 connector side at a "
                   "time or via jumper wires directly on the Morpho headers for prototyping.")

    h2(doc, "1.2  What MK0 Does Not Do")
    warning_box(doc, "MK0 does not perform resistance measurement or high-voltage insulation "
                     "testing. These functions require dedicated analogue circuitry (precision "
                     "current source, instrumentation amplifier, HV module) that is not present "
                     "on the Nucleo development board. They are part of the MK1 and MK2 hardware designs.")
    body_para(doc, "The Resistance and HV Insulation checkboxes are visible in the MK0 GUI but must "
                   "not be selected when running on MK0 hardware. Selecting them will cause the "
                   "GUI to send commands that the MK0 firmware will acknowledge but cannot "
                   "meaningfully execute.")
    body_para(doc, "MK0 also does not have a physical enclosure, a safety interlock, or status "
                   "LEDs beyond the three on-board Nucleo LEDs. These are features of the "
                   "MK1 and MK2 hardware.")

    h2(doc, "1.3  Audience")
    body_para(doc, "This manual is written for engineers and technicians who are evaluating or "
                   "demonstrating the MK0 POC system. A basic familiarity with Windows, USB serial "
                   "ports, and reading wiring diagrams is assumed. No programming knowledge is "
                   "required to operate the system.")

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 2 — System Overview
# ---------------------------------------------------------------------------

def add_section_2(doc):
    h1(doc, "2.  System Overview")

    body_para(doc, "The MK0 system has two main components: the Nucleo-F303ZE board (which acts "
                   "as the test instrument) and the Harness Tester PC application (which acts as "
                   "the controller and results display). They communicate over a standard USB cable "
                   "at 921,600 baud using a binary packet protocol with CRC-16 error checking.")

    screenshot_placeholder(doc,
        "Block diagram: Nucleo-F303ZE board connected via USB to PC running the GUI. "
        "Side-A Morpho header connected to harness Side A (37 wires). "
        "Side-B Morpho header connected to harness Side B (37 wires). "
        "Use draw.io or Visio to create this diagram.",
        height_cm=6.0)

    h2(doc, "2.1  Nucleo-F303ZE Board")
    body_para(doc, "The STM32F303ZE microcontroller on the Nucleo board runs the test firmware "
                   "at 72 MHz. It manages all 74 GPIO test pins, processes commands from the PC, "
                   "runs the scan logic, and streams results back over the UART. The firmware is a "
                   "single-threaded bare-metal application with no RTOS, which keeps the scan "
                   "loop tight and the timing predictable.")
    body_para(doc, "The board is powered entirely from the USB connection. No external power "
                   "supply is needed. The ST-Link section of the Nucleo board handles both "
                   "firmware flashing (via SWD) and the virtual COM port used for communication "
                   "with the GUI.")

    h2(doc, "2.2  PC Application")
    body_para(doc, "The PC runs the Harness Tester GUI, a Python/PyQt6 application packaged as a "
                   "standalone Windows executable. The GUI handles everything the operator sees: "
                   "the connection panel, the netlist loader, the test mode selection, the "
                   "real-time scan matrix, the results table, and the report generator.")
    body_para(doc, "The application runs on Windows 10 or Windows 11. No Python installation is "
                   "required if you are using the pre-built executable.")

    h2(doc, "2.3  How They Work Together")
    body_para(doc, "When the operator clicks START, the GUI uploads the netlist to the firmware, "
                   "sends a command to begin scanning, then listens for result packets. Each time "
                   "the firmware finds a connection (or confirms a missing one), it sends a result "
                   "packet back to the GUI. The GUI updates the matrix view in real time and "
                   "appends a row to the results table. When all pairs have been tested, the "
                   "firmware sends a scan-complete packet and the GUI calculates and displays the "
                   "final PASS or FAIL verdict.")
    body_para(doc, "The whole process, from netlist upload through scanning to results, takes "
                   "around two to five seconds for a 37-pin harness, depending on the number "
                   "of connections.")

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 3 — Hardware Description
# ---------------------------------------------------------------------------

def add_section_3(doc):
    h1(doc, "3.  Hardware Description")

    h2(doc, "3.1  The Nucleo-F303ZE Board")
    body_para(doc, "The STMicroelectronics Nucleo-F303ZE (order code: NUCLEO-F303ZE) is a "
                   "144-pin development board with Morpho expansion connectors on both sides. "
                   "For the MK0 harness tester, the board is used without any hardware "
                   "modification. No soldering, rework, or additional components are needed. "
                   "Everything connects through the standard pin headers.")

    screenshot_placeholder(doc,
        "Photo of the Nucleo-F303ZE board. Take a clear top-down photo showing the "
        "Morpho headers (CN7, CN8, CN9, CN10), the ST-Link USB connector (CN1), the "
        "three LEDs (LD1, LD2, LD3), and the blue user button (B1). Label these "
        "features in the photo using arrows or callout boxes.",
        height_cm=8.0)

    h2(doc, "3.2  GPIO Pin Assignments")
    body_para(doc, "The firmware uses 37 GPIO pins as Side A (Source) and 37 separate GPIO "
                   "pins as Side B (Destination). Side A Source pins are configured as push-pull. "
                   "During a scan, the firmware drives one Side A Source pin HIGH at a time and reads "
                   "all 37 Side B Destination pins. Side B Destination pins are configured with an internal "
                   "pull-down resistor, so they read LOW when nothing is connected.")
    body_para(doc, "The table below lists the pin assignment for both sides. The Morpho "
                   "connector column refers to the physical header and pin number silkscreened "
                   "on the board. For the exact mechanical position of each pin, refer to the "
                   "Nucleo-F303ZE user manual (ST document UM1974).")

    # Side A table
    h3(doc, "Side A: Source Pins (37 pins)")
    tbl = doc.add_table(rows=38, cols=3)
    tbl.style = "Table Grid"
    table_header_row(tbl.rows[0], "Harness Pin", "STM32 GPIO", "Morpho Header / Label")
    side_a = [
        (1, "PC8"), (2, "PC9"), (3, "PC6"), (4, "PB8"), (5, "PA12"),
        (6, "PA5"), (7, "PA11"), (8, "PA6"), (9, "PB12"), (10, "PA7"),
        (11, "PB11"), (12, "PB6"), (13, "PB2"), (14, "PA9"), (15, "PB15"),
        (16, "PB10"), (17, "PB13"), (18, "PB3"), (19, "PC4"), (20, "PA10"),
        (21, "PF5"), (22, "PA2"), (23, "PF4"), (24, "PA3"), (25, "PE7"),
        (26, "PD12"), (27, "PD14"), (28, "PD11"), (29, "PD15"), (30, "PE10"),
        (31, "PF14"), (32, "PE12"), (33, "PE9"), (34, "PE14"), (35, "PE11"),
        (36, "PE13"), (37, "PE15"),
    ]
    for i, (pin, gpio) in enumerate(side_a, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        row = tbl.rows[i]
        table_data_row(row, str(pin), gpio, "See UM1974 / board silkscreen", bg=bg)

    doc.add_paragraph()

    # Side B table
    h3(doc, "Side B: Destination Pins (37 pins)")
    tbl2 = doc.add_table(rows=38, cols=3)
    tbl2.style = "Table Grid"
    table_header_row(tbl2.rows[0], "Harness Pin", "STM32 GPIO", "Morpho Header / Label")
    side_b = [
        (1, "PC11"), (2, "PC10"), (3, "PD2"), (4, "PC12"), (5, "PC1"),
        (6, "PC2"), (7, "PC0"), (8, "PC3"), (9, "PD3"), (10, "PD4"),
        (11, "PG2"), (12, "PD5"), (13, "PG3"), (14, "PD6"), (15, "PE2"),
        (16, "PD7"), (17, "PE4"), (18, "PC14"), (19, "PF2"), (20, "PB1"),
        (21, "PF8"), (22, "PF9"), (23, "PG1"), (24, "PE6"), (25, "PG15"),
        (26, "PG10"), (27, "PG13"), (28, "PG11"), (29, "PD1"), (30, "PD0"),
        (31, "PG12"), (32, "PG9"), (33, "PF6"), (34, "PF7"), (35, "PA0"),
        (36, "PA1"), (37, "PA15"),
    ]
    for i, (pin, gpio) in enumerate(side_b, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        row = tbl2.rows[i]
        table_data_row(row, str(pin), gpio, "See UM1974 / board silkscreen", bg=bg)

    doc.add_paragraph()
    note_box(doc, "Pins reserved by the Nucleo board and excluded from harness use: "
                  "PB0 (LD1), PB7 (LD2), PB14 (LD3), PC13 (User Button), "
                  "PD8 (USART3 TX), PD9 (USART3 RX), PA13 (SWDIO), PA14 (SWCLK).")

    h2(doc, "3.3  On-Board LEDs")
    body_para(doc, "The Nucleo board has three user LEDs driven directly by the firmware. "
                   "Their behaviour during normal operation is described below.")

    tbl3 = doc.add_table(rows=7, cols=3)
    tbl3.style = "Table Grid"
    table_header_row(tbl3.rows[0], "LED", "Colour", "Meaning")
    led_rows = [
        ("LD1 (PB0)", "Green",      "Solid ON: IDLE and ready. Fast blink (2x): last test PASS"),
        ("LD2 (PB7)", "Blue",       "Blinking: scan in progress"),
        ("LD3 (PB14)","Red",        "Solid ON: fault condition. Fast blink (2x): last test FAIL"),
        ("LD1+LD2+LD3","All",       "Three blinks on power-on: firmware started correctly"),
        ("LD2 only",  "Blue blink", "Calibration running"),
        ("LD3 solid", "Red",        "Fault state. Check the GUI fault dialog for details."),
    ]
    for i, row_data in enumerate(led_rows, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        table_data_row(tbl3.rows[i], *row_data, bg=bg)

    doc.add_paragraph()

    h2(doc, "3.4  User Button (B1)")
    body_para(doc, "The blue user button on the Nucleo board (connected to PC13) provides a "
                   "quick way to trigger an auto-scan without touching the PC. A single press "
                   "starts a full 37×37 discovery scan, which is the same as clicking the Auto-Scan "
                   "button in the GUI. No netlist is required; the firmware scans every possible "
                   "pin pair and reports all detected connections.")
    body_para(doc, "If the button is pressed while a scan is already running, the firmware "
                   "ignores the press. Pressing the button when the system is in FAULT state "
                   "has no effect; use the GUI to acknowledge and reset.")

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 4 — MK0 Limitations
# ---------------------------------------------------------------------------

def add_section_4(doc):
    h1(doc, "4.  MK0 Limitations")

    body_para(doc, "MK0 is a development tool, not a production instrument. Understanding what "
                   "it cannot do is just as important as knowing what it can. The limitations "
                   "below are by design and reflect the use of a general-purpose development "
                   "board rather than dedicated measurement hardware.")

    tbl = doc.add_table(rows=7, cols=3)
    tbl.style = "Table Grid"
    table_header_row(tbl.rows[0], "Item", "MK0 Status", "MK1 Status")
    lim_rows = [
        ("Continuity test",            "Supported",                    "Supported"),
        ("Short circuit detection",    "Supported",                    "Supported"),
        ("Resistance measurement",     "Not available",                "Supported (1 mΩ resolution)"),
        ("HV insulation test",         "Not available",                "Supported (up to 500 V DC)"),
        ("Pin count",                  "37 pins per side",             "256 pins (7 × DB37)"),
        ("Physical enclosure",         "Open dev board, no enclosure",        "Aluminium instrument case"),
    ]
    aligns = [WD_ALIGN_PARAGRAPH.LEFT, WD_ALIGN_PARAGRAPH.LEFT, WD_ALIGN_PARAGRAPH.LEFT]
    for i, row_data in enumerate(lim_rows, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        table_data_row(tbl.rows[i], *row_data, bg=bg)

    doc.add_paragraph()

    warning_box(doc, "Never connect the MK0 system to a live harness that carries voltage. "
                     "The Nucleo board GPIO pins are rated for 3.3 V logic signals only. "
                     "Applying external voltage to any test pin will damage the microcontroller.")

    body_para(doc, "The development board is also not designed for repeated mechanical mating "
                   "cycles on the Morpho headers. For extended test runs, consider using a "
                   "breakout PCB or a purpose-built jig that connects to the Morpho headers "
                   "via ribbon cable rather than direct pin insertion.")

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 5 — PC Software Requirements
# ---------------------------------------------------------------------------

def add_section_5(doc):
    h1(doc, "5.  PC Software Requirements")

    body_para(doc, "The Harness Tester GUI runs on Windows 10 (64-bit) or Windows 11. "
                   "No other operating systems are supported for MK0 at this stage. The "
                   "application is distributed as a standalone executable, so Python does "
                   "not need to be installed on the target machine.")

    tbl = doc.add_table(rows=5, cols=2)
    tbl.style = "Table Grid"
    table_header_row(tbl.rows[0], "Requirement", "Specification")
    reqs = [
        ("Operating System", "Windows 10 (64-bit) or Windows 11"),
        ("USB Port",         "One available USB-A port (USB 2.0 or higher)"),
        ("USB Driver",       "ST-Link USB driver (installed with STM32CubeProgrammer)"),
        ("Disk Space",       "Approx. 150 MB for the GUI executable and dependencies"),
    ]
    for i, row_data in enumerate(reqs, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        table_data_row(tbl.rows[i], *row_data, bg=bg)

    doc.add_paragraph()

    h2(doc, "5.1  Installing the ST-Link Driver")
    body_para(doc, "Windows 10 and 11 will usually install a basic driver for the ST-Link "
                   "automatically when you plug in the Nucleo board. However, the generic "
                   "Windows driver does not always expose the virtual COM port correctly. "
                   "The recommended approach is to install STM32CubeProgrammer from "
                   "STMicroelectronics. The installer includes the correct ST-Link driver "
                   "and the virtual COM port driver.")
    numbered_para(doc, "Download STM32CubeProgrammer from the STMicroelectronics website "
                       "(search for 'STM32CubeProgrammer download').")
    numbered_para(doc, "Run the installer and follow the prompts. When asked whether to "
                       "install the ST-Link driver, select Yes.")
    numbered_para(doc, "After installation, plug in the Nucleo board and open Windows "
                       "Device Manager. Under 'Ports (COM & LPT)', you should see "
                       "'STMicroelectronics STLink Virtual COM Port (COMx)'. Note the "
                       "COM port number, as you will need it when setting up the GUI.")

    note_box(doc, "The COM port number is assigned dynamically by Windows and can change "
                  "each time the board is plugged into a different USB port. If the port "
                  "changes unexpectedly, check Device Manager again.")

    h2(doc, "5.2  Running the GUI Application")
    body_para(doc, "The GUI is distributed as a single executable file named "
                   "HarnessTester.exe. Copy this file to any convenient location on the "
                   "PC and double-click to launch it. Windows may show a security prompt "
                   "the first time. Click 'More info' and then 'Run anyway' to proceed.")
    body_para(doc, "The application creates a 'profiles' folder and a 'profiles/results' "
                   "folder in the same directory as the executable on first run. Test "
                   "reports are saved there automatically.")

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 6 — Connecting the System
# ---------------------------------------------------------------------------

def add_section_6(doc):
    h1(doc, "6.  Connecting the System")

    body_para(doc, "Connection between the PC and the Nucleo board uses the USB cable that "
                   "ships with the Nucleo kit (USB-A to USB-B Mini). This single cable "
                   "provides power to the board and carries the UART communication through "
                   "the ST-Link bridge. No separate power supply is needed.")

    h2(doc, "6.1  Physical Connection")
    numbered_para(doc, "Ensure the Nucleo board is not connected to the PC yet.")
    numbered_para(doc, "Connect the USB-B Mini end of the cable to the connector labelled "
                       "CN1 on the Nucleo board (the connector nearest to the ST-Link chip, "
                       "not the Arduino connector end).")
    numbered_para(doc, "Connect the USB-A end to a free port on the PC.")
    numbered_para(doc, "LD1 (green LED) should illuminate within two seconds. If none of "
                       "the LEDs light up, check the cable and try a different USB port.")
    numbered_para(doc, "After a successful boot, LD1, LD2, and LD3 blink three times in "
                       "unison, then LD1 stays solid green. This confirms the firmware is "
                       "running and the system is idle and ready.")

    screenshot_placeholder(doc,
        "Photo showing the USB cable connected to CN1 on the Nucleo board, "
        "with LD1 lit green. Label CN1 and LD1 in the photo.",
        height_cm=6.0)

    h2(doc, "6.2  Connecting in the GUI")
    numbered_para(doc, "Launch HarnessTester.exe.")
    numbered_para(doc, "In the Connection group box on the left panel, click the Scan "
                       "button (labelled 'Refresh') to populate the port list.")
    numbered_para(doc, "Select the COM port that corresponds to the ST-Link virtual COM "
                       "port. It is usually labelled 'STMicroelectronics STLink Virtual "
                       "COM Port' in the dropdown.")
    numbered_para(doc, "Confirm the baud rate is set to 921600.")
    numbered_para(doc, "Click Connect. The status label will change from 'DISCONNECTED' "
                       "to 'CONNECTED — FW v1.0.0' within a few seconds.")

    screenshot_placeholder(doc,
        "Screenshot of the GUI Connection group box showing the correct COM port "
        "selected, baud rate 921600, and status reading 'CONNECTED — FW v1.0.0'.",
        height_cm=5.0)

    note_box(doc, "If the status shows 'CONNECTING...' and does not progress, the firmware "
                  "may not have finished booting. Unplug and replug the USB cable and try "
                  "connecting again. If the problem persists, reflash the firmware using the "
                  "procedure in FFP-HT-MK0-v1.0.")

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 7 — Wiring the Test Harness
# ---------------------------------------------------------------------------

def add_section_7(doc):
    h1(doc, "7.  Wiring the Test Harness")

    body_para(doc, "The Morpho headers on the Nucleo-F303ZE board are not pre-populated "
                   "when the board is purchased. The pins need to be soldered before any "
                   "harness connection can be made. Once the Morpho header pins are soldered, "
                   "the DB37 connector is wired to the appropriate Morpho pins according "
                   "to the GPIO assignment table in Section 3.2.")

    warning_box(doc, "Soldering must be carried out before using the MK0 system. "
                     "Do not attempt to connect the DB37 connector to unpopulated headers.")

    screenshot_placeholder(doc,
        "Photo showing the soldered Morpho header pins on the Nucleo board and "
        "the DB37 connector wired to the correct pins. Label Side A and Side B "
        "connectors clearly.",
        height_cm=7.0)

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 8 — Quick-Start Workflow
# ---------------------------------------------------------------------------

def add_section_8(doc):
    h1(doc, "8.  Quick-Start Workflow")

    body_para(doc, "Follow these steps to run your first test. The entire process takes "
                   "under five minutes once the hardware is wired.")

    numbered_para(doc, "Connect the USB cable from the Nucleo board (CN1) to the PC. "
                       "Wait for LD1 to go solid green.", bold=False)
    numbered_para(doc, "Launch HarnessTester.exe on the PC.")
    numbered_para(doc, "In the Connection group box, click Refresh, select the ST-Link "
                       "COM port, confirm baud rate is 921600, and click Connect.")
    numbered_para(doc, "Wait for the status to show 'CONNECTED — FW v1.0.0'.")
    numbered_para(doc, "In the Netlist group box, click Browse and load your netlist JSON "
                       "file. The netlist tree will populate on the left panel. If you do "
                       "not have a netlist yet, use Tools → Golden Sample Learning to "
                       "generate one from a known-good harness.")
    numbered_para(doc, "In the Test Modes group box, ensure only Continuity and Short "
                       "Circuit are checked. Leave Resistance and HV Insulation unchecked.")
    numbered_para(doc, "Enter the operator name and DUT ID in the Test Profile group box.")
    numbered_para(doc, "Click START TEST. LD2 will blink blue while the scan runs. "
                       "The matrix view updates in real time.")
    numbered_para(doc, "When the scan finishes, the verdict (PASS in green or FAIL in "
                       "red) is displayed in large text on the left panel. LD1 blinks "
                       "twice for PASS; LD3 blinks twice for FAIL.")
    numbered_para(doc, "A CSV report is saved automatically to the profiles/results "
                       "folder. Use File → Export PDF Report to generate a PDF report.")

    screenshot_placeholder(doc,
        "Screenshot of the full GUI window immediately after a completed test, "
        "showing the PASS verdict (green), the populated matrix view, and the "
        "results table with at least a few rows of data visible.",
        height_cm=8.0)

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 9 — Test Modes on MK0
# ---------------------------------------------------------------------------

def add_section_9(doc):
    h1(doc, "9.  Test Modes on MK0")

    h2(doc, "9.1  Continuity Test")
    body_para(doc, "The continuity test verifies that every connection listed in the netlist "
                   "is actually present in the harness. The firmware drives each Side A pin "
                   "HIGH in turn and reads the voltage state on all 37 Side B pins. A Side B "
                   "pin reads HIGH if it is electrically connected to the driven Side A pin "
                   "through the harness.")
    body_para(doc, "Each result is compared against the loaded netlist. A connection that "
                   "matches the netlist is reported as PASS. A connection that the netlist "
                   "expects but is not found is reported as OPEN FAULT.")

    h2(doc, "9.2  Short Circuit Test")
    body_para(doc, "The short circuit test runs the same physical scan as the continuity "
                   "test. The difference is in the comparison logic: any connection found "
                   "between a Side A pin and a Side B pin that is NOT listed in the netlist "
                   "is flagged as a SHORT FAULT.")
    body_para(doc, "Both tests can run in the same scan sequence. When the GUI runs "
                   "'Continuity + Short Circuit', the firmware performs one pass across "
                   "all pin pairs and reports both OPEN and SHORT faults in a single scan. "
                   "There is no need to run them separately.")

    h2(doc, "9.3  Resistance and HV: Not Available on MK0")
    warning_box(doc, "The Resistance measurement and HV Insulation test modes are not "
                     "supported on MK0. Do not enable these checkboxes when the Nucleo "
                     "board is connected. Results would be meaningless and could confuse "
                     "the GUI state machine.")

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 10 — LED Status
# ---------------------------------------------------------------------------

def add_section_10(doc):
    h1(doc, "10.  LED Status Reference")

    body_para(doc, "The three on-board LEDs give a quick visual indication of the system "
                   "state without needing to look at the PC screen. The table below covers "
                   "every state you will encounter during normal operation.")

    tbl = doc.add_table(rows=9, cols=4)
    tbl.style = "Table Grid"
    table_header_row(tbl.rows[0], "System State", "LD1 (Green)", "LD2 (Blue)", "LD3 (Red)")
    led_states = [
        ("Power-on boot",       "3× blink",    "3× blink",    "3× blink"),
        ("IDLE, Ready",        "Solid ON",    "OFF",         "OFF"),
        ("Scan in progress",    "OFF",         "Slow blink",  "OFF"),
        ("Calibrating",         "OFF",         "Fast blink",  "OFF"),
        ("Last Test: PASS",    "2× fast",     "OFF",         "OFF"),
        ("Last Test: FAIL",    "OFF",         "OFF",         "2× fast"),
        ("Fault state",         "OFF",         "OFF",         "Solid ON"),
        ("Watchdog reset",      "OFF",         "OFF",         "Rapid blink"),
    ]
    for i, row_data in enumerate(led_states, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        table_data_row(tbl.rows[i], *row_data, bg=bg)

    doc.add_paragraph()
    note_box(doc, "If all three LEDs remain off after plugging in the USB cable, the "
                  "firmware may not be loaded. Flash the firmware following the procedure "
                  "in FFP-HT-MK0-v1.0 and then reconnect.")
    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 11 — Netlist File Format
# ---------------------------------------------------------------------------

def add_section_11(doc):
    h1(doc, "11.  Netlist File Format")

    body_para(doc, "The netlist is a JSON file that tells the firmware and GUI what the "
                   "correct wiring should look like. It defines one or more 'nets', where "
                   "each net is a group of pins that should all be electrically connected "
                   "to each other. For a 37-pin harness with a straight 1-to-1 wiring "
                   "scheme, you would have 37 nets, each containing exactly two pins.")

    h2(doc, "11.1  File Structure")
    body_para(doc, "The file must be valid JSON and follow the structure shown below. "
                   "All pin numbers are 1-based (pin 1 through pin 37 for MK0).")

    # Code block style
    tbl = doc.add_table(rows=1, cols=1)
    cell = tbl.cell(0, 0)
    set_cell_bg(cell, RGBColor(0x1E, 0x1E, 0x2E))
    para = cell.paragraphs[0]
    para.paragraph_format.space_before = Pt(6)
    para.paragraph_format.space_after  = Pt(6)
    code_text = (
        '{\n'
        '  "nets": [\n'
        '    {\n'
        '      "name": "WIRE_1",\n'
        '      "pins": [\n'
        '        { "n": 1, "l": "A1" },\n'
        '        { "n": 1, "l": "B1" }\n'
        '      ],\n'
        '      "hv": false\n'
        '    },\n'
        '    {\n'
        '      "name": "WIRE_2",\n'
        '      "pins": [\n'
        '        { "n": 2, "l": "A2" },\n'
        '        { "n": 2, "l": "B2" }\n'
        '      ],\n'
        '      "hv": false\n'
        '    }\n'
        '  ]\n'
        '}'
    )
    run = para.add_run(code_text)
    run.font.name  = "Courier New"
    run.font.size  = Pt(12)
    run.font.color.rgb = RGBColor(0xCC, 0xFF, 0xCC)
    doc.add_paragraph()

    h2(doc, "11.2  Field Descriptions")
    tbl2 = doc.add_table(rows=5, cols=3)
    tbl2.style = "Table Grid"
    table_header_row(tbl2.rows[0], "Field", "Type", "Description")
    fields = [
        ("name",  "string",  "Human-readable name for this net. Appears in the results table and PDF report."),
        ("pins",  "array",   "List of pin objects belonging to this net. Minimum two pins per net."),
        ("n",     "integer", "Pin number (1–37 for MK0). Side A and Side B share the same numbering."),
        ("hv",    "boolean", "Set to false for MK0. HV testing is not available on this hardware."),
    ]
    for i, row_data in enumerate(fields, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        table_data_row(tbl2.rows[i], *row_data, bg=bg)

    doc.add_paragraph()

    h2(doc, "11.3  Creating a Netlist")
    body_para(doc, "There are two ways to create a netlist for MK0:")
    bullet_para(doc, "Golden Sample Learning: install a known-good harness, then use "
                     "Tools → Golden Sample Learning in the GUI. The wizard runs a "
                     "continuity scan, shows all detected connections, lets you name them, "
                     "and saves the result as a JSON file. This is the fastest method.")
    bullet_para(doc, "Manual creation: write the JSON file by hand in any text editor, "
                     "following the structure above. Use the Netlist Editor (Tools → "
                     "Netlist Editor) to validate it before running a test.")

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 12 — Auto-Scan Mode
# ---------------------------------------------------------------------------

def add_section_12(doc):
    h1(doc, "12.  Auto-Scan Mode")

    body_para(doc, "Auto-scan performs a full 37×37 discovery scan with no netlist required. "
                   "Every possible pin pair is tested and all detected connections are "
                   "reported. There is no pass/fail comparison; the scan simply maps what "
                   "is there. This is useful for exploring an unknown harness or generating "
                   "a starting point for a new netlist.")

    h2(doc, "12.1  Triggering Auto-Scan")
    body_para(doc, "Auto-scan can be triggered in two ways:")
    bullet_para(doc, "From the GUI: the Auto-Scan button appears in the action group box "
                     "on the left panel when no netlist is loaded, or you can select it "
                     "from the test mode options.")
    bullet_para(doc, "From the hardware: press the blue user button (B1) on the Nucleo "
                     "board at any time while the system is IDLE. The scan starts immediately "
                     "without any PC interaction.")

    h2(doc, "12.2  Interpreting Auto-Scan Results")
    body_para(doc, "Each connection found during auto-scan appears as a row in the results "
                   "table showing the Side A pin number, the Side B pin number, and the "
                   "status CONNECTED. Pins with no detected connections do not appear. "
                   "After the scan, the matrix view highlights every pin that has at least "
                   "one connection in green.")
    body_para(doc, "The auto-scan results can be used directly to create a netlist: after "
                   "the scan completes, use Tools → Golden Sample Learning → Review Page "
                   "to review and name the discovered connections, then save as a new "
                   "netlist file.")

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 13 — Test Reports
# ---------------------------------------------------------------------------

def add_section_13(doc):
    h1(doc, "13.  Test Reports")

    body_para(doc, "The GUI saves a CSV report automatically after every completed test and "
                   "can generate a PDF report on demand. Both files are written to the "
                   "profiles/results folder, which is created next to the HarnessTester.exe "
                   "on first run.")

    h2(doc, "13.1  CSV Report")
    body_para(doc, "The CSV file is named using the pattern "
                   "report_YYYYMMDD_HHMMSS_<DUT_ID>.csv. It contains one row per tested "
                   "pin pair and can be opened directly in Excel or any spreadsheet "
                   "application. The columns are described below.")

    tbl = doc.add_table(rows=8, cols=2)
    tbl.style = "Table Grid"
    table_header_row(tbl.rows[0], "Column", "Content")
    cols = [
        ("Timestamp",       "Date and time of this specific result"),
        ("DUT_ID",          "Identifier entered in the Test Profile group box"),
        ("Operator",        "Operator name from the Test Profile"),
        ("Pin_A",           "Side A pin number (1–37)"),
        ("Pin_B",           "Side B pin number (1–37)"),
        ("Net_Name",        "Net name from the netlist, or blank if no netlist was loaded"),
        ("Status",          "PASS, OPEN (missing connection), or SHORT (unexpected connection)"),
    ]
    for i, row_data in enumerate(cols, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        table_data_row(tbl.rows[i], *row_data, bg=bg)

    doc.add_paragraph()
    note_box(doc, "The Resistance_mOhm, IR_MOhm, and HV_Voltage_V columns are present "
                  "in the CSV file but will be empty for all MK0 tests.")

    h2(doc, "13.2  PDF Report")
    body_para(doc, "The PDF report is generated on request via File → Export PDF Report. "
                   "It includes a cover page with the DUT ID, date, operator name, and "
                   "overall verdict; a matrix view image showing the pin states; and a "
                   "full results table sorted with failures first. The PDF is suitable for "
                   "including in a production traveller or emailing to a customer.")

    screenshot_placeholder(doc,
        "Screenshot of a generated PDF report cover page, showing the DUT ID, "
        "date, operator name, and a large PASS or FAIL verdict. Use a completed "
        "test result to generate this.",
        height_cm=7.0)

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 14 — Fault Codes
# ---------------------------------------------------------------------------

def add_section_14(doc):
    h1(doc, "14.  Fault Codes")

    body_para(doc, "The MK0 firmware generates fault events in two situations. When a fault "
                   "occurs, the GUI displays a non-dismissible alert dialog, LD3 goes solid "
                   "red, and the system enters FAULT state. No further tests can be run until "
                   "the fault is acknowledged in the GUI.")

    tbl = doc.add_table(rows=3, cols=4)
    tbl.style = "Table Grid"
    table_header_row(tbl.rows[0], "Code", "Name", "Plain Language Meaning", "Action Required")
    faults = [
        ("0x01", "FAULT_HV_INTERLOCK",
         "Triggered by the simulated HV interlock path. On MK0, this means the firmware "
         "received an HV command while the safety conditions were not met.",
         "Click 'Acknowledge' in the fault dialog. Ensure HV mode is not selected in the "
         "GUI and restart the test."),
        ("0x07", "FAULT_WATCHDOG",
         "The microcontroller's watchdog timer expired, indicating the firmware stopped "
         "responding. The board will have automatically reset.",
         "Reconnect the GUI after the board resets (LD1 will return to solid green). "
         "If this happens repeatedly, reflash the firmware."),
    ]
    for i, row_data in enumerate(faults, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        table_data_row(tbl.rows[i], *row_data, bg=bg)

    doc.add_paragraph()
    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 15 — Troubleshooting
# ---------------------------------------------------------------------------

def add_section_15(doc):
    h1(doc, "15.  Troubleshooting")

    problems = [
        (
            "COM port does not appear in the GUI port list",
            [
                "Check that the USB cable is firmly connected to CN1 on the Nucleo board, "
                "not to the Arduino USB connector.",
                "Open Windows Device Manager and look under 'Ports (COM & LPT)'. If no "
                "ST-Link port appears there either, the driver is not installed. Follow "
                "the procedure in Section 5.1.",
                "Try a different USB cable. Some USB cables are charge-only and do not "
                "carry data.",
                "Try a different USB port on the PC. Some hubs do not supply enough "
                "current for the Nucleo board.",
            ]
        ),
        (
            "Status shows 'CONNECTING...' and does not change",
            [
                "The firmware may have crashed or not been loaded. Unplug and replug the "
                "USB cable and wait for the LED boot sequence (three blinks on all LEDs).",
                "Check that no other application (STM32CubeIDE, serial terminal, etc.) "
                "has the same COM port open. Only one application can use a COM port "
                "at a time.",
                "Confirm the baud rate in the GUI is set to 921600. Any other value will "
                "result in garbage data and a timeout.",
            ]
        ),
        (
            "All pins show OPEN FAULT even though wires are connected",
            [
                "Verify the jumper wires are inserted into the correct Morpho header pins. "
                "A pin off by one position on the header is a common cause of this.",
                "Check that the netlist matches the physical wiring. If the netlist expects "
                "A1↔B3 but the wire connects A1↔B1, the result will be reported as OPEN "
                "for the expected connection and SHORT for the actual one.",
                "Confirm the wires are fully seated in the Morpho header. The 2.54 mm "
                "Dupont connector should click in with firm pressure.",
            ]
        ),
        (
            "Unexpected SHORT FAULTs on pins that are not wired",
            [
                "Check for stray wire strands touching adjacent pins on the Morpho header. "
                "Under bright light, inspect the header for any bent or bridged pins.",
                "If you are using a ribbon cable, check for damaged insulation that allows "
                "adjacent conductors to touch.",
                "Re-run the scan with no harness connected at all. If shorts still appear "
                "with nothing connected, reflash the firmware.",
            ]
        ),
        (
            "GUI crashes or freezes during scanning",
            [
                "Close and relaunch the GUI. The CSV report from the interrupted test may "
                "be incomplete, so check the file before relying on it.",
                "If the problem repeats consistently on the same harness, check the log "
                "tab for CRC errors; a high rate of CRC errors suggests a bad USB cable "
                "or a noisy USB port.",
            ]
        ),
    ]

    for title, steps in problems:
        h2(doc, title)
        for step in steps:
            bullet_para(doc, step)
        doc.add_paragraph()

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    doc = Document()
    setup_page(doc)

    add_cover_page(doc)
    add_footer_page_num(doc, "UM-HT-MK0-v1.0")
    add_doc_control(doc)
    add_section_1(doc)
    add_section_2(doc)
    add_section_3(doc)
    add_section_4(doc)
    add_section_5(doc)
    add_section_6(doc)
    add_section_7(doc)
    add_section_8(doc)
    add_section_9(doc)
    add_section_10(doc)
    add_section_11(doc)
    add_section_12(doc)
    add_section_13(doc)
    add_section_14(doc)
    add_section_15(doc)

    doc.save(OUTPUT_PATH)
    print(f"Saved: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
