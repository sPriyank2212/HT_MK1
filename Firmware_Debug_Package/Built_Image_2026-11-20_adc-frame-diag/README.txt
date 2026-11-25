HT_MK1 firmware - AD7476 raw-frame diagnostics (2026-11-20, CL-108)
Debug build, 0 errors / 0 warnings. NOT yet run on hardware.
Adds to CL-107: idle line prints the raw 16-bit AD7476 frame (expect 0x0FFF when open);
scan summary counts frames whose 4 leading bits are not 0 (expect 0). Verdicts unchanged.
