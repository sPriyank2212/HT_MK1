# 2 - Connector Configuration

How the connectors of the harness and the test fixture are defined, and how the GUI draws them.

## Files

| File | What it is |
|---|---|
| `Fixture_Connector_Layout_256x256_DRAFT.xlsx` | Reference table for the fixture's 256-pin connector breakdown (4 x 128-pin blocks). **A draft:** part numbers read `AMPHENOL-128CKT (TBD)` and mounting locations are placeholders pending a mechanical decision. |

## Where connector information comes from

The GUI does not need a separate connector file. It reads the **netlist**:

| Netlist column | Meaning |
|---|---|
| `Conn ID`, `Part Number` | the connector at harness end **A** (Side-A, the HI pins) |
| `Conn ID B`, `Part Number B` | the connector at harness end **B** (Side-B, the LO pins) |
| `Src Pin #` / `Dst Pin #` | the pin on each connector |

Side A is drawn as the left column and Side B as the right. A designator used at both ends
(a mated pair's `DB15-1`) is drawn once in each column.

## Connector families

The family is guessed from the part number and drawn with its own outline and icon:

| Family | Part-number keywords | Examples |
|---|---|---|
| D-sub | `DB`, `DE-`, `DA-`, `HD-`, `D-SUB` | `DB9-M-9P`, `DB37-F-37S` |
| Circular | `MS3`, `38999`, `MIL-DTL`, `CIRC`, `M8`, `M12`, `AMPHENOL` | `MS3116F14-19S`, `D38999/26WB35SN` |
| Rectangular | `CPC`, `MOLEX`, `DEUTSCH`, `JST`, `RECT` | `TE-CPC-46S`, `MOLEX-MINIFIT-12` |
| Terminal block | `TERMINAL`, `PHOENIX`, `WAGO`, `MSTB`, `SCREW` | `WAGO-TERMINAL-8` |
| Modular jack | `RJ45`, `RJ11`, `USB`, `ETHERNET` | `RJ45-8P8C-JACK` |

Anything else is drawn as rectangular.

## Confirming the layout

After a netlist is loaded the GUI shows **Confirm the connector layout**: every connector on Side A and
Side B with its guessed family, pin count and part number. Correct the family or label if needed, then Apply.

## Limits of the guess

* **Pin counts come from the pins the file wires.** A connector's block runs from just after the previous
  connector to just before the next one's first wired pin. Unwired trailing pins on the last connector of
  a side are therefore not counted (a DB37 with 20 wired pins is drawn with 20).
* **Wire the first pin of every connector.** A connector whose first pins are unwired looks the same as one
  that starts later, and its block comes out shifted.
* The GUI warns in the log when more pins are wired than the part number has (for example one `Conn ID`
  reused for two different connectors).
* Pin labels printed on the diagram come from `Src Pin Label` / `Dst Pin Label`.
