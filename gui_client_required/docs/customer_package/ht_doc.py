# -*- coding: utf-8 -*-
"""Customer-package document builder (A4, Times New Roman, 14 pt minimum).

Builds one .docx to the HT customer-package page standard:

  * A4 portrait, 2.54 cm margins, header/footer 1.25 cm from the edge.
  * Page header (9 pt, right-aligned) and footer (9 pt, centred) with a thin
    navy rule; these are the only text allowed below 14 pt.
  * Everything else is set by Word styles only - no direct font or size
    overrides, no empty spacer paragraphs, no page-break paragraphs.
  * Contents, List of Figures and List of Tables are real Word fields; the
    captions use SEQ fields so the lists update.
  * Tables are fixed-layout, full text width, with column widths fitted to the
    longest unbreakable word so nothing breaks mid-word.

Fields are refreshed and the PDF is exported by finalize_word.py.
"""
from __future__ import annotations

import copy
import re
from pathlib import Path

from docx import Document
from docx.enum.section import WD_ORIENT
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn
from docx.shared import Cm, Emu
from PIL import Image, ImageFont

# ── Page geometry ──────────────────────────────────────────────────────────
PAGE_W_CM, PAGE_H_CM = 21.0, 29.7
MARGIN_CM = 2.54
HDR_FTR_CM = 1.25
TEXT_W_CM = 15.92                       # 21.0 - 2 * 2.54 (rounded as specified)
TEXT_W_TW = 9026                        # same width in twips (1 cm = 566.93)

NAVY = "1F3864"          # heading / rule colour
COVER = "0E2740"         # cover title colour
TBL_FILL = "1F4E79"      # table header fill
GREY = "BFBFBF"          # table borders
FONT = "Times New Roman"
MONO = "Consolas"
MIN_PT = 14

_FONT_FILES = {
    ("roman", False): "C:/Windows/Fonts/times.ttf",
    ("roman", True): "C:/Windows/Fonts/timesbd.ttf",
    ("mono", False): "C:/Windows/Fonts/consola.ttf",
    ("mono", True): "C:/Windows/Fonts/consolab.ttf",
}
_font_cache: dict = {}


def _pt_width(text: str, kind: str = "roman", bold: bool = False, size: float = 14) -> float:
    """Width of *text* in points at *size* pt."""
    key = (kind, bold)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(_FONT_FILES[key], 1000)
    return _font_cache[key].getlength(text) / 1000.0 * size


# ── Inline markup:  **bold**   `code` ────────────────────────────────────────
_TOKEN = re.compile(r"(\*\*.+?\*\*|`.+?`)")


def _segments(text: str):
    """Yield (text, kind) with kind in {'', 'b', 'c'}."""
    for part in _TOKEN.split(text):
        if not part:
            continue
        if part.startswith("**") and part.endswith("**"):
            yield part[2:-2], "b"
        elif part.startswith("`") and part.endswith("`"):
            yield part[1:-1], "c"
        else:
            yield part, ""


def _plain(text: str) -> str:
    return "".join(s for s, _ in _segments(text))


def _words(text: str, header: bool = False):
    """Unbreakable tokens of *text* as (token, kind, bold).  Word breaks lines
    at spaces and after hyphens only."""
    for seg, kind in _segments(text):
        for tok in re.findall(r"[^\s-]+-?|-", seg):
            yield tok, ("mono" if kind == "c" else "roman"), (header or kind == "b")


def _min_word_pt(text: str, header: bool = False) -> float:
    return max((_pt_width(t, k, b) for t, k, b in _words(text, header)), default=0.0)


def _line_pt(text: str, header: bool = False) -> float:
    tot = 0.0
    for seg, kind in _segments(text):
        tot += _pt_width(seg, "mono" if kind == "c" else "roman",
                         header or kind == "b")
    return tot


# ── Style definitions (raw WordprocessingML) ───────────────────────────────
def _rfonts(font):
    return (f'<w:rFonts w:ascii="{font}" w:hAnsi="{font}" w:cs="{font}" '
            f'w:eastAsia="{font}"/>')


def _style(sid, name, kind="paragraph", based="Normal", nxt=None, ppr="",
           rpr="", q=True, default=False, ui=None, link=None):
    d = ' w:default="1"' if default else ""
    s = f'<w:style {nsdecls("w")} w:type="{kind}"{d} w:styleId="{sid}">'
    s += f'<w:name w:val="{name}"/>'
    if based:
        s += f'<w:basedOn w:val="{based}"/>'
    if nxt:
        s += f'<w:next w:val="{nxt}"/>'
    if link:
        s += f'<w:link w:val="{link}"/>'
    if ui is not None:
        s += f'<w:uiPriority w:val="{ui}"/>'
    if q:
        s += "<w:qFormat/>"
    if ppr:
        s += f"<w:pPr>{ppr}</w:pPr>"
    if rpr:
        s += f"<w:rPr>{rpr}</w:rPr>"
    return s + "</w:style>"


def _sz(pt):          # half-points, both complex and western
    return f'<w:sz w:val="{int(pt * 2)}"/><w:szCs w:val="{int(pt * 2)}"/>'


_SPACE = lambda b, a, line=276: (f'<w:spacing w:before="{b}" w:after="{a}" '
                                 f'w:line="{line}" w:lineRule="auto"/>')

_RIGHT_TAB = f'<w:tab w:val="right" w:leader="dot" w:pos="{TEXT_W_TW}"/>'

STYLES = [
    # --- base ---------------------------------------------------------------
    _style("Normal", "Normal", based=None, default=True,
           ppr=_SPACE(0, 160), rpr=_rfonts(FONT) + _sz(14)),
    _style("BodyText", "Body Text", nxt="BodyText",
           ppr='<w:jc w:val="both"/>' + _SPACE(0, 160)),
    _style("ListParagraph", "List Paragraph", ui=34,
           ppr='<w:ind w:left="567" w:hanging="283"/>' + _SPACE(0, 120)),
    _style("ProcedureStep", "Procedure Step", based="BodyText",
           ppr='<w:tabs><w:tab w:val="left" w:pos="567"/></w:tabs>'
               '<w:ind w:left="567" w:hanging="567"/>' + _SPACE(0, 120)),
    # --- headings -----------------------------------------------------------
    _style("Heading1", "heading 1", nxt="BodyText", ui=9,
           ppr='<w:keepNext/><w:keepLines/><w:numPr><w:ilvl w:val="0"/><w:numId w:val="90"/></w:numPr>'
               + _SPACE(360, 160) + '<w:outlineLvl w:val="0"/>',
           rpr=f'<w:b/><w:bCs/><w:color w:val="{NAVY}"/>' + _sz(20)),
    _style("Heading2", "heading 2", nxt="BodyText", ui=9,
           ppr='<w:keepNext/><w:keepLines/><w:numPr><w:ilvl w:val="1"/><w:numId w:val="90"/></w:numPr>'
               + _SPACE(280, 120) + '<w:outlineLvl w:val="1"/>',
           rpr=f'<w:b/><w:bCs/><w:color w:val="{NAVY}"/>' + _sz(16)),
    _style("Heading3", "heading 3", nxt="BodyText", ui=9,
           ppr='<w:keepNext/><w:keepLines/><w:numPr><w:ilvl w:val="2"/><w:numId w:val="90"/></w:numPr>'
               + _SPACE(240, 80) + '<w:outlineLvl w:val="2"/>',
           rpr=f'<w:b/><w:bCs/><w:color w:val="{NAVY}"/>' + _sz(14)),
    _style("FrontHeading", "Front Heading", nxt="BodyText",
           ppr='<w:keepNext/><w:keepLines/>' + _SPACE(0, 200),
           rpr=f'<w:b/><w:bCs/><w:color w:val="{NAVY}"/>' + _sz(20)),
    _style("FrontLabel", "Front Label", nxt="BodyText",
           ppr='<w:keepNext/><w:keepLines/>' + _SPACE(240, 80),
           rpr=f'<w:b/><w:bCs/><w:color w:val="{NAVY}"/>' + _sz(14)),
    # --- cover --------------------------------------------------------------
    _style("Title", "Title", nxt="Subtitle", ui=10,
           ppr='<w:jc w:val="center"/>' + _SPACE(2400, 240, 240),
           rpr=f'<w:b/><w:bCs/><w:color w:val="{COVER}"/>' + _sz(36)),
    _style("Subtitle", "Subtitle", nxt="BodyText", ui=11,
           ppr='<w:jc w:val="center"/>' + _SPACE(240, 1800, 240),
           rpr=f'<w:b/><w:bCs/><w:i/><w:iCs/><w:color w:val="{COVER}"/>' + _sz(26)),
    # --- tables -------------------------------------------------------------
    _style("TableData", "Table Data", based="Normal",
           ppr=_SPACE(40, 40, 240)),
    _style("TableHeader", "Table Header", based="TableData",
           ppr='<w:keepNext/><w:jc w:val="center"/>',
           rpr='<w:b/><w:bCs/><w:color w:val="FFFFFF"/>'),
    _style("Caption", "caption", nxt="BodyText", ui=35,
           ppr='<w:jc w:val="center"/>' + _SPACE(80, 240, 240),
           rpr=f'<w:i/><w:iCs/><w:color w:val="{NAVY}"/>' + _sz(14)),
    _style("FigurePara", "Figure", based="Normal", nxt="Caption",
           ppr='<w:keepNext/><w:jc w:val="center"/>' + _SPACE(120, 0, 240)),
    # --- callouts / code ----------------------------------------------------
    _style("Callout", "Callout", based="BodyText", nxt="BodyText",
           ppr='<w:keepLines/><w:shd w:val="clear" w:color="auto" w:fill="FBE4E1"/>'
               '<w:ind w:left="113" w:right="113"/>' + _SPACE(0, 160)),
    _style("CodeBlock", "Code Block", based="Normal", nxt="CodeBlock",
           ppr='<w:keepNext/><w:keepLines/><w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>'
               '<w:ind w:left="113" w:right="113"/><w:jc w:val="left"/>' + _SPACE(0, 0, 240),
           rpr=_rfonts(MONO) + _sz(14)),
    _style("CodeBlockEnd", "Code Block End", based="CodeBlock", nxt="BodyText",
           ppr='<w:keepNext w:val="0"/>' + _SPACE(0, 160, 240)),
    # --- contents lists -----------------------------------------------------
    _style("TOC1", "toc 1", nxt="BodyText", ui=39, q=False,
           ppr=f'<w:tabs><w:tab w:val="left" w:pos="567"/>{_RIGHT_TAB}</w:tabs>'
               '<w:ind w:left="567" w:hanging="567"/>' + _SPACE(30, 0, 240),
           rpr='<w:b/><w:bCs/>'),
    _style("TOC2", "toc 2", nxt="BodyText", ui=39, q=False,
           ppr=f'<w:tabs><w:tab w:val="left" w:pos="1247"/>{_RIGHT_TAB}</w:tabs>'
               '<w:ind w:left="1247" w:hanging="794"/>' + _SPACE(0, 0, 240)),
    _style("TOC3", "toc 3", nxt="BodyText", ui=39, q=False,
           ppr=f'<w:tabs><w:tab w:val="left" w:pos="2155"/>{_RIGHT_TAB}</w:tabs>'
               '<w:ind w:left="2155" w:hanging="1020"/>' + _SPACE(0, 0, 240)),
    _style("TableofFigures", "table of figures", nxt="BodyText", ui=99, q=False,
           ppr=f'<w:tabs>{_RIGHT_TAB}</w:tabs>'
               '<w:ind w:left="567" w:hanging="567"/>' + _SPACE(0, 60, 240)),
    # Holder for the closing mark of a generated list; 1 pt high so a full
    # contents page cannot spill an empty page.
    _style("FieldEnd", "Field End", based="Normal", nxt="BodyText", q=False,
           ppr='<w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/>',
           rpr=_sz(14)),
    # --- header / footer (the only 9 pt text) ----------------------------------
    _style("Header", "header", ui=99, q=False,
           ppr='<w:jc w:val="right"/>' + _SPACE(0, 0, 240), rpr=_sz(9)),
    _style("Footer", "footer", ui=99, q=False,
           ppr='<w:jc w:val="center"/>' + _SPACE(0, 0, 240), rpr=_sz(9)),
    # --- character styles ---------------------------------------------------
    _style("Strong", "Strong", kind="character", based="DefaultParagraphFont",
           rpr="<w:b/><w:bCs/>", ui=22),
    _style("Emphasis", "Emphasis", kind="character", based="DefaultParagraphFont",
           rpr="<w:i/><w:iCs/>", ui=20),
    _style("CodeChar", "Code Char", kind="character", based="DefaultParagraphFont",
           rpr=_rfonts(MONO) + _sz(14)),
    _style("Hyperlink", "Hyperlink", kind="character", based="DefaultParagraphFont",
           rpr="", ui=99, q=False),
]

# Multilevel heading numbering (1, 1.1, 1.1.1) and one bullet list.
_NUMBERING = f"""
<w:abstractNum {nsdecls("w")} w:abstractNumId="90">
  <w:multiLevelType w:val="multilevel"/>
  <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:pStyle w:val="Heading1"/>
    <w:lvlText w:val="%1"/><w:lvlJc w:val="left"/>
    <w:pPr><w:tabs><w:tab w:val="num" w:pos="567"/></w:tabs><w:ind w:left="567" w:hanging="567"/></w:pPr><w:rPr>{_rfonts(FONT)}</w:rPr></w:lvl>
  <w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:pStyle w:val="Heading2"/>
    <w:lvlText w:val="%1.%2"/><w:lvlJc w:val="left"/>
    <w:pPr><w:tabs><w:tab w:val="num" w:pos="794"/></w:tabs><w:ind w:left="794" w:hanging="794"/></w:pPr><w:rPr>{_rfonts(FONT)}</w:rPr></w:lvl>
  <w:lvl w:ilvl="2"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:pStyle w:val="Heading3"/>
    <w:lvlText w:val="%1.%2.%3"/><w:lvlJc w:val="left"/>
    <w:pPr><w:tabs><w:tab w:val="num" w:pos="1020"/></w:tabs><w:ind w:left="1020" w:hanging="1020"/></w:pPr><w:rPr>{_rfonts(FONT)}</w:rPr></w:lvl>
</w:abstractNum>
"""
_BULLET = f"""
<w:abstractNum {nsdecls("w")} w:abstractNumId="91">
  <w:multiLevelType w:val="hybridMultilevel"/>
  <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/>
    <w:lvlText w:val="&#8226;"/><w:lvlJc w:val="left"/>
    <w:pPr><w:ind w:left="567" w:hanging="283"/></w:pPr>
    <w:rPr>{_rfonts(FONT)}</w:rPr></w:lvl>
</w:abstractNum>
"""


def _install_styles(doc: Document) -> None:
    styles = doc.styles.element
    # docDefaults: Times New Roman, 14 pt, no theme fonts.
    for dd in styles.findall(qn("w:docDefaults")):
        styles.remove(dd)
    styles.insert(0, parse_xml(
        f'<w:docDefaults {nsdecls("w")}><w:rPrDefault><w:rPr>{_rfonts(FONT)}'
        f'{_sz(14)}<w:lang w:val="en-GB" w:eastAsia="en-GB" w:bidi="ar-SA"/>'
        f'</w:rPr></w:rPrDefault><w:pPrDefault><w:pPr>{_SPACE(0, 160)}</w:pPr>'
        f'</w:pPrDefault></w:docDefaults>'))
    # Drop every stock style we redefine (and any with a clashing id).
    new_ids = {re.search(r'w:styleId="([^"]+)"', s).group(1) for s in STYLES}
    new_names = {re.search(r'<w:name w:val="([^"]+)"', s).group(1).lower() for s in STYLES}
    for st in list(styles.findall(qn("w:style"))):
        name = st.find(qn("w:name")).get(qn("w:val")).lower()
        if st.get(qn("w:styleId")) in new_ids or name in new_names:
            styles.remove(st)
    for s in STYLES:
        styles.append(parse_xml(s))
    # Make sure the paragraph default exists for character styles.
    if styles.find(f'.//{qn("w:style")}[@{qn("w:styleId")}="DefaultParagraphFont"]') is None:
        styles.append(parse_xml(
            f'<w:style {nsdecls("w")} w:type="character" w:default="1" '
            f'w:styleId="DefaultParagraphFont"><w:name w:val="Default Paragraph Font"/>'
            f'<w:uiPriority w:val="1"/><w:semiHidden/><w:unhideWhenUsed/></w:style>'))
    # No theme fonts anywhere.
    for rf in styles.iter(qn("w:rFonts")):
        for attr in list(rf.attrib):
            if "Theme" in attr:
                del rf.attrib[attr]
    # numbering
    numbering = doc.part.numbering_part.element
    for tag in ("w:abstractNum", "w:num"):
        for el in list(numbering.findall(qn(tag))):
            numbering.remove(el)
    numbering.append(parse_xml(_NUMBERING))
    numbering.append(parse_xml(_BULLET))
    for nid, aid in ((90, 90), (91, 91)):
        numbering.append(parse_xml(
            f'<w:num {nsdecls("w")} w:numId="{nid}"><w:abstractNumId w:val="{aid}"/></w:num>'))


# ── Field helpers ─────────────────────────────────────────────────────────────
def _fld_runs(par, instr: str, result: str = "1", style: str | None = None):
    def r():
        run = par.add_run()
        if style:
            run.style = style
        return run
    a = r(); fc = OxmlElement("w:fldChar"); fc.set(qn("w:fldCharType"), "begin"); a._r.append(fc)
    b = r(); it = OxmlElement("w:instrText"); it.set(qn("xml:space"), "preserve")
    it.text = f" {instr} "; b._r.append(it)
    c = r(); fc = OxmlElement("w:fldChar"); fc.set(qn("w:fldCharType"), "separate"); c._r.append(fc)
    d = r(); d.text = result
    e = r(); fc = OxmlElement("w:fldChar"); fc.set(qn("w:fldCharType"), "end"); e._r.append(fc)


def _border(par, side: str):
    ppr = par._p.get_or_add_pPr()
    pbdr = ppr.find(qn("w:pBdr"))
    if pbdr is None:
        pbdr = OxmlElement("w:pBdr")
        ppr.append(pbdr)
    el = OxmlElement(f"w:{side}")
    for k, v in (("val", "single"), ("sz", "4"), ("space", "4"), ("color", NAVY)):
        el.set(qn(f"w:{k}"), v)
    pbdr.append(el)


# ── The document ────────────────────────────────────────────────────────────
class HTDoc:
    def __init__(self, doc_no: str, doc_title: str, version: str, date: str,
                 company: str, year: str, product: str = "HT_MK0 Harness Tester"):
        self.doc_no, self.doc_title = doc_no, doc_title
        self.version, self.date = version, date
        self.company, self.year, self.product = company, year, product
        self.doc = Document()
        self._tables = 0
        self._figures = 0
        self._setup_page()
        _install_styles(self.doc)
        self._header_footer()
        # the template starts with one empty paragraph; remove it
        body = self.doc.element.body
        for p in list(body.findall(qn("w:p"))):
            body.remove(p)

    # --- page / header / footer ---------------------------------------------------
    def _setup_page(self):
        s = self.doc.sections[0]
        s.orientation = WD_ORIENT.PORTRAIT
        s.page_width, s.page_height = Cm(PAGE_W_CM), Cm(PAGE_H_CM)
        s.left_margin = s.right_margin = s.top_margin = s.bottom_margin = Cm(MARGIN_CM)
        s.header_distance = s.footer_distance = Cm(HDR_FTR_CM)

    def _header_footer(self):
        s = self.doc.sections[0]
        hdr = s.header
        hdr.is_linked_to_previous = False
        ps = hdr.paragraphs
        first = ps[0]
        first.style = "header"
        first.add_run(f"Document No: {self.doc_no}")
        for text in (f"Version: {self.version}", f"Date: {self.date}"):
            p = hdr.add_paragraph(text, style="header")
        p = hdr.add_paragraph(style="header")
        p.add_run("Page ")
        _fld_runs(p, "PAGE", "1")
        p.add_run(" of ")
        _fld_runs(p, "NUMPAGES", "1")
        _border(p, "bottom")
        ftr = s.footer
        ftr.is_linked_to_previous = False
        f1 = ftr.paragraphs[0]
        f1.style = "footer"
        f1.add_run("This document is confidential & proprietary.")
        _border(f1, "top")
        f2 = ftr.add_paragraph(style="footer")
        f2.add_run(f"Copyright\u00a9{self.year} All Rights Reserved by {self.company}")

    # --- text -------------------------------------------------------------------
    def _runs(self, par, text: str):
        for seg, kind in _segments(text):
            run = par.add_run(seg)
            if kind == "b":
                run.style = "Strong"
            elif kind == "c":
                run.style = "CodeChar"

    def _par(self, text: str, style: str, page_break: bool = False, keep_next=False):
        p = self.doc.add_paragraph(style=style)
        self._runs(p, text)
        if page_break:
            p.paragraph_format.page_break_before = True
        if keep_next:
            p.paragraph_format.keep_with_next = True
        return p

    def h1(self, text, page_break=False):
        return self._par(text, "heading 1", page_break)

    def h2(self, text):
        return self._par(text, "heading 2")

    def h3(self, text):
        return self._par(text, "heading 3")

    def p(self, text):
        return self._par(text, "Body Text")

    def bullets(self, items):
        for it in items:
            p = self._par(it, "List Paragraph")
            ppr = p._p.get_or_add_pPr()
            num = parse_xml(f'<w:numPr {nsdecls("w")}><w:ilvl w:val="0"/><w:numId w:val="91"/></w:numPr>')
            ppr.append(num)
        return self

    def steps(self, items):
        """Numbered procedure: '1.<tab>text' with a 1 cm hanging indent."""
        for i, it in enumerate(items, 1):
            self._par(f"{i}.\t{it}", "Procedure Step")
        return self

    def note(self, text, label="Note:"):
        p = self.doc.add_paragraph(style="Callout")
        r = p.add_run(label + " ")
        r.style = "Strong"
        self._runs(p, text)
        return p

    def warning(self, text):
        return self.note(text, "WARNING:")

    def code(self, lines):
        lines = list(lines)
        for i, ln in enumerate(lines):
            if len(ln) > 56:
                raise ValueError(f"code line too long ({len(ln)}): {ln!r}")
            p = self.doc.add_paragraph(style="Code Block End" if i == len(lines) - 1 else "Code Block")
            r = p.add_run(ln if ln else "\u00a0")
        return self

    # --- captions -------------------------------------------------------------
    def _caption(self, kind: str, text: str):
        if kind == "Table":
            self._tables += 1
            n = self._tables
        else:
            self._figures += 1
            n = self._figures
        p = self.doc.add_paragraph(style="caption")
        p.add_run(f"{kind} ")
        _fld_runs(p, f"SEQ {kind} \\* ARABIC", str(n))
        p.add_run(f": {text}")
        return p

    # --- tables -----------------------------------------------------------------
    def _fit_columns(self, headers, rows, weights=None):
        ncol = len(headers if headers else rows[0])
        pad_pt = 12.0                             # 2 x 100 twips cell margin + slack
        mins, prefs = [], []
        for c in range(ncol):
            cells = []
            if headers:
                cells.append((headers[c], True))
            cells += [(r[c], False) for r in rows]
            mn = max(_min_word_pt(t, h) for t, h in cells) + pad_pt
            pf = max(max((_line_pt(l, h) for l in t.split("\n")), default=0.0)
                     for t, h in cells) + pad_pt
            mins.append(mn); prefs.append(max(pf, mn))
        total = TEXT_W_TW / 20.0                  # points
        if sum(mins) > total:
            raise ValueError("table cannot fit at 14 pt without breaking a word; "
                             f"minimum widths {[round(m) for m in mins]} pt > {total:.0f} pt "
                             f"(headers {headers})")
        widths = list(mins)
        spare = total - sum(widths)
        if weights:                               # explicit proportional shares
            share = [w / sum(weights) for w in weights]
            tgt = [max(mins[i], share[i] * total) for i in range(ncol)]
            # re-balance so the sum is exact
            over = sum(tgt) - total
            while over > 0.01:
                room = [tgt[i] - mins[i] for i in range(ncol)]
                tot = sum(room)
                if tot <= 0:
                    break
                tgt = [tgt[i] - over * room[i] / tot for i in range(ncol)]
                over = sum(tgt) - total
            widths = tgt
        else:
            want = [prefs[i] - mins[i] for i in range(ncol)]
            if sum(want) <= spare and sum(want) > 0:
                widths = [mins[i] + want[i] for i in range(ncol)]
                spare -= sum(want)
                widths = [w + spare * prefs[i] / sum(prefs) for i, w in enumerate(widths)]
            elif sum(want) > 0:
                widths = [mins[i] + spare * want[i] / sum(want) for i in range(ncol)]
            else:
                widths = [mins[i] + spare / ncol for i in range(ncol)]
        tw = [int(round(w * 20)) for w in widths]
        tw[-1] += TEXT_W_TW - sum(tw)
        return tw

    def table(self, headers, rows, caption: str, weights=None, center_cols=(),
              key_col: bool = False, keep: bool | None = None):
        """Full-width table with a repeating dark-blue header row.

        key_col: no header row; first column holds labels (cover-style table).
        """
        rows = [[str(c) for c in r] for r in rows]
        headers = [str(h) for h in headers] if headers else None
        if keep is None:                 # short tables stay on one page
            keep = len(rows) <= 10 and sum(len(c) for r in rows for c in r) < 900
        tw = self._fit_columns(headers, rows, weights)
        ncol = len(tw)
        t = self.doc.add_table(rows=0, cols=ncol)
        tbl = t._tbl
        tblPr = tbl.tblPr
        for el in list(tblPr):
            tblPr.remove(el)
        tblPr.append(parse_xml(f'<w:tblW {nsdecls("w")} w:w="{TEXT_W_TW}" w:type="dxa"/>'))
        tblPr.append(parse_xml(f'<w:jc {nsdecls("w")} w:val="left"/>'))
        tblPr.append(parse_xml(
            f'<w:tblBorders {nsdecls("w")}>'
            + "".join(f'<w:{s} w:val="single" w:sz="4" w:space="0" w:color="{GREY}"/>'
                      for s in ("top", "left", "bottom", "right", "insideH", "insideV"))
            + "</w:tblBorders>"))
        tblPr.append(parse_xml(f'<w:tblLayout {nsdecls("w")} w:type="fixed"/>'))
        tblPr.append(parse_xml(
            f'<w:tblCellMar {nsdecls("w")}><w:top w:w="0" w:type="dxa"/>'
            f'<w:left w:w="100" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/>'
            f'<w:right w:w="100" w:type="dxa"/></w:tblCellMar>'))
        tblPr.append(parse_xml(f'<w:tblLook {nsdecls("w")} w:val="04A0" w:firstRow="1" '
                               f'w:lastRow="0" w:firstColumn="0" w:lastColumn="0" '
                               f'w:noHBand="0" w:noVBand="1"/>'))
        grid = tbl.tblGrid
        for gc in list(grid):
            grid.remove(gc)
        for w in tw:
            gc = OxmlElement("w:gridCol"); gc.set(qn("w:w"), str(w)); grid.append(gc)

        def add_row(cells, header=False, last=False, key=False):
            row = t.add_row()
            trPr = row._tr.get_or_add_trPr()
            trPr.append(OxmlElement("w:cantSplit"))
            if header:
                trPr.append(OxmlElement("w:tblHeader"))
            for ci, (cell, text) in enumerate(zip(row.cells, cells)):
                tcPr = cell._tc.get_or_add_tcPr()
                for el in list(tcPr):
                    tcPr.remove(el)
                tcPr.append(parse_xml(f'<w:tcW {nsdecls("w")} w:w="{tw[ci]}" w:type="dxa"/>'))
                if header:
                    tcPr.append(parse_xml(f'<w:shd {nsdecls("w")} w:val="clear" w:color="auto" '
                                          f'w:fill="{TBL_FILL}"/>'))
                tcPr.append(parse_xml(f'<w:vAlign {nsdecls("w")} w:val="center"/>'))
                lines = text.split("\n") if text else [""]
                first = True
                for ln in lines:
                    par = cell.paragraphs[0] if first else cell.add_paragraph()
                    first = False
                    par.style = "Table Header" if header else "Table Data"
                    self._runs(par, ln)
                    if key and ci == 0:
                        for r in par.runs:
                            r.style = "Strong"
                    if ci in center_cols and not header:
                        par.alignment = 1
                    if last or keep:
                        par.paragraph_format.keep_with_next = True

        if headers:
            add_row(headers, header=True)
        for i, r in enumerate(rows):
            add_row(r, last=(i == len(rows) - 1), key=key_col)
        self._caption("Table", caption)
        return t

    # --- figures ------------------------------------------------------------
    def figure(self, path, caption: str, width_cm: float | None = None, max_h_cm: float = 17.5):
        path = str(path)
        with Image.open(path) as im:
            w, h = im.size
        width = min(width_cm or TEXT_W_CM, TEXT_W_CM)
        if width * h / w > max_h_cm:
            width = max_h_cm * w / h
        p = self.doc.add_paragraph(style="Figure")
        p.add_run().add_picture(path, width=Cm(width))
        self._caption("Figure", caption)
        return p

    # --- front matter / cover ------------------------------------------------------
    def cover(self, project: str):
        self.doc.add_paragraph(self.product, style="Title")
        self.doc.add_paragraph(self.doc_title, style="Subtitle")
        self.table(None, [["Document ID", self.doc_no], ["Revision", self.version],
                          ["Date", self.date], ["Project", project]],
                   "Document identification", key_col=True, weights=[35, 65])
        # the cover table's caption is not wanted on the cover page; drop it and
        # keep the table counter for the real tables
        cap = self.doc.element.body.findall(qn("w:p"))[-1]
        self.doc.element.body.remove(cap)
        self._tables -= 1

    def front_matter(self):
        d = self
        lab = self._par("Approval of Document:", "Front Label", page_break=True)
        self.table(["", "Name", "Designation", "Date"],
                   [["Prepared By", "", "", ""], ["Reviewed By", "", "", ""],
                    ["Approved By", "", "", ""]],
                   "Document approval", weights=[28, 28, 28, 16])
        self._par("Table of Revision:", "Front Label")
        self.table(["Version", "Note / Comment", "Date"],
                   [[self.version, "Initial release", self.date]],
                   "Revision history", weights=[16, 58, 26])
        self._par("Distribution List (for limited distribution only):", "Front Label")
        self.table(["S. No.", "Name", "Organization / Department"],
                   [["1", "", ""], ["2", "", ""], ["3", "", ""]],
                   "Distribution list", weights=[14, 40, 46])
        self._par("Contact Details:", "Front Label")
        self.table(["S. No.", "Name", "Communication Details"],
                   [["1", "", ""], ["2", "", ""]],
                   "Contact details", weights=[14, 40, 46])
        self.table(None, [["Registered Office Address", ""]],
                   "Registered office", key_col=True, weights=[40, 60])

    def contents(self):
        self._par("Contents", "Front Heading", page_break=True)
        self._toc_field('TOC \\o "1-3" \\h \\z \\u')
        self._par("List of Figures", "Front Heading", page_break=True)
        self._toc_field('TOC \\h \\z \\c "Figure"')
        self._par("List of Tables", "Front Heading", page_break=True)
        self._toc_field('TOC \\h \\z \\c "Table"')

    def _toc_field(self, instr):
        p = self.doc.add_paragraph(style="Field End")
        _fld_runs(p, instr, "Right-click and choose Update Field.")

    def standard_intro(self, purpose, audience, related):
        """1 Introduction: Purpose, Audience, Related Documents."""
        self.h1("Introduction", page_break=True)
        self.h2("Purpose")
        for t in purpose:
            self.p(t)
        self.h2("Audience")
        for t in audience:
            self.p(t)
        self.h2("Related Documents")
        self.p("The HT_MK0 customer package contains the six documents listed "
               "below. Each is issued as an editable Word file and a PDF copy.")
        self.table(["No.", "Document", "Document No.", "Read it for"],
                   related, "HT_MK0 customer-package documents")

    def save(self, path):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.doc.core_properties.title = f"{self.product} - {self.doc_title}"
        self.doc.core_properties.author = self.company
        self.doc.save(str(path))


PACKAGE_DOCS = [
    ["1", "System Overview", "HT_MK0_OVW", "What the tester does and how"],
    ["2", "User Manual", "HT_MK0_UM", "Running tests and reading results"],
    ["3", "GUI Functional Description", "HT_MK0_GUI", "Every screen, button and message"],
    ["4", "Flashing Procedure", "HT_MK0_FLASH", "Programming the firmware"],
    ["5", "Functional Test Procedure", "HT_MK0_FTP", "Acceptance testing of a unit"],
    ["6", "Code Walkthrough", "HT_MK0_CWT", "Firmware and GUI internals"],
]
