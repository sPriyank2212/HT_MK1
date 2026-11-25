# Prompt for the next chat (copy everything below the line)

---

You are continuing bench bring-up of the HT_MK1 harness tester (STM32G474 FreeRTOS firmware + Flutter GUI in `gui_flutter/`). Project root: this repo. Branch `fw/doc-reconciliation-2026-07-14`; none of the work from 2026-11-17..20 is committed. The client has only the Matrix card (no HV card). Everything you need is in `Handoff_2026-11-20_cold-start-matrix-init/` (read `README.md` there first, then the memory notes in `06_project_memory_notes/`). Read `03_docs_and_datasheets/Harness_Tester_Power_Jumper_Resistance_Checklist.docx` (the user's doc of which resistors/straps are fitted where; the boards follow it) as well as the log files and screenshots yourself; do not rely on this summary alone.

## Reference documents (read these before reasoning about the hardware)

All paths are inside `Handoff_2026-11-20_cold-start-matrix-init/03_docs_and_datasheets/`:

1. **`Harness_Tester_Power_Jumper_Resistance_Checklist.docx`** (text copy: `checklist_extracted_text.txt`) - the user's own document of which resistors, straps, jumpers and option parts are fitted where on each card. The user states the current boards follow it exactly. Table 6 = Control Card jumpers/straps (U20 address straps), Table 11 = Matrix Card MCP23017 address straps (columns A2, A1, A0; one pull-up and one pull-down footprint per pin, solder one of each pair). It is the source of truth for what is actually populated, over the schematic PDFs (which carry no DNP information).
2. **`Matrix_Card-9.pdf`** (text export `matrix_card.txt`) - Matrix card schematic. Relevant sheets: 3 (force/sense expanders and strap networks), 8 (BUFF1_SDA/SCK and BUFF2 buffers, U69), U103 ADuM1250 with R120/R121, U141/U142 NTS0102 level translators with 2.2 kOhm B-side pull-ups. Force-sheet net labels such as `0x01000010` have one extra 0; do not read them as 8-bit control bytes (see the memory note `matrix-expander-strap-audit.md`). Decode addresses from the fitted strap resistors (DNP crosses).
3. **`Control_Card-6.pdf`** (text export `control_card.txt`) - Control Card schematic. Relevant: sheet 11 (U20 MCP23017 on I2C3 and its A0-A2 straps R1/R76/R78), U5 ADuM1250 and R9/R10 on ISO_SDA3/SCL3, the HV_Card_EN1..EN4 / J1..J4 slot lines, U4 AD7476 (SPI3).
4. `i2c_bus_sharing.md` - how the Matrix card and HV cards share I2C2 behind HV_Card_EN1.
5. `20001952C.pdf` - MCP23017 datasheet (address = 0x20 + A2A1A0; power-on state: all pins inputs); `ad7476_7477_7478.pdf` - AD7476 datasheet.
6. `hardware_test_plan_2026-11-13.md`, `GUI_development_brief.md`, `PROJECT_LOG.md` (CL-102..104 are the latest entries).

Render PDF pages with PyMuPDF (`fitz`) and zoom (clip) on the strap networks and buffer sections; do not trust text exports alone for DNP crosses or resistor values.

## Problem to resolve (primary)

**Cold-start failure of the Matrix card.** After a power-up (cold start) `Board_Init` fails at `matrix/force-exp@0x20` (U101, MCP23017 on I2C2 behind the force buffer BUFF1), the board is marked not ready, and every `CONT RUN` is refused with `EHW board init failed at matrix/force-exp@0x20 (hal=1) mcp23017.c:39 i2c2 TIMEOUT` (earlier images showed `NAK` at the same place). Pressing the Control Card reset switch (MCU reset only) makes the next boot succeed: `BOARD: init ok: matrix, ads124s08, frontend`. The 5 x 250 ms retry in `Board_Init` (board.c, `BOARD_MATRIX_TRIES`/`BOARD_MATRIX_RETRY_MS`) did not cure it. Latest evidence: `01_logs/harness_tester_log_2026-11-20_14-57-51_LATEST.txt` (refused at 14:56:09 and 14:56:35, reset at 14:56:47, init ok afterwards). The first boot's own log is NOT in that file (the GUI connected afterwards), so whether the retries ran and how each attempt failed on the cold boot is **not known**.

Goal: the board comes up ready on a cold start with no reset-switch workaround, OR, if that cannot be achieved in firmware, the exact cause is identified from evidence and the workaround is made unnecessary or visible in the GUI.

### What is established (verified; do not re-derive)
- Matrix expander addresses are correct and match schematic, datasheet DS20001952C, the user's checklist and the 2026-11-19 bench scan: force/BUFF1 U101 0x20, U69 0x21 (ADC control), U102 0x22, U105 0x24, U106 0x26; sense/BUFF2 U66 0x20, U67 0x22, U107 0x24, U108 0x26. U20 (Control Card, I2C3) 0x20. See `06_project_memory_notes/matrix-expander-strap-audit.md`.
- After a reset the whole init passes, so addresses, strap resistors and the I2C2 wiring are fine in the warm case.
- The ISO_SDA3/SCL3 pull-up conflict (Control Card vs Matrix R120/R121) was fixed on the bench (2.2 kOhm now). It did not change the cold-start failure.
- U20 and the Matrix card keep their state across an MCU reset; after power-up they are at defaults. `board_init_matrix` -> `MatrixCard_Init` (matrix_card.c:262): U20 init + `matrix_flush_select` (both segments OFF) -> `MatrixCard_BusClaim` (EN1 high, `MATRIX_BUS_EN_SETTLE_MS` = 1 ms) -> `MatrixCard_SelectSegment(FORCE)` (U20 bit 7) -> force expander init at 0x20 -> fails.

### Hypotheses (all UNTESTED; do not state any as the proven cause)
1. The retry loop re-runs `MatrixCard_Init`, whose first act is `matrix_flush_select` (disables both buffers), so every retry restarts the buffer/level-translator settling and no attempt ever sees a buffer that has been enabled for long. After a reset the buffers are already enabled (U20 kept its state), which would explain why a warm boot passes.
2. I2C2 is stuck busy / SCL or SDA held low at power-up (a TIMEOUT rather than a NAK points at a busy bus); an I2C2 re-init and/or 9-clock bus clear before the first transaction might fix it.
3. The 1 ms settle after EN1 high, and the time after enabling BUFF1 via U20, is too short for the isolated side (ADuM1250 / NTS0102 U141/U142 with their 2.2 kOhm B-side pull-ups) after cold power-up.
4. EN1 (HV_Card_EN1) or the I2C2 pins have a different power-up state/ordering than assumed (check `gpio.c`, `i2c.c`, `main.c` init order).

### Suggested approach
- First make the failure observable: capture the cold-boot log. The GUI only connects after the boot, so add a boot-failure record that survives until the GUI connects (e.g. keep the first-failure text, attempt number and SDA/SCL pin levels in the existing diag/`BOARD:` event and re-print it on `STATUS`/connect), and log I2C2 SDA/SCL pin levels (read as GPIO) at the moment of failure. Use the existing diag helpers (`DIAG_ST`, file:line reporting) - failures must stay identifiable with file:line.
- Then choose the smallest fix that the evidence supports, e.g.: do NOT flush/disable the buffers on retries (enable once, wait, retry only the expander probe); re-init I2C2 + bus-clear between attempts; lengthen the settle after enabling BUFF1; and/or re-run `Board_Init` (bounded) when a run is requested while the board is not ready, instead of refusing forever. Compare against what the reset switch changes (MCU state only).
- Keep the minimum delays needed so GUI communication keeps working (user requirement); do not add long blocking waits before the console is up.

## Secondary items (only after the primary one, or if they block it)
1. **Auto-Scan with a jumper.** The last log was saved at progress 19/256 (scan takes ~13 min: 256 rows x ~3.07 s), so there is still no result. With the `spi3-adc-fix` image (`05_firmware_image/`) no ADC fault appeared in the first 19 rows. Needs a complete run with one jumper between one Side-A and one Side-B pin, then Save Log after `!DONE cont`. The jumper in the earlier photo was never confirmed to join one Side-A and one Side-B pin.
2. SPI2 (HV AD7476/DAC8830) is still at CubeMX defaults (`spi.c`); the SPI3 fix (16-bit, CPOL high, CPHA 1st edge, /8) is in `board_init_frontend()` only. HV card is not fitted, so this is not blocking.
3. GUI handshake blip `<ERR ESYNTAX empty>` on the first `>STATUS` after connect (harmless, costs one retry).
4. The Control Card pull-up resistor that was removed on ISO_SDA3/SCL3 was never named by the user (R9/R10 per netlist text is a guess); checklist item CC-S06 wording conflicts with that fix and omits U103 R120/R121.
5. U68 ADS124S08, U4 AD7476 values, HV card and DS18B20 have never been verified on hardware.

## Rules for this project (standing user preferences)
- Schematics/finalised KiCad PDFs and the bench are the source of truth, not the stale SAD doc. Read DNP crosses on the strap resistors, not the address labels.
- Deliver firmware to the user ONLY as `HT_MK1.hex` and `HT_MK1.bin`, zipped inside one folder whose name carries the date and time, containing no other files (send with SendUserFile). Also keep a copy under `Firmware_Debug_Package/Built_Image_<date>_<name>/` with SHA256.
- GUI is Flutter only (`gui_flutter/`); the Python `gui/` is unused.
- Do not claim an inference as proven cause. Say what failed, where (file:line) and how you know. Keep status messages short.
- Do not commit or push unless the user asks. Add a `PROJECT_LOG.md` row (CRLF file; newest row above the previous CL row; last used CL-104) for each change.

## Build (this machine)
```
export PATH="/c/ST/STM32CubeIDE_1.19.0/STM32CubeIDE/plugins/com.st.stm32cube.ide.mcu.externaltools.make.win32_2.2.100.202601091506/tools/bin:/c/ST/STM32CubeIDE_1.19.0/STM32CubeIDE/plugins/com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32.14.3.rel1.win32_1.0.100.202602081740/tools/bin:$PATH"
touch Core/Src/app/build_info.c
cd Debug && make -j8 all
arm-none-eabi-objcopy -O ihex HT_MK1.elf HT_MK1.hex && arm-none-eabi-objcopy -O binary HT_MK1.elf HT_MK1.bin
```
Use MSYS `/c/...` paths (a `C:` path breaks the bash PATH). Working-tree files are CRLF except `Core/Src/bsp/board.c` (LF): preserve each file's line endings. Python: run without `-I` for PyMuPDF (`fitz`); set `PYTHONIOENCODING=utf-8`.

## What I need back
1. A short statement of the identified (or still unknown) cause of the cold-start failure with the evidence.
2. The fix (or the diagnostic image if the cause still cannot be determined), built with 0 errors / 0 warnings, delivered per the rules above.
3. A precise test procedure for the user: cold start (power off/on, no reset switch), connect GUI, Auto-Scan with the jumper, Save Log, and what lines to look for.
