HT_MK1 debug firmware - 2026-11-17 - "matrix-bus-scan"
=====================================================

Includes everything in Built_Image_2026-11-17_i2c3-scan (U20 at 0x20, file:line
logging, I2C3 scan on a Matrix-stage failure) plus two boot-log additions.

Bench state this was built for (client log, init-diag image):
  U20 now ACKs at 0x20, and Board_Init fails one step later:
    init failed at matrix/force-exp@0x20 (hal=1) first: mcp23017.c:39 i2c2 NAK
  i.e. the Matrix card's first force expander (U101) does not answer on the
  shared I2C2 bus. Also: the host link drops ("link lost, errno 0") shortly
  after the first refused command; cause unknown.

1) Reset cause, at boot:
     BOOT: reset cause: BOR/POR PIN        (normal power-up)
     BOOT: reset cause: IWDG               (watchdog reset)
     BOOT: reset cause: BOR/POR            (brown-out / power dip)
   A reset right when the link drops would show up here on the next connect.

2) I2C2 scan, only when the Matrix stage fails PAST U20. With the Matrix
   segment claimed (EN1 high) U20's two buffer-enable bits (bit 3, bit 7) are
   driven through all four combinations and I2C2 0x08-0x77 is scanned under each:
     i2c2 scan U20=0x0000 (both off): none
     i2c2 scan U20=0x0008 (bit3 only): none
     i2c2 scan U20=0x0080 (bit7 only): none
     i2c2 scan U20=0x0088 (both on): none
   How to read it:
     none in all four      -> nothing electrically reaches the card on I2C2:
                              card unpowered / unseated, or ISO_SDA2/SCL2 not
                              connected (Control slot pins 21/23 vs Matrix J101
                              pins 35-38 - see PROJECT_LOG HW-03)
     acks only under one   -> the enable bit or its polarity is not what the
                              firmware assumes (matrix_card.h BUFF1/2_OE_BIT,
                              MATRIX_SEG_OE_ACTIVE_HIGH)
     acks under "both off" -> buffers are bypassed / something else drives the bus
   The scan writes only U20 (channel bits 0), writes no Matrix expander, and
   leaves the buffers disabled and the segment released afterwards.

Not run on hardware. Build: 0 errors, 0 warnings, text 87060 B, data 116 B, bss 41188 B.
Files: HT_MK1.hex / .bin / .elf, SHA256.txt (bin 43b8a942...b997).
Earlier images and Customer_Package firmware were NOT touched.
