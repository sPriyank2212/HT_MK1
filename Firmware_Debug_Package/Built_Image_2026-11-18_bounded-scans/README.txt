HT_MK1 debug firmware - 2026-11-18 - bounded-scans
Reverted base (no fault module / selfcheck / continue-on-fail) + boot prints + the bus scans back,
but now run from a low-priority thread tScan 1.5 s AFTER the kernel starts (comms answers first),
only if Board_Init failed, holding the hardware mutex. Each scan: 3 ms per address, 1500 ms budget
(BOARD_SCAN_BUDGET_MS), gives up after 3 consecutive HAL_BUSY (BOARD_SCAN_BUSY_MAX) and says why.
Log lines (tag SCAN): start / "i2c3 ...: nothing answers | N ack: 0x.. (ms)" / "i2c2 U20=0x.... (...)" x4 /
"bus BUSY at 0x.." / "TIMEOUT ... stopped at 0x.." / done in N ms. text 88556 B, 0 warnings. Not run on hardware.
