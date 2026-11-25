# GUI Development Plan
## Harness Tester — PC Software (PyQt6)

**Document ID:** GUI-PLAN-001
**Version:** 1.0
**Date:** 2026-04-21
**Parent Documents:** GUI-REQ-001, SRS-001
**Status:** Draft

---

## Table of Contents

1. [Overview](#1-overview)
2. [Phases Summary](#2-phases-summary)
3. [Phase 1 — Skeleton and Serial Foundation](#3-phase-1--skeleton-and-serial-foundation)
4. [Phase 2 — Core UI Panels](#4-phase-2--core-ui-panels)
5. [Phase 3 — Test Engine and Live Data](#5-phase-3--test-engine-and-live-data)
6. [Phase 4 — Reporting and Profiles](#6-phase-4--reporting-and-profiles)
7. [Phase 5 — Safety Dialogs and HV Workflow](#7-phase-5--safety-dialogs-and-hv-workflow)
8. [Phase 6 — Polish and Packaging](#8-phase-6--polish-and-packaging)
9. [Module Dependency Map](#9-module-dependency-map)
10. [Testing Strategy](#10-testing-strategy)
11. [Risk Register](#11-risk-register)
12. [Done Criteria](#12-done-criteria)

---

## 1. Overview

The GUI is a PyQt6 desktop application that communicates with the Harness Tester firmware over UART (USB-serial). It is the **only user interface** for the tester — the firmware has no local display.

Development is organised into six sequential phases. Each phase produces working, runnable software; no phase leaves the application in a broken state. A firmware simulator is built in Phase 1 so that GUI development does not depend on hardware availability.

### Key Constraints

- GUI thread must never block (all serial I/O on QThread).
- Safety-critical dialogs (HV confirm, fault alert) are non-dismissible by design.
- The application must package as a single executable via PyInstaller.
- Target platforms: Windows 10/11 (primary), Ubuntu 22.04 (secondary).

---

## 2. Phases Summary

| Phase | Focus | Deliverable |
|---|---|---|
| 1 | Project scaffold, serial layer, firmware simulator | Runnable shell + serial comms |
| 2 | Core UI — left panel, matrix, results table, log | Full layout, no live data |
| 3 | Test engine state machine, live data integration | End-to-end continuity + resistance scan |
| 4 | Reporting (CSV / PDF), profiles, netlist editor | Persistent data, reports |
| 5 | HV workflow, fault dialogs, Golden Sample wizard | Full safety flow |
| 6 | Theming, packaging, performance, final testing | Shippable executable |

---

## 3. Phase 1 — Skeleton and Serial Foundation

**Goal:** A runnable application window with a working serial communication layer. No firmware hardware required — a simulator provides test data.

### 3.1 Tasks

#### 1.1 — Project Setup

- Create directory structure as defined in GUI-REQ-001 Section 2.1.
- Create `requirements.txt`: PyQt6, pyserial, reportlab, pytest, pytest-qt.
- Create `main.py` entry point that instantiates `QApplication` and shows a placeholder `MainWindow`.
- Set up `venv` and install dependencies.
- Add `.gitignore` for `venv/`, `__pycache__/`, `reports/`, `profiles/`.

#### 1.2 — CRC Module

- Implement `core/crc16.py`: `crc16_ccitt_false(data: bytes) -> int`.
- Polynomial: 0x1021, init: 0xFFFF, no reflection (matches SRS COMM-PKT-002).
- Unit test: verify against known vectors from the SRS firmware CRC table.

#### 1.3 — Packet Codec

- Implement `core/packet_codec.py`:
  - `encode_packet(cmd: int, payload: bytes) -> bytes`
  - `PacketDecoder` class with a `feed(data: bytes)` method that accumulates bytes and emits complete packets via a callback when SOF + LEN + CRC align.
- Unit tests: encode/decode round-trip for all 10 command types; verify CRC mismatch is rejected.

#### 1.4 — Serial Worker (QThread)

- Implement `core/serial_comm.py`:
  - `SerialWorker(QThread)` — opens port, runs read loop, feeds `PacketDecoder`.
  - Emits all signals listed in GUI-REQ-001 Section 13.1.
  - `send_packet(cmd, payload)` method queues a packet for TX.
  - Heartbeat: sends CMD_PING every 2 seconds when idle; detects 3 missed ACKs → emits `connectionLost`.
- Manual integration test: connect to real hardware or simulator, verify PING/ACK loop in log.

#### 1.5 — Firmware Simulator

- Implement `tools/firmware_sim.py`: a standalone script that opens a virtual serial port pair (using `socat` on Linux or `com0com` on Windows) and responds to all commands with realistic responses.
- Simulator behaviour:
  - Responds to CMD_PING with RSP_ACK.
  - Responds to CMD_GET_STATUS with a hardcoded RSP_STATUS (v1.0.0, IDLE).
  - Responds to CMD_START_CONTINUITY by streaming 100 RSP_RESULT_CONT packets, then RSP_SCAN_DONE.
  - Responds to CMD_CALIBRATE with RSP_ACK containing a 120 mΩ calibration offset.
  - Responds to CMD_START_HV with RSP_RESULT_HV then a simulated FAULT_HV_INTERLOCK after 2 seconds.
- This simulator is used for all GUI development until real hardware is available.

#### 1.6 — Main Window Skeleton

- Implement `ui/main_window.py` with:
  - QMenuBar (all menus listed in GUI-REQ-001 Section 10, menu items not yet wired).
  - QSplitter containing placeholder Left Panel and Centre Panel widgets.
  - QStatusBar with all sections (static placeholder text).
  - Window title, minimum size, icon.
  - Geometry restore from `profiles/app_settings.json` on open; save on close.

**Phase 1 Exit Criteria:**
- `python main.py` opens the window without errors.
- SerialWorker connects to the firmware simulator, PING/ACK loop visible in console log.
- CRC unit tests pass (`pytest tests/test_crc16.py`).
- Packet encode/decode round-trip tests pass.

---

## 4. Phase 2 — Core UI Panels

**Goal:** All UI panels are implemented with full layout and styling. Controls are wired to enable/disable rules but not yet connected to live data.

### 4.1 Tasks

#### 2.1 — Left Panel

- Implement `ui/left_panel.py` with all group boxes from GUI-REQ-001 Section 5:
  - Connection group: port combo, scan button, baud combo, connect/disconnect buttons, status label.
  - Netlist group: browse button, filename label, tree widget (populated from a hardcoded sample netlist).
  - Test Profile group: profile combo, operator field, DUT ID field, save/new/delete buttons.
  - Test Modes group: four checkboxes, threshold spin boxes.
  - Action group: START, STOP, verdict label, progress bar.
- Connect START / STOP button enable/disable to placeholder state variable.
- COM port scan populates combo from `serial.tools.list_ports`.

#### 2.2 — Matrix View

- Implement `ui/matrix_view.py` as a `QWidget` with `paintEvent` override:
  - Renders 16×16 grid of filled circles using `QPainter`.
  - `update_pin(pin: int, state: PinState)` method triggers `update()`.
  - Hover detection via `mouseMoveEvent` → `QToolTip.showText()`.
  - Click detection via `mousePressEvent` → emits `pinClicked(pin: int)` signal.
  - Scales to widget size while maintaining aspect ratio.
- Populate with test data (all UNTESTED state initially) to confirm rendering.

#### 2.3 — Results Table

- Implement `core/result_model.py` (`QAbstractTableModel`):
  - `appendResult(result: TestResult)` adds a row and calls `layoutChanged`.
  - `data()` returns formatted strings and colour roles for each column.
  - Supports sort via `sort(column, order)`.
- Implement `ui/results_table.py` (`QTableView`):
  - Sets the model.
  - Adds filter toolbar (status combo, type combo, search field).
  - Implements proxy model (QSortFilterProxyModel) for filtering.
  - Context menu with "Copy to Clipboard as CSV".
  - Summary label below table.
- Populate with 20 hardcoded test rows to verify column widths and colours.

#### 2.4 — Log Panel

- Implement `ui/log_panel.py`:
  - QPlainTextEdit, read-only, monospace font.
  - `append_line(level: str, text: str)` method applies colour via HTML.
  - "Clear" and "Save Log…" buttons in toolbar.
  - Max-lines enforcement (oldest lines removed when exceeded).

#### 2.5 — Centre Tabbed Panel

- Integrate MatrixView, ResultsTable, and LogPanel into a QTabWidget in `ui/main_window.py`.
- Wire View menu items (Ctrl+M, Ctrl+R, Ctrl+L) to `setCurrentIndex`.

#### 2.6 — Theming

- Implement `dark_theme.qss` and `light_theme.qss`.
- Wire View → Theme menu to `QApplication.setStyleSheet()`.
- Persist selection to `profiles/app_settings.json`.

**Phase 2 Exit Criteria:**
- All panels render correctly in both dark and light themes.
- Matrix view renders 256 circles; hovering shows pin number tooltip.
- Results table renders with correct column widths and row colours for hardcoded data.
- Log panel appends and colour-codes lines correctly.
- Theme toggle works without restart.

---

## 5. Phase 3 — Test Engine and Live Data

**Goal:** A complete continuity + resistance scan cycle runs end-to-end from the GUI, with live updates to the Matrix View and Results Table. Uses firmware simulator.

### 5.1 Tasks

#### 3.1 — Data Classes

Define dataclasses in `core/data_types.py`:
- `TestResult(pin_a, pin_b, test_type, resistance_mohm, ir_mohm, hv_v, status, timestamp, net_name, pin_a_name, pin_b_name)`
- `ScanSummary(total, pass_count, fail_count)`
- `FirmwareStatus(state, flags, fw_version, cal_offset_mohm)`
- `FaultEvent(fault_code, fault_data, timestamp)`
- `TestState(Enum)`: IDLE, UPLOADING, CALIBRATING, SCANNING, HV_TESTING, COMPLETE, FAULT

#### 3.2 — Test Engine State Machine

Implement `core/test_engine.py` (`QObject`):
- Manages state transitions.
- `start_test(profile, netlist, modes)`: orchestrates the command sequence from SRS PC-TE-002.
- `abort()`: sends CMD_ABORT, transitions to IDLE.
- Emits `stateChanged(TestState)`, `verdictReady(Verdict)`, `calibrationComplete(int)`.
- Connects to `SerialWorker` signals to drive state transitions on packet receipt.

#### 3.3 — Wire START / STOP to Test Engine

- Connect LEFT PANEL START button → `TestEngine.start_test()`.
- Connect LEFT PANEL STOP button → `TestEngine.abort()`.
- Connect `TestEngine.stateChanged` → `MainWindow.onStateChanged()` (applies enable/disable rules from GUI-REQ-001 Section 12).

#### 3.4 — Live Matrix and Table Updates

- Connect `SerialWorker.contResultReceived` → `ResultModel.appendResult` + `MatrixView.update_pin`.
- Connect `SerialWorker.progressUpdate` → progress bar `setValue`.
- Implement 100ms batch-update timer in MatrixView (accumulates pin state changes, repaints once per tick).

#### 3.5 — Netlist Upload

- On `TestEngine` entering UPLOADING state, read the loaded netlist JSON and fragment into ≤510-byte chunks.
- Send CMD_SET_NETLIST packets with sequence numbers; wait for RSP_ACK between fragments.
- Timeout handling: if ACK not received within 5 s, retry once then emit error.

#### 3.6 — Calibration

- Implement Tools → Calibrate menu action: sends CMD_CALIBRATE, waits for RSP_ACK with offset, shows QMessageBox with result.
- Store received calibration offset in profile.

#### 3.7 — Connection Management

- Connect `SerialWorker.connectionLost` → show toast notification, update status bar, re-enable Connect button.
- Implement auto-reconnect option (off by default; configurable in Settings).

**Phase 3 Exit Criteria:**
- Full continuity scan runs against firmware simulator; results appear in Matrix View and Results Table in real time.
- Progress bar advances as RSP_PROGRESS packets arrive.
- Verdict label shows PASS or FAIL after RSP_SCAN_DONE.
- START is disabled during scan; STOP aborts the scan and returns to IDLE.
- Calibration command works and displays result.

---

## 6. Phase 4 — Reporting and Profiles

**Goal:** CSV and PDF reports are generated automatically. Test profiles are fully functional. Netlist editor works.

### 6.1 Tasks

#### 4.1 — CSV Report Generation

- Implement `core/report.py`: `save_csv(results: list[TestResult], profile: TestProfile, path: str)`.
- Columns match SRS PC-RPT-002.
- Auto-save triggered by `TestEngine.verdictReady` signal. Save path: `reports/report_YYYYMMDD_HHMMSS_<DUT_ID>.csv`.

#### 4.2 — PDF Report Generation

- Implement `core/report.py`: `save_pdf(results, profile, matrix_image, path)` using `reportlab.platypus`.
- Page 1: Cover (SRS PC-RPT-003).
- Page 2: Matrix heatmap — render MatrixView to `QImage`, convert to PIL for reportlab.
- Page 3+: Full results table (FAIL rows first, red highlight).
- Footer: doc number, revision, page X of Y.
- PDF generation runs in a QThread to avoid blocking the GUI.
- Wire File → Export PDF menu action.

#### 4.3 — Test History Log

- Implement `core/report.py`: `append_history(entry: HistoryEntry)` writes to `reports/history.json`.
- History viewer dialog: simple QTableView showing history log entries; button to open the associated CSV/PDF.

#### 4.4 — Test Profile Management

- Implement `core/profile.py`: load/save/validate `TestProfile` dataclass to/from JSON in `profiles/`.
- Wire Left Panel Profile combo: loading a profile populates all UI fields.
- Wire Save / New / Delete buttons.
- Implement Profile Manager dialog (GUI-REQ-001 Section 8.5).
- Auto-save current profile to `profiles/app_settings.json` on window close.

#### 4.5 — Netlist Editor Dialog

- Implement `ui/netlist_editor.py` per GUI-REQ-001 Section 8.3.
- Wire to Tools → Edit Netlist and Left Panel "Edit Netlist" button.
- Real-time validation with error status bar.
- Save and Save As functionality.

#### 4.6 — Netlist Validation

- Implement `core/netlist.py`: `load_netlist(path) -> Netlist`, `validate_netlist(netlist) -> list[str]`.
- Validation rules from SRS PC-NL-002.
- Integrate into file browse (Left Panel) and Netlist Editor.

**Phase 4 Exit Criteria:**
- CSV report auto-saves after each test completion; content matches SRS format.
- PDF report generates within 10 s for a 256-pair result set; all three sections present.
- Test profiles save/load correctly; switching profiles updates all UI fields.
- Netlist editor opens, allows editing, validates, and saves.
- History log persists across application restarts.

---

## 7. Phase 5 — Safety Dialogs and HV Workflow

**Goal:** The HV insulation test workflow is fully implemented with all required safety steps. Fault handling is complete.

### 7.1 Tasks

#### 5.1 — HV Confirmation Dialog

- Implement `ui/hv_confirm_dialog.py` per GUI-REQ-001 Section 8.1.
- Non-dismissible (override `closeEvent`, disable Escape key, hide title bar close button).
- Three-checkbox confirmation; CONFIRM button disabled until all checked.
- Prominent voltage display.
- Wire: TestEngine enters HV_TESTING state → show dialog before sending first CMD_START_HV.

#### 5.2 — HV Status Bar Indicator

- Add HV ACTIVE label to status bar (hidden by default).
- Wire `TestEngine.stateChanged(HV_TESTING)` → show label with 1 Hz flash (QTimer + toggle visible).
- Wire `TestEngine.stateChanged` (any other) → hide label.

#### 5.3 — Fault Alert Dialog

- Implement `ui/fault_dialog.py` per GUI-REQ-001 Section 8.2.
- Non-dismissible; always-on-top.
- Maps fault codes to human-readable strings.
- "ACKNOWLEDGE AND ABORT" button triggers `TestEngine.abort()` and closes dialog.
- Wire `SerialWorker.faultReceived` → `TestEngine.onFault()` → show dialog.

#### 5.4 — HV Test Results

- Wire `SerialWorker.hvResultReceived` → `ResultModel.appendResult` + `MatrixView.update_pin` (orange state).
- Show IR value in tooltip and Results Table.

#### 5.5 — Golden Sample Wizard

- Implement `ui/golden_sample.py` (QWizard) per GUI-REQ-001 Section 8.4.
- Page 1 (Warning): checkbox required to advance.
- Page 2 (Scan): embeds a compact MatrixView; drives CMD_START_CONTINUITY; advances on RSP_SCAN_DONE.
- Page 3 (Review): QTreeWidget showing discovered nets; inline rename via double-click; drag-and-drop pins between nets.
- Page 4 (Save): filename field with default `golden_YYYYMMDD.json`; saves to `netlists/`.
- Wire to Tools → Golden Sample Learning.

#### 5.6 — STOP During HV Confirmation

- When STOP is clicked while TestEngine is in HV_TESTING state, show QMessageBox:
  `"WARNING: Stopping during HV test will trigger discharge sequence. Confirm?"`.
- Only send CMD_ABORT after user confirms.

**Phase 5 Exit Criteria:**
- HV confirmation dialog appears before any HV command is sent; cannot be dismissed without all checkboxes ticked.
- Fault dialog appears on simulated RSP_FAULT; cannot be dismissed until ACKNOWLEDGE clicked.
- After fault acknowledgement, application returns to IDLE state with amber verdict display.
- Golden Sample wizard completes and saves a valid netlist JSON.
- HV ACTIVE indicator flashes in status bar during simulated HV test.

---

## 8. Phase 6 — Polish and Packaging

**Goal:** Production-quality application, packaged as a standalone Windows executable.

### 8.1 Tasks

#### 6.1 — Performance Optimisation

- Profile matrix view repaint under 32,640-pair simulated scan. Target: no visible lag at 200ms update cadence.
- Profile ResultModel under high row count (10,000+ rows). Ensure QSortFilterProxyModel does not block the main thread.
- Profile PDF generation; ensure it runs off-thread (Phase 4 task, validated here).

#### 6.2 — Keyboard Shortcuts and Accessibility

- Wire all shortcuts from GUI-REQ-001 Section 11.
- Add `setToolTip` and `setAccessibleName` to all interactive controls.
- Verify tab order in each panel.

#### 6.3 — Settings Dialog

- Implement a Settings dialog (Tools → Settings):
  - Auto-save PDF: on/off.
  - Auto-reconnect: on/off and retry interval.
  - Log max lines.
  - DUT ID prefix.
  - Default test thresholds.

#### 6.4 — About Dialog and Version

- Implement Help → About: application version, build date, firmware protocol version, Python/Qt versions.
- Read version from `version.py` constant; PyInstaller build script injects build date.

#### 6.5 — Error Handling Audit

- Review all file I/O (netlist load, CSV/PDF save) for exception handling; surface errors as QMessageBox.
- Review all serial error paths: port-not-found, permission denied, unexpected disconnect.
- Verify no unhandled Python exceptions propagate to Qt's event loop.

#### 6.6 — PyInstaller Packaging

- Create `harness_tester.spec` for PyInstaller:
  - Include `resources/` (QSS files, icons).
  - Include `reportlab` font data.
  - Hidden imports: `pyserial`, `reportlab`, `PyQt6`.
  - One-file mode (`--onefile`).
  - Windows: set application icon, version info, no console window (`--noconsole`).
- Test the built executable on a clean Windows 10 VM (no Python installed).

#### 6.7 — Final Testing with Hardware

- Connect to real Harness Tester hardware.
- Run full test cycle: continuity + resistance + short + HV.
- Verify CSV and PDF outputs.
- Test lid-open fault during HV test; verify fault dialog and discharge.
- Test unexpected USB disconnect during scan.

**Phase 6 Exit Criteria:**
- Single `.exe` runs on a clean Windows 10 machine without any Python installation.
- All keyboard shortcuts functional.
- No unhandled exceptions during normal operation.
- Full hardware test cycle completes: PASS result, CSV and PDF generated correctly.
- HV fault scenario handled cleanly.

---

## 9. Module Dependency Map

```
main.py
  └── ui/main_window.py
        ├── ui/left_panel.py
        │     └── core/netlist.py
        │     └── core/profile.py
        ├── ui/matrix_view.py
        ├── ui/results_table.py
        │     └── core/result_model.py
        │           └── core/data_types.py
        ├── ui/log_panel.py
        ├── ui/hv_confirm_dialog.py
        ├── ui/fault_dialog.py
        ├── ui/netlist_editor.py
        │     └── core/netlist.py
        ├── ui/golden_sample.py
        │     └── core/netlist.py
        └── core/test_engine.py
              ├── core/serial_comm.py
              │     ├── core/packet_codec.py
              │     │     └── core/crc16.py
              │     └── core/data_types.py
              ├── core/result_model.py
              └── core/report.py
                    └── core/result_model.py
```

**Build order (no circular imports):**
`crc16` → `packet_codec` → `data_types` → `result_model` → `serial_comm` → `netlist` → `profile` → `report` → `test_engine` → UI modules → `main_window` → `main`

---

## 10. Testing Strategy

### 10.1 Unit Tests (`tests/`)

| Test File | Coverage |
|---|---|
| `test_crc16.py` | CRC vectors; round-trip |
| `test_packet_codec.py` | Encode/decode all commands; CRC mismatch rejection; fragmented input |
| `test_netlist.py` | Valid netlist load; each validation error type |
| `test_result_model.py` | Append, sort, filter, CSV export |
| `test_report.py` | CSV content; PDF page count (smoke test) |
| `test_profile.py` | Save/load; default creation; field round-trip |
| `test_test_engine.py` | State machine transitions; correct command sequence; fault handling |

### 10.2 Integration Tests

- `tests/integration/test_serial_loopback.py`: connects SerialWorker to firmware simulator, runs a full continuity scan, verifies all results received.
- Requires `firmware_sim.py` running on a virtual port pair.

### 10.3 GUI Tests (pytest-qt)

- `tests/gui/test_matrix_view.py`: verify pin state updates trigger repaint; click signal emitted correctly.
- `tests/gui/test_results_table.py`: verify filter proxy; row count after append; CSV clipboard copy.
- `tests/gui/test_hv_dialog.py`: verify CONFIRM button remains disabled until all checkboxes ticked; Escape does not close.

### 10.4 Manual Test Checklist (Hardware)

- [ ] Full continuity scan: 256-pin known harness → correct PASS/FAIL
- [ ] Resistance measurement: 100 mΩ reference → within ±20 mΩ
- [ ] Short circuit: deliberate short between two pins → detected and reported
- [ ] HV insulation: known good isolation → IR value > limit → PASS
- [ ] HV fault: open lid during HV test → fault dialog appears, discharge confirmed
- [ ] Disconnect during scan → connection lost → reconnect works
- [ ] CSV report: open in Excel, verify all columns and row count
- [ ] PDF report: open in PDF viewer, verify cover, matrix, table pages
- [ ] PyInstaller build: run on clean Windows 10 VM

---

## 11. Risk Register

| # | Risk | Probability | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Virtual serial port tools (`com0com`) not available on test machine | Medium | High | Document install steps; provide alternative using real USB-serial loopback |
| R2 | PyInstaller fails to bundle all reportlab font data | Medium | High | Test build early (Phase 4); add explicit `--add-data` for reportlab fonts in .spec |
| R3 | Matrix view repaint too slow for 32,640 pairs | Low | Medium | Batch updates via 100ms timer (Phase 3); use `update(rect)` not full repaint |
| R4 | QSortFilterProxyModel blocks main thread at 10k+ rows | Low | Medium | Qt proxy models must stay on the main thread — mitigation is virtual scrolling, visible-row cap (5000), or pagination; do NOT move to background thread |
| R5 | Non-dismissible dialogs cause issues under certain window managers (Linux) | Medium | Low | Override `closeEvent`, `keyPressEvent`, and `reject()` |
| R6 | Firmware protocol changes break packet codec | Low | High | Version check on RSP_STATUS; warn user if firmware version mismatches |
| R7 | Hardware not available for Phase 6 testing | Medium | High | All phases 1–5 work against simulator; hardware testing is Phase 6 only |

---

## 12. Done Criteria

The GUI development is complete when all of the following are true:

- [ ] All GUI-REQ-001 requirements are implemented and verified.
- [ ] All unit tests pass (`pytest tests/` — zero failures).
- [ ] Integration test with firmware simulator passes end-to-end.
- [ ] Manual hardware test checklist is fully ticked.
- [ ] PyInstaller build runs on a clean Windows 10 machine with no Python installed.
- [ ] Ubuntu 22.04 smoke test: application launches, connects, runs a scan.
- [ ] No unhandled Python exceptions observed during any test scenario.
- [ ] PDF report reviewed and approved by a test engineer.
- [ ] Code follows PEP 8; all public functions have docstrings (SRS NFR-MNT-003).

---

*Document ID: GUI-PLAN-001 | Version 1.0 | 2026-04-21*
