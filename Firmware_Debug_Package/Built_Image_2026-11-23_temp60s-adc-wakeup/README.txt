HT_MK1 firmware - ADC wake-up read + 60 s board temperature (2026-11-23, CL-112)
Debug build, GCC 14.3.rel1, 0 errors / 0 warnings. text 96 864 B. NOT yet run on hardware.
- AD7476 dummy conversion at start-up (first reading after boot was 0x0FFF on the bench).
- Close path logs two readings: after the normal 2 ms settle and again +20 ms.
- DS18B20 read every 60 s while idle, printed as "TEMP periodic: board temperature xx.x C";
  never during a test or while a manual path is held. TEMP READ no longer releases a held path.
Includes CL-105..CL-111. Works with Harness_Tester.exe built 2026-11-23 16:20.
