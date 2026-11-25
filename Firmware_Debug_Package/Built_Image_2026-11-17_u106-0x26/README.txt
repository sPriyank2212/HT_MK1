HT_MK1 debug firmware - 2026-11-17 - "u106-0x26"
================================================

Includes everything in Built_Image_2026-11-17_matrix-bus-scan (reset-cause line,
I2C3 scan, I2C2 scan under the four U20 buffer-enable combinations) plus:

1) U106 (LO_EN17..32, force segment) is now polled at 0x26, was 0x23.
   Client log: "init failed at matrix/force-exp@0x23 ... i2c2 wr 0x23 NAK" after
   U101 0x20, U105 0x22 and U102 0x21 had passed - so the Matrix segment, EN1 and
   the U20 buffer-enable bits all work.
   Matrix_Card-9 sheet 3: R171 + R173 fitted (A2, A1 pull-ups), R177 fitted (A0
   pull-down), R172/R174/R176 DNP  ->  A2:A1:A0 = 1:1:0 = 0x26, the same pattern
   as U108. The label next to U106 (0x01000110 = 0x23) does not match its own
   resistors. Decision 2026-11-17: firmware follows the board.
   (To get 0x23 instead: move R171 -> R172 and R177 -> R176, set
   MATRIX_LO_EN_HI_STRAP back to 3U in matrix_card.h.)

2) The I2C2 scan now also runs when Board_Init fails at the "ads124s08" stage
   (U69, ADC control). Scan lines are named by segment:
     i2c2 scan U20=0x0000 (both off): ...
     i2c2 scan U20=0x0008 (sense/BUFF2): ...
     i2c2 scan U20=0x0080 (force/BUFF1): ...
     i2c2 scan U20=0x0088 (both on): ...

WHAT TO EXPECT / WHAT MAY FAIL NEXT
  Expected: all four force expanders pass, then the sense expanders
  (U66 0x20, U67 0x22, U107 0x24, U108 0x26; all populated to match their labels),
  then U69.
  Likely next failure - U69 (ADC control, 0x21): firmware reaches it through the
  SENSE segment (BUFF2) per Matrix_Card-7, but Matrix_Card-9 draws U69 on
  BUFF1_SDA/SCK, the force bus, at 0x21 - the same address as U102 (LO_EN1..16).
  If the client's card is built to rev 9 the log will say
    BOARD: init FAILED at ads124s08 ... i2c2 wr 0x21 NAK
  and the i2c2 scan will show 0x21 answering under "force/BUFF1" only.
  That is a HARDWARE address clash (U102 and U69 both 0x21 on BUFF1): it needs a
  strap change on U69 or moving it back to BUFF2; do not paper over it in firmware
  until the actual card revision is known.

Not run on hardware. Build: 0 errors, 0 warnings, text 87120 B, data 116 B, bss 41188 B.
Files: HT_MK1.hex / .bin / .elf, SHA256.txt (bin 60f9a171...8d13).
Earlier images and Customer_Package firmware were NOT touched.
