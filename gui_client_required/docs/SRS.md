# Software Requirements Specification (SRS)
## Harness Tester System

**Document ID:** SRS-001
**Version:** 1.0
**Date:** 2026-03-12
**Project:** STM32G474-Based Wire Harness Tester
**Status:** Approved

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Overall Description](#2-overall-description)
3. [Firmware Requirements (STM32G474)](#3-firmware-requirements-stm32g474)
4. [PC Software Requirements (Python/PyQt6)](#4-pc-software-requirements-pythonpyqt6)
5. [Communication Protocol Requirements](#5-communication-protocol-requirements)
6. [Performance Requirements](#6-performance-requirements)
7. [Safety Requirements](#7-safety-requirements)
8. [Non-Functional Requirements](#8-non-functional-requirements)
9. [Hardware Interface Requirements](#9-hardware-interface-requirements)
10. [Constraints and Assumptions](#10-constraints-and-assumptions)
11. [Requirement Traceability Matrix](#11-requirement-traceability-matrix)

---

## 1. Introduction

### 1.1 Purpose

This Software Requirements Specification (SRS) defines the complete functional, performance, safety, and interface requirements for the Harness Tester system software, covering:
- **Embedded Firmware** running on the STM32G474RE microcontroller
- **PC Application** running on a Windows/Linux PC (Python + PyQt6)

### 1.2 Scope

The Harness Tester system automatically tests wire harnesses and cable assemblies by performing:
- Electrical continuity verification
- Wire resistance measurement (milliohm resolution)
- Short circuit detection
- High-voltage insulation resistance testing (up to 500V DC)

The system supports up to **256 test pins** and compares measured connectivity against a user-defined netlist to produce pass/fail results and test reports.

### 1.3 Definitions, Acronyms, and Abbreviations

| Term | Definition |
|---|---|
| DUT | Device Under Test — the wire harness being tested |
| MCU | Microcontroller Unit — STM32G474RE |
| MUX | Multiplexer — CD74HC4067 analog switch IC |
| VCCS | Voltage-Controlled Current Source |
| IR | Insulation Resistance (measured in MΩ) |
| HV | High Voltage (in this context: up to 500V DC) |
| Netlist | JSON file defining expected electrical connections in the DUT |
| Kelvin | 4-wire measurement method eliminating lead resistance |
| RTOS | Real-Time Operating System (FreeRTOS) |
| SWD | Serial Wire Debug (STM32 debug interface) |
| CRC | Cyclic Redundancy Check (CRC-16/CCITT-FALSE) |
| DMA | Direct Memory Access |
| ADC | Analog-to-Digital Converter |
| DAC | Digital-to-Analog Converter |
| OPAMP | Operational Amplifier (STM32G474 built-in) |
| GUI | Graphical User Interface |
| CSV | Comma-Separated Values |
| PDF | Portable Document Format |
| BOM | Bill of Materials |
| FMEA | Failure Mode and Effects Analysis |
| SOF | Start of Frame byte (0xAA in UART protocol) |

### 1.4 References

| Ref | Document |
|---|---|
| [HBD-001] | Hardware Block Diagram — Harness Tester |
| [SBD-001] | System Block Diagram — Harness Tester |
| IEC 61010-1 | Safety requirements for electrical equipment for measurement |
| ISO 6722 | Road vehicles — cables |
| LV216 | BMW Group standard for HV cable testing |
| STM32G474 Ref Manual | RM0440 — STMicroelectronics |
| FreeRTOS Docs | FreeRTOS V10.x reference |

### 1.5 Overview

- Section 3: Firmware requirements (embedded C, FreeRTOS, STM32 HAL)
- Section 4: PC software requirements (Python, PyQt6)
- Section 5: Communication protocol between firmware and PC software
- Sections 6–9: Cross-cutting requirements (performance, safety, HW interface)

---

## 2. Overall Description

### 2.1 Product Perspective

```
┌────────────────────────────────────────────────────────────┐
│                    SYSTEM CONTEXT                           │
│                                                            │
│   Operator ──► PC Application ──► (USB/UART) ──► Firmware │
│                     │                               │      │
│                     │                          Matrix MUX  │
│                     │                               │      │
│                 [Reports]                        [DUT]     │
│                                                            │
│   The PC software is the primary user interface.           │
│   The firmware is the measurement engine.                  │
│   Both must implement the same communication protocol.     │
└────────────────────────────────────────────────────────────┘
```

### 2.2 Product Functions Summary

| # | Function | Implemented In |
|---|---|---|
| F1 | Continuity test (open/close detection per pin pair) | Firmware + PC |
| F2 | Resistance measurement (milliohm, 4-wire Kelvin) | Firmware + PC |
| F3 | Short circuit detection (unexpected connections) | Firmware + PC |
| F4 | Insulation resistance test (500V DC, report in MΩ) | Firmware + PC |
| F5 | Netlist-driven pass/fail comparison | Firmware + PC |
| F6 | Golden sample learning mode | PC Software |
| F7 | Test report generation (CSV + PDF) | PC Software |
| F8 | Test profile management (save/load settings) | PC Software |
| F9 | Real-time pin matrix visualization | PC Software |
| F10 | UART packet communication with CRC | Firmware + PC |
| F11 | HV safety interlock enforcement | Firmware (primary) |
| F12 | Self-calibration (offset compensation) | Firmware + PC |
| F13 | Firmware version reporting and mismatch warning | Firmware + PC |

### 2.3 User Classes

| User Class | Description | Primary Interface |
|---|---|---|
| Test Operator | Performs daily harness testing on production floor | PC Application GUI |
| Test Engineer | Creates/modifies netlists, configures test profiles | PC Application (advanced) |
| Maintenance Engineer | Calibrates system, reviews diagnostics | PC Application + SWD debug |
| Administrator | Manages test records, exports reports | PC Application |

### 2.4 Operating Environment

| Component | Environment |
|---|---|
| Firmware | STM32G474RE, 170MHz, 128KB SRAM, 512KB Flash, FreeRTOS V10 |
| PC OS | Windows 10/11 (primary), Ubuntu 22.04 LTS (secondary) |
| PC Python | Python 3.10 or later |
| PC GUI | PyQt6 (Qt 6.4 or later) |
| Serial | pyserial 3.5 or later |
| PDF | reportlab 3.6 or later |
| Toolchain | STM32CubeIDE / ARM GCC 12 + CMake, OR STM32CubeMX + Keil MDK |

---

## 3. Firmware Requirements (STM32G474)

### 3.1 System Initialization Requirements

**FW-SYS-001**
The firmware shall initialize all peripherals (GPIO, USART2, I2C1, ADC1, ADC2, DAC1, OPAMP1, TIM1, DMA) within 500ms of power-on reset.

**FW-SYS-002**
The firmware shall run a self-test on startup that verifies:
- I2C communication with both MCP23017 expanders
- DAC output range (verify output with ADC feedback)
- UART loopback echo at 921600 baud
- OPAMP1 functional check

**FW-SYS-003**
The firmware shall report the self-test result to the PC via `RSP_STATUS` within 2 seconds of power-on.

**FW-SYS-004**
The firmware shall include a firmware version number (major.minor.patch) and report it in `RSP_STATUS` payload. Format: 3 bytes (e.g., 0x01 0x00 0x00 = v1.0.0).

**FW-SYS-005**
The firmware shall support the IWDG (Independent Watchdog) with a timeout of 2 seconds. The watchdog shall be fed by the CommTask on each received valid packet and by MeasureTask on each completed measurement cycle.

### 3.2 FreeRTOS Task Requirements

**FW-RTOS-001**
The firmware shall implement four FreeRTOS tasks with the following priorities:

| Task | Priority | Min Stack |
|---|---|---|
| SafetyTask | 4 (Highest) | 256 words |
| CommTask | 3 | 512 words |
| MeasureTask | 2 | 1024 words |
| LEDTask | 1 (Lowest) | 128 words |

**FW-RTOS-002**
`configCHECK_FOR_STACK_OVERFLOW` shall be set to 2 in FreeRTOS configuration. A stack overflow shall trigger a system fault and send `RSP_FAULT` before halting.

**FW-RTOS-003**
Inter-task communication shall use FreeRTOS primitives exclusively:
- `xCmdQueue` (depth 8): CommTask → MeasureTask
- `xResultQueue` (depth 64): MeasureTask → CommTask
- `xSafetyEventGroup`: SafetyTask broadcasts fault bits
- `xHVSemaphore` (binary): SafetyTask controls HV permission
- `xMeasureMutex`: serializes ADC/DAC access

**FW-RTOS-004**
No task shall use `vTaskDelay` inside a critical measurement loop. Timing delays during measurement shall use hardware timers (TIM6/TIM7) or DWT cycle counter.

### 3.3 Matrix Control Requirements

**FW-MX-001**
The firmware shall implement a `selectMUX(bus, pin)` function that:
- Accepts `bus` as HI_BUS or LO_BUS and `pin` as 0–255
- Sets MUX address lines A[3:0] = pin % 16 via GPIO PB[3:0]
- Enables exactly one chip via MCP23017 I2C write (chip = pin / 16)
- Completes within 50µs (including I2C transaction at 400kHz)

**FW-MX-002**
The firmware shall implement `deselectAllMUX()` that disables all 32 CD74HC4067 chips by writing 0x00 to both MCP23017 output ports. This shall be called as the first operation in any test sequence and as the last operation after any test.

**FW-MX-003**
The firmware shall enforce that only ONE HI bus chip and ONE LO bus chip are active simultaneously. Enabling more than one chip on the same bus is a firmware error and shall trigger `RSP_FAULT`.

**FW-MX-004**
The firmware shall implement a `scanAllPairs()` function that iterates all N×(N-1)/2 unique pin pairs (for N=256: 32,640 pairs) in ascending order and calls the registered measurement callback for each pair.

**FW-MX-005**
The MUX settle time between selecting a new pin and reading the ADC shall be at least 10µs to allow RC settling on capacitive loads up to 10nF.

### 3.4 Continuity Test Requirements

**FW-CT-001**
The continuity test shall drive the HI bus pin with 3.3V through a 10kΩ series resistor and measure the resulting voltage on the LO bus pin via ADC1.

**FW-CT-002**
A pin pair shall be classified as CONNECTED if the ADC reading corresponds to a voltage greater than `CONT_THRESH_MV` (default: 2500mV, configurable via CMD_SET_PARAM).

**FW-CT-003**
A pin pair shall be classified as OPEN if the ADC reading corresponds to a voltage less than `OPEN_THRESH_MV` (default: 500mV, configurable).

**FW-CT-004**
The firmware shall complete the full 256-pin continuity scan (32,640 pairs) within 1 second (target: 330ms).

**FW-CT-005**
For each detected connection, the firmware shall send `RSP_RESULT_CONT` containing: pin_a (1B), pin_b (1B), status (1B: CONNECTED/OPEN/UNEXPECTED_SHORT), voltage_mV (2B LE).

**FW-CT-006**
If a netlist has been uploaded (via CMD_SET_NETLIST), the firmware shall compare each result against the expected netlist and set the status byte accordingly:
- `PASS`: connection matches netlist expectation
- `OPEN_FAULT`: expected connection not found
- `SHORT_FAULT`: connection found but not in netlist

**FW-CT-007**
The firmware shall send `RSP_PROGRESS` every 256 pairs (approximately every ~2.5ms) during scanning.

**FW-CT-008**
The firmware shall send `RSP_SCAN_DONE` after all pairs have been tested, containing: total pairs tested (2B), pass count (2B), fail count (2B).

### 3.5 Resistance Measurement Requirements

**FW-RM-001**
The resistance measurement shall use the 4-wire Kelvin method with:
- Force current of 10mA generated by OPAMP1 VCCS driven by DAC1_CH1
- Sense voltage measured by INA826 (G=100) connected to ADC1_IN1
- Hardware 16x oversampling enabled on ADC1 for effective 16-bit resolution

**FW-RM-002**
The current source shall be stable within ±1% of the setpoint (10mA) within 2ms of DAC output change.

**FW-RM-003**
The firmware shall take 64 consecutive ADC samples and average them for each resistance measurement to reduce noise.

**FW-RM-004**
The firmware shall compute resistance as:
```
R_dut = (ADC_average / 4096.0 * V_REF / INA_GAIN) / I_force - CAL_OFFSET
```
where:
- `V_REF` = 3.3V (REF3033)
- `INA_GAIN` = 100
- `I_force` = DAC_CH1_voltage / 10.0 (R_sense = 10Ω)
- `CAL_OFFSET` = stored calibration offset in mΩ

**FW-RM-005**
The firmware shall report resistance in milliohms (integer, 4 bytes) in `RSP_RESULT_CONT` payload.

**FW-RM-006**
The resistance measurement range shall be 0 to 330,000 mΩ (330Ω). Values outside this range shall be reported as OVERFLOW (0xFFFFFFFF).

**FW-RM-007**
The firmware shall support a calibration command (CMD_CALIBRATE) that:
1. Selects a dedicated calibration shorting pin pair (hardwired on PCB)
2. Performs 10 resistance measurements
3. Averages the results
4. Stores the result as `CAL_OFFSET` in internal Flash (page reserved for calibration data)
5. Returns the calibration offset value in RSP_ACK payload

**FW-RM-008**
The current source (OPAMP1/DAC) shall be turned OFF (DAC output = 0V) between measurements. The current source shall never be left active with no DUT connected.

### 3.6 Short Circuit Detection Requirements

**FW-SC-001**
Short circuit detection shall use the fast GPIO voltage scan (same as continuity, see FW-CT-001) rather than the current source, for maximum scan speed.

**FW-SC-002**
A "short circuit" shall be defined as: a CONNECTED result between any two pins that are NOT listed as connected in the uploaded netlist.

**FW-SC-003**
If no netlist has been uploaded, `CMD_START_SHORT` shall return `RSP_NACK` with error code `ERR_NO_NETLIST`.

**FW-SC-004**
The firmware shall send `RSP_RESULT_SHORT` for each detected short, containing: pin_a (1B), pin_b (1B), measured_voltage_mV (2B).

**FW-SC-005**
The short circuit scan shall complete within 1 second for 256 pins.

### 3.7 High-Voltage Insulation Test Requirements

**FW-HV-001**
The HV insulation test shall ONLY begin if ALL of the following conditions are true:
1. Lid interlock switch is CLOSED (PC2 = LOW, pulled high)
2. HV rail voltage (ADC reading) is below 10V (confirmed discharged)
3. `xHVSemaphore` is successfully acquired from SafetyTask
4. All MUX chips are disabled (`deselectAllMUX()` confirmed)
5. The requested HV voltage is within the range 0–500V

**FW-HV-002**
The HV voltage shall be ramped from 0V to the target voltage in steps of maximum 50V per step, with a 100ms delay between steps. Abrupt voltage application is prohibited.

**FW-HV-003**
During HV ramp and soak, the firmware shall monitor the HV rail voltage every 50ms via ADC. If the measured voltage exceeds the setpoint by more than 30V, the firmware shall immediately invoke the HV fault shutdown sequence.

**FW-HV-004**
The soak time (duration of HV application) shall be configurable via CMD_SET_PARAM. The default soak time shall be 1000ms. The minimum soak time shall be 200ms. The maximum soak time shall be 10,000ms.

**FW-HV-005**
The insulation resistance shall be calculated as:
```
IR_MOhm = V_test / (I_leak_uA / 1,000,000)
```
where `I_leak_uA` is derived from the voltage across the 1MΩ series measurement resistor.

**FW-HV-006**
The HV discharge sequence shall be:
1. Set DAC1_CH2 = 0V (HV module set to 0V output)
2. Deassert HV_ENABLE (PC0 = LOW)
3. Assert HV_DISCHARGE (PC1 = HIGH) to activate bleeder FET
4. Poll HV rail ADC until voltage < 10V OR timeout of 2 seconds
5. Deassert HV_DISCHARGE (PC1 = LOW)
6. Release `xHVSemaphore`

**FW-HV-007**
If the HV discharge fails to reach below 10V within 2 seconds, the firmware shall:
- Maintain HV_DISCHARGE active
- Send RSP_FAULT with code FAULT_HV_DISCHARGE_FAIL
- Enter FAULT state (refuse all further commands until reset)

**FW-HV-008**
The firmware shall send `RSP_RESULT_HV` containing: pin_a (1B), pin_b (1B), IR_MOhm (4B LE), V_test (2B LE), I_leak_nA (4B LE), status (1B: PASS/FAIL/FAULT).

### 3.8 Safety Task Requirements

**FW-SF-001**
SafetyTask shall run at FreeRTOS priority 4 (highest application priority) and shall never block for more than 5ms.

**FW-SF-002**
SafetyTask shall monitor the lid interlock input (PC2) via EXTI interrupt. Any transition from CLOSED to OPEN (rising edge) shall immediately:
1. Write HV_ENABLE = LOW (GPIO direct write, not via task queue)
2. Write HV_DISCHARGE = HIGH
3. Set `FAULT_INTERLOCK` bit in `xSafetyEventGroup`
4. Activate buzzer via direct GPIO (not through LEDTask queue)

**FW-SF-003**
The HV_ENABLE GPIO shall be configured as open-drain output with a pull-down resistor so that in the event of MCU lockup or power loss to the GPIO, HV is disabled by default.

**FW-SF-004**
SafetyTask shall poll the HV rail ADC (via `xMeasureMutex`) every 100ms during HV test mode. If the HV rail exceeds `HV_SETPOINT + 30V`, SafetyTask shall immediately trigger HV fault shutdown without waiting for MeasureTask.

**FW-SF-005**
After a HV fault event, the firmware shall refuse CMD_START_HV until:
- The fault has been acknowledged by the PC (CMD_ABORT received)
- The HV rail has been confirmed below 10V for at least 500ms

**FW-SF-006**
The IWDG shall be configured to generate a reset if not serviced within 2 seconds. Only CommTask and MeasureTask shall service the IWDG.

### 3.9 LED and Buzzer Requirements

**FW-LED-001**
LED and buzzer states shall be defined as follows:

| State | LED_GREEN | LED_RED | LED_YELLOW | Buzzer |
|---|---|---|---|---|
| IDLE | Solid ON | OFF | OFF | OFF |
| SCANNING | Blink 1Hz | OFF | OFF | OFF |
| HV_ACTIVE | OFF | OFF | Solid ON | OFF |
| TEST_PASS | Blink 2×fast | OFF | OFF | 1 beep (200ms) |
| TEST_FAIL | OFF | Blink 2×fast | OFF | 3 beeps (100ms each) |
| HV_FAULT | OFF | Solid ON | OFF | Continuous 2.5kHz |
| CALIBRATING | OFF | OFF | Blink 2Hz | OFF |
| STARTUP_OK | Blink 3× | Blink 3× | Blink 3× | 1 beep |

**FW-LED-002**
Buzzer output shall use PWM (TIM1_CH1) at 2500Hz for alerts and 1000Hz for status notifications.

---

## 4. PC Software Requirements (Python/PyQt6)

### 4.1 Application Startup Requirements

**PC-APP-001**
The application shall launch and display the main window within 3 seconds of execution on a standard PC (i5 class, 8GB RAM, SSD).

**PC-APP-002**
On startup, the application shall:
1. Load the last-used test profile (or "Default" if none exists)
2. Auto-scan available COM ports and highlight any that match CH340G or CP2102 VID/PID
3. Display connection status as "DISCONNECTED" until a valid COM port is selected and opened

**PC-APP-003**
The application shall remember the last used COM port, baud rate, netlist path, and window size/position across sessions (stored in `profiles/app_settings.json`).

### 4.2 Main Window Requirements

**PC-UI-001**
The main window shall contain the following panels:
1. **Left Panel**: Netlist Explorer (file tree), Test Profile settings, Test Mode selector, START/STOP buttons
2. **Center Panel**: Tabbed view with three tabs: "Matrix View", "Results Table", "Log"
3. **Status Bar**: COM port status, baud rate, PASS count, FAIL count, elapsed time

**PC-UI-002**
The Matrix View tab shall display a 16×16 grid of colored circles representing pins 0–255:
- Grey: Not yet tested
- Green: PASS (all tests passed for this pin)
- Red: FAIL (at least one failure involving this pin)
- Yellow: IN PROGRESS (currently being tested)
- Orange: HV test result available (hover to see IR value)

**PC-UI-003**
The Matrix View shall update in real time during scanning. Each pin circle shall update within 200ms of the result being received.

**PC-UI-004**
Clicking a pin circle in the Matrix View shall open a tooltip or detail popup showing all test results involving that pin (all pairs, resistances, IR values).

**PC-UI-005**
The Results Table shall have the following columns:
- Test # (sequential)
- Pin A (number)
- Pin A Name (from netlist)
- Pin B (number)
- Pin B Name (from netlist)
- Net Name (from netlist)
- Test Type (Continuity / Resistance / Short / HV)
- Resistance (mΩ) or N/A
- IR (MΩ) or N/A
- HV Voltage (V) or N/A
- Status (PASS / OPEN / SHORT / HV_FAIL)
- Timestamp

**PC-UI-006**
The Results Table shall support:
- Column sorting by clicking headers
- Filtering by status (PASS/FAIL/ALL)
- Row highlighting (red for FAIL, green for PASS)
- Copy selected rows to clipboard as CSV

**PC-UI-007**
The START button shall be disabled unless:
- A COM port is open and firmware is responding to PING
- A netlist is loaded (or Golden Sample mode is selected)
- No test is currently running

**PC-UI-008**
The STOP button shall send CMD_ABORT and wait up to 3 seconds for RSP_ACK before closing the port. During HV test, a confirmation dialog shall be shown: "WARNING: Stopping during HV test will trigger discharge sequence. Confirm?"

**PC-UI-009**
A progress bar shall be displayed during scanning showing percentage complete and an estimated time to completion based on current scan rate.

**PC-UI-010**
The application shall support a dark theme (dark_theme.qss) and a light theme. Theme selection shall be accessible from the View menu.

### 4.3 Netlist Management Requirements

**PC-NL-001**
The application shall load and validate JSON netlist files conforming to the netlist schema defined in `docs/netlist_format.md`. Invalid netlists shall produce a clear error message specifying the validation error and line.

**PC-NL-002**
Netlist validation shall check:
- All `pins` values are integers in range 0–255
- No pin appears in more than one `net` (duplicate pin error)
- No net has fewer than 2 pins
- Resistance limits: `min` < `max`, both non-negative
- `hv_test_voltage_V` is in range 10–500V if `insulation_test` is true
- `hv_min_IR_MOhm` is a positive value if `insulation_test` is true

**PC-NL-003**
The application shall display the loaded netlist in the Left Panel Netlist Explorer as a tree:
```
▶ NET: GROUND (4 pins)
  ├─ Pin 1 — GND
  ├─ Pin 15 — GND_RTN
  ├─ Pin 32 — CHASSIS
  └─ Pin 67 — SHIELD
▶ NET: CAN_BUS (2 pins)
  ├─ Pin 3 — CAN_H
  └─ Pin 4 — CAN_L
```

**PC-NL-004**
The application shall support a **Netlist Editor** accessible from the Tools menu, allowing the user to:
- Add/remove nets
- Add/remove pins from nets
- Assign pin names
- Set resistance limits and HV test parameters per net
- Save the modified netlist as a new file

**PC-NL-005**
The application shall support **Golden Sample Learning Mode**:
1. User selects "Learn from Golden Sample" from the Tools menu
2. Application displays warning: "Install the known-good reference harness. All current connections will be recorded as the expected netlist."
3. Application sends CMD_START_CONTINUITY (all pairs mode)
4. All CONNECTED pairs are recorded
5. Application presents a confirmation dialog showing the discovered connections
6. User can rename nets, exclude individual pairs, and assign names
7. User saves the result as a new netlist JSON file

**PC-NL-006**
The application shall detect when no netlist is loaded and offer the user the option to run a "Discovery Scan" (continuity only, no pass/fail, just map all connections) before loading or creating a netlist.

### 4.4 Serial Communication Requirements

**PC-COM-001**
The `serial_comm.py` module shall implement the UART packet protocol defined in Section 5 using `pyserial`.

**PC-COM-002**
Serial port reading shall be performed in a dedicated background `QThread` (not the main GUI thread) to prevent GUI freezing.

**PC-COM-003**
The communication module shall emit the following Qt signals:
- `packetReceived(cmd: int, payload: bytes)` — valid packet received
- `connectionLost()` — COM port disconnected unexpectedly
- `faultReceived(fault_code: int)` — RSP_FAULT packet received
- `progressUpdate(done: int, total: int)` — RSP_PROGRESS received
- `scanComplete(TestSummary)` — RSP_SCAN_DONE received

**PC-COM-004**
The communication module shall verify CRC-16/CCITT-FALSE on every received packet. Packets with CRC mismatch shall be discarded and logged. Three consecutive CRC errors shall trigger `connectionLost()`.

**PC-COM-005**
The communication module shall implement a command timeout of 5 seconds. If no response is received within 5 seconds of sending a command, the command shall be retried once. If the retry also times out, `connectionLost()` shall be emitted.

**PC-COM-006**
The application shall send CMD_PING every 2 seconds when connected and idle. If three consecutive PINGs receive no RSP_ACK, `connectionLost()` shall be emitted.

**PC-COM-007**
The application shall display the connection status in the status bar:
- "DISCONNECTED" — no COM port open
- "CONNECTING..." — COM port open, waiting for RSP_STATUS
- "CONNECTED — FW v1.0.0" — firmware responded with version
- "FAULT — HV Interlock Open" — RSP_FAULT received

### 4.5 Test Engine Requirements

**PC-TE-001**
The test engine shall implement a state machine with the following states:

```
IDLE ──► UPLOADING_NETLIST ──► CALIBRATING ──► SCANNING ──► HV_TESTING ──► COMPLETE
  │                                                │                            │
  │◄───────────────────────────────────────────────┴────────────────────────────┘
  │
  └──► FAULT (from any state on RSP_FAULT received)
         │
         └──► IDLE (after user acknowledges fault)
```

**PC-TE-002**
The test engine shall execute tests in the following order when "Run All" is selected:
1. Upload netlist (CMD_SET_NETLIST)
2. Run calibration (CMD_CALIBRATE)
3. Run continuity scan (CMD_START_CONTINUITY)
4. Run resistance measurement for all connected pairs (CMD_START_RESISTANCE per pair)
5. Run short circuit scan (CMD_START_SHORT)
6. Run HV insulation test for nets marked `insulation_test: true` (CMD_START_HV per net)

**PC-TE-003**
The test engine shall allow the user to select individual test modes (e.g., continuity only, resistance only) from the Left Panel.

**PC-TE-004**
On receipt of RSP_FAULT at any point, the test engine shall:
1. Immediately transition to FAULT state
2. Display a modal dialog with the fault description (non-closeable until acknowledged)
3. Log the fault event with timestamp
4. Send CMD_ABORT to the firmware

**PC-TE-005**
The test engine shall build a `TestResult` object for each received result packet and append it to the `ResultModel` (Qt data model). This shall trigger automatic update of the Results Table and Matrix View.

**PC-TE-006**
After all tests complete, the test engine shall compute the overall verdict:
- **PASS**: All expected connections found, no unexpected shorts, all resistance values within limits, all IR values above minimum
- **FAIL**: One or more failures in any category
- **INCONCLUSIVE**: Test was aborted before completion

**PC-TE-007**
The overall verdict (PASS/FAIL) shall be displayed in large text (minimum 48pt font) in a dedicated area of the main window, visible from 2 meters away.

### 4.6 Report Generation Requirements

**PC-RPT-001**
The application shall auto-save a CSV report after every completed test to the `reports/` directory with filename format: `report_YYYYMMDD_HHMMSS_<DUT_ID>.csv`.

**PC-RPT-002**
The CSV report shall include one row per tested pair with columns:
`Timestamp, DUT_ID, Operator, Pin_A, Pin_A_Name, Pin_B, Pin_B_Name, Net_Name, Test_Type, Resistance_mOhm, IR_MOhm, HV_Voltage_V, Status`

**PC-RPT-003**
The application shall generate a PDF report on user request (File → Export PDF) or optionally auto-generate after each test. The PDF shall include:
- **Page 1 — Cover**: DUT ID, test date/time, operator name, overall PASS/FAIL verdict (large), summary counts (pass, fail, total)
- **Page 2 — Matrix Heatmap**: Rendered image of the 16×16 pin matrix with color coding
- **Page 3+ — Full Results Table**: All tested pairs with measurements, sorted by status (FAIL first), highlighted red for failures
- **Footer**: Document number, revision, page X of Y

**PC-RPT-004**
PDF generation shall use `reportlab.platypus` (no external tools required). PDF generation shall complete within 10 seconds for a 256-pin full test result set.

**PC-RPT-005**
The application shall maintain a **test history log** (`reports/history.json`) recording: date, DUT_ID, overall result, CSV filename, PDF filename, operator name, firmware version. The last 1000 records shall be kept; older records shall be archived.

### 4.7 Test Profile Requirements

**PC-TP-001**
A test profile shall store:
- COM port name and baud rate
- Selected test modes (bitfield: continuity, resistance, short, HV)
- Threshold overrides (continuity limit mΩ, short threshold mV, HV soak time ms)
- Path to the active netlist file
- Operator name
- DUT serial number prefix (for auto-numbering)
- Auto-save PDF on/off

**PC-TP-002**
Test profiles shall be stored as JSON files in `profiles/` directory.

**PC-TP-003**
The application shall create a "Default" profile on first run with standard threshold values.

**PC-TP-004**
The user shall be able to create, duplicate, rename, and delete profiles from the Left Panel.

---

## 5. Communication Protocol Requirements

### 5.1 Physical Layer

**COMM-PHY-001**
Physical layer: USART2 on STM32G474RE at 921600 baud, 8 data bits, no parity, 1 stop bit (8N1).

**COMM-PHY-002**
Voltage levels: 3.3V CMOS logic. Direct connection from STM32 GPIO to CH340G/CP2102 RX/TX pins (both 3.3V tolerant). No level shifting required.

**COMM-PHY-003**
DMA shall be used for both UART TX and RX on the firmware side. RX shall use circular DMA with a 256-byte ring buffer. TX shall use double-buffered DMA.

### 5.2 Packet Structure

**COMM-PKT-001**
All packets shall conform to the following structure:

```
Byte 0:      SOF = 0xAA (Start of Frame)
Byte 1:      CMD/RSP = command or response code (1 byte)
Byte 2–3:    LEN = payload length in bytes, little-endian uint16
Byte 4..N:   PAYLOAD = LEN bytes of data
Byte N+1–2:  CRC16 = CRC-16/CCITT-FALSE over bytes 1..N (CMD+LEN+PAYLOAD), little-endian
```

**COMM-PKT-002**
CRC algorithm: CRC-16/CCITT-FALSE (polynomial 0x1021, initial value 0xFFFF, no input/output reflection).

**COMM-PKT-003**
Both firmware and PC software shall use identical CRC implementations. The `crc16.py` (PC) and `crc16.c` (firmware) modules shall produce identical results for all inputs.

**COMM-PKT-004**
The maximum payload size shall be 512 bytes. Larger data (e.g., netlist upload) shall be fragmented into multiple CMD_SET_NETLIST packets with a sequence number in the payload.

**COMM-PKT-005**
On receiving a packet with invalid CRC, the receiver shall:
- Firmware: Send RSP_NACK (error code ERR_CRC), reset RX state machine
- PC software: Log CRC error, increment error counter, attempt re-sync by scanning for next 0xAA byte

**COMM-PKT-006**
If no SOF byte (0xAA) is received within 200ms during active packet reception, the RX state machine shall reset to IDLE state.

### 5.3 Command Definitions

**COMM-CMD-001**
The following PC→MCU commands shall be implemented:

| CMD Byte | Name | Payload | Response |
|---|---|---|---|
| 0x01 | CMD_PING | None (0 bytes) | RSP_ACK |
| 0x10 | CMD_START_CONTINUITY | mode (1B): 0=all, 1=netlist | RSP_ACK, then stream of RSP_RESULT_CONT + RSP_SCAN_DONE |
| 0x11 | CMD_START_RESISTANCE | pin_a (1B), pin_b (1B) | RSP_ACK, then RSP_RESULT_CONT |
| 0x12 | CMD_START_SHORT | None | RSP_ACK, then stream of RSP_RESULT_SHORT + RSP_SCAN_DONE |
| 0x13 | CMD_START_HV | voltage_V (2B LE), soak_ms (2B LE), pin_a (1B), pin_b (1B) | RSP_ACK, then RSP_RESULT_HV |
| 0x20 | CMD_ABORT | None | RSP_ACK |
| 0x30 | CMD_SET_NETLIST | seq (1B), total_segs (1B), json_chunk (up to 510B) | RSP_ACK or RSP_NACK |
| 0x40 | CMD_GET_STATUS | None | RSP_STATUS |
| 0x50 | CMD_CALIBRATE | None | RSP_ACK (with cal_offset_mOhm 4B in payload) |
| 0x60 | CMD_SET_PARAM | param_id (1B), value (4B LE) | RSP_ACK or RSP_NACK |

**COMM-CMD-002**
CMD_SET_PARAM parameter IDs:

| param_id | Name | Default | Range |
|---|---|---|---|
| 0x01 | CONT_THRESH_MV | 2500 | 100–3200 |
| 0x02 | OPEN_THRESH_MV | 500 | 0–1000 |
| 0x03 | IFORCE_MA | 10 | 1–30 |
| 0x04 | HV_SOAK_MS | 1000 | 200–10000 |
| 0x05 | HV_MAX_LEAK_UA | 500 | 10–1000 |
| 0x06 | SHORT_THRESH_MV | 2500 | 100–3200 |

### 5.4 Response Definitions

**COMM-RSP-001**
The following MCU→PC responses shall be implemented:

| RSP Byte | Name | Payload |
|---|---|---|
| 0x80 | RSP_ACK | cmd_echo (1B) + optional data |
| 0x81 | RSP_NACK | cmd_echo (1B), error_code (1B) |
| 0x90 | RSP_RESULT_CONT | pin_a (1B), pin_b (1B), status (1B), voltage_mV (2B LE), resistance_mOhm (4B LE) |
| 0x91 | RSP_RESULT_SHORT | pin_a (1B), pin_b (1B), voltage_mV (2B LE) |
| 0x92 | RSP_RESULT_HV | pin_a (1B), pin_b (1B), IR_MOhm (4B LE), V_test (2B LE), I_leak_nA (4B LE), status (1B) |
| 0x9F | RSP_SCAN_DONE | total_pairs (2B LE), pass_count (2B LE), fail_count (2B LE) |
| 0xA0 | RSP_STATUS | state (1B), flags (1B), fw_major (1B), fw_minor (1B), fw_patch (1B), cal_offset_mOhm (4B LE) |
| 0xA1 | RSP_PROGRESS | pairs_done (2B LE), pairs_total (2B LE) |
| 0xFF | RSP_FAULT | fault_code (1B), fault_data (4B LE) |

**COMM-RSP-002**
RSP_FAULT fault codes:

| Code | Name | Description |
|---|---|---|
| 0x01 | FAULT_HV_INTERLOCK | Lid switch opened during HV test |
| 0x02 | FAULT_HV_OVERVOLT | HV rail exceeded setpoint + 30V |
| 0x03 | FAULT_HV_OVERCURRENT | Leakage current exceeded limit |
| 0x04 | FAULT_HV_DISCHARGE_FAIL | HV did not discharge within 2s |
| 0x05 | FAULT_MUX_COMM | I2C communication with MCP23017 failed |
| 0x06 | FAULT_ADC | ADC reading out of valid range |
| 0x07 | FAULT_STACK_OVERFLOW | FreeRTOS stack overflow detected |
| 0x08 | FAULT_WATCHDOG | Watchdog reset occurred |

---

## 6. Performance Requirements

**PERF-001**
Full continuity scan (256 pins, 32,640 pairs): complete within **1 second** (target: 330ms).

**PERF-002**
Single resistance measurement (one pin pair, 4-wire Kelvin): complete within **50ms** including ADC oversampling and current source settling.

**PERF-003**
Full short circuit scan (256 pins): complete within **1 second**.

**PERF-004**
Single HV insulation test (one pin pair, 500V, 1s soak): complete within **5 seconds** including ramp, soak, measurement, and discharge.

**PERF-005**
PC software GUI shall remain responsive (< 100ms response to user interaction) during active scanning.

**PERF-006**
Results table shall update in real time with latency < 200ms from result reception.

**PERF-007**
PDF report generation for a full 256-pin test session: complete within **10 seconds**.

**PERF-008**
PC application shall start and be ready for user interaction within **3 seconds**.

**PERF-009**
Firmware packet processing (receive command → begin execution): < 5ms.

**PERF-010**
Maximum UART transmission latency for a single result packet: < 1ms at 921600 baud.

---

## 7. Safety Requirements

**SAF-001 (CRITICAL)**
The firmware shall NEVER enable the HV module (HV_ENABLE = HIGH) unless the lid interlock input confirms the enclosure is closed. This check shall be performed in firmware immediately before each HV enable event. Software alone cannot override this; hardware interlock is required.

**SAF-002 (CRITICAL)**
The HV discharge sequence (FW-HV-006) shall always be executed after every HV test, whether the test completes normally, is aborted, or ends with a fault. The discharge shall not be skipped under any condition.

**SAF-003 (CRITICAL)**
The HV reed relays (connecting DUT pins to the HV rail) shall NEVER be energized simultaneously with the CD74HC4067 MUX chips connected to the same DUT pins. The firmware shall enforce `deselectAllMUX()` before energizing any HV relay, with a minimum 1ms gap.

**SAF-004**
The PC software shall display a non-dismissible warning modal when HV test mode is selected, requiring the user to confirm: "HIGH VOLTAGE TEST — Ensure safety enclosure is closed and no personnel are in contact with the DUT. Click CONFIRM to proceed."

**SAF-005**
The PC software shall display the HV test voltage prominently (yellow warning label) during HV test execution.

**SAF-006**
On receipt of RSP_FAULT with any FAULT_HV_* code, the PC software shall display a modal alert that cannot be dismissed until the user clicks an explicit acknowledgment button. The alert shall clearly state the fault type in plain language.

**SAF-007**
The STM32 HV_ENABLE GPIO (PC0) shall be configured as open-drain with an external pull-down resistor (10kΩ to GND), ensuring the HV module is disabled if the MCU is in reset, unpowered, or in any undefined state.

**SAF-008**
The firmware shall validate that the requested HV voltage is within the range 10–500V before enabling the HV module. A value of 0V or > 500V shall result in RSP_NACK.

**SAF-009**
The system enclosure shall include a physical mechanical interlock that prevents access to the DUT connectors when the HV relay section is energized. This is a hardware requirement but must be tested as part of system verification.

---

## 8. Non-Functional Requirements

### 8.1 Reliability

**NFR-REL-001**
The firmware shall achieve a mean time between failures (MTBF) of at least 10,000 operating hours. This shall be validated by extended stress testing at maximum scan rate.

**NFR-REL-002**
The system shall correctly identify a 100mΩ reference resistor with accuracy ±20mΩ (±20%) over a temperature range of 0°C to 50°C.

**NFR-REL-003**
The system shall produce zero false positives (reporting a connection as FAIL when the DUT is correct) in any mode. False negatives (missing a real fault) are to be minimized.

### 8.2 Maintainability

**NFR-MNT-001**
Firmware code shall follow MISRA-C:2012 advisory rules where practical. All safety-critical functions (SafetyTask, HV sequences) shall comply with MISRA-C:2012 mandatory rules.

**NFR-MNT-002**
All firmware source files shall include a file header with: filename, brief description, author, creation date, version, and change log.

**NFR-MNT-003**
PC software shall follow PEP 8 coding style. All public functions and classes shall have docstrings.

**NFR-MNT-004**
Firmware shall provide a method to update (reflash) without requiring specialized hardware beyond a CH340G/FTDI serial adapter — i.e., a UART bootloader shall be supported (STM32 built-in UART bootloader via BOOT0 pin).

### 8.3 Portability

**NFR-PORT-001**
PC software shall run on Windows 10/11 (x64) and Ubuntu 22.04 LTS without modification.

**NFR-PORT-002**
PC software shall be distributable as a standalone executable (via PyInstaller) that does not require Python installation on the target PC.

### 8.4 Usability

**NFR-USE-001**
A new test operator shall be able to load a netlist, connect to the device, and run a complete test within 5 minutes without reading the manual (intuitive workflow).

**NFR-USE-002**
All test failures shall be displayed in plain language (not error codes). Example: "Pin 3 (CAN_H) is NOT connected to Pin 4 (CAN_L) — expected connection MISSING."

**NFR-USE-003**
The PASS/FAIL verdict shall be visible from 2 meters distance (minimum 48pt font, high-contrast color).

### 8.5 Security

**NFR-SEC-001**
The firmware shall reject and discard any packet with a payload length exceeding 512 bytes to prevent buffer overflow attacks.

**NFR-SEC-002**
The PC software shall validate all JSON netlist inputs before sending to firmware to prevent injection of malformed commands.

---

## 9. Hardware Interface Requirements

**HW-INT-001**
The firmware shall use STM32 HAL (Hardware Abstraction Layer) drivers generated by STM32CubeMX for all peripheral initialization. LL (Low Level) drivers may be used for time-critical paths (ADC reads, GPIO toggles in measurement loops).

**HW-INT-002**
The INA826 shall be configured for a gain of 100 (RG = 499Ω). The firmware shall store the gain value as a compile-time constant `INA826_GAIN = 100.0f` in `config.h`.

**HW-INT-003**
The REF3033 voltage reference output shall be connected to the STM32 VREF+ pin. The firmware shall use `V_REF = 3.3f` in all ADC-to-voltage calculations in `config.h`.

**HW-INT-004**
I2C1 shall be configured for 400kHz (Fast Mode) for MCP23017 communication. The firmware shall implement I2C error recovery (bus reset via GPIO bit-banging) if the I2C peripheral returns a BUSY or NACK error.

**HW-INT-005**
ADC1 and ADC2 shall be configured for 12-bit resolution with hardware oversampling of 16× (shift 4 bits), yielding effective 16-bit resolution. Sampling time shall be 247.5 ADC clock cycles for accurate measurement of the INA826 output.

**HW-INT-006**
DAC1 Channel 1 (PA4) shall use an output buffer and a 100Ω + 100nF RC filter on the PCB to reduce DAC glitches.

**HW-INT-007**
The EMCO CA05-5 Vadj pin shall receive the DAC1_CH2 (PA5) output through the same RC filter (100Ω + 100nF).

---

## 10. Constraints and Assumptions

### 10.1 Constraints

**CON-001**
Firmware flash budget: 512KB total. Estimated usage: 128KB HAL drivers + 32KB FreeRTOS + 64KB application = 224KB total. Maximum 288KB available for future expansion.

**CON-002**
Firmware SRAM budget: 128KB total. Estimated usage: FreeRTOS stacks (12KB) + queues (4KB) + DMA buffers (2KB) + netlist storage (8KB for 256-pin netlist JSON) + application data (8KB) = 34KB total. Well within limits.

**CON-003**
The HV insulation test is limited to 500V DC maximum. Systems requiring higher voltages (e.g., EV HV battery cables at 800V) are NOT supported in v1.0.

**CON-004**
The CD74HC4067 MUX chips are rated for 3.3V supply with 70–200Ω on-resistance. This limits resistance measurement accuracy for DUT resistances below ~10mΩ (MUX Rds is a significant error source). Calibration mitigates but does not eliminate this.

**CON-005**
Maximum scan rate for resistance measurement: one measurement per 50ms = 20 measurements/second. A full 256-pin resistance scan (32,640 pairs) would take ~27 minutes. In practice, only netlist-specified pairs (typically < 1000) are measured for resistance.

### 10.2 Assumptions

**ASS-001**
The PC running the software has at least one available USB port and supports USB Full Speed (USB 2.0). USB 1.1 is not guaranteed to work at 921600 baud.

**ASS-002**
The DUT harness will not carry voltages above 30V DC when connected to the tester (Low Voltage mode). For HV mode, the DUT must be fully isolated from external power supplies before testing.

**ASS-003**
The operator is trained in basic electrical safety and understands the hazards of high voltage (500V DC can cause severe injury or death).

**ASS-004**
The system will be operated in an environment with ambient temperature 10°C to 40°C and relative humidity < 80% (non-condensing).

---

## 11. Requirement Traceability Matrix

| Req ID | Category | Phase | Priority | Verification Method |
|---|---|---|---|---|
| FW-SYS-001 | Firmware Init | Phase 1 | HIGH | Power-on test |
| FW-SYS-002 | Firmware Init | Phase 1 | HIGH | Startup log check |
| FW-SYS-004 | Firmware Init | Phase 5 | MED | PC software version display |
| FW-SYS-005 | Watchdog | Phase 2 | HIGH | Force stall MeasureTask, observe reset |
| FW-RTOS-001 | RTOS | Phase 1 | HIGH | Code review + FreeRTOS trace |
| FW-RTOS-002 | RTOS | Phase 1 | HIGH | Stack overflow stress test |
| FW-MX-001 | Matrix | Phase 1 | HIGH | Logic analyzer on I2C + GPIO |
| FW-MX-004 | Matrix | Phase 1 | HIGH | Scan 64 pins, count pairs |
| FW-CT-001 | Continuity | Phase 1 | HIGH | Connect jumper wire, verify detected |
| FW-CT-004 | Performance | Phase 1 | HIGH | Timer measurement on full scan |
| FW-CT-006 | Netlist | Phase 3 | HIGH | Load test netlist, check results |
| FW-RM-001 | Resistance | Phase 2 | HIGH | Oscilloscope on OPAMP output |
| FW-RM-004 | Resistance | Phase 2 | HIGH | Measure 100mΩ reference |
| FW-RM-007 | Calibration | Phase 2 | HIGH | Run CMD_CALIBRATE, measure reference |
| FW-SC-001 | Short | Phase 3 | HIGH | Short two pins, verify detected |
| FW-HV-001 | HV Safety | Phase 4 | CRITICAL | All preconditions individually defeated |
| FW-HV-002 | HV Safety | Phase 4 | CRITICAL | Oscilloscope on HV rail during ramp |
| FW-HV-006 | HV Safety | Phase 4 | CRITICAL | Oscilloscope on HV rail after test |
| FW-SF-001 | Safety | Phase 4 | CRITICAL | FreeRTOS profiler |
| FW-SF-002 | Safety | Phase 4 | CRITICAL | Open lid during HV, measure response time |
| FW-SF-003 | Safety | Phase 4 | CRITICAL | Remove MCU power during HV, verify off |
| PC-APP-001 | PC SW | Phase 1 | MED | Stopwatch on launch |
| PC-UI-002 | Matrix View | Phase 3 | MED | Visual inspection during scan |
| PC-UI-007 | Safety UI | Phase 4 | HIGH | UI state validation |
| PC-NL-001 | Netlist | Phase 2 | HIGH | Load valid + invalid netlists |
| PC-NL-005 | Golden Sample | Phase 3 | MED | Learn from reference harness |
| PC-COM-004 | Protocol | Phase 1 | HIGH | Inject corrupt packets, verify discard |
| PC-COM-006 | Heartbeat | Phase 1 | MED | Unplug cable, verify detection |
| PC-TE-004 | Fault Handling | Phase 4 | CRITICAL | Trigger HV fault, verify modal |
| PC-RPT-001 | Reporting | Phase 3 | MED | Run test, check reports/ directory |
| PC-RPT-003 | PDF | Phase 3 | MED | Generate PDF, review content |
| COMM-PKT-002 | Protocol | Phase 1 | HIGH | Software unit test (test_protocol.py) |
| PERF-001 | Performance | Phase 1 | HIGH | Measure scan time with timer |
| PERF-002 | Performance | Phase 2 | HIGH | Measure single R measurement time |
| PERF-004 | Performance | Phase 4 | MED | Time full HV test cycle |
| SAF-001 | Safety | Phase 4 | CRITICAL | HV attempt with lid open |
| SAF-002 | Safety | Phase 4 | CRITICAL | Abort during HV, verify discharge |
| SAF-003 | Safety | Phase 4 | CRITICAL | Code review + logic analyzer |
| SAF-007 | Safety | Phase 4 | CRITICAL | Remove MCU VDD, verify HV disabled |

---

*End of SRS Document*
*Document ID: SRS-001 | Version 1.0 | 2026-03-12*
