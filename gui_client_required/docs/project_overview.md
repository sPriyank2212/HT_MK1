# Harness Tester — Project Overview

**Document ID:** POV-001 | **Version:** 3.0 | **Date:** 2026-04-30
**Change v3.0:** Redesigned as two-card architecture. Card 1 uses SPI-based external ADC/DAC (ADS8688×2, ADS131M04, DAC8411), XTR111 current source, TMUX1101 mode switch, INA826 InAmp, 34× CD74HC4067M96 MUX. Card 2 uses EMCO CA05N-5 + ISOM8110 isolation. Removed MCP23017, internal OPAMP VCCS, internal ADC/DAC for measurement.
**Change v2.0:** DUT interface changed to 7× DB37 gold-plated female connectors (259 pins). Enclosure upgraded to 450×250×100mm.

---

## Requirements

- Test wire harnesses with up to **256 pins** automatically
- Detect **open circuits** (missing connections) against a reference netlist
- Detect **short circuits** (unexpected connections) between any pin pair
- Measure **wire resistance** with **1mΩ resolution** using known-current injection (XTR111 + INA826 + 24-bit ADC)
- Complete **full 256-pin mapping in ~29ms** using parallel dual-ADS8688 simultaneous scanning
- Perform **insulation resistance test** at up to **500V DC** per net
- Compare test results against a **JSON netlist** (expected connections)
- Communicate with PC over **UART via USB-UART adapter** (921600 baud)
- Generate **CSV and PDF test reports** after every test session
- Save and load **test profiles** (thresholds, netlist path, operator info)
- Enforce **hardware safety interlock** — HV disabled when enclosure lid is open
- Perform **MUX self-calibration** using HI_CAL_MUX and LO_CAL_MUX reference paths → 1mΩ accuracy
- Operate as a **standalone tester** controlled from PC software (Python + PyQt6 GUI)

---

## Definitions

| Term                                 | Definition                                                                                                 |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| **DUT**                        | Device Under Test — the wire harness or cable assembly being tested                                       |
| **Netlist**                    | JSON file defining all expected electrical connections in the DUT                                          |
| **Continuity**                 | Electrical connection between two pins (detected by voltage threshold)                                     |
| **Open Fault**                 | An expected connection is missing in the DUT                                                               |
| **Short Fault**                | An unexpected connection exists between two pins                                                           |
| **Known-Current Method**       | Resistance measurement: XTR111 forces known current through wire; INA826 measures resulting voltage drop  |
| **IR (Insulation Resistance)** | Resistance between two conductors measured at high voltage (MΩ range)                                     |
| **HV**                         | High Voltage — up to 500V DC used for insulation resistance testing                                       |
| **MUX**                        | Analog multiplexer (CD74HC4067M96) — routes any of 16 pins to a single measurement bus                   |
| **XTR111**                     | Voltage-to-current converter used as the precision current source for resistance measurement               |
| **InAmp**                      | Instrumentation amplifier (INA826) — measures differential voltage across DUT wire                        |
| **MCU**                        | Microcontroller Unit — STM32G474RET6, the main measurement engine                                         |
| **Golden Sample**              | A known-good reference harness used to learn the expected netlist automatically                            |
| **Pass/Fail Verdict**          | Overall test result: PASS if all connections match netlist and all limits are met; FAIL otherwise          |
| **CRC**                        | Cyclic Redundancy Check (CRC-16/CCITT) — error detection on every UART packet                             |
| **Interlock**                  | Physical lid switch that immediately cuts HV when the enclosure is opened                                  |
| **Calibration Offset**         | Stored resistance value subtracted from every measurement to remove systematic error (MUX Rds + PCB trace) |
| **HI_MUX / LO_MUX**           | High-side and low-side multiplexer chips connecting Side A and Side B DUT pins to measurement buses        |
| **HIGH_SIDE_COM / LOW_SIDE_COM** | The common buses connecting the selected MUX output to the measurement front-end                         |
| **TMUX1101**                   | SPDT analog switch that selects between pin-mapping mode (PA0=LOW) and resistance-measurement mode (PA0=HIGH) |

---

## Features

### Hardware

- **MCU:** STM32G474RET6 (Military, ARM Cortex-M4F, 170MHz)
- **34× CD74HC4067M96 analog MUX (military): 16× HI_MUX + 16× LO_MUX + 1× HI_CAL + 1× LO_CAL**
- **DUT interface:** **7× DB37 gold-plated female panel-mount connectors** (7×37 = 259 pins; 256 active + 3 chassis GND). Layout: 4+3 grid on front panel. Enables intermediate adapter harness for any target connector type (MQS, JPT, Deutsch DT, MIL-38999, etc.)
- **Enclosure:** 450×250×100mm aluminum instrument case (olive green powder coat, brushed aluminium front panel, 2× chrome D-ring carry handles top-mounted)
- **MUX control:** 34 direct GPIO enable lines + 4 shared address lines (no I2C expanders)
- **Resistance front-end:** XTR111AIDGQR (V-to-I converter, 0–20mA) + DAC8411AIDCKR (16-bit SPI DAC) + INA826AIDGKR (InAmp, G=495 or G=11 switchable) + ADS131M04IPBSR (24-bit 4-ch ADC)
- **Pin mapping ADC:** 2× ADS8688AIDBT (16-bit 8-ch simultaneous, reads 16 LO_MUX COM lines in parallel)
- **Mode switch:** TMUX1101DCKT SPDT analog switch (selects pin-mapping vs resistance-measurement path)
- **ADC:** ADS8688AIDBT (16-bit, pin mapping) + ADS131M04IPBSR (24-bit, resistance measurement)
- **SPI1 bus (shared):** ADS8688_U1, ADS8688_U2, ADS131M04, DAC8411 — all on SPI1, individual CS lines
- **HV module:** EMCO CA05N-5 (5V→0–500V DC, 1mA max, VCTRL×100=Vout)
- **HV safety:** ISOM8110 digital isolator (1.5kV galvanic isolation), firmware SafetyTask, PCB creepage
- **HV discharge:** Permanent 100kΩ/10W bleeder + firmware-controlled FET, confirmed discharge before any switching
- **Indicators:** 3× status LEDs (Red/Green/Yellow) + PWM buzzer (TIM1)
- **PC interface:** CH340G USB-UART bridge, 921600 baud, 8N1
- **2-card PCB architecture: Card 1 (Pin Mapping + Resistance), Card 2 (HV Insulation)**

### Firmware (STM32G474RET6 — C, FreeRTOS)

- **4 FreeRTOS tasks:** SafetyTask (priority 4), CommTask (priority 3), MeasureTask (priority 2), LEDTask (priority 1)
- **MUX control:** 34 direct GPIO enable lines + 4 shared address lines (PC[4:7] = S0–S3 shared to all 34 MUX chips)
- **Continuity scan:** Full 256-pin map in ~29ms using parallel dual-ADS8688 (16 channels read simultaneously)
- **Kelvin resistance:** XTR111 current source (10mA) controlled by 16-bit DAC8411; 24-bit ADS131M04 reads INA826 (G=495/11 switchable); 1mΩ resolution after MUX calibration
- **Short circuit scan:** Full matrix scan compared against uploaded netlist; unexpected connections flagged
- **HV insulation test:** Controlled voltage ramp (50V/step), programmable soak time (200–10,000ms), leakage current measurement via R4 (1kΩ current sense), safe discharge sequence
- **UART protocol:** Binary packet format `[SOF | CMD | LEN | PAYLOAD | CRC16]`, 10 commands, 8 response types
- **Netlist storage:** Uploaded JSON netlist stored in RAM; firmware compares every result against expected pairs
- **Flash calibration:** Calibration offset saved to last Flash page (`0x0807F800`), survives power cycle
- **Watchdog:** IWDG with 2-second timeout fed by CommTask and MeasureTask
- **Safety enforcement:** HV_ENABLE signal passes through ISOM8110 digital isolator — HV is OFF by default on any fault or reset

### PC Software (Python + PyQt6)

- **Real-time matrix view:** 16×16 grid showing per-pin status (grey/green/red/yellow) updated live during scan
- **Results table:** Sortable, filterable, color-coded; columns include pin names, resistance (mΩ), IR (MΩ), status
- **Netlist manager:** Load/validate/edit JSON netlists; create new netlists via built-in editor
- **Golden sample mode:** Run a full scan on a known-good harness → auto-generate netlist JSON
- **Test profile management:** Save/load COM port, thresholds, netlist path, operator name as JSON profiles
- **Reporting:** Auto-save CSV after every test; on-demand PDF report with cover page, matrix heatmap, full results table
- **Test engine state machine:** IDLE → UPLOADING → CALIBRATING → SCANNING → HV_TESTING → COMPLETE / FAULT
- **Fault handling:** Modal non-dismissible alert on any HV fault; CMD_ABORT sent immediately
- **Connection management:** Auto-detect CH340G/CP2102 COM port; heartbeat PING every 2 seconds; auto-reconnect
- **Dark / light theme:** Switchable via View menu (dark_theme.qss)
- **Standalone executable:** Packaged with PyInstaller
