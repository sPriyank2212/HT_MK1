# Memory Index

- [Schematics are source of truth](schematics-are-source-of-truth.md) — finalised KiCad schematics override the stale SAD doc; lists the known SAD mismatches
- [Firmware single-MCU architecture](firmware-single-mcu-architecture.md) — one STM32G474 drives Matrix+HV cards over I2C/SPI; driver stack layout, peripheral map, config caveats
- [Matrix card Kelvin resistance rework](matrix-card-kelvin-resistance-rework.md) — rev 6 schematic went 4-wire Kelvin + 24-bit ADS124S08; mux polarity resolved, three blocking routing gaps
- [Two-stage test workflow](two-stage-test-workflow.md) — DUT moves from the Matrix connector to the HV connector between stages; insulation is gated on stage 1 passing
- [Flutter GUI only](gui-flutter-only.md) — Python gui/ is not used, decided by the user; all GUI work targets gui_flutter/
- [Demo sim --nets must match netlist](demo-sim-nets-must-match-netlist.md) — test_netlists/ fixtures, --sim --nets N must match loaded file's net count or CONT RUN FAILs
- [Client-styled app](client-styled-app.md) — second app in gui_flutter (main_client.dart) with the customer's layout + report format and MK1 tests; what is not done
- [Checkout reconciled with GitHub 2026-11-13](local-checkout-diverged-from-remote.md) — backup folder, Debug/ untracked+ignored, FW-11 configurable decided; HW-15 + I2C3 400 kHz still open
- [U20 strap resistors DNP](u20-strap-resistors-dnp.md) — U20 NAK was DNP R1/R76/R78, not firmware; schematics show no DNP
- [Matrix expander strap audit](matrix-expander-strap-audit.md) — U106 populated 0x26 (firmware follows); U69 on BUFF1 clashes with U102 (open); read DNP crosses, not labels
