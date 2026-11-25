HT_MK1 debug firmware - 2026-11-17 - "i2c3-scan"
===================================================

Same as Built_Image_2026-11-16_init-diag (U20 at 0x20, detailed file:line logging,
Matrix-only bring-up) plus ONE addition for the open bench problem:

  If Board_Init fails inside the Matrix stage, the boot log now also prints
  who answers on I2C3 (U20's own local bus):

    i2c3 scan: nothing answers (U20 off/unfitted/reset?)      -> no device on the bus at all
    i2c3 scan: 1 ack: 0x2N; U20 wants 0x20                    -> U20 is alive but strapped to 0x2N

Why: the previous log showed  "init failed at matrix/U20@0x20 (hal=1) ... i2c3 NAK".
A NAK (not BUSY / ARLO / timeout) means SDA and SCL are idle-high and the address
phase ran; nothing acked 0x20. The scan tells a wrong address strap from a dead part.

Not run on hardware. Build: 0 errors, 0 warnings, text 86104 B, data 116 B, bss 41188 B.
Files: HT_MK1.hex / .bin / .elf, SHA256.txt (bin 898f3874...2504c).
The previous image and Customer_Package firmware were NOT touched.
