# -*- coding: utf-8 -*-
"""Open a .docx in Word, refresh every field, save it, and export the PDF."""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

import pythoncom
import win32com.client as win32

WD_FORMAT_PDF = 17
WD_REPAGINATE = 1


def finalize(docx_path: str, pdf_path: str | None = None) -> int:
    """Update contents, figures list, tables list, header/footer fields.
    Returns the page count."""
    docx_path = str(Path(docx_path).resolve())
    pdf_path = str(Path(pdf_path or Path(docx_path).with_suffix(".pdf")).resolve())
    pythoncom.CoInitialize()
    word = win32.DispatchEx("Word.Application")
    word.Visible = False
    word.DisplayAlerts = 0
    try:
        doc = word.Documents.Open(docx_path, ReadOnly=False, AddToRecentFiles=False)
        doc.Repaginate()
        # Two passes: the contents pages themselves shift the page numbers.
        for _ in range(2):
            doc.Fields.Update()
            for toc in doc.TablesOfContents:
                toc.Update()
            for tof in doc.TablesOfFigures:
                tof.Update()
            doc.Repaginate()
        for sec in doc.Sections:
            for hf in list(sec.Headers) + list(sec.Footers):
                hf.Range.Fields.Update()
        # Word tags the tab characters in generated lists with 12 pt theme-font
        # formatting.  Reset it so the lists carry only their style.
        for toc in list(doc.TablesOfContents) + list(doc.TablesOfFigures):
            toc.Range.Font.Reset()
        pages = doc.ComputeStatistics(2)           # wdStatisticPages
        doc.Save()
        doc.ExportAsFixedFormat(OutputFileName=pdf_path, ExportFormat=WD_FORMAT_PDF,
                                OpenAfterExport=False, OptimizeFor=0,
                                CreateBookmarks=1, DocStructureTags=True,
                                BitmapMissingFonts=False)
        doc.Close(SaveChanges=0)
        return pages
    finally:
        word.Quit()
        pythoncom.CoUninitialize()


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        print(arg, finalize(arg), "pages")
