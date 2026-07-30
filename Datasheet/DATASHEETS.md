# Component Datasheets — HT_MK1

Every active part on the three cards, extracted from `Doc/Control_Card-4.pdf`,
`Doc/Matrix_Card-6.pdf` and `Doc/HV_Card-1.pdf`. Tick a row once the PDF is in this folder.

Suggested filename convention: lowercase part family, no suffixes — `cd4067b.pdf`,
`mcp23017.pdf`, `stm32g474_rm0440.pdf`.

## Priority 1 — firmware needs these to finish the resistance path

| ✓ | Part | Where | Vendor | Why firmware needs it |
|---|---|---|---|---|
| ✅ | **ADS124S08**IRHBR | Matrix U68 | TI | Register map, commands, PGA/reference limits. **Have it** (`ads124s08.pdf`). |
| ✅ | **CD4067B**F3A | Matrix U1–U65 | TI | Rₒₙ vs VDD at 3.3 V — sets the excitation-current ceiling (BU-01). The single biggest unknown in the compliance budget. |
| ☐ | **DAC8775**IRWFR | Control U6 | TI | Current-source mode: code → current mapping and compliance voltage (FW-02). |
| ☐ | **MCP23017** | all cards ×14 | Microchip | Register map, power-on defaults, I2C timing. |
| ☐ | **AD7476**SRTZ-EP | Control, Matrix U33, HV ×2 | Analog Devices | SPI mode and CS-framed timing — needed to share SPI1 with the ADS124S08 (BU-02). |
| ☐ | **STM32G474** datasheet | Control U1 | ST | Pin alternate functions, electrical limits. |
| ☐ | **RM0440** reference manual | Control U1 | ST | Peripheral programming (SPI/I2C). Large but essential. |

## Priority 2 — HV subsystem

| ✓ | Part | Where | Vendor |
|---|---|---|---|
| ☐ | **CA05P-5** | HV U401 | XP Power / EMCO — 500 V DC-DC, VPGM transfer function |
| ☐ | **MHV05-1A** | HV ×128 | Standex-Meder — reed relay, coil current and HV rating |
| ☐ | **DAC8830**MCDEP | HV U201 | TI |
| ☐ | **OPA376**xxDBV | HV U101 | TI |
| ☐ | **NTS0102DP**-Q100H | HV U1002/U1003 | Nexperia — level shifter |
| ☐ | **BAV99LT1G** | HV | onsemi |
| ☐ | **1N5819** | HV D401 | Schottky |

## Priority 3 — isolation, power and discretes

| ✓ | Part | Where | Vendor |
|---|---|---|---|
| ☐ | **ADuM1250**ARZ | Control U9/U10 | ADI — I2C isolator |
| ☐ | **ADuM1205**ARZ | Matrix U103 | ADI — I2C isolator |
| ☐ | **ADuM3200**TRZ-EP | Control | ADI — SPI isolator |
| ☐ | **ADuM3201**TRZ-EP | Control | ADI — SPI isolator |
| ☐ | **TLV70033** | Control U5 | TI — 3.3 V LDO |
| ☐ | **LT8337**EV-1-PBF | Control U3 | ADI — +12 V boost |
| ☐ | **R05C05TE05S-R** | Control U2 | Recom — isolated 5 V DC-DC |
| ☐ | **R05CT05S-R** | Control U4 | Recom — isolated 5 V DC-DC |
| ☐ | **TS5A3159**DBV | Control U7 | TI — analog SPDT (the force/continuity selector) |
| ☐ | **2N7002LT1G** | Control, HV | onsemi — relay-driver MOSFET |
| ☐ | **B140**-13-F | Control D3/D4 | Diodes Inc — Schottky |
| ☐ | **P6SMB33A** | Control D1/D2 | TVS |
| ☐ | **61205022021** | all cards | Würth — 50-pin box header |

## Key numbers already pulled from the ADS124S08 datasheet (SBAS660C)

Recorded here so they do not have to be re-derived:

- **VREF (external): 0.5 V min**, max AVDD − AVSS. Confirms that 1 mA × 100 Ω = 100 mV
  cannot drive REFP0/REFN0 ratiometrically (PROJECT_LOG HW-04).
- **PGA absolute input range**, gain 1–16: `AVSS + 0.15 + |VINMAX|·(Gain−1)/2` to
  `AVDD − 0.15 − |VINMAX|·(Gain−1)/2`. **Gain 32–128 uses a different formula:**
  `AVSS + 0.15 + 15.5·|VINMAX|` to `AVDD − 0.15 − 15.5·|VINMAX|`.
- **PGA bypass** (`PGA_EN = 00`) removes the headroom constraint entirely — absolute input
  range becomes AVSS − 0.05 to AVDD + 0.05. Right mode for single-ended reads.
- **Internal 2.5 V reference is OFF at reset** (`REFCON = 00`). Firmware must set
  `REFSEL = 10` *and* `REFCON = 01` or `10`.
- **START/SYNC must be held LOW** for the START command to be decoded — confirms the
  pull-down asked for in HW-10.
- `DEV_ID = 000` identifies the ADS124S08. `AINCOM` is mux code `1100`.
- Commands: RESET `0x06`, START `0x08`, STOP `0x0A`, RDATA `0x12`, SFOCAL `0x19`,
  RREG `0x20|addr`, WREG `0x40|addr`.
- Defaults: 20 SPS, low-latency filter, continuous conversion, internal 4.096 MHz oscillator.
