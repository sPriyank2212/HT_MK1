HT_MK1 firmware - continuity diagnostics (2026-11-20, CL-107)
Debug build, 0 errors / 0 warnings. NOT yet run on hardware.
Includes CL-105 (cold-start recovery) and CL-106 (row scan, I2C 400 kHz), plus:
  Auto-Scan and Manual Sweep log:
    CONT: idle (matrix open) N mV        - front end alone, expect ~3300
    CONT: anomaly hi-lo N mV (code C)    - first 12 readings outside open/connected bands
    CONT: reads: open= pass= low<20mV= mid= err=
    CONT: min N mV at hi-lo, max N mV at hi-lo
  Verdicts unchanged.
