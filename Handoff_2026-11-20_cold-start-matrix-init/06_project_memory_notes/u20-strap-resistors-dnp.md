---
name: u20-strap-resistors-dnp
description: "Control Card U20 (I2C3 0x20) NAK was caused by DNP strap resistors R1/R76/R78, not firmware; schematic PDFs carry no DNP info"
metadata:
  node_type: memory
  type: project
  originSessionId: a7e8908f-1fcc-4d29-943a-55ffa417e05a
  modified: 2026-11-19T12:27:58.423Z
---

The 2026-11-16/17 bench failure `matrix/U20@0x20 ... i2c3 NAK` was **board assembly**: the user reported strap resistors **R1, R76 and R78** (U20's A0/A1/A2 resistors, Control_Card-6 sheet 11) were DNP. Firmware address 0x20 (`MATRIX_SEL_MCP_STRAP` 0) was already right and stays.

**Why:** the schematic PDFs have no DNP marks and the repo has no BOM, so a NAK from a part whose address and bus are verified on paper can be a population problem. U20 passes in the next log; the failure then moved to the Matrix card's first force expander (U101, 0x20 on I2C2) - see [[matrix-card-kelvin-resistance-rework]] for the card.

**Also (2026-11-19, CL-102):** the ISO_SDA3/SCL3 line (I2C3 link to U20) had pull-ups on both the Control Card (to normal +5V) and the Matrix Card R120/R121 (to isolated +5V). Final fix: Matrix R120/R121 kept, the Control Card pull-up removed (reference not named by the user; R9/R10 per netlist text, unconfirmed) -> 2.2 kOhm. The build differs from the PDFs. It did not change the I2C2 failures (U101 cold start, U69 0x21 NAK): the scan shows an extra device at 0x24 on the force bus, probably U69 - see [[matrix-expander-strap-audit]].

**How to apply:** when a verified-address expander NAKs, ask about / check the DNP state of its A0-A2 strap resistors, pull-ups and RESET pull-up before changing firmware. The Matrix card has the same kind of strap/pull-up resistors (U101 area, R107-R109, BUFF SDA/SCK pull-ups). See [[schematics-are-source-of-truth]] - the schematic is right about addresses, but not about what is actually fitted.
