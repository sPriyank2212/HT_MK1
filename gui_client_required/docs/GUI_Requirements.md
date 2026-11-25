# GUI Requirements Specification
## Harness Tester — PC Software (PyQt6)

**Document ID:** GUI-REQ-001
**Version:** 1.0
**Date:** 2026-04-21
**Parent Document:** SRS-001 (Software Requirements Specification)
**Status:** Draft

---

## Table of Contents

1. [Purpose and Scope](#1-purpose-and-scope)
2. [Technology Stack](#2-technology-stack)
3. [Application Structure](#3-application-structure)
4. [Main Window Layout](#4-main-window-layout)
5. [Left Panel — Control & Navigation](#5-left-panel--control--navigation)
6. [Centre Panel — Tabbed Views](#6-centre-panel--tabbed-views)
7. [Status Bar](#7-status-bar)
8. [Dialogs and Modals](#8-dialogs-and-modals)
9. [Theming and Visual Design](#9-theming-and-visual-design)
10. [Menu Bar](#10-menu-bar)
11. [Keyboard Shortcuts](#11-keyboard-shortcuts)
12. [State-Driven UI Behaviour](#12-state-driven-ui-behaviour)
13. [Signal / Slot Architecture](#13-signal--slot-architecture)
14. [Accessibility](#14-accessibility)
15. [Requirement Traceability](#15-requirement-traceability)

---

## 1. Purpose and Scope

This document defines the graphical user interface requirements for the Harness Tester PC application. It expands on the PC software requirements in SRS-001 Section 4 with the pixel-level detail needed to implement a production-quality PyQt6 application.

### 1.1 Target Users

| User | Primary Tasks | Skill Level |
|---|---|---|
| Test Operator | Connect device, load netlist, run test, read verdict | Low — needs minimal training |
| Test Engineer | Create/edit netlists, tune thresholds, review detailed results | Medium |
| Maintenance Engineer | Run calibration, review diagnostics, export logs | Medium |

### 1.2 Design Principles

- **Operator-first:** The most common workflow (connect → load → run → verdict) requires no more than three clicks from startup.
- **Fail-safe UI:** Safety-critical controls (HV test) require an explicit confirmation step that cannot be bypassed.
- **Non-blocking:** All communication with firmware runs on a background thread. The GUI must never freeze.
- **Legible verdict:** PASS / FAIL is readable at 2 m distance without walking up to the screen.

---

## 2. Technology Stack

| Component | Version | Notes |
|---|---|---|
| Python | 3.10+ | 3.11 recommended |
| PyQt6 | 6.4+ | Qt 6.4 minimum for full feature set |
| pyserial | 3.5+ | UART communication |
| reportlab | 3.6+ | PDF report generation |
| PyInstaller | 5.x | Standalone executable packaging |

### 2.1 File / Module Layout

```
harness_tester/
├── main.py                   # Entry point — creates QApplication, shows MainWindow
├── version.py                # Application version constant
├── ui/
│   ├── main_window.py        # MainWindow (QMainWindow subclass)
│   ├── left_panel.py         # LeftPanel widget
│   ├── matrix_view.py        # MatrixView widget (16×16 grid)
│   ├── results_table.py      # ResultsTable widget (QTableView + model)
│   ├── log_panel.py          # LogPanel widget (QPlainTextEdit)
│   ├── netlist_editor.py     # NetlistEditorDialog
│   ├── golden_sample.py      # GoldenSampleWizard (QWizard)
│   ├── hv_confirm_dialog.py  # HVConfirmDialog (non-dismissible modal)
│   ├── fault_dialog.py       # FaultDialog (non-dismissible modal)
│   ├── profile_manager.py    # ProfileManagerDialog
│   ├── settings_dialog.py    # SettingsDialog (Tools → Settings)
│   ├── serial_monitor.py     # SerialMonitorWindow (Tools → Serial Monitor)
│   └── history_viewer.py     # HistoryViewerDialog (File → Test History)
├── core/
│   ├── crc16.py              # CRC-16/CCITT-FALSE
│   ├── packet_codec.py       # encode_packet / PacketDecoder
│   ├── data_types.py         # Shared dataclasses and enums (TestResult, TestState, etc.)
│   ├── serial_comm.py        # SerialWorker (QThread + Qt signals)
│   ├── test_engine.py        # TestEngine state machine
│   ├── result_model.py       # ResultModel (QAbstractTableModel)
│   ├── netlist.py            # Netlist load / validate / edit
│   ├── profile.py            # TestProfile load / save / validate
│   └── report.py             # CSV and PDF generation
├── tools/
│   └── firmware_sim.py       # Firmware simulator (virtual serial port)
├── resources/
│   ├── dark_theme.qss        # Dark stylesheet
│   ├── light_theme.qss       # Light stylesheet
│   └── icons/                # SVG icons (connect, start, stop, etc.)
├── tests/
│   ├── test_crc16.py
│   ├── test_packet_codec.py
│   ├── test_netlist.py
│   ├── test_result_model.py
│   ├── test_report.py
│   ├── test_profile.py
│   ├── test_test_engine.py
│   ├── integration/
│   │   └── test_serial_loopback.py
│   └── gui/
│       ├── test_matrix_view.py
│       ├── test_results_table.py
│       └── test_hv_dialog.py
├── profiles/                 # JSON test profiles (created at runtime)
├── reports/                  # CSV and PDF outputs (created at runtime)
└── netlists/                 # Netlist JSON files (created at runtime)
```

---

## 3. Application Structure

### 3.1 Top-Level Window Hierarchy

```
QMainWindow (MainWindow)
├── QMenuBar
│   ├── File
│   ├── View
│   ├── Tools
│   └── Help
├── QSplitter (horizontal, resizable)
│   ├── LeftPanel (QWidget, fixed min-width 240px, max 380px)
│   └── CentrePanel (QWidget, stretches to fill remaining space)
│       └── QTabWidget
│           ├── Tab 0: MatrixView
│           ├── Tab 1: ResultsTable
│           └── Tab 2: LogPanel
└── QStatusBar
```

### 3.2 Window Defaults

| Property | Value |
|---|---|
| Minimum size | 1024 × 640 px |
| Default size | 1280 × 800 px |
| Title | `Harness Tester vX.Y.Z — [profile name]` |
| Window icon | Logo icon (16×16, 32×32, 48×48) |
| Position | Restored from `profiles/app_settings.json`; centred on first run |

---

## 4. Main Window Layout

```
┌────────────────────────────────────────────────────────────────────┐
│  File   View   Tools   Help                              [min][max]│
├──────────────────┬─────────────────────────────────────────────────┤
│  LEFT PANEL      │  Matrix View  │ Results Table │  Log            │
│                  │                                                  │
│  [Connection]    │  [16×16 GRID — coloured circles]                │
│  ─────────────   │                                                  │
│  [Netlist]       │                                                  │
│  ─────────────   │                                                  │
│  [Test Profile]  │                                                  │
│  ─────────────   │                                                  │
│  [Test Modes]    │                                                  │
│  ─────────────   │                                                  │
│  [START]         │                                                  │
│  [STOP]          │                                                  │
│                  │                                                  │
│  VERDICT:        │                                                  │
│  ██ PASS ██      │                                                  │
├──────────────────┴─────────────────────────────────────────────────┤
│ COM3 @ 921600  |  FW v1.0.0  |  PASS: 254  |  FAIL: 2  |  01:23  │
└────────────────────────────────────────────────────────────────────┘
```

---

## 5. Left Panel — Control & Navigation

The left panel is a vertical stack of collapsible group boxes. Minimum width 240 px.

### 5.1 Connection Group Box

```
┌─ Connection ─────────────────────┐
│ Port: [COM3 ▼]  [Scan]           │
│ Baud: [921600 ▼]                 │
│ [● Connect]  [○ Disconnect]      │
│ Status: CONNECTED — FW v1.0.0    │
└──────────────────────────────────┘
```

**Widgets and behaviour:**

| Widget | Type | Behaviour |
|---|---|---|
| Port combo | QComboBox | Populated by `serial.tools.list_ports`; auto-highlights CH340G/CP2102 entries with a USB icon |
| Scan button | QPushButton | Re-scans available ports; label "Refresh" |
| Baud combo | QComboBox | Fixed values: 9600, 115200, 921600; default 921600 |
| Connect button | QPushButton | Opens port, starts heartbeat; disabled when already connected |
| Disconnect button | QPushButton | Sends CMD_ABORT if scan active, closes port; disabled when not connected |
| Status label | QLabel | Updates via `connectionStatusChanged` signal; colour-coded (grey/green/red/orange) |

**GUI-CON-001** — The Port combo shall show VID/PID description next to each port name. CH340G and CP2102 entries shall be highlighted bold.

**GUI-CON-002** — On successful connection (RSP_STATUS received), the Status label shall turn green and show `CONNECTED — FW vX.Y.Z`. If firmware version mismatches the expected version, a yellow warning icon shall appear next to the label.

**GUI-CON-003** — If connection is lost unexpectedly, the Status label shall turn red (`CONNECTION LOST`), the Connect button shall re-enable, and a non-blocking toast notification shall appear at the bottom of the screen for 5 seconds.

### 5.2 Netlist Group Box

```
┌─ Netlist ────────────────────────┐
│ [Browse…]  current_netlist.json  │
│ ─────────────────────────────    │
│ ▶ NET: GROUND (4 pins)           │
│   ├─ Pin 1 — GND                 │
│   └─ Pin 15 — GND_RTN            │
│ ▶ NET: CAN_BUS (2 pins)          │
│                                  │
│ [Edit Netlist]  [New Netlist]    │
└──────────────────────────────────┘
```

**GUI-NL-001** — The netlist tree (QTreeWidget) shall show all nets and their pins. Pin names come from the JSON netlist. If a pin has no name, display `Pin N`.

**GUI-NL-002** — Clicking "Browse…" opens a QFileDialog filtered for `*.json`. The loaded netlist is immediately validated. Validation errors are shown in a modal dialog listing each error by line number.

**GUI-NL-003** — If no netlist is loaded, a placeholder text reads `No netlist loaded — Click Browse or run Golden Sample`. The START button shall be disabled.

**GUI-NL-004** — An icon badge on the group box title shall show: green tick (valid), red cross (invalid), grey dash (none loaded).

### 5.3 Test Profile Group Box

```
┌─ Test Profile ───────────────────┐
│ Profile: [Default ▼]             │
│ Operator: [____________]         │
│ DUT ID:   [____________]         │
│ [Save]  [New]  [Delete]          │
└──────────────────────────────────┘
```

**GUI-TP-001** — Profile combo lists all JSON files in `profiles/`. Selecting a profile populates all fields (COM port, test modes, thresholds, operator, netlist path).

**GUI-TP-002** — DUT ID field auto-increments numeric suffix each test (e.g., `HT-0001`, `HT-0002`). The prefix comes from the profile setting.

**GUI-TP-003** — Unsaved changes to operator or DUT ID are indicated by an asterisk in the profile combo label. Navigating away without saving prompts a "Save changes?" dialog.

### 5.4 Test Modes Group Box

```
┌─ Test Modes ─────────────────────┐
│ [x] Continuity                   │
│ [x] Resistance (4-wire Kelvin)   │
│ [x] Short Circuit                │
│ [x] HV Insulation  ⚠ 500V       │
│ ─────────────────────────────    │
│ R Limit: [____] mΩ max           │
│ IR Limit: [____] MΩ min          │
│ HV Soak:  [____] ms              │
└──────────────────────────────────┘
```

**GUI-TM-001** — Each test mode is a QCheckBox. All are checked by default. HV Insulation checkbox has a yellow warning icon and shows the configured test voltage from the netlist.

**GUI-TM-002** — Threshold fields (R Limit, IR Limit, HV Soak) are QSpinBox/QDoubleSpinBox. Values are clamped to firmware-validated ranges (from SRS Section 5.3, CMD_SET_PARAM). Out-of-range values highlight red.

**GUI-TM-003** — If HV Insulation is unchecked while a test is running, a warning dialog states: "Disabling HV mid-test is not allowed. Stop the test first."

### 5.5 Action Buttons and Verdict

```
┌──────────────────────────────────┐
│  [        START TEST        ]    │
│  [         STOP / ABORT     ]    │
│                                  │
│  ┌──────────────────────────┐    │
│  │   ██  P A S S  ██        │    │
│  └──────────────────────────┘    │
│  Duration: 00:01:23              │
│  Progress: ████████░░░  78%      │
└──────────────────────────────────┘
```

**GUI-ACT-001** — START button: green background, large font (14pt bold). Disabled when: no COM port open, no netlist loaded, or a test is running.

**GUI-ACT-002** — STOP button: red background, large font (14pt bold). Disabled when no test is running. During HV test shows a confirmation dialog before sending CMD_ABORT (text from SAF-005 in SRS).

**GUI-ACT-003** — Verdict display: a QLabel with minimum height 60px and font size 36pt bold. Background colour: green for PASS, red for FAIL, grey for no result, amber for INCONCLUSIVE. Visible from 2 m distance (SRS NFR-USE-003).

**GUI-ACT-004** — Progress bar updates every RSP_PROGRESS packet. Shows both percentage and `pairs_done / pairs_total`. Estimated time to completion is shown below the bar.

---

## 6. Centre Panel — Tabbed Views

### 6.1 Matrix View Tab

The Matrix View is a custom QWidget rendering a 16-column × 16-row grid of 256 circular pin indicators.

```
     1   2   3   4   5 ...  16
 1  (G) (G) (R) (G) (G)... (.)
 2  (.) (G) (G) (G) (G)... (.)
 ...
16  (G) (G) (G) (G) (G)... (G)

Legend: G=PASS  R=FAIL  Y=IN PROGRESS  .=UNTESTED  O=HV Result
```

**GUI-MX-001** — Each pin indicator is a filled circle, 28px diameter with 4px gap. Colours:

| State | Fill Colour | Border |
|---|---|---|
| UNTESTED | #808080 (grey) | None |
| IN_PROGRESS | #FFD700 (yellow) | 2px white |
| PASS | #28A745 (green) | None |
| FAIL | #DC3545 (red) | None |
| HV_RESULT | #FD7E14 (orange) | None |

**GUI-MX-002** — The grid shall update within 200ms of receiving any RSP_RESULT_CONT / RSP_RESULT_SHORT / RSP_RESULT_HV. Updates shall be batched by a 100ms timer to avoid repainting on every packet.

**GUI-MX-003** — Hovering over a pin circle shows a QToolTip containing:
- Pin number and name
- Total pairs involving this pin
- Count of PASS / FAIL results so far
- Best/worst resistance measured (if any)
- IR value (if HV result available)

**GUI-MX-004** — Clicking a pin circle opens a `PinDetailDialog` (non-modal) listing all test results that involve that pin, with the same columns as the Results Table.

**GUI-MX-005** — A colour legend bar sits below the grid with labelled swatches for each state. The matrix title shows the current DUT ID and scan progress.

**GUI-MX-006** — The matrix shall scale proportionally when the window is resized. Minimum circle size is 16px; maximum is 48px. The grid always shows all 256 pins (no scroll).

### 6.2 Results Table Tab

The Results Table is a QTableView backed by `ResultModel` (QAbstractTableModel).

**GUI-RT-001** — Columns (in order):

| # | Column | Width | Align |
|---|---|---|---|
| 0 | Test # | 60 px | Center |
| 1 | Pin A | 55 px | Center |
| 2 | Pin A Name | 110 px | Left |
| 3 | Pin B | 55 px | Center |
| 4 | Pin B Name | 110 px | Left |
| 5 | Net Name | 130 px | Left |
| 6 | Test Type | 100 px | Center |
| 7 | Resistance (mΩ) | 110 px | Right |
| 8 | IR (MΩ) | 90 px | Right |
| 9 | HV (V) | 70 px | Right |
| 10 | Status | 90 px | Center |
| 11 | Timestamp | 130 px | Left |

**GUI-RT-002** — Row highlighting: FAIL rows have a light red background (#FFCCCC), PASS rows have a light green background (#CCFFCC) in light theme; equivalent dark-theme colours apply.

**GUI-RT-003** — Status column cells use a coloured badge (rounded rectangle): green for PASS, red for FAIL/OPEN/SHORT/HV_FAIL.

**GUI-RT-004** — A filter toolbar above the table contains:
- Status filter combo: All / PASS / FAIL / OPEN / SHORT / HV_FAIL
- Test type filter combo: All / Continuity / Resistance / Short / HV
- Search field (filters by pin name or net name, case-insensitive)
- "Clear Filters" button

**GUI-RT-005** — All columns shall be sortable by clicking headers. Default sort: Test # ascending.

**GUI-RT-006** — Right-click context menu on selected rows: "Copy to Clipboard as CSV", "Export Selected as PDF", "Show Pin Detail".

**GUI-RT-007** — The table footer (below the last row) shows summary counts: `Total: N | PASS: N | FAIL: N | OPEN: N | SHORT: N | HV FAIL: N`.

**GUI-RT-008** — New rows are appended to the bottom. Auto-scroll to the latest row is active during scanning; disabled if the user manually scrolls up.

### 6.3 Log Tab

**GUI-LOG-001** — A read-only `QPlainTextEdit` with monospace font (Courier New 9pt or Consolas 9pt). Horizontal scrollbar enabled.

**GUI-LOG-002** — Each log line is prefixed with a timestamp `[HH:MM:SS.mmm]` and a level tag: `[INFO]`, `[WARN]`, `[ERROR]`, `[TX]`, `[RX]`, `[FAULT]`.

**GUI-LOG-003** — Log lines are colour-coded:
- INFO: default foreground
- WARN: #FFA500 (amber)
- ERROR / FAULT: #FF4444 (red)
- TX: #6699FF (blue)
- RX: #66CC66 (green)

**GUI-LOG-004** — A toolbar above the log provides: "Clear Log", "Save Log…" (exports to .txt), and a "Max lines" spin box (default 10,000; older lines discarded when exceeded).

**GUI-LOG-005** — CRC errors, NACK responses, unexpected disconnects, and fault events are always logged at ERROR level regardless of the current log filter.

---

## 7. Status Bar

The QStatusBar runs the full width of the window and contains (left to right):

| Section | Content | Update Trigger |
|---|---|---|
| Port indicator | `● COM3 @ 921600` or `○ Not connected` | Connection state change |
| Firmware version | `FW v1.0.0` | On RSP_STATUS received |
| PASS counter | `PASS: 254` | Each PASS result |
| FAIL counter | `FAIL: 2` | Each FAIL result |
| Elapsed time | `01:23` (MM:SS) | Timer tick every second while test runs |
| HV indicator | `⚡ HV ACTIVE 500V` (visible only during HV test) | HV state change |

**GUI-SB-001** — The FAIL counter shall be displayed in red if value > 0.

**GUI-SB-002** — The HV ACTIVE label shall use a yellow background and flash at 1 Hz during HV test execution.

**GUI-SB-003** — Clicking any status bar section opens the relevant context (clicking Port opens Connection group, clicking FAIL opens Results Table filtered to FAIL).

---

## 8. Dialogs and Modals

### 8.1 HV Confirmation Dialog

Triggered when the user clicks START and HV Insulation is enabled.

**GUI-DLG-HV-001** — Non-dismissible modal dialog. Cannot be closed by pressing Escape or clicking the X button.

**GUI-DLG-HV-002** — Content:
```
⚠  HIGH VOLTAGE TEST — SAFETY WARNING  ⚠

This test will apply up to 500V DC to the DUT.

Before proceeding, confirm ALL of the following:
  [ ] Safety enclosure lid is fully closed and latched
  [ ] No personnel are in contact with the DUT or connectors
  [ ] DUT is fully isolated from external power supplies

Requested test voltage: 500V DC
Soak time: 1000 ms

              [CANCEL]  [CONFIRM AND START]
```

**GUI-DLG-HV-003** — The "CONFIRM AND START" button is disabled until all three checkboxes are ticked.

**GUI-DLG-HV-004** — Checkbox text and dialog background use a yellow (#FFEE88) highlight colour.

### 8.2 Fault Alert Dialog

Triggered on receipt of RSP_FAULT.

**GUI-DLG-FAULT-001** — Non-dismissible, always-on-top modal. Cannot be closed until the user clicks "ACKNOWLEDGE AND ABORT".

**GUI-DLG-FAULT-002** — Content layout:
```
🔴  HARDWARE FAULT DETECTED

Fault Type:    HV Interlock — Lid Opened During Test
Fault Code:    0x01
Fault Data:    0x00000000
Time:          14:23:07.441

The test has been stopped. The HV discharge sequence
has been triggered automatically.

DO NOT open the enclosure until the status LED
shows IDLE (solid green).

                    [ACKNOWLEDGE AND ABORT]
```

**GUI-DLG-FAULT-003** — Fault descriptions are human-readable, mapped from the fault codes defined in SRS Table COMM-RSP-002.

**GUI-DLG-FAULT-004** — After acknowledgement, the test engine transitions to FAULT → IDLE, the verdict label shows FAULT in amber, and a fault entry is added to the Log tab.

### 8.3 Netlist Editor Dialog

Accessible from Tools → Edit Netlist or the Left Panel "Edit Netlist" button.

**GUI-DLG-NL-001** — QDialog (resizable, non-modal). Two-panel layout: left side shows the netlist tree; right side shows properties for the selected net or pin.

**GUI-DLG-NL-002** — Toolbar: Add Net, Add Pin, Remove Selected, Move Pin to Net, Save, Save As, Validate.

**GUI-DLG-NL-003** — Validation runs on every change. Errors are shown in a status bar at the bottom of the dialog, preventing Save until resolved.

**GUI-DLG-NL-004** — The per-net properties panel shows: Net Name (QLineEdit), Resistance Min/Max (QDoubleSpinBox, mΩ), HV Test enabled (QCheckBox), HV Voltage (QSpinBox, V), Soak time (QSpinBox, ms), Min IR (QDoubleSpinBox, MΩ).

### 8.4 Golden Sample Wizard

Accessible from Tools → Golden Sample Learning.

**GUI-DLG-GS-001** — QWizard with four pages:
1. **Warning Page**: Explains the Golden Sample mode; requires checkbox confirmation.
2. **Scan Page**: Runs CMD_START_CONTINUITY; shows real-time matrix view as connections are discovered.
3. **Review Page**: Shows all discovered connections as a provisional netlist; user can rename nets, exclude pairs, assign pin names.
4. **Save Page**: Confirms filename and saves to `netlists/` directory.

**GUI-DLG-GS-002** — The wizard cannot advance past the Scan Page until the firmware sends RSP_SCAN_DONE.

**GUI-DLG-GS-003** — On the Review Page, the user can drag-and-drop pins between nets (which merges/splits nets) and rename both nets and individual pins.

### 8.5 Profile Manager Dialog

Accessible from File → Manage Profiles.

**GUI-DLG-PM-001** — Lists all profiles in `profiles/`. Buttons: New, Duplicate, Rename, Delete, Set as Default.

**GUI-DLG-PM-002** — Deleting the active profile prompts: "This is the current profile. Switch to Default before deleting. Continue?"

---

## 9. Theming and Visual Design

### 9.1 Themes

**GUI-THM-001** — The application ships with two QSS stylesheets: `dark_theme.qss` (default) and `light_theme.qss`. Theme is set via `QApplication.setStyleSheet()`.

**GUI-THM-002** — Theme selection is accessible from View → Theme → Dark / Light. Change takes effect immediately without restart.

**GUI-THM-003** — Theme choice is persisted in `profiles/app_settings.json`.

### 9.2 Dark Theme Palette

| Role | Colour |
|---|---|
| Window background | #1E1E2E |
| Panel background | #2A2A3E |
| Group box title | #CDD6F4 |
| Primary text | #CDD6F4 |
| Secondary text | #BAC2DE |
| Accent / active | #89B4FA |
| PASS green | #A6E3A1 |
| FAIL red | #F38BA8 |
| WARNING amber | #F9E2AF |
| Input background | #313244 |
| Border | #45475A |

### 9.3 Light Theme Palette

| Role | Colour |
|---|---|
| Window background | #F5F5F5 |
| Panel background | #FFFFFF |
| Group box title | #1C1C1C |
| Primary text | #1C1C1C |
| PASS green | #28A745 |
| FAIL red | #DC3545 |
| WARNING amber | #FFC107 |
| Input background | #FFFFFF |
| Border | #CCCCCC |

### 9.4 Typography

| Context | Font | Size | Weight |
|---|---|---|---|
| General UI | System default (Segoe UI on Windows) | 10pt | Normal |
| Group box titles | As above | 10pt | Bold |
| Verdict label | System default | 36pt | Bold |
| Status bar | System default | 9pt | Normal |
| Log panel | Consolas / Courier New | 9pt | Normal |
| Results table | System default | 9pt | Normal |

---

## 10. Menu Bar

### File Menu
| Item | Shortcut | Action |
|---|---|---|
| Load Netlist… | Ctrl+O | Opens netlist file dialog |
| Save Test Results as CSV… | Ctrl+S | Saves current results to CSV |
| Export PDF Report… | Ctrl+P | Opens save dialog, generates PDF |
| Test History… | — | Opens history viewer dialog |
| Manage Profiles… | — | Opens Profile Manager dialog |
| Exit | Alt+F4 | Prompts if test is running |

### View Menu
| Item | Shortcut | Action |
|---|---|---|
| Theme → Dark | — | Apply dark_theme.qss |
| Theme → Light | — | Apply light_theme.qss |
| Show Log | Ctrl+L | Switches to Log tab |
| Show Matrix | Ctrl+M | Switches to Matrix View tab |
| Show Results | Ctrl+R | Switches to Results Table tab |

### Tools Menu
| Item | Shortcut | Action |
|---|---|---|
| Netlist Editor… | Ctrl+E | Opens Netlist Editor Dialog |
| Golden Sample Learning… | — | Opens Golden Sample Wizard |
| Calibrate… | — | Sends CMD_CALIBRATE, shows result |
| Serial Monitor… | — | Opens raw serial monitor window |
| Settings… | Ctrl+, | Opens application settings dialog |

### Help Menu
| Item | Action |
|---|---|
| User Manual | Opens PDF manual from resources/ |
| About | Shows version, build date, firmware protocol version |

---

## 11. Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| F5 | Start Test |
| F6 | Stop / Abort Test |
| F7 | Run Calibration |
| Ctrl+O | Load Netlist |
| Ctrl+S | Save CSV |
| Ctrl+P | Export PDF |
| Ctrl+E | Open Netlist Editor |
| Ctrl+L | Switch to Log Tab |
| Ctrl+M | Switch to Matrix Tab |
| Ctrl+R | Switch to Results Tab |
| Ctrl+, | Open Settings |
| Escape | Cancel current dialog (except non-dismissible modals) |

---

## 12. State-Driven UI Behaviour

The GUI reflects the `TestEngine` state machine. Each state enables/disables specific controls:

| UI Control | IDLE | UPLOADING | CALIBRATING | SCANNING | HV_TESTING | COMPLETE | FAULT |
|---|---|---|---|---|---|---|---|
| Port combo | Enabled | Disabled | Disabled | Disabled | Disabled | Enabled | Enabled |
| Connect/Disconnect | Enabled | Disabled | Disabled | Disabled | Disabled | Enabled | Enabled |
| Netlist browse | Enabled | Disabled | Disabled | Disabled | Disabled | Enabled | Disabled |
| Test mode checkboxes | Enabled | Disabled | Disabled | Disabled | Disabled | Enabled | Disabled |
| Threshold fields | Enabled | Disabled | Disabled | Disabled | Disabled | Enabled | Disabled |
| START button | Enabled* | Disabled | Disabled | Disabled | Disabled | Enabled* | Disabled |
| STOP button | Disabled | Enabled | Enabled | Enabled | Enabled | Disabled | Disabled |
| Progress bar | Hidden | Visible | Visible | Visible | Visible | Hidden | Hidden |
| HV status bar | Hidden | Hidden | Hidden | Hidden | Visible | Hidden | Hidden |

*START enabled only when: COM port connected AND netlist loaded.

**GUI-STM-001** — State transitions shall be signalled by `TestEngine.stateChanged(TestState)` and connected to `MainWindow.onStateChanged()` which applies the above enable/disable rules.

**GUI-STM-002** — During FAULT state, the entire left panel is overlaid with a semi-transparent red tint and the message "FAULT — Acknowledge to continue" until the Fault Dialog is dismissed.

---

## 13. Signal / Slot Architecture

All cross-thread communication uses Qt signals emitted from worker threads and connected to GUI slots on the main thread.

### 13.1 SerialWorker Signals

| Signal | Payload | Connected To |
|---|---|---|
| `statusReceived` | `FirmwareStatus` dataclass | `LeftPanel.onStatusReceived` |
| `contResultReceived` | `ContResult` dataclass | `ResultModel.appendResult`, `MatrixView.updatePin` |
| `shortResultReceived` | `ShortResult` dataclass | `ResultModel.appendResult`, `MatrixView.updatePin` |
| `hvResultReceived` | `HVResult` dataclass | `ResultModel.appendResult`, `MatrixView.updatePin` |
| `scanComplete` | `ScanSummary` dataclass | `TestEngine.onScanComplete` |
| `progressUpdate` | `(done: int, total: int)` | `ProgressBar.setValue` |
| `faultReceived` | `FaultEvent` dataclass | `TestEngine.onFault` |
| `connectionLost` | (none) | `TestEngine.onConnectionLost` |
| `rawPacketLogged` | `(direction: str, hex: str)` | `LogPanel.appendLine` |

### 13.2 TestEngine Signals

| Signal | Payload | Connected To |
|---|---|---|
| `stateChanged` | `TestState` enum | `MainWindow.onStateChanged` |
| `verdictReady` | `Verdict` enum | `VerdictLabel.setVerdict` |
| `calibrationComplete` | `(offset_mohm: int)` | `LeftPanel.onCalibrationResult` |

---

## 14. Accessibility

**GUI-ACC-001** — All interactive controls shall have `setToolTip()` set with a brief plain-language description.

**GUI-ACC-002** — All interactive controls shall have `setAccessibleName()` set for screen reader compatibility.

**GUI-ACC-003** — Colour is never the sole indicator of state (e.g., PASS/FAIL labels include text, not just colour).

**GUI-ACC-004** — Minimum font size across the entire application: 9pt. User can override via OS accessibility settings; the application shall respond to `QApplication.setFont()`.

**GUI-ACC-005** — Tab order within each panel shall follow a logical top-to-bottom, left-to-right sequence.

---

## 15. Requirement Traceability

| GUI Req ID | SRS Req ID | Description |
|---|---|---|
| GUI-CON-001 | PC-APP-002 | Auto-detect CH340G/CP2102 COM ports |
| GUI-CON-002 | PC-COM-007 | Connection status display |
| GUI-NL-001..004 | PC-NL-001..003 | Netlist load and display |
| GUI-TM-001..003 | PC-TP-001 | Test mode selection |
| GUI-ACT-001..004 | PC-UI-007..009 | START/STOP buttons and progress |
| GUI-MX-001..006 | PC-UI-002..004 | 16×16 matrix view |
| GUI-RT-001..008 | PC-UI-005..006 | Results table |
| GUI-LOG-001..005 | PC-APP-003 | Log panel |
| GUI-SB-001..003 | PC-UI-001 | Status bar |
| GUI-DLG-HV-001..004 | SAF-004..005 | HV confirmation dialog |
| GUI-DLG-FAULT-001..004 | SAF-006, PC-TE-004 | Fault alert dialog |
| GUI-DLG-NL-001..004 | PC-NL-004 | Netlist editor |
| GUI-DLG-GS-001..003 | PC-NL-005 | Golden sample wizard |
| GUI-THM-001..003 | PC-UI-010 | Dark / light theming |
| GUI-STM-001..002 | PC-TE-001 | State-driven UI enable/disable |

---

*Document ID: GUI-REQ-001 | Version 1.0 | 2026-04-21*
