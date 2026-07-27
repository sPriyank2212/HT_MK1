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

## Status snapshot — 2026-07-27

| Category | Count |
|---|---|
| Blocking — firmware cannot proceed | 2 |
| Awaiting hardware decision | 3 |
| Agreed, awaiting schematic edit | 3 |
| Firmware work queued | 5 |
| Verify at bring-up | 6 |
| Closed to date | 4 |

**Next actions:** close HW-01 and HW-02 (both are schematic edits that unblock everything on the
resistance path), then answer HW-03/HW-04 so the connector pinout can be frozen.

---

## Open items

### Blocking — the new precision resistance chain cannot be exercised until these close

| ID | Item | Raised |
|---|---|---|
| HW-01 | **ADS124S08 control lines unrouted.** `ADC_CS_1`, `DRDY_1`, `ADC_RST_1`, `Start_SYNC_1` exist only on Matrix sheet 9 — not on J101, not anywhere on Control_Card-4. `SPI1_MOSI`/`SPI1_MISO` do reach J101, so only the clock and these four dead-end. Needs 4 connector pins (14 are spare) and 4 MCU pins (PA0, PA1, PA4, PA11, PA12, PC1, PC7, PC15 are all no-connect). | 2026-07-27 |
| HW-02 | **Sense-mux enables undriven.** Sheet 8 names them `HI_SENSE_EN1..16` / `LO_SENSE_EN1..16`; expanders U66/U67/U69 on sheet 9 emit `HI_EN1..16` / `LO_EN1..16`, which U101/U102 already drive. As drawn the sense array can never be switched on and the force enables have three extra drivers. Rename, carry the 100 kΩ pull-ups onto the renamed nets, re-run ERC. | 2026-07-27 |

### Awaiting hardware decision

| ID | Item | Raised |
|---|---|---|
| HW-03 | **Matrix-slot power/ground domain.** J101 expects non-isolated +5 V / +3V3 / GND; the Control connectors offer `+5V_ISO`/`ISO_GND` and `+5V_ISO_1`/`ISO_GND_1`, with +3V3 on slot 1 only. `SPI1`, `HI_S1–S4`, `LO_S1–S4` and `I2C_EN` all cross non-isolated, so Matrix ground must be the same node as Control ground — otherwise neither those signals nor the excitation loop has a return. Related: I2C is isolated twice (Control ADuM1250 → Matrix ADuM1205 U103); one barrier is redundant. | 2026-07-27 |
| HW-04 | **Current reference.** Route the `LO_COM` node to a spare ADS124S08 input (AIN2–AIN5 are free) so firmware can compute I = V / 100 Ω and evaluate resistance ratiometrically against the 0.01 % R131. Without it, accuracy rides entirely on DAC8775 tolerance and drift. Wiring REFP0/REFN0 across R131 instead does not work — 1 mA × 100 Ω = 100 mV is below the ADC's minimum external reference. | 2026-07-27 |
| HW-05 | **`I2C_EN1` / `I2C_EN2` purpose.** Driven by U21, routed to all four card connectors, but no net of that name exists on Matrix_Card-6 or HV_Card-1. Function and safe default state both unknown — firmware must not write them until this is answered. | 2026-07-27 |

### Agreed — awaiting schematic edit

| ID | Item | Agreed |
|---|---|---|
| HW-06 | Merge `SPI1_SCLK` into `SPI1_SCK`. U68 and U33 share one clock; this is a rename, not an extra pin. | 2026-07-27 |
| HW-07 | Keep 100 kΩ pull-ups on `HI_EN` / `LO_EN`, and carry them onto the renamed sense enables (see HW-02). Pull-downs would leave all 64 multiplexers enabled whenever the expanders are unpowered or uninitialised. | 2026-07-27 |
| HW-08 | HV card R3003 50 kΩ → 5 kΩ, so HV_Sense reads 0.245 V at 500 V. Firmware already assumes the 5 kΩ value. Carried from v1.3. | 2026-07-20 |

### Firmware work queued

| ID | Item | Raised |
|---|---|---|
| FW-01 | New `drivers/ads124s08` — reset, device-ID read, PGA / data-rate config, internal 2.5 V reference, offset self-calibration, DRDY handling. No driver exists today. | 2026-07-27 |
| FW-02 | Rewrite `test/kelvin.c` for 4-wire. It currently reads the AD7476 and hard-codes `KELVIN_FORCE_CURRENT_A = 0.010f`; both are wrong under the new scheme. Add PGA auto-ranging and system-offset subtraction. | 2026-07-27 |
| FW-03 | `cards/matrix_card.c` — pin `MATRIX_EN_ALL_OFF` to `0xFFFF` (the `0x0000` branch is the unsafe polarity) and add sense-array bank control paired with the force array. | 2026-07-27 |
| FW-04 | Mux address lines now come from MCP23017 U21 on I2C3, not MCU GPIO. Update `bsp/board.c`, add OLAT shadow registers, and consider 400 kHz — a 256 × 256 scan is roughly 70 s of pure bus time at 100 kHz versus 18 s at 400 kHz. | 2026-07-27 |
| DOC-01 | `fw_status.txt` still describes the 2-wire path, 10 mA excitation, and Matrix U33 as the resistance ADC. Sync it with v1.4. | 2026-07-27 |

### Verify at bring-up

| ID | Item | Raised |
|---|---|---|
| BU-01 | Excitation current — run the 0 Ω loopback compliance sweep. 10 mA is unachievable through two CD4067B plus 100 Ω on a 3.3 V rail; expect roughly 1–3 mA. Capture the system offset at the same time. | 2026-07-27 |
| BU-02 | SPI1 is now shared by U33 and U68 — confirm one CPOL/CPHA suits both, and that `SPI1_CS` and `ADC_CS_1` are never asserted together (the AD7476 drives SDATA whenever its CS is low). | 2026-07-27 |
| BU-03 | U101 / U102 I2C addresses are set by strapping and not annotated, unlike the sense trio at 0x23 / 0x24 / 0x25. Scan and log. | 2026-07-27 |
| BU-04 | JP1 (AINCOM → GND, Matrix sheet 9) must be fitted, or the ADC's analog common floats and every reading is meaningless. | 2026-07-27 |
| BU-05 | No differential RC filter on `HI_SENSE` / `LO_SENSE` into AIN0/AIN1 — R83–R89 are digital damping on the SPI lines. Characterise noise before committing to the high PGA gains. | 2026-07-27 |
| BU-06 | Harness build must encode `ISO_HV_CARD_ENx` per card slot (card 1 → EN1 … card 4 → EN4). HV_Card-1 sheet 1 states this is done in the cable, not the schematic. | 2026-07-27 |

---

## Closed items

| ID | Closed | Item | Resolution |
|---|---|---|---|
| CL-01 | 2026-07-27 | Multiplexer enable polarity — contradictory in v1.3 | Every CD4067 E pin carries a 100 kΩ pull-up to +3V3, on the force sheet and the sense sheet alike. E is active LOW, so expander bit 1 = disabled, 0 = enabled. Initialise all mux OLAT registers to `0xFF`. Safe from power-on while the MCP23017s are still high-Z. Confirmed with the hardware owner. |
| CL-02 | 2026-07-27 | `HI_COM` reported missing from the Control Card | Not missing. It is net `IN` — the Opto SPDT common, switched between `ADC_IN` (10 kΩ pull-up via R26) and `I_OUT` (excitation) — present on card-connector pin 29. A naming difference, not a routing gap. |
| CL-03 | 2026-07-27 | `LO_COM` reported missing from the Control Card | Needs no connector pin at all; it returns through R131 to Matrix Card ground locally. What matters instead is a continuous ground return — folded into HW-03. |
| CL-04 | 2026-07-20 | LO_COM pull-down value | Fixed at 100 Ω, now fitted as R131, 0.01 %, 1206. |

---

## Activity log

### 2026-07-27
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
- Pin-budget analysis for the connector gaps: 14 spare pins on the 50-pin card connector and
  8 free MCU pins, against 4 signals actually needed — fits without removing anything.
- Raised HW-01 … HW-05, FW-01 … FW-04, BU-01 … BU-06. Closed CL-01, CL-02, CL-03 with the
  hardware owner.
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
