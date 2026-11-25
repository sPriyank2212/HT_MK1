HT_MK1 debug firmware - 2026-11-18 - no-boot-scans
reverted-boot-prints image, minus the I2C3/I2C2 bus scans that Tasks_Init ran before the scheduler started.
Bench logs (both previous images) ended at "Tasks_Init: bus scans" / "tasks created" with no scheduler output.
Adds a last print: #[boot] Tasks_Init done, starting scheduler. text 86488 B, 0 warnings. Not run on hardware.
