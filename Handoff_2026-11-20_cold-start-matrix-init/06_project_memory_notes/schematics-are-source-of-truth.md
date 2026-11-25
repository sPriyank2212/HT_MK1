---
name: schematics-are-source-of-truth
description: "For the Harness Tester, the finalised KiCad schematics override the SAD document wherever they disagree"
metadata: 
  node_type: memory
  type: project
  originSessionId: c5000e64-a077-42b7-a176-374f7cd85c12
  modified: 2026-07-27T10:18:42.144Z
---

For the Automated Harness Test System (HT_MK1), the **`Doc/` folder is now the single source of truth** (user, 2026-07-14): the three KiCad schematics there (`Control_Card (1).pdf`, `Matrix_Card-2.pdf`, `HV_Card (1).pdf`) plus `Harness_Tester_Operation_Document` (docx, v1.1) and `Operation.txt`. The old schematics were removed. Where the Operation Document (prose) disagrees with the schematics, the **schematics win**.

Operation-Document errors found (schematic-confirmed): DAC8830 is SPI not I2C; OPTO_CNTR is PC12 not PA15 (PA15 = buzzer); insulation §3.2.5 conflates the HV rail monitor (~0.25 V @500 V, node HV_Sense) with the leakage node (~0.045 V @short, across R3004 1k) — the 0.045 V table belongs to HV_RET, not the rail. See [[firmware-single-mcu-architecture]] for the corrected bus/ADC/HV-enable map.

**Why:** User finalised the schematics and explicitly chose to go by the Doc folder over any prose doc.

**Current schematic set (2026-07-27):** `Control_Card-4.pdf` (11 sheets, dated 2026-07-12), `Matrix_Card-6.pdf` (9 sheets, 2026-07-11), `HV_Card-1.pdf` (6 sheets, unchanged). The older `Control_Card-1` / `Matrix_Card-3` were deleted in the same working-tree change. Prose doc is now `Harness_Tester_Operation_Document_v1.4.docx`.

**How to apply:** When reasoning about the design, follow what the schematics show. Known points where the SAD is wrong/outdated:
- ~~Matrix Card = 2-wire HI/LO matrix~~ **SUPERSEDED 2026-07-27 — the Matrix Card IS now 4-wire Kelvin.** See [[matrix-card-kelvin-resistance-rework]].
- ~~ADC is AD7476 (12-bit SAR) everywhere, not 24-bit Δ-Σ~~ **SUPERSEDED** — Matrix_Card-6 adds an **ADS124S08 (24-bit Δ-Σ, U68)**. AD7476 remains correct for the Control and HV cards and for Matrix U33.
- HV relays = **single MHV05-1A per position** (64 inject + 64 return), 2N7002 MOSFET drivers — not series-pair-with-balance-resistor, not NPN.
- Galvanic isolation is **centralised on the Control Card** (ADuM1250 for I2C, ADuM3200/3201 for SPI, + 2 isolated DC-DC bricks make `+5V_ISO`/`_ISO`), not per-HV-board. Matrix-card I2C isolator is ADuM1205ARZ (U103).
- All inter-card ribbons are **50-pin** (6120XX22021 / 61205022021).

Open/incomplete items in the schematics (still true in rev 4/6): no analog HI_COM/LO_COM connection drawn between Control and Matrix cards — those nets exist only on the Matrix side; `IN` net routing between Opto_SPDT and HV connectors looks unfinished.
