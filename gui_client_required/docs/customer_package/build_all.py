# -*- coding: utf-8 -*-
"""Build the customer-package documents: .docx -> Word field update -> .pdf."""
import importlib
import os
import sys

from common import OUT_DIR
from finalize_word import finalize

DOCS = [
    ("doc1_overview", "1_System_Overview"),
    ("doc2_user_manual", "2_User_Manual"),
    ("doc3_gui", "3_GUI_Functional_Description"),
    ("doc4_flashing", "4_Flashing_Procedure"),
    ("doc5_ftp", "5_Functional_Test_Procedure"),
    ("doc6_code", "6_Code_Walkthrough"),
]

if __name__ == "__main__":
    wanted = set(sys.argv[1:])
    os.makedirs(OUT_DIR, exist_ok=True)
    for mod, name in DOCS:
        if wanted and name.split("_")[0] not in wanted and mod not in wanted:
            continue
        try:
            m = importlib.import_module(mod)
        except ModuleNotFoundError as exc:
            print("skip", mod, exc)
            continue
        path = os.path.join(OUT_DIR, name + ".docx")
        m.build(path)
        pages = finalize(path)
        print(f"{name}: {pages} pages")
