HT_MK1 firmware - cold-start I2C2 recovery + cold-start record (2026-11-20 15:26, CL-105)
Debug build, 0 errors / 0 warnings. NOT yet run on hardware.

Based on the spi3-adc-fix image, plus:
  - Before EVERY matrix-stage attempt in Board_Init: record I2C2 state (ISR.BUSY, SDA PA8, SCL PC4),
    then I2C2 de-init, bus clear (up to 9 SCL pulses + STOP), RCC reset, re-init.
  - If the boot Board_Init still fails, tScan re-runs Board_Init in the background
    (up to 5 runs, 1 s apart) before the diagnostic bus scans. GUI link is not blocked.
  - One "BOARD: mx a<n> ..." line per attempt: at boot, on the first STATUS after connect,
    on every refused run, and after each background run.
    Legend: b = I2C2 BUSY flag, d = SDA level, c = SCL level, k = bus-clear pulses,
            e = HAL I2C error (04 NAK, 20 TIMEOUT), t = ms since reset.
