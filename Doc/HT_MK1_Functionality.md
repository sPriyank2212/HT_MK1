# HT_MK1 — Automated Harness Test System
## Functional Specification (step-by-step)

**Version:** 1.0 · **Date:** 2026-07-14 · **MCU:** STM32G474RET6 (Cortex-M4F, FreeRTOS, HAL)

This document describes every functionality the product supports, as an explicit
sequence of steps (what is initialised, what value is written to which device,
which expander pin is driven, what is read back, and how the result is judged).

Source of truth: the `Doc/` schematics (`Control_Card (1).pdf`, `Matrix_Card-2.pdf`,
`HV_Card (1).pdf`) and `Harness_Tester_Operation_Document_v1.2_corrected.docx`.
Where the prose document disagreed with the schematics, the schematics win.

### 0. Source Reference Index

| Tag | Document | Sheet / Section |
|-----|----------|-----------------|
| `[CC-uC]` | Control_Card (1).pdf | 2/9 — uC (STM32G474 pinout) |
| `[CC-PWR]` | Control_Card (1).pdf | 3/9 — Power_Interface (+3V3 / +5V_ISO / +12V) |
| `[CC-DAC]` | Control_Card (1).pdf | 4/9 — DAC (DAC8775, I_OUT) |
| `[CC-SPDT]` | Control_Card (1).pdf | 5/9 — Opto_SPDT (TS5A3159, R54 10 k pull-up) |
| `[CC-ADC]` | Control_Card (1).pdf | 6/9 — ADC (U4 AD7476 on SPI3, VDD=+3V3) |
| `[CC-ISO]` | Control_Card (1).pdf | 7/9 — Isolator (ADUM1250 I2C, ADUM3200/3201) |
| `[CC-CON]` | Control_Card (1).pdf | 8/9 — Connector (J1–J4 HV, 50-pin) |
| `[MX-MUX]` | Matrix_Card-2.pdf | 2/7 — Muxer_Interface (32× CD4067) |
| `[MX-MCP]` | Matrix_Card-2.pdf | 3/7 — MCP23017 (U101/U102, U103 ADUM1205, Pull_Down) |
| `[MX-CON]` | Matrix_Card-2.pdf | 4/7 — Connector_interface (J101) |
| `[MX-ADC]` | Matrix_Card-2.pdf | 7/7 — ADC (U33 AD7476 on SPI1, VIN=HI_COM) |
| `[HV-TOP]` | HV_Card (1).pdf | 1/6 — DAC_Module / ADC_Module / HV_ADC_Sense / HV_Module |
| `[HV-DIV]` | HV_Card (1).pdf | 2/6 — Reed_Relay / HV_Sense_Divider (R3001–R3004) |
| `[HV-HS]` | HV_Card (1).pdf | 3/6 — High_Side (K1001–K1064, Q1001–Q1064) |
| `[HV-LS]` | HV_Card (1).pdf | 4/6 — Low_Side (K2001–K2064) |
| `[HV-EXP]` | HV_Card (1).pdf | 5/6 — GPIO_Expander (U501–U508) |
| `[HV-CON]` | HV_Card (1).pdf | 6/6 — Connector_Interface (J1001) |
| `[OD §x]` | Harness_Tester_Operation_Document_v1.2_corrected.docx | section x |

---

## 1. System Overview

Single-MCU instrument. The STM32G474 on the **Control Card** is the only processor.
The **Matrix Card** and **HV Cards** contain no MCU — they are GPIO expanders,
analogue muxes, reed relays, DACs and ADCs driven over I2C/SPI/GPIO.

| Card | Role | Key parts |
|------|------|-----------|
| Control | Master controller, stimulus + LV measurement | STM32G474, DAC8775, AD7476 (U4), TS5A3159 SPDT, isolators |
| Matrix | 256 HI × 256 LO cross-point routing | 32× CD4067, 2× MCP23017, AD7476 (U33) |
| HV (×1–4) | 500 V insulation channel, 64 HS + 64 LS | CA05P-5, DAC8830, 2× AD7476, 8× MCP23017, 128× MHV05-1A |

---

## 2. Hardware Resource Map

| Bus | Pins | Devices |
|-----|------|---------|
| **I2C2** | PC4 (SCL) / PA8 (SDA) | HV-card MCP23017 ×8 @ `0x20`–`0x27` (isolated, ADUM1250) |
| **I2C3** | PC8 (SCL) / PC9 (SDA) | Matrix MCP23017 ×2: **U101 = `0x20`** (HI_EN1..16), **U102 = `0x21`** (LO_EN1..16) (isolated, ADUM1205) |
| **SPI1** | PA5/6/7, CS **PB0** | Matrix **AD7476 U33** → reads `HI_COM` → **RESISTANCE** measurement (vref 3.3 V) |
| **SPI2** | PB13/14/15, CS **PB2** (isolated) | **DAC8775** (Kelvin I-source) + HV **DAC8830** + HV **AD7476 ×2** — shared bus, per-device CS |
| **SPI3** | PB3/4/5, CS **PB1** | Control **AD7476 U4** → reads `ADC_IN` → **CONTINUITY** measurement (vref 3.3 V) |

**Control GPIO**

| Signal | Pin | Meaning |
|--------|-----|---------|
| `OPT0_CNTR` | **PC12** | **LOW** = 3V3 pull-up path (continuity) · **HIGH** = I_OUT path (resistance) |
| `HV_Card_1.0 / 1.1` | PC13 / PC14 | HV board 1: **LEAK ADC CS** (U302) / **RAIL ADC CS** (U301) |
| `HV_Card_2.0 / 2.1` | PD2 / PC0 | HV board 2 ADC chip-selects |
| `HV_Card_3.0 / 3.1` | PC5 / PC6 | HV board 3 ADC chip-selects |
| `HV_Card_4.0 / 4.1` | PA10 / PA9 | HV board 4 ADC chip-selects |
| `BUZZ_I/P` | PA15 | Buzzer (2N7002 driver) — *not* OPT0_CNTR |

**HV sense network** (`R3001` 10 M, `R3002` 1 M, `R3003` 50 k, `R3004` 1 k), HV ADC vref = **5.0 V** (+5V_ISO):

| Node | ADC | Meaning |
|------|-----|---------|
| `HV_Sense` | U301 (RAIL) | Rail monitor: **V = 0.00049 × V_HV** → **≈ 0.245 V @ 500 V** |
| `HV_RET` | U302 (LEAK) | Leakage across `R3004` (1 kΩ): **0.045 V = 10 MΩ** go/no-go |

> **There is no HV enable pin and no discharge relay.** CA05P-5 `VIN` is tied to
> +5V_ISO; its output follows `VPGM`, driven by DAC8830 through an OPA376 buffer.
> **Programming the DAC IS the HV control. HV OFF = write DAC code 0.**
> Discharge is passive through the ≈10.05 MΩ divider.

---

## 3. Firmware Constants

| Constant | Value | Where |
|----------|-------|-------|
| `BOARD_VREF` | 3.3 V | Control/Matrix ADCs |
| `BOARD_VREF_HV` | 5.0 V | HV-card ADCs |
| `BOARD_HV_COUNT` | 1 | HV boards fitted (1..4) |
| `AD7476_FULL_SCALE` / `CODE_MASK` | 4096.0 / `0x0FFF` | 12-bit |
| `DAC8830_FULL_SCALE` | 65536.0 | 16-bit → 0..500 V |
| `CONTINUITY_SETTLE_MS` | 2 ms | |
| `CONTINUITY_CONNECTED_V_MIN/MAX` | 1.3 / 1.7 V | connected band |
| `CONTINUITY_OPEN_V_MIN` | 3.0 V | open |
| `KELVIN_SETTLE_MS` | 2 ms | |
| `KELVIN_FORCE_CODE` | `0x8000` | DAC8775 code for 10 mA |
| `KELVIN_FORCE_CURRENT_A` | 0.010 A | |
| `KELVIN_INAMP_GAIN` | 1.0 | no InAmp in path |
| `KELVIN_R_MAX_OHM` | 5.0 Ω | default wire limit |
| `INSULATION_RAMP_MS` | 50 ms | settle after energising |
| `INSULATION_DISCHARGE_MS` | 200 ms | passive bleed before relay switch |
| `INSULATION_V_PASS_MAX` | 0.045 V | = 10 MΩ go/no-go |
| `MATRIX_EN_ACTIVE_LOW` | 1 | CD4067 `E` active-low |

**MCP23017 registers used:** `IODIRA=0x00`, `IOCON=0x0A`, `GPPUA=0x0C`, `GPIOA=0x12`, `OLATA=0x14` (16-bit writes auto-increment A→B), `IOCON.HAEN=0x08`, address base `0x20`.

---

## 4. Safety Model (invariants)

1. **MCP all-zero = safe.** HV relay gates are 2N7002 **active-HIGH** with 10 k pull-downs → `OLAT = 0x0000` means every relay is open.
2. **Matrix all-ones = safe.** CD4067 `E` is **active-LOW** → `OLAT = 0xFFFF` disables all 32 muxes. `MatrixCard_Init` forces this immediately (the generic MCP init leaves outputs low = muxes ON).
3. **Break-before-make.** Selecting a pin opens the whole bank/side first, then asserts exactly one enable.
4. **Cold switching.** Reed relays are only ever switched with the line de-energised (HV DAC = 0 + discharge wait). Hot-switching at 500 V erodes the MHV05 contacts.
5. **Every HV exit path** de-energises → waits `INSULATION_DISCHARGE_MS` → opens relays, including on error (`goto safe_exit`).

---

## 5. Functionality Catalogue

### F1 — System Power-On & Initialisation
**Entry point:** `Board_Init()` (called from `main.c` `USER CODE 2`) · **Status: implemented**
**Ref:** `[CC-PWR]` rails · `[CC-uC]` pinout · `[MX-MCP]` U101/U102 · `[HV-EXP]` U501–U508 · `[HV-TOP]` DAC/ADC · `[OD §2]`

1. Apply +5 V. Confirm rails: **+3.3 V** (TLV70033), **+5 V_ISO** (R05C05TE05S-R / R05CT05S-R), **+12 V** (LT8337).
2. CubeMX `MX_*_Init()` brings up I2C2/I2C3, SPI1/2/3, UARTs, GPIO.
3. **Matrix init** — `MatrixCard_Init(&g_matrix, &hi2c3, &sel)`:
   - `MCP23017_Init(U101, 0x20)` and `(U102, 0x21)`: write `IOCON = 0x08` (HAEN), `OLATA/B = 0x0000`, `IODIRA/B = 0x0000` (all outputs).
   - `MatrixCard_AllOff()` → write `OLAT = 0xFFFF` to **both** expanders → **all 32 muxes disabled**.
4. **Matrix ADC** — `MatrixCard_InitAdc(&g_matrix, &hspi1, PB0, 3.3f)`: park CS high.
5. **Front-end init** — `Frontend_Init(&g_frontend, cfg)`:
   - `DAC8775_Init` (SPI2, CS PB2) — park CS high.
   - `AD7476_Init` (SPI3, CS PB1) — park CS high.
   - `Frontend_SetMode(FRONTEND_MODE_CONTINUITY)` → drive **PC12 = LOW** (3V3 pull-up path).
6. **HV init (per board)** — `HvCard_Init(&g_hv[i], cfg)`:
   - `MCP23017_Init` ×4 inject (`0x20`–`0x23`) and ×4 return (`0x24`–`0x27`) on I2C2 → all `OLAT = 0x0000` → **all 128 relays open**.
   - `DAC8830_Init` → **write code `0x0000` → HV = 0 V**.
   - `AD7476_Init` ×2: RAIL (CS PC14), LEAK (CS PC13).
   - `HvCard_HvOff()` + `HvCard_OpenAllRelays()`.
7. **RTOS** — `Tasks_Init()` in `app_freertos.c`: LPUART1 @115200 (PA2/PA3, ST-LINK VCP), log queue, HW mutex, command queue, 4 tasks.

**Expected baselines:** continuity channel (SPI3) ≈ **3.3 V** (all paths open); HV RAIL (SPI2) < 0.005 V (HV off); HV LEAK < 0.005 V.

---

### F2 — Matrix Pin Routing *(primitive)*
**Entry point:** `MatrixCard_SelectPin(m, bank, pin)` / `MatrixCard_ConnectPair(m, hi, lo)` · **Status: implemented**
**Ref:** `[MX-MUX]` CD4067 `E`/S0-3 · `[MX-MCP]` U101=0x20 / U102=0x21, Pull_Down · `[MX-CON]` J101 · `[OD §5, §6]`

Route harness pin `p` (1..256) onto the `HI_COM` or `LO_COM` bus.

1. **Decode:** `mux = (p-1) >> 4` (0..15), `channel = (p-1) & 0x0F` (0..15).
2. **Break:** write `OLAT = 0xFFFF` to the bank's expander (U101 for HI, U102 for LO) → bank fully open.
3. **Address:** drive the bank's 4 shared select lines `HI_S0..3` / `LO_S0..3` = `channel` (LSB first). *(GPIOs currently NULL — the Control↔Matrix connector is not yet drawn; NULL ports are skipped.)*
4. **Make:** write `OLAT = 0xFFFF & ~(1 << mux)` → exactly one mux enabled (its `E` pin pulled LOW).
5. `ConnectPair` = step 1–4 for HI, then 1–4 for LO.
6. **Release:** `MatrixCard_AllOff()` → `0xFFFF` to both.

> Pin→(mux,channel) is a linear map (`matrix_map_pin`). If the PCB routes `I0..I15`
> differently, swap the body for a LUT — nothing else changes.

---

### F3 — HV Relay Selection *(primitive)*
**Entry point:** `HvCard_CloseInject/CloseReturn/ConnectPair` · **Status: implemented**
**Ref:** `[HV-EXP]` U501–U508 straps · `[HV-HS]` K1001–K1064 + 2N7002 + 10 k pull-down · `[HV-LS]` K2001–K2064 · `[OD §3.1, §4.2]`

Close exactly one of the 64 HS (or LS) reed relays on one HV board.

1. **Decode:** `exp = (pin-1) >> 4` (0..3), `bit = (pin-1) & 0x0F`.
2. **Break:** write `OLAT = 0x0000` to **all 4** expanders on that side → whole side open.
3. **Make:** write `OLAT = (1 << bit)` to expander `exp` → that 2N7002 gate goes HIGH → coil energises → contact closes.
   - Inject side = `H_CONT1..64` (MCP `0x20`–`0x23`), Return side = `L_CONT1..64` (MCP `0x24`–`0x27`).
4. `HvCard_OpenAllRelays()` → `0x0000` to all 8 → everything open.

---

### F4 — Front-End Mode Switch *(primitive)*
**Entry point:** `Frontend_SetMode(fe, mode)` · **Status: implemented**
**Ref:** `[CC-SPDT]` U3A TS5A3159 (COM=IN, throw3=ADC_IN + R54 10 k→+3V3, throw1=I_OUT, OPT0_CNTR=pin6) · `[CC-uC]` PC12 · `[OD §7]`

The TS5A3159 SPDT selects what drives the measurement node:

| Mode | `OPT0_CNTR` (PC12) | Path | Measuring ADC |
|------|--------------------|------|---------------|
| `FRONTEND_MODE_CONTINUITY` | **LOW** | +3V3 pull-up → `ADC_IN` | **Control U4 (SPI3)** |
| `FRONTEND_MODE_IMPEDANCE` | **HIGH** | DAC8775 `I_OUT` → wire | **Matrix U33 (SPI1, HI_COM)** |

> **Critical:** in impedance mode the SPDT **disconnects `ADC_IN`**, so the Control
> ADC cannot see the node. Resistance must be read from the Matrix ADC.

---

### F5 — Continuity Test (single pair)
**Entry point:** `Continuity_TestPair(hi_pin, lo_pin, &res)` · **Status: implemented**
**Ref:** `[CC-SPDT]` R54 10 k pull-up · `[CC-ADC]` U4 SPI3 · `[MX-MUX]`/`[MX-MCP]` routing · `[OD §6]`
**⚠ See Issue I-1** — the ≈1.5 V "connected" level is not reconciled with the schematic.

**Purpose:** confirm a wire exists between HS pin *i* and LS pin *j*.

1. `Frontend_SetMode(CONTINUITY)` → **PC12 = LOW** → 3V3 pull-up onto the node.
2. `MatrixCard_ConnectPair(hi_pin, lo_pin)` → F2 for both banks.
3. Wait **`CONTINUITY_SETTLE_MS` = 2 ms**.
4. `Frontend_ReadRaw()` → **Control U4 via SPI3**: CS LOW starts conversion, read one 16-bit frame, mask `0x0FFF`.
5. Convert: `V = (code / 4096) × 3.3`.
6. **Judge:**

| Reading | Verdict |
|---------|---------|
| **1.3 – 1.7 V** (≈1.5 V) | `TEST_PASS` — wire present |
| **≥ 3.0 V** (≈3.3 V) | `TEST_OPEN` — no wire |
| anything else | `TEST_ERROR` — anomaly (relay/wiring fault) |

7. **Always** `MatrixCard_AllOff()` before returning.

---

### F6 — Continuity Auto-Discovery Scan (256 × 256) *(planned)*
**Status: not implemented** — primitives exist (F2/F5); orchestration pending.

1. Confirm all matrix paths open, ADC ≈ 3.3 V; `OPT0_CNTR = LOW`.
2. For each HS `i` = 1..256: `MatrixCard_SelectPin(HI, i)`.
3.  For each LS `j` = 1..256: `MatrixCard_SelectPin(LO, j)`; read Control U4; if 1.3–1.7 V → record `(i, j)` as connected.
4.  `MatrixCard_BankOff(LO)`; next `i` → `MatrixCard_BankOff(HI)`, verify ADC returns to 3.3 V.
5. Output the connection map (multi-destination HS, LS with multiple sources).

---

### F7 — Continuity Plan Verification *(planned)*
**Status: not implemented**

1. Load expected `(HS, LS)` pair list from storage.
2. For each expected pair: run F5 → `PASS` if ≈1.5 V, **`F06` OPEN FAIL** if ≈3.3 V.
3. For each HS **not** in the plan: scan all LO channels; any ≈1.5 V = **`F07` SHORT FAIL**.
4. Emit report: PASS / OPEN / SHORT per connection.

---

### F8 — Resistance (Kelvin) Measurement (single pair)
**Entry point:** `Kelvin_MeasurePair(hi_pin, lo_pin, &res)` · **Status: implemented (2-wire, as drawn)**
**Ref:** `[CC-DAC]` DAC8775 IOUT_A → I_OUT · `[CC-SPDT]` I_OUT throw · `[MX-ADC]` U33 on SPI1 (VIN=HI_COM) · `[OD §7]`
**⚠ See Issue I-2** — the 10 mA return path / `LO_COM` reference is not established.

**Purpose:** measure wire resistance by forcing a known current and reading the drop.

1. `MatrixCard_ConnectPair(hi_pin, lo_pin)` → route the wire.
2. `Frontend_SetMode(IMPEDANCE)` → **PC12 = HIGH** → SPDT selects `I_OUT` (and disconnects `ADC_IN`).
3. `Frontend_SetCurrentCode(KELVIN_FORCE_CODE = 0x8000)`:
   - `DAC8775_SelectChannel(CH_A)` → 24-bit frame (3 bytes @ 8-bit) to `REG_SELECT (0x04)`.
   - `DAC8775_SetCode` → `REG_DACDATA (0x03)` → **10 mA** out of Channel A.
   - *(DAC8775 register-map constants still marked VERIFY vs datasheet.)*
4. Wait **`KELVIN_SETTLE_MS` = 2 ms**.
5. `MatrixCard_ReadRaw()` → **Matrix U33 via SPI1** (`HI_COM`), `V = (code/4096) × 3.3`.
6. **Compute:** `R = (V / KELVIN_INAMP_GAIN) / 0.010` → with gain = 1 → **`R = V / 0.010`**.
7. **Judge:** `R ≤ KELVIN_R_MAX_OHM (5.0 Ω)` → `TEST_PASS`, else `TEST_FAIL`.
8. **Release (always):** DAC code → 0, `Frontend_SetMode(CONTINUITY)` (**PC12 = LOW**), `MatrixCard_AllOff()`.

---

### F9 — Current-Source Calibration
**Status: procedure defined, not automated**

1. `OPT0_CNTR = HIGH`; program DAC8775 Ch.A for 10 mA.
2. Connect a **100 Ω** reference across the measurement path.
3. Read Matrix U33 → **expect 1.000 V** (10 mA × 100 Ω).
4. Deviation **> 5 %** → adjust the DAC code and repeat; log a correction factor. Uncorrectable → **`F10`**, do not run resistance tests.
5. Restore `OPT0_CNTR = LOW`.

---

### F10 — HV Rail Bring-Up (ramp to 500 V)
**Status: single-shot implemented; stepped ramp verification planned**
**Ref:** `[HV-TOP]` U401 CA05P-5 (VIN=+5V_ISO, VPGM←OPA376←DAC_OUT), U201 DAC8830, U301 · `[HV-DIV]` `V_HV_Sense = 0.00049 × V_HV` · `[OD §3.2]`

1. **Pre-check:** all 8 HV MCP `OLAT = 0x0000` (readback to confirm); RAIL ADC < 0.005 V.
2. `HvCard_SetVoltageCode(0x0000)` → HV = 0 V.
3. **Ramp** in 10 % steps of full scale, 100 ms hold per step (`code += 0x1999`):
   - `HvCard_SetVoltageFraction(f)` → `DAC8830_WriteCode(f × 65535)` → 16-bit SPI frame, CS LOW → transmit → **CS HIGH latches** → `VPGM` → CA05P-5 output.
4. **At each step** read RAIL (`HvCard_ReadRailVolts`, U301 via CS **PC14**, vref 5.0 V) and check against **V = 0.00049 × V_HV**:

| Target HV | Expected `HV_Sense` |
|-----------|--------------------|
| 50 V | ≈ 0.025 V |
| 100 V | ≈ 0.049 V |
| 200 V | ≈ 0.098 V |
| 350 V | ≈ 0.172 V |
| **500 V** | **≈ 0.245 V ± 0.010 V** |

5. Out of tolerance at any step → **write DAC = 0 immediately**, log **`F03`**, HALT.
6. **HV OFF:** `HvCard_HvOff()` → DAC code 0 → passive bleed via ≈10.05 MΩ.

---

### F11 — Insulation Test (single pair, 500 V)
**Entry point:** `Insulation_TestPair(board, inject_pin, return_pin, v_fraction, &res)` · **Status: implemented**
**Ref:** `[HV-DIV]` R3001–R3004, INS_VIN / HV_RET · `[HV-HS]`/`[HV-LS]` relays · `[HV-TOP]` U302 (CS=ISO_HV_Card_1) · `[OD §4]`
**⚠ See Issues I-3, I-4** — return-path definition and hot-switching in the OD scan procedure.

**Purpose:** go/no-go the insulation between an HS conductor and the return.

1. **Safe pre-condition** (`insulation_safe`): `HvCard_HvOff()` (DAC = 0) → `Discharge()` (no-op; passive) → wait **200 ms** → `HvCard_OpenAllRelays()`.
2. **Connect COLD** — `HvCard_ConnectPair(inject_pin, return_pin)` (F3). *The line is dead here; this ordering is mandatory because the DAC is the HV control — closing relays after energising would hot-switch them at 500 V.*
3. **Energise** — `HvCard_SetVoltageFraction(v_fraction)` → DAC8830 code = `f × 65535` → HV rises toward `f × 500 V`.
4. Wait **`INSULATION_RAMP_MS` = 50 ms** (RC settling with stray capacitance).
5. **Measure the LEAK node** — `HvCard_ReadLeakageRaw()` → **U302 via CS PC13** (`HV_RET`, across `R3004` 1 kΩ), `V = (code/4096) × 5.0`.
6. **Judge (go/no-go):**

| `V_HV_RET` | Insulation | Verdict |
|------------|-----------|---------|
| **< 0.045 V** | **> 10 MΩ** | `TEST_PASS` |
| **≥ 0.045 V** | **≤ 10 MΩ** | `TEST_FAIL` (**`F04`**) |

  *Higher voltage = worse insulation.* Informational estimate:
  `I_leak = V / 1 kΩ`; `R_ins ≈ (V_applied / I_leak) − 1 MΩ`.
7. **Always de-energise** (`safe_exit` → `insulation_safe`): DAC = 0 → wait 200 ms → open relays **cold**.

---

### F12 — Insulation Full Scan (all HS lines) *(planned)*
**Status: not implemented** — needs 4 HV cards + per-card bus select for 256 lines.

1. Verify all MCP `OLAT = 0x0000`; matrix all open.
2. For each HS `n` = 1..64 (per board): run F11 against the chosen return.
3. Wait ≥ 20 ms between relays; log per-line `V_HV_RET` + PASS/FAIL.
4. After the last line: confirm all `OLAT = 0x0000`, DAC = 0, RAIL < 0.002 V.
5. Emit the insulation report.

---

### F13 — Safe State / Fault Handling
**Entry point:** `Safety_SignalFault()`, `force_safe_all()` in `tasks.c` · **Status: implemented**

- **`tSafety` (priority High, 10 ms loop):** if a fault is latched, take the HW mutex and `force_safe_all()`:
  1. `HvCard_HvOff()` for every board (DAC → 0).
  2. `HvCard_OpenAllRelays()` for every board (`OLAT = 0x0000` ×8).
  3. `MatrixCard_AllOff()` (`OLAT = 0xFFFF` ×2).
- When idle (no HV test running) it also backstops HV-off on every board.
- `Safety_ClearFault()` releases the latch. IWDG refresh hook is in place (watchdog not yet enabled).
- **A single HW mutex** serialises all shared I2C/SPI access between the sequencer and safety tasks.

---

### F14 — Logging & Bring-Up Console
**Entry point:** `Log_*` / `tComms` · **Status: implemented**

- Leveled logger (ERROR/WARN/INFO/DEBUG), non-blocking: formats `<L>[tick] tag: msg` into a drop-if-full queue; `tLogger` (Low) drains it to **LPUART1 @ 115200 (PA2/PA3 = ST-LINK VCP)**.
- Console commands on the VCP:

| Key | Action |
|-----|--------|
| `c` | continuity test (pins 1–2) |
| `k` | kelvin/resistance (pins 1–2) |
| `i` | insulation (board 0, pins 1–1, 50 % = 250 V) |
| `s` | force safe-all |
| `f` | raise fault |
| `r` | clear fault |

- Commands are queued to `tSequencer` (Normal), which runs **one test at a time** under the HW mutex.

---

## 6. Fault Codes

| Code | Meaning | Action |
|------|---------|--------|
| `F01` | I2C device not found | Check wiring/pull-ups/isolator supply. HALT. |
| `F02` | SPI ADC no response / invalid | Check CS, CLK, MISO, isolator. HALT. |
| `F03` | HV ramp out of tolerance | DAC = 0 immediately. HALT. |
| `F04` | Insulation fail (`V_HV_RET ≥ 0.045 V`) | De-energise, log line, flag harness. |
| `F05` | MCP `OLAT` readback ≠ `0x00` | Re-command; if persistent, HALT HV ops. |
| `F06` | Continuity OPEN (expected wire missing) | Log pair, continue. |
| `F07` | Continuity SHORT (unplanned connection) | Log pair, continue. |
| `F08` | Resistance HIGH (`R > R_max`) | Flag wire. |
| `F09` | Resistance LOW (`R < R_min`) | Check parallel path / calibration. |
| `F10` | Current-source cal fail (>5 %) | Do not run resistance tests. |

---

## 7. Implementation Status

| # | Functionality | Status |
|---|---------------|--------|
| F1 | System init / POST | ✅ implemented (no I2C bus scan / HALT-on-missing yet) |
| F2 | Matrix routing | ✅ implemented (select GPIOs NULL until connector drawn) |
| F3 | HV relay selection | ✅ implemented |
| F4 | Front-end mode switch | ✅ implemented |
| F5 | Continuity — single pair | ✅ implemented |
| F6 | Continuity auto-discovery | ⬜ planned |
| F7 | Continuity plan verify | ⬜ planned |
| F8 | Resistance — single pair | ✅ implemented |
| F9 | Current-source calibration | ⬜ procedure only |
| F10 | HV ramp | 🟡 single-shot; stepped verification planned |
| F11 | Insulation — single pair | ✅ implemented |
| F12 | Insulation full scan | ⬜ planned |
| F13 | Safe state / fault | ✅ implemented |
| F14 | Logging / console | ✅ implemented (full host protocol pending) |

---

## 8. Prerequisites Before Hardware Bring-Up

**CubeMX / `.ioc` (required — generated default is `SPI_DATASIZE_4BIT`):**
- SPI1 → 16-bit RX, ≤ 20 MHz, soft-CS **PB0** (assign PB0 as GPIO output).
- SPI2 → mixed: DAC8775 8-bit vs DAC8830/AD7476 16-bit → set data size per transaction (or run 8-bit and byte-frame).
- SPI3 → 16-bit RX, ≤ 20 MHz, soft-CS **PB1**.
- `OPT0_CNTR` (PC12) and the HV ADC-CS lines (`HV_Card_x.0/x.1`) → **INPUT → OUTPUT**.

**Open items:**
- HV DAC8830 CS (`CS_ISO`) pin — confirm from connector netlist (placeholder PC2).
- CA05P-5 output capacitance — sets the real `INSULATION_DISCHARGE_MS`.
- Per-card **ISO1251 + chip-select** — required for >1 HV card (all cards use identical MCP addresses `0x20`–`0x27`, so they cannot share a bus).
- Control↔Matrix connector (`HI_COM`/`LO_COM`, `HI_S0..3`/`LO_S0..3`, isolated I2C, power).
- DAC8775 current-source register map — VERIFY vs datasheet.
- Matrix EN-line pull-ups (next schematic rev) — muxes float until MCP init.

---

## 9. Issues Found Cross-Checking This Spec Against `Doc/`

Raised 2026-07-14 while deriving each functionality from the schematics + OD v1.2.

### I-1 — Continuity "connected ≈ 1.5 V" is not explained by the schematic — **HIGH**
`[CC-SPDT]` shows **R54 = 10 kΩ** pulling `ADC_IN` up to +3V3. `[OD §6]` claims a
connected wire reads **≈ 1.5 V** and an open reads ≈ 3.3 V.
- Open ≈ 3.3 V ✓ consistent (unloaded pull-up).
- **Connected ≈ 1.5 V is not reproducible from the drawn parts.** A good harness wire
  is ~0 Ω, so `ADC_IN` would need the return path to present ≈ **8.3 kΩ** to ground
  (`3.3 × R/(10k+R) = 1.5` → `R ≈ 8.3 k`). No such element exists in the schematics.
  - If `LO_COM` returns to GND directly → connected ≈ **0 V**.
  - If the only path is the 100 kΩ `LO_COM` pull-down `[MX-MCP Pull_Down]` → ≈ **3.0 V**,
    i.e. indistinguishable from open.
- **Impact:** F5's PASS band (1.3–1.7 V) may be wrong. (The original firmware assumed
  ≤ 0.5 V.) **Need the intended continuity return topology + resistor values.**

### I-2 — Resistance: the 10 mA return path / `LO_COM` reference is undefined — **HIGH**
`[CC-DAC]` `IOUT_A → I_OUT` → `[CC-SPDT]` → `IN` → matrix → wire → `LO_COM`. The only
`LO_COM` reference drawn is a **100 kΩ pull-down** `[MX-MCP Pull_Down]`. Forcing 10 mA
through 100 kΩ would require 1000 V — impossible. A low-impedance return must exist but
is not drawn. **Impact:** F8 cannot be trusted, and it changes what U33 (`HI_COM`) reads.

### I-3 — The Control Card has **no Matrix connector** — **HIGH**
`[MX-CON]` J101 (50-pin) carries `HI_COM`, `LO_COM`, `HI_S0..3`, `LO_S0..3`,
`SPI1_CS/SCK/MISO`, `SDA_ISO/SCLK_ISO`, power. `[CC-CON]` has only **J1–J4 = HV_Card_1..4**
and J5 = power barrel — **no mating matrix connector**. So the select lines, the analogue
buses and SPI1 do not physically reach the Control Card. This is why the firmware leaves
the matrix select GPIOs NULL. **Blocks F2 / F5 / F8 on hardware.**

### I-4 — SPI1 is routed to the HV connectors but unused by the HV card — **MEDIUM**
`[CC-CON]` J1 carries `SPI1_CS/SCK/MISO` to the HV cards, but `[HV-CON]` J1001 lists no
SPI1 net (HV ADCs use `SPI2_SCK_ISO`/`SPI2_MISO_ISO`). Meanwhile SPI1 is exactly what the
**Matrix** ADC needs `[MX-ADC]` — and the matrix has no Control-Card connector (I-3).
Either the SPI1 pins on the HV connector are vestigial, or the matrix link was intended to
route through one of them. **Needs a routing decision.**

### I-5 — DAC8830 `CS_ISO` has no identified Control-Card source; possible CS collision — **MEDIUM/HIGH**
`[HV-TOP]` U201: `CS=CS_ISO`, `SCLK=SCL_ISO`, `SDI=SDA_ISO`. `[HV-CON]` lists `CS_ISO` and
`CS1_ISO`. `[CC-CON]` provides `SPI2_SCK/CS/MOSI/MISO_ISO` + the two `ISO_HV_Card` GPIO.
If `CS_ISO` maps to `SPI2_CS_ISO`, it **collides with the DAC8775 `SYNC_N`** `[CC-DAC]`,
which already uses `SPI2_CS_ISO` → both DACs selected simultaneously. Firmware placeholder
is PC2. **Resolve from the connector netlist.**

### I-6 — The OD insulation scan **hot-switches every relay** — **HIGH**
`[OD §4.2.2]` holds HV at 500 V and toggles one relay bit per line ("write bit to 1 …
read … write bit back to 0. Wait 20 ms before next relay") with **no ramp-down between
lines**. That switches MHV05 contacts at 500 V on every line — the arc-erosion case the
design explicitly avoids. Firmware F11 de-energises + waits 200 ms (cold). Also OD's 20 ms
inter-relay wait is far shorter than the passive 10.05 MΩ bleed needs.
**Decision required:** accept cold-switch scan time (≈250 ms/line ⇒ ~1 min per 256 lines),
accept hot-switching (relay life), or add an active discharge.

### I-7 — The OD insulation test leaves the return undefined — **MEDIUM**
`[OD §4.2.2]` energises only HS[n] with "all other reed relays OFF", including every LS
relay. But leakage must return through `HV_RET`/`R3004` `[HV-DIV]` to be measured — with
all LS relays open there is **no defined return**, so the measurement cannot work as
written. Firmware F11 closes an inject+return **pair** (defined return). These are different
tests: "HS[i] vs LS[j]" (pair) vs "HS[n] vs everything else" (needs the rest bonded to
`HV_RET`). **Confirm the intended insulation topology.**

### I-8 — DAC8830 presence cannot be verified — **LOW**
DAC8830 is write-only SPI (no SDO) `[HV-TOP]`, so POST cannot detect it or "record an
address". The only indirect check is ramping HV and watching `HV_Sense`.

### I-9 — Four HV cards cannot share one I2C bus — **known, fix in progress**
`[HV-EXP]` every (identical) card straps its 8 MCPs to `0x20`–`0x27`; MCP23017 has only
3 address bits, so one card consumes all 8. **ISO1251 + per-card chip-select** is the fix.

### I-10 — CA05P-5 `VMON` unused — **LOW**
`[HV-TOP]` U401 `VMON` and `HV_RTN` are marked not-connected. `VMON` could provide a rail
monitor independent of the divider; firmware doesn't use it.

### I-11 — Settle times are placeholders — **LOW**
`CONTINUITY_SETTLE_MS` / `KELVIN_SETTLE_MS` = 2 ms were chosen before the matrix
capacitance was known. Tune on hardware once I-1/I-2/I-3 are resolved.

---

### I-12 — 500 V insulation test vs the matrix CD4067 input clamps — ✅ **RESOLVED 2026-07-14**
**Answer (design owner):** the Matrix 256 lines and the HV 256 lines are **separate nets —
no conductor is common between HV and Matrix**. The HV rail therefore never reaches a
CD4067 input, so the clamp path below does not exist and the 500 V develops normally.
The test scenario is **sequential: the Matrix phase runs first, then the HV phase.**
*(Analysis retained below for the record.)*

<details><summary>Original analysis (no longer applicable)</summary>
`[MX-MUX]` the CD4067BF3A muxes run from **VCC = +3V3**, so every mux input pin
(`I0..I15` = the harness conductors) has an **ESD clamp diode to +3V3 that is always
present — disabling the mux (`E` high) does NOT remove it**.

**Question:** do the matrix `HI1..256`/`LO1..256` lines and the HV card
`H_PWR1..64`/`L_PWR1..64` lines land on the **same harness conductors**? For a
256-line harness with 4 HV cards (4 × 64 = 256) they map 1:1, and `[OD §4.1.3]`
("Confirm Matrix Card all outputs = 0x00 … before insulation") implies they do.

**If they share conductors, the insulation test cannot work:**
- HV injects 500 V through ≈11 MΩ into the harness line.
- That line is also a CD4067 input → its clamp diode conducts as soon as the line
  exceeds ≈3.9 V, so **the line never rises above ≈3.9 V** — the 500 V stress is
  never applied to the insulation.
- The clamp sinks the full ≈45 µA into +3V3, which appears across `R3004` as
  **45 µA × 1 kΩ = 0.045 V — exactly the FAIL threshold**. So **every line reads FAIL**,
  regardless of its actual insulation.
- The 11 MΩ current limit means the diode survives (45 µA is harmless) — this is a
  **measurement-validity** failure, not a smoke failure, which makes it easy to miss.

**Mitigation options:** HV-rated isolation relays between the matrix and the harness;
or matrix and HV never share a conductor (separate fixture positions); or per-line HV
blocking (impractical for 512 lines). `[OD §4.1.3]`'s "matrix outputs = 0x00" is **not**
a sufficient mitigation.
</details>

**Consequence for firmware:** the phase order (Matrix → HV) should be *enforced*, not just
procedural — the sequencer should refuse an insulation run until the matrix phase has
completed, so a harness with a known short is never HV-stressed.

### I-13 — 10 mA resistance test over-ranges and over-stresses the 3V3 analogue path — **HIGH**
The whole LV path is 3.3 V-rated: CD4067 `VCC = +3V3` `[MX-MUX]`, AD7476 U33
`VDD = +3V3` `[MX-ADC]`, TS5A3159 `V+ = +5V` `[CC-SPDT]`. But `[CC-DAC]` DAC8775 runs
its output stage from **+12 V (PVDD)**.

At the documented **10 mA** test current (`[OD §7]`):

| Wire R | Node voltage | Consequence |
|--------|--------------|-------------|
| 100 Ω (cal ref) | 1.0 V | OK ✓ |
| **> 330 Ω** | **> 3.3 V** | exceeds AD7476 input range **and** CD4067 analogue range → reading clips |
| **> 500 Ω** | **> 5 V** | exceeds the TS5A3159 rail |
| **open / broken wire** | rises to DAC compliance (**≈12 V**) | 10 mA driven into the CD4067 / AD7476 / SPDT **ESD clamp diodes** — at/over the typical ±10 mA limit, with CMOS latch-up risk |

No clamp or series limiter is drawn on `HI_COM` at U33 `[MX-ADC]`. **An open or
high-resistance wire — exactly the fault being tested for — is the damaging case.**
**Mitigations:** gate resistance on a passing continuity test (firmware, free); clamp
`HI_COM` (Schottky to +3V3 + series R); limit the DAC8775 compliance; or drop the test
current so full-scale ≈3 V (e.g. 1 mA ⇒ 0–3 kΩ range).

### I-14 — No HV safety interlock — **MEDIUM (safety/compliance)**
No enclosure/door interlock input exists in `[CC-uC]` or `[CC-CON]`. `[OD §3]` only
states "ensure the test fixture is fully enclosed" as a procedural note. A 500 V
instrument would normally have a **hardware** interlock that cannot be bypassed in
firmware (e.g. gating the CA05P-5 supply or VPGM).

### I-15 — DAC8775 reference wiring — **VERIFY**
`[CC-DAC]` U2 pins `REFIN (46)` / `REFOUT (47)`: could not confirm from the PDF whether
`REFOUT` is tied to `REFIN` (or an external reference applied). If the reference is not
connected the DAC produces no output. Please confirm against the netlist.

### I-16 — Buzzer unused (suggestion, not a defect)
`[CC-uC]` PA15 → `BUZZ_I/P` → 2N7002 → SMI-1027 buzzer is fitted but no firmware drives
it. Natural use: **audible HV-live warning** whenever the HV DAC is non-zero, which also
partially offsets I-14.
