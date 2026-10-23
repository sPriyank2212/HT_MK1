# Release v1 - HT_MK1 Harness Tester

Prepared by Atulya Core Tech (ACT) for Infinity Integrations Pvt Ltd

## Contents

| Item | Where |
|---|---|
| Documents (Word + PDF) | `0_Documents/` |
| Netlist template and examples | `1_Test_Harness_Plan/` |
| Connector configuration notes | `2_Connector_Config/` |
| Results record and sample reports | `3_Test_Results/` |
| Firmware image and GUI (real and demo) | `4_GUI_and_Firmware/` |

## What this release includes

* Mode 1 (continuity, resistance), Mode 2 (insulation test) and Auto scan in the GUI.
* HV safety: arm and confirm before energizing; the HV rail is checked before and after every
  insulation reading and proven discharged before the relays open; any HV-path error latches a
  fault and stops the run; an idle live rail latches a fault; an independent watchdog resets a
  hung controller.
* GUI: Stop and Esc abort the instrument; Run is disabled without a link; every completed run is
  saved automatically as CSV and PDF (`%LOCALAPPDATA%\HT_MK1\reports`).

## Before first use

* The firmware image has been compiled and its logic tested on a PC. It has **not** yet been run on
  a unit: perform the bring-up and the Functional Test Procedure (`0_Documents/5_Functional_Test_Procedure`)
  first.
* There is no hardware interlock signal; the GUI shows "Interlock closed: unverified".
* The HV rail thresholds and time-outs are intended values to be confirmed on a real card.
* `Fixture_Connector_Layout_256x256_DRAFT.xlsx` is a draft.

The firmware source commit is recorded in `4_GUI_and_Firmware/Firmware/FIRMWARE_INFO.txt`.
