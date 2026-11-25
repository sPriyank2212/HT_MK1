HT_MK1 firmware - faster Auto-Scan + I2C 400 kHz (2026-11-20, CL-106)
Debug build, 0 errors / 0 warnings. NOT yet run on hardware.

Includes the cold-start I2C2 recovery image (CL-105), plus:
  - Auto-Scan and Manual Sweep scan row by row: HI stays connected for the row, only LO moves
    (3 I2C writes per pair instead of ~13), EN1 held for the row (no 1 ms settle 3x per pair).
  - I2C2 and I2C3 at 400 kHz (TIMINGR 0x10C7172C, set in Board_Init). board.h BOARD_I2C_FAST 0 = 100 kHz.
  - First STATUS after connect logs "i2c 400k".
Unchanged: continuity analogue settle (2 ms), netlist continuity, resistance, insulation.
