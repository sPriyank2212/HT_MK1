# HT_MK1 Harness Tester - Customer Package

Everything needed to set up and run the HT_MK1 test, in one place.

| Folder | Contents |
|---|---|
| `0_Documents/` | All documents (Word and PDF): overview, user manual, GUI functional description, flashing procedure, functional test procedure, code walkthrough |
| `1_Test_Harness_Plan/` | A blank netlist template and example netlists |
| `2_Connector_Config/` | Connector configuration guide and the fixture connector layout |
| `3_Test_Results/` | Results record sheet and sample reports in the formats the GUI writes |
| `4_GUI_and_Firmware/` | The operator GUI (real and demo) and the firmware image |

## Quick start

1. **Flash the firmware** - `4_GUI_and_Firmware/Firmware/`, following `0_Documents/4_Flashing_Procedure.pdf`.
2. **Start the GUI** - `4_GUI_and_Firmware/GUI/HT_MK1_GUI.exe`, pick the instrument's COM port, Connect.
   (`HT_MK1_GUI_Demo.exe` runs without an instrument, for practice.)
3. **Load a netlist** - make one from `1_Test_Harness_Plan/Netlist_Template.xlsx`, or try an example.
4. **Run Mode 1** (continuity, resistance), then move the harness to the HV connector for **Mode 2**
   (insulation). Read the Safety section of `0_Documents/2_User_Manual.pdf` before Mode 2.
5. **Record the result** - `3_Test_Results/Test_Results_Record.xlsx`, and export the report from the RESULTS screen.

## Versions

| Item | Version |
|---|---|
| Firmware | fw 0.1.0, built from git commit `89c4ebe` |
| GUI | built 2026-10-22 (the exact time is shown in the GUI footer) |
| Documents | Issue 1.1.0 of the manuals (22-10-2026), GUI Functional Description 1.0.0 |

Checksums for every file are in `MANIFEST.txt`.

## Things to know

* `Fixture_Connector_Layout_256x256_DRAFT.xlsx` is a draft: its part numbers are marked TBD.
* The firmware image has been compiled but not yet exercised on a unit.
