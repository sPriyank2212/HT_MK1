# Handoff 2026-11-20 - Matrix cold-start init failure

Start with `00_START_HERE_PROMPT.md` (paste it as the first message of the next chat). Copies only: the originals stay where they are in the repo; nothing here is committed.

| Folder | Contents |
|---|---|
| `01_logs/` | GUI log files saved by the user. `..._14-57-51_LATEST` is the newest (cold start refused, reset, scan started, cut at 19/256). `10-14-09` is the long 67-minute false-PASS scan (SPI3 misconfig). `17-52-45` is the pull-up-fix run. `17-48-37`, `15-18-24`, `17-01-15` are older cold-start/NAK logs. Extracted from the session transcript, so formatting may differ slightly from the original files. |
| `02_screenshots/` | Bench/GUI screenshots 2026-11-17..18 (cold-boot failure on GUI + PuTTY, refusal, reset, bus scans, Auto-Scan view). The 2026-11-20 screenshots and bench photo of the jumper were not available as files. |
| `03_docs_and_datasheets/` | **`Harness_Tester_Power_Jumper_Resistance_Checklist.docx`** - the user's own doc of which resistors/straps/jumpers are fitted where on each card (Table 6 Control Card straps, Table 11 Matrix address straps); the boards follow it. Plus extracted text, Matrix_Card-9 and Control_Card-6 schematics (+ text exports), I2C bus-sharing note, hardware test plan, GUI brief, MCP23017 (DS20001952C) and AD7476 datasheets, `PROJECT_LOG.md` (CL-102..104 are the latest), `fw_status.txt`. |
| `04_firmware_source/` | Copies of the files that matter (board, matrix/hv/control cards, mcp23017/ad7476/ads124s08 drivers, tasks/proto/log, main, i2c/spi/gpio, `HT_MK1.ioc`) plus `uncommitted_changes_Core.diff` (everything changed in `Core/` vs HEAD). |
| `05_firmware_image/` | The image under test (`spi3-adc-fix`, build 2026-11-20T11:34:40): hex, bin, SHA256, README. |
| `06_project_memory_notes/` | The project memory notes (verified addresses, topology, workflow, decisions). |

Key code locations: `Core/Src/bsp/board.c` (`Board_Init` retry loop, `board_init_matrix`), `Core/Src/cards/matrix_card.c:262` (`MatrixCard_Init`), `matrix_card.c:27-49` (bus claim/release), `Core/Src/drivers/mcp23017.c:39` (the failing I2C access), `Core/Src/app/proto.c:416-422` (the refusal), `Core/Src/app/tasks.c:477` (`run_continuity_all`).
