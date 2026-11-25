HT_MK1 firmware - Matrix Card expander address fix (2026-11-20)
Debug build, 0 errors / 0 warnings. NOT yet run on hardware.

Changes vs the matrix-retry image (2026-11-18):
  U102 strap 1 -> 2 (0x21 -> 0x22)      LO_EN1..16
  U105 strap 2 -> 4 (0x22 -> 0x24)      HI_EN17..32
  U69  moved from the sense segment to the force segment (BUFF1), still 0x21
  Bus scan (BUS SCAN) now probes U69 on the force segment.
Basis: Matrix_Card-9 address resistors (fitted/DNP) read per MCP23017 datasheet
(0100 A2 A1 A0), the hardware checklist Table 11, and the 2026-11-19 bench scan.
Everything else (cold-start matrix retry, bounded scans in tScan, IODIRA readback) as matrix-retry.
