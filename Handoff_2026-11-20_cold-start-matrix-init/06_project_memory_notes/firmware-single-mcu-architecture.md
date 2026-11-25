---
name: firmware-single-mcu-architecture
description: "HT_MK1 firmware runs on one STM32G474 (Control Card); Matrix and HV cards are peripheral-only, driven over I2C/SPI"
metadata: 
  node_type: memory
  type: project
  originSessionId: c5000e64-a077-42b7-a176-374f7cd85c12
  modified: 2026-07-27T10:19:24.643Z
---

The HT_MK1 firmware is a **single-MCU** design. The STM32G474RET6 on the **Control Card is the only processor** in the whole instrument. The Matrix Card and HV Cards have **no MCU** — they are just I2C GPIO expanders (MCP23017), analog muxes (CD74HC4067), reed relays, DACs (DAC8775 / DAC8830) and ADCs (AD7476) that this one firmware drives over I2C/SPI plus a few GPIOs.

**How to apply:** All test logic (continuity, Kelvin, insulation) lives in this firmware. "Talking to the Matrix/HV card" means doing I2C/SPI transactions, not inter-processor messaging.

**STALE WARNING (2026-07-27):** the resistance-path claims below were written against the *previous* Matrix/Control schematics. `Matrix_Card-6` / `Control_Card-4` replaced 2-wire resistance with 4-wire Kelvin on a 24-bit ADS124S08, moved the mux address lines onto a Control-Card MCP23017, and made 10 mA unachievable. Read [[matrix-card-kelvin-resistance-rework]] first; where the two disagree, that one wins.

Peripheral map — CORRECTED against the Doc-folder schematics (2026-07, now authoritative; see [[schematics-are-source-of-truth]]). The old firmware board.c assignments are WRONG:
- **SPI1** (PA5/6/7, CS PB0) = **Matrix-Card AD7476 (U33, reads HI_COM, vref 3V3)**; also routed to HV connectors. *(Rev 6: SPI1 is now shared with the ADS124S08 U68, and U33 is continuity-only.)*
- **SPI2** (PB13/14/15, CS PB2, isolated) = **DAC8775** (Kelvin 10 mA I-source) + the **HV-card AD7476s** share this isolated bus.
- **SPI3** (PB3/4/5, CS PB1) = **Control-Card AD7476 (U4, reads ADC_IN off the Opto SPDT, vref 3V3)**.
- I2C2 = PC4/PA8 (+CS PC2); I2C3 = PC8/PC9 (+CS PC3). One serves HV MCPs, other serves Matrix MCPs.
- **DAC8830** (HV V_PGM) is **SPI** (CS/SCLK/SDI), NOT I2C — the Operation Document's "DAC via I2C" is wrong.
- **OPTO_CNTR = PC12** (mode switch; PA15 is the BUZZER, not OPTO — Operation Document says PA15, wrong).
- **HV_Card_x.0 / x.1 GPIO are the two ADC chip-selects** on HV card x (CS for the HV_RET and HV_Sense AD7476), NOT HV-enable/discharge. HV on/off is done **purely via the DAC8830 voltage** (set 0 = off); there is **no firmware HV-enable and no discharge relay** (CA05P-5 VIN tied to +5V_ISO; bleed is passive through the sense divider). Firmware's HvCard_HvEnable/Discharge GPIO model is therefore wrong.
- Four AD7476 total: Control U4 (SPI3, 3V3) = **continuity** measure (ADC_IN); Matrix U33 (SPI1, HI_COM, 3V3) = **resistance** measure (ADC_IN is disconnected by the SPDT in I_OUT mode, so Kelvin reads HI_COM); HV ×2-per-card (SPI2-iso, **vref 5.0 V off +5V_ISO**): U301=HV_Sense rail monitor (~0.245 V @500 V, ratio 0.00049), U302=HV_RET leakage.
- Insulation is **go/no-go**: 10 MΩ ⇔ 0.045 V at HV_RET (below=PASS, at/above=FAIL); INSULATION_V_PASS_MAX=0.045, effective leakage series ≈1 MΩ.
- HW decisions (user, 2026-07-14): no HV inhibit needed (DAC→opamp drives VPGM, 10.05 MΩ passive bleed); per-card I2C **ISO1251 + chip-select** to be added so 4 identical cards (all MCP 0x20-0x27) share the bus — firmware will need a per-card bus-select GPIO asserted under the HW mutex, one card at a time; EN-line pull-ups to be added next schematic rev.
- HV sense divider (HV_Card Reed_Relay sheet): R3001 10M, R3002 1M, R3003 50k, R3004 1k. HV_Sense ≈ 0.25 V at 500 V (rail monitor, U301); voltage across R3004 1k read at HV_RET (U302) ≈ 0.045 V at dead-short = the insulation/leakage measurement.
- Firmware fixes applied 2026-07-14 (all compile clean via bundled arm-none-eabi-gcc): BOARD_VREF 3.0→3.3 (+ BOARD_VREF_HV 5.0); continuity band →1.3-1.7 V connected; Kelvin InAmp gain 10→1; board.c SPI map corrected (control ADC→SPI3, HV bus→SPI2); HvCard reworked to **two ADCs** (adc_rail=HV_Sense, adc_leak=HV_RET) + HvCard_HvOff/HvEnable(0)=DAC 0 + Discharge=passive no-op, the two per-card GPIO now the ADC CS; insulation.c reads the leakage node and classifies by voltage (verdict PASS/FAIL) with an approximate ohms estimate. Still VERIFY (needs connector netlist): HV DAC8830 CS pin (CS_ISO) and SPI2 mixed 8/16-bit data-size handling.

**Code layout:** layered driver stack under `Core/Src/drivers` + `Core/Inc/drivers` (include as `"drivers/xxx.h"`). `Core` is a recursive CubeIDE source path so new subfolders compile with no .cproject edit. First driver done: `mcp23017` (bus-agnostic, address-parameterized — foundation for matrix mux-enables and HV relay drivers). Planned: dac8775, dac8830, ad7476, then cards/ (matrix, hv, control front-end) and test/ layers.

Matrix mux addressing — RESOLVED by updated Matrix_Card.pdf (2026-06-16, now 4 sheets, muxes = CD4067BF3A):
- Select lines are SHARED/broadcast per side: one `HI_S0..3` for all 16 HI muxes, one `LO_S0..3` for all 16 LO muxes. Enables are one-hot: `HI_EN1..16`, `LO_EN1..16`.
- Expanders: **U101 drives all 16 HI_EN**, **U102 drives all 16 LO_EN** (GPB0-7 = EN1..8, GPA0-7 = EN9..16). All 32 GPIO used for enables.
- To route harness pin p (1..256): mux_index = ((p-1)>>4)+1 (assert that one EN), channel = (p-1)&0x0F (drive S[3:0]).
- The S0..3 lines are driven by MCU GPIO and reach the matrix over connector **J101 (50-pin, 61205022021)**, which also carries analog buses HI_COM/LO_COM, isolated I2C (SCLK_ISO/SDA_ISO), +5V/+3V3. Harness fixture connectors now populated (DE9/DA15/DB25/DC37 + 50/100-pin headers) for HI1..256/LO1..256.
- On-card I2C isolator U103 = **ADUM1205ARZ (bidirectional)** — reads/ACK DO work. The earlier "ADuM3201 write-only" worry is RESOLVED (Control-Card I2C isolators are ADUM1250, also bidirectional).

Still to confirm with user: the two MCP23017 I2C addresses (U101 HI / U102 LO — build-time strap option, must differ; assume 0x20/0x21 until told; not annotated on the sheet, unlike the sense expanders at 0x23/0x24/0x25). **Item (2) "which MCU GPIOs drive HI_S0..3 / LO_S0..3" is ANSWERED: none — Control_Card-4 adds MCP23017 U21 on I2C3 for them.** See [[schematics-are-source-of-truth]] and [[matrix-card-kelvin-resistance-rework]].

Config caveats noted in generated code (likely need fixing in CubeMX): all SPIs are `SPI_DATASIZE_4BIT` (DAC8775/DAC8830/AD7476 need 8/16-bit frames); the Control-Card AD7476 nets are named `I2C2_*` but the part is SPI-serial.
