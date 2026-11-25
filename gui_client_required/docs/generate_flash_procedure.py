#!/usr/bin/env python3
"""
generate_flash_procedure.py
Generates: FFP-HT-MK0-v1.0.docx  — Firmware Flash Procedure, Harness Tester MK0
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
OUTPUT_PATH = os.path.join(SCRIPT_DIR, "FFP-HT-MK0-v1.0.docx")
LOGO_PATH   = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "resources", "company_logo.jpeg"))
GUI_SS_DIR  = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "..", "GUI_SS"))

def gui_ss(filename):
    """Return absolute path to a GUI screenshot, or None if missing."""
    p = os.path.join(GUI_SS_DIR, filename)
    return p if os.path.exists(p) else None

# Board photo fetched at runtime from mbed platform page (Nucleo-144 form factor)
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
C_LIGHT_BLU = RGBColor(0xD6, 0xE4, 0xF0)
C_WARN      = RGBColor(0xFF, 0xF2, 0xCC)
C_NOTE      = RGBColor(0xE2, 0xEF, 0xDA)
C_WHITE     = RGBColor(0xFF, 0xFF, 0xFF)
C_BLACK     = RGBColor(0x00, 0x00, 0x00)
C_LGRAY     = RGBColor(0xF2, 0xF2, 0xF2)
C_DGRAY     = RGBColor(0x60, 0x60, 0x60)

# ---------------------------------------------------------------------------
# Image download helper
# ---------------------------------------------------------------------------

def download_image(url, suffix=".jpg"):
    """Download image from URL to a temp file; return path or None on failure."""
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
    run.font.name = FONT_NAME
    run.font.size = Pt(SZ_FOOTER)
    run.font.color.rgb = C_DGRAY
    run2 = ft_para.add_run()
    run2.font.name = FONT_NAME
    run2.font.size = Pt(SZ_FOOTER)
    run2.font.color.rgb = C_DGRAY
    fldChar1  = OxmlElement("w:fldChar"); fldChar1.set(qn("w:fldCharType"), "begin")
    instrText = OxmlElement("w:instrText"); instrText.text = "PAGE"
    fldChar2  = OxmlElement("w:fldChar"); fldChar2.set(qn("w:fldCharType"), "end")
    run2._r.append(fldChar1); run2._r.append(instrText); run2._r.append(fldChar2)


def hr_line(doc):
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
    run.font.name   = FONT_NAME
    run.font.size   = Pt(size)
    run.font.bold   = bold
    run.font.italic = italic
    if color:
        run.font.color.rgb = color


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
    """Embed a downloaded image with a caption below it."""
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run()
    run.add_picture(img_path, width=Cm(width_cm))
    cap = doc.add_paragraph()
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = cap.add_run(caption)
    r.font.name   = FONT_NAME
    r.font.size   = Pt(SZ_CAPTION)
    r.font.italic = True
    r.font.color.rgb = C_DGRAY
    doc.add_paragraph()


def screenshot_placeholder(doc, instruction, height_cm=6.0):
    tbl  = doc.add_table(rows=1, cols=1)
    cell = tbl.cell(0, 0)
    set_cell_bg(cell, C_LGRAY)
    bdr  = {side: {"val": "dashed", "sz": "6", "color": "888888"}
            for side in ("top", "bottom", "left", "right")}
    set_cell_border(cell, **bdr)
    para = cell.paragraphs[0]
    para.alignment = WD_ALIGN_PARAGRAPH.CENTER
    para.paragraph_format.space_before = Pt(int(height_cm * 6))
    para.paragraph_format.space_after  = Pt(int(height_cm * 6))
    run  = para.add_run(f"[ SCREENSHOT — {instruction} ]")
    run.font.name   = FONT_NAME; run.font.size = Pt(SZ_CAPTION)
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
        if bg:
            set_cell_bg(cell, bg)
        run = cell.paragraphs[0].add_run(str(txt))
        run.font.name = FONT_NAME; run.font.size = Pt(SZ_TABLE)

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
        p.runs[0].font.size = Pt(14)
        p.runs[0].font.color.rgb = C_DGRAY

    doc.add_paragraph(); doc.add_paragraph(); doc.add_paragraph()
    hr_line(doc)

    p = doc.add_paragraph()
    run = p.add_run("FIRMWARE FLASH PROCEDURE")
    run.font.name = FONT_NAME; run.font.size = Pt(13)
    run.font.bold = True; run.font.color.rgb = C_MID_BLUE
    p.paragraph_format.space_after = Pt(4)

    p = doc.add_paragraph()
    run = p.add_run("Harness Tester")
    run.font.name = FONT_NAME; run.font.size = Pt(32)
    run.font.bold = True; run.font.color.rgb = C_NAVY
    p.paragraph_format.space_after = Pt(4)

    p = doc.add_paragraph()
    run = p.add_run("MK0  |  Proof of Concept  |  Nucleo-F303ZE")
    run.font.name = FONT_NAME; run.font.size = Pt(18)
    run.font.color.rgb = C_MID_BLUE

    hr_line(doc)
    for _ in range(6):
        doc.add_paragraph()

    tbl  = doc.add_table(rows=7, cols=2)
    tbl.alignment = WD_TABLE_ALIGNMENT.LEFT
    info = [
        ("Document Number",  "FFP-HT-MK0-v1.0"),
        ("Version",          "1.0"),
        ("Date",             "July 2026"),
        ("Status",           "Released"),
        ("Product",          "Harness Tester MK0 (Nucleo-F303ZE POC)"),
        ("Firmware Version", "v2.0.0"),
        ("Prepared by",      "Engineering Team"),
    ]
    for i, (label, value) in enumerate(info):
        row = tbl.rows[i]
        row.cells[0].width = Cm(5.5)
        row.cells[1].width = Cm(10.0)
        r0 = row.cells[0].paragraphs[0].add_run(label)
        r0.font.name = FONT_NAME; r0.font.size = Pt(SZ_BODY)
        r0.font.bold = True; r0.font.color.rgb = C_NAVY
        r1 = row.cells[1].paragraphs[0].add_run(value)
        r1.font.name = FONT_NAME; r1.font.size = Pt(SZ_BODY)
        r1.font.color.rgb = C_BLACK

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
        ("UM-HT-MK0-v1.0",  "User Manual, Harness Tester MK0",                  "1.0"),
        ("FTP-HT-MK0-v1.0", "Functional Test Procedure, Harness Tester MK0",     "1.0"),
        ("UM1974",           "STM32 Nucleo-144 Boards User Manual (STMicro)",     "Latest"),
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
        "This document describes the complete procedure for programming (flashing) "
        "the Harness Tester MK0 firmware onto the STMicroelectronics Nucleo-F303ZE "
        "development board. It covers the primary method using STM32CubeProgrammer "
        "and the alternative method using STM32CubeIDE, followed by post-flash "
        "verification steps using the Harness Tester GUI.")

    h2(doc, "2.2  Scope")
    body_para(doc,
        "This procedure applies to the Harness Tester MK0 system only. The target "
        "hardware is the STMicroelectronics NUCLEO-F303ZE (Nucleo-144) development "
        "board. The firmware project name is POC_HT and the binary is located in "
        "the STM32CubeIDE Debug build output folder.")
    note_box(doc,
        "The Nucleo-F303ZE has an on-board ST-Link V2-1 debugger/programmer. "
        "No external programmer, J-Link, or JTAG probe is required. A single "
        "USB cable connects the board to the PC for both power and programming.")
    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 3 — Tools and Prerequisites
# ---------------------------------------------------------------------------

def add_section_3(doc, board_img_path):
    h1(doc, "3.  Tools and Prerequisites")

    h2(doc, "3.1  Hardware Required")
    tbl = doc.add_table(rows=4, cols=3)
    tbl.style = "Table Grid"
    table_header_row(tbl.rows[0], "Item", "Description", "Qty")
    hw = [
        ("NUCLEO-F303ZE",  "STMicroelectronics Nucleo-144 development board with STM32F303ZE MCU", "1"),
        ("USB Cable",      "USB-A to USB-B Mini cable (supplied with the Nucleo kit)", "1"),
        ("PC",             "Windows 10 or Windows 11 (64-bit) with one free USB-A port", "1"),
    ]
    for i, row_data in enumerate(hw, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        table_data_row(tbl.rows[i], *row_data, bg=bg)
    doc.add_paragraph()

    # Board photo
    if board_img_path:
        insert_image(doc, board_img_path,
                     "Figure 1 — STM32 Nucleo-144 (NUCLEO-F303ZE) development board "
                     "(source: mbed.com)", width_cm=12.0)
    else:
        screenshot_placeholder(doc,
            "Photo of the NUCLEO-F303ZE board — top-down view showing CN7, CN10 "
            "morpho headers, CN1 ST-Link USB connector, LD1/LD2/LD3 LEDs, and "
            "the blue user button B1.", height_cm=7.0)

    h2(doc, "3.2  Software Required")
    tbl2 = doc.add_table(rows=4, cols=3)
    tbl2.style = "Table Grid"
    table_header_row(tbl2.rows[0], "Software", "Version", "Source")
    sw = [
        ("STM32CubeProgrammer",
         "v2.14 or later (recommended)",
         "www.st.com — search 'STM32CubeProgrammer'"),
        ("STM32CubeIDE",
         "v1.13 or later (alternative method only)",
         "www.st.com — search 'STM32CubeIDE'"),
        ("POC_HT firmware binary",
         "v2.0.0 (Debug\\POC_HT.elf)",
         "Provided by Engineering Team / source repo"),
    ]
    for i, row_data in enumerate(sw, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        table_data_row(tbl2.rows[i], *row_data, bg=bg)
    doc.add_paragraph()
    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 4 — Board Connector Overview
# ---------------------------------------------------------------------------

def add_section_4(doc, board_img_path):
    h1(doc, "4.  Board Connector Overview")

    h2(doc, "4.1  ST-Link USB Connector CN1")
    body_para(doc,
        "The Nucleo-F303ZE contains an integrated ST-Link V2-1 programmer/debugger. "
        "Programming is performed entirely over USB through connector CN1, which is "
        "the USB-B Mini connector located near the ST-Link chip at the top of the board. "
        "This is the only connector used for firmware flashing.")
    body_para(doc,
        "When CN1 is connected to a PC and the ST-Link driver is installed, Windows "
        "will enumerate two devices: a mass-storage device (ST-Link DFU) and a "
        "virtual COM port (STLink Virtual COM Port). Both are normal. Programming "
        "uses the ST-Link DFU interface; the virtual COM port is used for UART "
        "communication with the Harness Tester GUI after flashing.")

    warning_box(doc,
        "Connect the USB cable to CN1 (ST-Link USB, near the top of the board). "
        "Do NOT connect to the Arduino USB connector (CN13) at the other end of "
        "the board — that connector is not used by this firmware.")

    tbl = doc.add_table(rows=3, cols=3)
    tbl.style = "Table Grid"
    table_header_row(tbl.rows[0], "Connector", "Location on Board", "Purpose")
    rows = [
        ("CN1",  "Top edge, near ST-Link chip",  "ST-Link USB — firmware programming and virtual COM port"),
        ("CN13", "Bottom edge, Arduino end",      "Arduino USB — NOT used. Do not connect this for flashing."),
    ]
    for i, row_data in enumerate(rows, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        table_data_row(tbl.rows[i], *row_data, bg=bg)
    doc.add_paragraph()

    if board_img_path:
        insert_image(doc, board_img_path,
                     "Figure 2 — Nucleo-144 board. CN1 (ST-Link USB) is at the top edge "
                     "near the ST-Link MCU. Connect here for firmware flashing.",
                     width_cm=12.0)
    else:
        screenshot_placeholder(doc,
            "Annotated photo of the Nucleo-F303ZE board with CN1 (ST-Link USB "
            "connector) labelled with an arrow. Also label LD1, LD2, LD3 LEDs.",
            height_cm=7.0)

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 5 — Firmware Binary Location
# ---------------------------------------------------------------------------

def add_section_5(doc):
    h1(doc, "5.  Firmware Binary Location")

    body_para(doc,
        "The firmware binary is produced by STM32CubeIDE when the POC_HT project "
        "is built. The output files are placed in the Debug sub-folder of the "
        "firmware project directory. The recommended file for STM32CubeProgrammer "
        "is the ELF file, which contains full debug symbol information.")

    tbl = doc.add_table(rows=3, cols=3)
    tbl.style = "Table Grid"
    table_header_row(tbl.rows[0], "File", "Location", "Use")
    files = [
        ("POC_HT.elf",
         "firmware\\Debug\\POC_HT.elf",
         "ELF with debug symbols — preferred for STM32CubeProgrammer"),
        ("POC_HT.hex",
         "firmware\\Debug\\POC_HT.hex",
         "Intel HEX — alternative, can also be used with CubeProgrammer"),
    ]
    for i, row_data in enumerate(files, start=1):
        bg = C_LGRAY if i % 2 == 0 else None
        table_data_row(tbl.rows[i], *row_data, bg=bg)
    doc.add_paragraph()

    note_box(doc,
        "If the Debug folder does not contain these files, the project has not "
        "been built yet. Open the project in STM32CubeIDE and run "
        "Project → Build All (Ctrl+B) before proceeding.")

    body_para(doc,
        "If you have received a pre-built binary (e.g. from Engineering), copy "
        "the .elf or .hex file to a convenient location on the PC before starting "
        "the flash procedure. The file must be accessible when STM32CubeProgrammer "
        "is running.")

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 6 — Flashing via STM32CubeProgrammer (Primary)
# ---------------------------------------------------------------------------

def add_section_6(doc):
    h1(doc, "6.  Flashing via STM32CubeProgrammer (Primary Method)")

    h2(doc, "6.1  Install STM32CubeProgrammer")
    body_para(doc,
        "If STM32CubeProgrammer is not already installed on the PC, download "
        "and install it from the STMicroelectronics website. The installer "
        "also installs the ST-Link USB driver needed for the Nucleo board.")
    numbered_para(doc,
        "Go to www.st.com and search for 'STM32CubeProgrammer'.")
    numbered_para(doc,
        "Download the Windows installer (SetupSTM32CubeProgrammer-x.xx.exe).")
    numbered_para(doc,
        "Run the installer with administrator rights and follow the prompts. "
        "Accept the default installation path.")
    numbered_para(doc,
        "When prompted to install the ST-Link driver, select Yes. This step "
        "is mandatory; the programmer cannot connect to the board without it.")
    numbered_para(doc,
        "Restart the PC after installation completes.")

    screenshot_placeholder(doc,
        "Screenshot of the STM32CubeProgrammer installer at the ST-Link driver "
        "installation step, with the 'Install ST-Link drivers' checkbox ticked.",
        height_cm=5.0)

    h2(doc, "6.2  Hardware Connections")
    numbered_para(doc,
        "Ensure the Nucleo board is not connected to the PC.")
    numbered_para(doc,
        "Connect the USB-B Mini end of the cable to CN1 on the Nucleo board "
        "(the connector near the ST-Link chip at the top of the board).")
    numbered_para(doc,
        "Connect the USB-A end to a free USB port on the PC.")
    numbered_para(doc,
        "Wait for Windows to finish enumerating the device (approximately "
        "5–10 seconds). The LD1 (green) LED will illuminate when the board "
        "has power and the firmware is running.")
    note_box(doc,
        "If the board has never been connected to this PC before, Windows may "
        "show 'Installing device driver' in the taskbar. Wait for this to "
        "complete before proceeding.")

    h2(doc, "6.3  Launch STM32CubeProgrammer and Connect to Target")
    numbered_para(doc,
        "Open STM32CubeProgrammer from the Start menu or desktop shortcut.")
    numbered_para(doc,
        "In the top-right connection panel, set the interface to ST-LINK "
        "(the default). Leave all other settings at their defaults.")
    numbered_para(doc,
        "Click the green Connect button. The log panel at the bottom should "
        "show 'ST-LINK SN: xxxxxxxx' and 'Connected via SWD' within a few "
        "seconds. The target MCU (STM32F303ZETx) will be identified "
        "automatically.")
    numbered_para(doc,
        "If connection fails, click the Refresh button next to the Port "
        "dropdown and try connecting again. Check that no other application "
        "(e.g. STM32CubeIDE in debug mode) is using the ST-Link.")

    screenshot_placeholder(doc,
        "Screenshot of STM32CubeProgrammer showing the ST-LINK interface "
        "selected, the Connect button highlighted, and the log panel showing "
        "a successful connection to STM32F303ZETx.", height_cm=6.0)

    h2(doc, "6.4  Load Firmware File")
    numbered_para(doc,
        "In the left navigation bar, click the Erasing & Programming icon "
        "(the memory chip icon, third from top).")
    numbered_para(doc,
        "In the 'File path' field, click Browse and navigate to the firmware "
        "binary: firmware\\Debug\\POC_HT.elf")
    numbered_para(doc,
        "Confirm the 'Start address' field shows 0x08000000 (the STM32 "
        "Flash start address). This is filled automatically from the ELF file.")
    numbered_para(doc,
        "Leave 'Skip flash erase before programming' unchecked to ensure a "
        "clean flash.")

    screenshot_placeholder(doc,
        "Screenshot of STM32CubeProgrammer Erasing & Programming panel with "
        "the firmware ELF file path loaded and Start address showing 0x08000000.",
        height_cm=6.0)

    h2(doc, "6.5  Erase and Program")
    numbered_para(doc,
        "Click the Start Programming button. STM32CubeProgrammer will erase "
        "the Flash and write the new firmware.")
    numbered_para(doc,
        "A progress bar appears during programming. The operation should "
        "complete in under 10 seconds.")
    numbered_para(doc,
        "When programming is complete, the log panel will show "
        "'File download complete' and 'Verification OK'. If a verification "
        "error appears, repeat from step 6.4 with a fresh download of "
        "the firmware binary.")

    note_box(doc,
        "STM32CubeProgrammer performs an automatic verify after programming "
        "by default. No separate verify step is needed unless you disabled "
        "this option.")

    h2(doc, "6.6  Verify Read-Back")
    numbered_para(doc,
        "After successful programming, click the Disconnect button in the "
        "top-right panel.")
    numbered_para(doc,
        "Unplug and replug the USB cable to perform a full power cycle on "
        "the board.")
    numbered_para(doc,
        "Observe the LEDs: all three (LD1, LD2, LD3) should blink three "
        "times together (the firmware boot sequence), then LD1 (green) "
        "should remain solid. This confirms the firmware has started "
        "correctly.")

    screenshot_placeholder(doc,
        "Screenshot of STM32CubeProgrammer log panel showing "
        "'File download complete' and 'Verification OK' messages after "
        "a successful flash.", height_cm=5.0)

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 7 — Alternative: STM32CubeIDE
# ---------------------------------------------------------------------------

def add_section_7(doc):
    h1(doc, "7.  Alternative — Flashing via STM32CubeIDE")

    body_para(doc,
        "If STM32CubeIDE is already installed and the firmware source project "
        "is available, flashing can be done directly from the IDE during a "
        "debug session. This method is primarily intended for developers who "
        "are actively modifying the firmware.")

    h2(doc, "7.1  Open and Build the Project")
    numbered_para(doc,
        "Launch STM32CubeIDE. Select the workspace that contains the "
        "POC_HT firmware project, or import the project via "
        "File → Import → Existing Projects into Workspace and browse to "
        "the firmware\\ folder in the repository.")
    numbered_para(doc,
        "In the Project Explorer, right-click the POC_HT project and "
        "select Build Project (or press Ctrl+B).")
    numbered_para(doc,
        "Confirm the build completes with 0 errors. The Console view "
        "at the bottom will show 'Build Finished' with a binary size "
        "summary. The ELF file will be created at "
        "firmware\\Debug\\POC_HT.elf")

    screenshot_placeholder(doc,
        "Screenshot of STM32CubeIDE Console view showing a successful build "
        "with '0 errors, 0 warnings' and the binary size output for POC_HT.",
        height_cm=5.0)

    h2(doc, "7.2  Run Debug Configuration")
    numbered_para(doc,
        "Ensure the Nucleo board is connected via USB to CN1.")
    numbered_para(doc,
        "In the toolbar, click the dropdown arrow next to the Debug button "
        "(the green bug icon) and select 'Debug Configurations'.")
    numbered_para(doc,
        "Select the POC_HT Debug configuration under 'STM32 Cortex-M C/C++ "
        "Application'. Confirm the ELF file path points to "
        "firmware\\Debug\\POC_HT.elf")
    numbered_para(doc,
        "Click Debug. STM32CubeIDE will flash the firmware and halt at "
        "the first line of main(). Click the Resume button (F8) or "
        "select Run → Resume to start execution.")
    numbered_para(doc,
        "To disconnect without stopping the firmware, select "
        "Run → Terminate (Ctrl+F2). The firmware will continue running "
        "on the board.")

    warning_box(doc,
        "STM32CubeIDE holds the ST-Link occupied while a debug session is "
        "active. If you need to use the virtual COM port in the Harness "
        "Tester GUI at the same time, terminate the debug session first. "
        "The COM port is shared between the debugger and the UART bridge.")

    add_page_break(doc)

# ---------------------------------------------------------------------------
# Section 8 — Post-Flash Verification
# ---------------------------------------------------------------------------

def add_section_8(doc):
    h1(doc, "8.  Post-Flash Verification")

    body_para(doc,
        "After flashing, perform the following checks to confirm the firmware "
        "is running correctly and communicating with the PC application.")

    h2(doc, "8.1  Connect the GUI")
    numbered_para(doc,
        "Ensure the Nucleo board is powered and LD1 (green) is solid ON.")
    numbered_para(doc,
        "Launch HarnessTester.exe on the PC. The GUI opens in the "
        "not-connected state shown below.")

    _img = gui_ss("GUI_IDEAL.png")
    if _img:
        insert_image(doc, _img,
                     "Figure 3 — Harness Tester GUI at launch: not connected, "
                     "no netlist loaded.", width_cm=14.0)
    else:
        screenshot_placeholder(doc,
            "Harness Tester GUI — initial not-connected state.", height_cm=5.0)

    numbered_para(doc,
        "In the Connection group box on the left panel, click the Refresh "
        "button to scan for available COM ports.")
    numbered_para(doc,
        "Select the STLink Virtual COM Port from the dropdown list. "
        "Set the baud rate to 921600.")
    numbered_para(doc,
        "Click Connect. Within 2–3 seconds the status should change from "
        "'Not connected' to 'CONNECTED — FW v1.0.0' (or v2.0.0 for the "
        "latest firmware).")

    _img2 = gui_ss("GUI_Connect.png")
    if _img2:
        insert_image(doc, _img2,
                     "Figure 4 — GUI after successful connection: status bar shows "
                     "'CONNECTED — FW v1.0.0' and the STLink COM port is selected.",
                     width_cm=14.0)
    else:
        screenshot_placeholder(doc,
            "Harness Tester GUI connected state — status 'CONNECTED — FW v2.0.0'.",
            height_cm=5.0)

    h2(doc, "8.2  Verify Firmware Version in Info Tab")
    numbered_para(doc,
        "Once connected, click the Info tab (or the Info panel button) in "
        "the GUI.")
    numbered_para(doc,
        "Confirm the following fields display correctly:")
    bullet_para(doc, "Firmware Version: v2.0.0", level=1)
    bullet_para(doc, "Board: STM32F303ZE Nucleo-144", level=1)
    bullet_para(doc, "State: IDLE", level=1)
    numbered_para(doc,
        "If the firmware version shown does not match v2.0.0, the wrong "
        "binary was flashed. Repeat the flash procedure from Section 6 "
        "using the correct POC_HT.elf file.")

    screenshot_placeholder(doc,
        "Screenshot of the Harness Tester GUI Info tab showing Firmware "
        "Version v2.0.0, State IDLE, and calibration offset value.",
        height_cm=5.0)

    h2(doc, "8.3  Basic Routing Smoke-Test")
    body_para(doc,
        "This quick check verifies that the firmware GPIO scan is working "
        "correctly before the board is handed over for harness testing.")
    numbered_para(doc,
        "Connect a single jumper wire between Side A Pin 1 (PC8) and "
        "Side B Pin 1 (PC11) on the Morpho headers.")
    numbered_para(doc,
        "In the GUI, click Auto-Scan (no netlist required).")
    numbered_para(doc,
        "In the Results Table, confirm that a PASS result appears for "
        "the pair A1 ↔ B1.")
    numbered_para(doc,
        "Remove the jumper wire and run Auto-Scan again. Confirm the "
        "A1 ↔ B1 pair no longer appears (no connection detected).")
    numbered_para(doc,
        "If both checks pass, the firmware is functioning correctly. "
        "The board is ready for harness testing.")

    note_box(doc,
        "If the smoke-test fails (connection not detected with jumper, or "
        "connection detected without jumper), check the Morpho header pin "
        "positions against the GPIO table in UM-HT-MK0-v1.0 Section 3.2. "
        "A pin off by one position is the most common cause.")

    add_page_break(doc)

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
    add_footer_page_num(doc, "FFP-HT-MK0-v1.0")
    add_doc_control(doc)
    add_section_2(doc)
    add_section_3(doc, board_img)
    add_section_4(doc, board_img)
    add_section_5(doc)
    add_section_6(doc)
    add_section_7(doc)
    add_section_8(doc)

    doc.save(OUTPUT_PATH)
    print(f"Saved: {OUTPUT_PATH}")

    # Clean up temp image
    if board_img and os.path.exists(board_img):
        os.unlink(board_img)


if __name__ == "__main__":
    main()
