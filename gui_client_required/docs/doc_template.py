# -*- coding: utf-8 -*-
"""
Shared document template — reused verbatim across all four client deliverables
(Code Walkthrough, User Manual, Flashing/Deployment Procedure, Functional Test
Procedure) so every document shares identical fonts, colors, spacing, table
style, and page layout.

USAGE:
  1. Copy this file into your new project's doc-generation scratch folder unchanged.
  2. In each per-document generation script, do:
         from doc_template import *
         doc, sec = new_document()
         build_cover_page(doc, sec, title="...", subtitle="...", doc_id="...",
                           version="1.0", date="...", system="...",
                           company="...", client="...", logo_path="...")
         build_revision_history_and_toc(doc, rows=[["1.0", "...", "Initial release", "[Author]"]])
         # ... then your content, using add_table / add_code_block / add_warning_box /
         #     numbered / bullet / add_screenshot / doc.add_heading / doc.add_paragraph ...
         build_footer(doc, sec, company="...", client="...")
         save(doc, out_path)
  3. Do NOT change font names, sizes, colors, or margins below for a "same client,
     new project" package — that is the whole point of this file. If the client
     wants a visually different package, change it here once and every document
     picks it up, rather than editing four scripts separately.
"""
from docx import Document
from docx.shared import Pt, Cm, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

# =========================================================
# FIXED STYLE CONSTANTS — identical across every document
# =========================================================
BODY_FONT = 'Calibri'
BODY_SIZE = Pt(11)
HEADING_FONT = 'Calibri'
HEADING_COLOR = RGBColor(0x1F, 0x38, 0x64)      # dark navy
CODE_FONT = 'Consolas'
CODE_SIZE = Pt(9.5)
CODE_TEXT_COLOR = RGBColor(0x20, 0x20, 0x20)
CODE_SHADING = 'F2F2F2'                          # light grey code-block background
CAPTION_SIZE = Pt(9.5)
CAPTION_COLOR = RGBColor(0x55, 0x55, 0x55)
WARNING_FILL = 'FBE4E1'                          # light red
WARNING_BORDER = 'B5352B'                        # dark red
WARNING_LABEL_COLOR = RGBColor(0xB5, 0x35, 0x2B)
WARNING_TEXT_COLOR = RGBColor(0x5A, 0x1A, 0x14)
TABLE_STYLE = 'Light Grid Accent 1'
TABLE_FONT_SIZE = Pt(9.5)
TABLE_HEADER_SIZE = Pt(9.5)
MARGIN = Cm(2.0)                                 # same on all four edges, all docs
INLINE_CODE_COLOR = RGBColor(0x8B, 0x00, 0x00)
PLACEHOLDER_COLOR = RGBColor(0x99, 0x33, 0x00)

# =========================================================
# DOCUMENT / SECTION SETUP
# =========================================================
def new_document():
    doc = Document()
    normal = doc.styles['Normal']
    normal.font.name = BODY_FONT
    normal.font.size = BODY_SIZE
    for i in range(1, 4):
        h = doc.styles[f'Heading {i}']
        h.font.name = HEADING_FONT
        h.font.color.rgb = HEADING_COLOR
    sec = doc.sections[0]
    sec.left_margin = MARGIN
    sec.right_margin = MARGIN
    sec.top_margin = MARGIN
    sec.bottom_margin = MARGIN
    _enable_update_fields(doc)
    return doc, sec

def _enable_update_fields(doc):
    """Forces Word to recompute TOC/PAGE/NUMPAGES fields on first open."""
    settings = doc.settings.element
    uf = OxmlElement('w:updateFields')
    uf.set(qn('w:val'), 'true')
    settings.append(uf)

def _add_field(paragraph, instr, placeholder_text):
    run = paragraph.add_run()
    fld_begin = OxmlElement('w:fldChar'); fld_begin.set(qn('w:fldCharType'), 'begin')
    instr_el = OxmlElement('w:instrText'); instr_el.set(qn('xml:space'), 'preserve'); instr_el.text = instr
    fld_sep = OxmlElement('w:fldChar'); fld_sep.set(qn('w:fldCharType'), 'separate')
    t_el = OxmlElement('w:t'); t_el.text = placeholder_text
    fld_end = OxmlElement('w:fldChar'); fld_end.set(qn('w:fldCharType'), 'end')
    r = run._r
    r.append(fld_begin); r.append(instr_el); r.append(fld_sep); r.append(t_el); r.append(fld_end)

# =========================================================
# COVER PAGE + REVISION HISTORY + TOC
# =========================================================
def build_cover_page(doc, sec, title, subtitle, doc_id, version, date, system,
                      company, client, logo_path, classification="Confidential"):
    if logo_path:
        doc.add_picture(logo_path, width=Inches(1.4))
        doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER
    else:
        _placeholder(doc, "Company Logo Placeholder")
        doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER

    for _ in range(3):
        doc.add_paragraph()

    t = doc.add_paragraph(); t.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = t.add_run(title); r.font.size = Pt(26); r.font.bold = True

    s = doc.add_paragraph(); s.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r2 = s.add_run(subtitle); r2.font.size = Pt(18)

    for _ in range(2):
        doc.add_paragraph()

    info_lines = [
        ("Document ID:", doc_id),
        ("Document Version:", version),
        ("Date:", date),
        ("System:", system),
        ("Prepared by:", company),
        ("Prepared for:", client),
        ("Classification:", classification),
    ]
    tbl = doc.add_table(rows=0, cols=2)
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    for label, value in info_lines:
        row = tbl.add_row().cells
        row[0].text = label
        row[1].text = value
        for p_ in row[0].paragraphs:
            for r_ in p_.runs:
                r_.font.bold = True; r_.font.size = Pt(11)
        for p_ in row[1].paragraphs:
            for r_ in p_.runs:
                r_.font.size = Pt(11)
    doc.add_page_break()

def build_revision_history_and_toc(doc, rows):
    """rows: list of [version, date, description, author]"""
    doc.add_heading("Revision History", level=1)
    add_table(doc, ["Version", "Date", "Description", "Author"], rows)

    doc.add_heading("Table of Contents", level=1)
    toc_para = doc.add_paragraph()
    _add_field(toc_para, 'TOC \\o "1-3" \\h \\z \\u',
               "Right-click here and choose \"Update Field\" to build the table of contents.")
    doc.add_page_break()

def build_footer(doc, sec, company, client):
    footer = sec.footer
    fp = footer.paragraphs[0]
    fp.alignment = WD_ALIGN_PARAGRAPH.CENTER
    fp.add_run(f"{company} — Confidential — Prepared for {client}    |    Page ").font.size = Pt(8)
    _add_field(fp, 'PAGE', '1')
    fp.add_run(" of ").font.size = Pt(8)
    _add_field(fp, 'NUMPAGES', '1')

# =========================================================
# CONTENT HELPERS — use these for every document's body
# =========================================================
def _style_table(table):
    table.style = TABLE_STYLE
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    for row in table.rows:
        for cell in row.cells:
            for p in cell.paragraphs:
                for r in p.runs:
                    r.font.size = TABLE_FONT_SIZE

def add_table(doc, headers, rows):
    t = doc.add_table(rows=1, cols=len(headers))
    _style_table(t)
    hdr = t.rows[0].cells
    for i, htext in enumerate(headers):
        hdr[i].text = htext
        for p in hdr[i].paragraphs:
            for r in p.runs:
                r.font.bold = True; r.font.size = TABLE_HEADER_SIZE
    for row in rows:
        cells = t.add_row().cells
        for i, val in enumerate(row):
            cells[i].text = str(val)
            for p in cells[i].paragraphs:
                for r in p.runs:
                    r.font.size = TABLE_FONT_SIZE
    doc.add_paragraph()
    return t

def add_code_block(doc, code_text, caption=None):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after = Pt(2)
    pPr = p._p.get_or_add_pPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear'); shd.set(qn('w:color'), 'auto'); shd.set(qn('w:fill'), CODE_SHADING)
    pPr.append(shd)
    lines = code_text.strip('\n').split('\n')
    for i, line in enumerate(lines):
        r = p.add_run(line if line.strip() else ' ')
        r.font.name = CODE_FONT; r.font.size = CODE_SIZE; r.font.color.rgb = CODE_TEXT_COLOR
        if i < len(lines) - 1:
            r.add_break()
    if caption:
        cp = doc.add_paragraph()
        cr = cp.add_run(caption)
        cr.italic = True; cr.font.size = CAPTION_SIZE; cr.font.color.rgb = CAPTION_COLOR
    doc.add_paragraph()

def add_inline_code(paragraph, text, trailing=""):
    r = paragraph.add_run(text)
    r.font.name = CODE_FONT; r.font.size = Pt(10); r.font.color.rgb = INLINE_CODE_COLOR
    if trailing:
        paragraph.add_run(trailing)

def add_warning_box(doc, text, label="CAUTION"):
    """label examples: CAUTION, WARNING, NOTE, IMPORTANT, OPEN ITEM, COORDINATION POINT"""
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(6)
    p.paragraph_format.space_after = Pt(6)
    pPr = p._p.get_or_add_pPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear'); shd.set(qn('w:color'), 'auto'); shd.set(qn('w:fill'), WARNING_FILL)
    pPr.append(shd)
    pBdr = OxmlElement('w:pBdr')
    for edge in ('top', 'left', 'bottom', 'right'):
        b = OxmlElement(f'w:{edge}')
        b.set(qn('w:val'), 'single'); b.set(qn('w:sz'), '12'); b.set(qn('w:color'), WARNING_BORDER)
        pBdr.append(b)
    pPr.append(pBdr)
    lbl = p.add_run(f"{label}:  ")
    lbl.bold = True; lbl.font.color.rgb = WARNING_LABEL_COLOR
    r = p.add_run(text)
    r.font.color.rgb = WARNING_TEXT_COLOR
    doc.add_paragraph()

def add_screenshot(doc, path, caption, width=6.3):
    doc.add_picture(path, width=Inches(width))
    doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER
    cp = doc.add_paragraph()
    cp.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cr = cp.add_run(caption)
    cr.italic = True; cr.font.size = CAPTION_SIZE; cr.font.color.rgb = CAPTION_COLOR
    doc.add_paragraph()

def _placeholder(doc, label):
    p = doc.add_paragraph()
    r = p.add_run(f"[{label}]")
    r.italic = True; r.font.color.rgb = PLACEHOLDER_COLOR
    return p

def bullet(doc, text):
    doc.add_paragraph(text, style='List Bullet')

# ---- numbered(): manual counter, NOT Word's native "List Number" style ----
# Word's built-in numbered-list style silently continues counting across
# every separate use in the document (a new procedure's step 1 renders as
# step 7 if six numbered steps appeared earlier in the doc). This bit us
# during the HT_MK1 package's formatting review. Always pass restart=True
# on the FIRST numbered() call of each new procedure/section; leave it
# False for every subsequent call in that same procedure (including calls
# separated by a screenshot or code block — those should keep counting).
_num_state = {'n': 0}
def numbered(doc, text, restart=False):
    if restart:
        _num_state['n'] = 0
    _num_state['n'] += 1
    p = doc.add_paragraph()
    p.paragraph_format.left_indent = Pt(18)
    p.paragraph_format.first_line_indent = Pt(-18)
    p.add_run(f"{_num_state['n']}.\t")
    p.add_run(text)
    return p

# =========================================================
# SAVE
# =========================================================
def save(doc, out_path):
    import os
    out_dir = os.path.dirname(out_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    doc.save(out_path)
    print("Saved:", out_path)
