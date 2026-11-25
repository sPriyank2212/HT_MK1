# -*- coding: utf-8 -*-
"""Shared constants and generated tables for the customer-package documents."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GUI = os.path.abspath(os.path.join(HERE, "..", ".."))
REPO = os.path.abspath(os.path.join(GUI, ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, GUI)

from ht_doc import HTDoc, PACKAGE_DOCS      # noqa: E402,F401

VERSION = "1.0.0"
DATE = "28-10-2026"
COMPANY = "Infinity Integrations Private Limited"
YEAR = "2026"
PRODUCT = "HT_MK0 Harness Tester"
FW_VERSION = "2.2.0"
GUI_VERSION = "2.0.0"
EXE_NAME = "HarnessTester_26102026.exe"

OUT_DIR = os.path.join(REPO, "Customer_Package", "0_Documents")


def new_doc(doc_no: str, title: str) -> HTDoc:
    d = HTDoc(doc_no, title, VERSION, DATE, COMPANY, YEAR, PRODUCT)
    d.cover(PRODUCT)
    d.front_matter()
    d.contents()
    return d


def shot(name):
    return os.path.join(HERE, "assets", "shots", name)


def dia(name):
    return os.path.join(HERE, "assets", "diagrams", name)


# ── Tables generated from the real files, so they cannot drift ─────────────────────
def _firmware_pins():
    s = open(os.path.join(REPO, "firmware", "Core", "Src", "harness.c"), encoding="utf-8").read()

    def parse(name):
        m = re.search(r"static const GPIOPin_t " + name + r"\[HARNESS_PINS\] = \{(.*?)\n\};", s, re.S)
        body = re.sub(r"/\*.*?\*/", "", m.group(1), flags=re.S)
        return [f"P{a}{b}" for a, b in re.findall(r"\{GPIO([A-G]),\s*GPIO_PIN_(\d+)\s*\}", body)]

    return parse("SIDE_A"), parse("SIDE_B")


def pin_rows():
    """[channel, connector, pin, Side A MCU pin, Side B MCU pin] from the
    default connector config, checked against the firmware tables."""
    from core.pinmap import load_pinmap
    pm = load_pinmap(os.path.join(REPO, "netlists", "connector_config.xlsx"))
    a, b = _firmware_pins()
    rows = []
    for c in pm.channels:
        assert c.side_a == a[c.number - 1] and c.side_b == b[c.number - 1], \
            f"connector_config.xlsx and harness.c disagree on channel {c.number}"
        rows.append([str(c.number), c.connector_id, str(c.conn_pin), c.side_a, c.side_b])
    assert len(rows) == 37
    return rows


def shared_pin_rows():
    """Channels whose MCU pin also has another job on the board."""
    from core.pinmap import SHARED
    rows = []
    for ch, conn, pin, a, b in pin_rows():
        for side, mcu in (("A", a), ("B", b)):
            if mcu in SHARED:
                rows.append([f"{conn} pin {pin}", f"Side {side}", mcu, SHARED[mcu]])
    return rows
