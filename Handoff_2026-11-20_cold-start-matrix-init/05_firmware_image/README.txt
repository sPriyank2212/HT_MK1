HT_MK1 firmware - SPI3/AD7476 fix + runs stop on a dead ADC (2026-11-20)
Debug build, 0 errors / 0 warnings. NOT yet run on hardware.

Based on the address-fix image (U102 0x22, U105 0x24, U69 on BUFF1 0x21), plus:
  - SPI3 (Control Card AD7476 U4) reconfigured in Board_Init: 16-bit, CPOL high / CPHA 1st edge, 8 MHz
    (was CubeMX default 4-bit / 32 MHz; every ADC read timed out)
  - continuity discover / verify / manual sweep stop after 8 failed ADC reads in a row with a FAULT
  - discover error counter widened to 32 bit (65,536 errors wrapped to 0 and reported 'PASS 0/0')
