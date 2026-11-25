---
name: matrix-expander-strap-audit
description: Matrix_Card-9 expander addresses as populated and verified 2026-11-20 (U102 0x22, U105 0x24, U69 on BUFF1 0x21); force-sheet labels have an extra 0 and mislead; read DNP crosses
metadata:
  node_type: memory
  type: project
  originSessionId: a7e8908f-1fcc-4d29-943a-55ffa417e05a
  modified: 2026-11-19T19:07:48.082Z
---

**Verified 2026-11-20** (rendered Matrix_Card-9 sheets 3 and 8, DNP crosses read, columns left-to-right = A2, A1, A0, address = 0x20 + A2A1A0 per MCP23017 DS20001952C fig. 3-4) against the user's hardware checklist (Table 11) and the 2026-11-19 bench scan - all three agree:

- Force/BUFF1: **U101 0x20, U69 0x21 (drawn on BUFF1_SDA/SCK, sheet 8), U102 0x22, U105 0x24, U106 0x26.**
- Sense/BUFF2: U66 0x20, U67 0x22, U107 0x24, U108 0x26.
- The user states the current boards follow that checklist.

**Why the old firmware was wrong:** the force-sheet labels (`0x01000010`, `0x01000100`, `0x01000110`) have 8 digits (one 0 too many; sense-sheet labels have 7) and were read as 8-bit control bytes -> 0x21/0x22/0x23. The earlier "match their labels and passed on the bench" note was wrong: 0x21/0x22 ACKed because U69 and U102 really sit there. Old firmware also looked for U69 on the sense segment (from Matrix_Card-7) -> `init FAILED at ads124s08 ... wr 0x21 NAK`. Fixed in CL-103 (image `Built_Image_2026-11-20_address-fix`, not yet run on hardware).

**Open:** cold-start `matrix/force-exp@0x20` failure (NAK, later TIMEOUT) is unrelated to addresses; the matrix-retry image has a retry for it, result unknown.

**How to apply:** when an expander NAKs, decode A2/A1/A0 from the fitted pull-up/pull-down resistors (zoom the strap network with fitz clip), not from the address label, and check which BUFFn the SDA/SCK labels name. See [[schematics-are-source-of-truth]], [[u20-strap-resistors-dnp]], [[matrix-card-kelvin-resistance-rework]].
