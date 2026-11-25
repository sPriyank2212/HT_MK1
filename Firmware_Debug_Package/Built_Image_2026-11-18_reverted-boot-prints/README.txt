HT_MK1 debug firmware - 2026-11-18 - "reverted-boot-prints"
===========================================================
The selfcheck image (2026-11-17) and the fault-reporting image (2026-11-18) did
not let the GUI connect. Both sets of changes are REMOVED:
  - fault module (fault.c/h), HardFault/etc. trampolines, .noinit section,
    Default_Handler change, assert/malloc/overflow hook changes
  - Board_SelfCheck, tSelfChk thread, continue-on-fail Board_Init
This is the "u106-0x26" firmware (text 87120 B, bss 41188 B, identical bss) plus
three plain boot prints (+160 B text):
  #[boot] main: peripherals up, Board_Init start
  #[boot] main: Board_Init done, starting scheduler
  #[boot] tasks created
(together with the existing "#[boot] console up" / DIAG failure lines.)
Command handling, file:line failure logging (LOG_E/DIAG) and the U106 0x26 strap
are unchanged. Not run on hardware. Build: 0 errors, 0 warnings.
