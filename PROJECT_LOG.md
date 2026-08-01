# HT_MK1 — Project Log

One place to see where the project stands: what is open, what is closed, and what happened on
each working day.

- **Status snapshot** and **Open items** are live — edit them in place as things move.
- **Closed items** and **Activity log** are append-only. Newest day first.
- This file tracks *tasks and decisions*. Design detail lives elsewhere:
  - `fw_status.txt` — firmware state, bus map, driver stack
  - `Doc/Harness_Tester_Operation_Document_v1.4.docx` — system operation, test procedures
  - `Doc/*.pdf` — the schematics, which win over any prose

ID prefixes: `HW-` schematic/hardware · `FW-` firmware · `BU-` bring-up/verify · `DOC-` documentation.

---

## Status snapshot — 2026-08-01

| Category | Count |
|---|---|
| Blocking — firmware cannot proceed | **0** |
| Agreed, awaiting schematic edit | 5 |
| Awaiting a decision | 2 |
| Firmware work queued | 5 |
| Verify at bring-up | 7 |
| Closed to date | 7 |

**The 4-wire method is now proven on real hardware**, not just on paper: the ADS1232 bench rig
measured a 0.033 Ω resistor to **0.4 %** with no current calibration at all, because the
ratiometric arrangement cancels the excitation. Write-up in
`Doc/4wire_resistance_validation.md`.

**Next actions:** answer HW-04 — the bench result is now the concrete argument for it — and
HW-09 (four card slots, five cards). Then the next schematic revision can pick up HW-02, HW-03,
HW-06, HW-08 and HW-10 in one pass.

**Forward risk list** is in `Doc/4wire_resistance_validation.md` §7. Headline: the excitation
has a **usable window of roughly 1–8 mA**, target **5 mA** — below that the sense common mode
falls under the PGA floor (BU-07), above it the force loop runs out of compliance on 3.3 V.
Highest-value next measurement is **CD74HC4051 Rₒₙ at 3.3 V**, because it sets that whole
window and nothing downstream can be finalised without it.

---

## Open items

### Agreed — awaiting schematic edit

| ID | Item | Agreed |
|---|---|---|
| HW-02 | Rename the sense-mux enables. **U66** (0x23, currently `HI_EN1..16`) → `HI_SENSE_EN1..16`; **U67** (0x24, currently `LO_EN1..16`) → `LO_SENSE_EN1..16`. **Do not touch U69** (0x25) — that is the ADC control expander and its net names are already correct. The 100 kΩ pull-ups are already fitted and follow the renamed nets automatically. Re-run ERC afterwards. | 2026-07-29 |
| HW-03 | Matrix card moves to the non-isolated domain: `+5V_ISO` → plain `+5V`, no isolators in the Matrix path. Follow-ons: the Matrix card's ADuM1205 (U103) becomes redundant once both sides share ground — DNF with links or keep as a buffer; and feed the slot raw `I2C3_SDA`/`I2C3_SCL` rather than `ISO_SDA3`/`ISO_SCL3`. | 2026-07-29 |
| HW-06 | Merge `SPI1_SCLK` into `SPI1_SCK`. This is now the **only** genuinely unconnected net on the board — `SPI1_SCLK` has exactly one node, U68 pin 11 via R86. | 2026-07-27 |
| HW-08 | HV card R3003 50 kΩ → 5 kΩ, giving 0.245 V at 500 V from the 10 M : 5 k divider. **The PDF in the repo still shows 50 kOhms** (HV_Card-1.pdf sheet 2), so either the change is not exported or HV_Card-1 is stale — re-issue and re-check. | 2026-07-20 |
| HW-10 | Add pull resistors on the three ADC control lines that U69 drives, so they are defined while the MCP23017 is still in its power-on high-Z input state: `ADC_CS_1` and `ADC_RST_1` pulled **up** to +3V3 (CS deasserted, ADC out of reset), `Start_SYNC_1` pulled **down** to GND. Sheet 9 currently carries only 4.7 K (I2C and address strapping) and 47 Ω (series damping) — nothing on these nets. Same argument as the mux enables. | 2026-07-29 |

### Awaiting a decision

| ID | Item | Raised |
|---|---|---|
| HW-04 | **Current reference — on-card net, not a connector wire.** Route the `LO_COM` node (top of R131) to **U68 AIN2**, both on Matrix sheet 9, with 1 kΩ series + 100 nF to AINCOM. Purpose is measuring the excitation current, not sensing harness voltage: R = V_kelvin / I, and without measuring I across R131 the current comes from the DAC8775's programmed value, so resistance accuracy equals DAC tolerance plus tempco and R131's 0.01 % does nothing. AIN2–AIN5 are free. If declined, firmware calibrates the current against a reference resistor instead and the accuracy claim drops accordingly. | 2026-07-27 |
| HW-09 | **Four card slots, five cards.** The Control card has four 50-pin connectors (J2–J5). A 256-line harness needs four HV cards (64 HS lines each) *plus* the Matrix card. Not a problem while only one or two HV cards are fitted, but the full configuration cannot be assembled as drawn. Decide before the connector pinout is frozen. | 2026-07-27 |

### Firmware work queued

| ID | Item | Raised |
|---|---|---|
| FW-01 | New `drivers/ads124s08` — reset, device-ID read, PGA / data-rate config, internal 2.5 V reference, offset self-calibration. **CS, RESET and START/SYNC are driven over I2C via U69 (0x25), not by MCU GPIO**, so each conversion sequences I2C(CS low) → SPI → I2C(CS high). `DRDY_1` is likewise an expander *input*: no interrupt is possible and polling costs a bus round-trip, so use a timed wait derived from the configured data rate and read DRDY only as a sanity check. | 2026-07-27 |
| FW-02 | Rewrite `test/kelvin.c` for 4-wire. It currently reads the AD7476 and hard-codes `KELVIN_FORCE_CURRENT_A = 0.010f`; both are wrong under the new scheme. Add PGA auto-ranging and system-offset subtraction. | 2026-07-27 |
| FW-03 | `cards/matrix_card.c` — pin `MATRIX_EN_ALL_OFF` to `0xFFFF` (the `0x0000` branch is the unsafe polarity) and add sense-array bank control paired with the force array. | 2026-07-27 |
| FW-04 | Mux address lines come from MCP23017 U21 on I2C3, not MCU GPIO. Update `bsp/board.c`, add OLAT shadow registers, and consider 400 kHz — a 256 × 256 scan is roughly 70 s of pure bus time at 100 kHz versus 18 s at 400 kHz. | 2026-07-27 |
| DOC-01 | `fw_status.txt` still describes the 2-wire path, 10 mA excitation, and Matrix U33 as the resistance ADC. Sync it with v1.4. | 2026-07-27 |

### Verify at bring-up

| ID | Item | Raised |
|---|---|---|
| BU-01 | Excitation current — run the 0 Ω loopback compliance sweep. 10 mA is unachievable through two CD4067B plus 100 Ω on a 3.3 V rail; expect roughly 1–3 mA. Capture the system offset at the same time. | 2026-07-27 |
| BU-02 | SPI1 is shared by U33 and U68 — confirm one CPOL/CPHA suits both, and that `SPI1_CS` and `ADC_CS_1` are never asserted together (the AD7476 drives SDATA whenever its CS is low). | 2026-07-27 |
| BU-03 | U101 / U102 I2C addresses are set by strapping and not annotated, unlike the sheet-9 trio at 0x23 / 0x24 / 0x25. Scan and log. | 2026-07-27 |
| BU-04 | JP1 (AINCOM → GND, Matrix sheet 9) must be fitted, or the ADC's analog common floats. Populate with a 0 Ω link by default and mark it on the assembly drawing. | 2026-07-27 |
| BU-05 | ~~No differential RC filter~~ **DONE in Matrix rev 2** — R234/R235 4.99 k 0.1 % + C33 47 nF + C142/C143 4.7 nF fitted. | 2026-07-27 |
| BU-07 | **Common-mode headroom is now marginal.** `LO_SENSE ≈ I × (R_LOmux + R131)`. With CD74HC4051 (~100 Ω) instead of CD4067B (~900 Ω) that is only ~0.20 V at 1 mA, against an ADS124S08 floor of 0.15 + 15.5·\|V_IN\| ≈ 0.166 V at gain 32 — and it is **violated below ~0.85 mA**. Improving the muxes made this worse, because R131 was sized when the mux drop did the lifting. Confirm HC4051 Rₒₙ at 3.3 V, then hold I ≥ 1 mA or raise R131. See Doc/4wire_resistance_validation.md §5.1. | 2026-08-01 |
| BU-09 | **Characterise CD74HC4051 Rₒₙ at 3.3 V across several channels**, not one. Per-channel spread narrows the 1–8 mA window from the compliance side: at 200 Ω per mux the loop is 500 Ω and HI_COM hits 2.5 V at 5 mA. A channel fine at pin 1 may be in compliance limiting at pin 200 — and that presents as "some wires read wrong", not as an obvious fault. See Doc/4wire_resistance_validation.md §7.2. | 2026-08-01 |
| BU-10 | **Thermal EMF is the accuracy floor below ~1 mΩ.** At 5 mA, 1 µV of junction EMF = 200 µΩ. A 256-line harness has hundreds of dissimilar-metal junctions. Mitigation to design in now: **current reversal** — the DAC8775 has a ±24 mA range, and R = (V_fwd − V_rev)/(2I) cancels EMF because it does not reverse with the current. The ADS124S08 `G_CHOP` bit cancels the ADC's own offset only; the two are complementary. See §7.3. | 2026-08-01 |
| BU-11 | **Measure sense-path leakage.** `HI_SENSE` is the common node of 32 CD74HC4051s with 31 disabled; summed off-channel leakage into the 4.99 kΩ series resistor could be a large offset (1 µA → 5 mV). Should largely cancel between HI and LO legs, but unverified. Cheap test: enable a sense bank with no excitation and check the differential reads near zero. Rises sharply with temperature. See §7.4. | 2026-08-01 |
| BU-08 | **Do not copy the bench resistance formula.** ADS1232 full scale is ±0.5·VREF/Gain, ADS124S08 is ±VREF/Gain. The bench divides by `2 × gain × 2²³`; the product must divide by `gain × 2²³`. Copy-pasting gives a silent 2× error. | 2026-08-01 |
| BU-06 | Harness build must encode `ISO_HV_CARD_ENx` per card slot (card 1 → EN1 … card 4 → EN4). HV_Card-1 sheet 1 states this is done in the cable, not the schematic. | 2026-07-27 |

---

## Closed items

| ID | Closed | Item | Resolution |
|---|---|---|---|
| CL-07 | 2026-07-29 | Mux enable pull direction — full verification requested | All 64 verified: sheet 2 R1–R32 and sheet 8 R33–R64, every one 100 kΩ to **+3V3**, none to GND. The +3V3 label sits at an identical (−31, +11) offset from the refdes on all 64 instances, and R1 and R33 were wire-traced explicitly to the +3V3 label. No resistor has a GND nearer than its +3V3. Sense muxes are U34–**U65** (32 of them). |
| CL-06 | 2026-07-29 | `I2C_EN1` / `I2C_EN2` purpose | Leftover access GPIO from an earlier concept, deliberately kept on the connector as spare lines. No function. Firmware must not drive them; treat as reserved. |
| CL-05 | 2026-07-29 | ADS124S08 control lines believed unrouted | **Not a gap — this finding was wrong.** U69 (MCP23017 at 0x25) drives all four from sheet 9: GPB0 → `ADC_RST_1`, GPB1 → `DRDY_1`, GPB2 → `ADC_CS_1`, GPB3 → `Start_SYNC_1`. They never needed to leave the card. No connector pins and no MCU pins are required; the pin-budget proposal is withdrawn. The error was checking whether the nets reached J101 and concluding they dead-ended, without checking whether they were driven locally on the same sheet. Firmware consequences are tracked in FW-01. |
| CL-04 | 2026-07-20 | LO_COM pull-down value | Fixed at 100 Ω, now fitted as R131, 0.01 %, 1206. |
| CL-03 | 2026-07-27 | `LO_COM` reported missing from the Control Card | Needs no connector pin at all; it returns through R131 to Matrix Card ground locally. What matters instead is a continuous ground return — folded into HW-03. |
| CL-02 | 2026-07-27 | `HI_COM` reported missing from the Control Card | Not missing. It is net `IN` — the Opto SPDT common, switched between `ADC_IN` (10 kΩ pull-up via R26) and `I_OUT` (excitation) — present on card-connector pin 29. A naming difference, not a routing gap. |
| CL-01 | 2026-07-27 | Multiplexer enable polarity — contradictory in v1.3 | Every CD4067 E pin carries a 100 kΩ pull-up to +3V3, force and sense alike. E is active LOW, so expander bit 1 = disabled, 0 = enabled. Initialise all mux OLAT registers to `0xFF`. Safe from power-on while the MCP23017s are still high-Z. |

---

## Activity log

### 2026-08-01
- Built and validated a 4-wire Kelvin bench rig on a NUCLEO-G474RE with an **ADS1232** as a
  stand-in for the ADS124S08. **Measured a 0.033 Ω resistor to 0.4 %** (predicted code
  7,539, measured 7,553–7,705). Full write-up in `Doc/4wire_resistance_validation.md`.
- Proved the ratiometric method end to end: because REFP sits on the same rail that drives
  the divider, the excitation cancels and no current calibration was needed at all. This is
  the concrete argument for HW-04 on the product board.
- Measured noise floor **±0.6 mΩ at 0.53 mA** on flying leads with a marginal joint; scales
  to ±0.06 mΩ with a 470 Ω divider pair.
- Root causes found along the way, all now documented as recognisable signatures: floating
  DOUT (`code = -1`), SCLK not reaching the ADC (`code = 0`), ~50 % silent link corruption,
  **inputs at ground outside the PGA common-mode window** (the expensive one), a misread
  full-scale convention, and a tare that captured the signal itself.
- Raised BU-07 (common-mode headroom shrank when the muxes improved) and BU-08 (the two ADCs
  use different full-scale conventions — do not copy the formula).
- Added `drivers/ads1232` — bench-only, gated on `HT_ENABLE_ADS1232`, 0 bytes when off,
  `#error` if left enabled in a Release build.

### 2026-07-29
- Hardware owner answered the eight open HW items; each checkable claim was verified against the
  schematics.
- **HW-01 withdrawn.** U69 (0x25) drives `ADC_RST_1`, `DRDY_1`, `ADC_CS_1` and `Start_SYNC_1` from
  GPB0–GPB3 on sheet 9. The "unrouted ADC control lines" finding was wrong, and with it the
  connector pin-budget and MCU pin proposal. Closed as CL-05.
- **HW-07 verified** across all 64 multiplexer enables — pull-ups to +3V3, none to GND. Closed as
  CL-07.
- **HW-05 closed** — the `I2C_EN` lines are deliberate spares from an earlier concept.
- HW-02 refined: the expanders to rename are U66 and U67; U69 must be left alone. Sheet-9 refdes
  confirmed as U66 @ 0x23 (HI), U67 @ 0x24 (LO), U69 @ 0x25 (ADC control).
- HW-03 agreed — Matrix card moves to the non-isolated domain.
- HW-08 flagged: the intent (0.245 V, so 10 M : 5 k) is right, but HV_Card-1.pdf in the repo still
  shows R3003 = 50 kOhms. Needs re-export.
- HW-10 raised: no pull resistors on the three U69-driven ADC control lines, which float until
  firmware configures the expander.
- HW-04 clarified — it is an on-card net to U68 AIN2 for measuring excitation current, not a wire
  to the Control card. Still open.
- Net effect: **zero blocking items.**

### 2026-07-28 — `f863c06`
- GUI front-end proposal added (`Doc/HT_MK1_GUI_Proposal.html`).

### 2026-07-27 — `cdb0520`
- Reviewed the revised schematics `Control_Card-4.pdf` (2026-07-12) and `Matrix_Card-6.pdf`
  (2026-07-11) against operation document v1.3. HV_Card-1 unchanged.
- Identified the headline change: **resistance measurement redesigned from 2-wire to 4-wire
  Kelvin.** New 32-multiplexer sense array (sheet 8, U34–U65) tapping all 512 harness pins;
  ADS124S08 24-bit Σ-Δ ADC (U68, sheet 9) reading `HI_SENSE` − `LO_SENSE` differentially;
  R131 changed 100 kΩ → 100 Ω 0.01 %; three more MCP23017 (0x23/0x24/0x25); mux address
  lines moved off MCU GPIO onto Control-card MCP23017 U21.
- Wrote `Doc/Harness_Tester_Operation_Document_v1.4.docx` — new §1.4 (Kelvin architecture),
  §7 rewritten (compliance characterisation, ratiometric options, PGA gain/range table),
  §5.3 sense-array init, faults F11–F14, open-items block at the front. §3 and §4 (HV)
  carried over unchanged.
- Raised HW-01 … HW-09, FW-01 … FW-04, BU-01 … BU-06. Closed CL-01, CL-02, CL-03.
- Created this log file.

### 2026-07-21 — `cff9623`
- Schematics re-issued: `Control_Card-4.pdf` and `Matrix_Card-6.pdf` replace `Control_Card-1.pdf`
  and `Matrix_Card-3.pdf`. `ht_architecture.html` removed.

### 2026-07-20 — `6a5c829`, `f4d028f`
- LO_COM pull-down fixed at 100 Ω; resistance self-calibration plan added to `fw_status.txt`.
- HV_Sense finalised at 0.245 V for 500 V, with R3003 50 kΩ → 5 kΩ deferred to the next
  schematic revision.

### 2026-07-17 — `c9a5d04`, `62488a3`
- Operation document renamed to v1.3; `fw_status.txt` synced with the v1.3 review; hardware
  owner's clarifications folded in.

### 2026-07-16 — `fe38b94`
- v1.3 firmware-engineering review of the Harness Tester operation document.

### 2026-07-14 — `9b45613`
- Firmware reconciled with the `Doc/` schematics: bus and ADC maps corrected, insulation
  measurement reworked to the leakage node, HV control model fixed (no enable/discharge GPIO).
- Established that the schematics are the source of truth over the prose documents.

### 2026-06-17 — `4318fb2`
- Device / card / test driver stack added, plus logging and RTOS tasks, and Nucleo bring-up.

### 2026-06-16 — `56553f0`, `18d6ed9`
- Project start. Peripherals configured in CubeMX; `fw_status.txt` created.
