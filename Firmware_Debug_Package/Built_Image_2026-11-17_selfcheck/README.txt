HT_MK1 debug firmware - 2026-11-17 - "selfcheck"   (TEMPORARY bring-up image)
==============================================================================

Goal: ONE boot / ONE connect tells you every peripheral that is working and every
one that is not, instead of stopping at the first failure.

Includes: U106 polled at 0x26, I2C3/I2C2 scans, reset-cause line, file:line DIAG
logging (everything in Built_Image_2026-11-17_u106-0x26).

NEW (two temporary switches in Core/Inc/bsp/board.h, set to 0 to remove):

1) BOARD_INIT_CONTINUE_ON_FAIL
   Board_Init() no longer stops at the first failed stage: matrix, ads124s08 and
   frontend all run, so each logs its own DIAG chain (file:line, bus, address,
   error). The FIRST failure is still what "init FAILED at ..." names. The board
   is still NOT ready if any stage failed - hardware commands stay refused.

2) BOARD_SELFCHECK  ->  Board_SelfCheck()
   Runs in its own low-priority thread tSelfChk:
     - once, 2.5 s after boot
     - again on every host ">ID" (= every GUI connect), so the table appears in the
       GUI log / Save Log without pressing reset
   It takes the hardware mutex (skips if a test owns the hardware) and is READ-ONLY:
   register reads and conversion reads only - no relay, mux or HV output written.

   Output (OK = info, FAIL = error/red, skip = warning):
     CHK === SELF-CHECK (temporary) - Board_Init first failure: <where> ===
     CHK OK   U20  i2c3 0x20
     CHK OK   U101 i2c2 force/BUFF1 0x20
     CHK FAIL U106 i2c2 force/BUFF1 0x26 NAK
     CHK OK   U66  i2c2 sense/BUFF2 0x20
     ...
     CHK FAIL U69  i2c2 sense/BUFF2 0x21 NAK
     CHK WARN info: extra ack on force/BUFF1: ...    (clash / unexpected part)
     CHK OK   U68  SPI1 ADS124S08 id=0x00        or  skip ... init stage failed
     CHK OK   U4   SPI3 AD7476 code=0x...
     CHK skip HV1  not fitted (0/8 expanders answer) - fine for Matrix-only
     CHK OK   U2   1-Wire DS18B20 24.5 C         or  FAIL no presence / bad CRC
     CHK === DONE: n ok, n FAIL, n skip ===
     CHK FAILED: U106 U69 ...

   What each line proves:
     U20            I2C3 data transaction to the Control Card select expander
     U101..U108,U69 a real register READ (IOCON) on that expander, through its
                    own segment (force = BUFF1, sense = BUFF2), so it also proves
                    EN1 + the U20 buffer-enable bit + the isolator + the strap
     "extra ack"    any other address answering on a segment, e.g. U69 and U102
                    both at 0x21 on BUFF1 (Matrix_Card-9) - see below
     U68 (ADS124S08) SPI1 ID register, needs U69 reachable (chip-select via U69)
     U4 (AD7476)    one SPI3 conversion read
     HV1            all 8 relay expanders 0x20-0x27 behind EN1 (Matrix segment
                    taken off the bus first, HW-15); if fitted, the two SPI2 ADCs
                    (DAC8830 is write-only: reported as skip)
     U2 (DS18B20)   presence + CRC of one temperature read (~750 ms)

   Known limits: U68 cannot be tested while U69 is unreachable (rev-9 BUFF1/0x21
   clash or a dead U69) - it prints "skip", and the U69 FAIL line says why. The
   DAC8830 and the HV rails/relays are not exercised (read-only by design).

Expected on the client's Matrix-only bench: U20 OK, U101/U102/U105/U106/U66/U67/
U107/U108 OK, then U69 / U68 are the open question (Matrix_Card-9 draws U69 on
BUFF1 at 0x21, the same as U102; firmware reaches it via BUFF2).

Not run on hardware. Build: 0 errors, 0 warnings, text 92616 B, data 116 B, bss 41196 B.
Files: HT_MK1.hex / .bin / .elf, SHA256.txt (bin a216166d...c877).
Earlier images and Customer_Package firmware were NOT touched.
