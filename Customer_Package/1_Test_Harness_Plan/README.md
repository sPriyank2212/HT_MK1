# 1 - Test Harness Plan

How a harness is described to the HT_MK1 and how the test is run. The formal test plan, `5_Functional_Test_Procedure`, is in `../0_Documents/` (its `.docx` has the result tables to fill in).

## Files

| File | What it is |
|---|---|
| `Netlist_Template.xlsx` | Blank netlist in the format the GUI reads, with a worked-examples sheet and a read-me sheet. |
| `Example_Netlists/` | Ready-to-load netlists - see the table below. |

## The test sequence

The GUI runs the test in two modes, with the harness on one connector at a time:

| GUI | Test | Harness on | Needs |
|---|---|---|---|
| **Mode 1** | Continuity, then Resistance | Matrix connector (J-MTX) | MTX netlist |
| **Mode 2** | Insulation test (up to 500 V DC) | HV connector (J-HV) | HV netlist |
| **Auto Scan** | Finds which pins are connected, with no netlist | Matrix connector (J-MTX) | nothing |

* Mode 2 is normally unlocked only after Mode 1 passes and the harness is moved to J-HV. The operator
  can choose **Continue anyway** to run insulation without Mode 1; the skipped tests are logged.
* Auto Scan is a survey, not a pass/fail test. Its result can be saved as a netlist.
* The insulation test applies high voltage: read the Safety section of the User Manual (`../0_Documents/2_User_Manual.pdf`) first.

## Preparing a netlist for a new harness

1. Copy `Netlist_Template.xlsx` and fill the `NETLIST` sheet - one row per connection.
2. Load it in the GUI (NETLIST screen, or the Select button on the Continuity screen).
3. Check the **Confirm the connector layout** dialog, then run Mode 1.

**Pin numbers.** `Src Pin #` is the Side-A (HI) pin and `Dst Pin #` the Side-B (LO) pin, each 1..256 and
numbered independently. Inside one side the connectors are numbered one after another.

**Wiring scenarios.** Rows that share a `Net` name are one net:

| Scenario | In the file | Drawn as |
|---|---|---|
| plain wire | one row | a single wire |
| crossed pins | Connector Detail `crossed pin 5 -> 8` | wire to a different pin number |
| Y branch (1 to N) | N rows, same Net, same Src Pin # | a trunk to a spine, one branch per destination |
| merge (N to 1) | N rows, same Net, same Dst Pin # | the Y mirrored |
| multi-drop bus | rows sharing a Net on both ends | a node every wire meets at |
| inline splice | Connector Detail `inline butt splice` | a splice bar on the wire |

A net with several branches fails if any branch fails; each branch is coloured on its own.

## Example netlists

| File | Pairs | Shows |
|---|---|---|
| `Reference_3_connector_example.xlsx` | 20 | The operator-supplied reference: two DB15 and a DB9, Y branches, crossed pins |
| `Reference_full_256x256.xlsx` | 256 | Every one of the 256 HI / 256 LO pins, straight through |
| `HW-01_dsub_family_mated_pairs.xlsx` | 136 | DB9/15/25/37/50, same designators at both ends, null-modem crossings |
| `HW-02_circular_connectors.xlsx` | 51 | MS3116, MIL-DTL-38999, M12, M8; Y power/ground, twisted pairs |
| `HW-03_rectangular_connectors.xlsx` | 72 | TE CPC, Molex Mini-Fit, Deutsch DT, JST XH, Amphenol rectangular |
| `HW-04_terminal_blocks_and_modular_jacks.xlsx` | 46 | Phoenix / WAGO terminal blocks, RJ45 (straight and crossover), RJ11, USB |
| `HW-05_y_joints_branch_and_merge.xlsx` | 52 | Y joints 1:2, 1:3, 1:4, 1:6 and N:1 merges |
| `HW-06_inline_splices_crossed_and_spares.xlsx` | 16 | Inline splices, crossed wires, spare pins |
| `HW-07_multidrop_buses.xlsx` | 28 | CAN, RS-485, ground and power buses |
| `HW-08_mixed_avionics_harness.xlsx` | 74 | Every connector family and joint in one harness |
| `HW-09_density_stress_5_types.xlsx` | 256 | Full-density case across seven connectors of five families |

The `HW-*` files are demonstration harnesses for trying out the software (they also work against the
built-in demo). The functional test procedure needs your own known-good reference netlist and
fault variants.
