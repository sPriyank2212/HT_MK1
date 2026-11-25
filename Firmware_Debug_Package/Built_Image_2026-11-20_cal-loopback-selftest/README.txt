HT_MK1 firmware - calibration loopback off at boot + continuity self-test (2026-11-20, CL-109)
Debug build, 0 errors / 0 warnings. NOT yet run on hardware.
U69 now parks HI_EN_INT_1, LO_EN_INT_1 and both sense cal enables OFF (they were ON = HI_COM tied to LO_COM via R2065).
Auto-Scan / Manual Sweep start with a self-test: loopback open (expect >=3000 mV) then R2065 closed (expect 20..500 mV);
if it fails the run stops with F01 instead of scanning. Raw AD7476 frame printed on both lines.
