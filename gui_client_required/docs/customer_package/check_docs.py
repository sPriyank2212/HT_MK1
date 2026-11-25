# -*- coding: utf-8 -*-
"""Verify a finished .docx/.pdf pair against the customer-package standard."""
from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path

import fitz
from docx import Document
from docx.oxml.ns import qn

from ht_doc import TEXT_W_CM, _words

HDR_FTR = re.compile(r"^(Document No:|Version:|Date:|Page \d+ of \d+|This document is confidential|Copyright)")
OK_FONTS = ("TimesNewRoman", "Consolas")


def check(docx_path: str, pdf_path: str | None = None) -> list[str]:
    docx_path = Path(docx_path)
    pdf_path = Path(pdf_path or docx_path.with_suffix(".pdf"))
    problems: list[str] = []
    notes: list[str] = []

    pdf = fitz.open(str(pdf_path))
    alltext = ""
    small_body = []
    bad_font = set()
    blank = []
    for pn, page in enumerate(pdf, 1):
        txt = page.get_text()
        alltext += txt + "\n"
        content = False
        for b in page.get_text("dict")["blocks"]:
            if b["type"] == 1:
                content = True
            for ln in b.get("lines", []):
                line_text = "".join(s["text"] for s in ln["spans"]).strip()
                for s in ln["spans"]:
                    if not s["text"].strip():
                        continue
                    if not s["font"].startswith(OK_FONTS):
                        bad_font.add(s["font"])
                    is_hf = bool(HDR_FTR.match(line_text)) and abs(s["size"] - 9) < 0.2
                    if s["size"] < 13.9 and not is_hf:
                        small_body.append((pn, round(s["size"], 1), s["text"][:40]))
                    if not is_hf and s["text"].strip():
                        content = True
        if page.get_drawings() and not content:
            pass
        if not content:
            blank.append(pn)
    if small_body:
        problems.append(f"text below 14 pt outside header/footer: {small_body[:5]}")
    if bad_font:
        problems.append(f"fonts other than Times New Roman / Consolas: {sorted(bad_font)}")
    if blank:
        problems.append(f"blank pages: {blank}")

    # header/footer present on every page
    for pn, page in enumerate(pdf, 1):
        t = page.get_text()
        if f"Page {pn} of {len(pdf)}" not in t:
            problems.append(f"page {pn}: header 'Page X of Y' missing or wrong")
            break

    # ── docx structure ──────────────────────────────────────────────────────────────────
    doc = Document(str(docx_path))
    body = doc.element.body
    sect = doc.sections[0]
    if abs(sect.page_width.cm - 21.0) > 0.01 or abs(sect.page_height.cm - 29.7) > 0.01:
        problems.append("page is not A4")
    for side in ("left_margin", "right_margin", "top_margin", "bottom_margin"):
        if abs(getattr(sect, side).cm - 2.54) > 0.01:
            problems.append(f"{side} is not 2.54 cm")
    if abs(sect.header_distance.cm - 1.25) > 0.01 or abs(sect.footer_distance.cm - 1.25) > 0.01:
        problems.append("header/footer distance is not 1.25 cm")

    # empty spacer paragraphs and page-break paragraphs (outside tables)
    empties = 0
    brk = 0
    direct = 0
    toc_styles = {"TOC1", "TOC2", "TOC3", "TableofFigures"}
    for p in body.iterchildren(qn("w:p")):
        ppr = p.find(qn("w:pPr"))
        style = ""
        if ppr is not None and ppr.find(qn("w:pStyle")) is not None:
            style = ppr.find(qn("w:pStyle")).get(qn("w:val"))
        text = "".join(t.text or "" for t in p.iter(qn("w:t")))
        has_obj = p.find(".//" + qn("w:drawing")) is not None or p.find(".//" + qn("w:fldChar")) is not None
        if not text.strip() and not has_obj:
            empties += 1
        for br in p.iter(qn("w:br")):
            if br.get(qn("w:type")) == "page":
                brk += 1
        if style in toc_styles:
            continue
        for r in p.findall(qn("w:r")):
            rpr = r.find(qn("w:rPr"))
            if rpr is not None and (rpr.find(qn("w:sz")) is not None or rpr.find(qn("w:rFonts")) is not None):
                direct += 1
    if empties:
        problems.append(f"{empties} empty paragraph(s) in the body")
    if brk:
        problems.append(f"{brk} manual page-break run(s)")
    if direct:
        problems.append(f"{direct} run(s) with a direct font/size override")

    # figure widths
    for shp in doc.inline_shapes:
        if shp.width.cm > TEXT_W_CM + 0.01:
            problems.append(f"picture wider than text: {shp.width.cm:.2f} cm")

    # tables: full width, repeating header, no splitting rows, no broken words
    for ti, t in enumerate(doc.tables, 1):
        tw = t._tbl.tblPr.find(qn("w:tblW"))
        if tw is None or int(tw.get(qn("w:w"))) != 9026:
            problems.append(f"table {ti}: not full text width")
        grid = [int(g.get(qn("w:w"))) for g in t._tbl.tblGrid.findall(qn("w:gridCol"))]
        if sum(grid) != 9026:
            problems.append(f"table {ti}: grid sums to {sum(grid)}")
        for ri, row in enumerate(t.rows):
            trpr = row._tr.trPr
            if trpr is None or trpr.find(qn("w:cantSplit")) is None:
                problems.append(f"table {ti} row {ri + 1}: may split across pages")
                break
        first = t.rows[0]._tr.trPr
        header = first is not None and first.find(qn("w:tblHeader")) is not None
        text_all = " ".join(c.text for r in t.rows for c in r.cells)
        for r in t.rows:
            for c in r.cells:
                for par in c.paragraphs:
                    for tok, kind, bold in _words(par.text):
                        if len(tok) >= 5 and tok not in alltext:
                            problems.append(f"table {ti}: word '{tok}' is not on one line in the PDF")
        # header row must carry the fill when present
        if header:
            shd = t.rows[0].cells[0]._tc.tcPr.find(qn("w:shd"))
            if shd is None:
                problems.append(f"table {ti}: header row has no fill")

    # captions vs lists
    caps = {"Table": 0, "Figure": 0}
    for p in doc.paragraphs:
        if p.style.name.lower() == "caption":
            for k in caps:
                if p.text.startswith(k + " "):
                    caps[k] += 1
    pages = [pg.get_text() for pg in pdf]

    def list_entries(title, kind):
        idx = next((i for i, t in enumerate(pages) if re.search(r"^\s*" + title + r"\s*$", t, re.M)), None)
        if idx is None:
            return None
        n = 0
        for i in range(idx, len(pages)):
            if i > idx and re.search(r"^\s*(List of|Contents|1\s+Introduction)", pages[i], re.M):
                break
            n += len(re.findall(r"^" + kind + r" \d+: ", pages[i], re.M))
            if i > idx and not re.search(r"^" + kind + r" \d+: ", pages[i], re.M):
                break
        return n

    for title, kind in (("List of Figures", "Figure"), ("List of Tables", "Table")):
        n = list_entries(title, kind)
        if n is None:
            problems.append(f"'{title}' page not found")
        elif n != caps[kind]:
            problems.append(f"{title}: {n} entries for {caps[kind]} captions")

    notes.append(f"{len(pdf)} pages, {len(doc.tables)} tables, {caps['Table']} table captions, "
                 f"{caps['Figure']} figures")
    return notes + [("PROBLEM: " + p) for p in problems]


if __name__ == "__main__":
    bad = False
    for a in sys.argv[1:]:
        print(Path(a).name)
        for line in check(a):
            print("   ", line)
            bad = bad or line.startswith("PROBLEM")
    sys.exit(1 if bad else 0)
