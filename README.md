# HT_MK1 — Automated Harness Test System

STM32G474RET6 firmware for a 256-line harness tester: continuity, 4-wire resistance,
and 500 V insulation testing across a Control Card, a Matrix Card and up to four HV Cards.

---

## Where to look

**There are four living documents. Everything else is reference or history.**

| Document | What it is | When you want it |
|---|---|---|
| **[PROJECT_LOG.md](PROJECT_LOG.md)** | Open items, closed items, daily history | **Start here.** "What is the state of things?" |
| **[fw_status.txt](fw_status.txt)** | Firmware and hardware technical reference — bus map, pin map, driver stack | "Which peripheral is which? What did we decide about X?" |
| **[Doc/Harness_Tester_Operation_Document_v1.4.docx](Doc/Harness_Tester_Operation_Document_v1.4.docx)** | How the system is operated: init sequences, test procedures, fault codes | "How is a test actually run?" |
| **[Doc/4wire_resistance_validation.md](Doc/4wire_resistance_validation.md)** | Why the resistance design is what it is, plus the bench evidence and forward risks | "Why was it done this way? What could still go wrong?" |

### Reference — read, do not edit

| | |
|---|---|
| `Doc/*.pdf` | The KiCad schematics. **These are the source of truth.** Where any document disagrees with them, they win |
| `Datasheet/` | Component datasheets, with [DATASHEETS.md](Datasheet/DATASHEETS.md) as the tick-list |
| [Doc/i2c_bus_sharing.md](Doc/i2c_bus_sharing.md) | Why the Matrix Card and every HV card share one I2C address range, and how `HV_Card_EN1-4` gates them apart |
| [Doc/idac_current_source.md](Doc/idac_current_source.md) | Why the DAC8775 is gone and Kelvin excitation now comes from the ADS124S08's own IDAC, the 2 mA ceiling that comes with it, and what firmware still needs to change |

### Work in progress

| | |
|---|---|
| `gui_flutter/` | **Primary GUI build** (decided 2026-08-10) — Flutter/Dart, native Windows exe, no Python at runtime |
| `gui/` | Python GUI (htweb + Tk) — **superseded** by `gui_flutter/`, kept for reference only, not tracked for new work |
| `Doc/HT_MK1_GUI_Proposal.html` | Visual mock-up of the operator GUI |
| `Doc/GUI_development_brief.md` | Build brief for the GUI, including the firmware↔GUI protocol contract |
| `Doc/GUI_protocol_command_coverage.md` | Audit of every `gui_flutter/` control against the protocol — what's wired, what isn't, what should happen |
| `Doc/GUI_protocol_proposed_commands.md` | Proposed new `>` commands for the buttons that need firmware work first |

---

## Current hardware baseline

| Card | File | Notes |
|---|---|---|
| Control | `Doc/Control_Card 1.pdf` | STM32G474, mux addressing via MCP23017 U21, 6 connectors (J1–J6). **DAC8775 removed** — Kelvin excitation now sources from the ADS124S08's own IDAC instead (HW-11 closed; firmware updated, FW-12 closed — see `Doc/idac_current_source.md`) |
| Matrix | `Doc/Matrix_Card-8.pdf` | 128× CD74HC4051, 4-wire sense array, ADS124S08 (U68, sheet 9 — confirmed present, see HW-12); AIN9 now wired to `HI_COM` for the IDAC excitation path |
| HV | `Doc/HV_Card-3.pdf` | 500 V, 64 HS + 64 LS reed relays per card, R3003 = 5 kΩ, confirmed (HW-08 closed) |

**2026-08-12: schematic set replaced again** (`Control_Card-5`/`Matrix_Card-7` → `Control_Card 1`/`Matrix_Card-8`), still uncommitted in the working tree, same-day as `-4`/`2`/`-1` → `-5`/`-7`/`-3` closed out under HW-12. Note the naming break: `Control_Card 1.pdf` doesn't follow the `-N` convention the other files use — worth confirming that's intentional before the next sync. See `Doc/idac_current_source.md` for what changed and why it matters.

## Firmware layout

```
Core/Src, Core/Inc
  drivers/   ads124s08, mcp23017, dac8830, ad7476, ads1232(bench-only)
  cards/     matrix_card, hv_card, control_frontend
  test/      continuity, kelvin, insulation
  bsp/       board            — instantiates and binds everything
  app/       log, tasks       — FreeRTOS threads and the command queue
```

Build in STM32CubeIDE, or from `Debug/` with the bundled toolchain:

```
make all -j8
```

> `drivers/ads1232` is **bench-only** — a validation rig, not product code. It is gated on
> `HT_ENABLE_ADS1232` (default off), compiles to zero bytes when disabled, and a Release
> build with it enabled fails at compile time on purpose.

---

## Document rules

1. **Four living docs, listed above.** If something needs recording, it goes in one of them.
2. **No new parallel documents** without removing one. That is what caused the last clear-out.
3. **Schematics win.** If prose and a PDF disagree, the PDF is right and the prose is a bug.
4. Superseded material is **deleted, not archived** — git history keeps it, and stale files on
   disk get read by mistake.
