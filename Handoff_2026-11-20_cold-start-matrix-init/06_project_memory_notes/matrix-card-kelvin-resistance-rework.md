---
name: matrix-card-kelvin-resistance-rework
description: Matrix_Card-6 / Control_Card-4 replaced 2-wire resistance with 4-wire Kelvin + 24-bit ADS124S08; three blocking routing gaps
metadata: 
  node_type: memory
  type: project
  originSessionId: df9644f0-95fc-4902-8a77-e875f17fd16a
  modified: 2026-07-27T10:19:06.822Z
---

Schematic revision landed 2026-07-27 (`Doc/Matrix_Card-6.pdf`, `Doc/Control_Card-4.pdf`) **redesigned the precision resistance measurement**. This invalidates the 2-wire assumptions in [[firmware-single-mcu-architecture]] and [[schematics-are-source-of-truth]].

What changed:
- **Second 32-mux "sense" array** on Matrix sheet 8 (`Muxer_Sense`, U34–U65 CD4067BF3A) taps the same HI1..256 / LO1..256 harness pins as the force array, producing `HI_SENSE` / `LO_SENSE`. Genuine 4-wire Kelvin.
- **ADS124S08 (U68)**, 24-bit Δ-Σ, PGA 1–128, on Matrix sheet 9. `AIN0 = HI_SENSE`, `AIN1 = LO_SENSE`, `AINCOM = GND` via jumper JP1. `REFP0`/`REFN0` are **no-connect** → internal 2.5 V reference. AVDD/IOVDD = +3V3 (unipolar). AIN2–AIN5, REF1 pair and GPIO0–3 all free.
- **Matrix U33 (AD7476) is now continuity-only** — it is no longer the resistance ADC.
- **R131 (LO_COM pull-down) changed 100 kΩ → 100 Ω @ 0.01 %, 1206.** Doubles as the ADC common-mode floor.
- **3× more MCP23017 on the Matrix bus** (U66/U67/U69, annotated **0x23/0x24/0x25**) for the sense enables — five total on that bus.
- **Mux address lines moved off the MCU**: new Control-Card MCP23017 **U21 on I2C3** drives `HI_S1–S4`, `LO_S1–S4`, `I2C_EN1`, `I2C_EN2`. (Control names them S1–S4; Matrix names the same wires S0–S3.) This closes the old "which GPIOs drive HI_S0..3" question — the answer is: none, it's an I2C expander now, so every channel step costs an I2C transaction.
- **Mux enable polarity RESOLVED**: every CD4067 `E` pin (force sheet 2 *and* sense sheet 8) has a **100 kΩ pull-up to +3V3**. E is active LOW ⇒ OLAT bit **1 = disabled, 0 = enabled**; init all mux expanders to **0xFF**, and they are safe while the MCP23017 is still in its power-on high-Z state.
- Force and sense arrays **share** `HI_S0–S3` / `LO_S0–S3`, so selecting a pin on one selects it on the other — firmware only mirrors the bank enable `HI_SENSE_EN[k]` alongside `HI_EN[k]`.

**Why:** removes the ~1 kΩ of uncancelled CD4067 Rₒₙ that made the old 2-wire reading useless for wire resistance.

**How to apply:** three gaps block firmware; do not plan around them being fixed:
1. `ADC_CS_1`, `ADC_RST_1`, `Start_SYNC_1`, `DRDY_1`, `SPI1_SCLK` exist **only** on Matrix sheet 9 — not on connector J101, not anywhere on the Control Card. The ADS124S08 is unreachable. Also U68 clocks on `SPI1_SCLK` while U33 clocks on `SPI1_SCK`.
2. Sense enables are **undriven**: sheet 8 names them `HI_SENSE_EN1..16`/`LO_SENSE_EN1..16` but U66/U67/U69 emit `HI_EN1..16`/`LO_EN1..16`, colliding with U101/U102. Looks like un-renamed copy-paste.
3. Control J2–J5 (labelled HV_Card_1..4) and Matrix J101 are **not pin-compatible**, and Control carries no `HI_COM`/`LO_COM` at all.

Excitation: still 2× CD4067 on a 3.3 V rail + 100 Ω, so compliance caps current at roughly **1.5–3 mA — 10 mA is not achievable**; assume **1 mA**. Kelvin removes Rₒₙ from accuracy but not from compliance. The 0.01 % R131 can't yet serve as a current reference because `LO_SENSE` taps above the LO force mux; recommended fix is routing the `LO_COM` node to a spare `AIN2`.
