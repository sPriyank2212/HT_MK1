# Hardware test plan — 2026-11-13

Covers: the new firmware (USART2 console, HV card slot remap, configurable insulation limit,
build stamp), **BU-16** (run today) and the **FW-19** plan (written down only — nothing in it is
implemented, and no GitHub issues were opened for it).

Related: `PROJECT_LOG.md` HW-15 / BU-16 / BU-17 / FW-11 / FW-19, `Doc/i2c_bus_sharing.md` §7,
`Doc/GUI_development_brief.md` §3.2. Write results into the tables as you go.

## 0. Ground rules (read first)

1. **500 V is lethal.** Nothing is touched while HV is armed or while the rail monitor shows it live.
   After every insulation run wait for `!SAFE`, then at least 10 s before touching the fixture.
2. **No hardware interlock exists** (the GUI correctly says "Interlock closed: unverified"). The only
   protections are the firmware ones. Keep one hand free and a person who can pull power.
3. **Order matters: low risk first.** Parts 1–3 never arm HV. Part 4 (BU-16) is the first HV work.
4. **Stop on any `!FAULT`.** Do not clear a fault and retry blindly. Write down the code
   (F01 relay bus, F02 DAC/ADC, F03 rail, F05 not armed / bad netlist, F04 insulation low, F09 resistance).
5. **Test resistors must be rated for the voltage.** A standard ¼ W resistor is rated ~200–250 V; 500 V
   across a multi-megohm part needs an HV-rated resistor (or two half-value parts in series). Do not use
   ordinary parts at 500 V.
6. **Rollback:** keep the previous image (`Customer_Package/4_GUI_and_Firmware/Firmware` from commit
   `fe73672`, or your last known-good build) so the unit can be reflashed in a minute.

Console for all commands below: a serial terminal at **115200 8N1**, lines end with Enter, each command
starts with `>`. (The GUI is not needed; it is built separately.)

## 1. Pre-flight — new firmware, USB-UART

| # | Do | Expect | Result |
|---|---|---|---|
| 1.1 | Flash the new `HT_MK1.bin` at `0x08000000` (Flashing Procedure §5). | Programming OK | |
| 1.2 | Connect the **USB Type-C (J8)**; find the COM port (Windows: "USB Serial Device"). | Port appears | |
| 1.3 | `>PING` | `<PONG` | |
| 1.4 | `>ID` | `<ID HT_MK1 fw=0.1.0 proto=1 build=2026-…` — the stamp is the build PC's clock | |
| 1.5 | `>STATUS` | `state=idle fixture=none hv_mv=0` | |
| 1.6 | `>LIMITS GET` | `r_max_mohm=5000 ins_min_mohm=10000000000` (10 MΩ default, a 64-bit number) | |

If 1.3 gets no answer: check the terminal is on the MCP2221A port (not another), 115200, and that
PA2/PA3 reach U12. This is the first run of the USART2 console — if it fails, nothing else is worth doing.

## 2. HW-15 / BU-17 — HV card 1 now shares EN1 with the Matrix Card

**Why this needs checking.** HV card N is on Control Card slot J*N* (EN*N*); HV card 1 shares J1/EN1 with
the Matrix Card. Both cards strap their expanders to 0x20–0x27, and the Matrix's "all enables off" word
(`0xFFFF`) means *close every relay* to an HV expander. The firmware therefore switches **both Matrix
segments off the bus before it raises EN1 for HV card 1** (`MatrixCard_Deselect`, `pre_enable` hook). The
reverse direction cannot be made safe in software: **while the Matrix is being accessed (EN1 high), HV
card 1's expanders are also on the bus.** If both cards are fitted, Matrix writes also reach HV card 1.

| # | Do | Expect | Result |
|---|---|---|---|
| 2.1 | **Matrix only** (HV card 1 unplugged or not fitted): `>BUS SCAN` | `!BUSLINE` for U20, U101, U105, U102, U106, U66, U67, U107, U108, U69, U68 = `ok`; the 8 `HV1_*` lines = `fault` (card absent) | |
| 2.2 | Record a baseline: connect a known loopback/resistor between a Matrix HI and LO pin. Upload netlist `>NETLIST BEGIN 1` / `>NETLIST ADD <hi> <lo>` / `>NETLIST END`, then `>RES RUN` and `>CONT RUN verify`. | Note the resistance (mΩ) and the continuity verdict | R = |
| 2.3 | **Matrix + HV card 1 fitted:** `>BUS SCAN` | All 11 Matrix lines `ok` **and** all 8 `HV1_HS1..4`/`HV1_LS1..4` `ok` (19 lines, 0 faults) | |
| 2.4 | Repeat 2.2 exactly (same loopback). | **Same** resistance (within noise) and verdict as 2.2 | R = |
| 2.5 | Run `>BUS SCAN` three times in a row. | Identical every time | |

**Reading the result.**
- 2.4 differs from 2.2 (resistance noticeably lower, extra paths, continuity on pairs that should be open):
  the HV card's relays are being driven by Matrix writes. **Stop. Do not arm HV.** This is a hardware sharing
  problem, not a firmware one; record exactly what changed and report it (the fix is a different EN line for
  HV card 1, i.e. a harness change — the firmware slot map is one line in `board_init_hv()`).
- 2.3 shows `HV1_*` faults with the card plugged in: check the EN1 wiring to the HV card and that the HV
  card's own `ISO_HV_CARD_EN` pin is wired to Control **EN1** in the harness (HV Card sheet 1 note).
- A Matrix line faulting only when HV card 1 is fitted points to the same collision.

## 3. Low-risk checks (no HV)

| # | Do | Expect | Result |
|---|---|---|---|
| 3.1 | `>TEMP READ` | `!TEMP <deci-°C>` plausible | |
| 3.2 | `>CAL GET`, `>CAL RUN <hi> <lo>` on the reference pair | ratiometric=1, `pass` | |
| 3.3 | `>LIMITS SET r_max_mohm=5000 ins_min_mohm=99999999` | `<ERR ERANGE …` (below 100 kΩ) — nothing changed | |
| 3.4 | `>LIMITS SET r_max_mohm=5000 ins_min_mohm=40000000001` | `<ERR ERANGE …` (above 40 MΩ) | |
| 3.5 | `>LIMITS SET r_max_mohm=1234 ins_min_mohm=0` then `>LIMITS GET` | `ERR ERANGE`; `r_max_mohm` still 5000 (a refused SET changes nothing) | |
| 3.6 | `>LIMITS SET r_max_mohm=5000 ins_min_mohm=20000000000`, `>LIMITS GET` | `OK`, then `ins_min_mohm=20000000000` | |
| 3.7 | `>LIMITS SET r_max_mohm=5000 ins_min_mohm=10000000000` | back to the 10 MΩ default | |
| 3.8 | During a `>CONT RUN discover` (or any long run) send `>LIMITS SET …` | `<ERR EBUSY …`; the run is unaffected | |

## 4. BU-16 — prove the configurable insulation limit (first HV work)

**Fixture.** HV card 1 with `>FIXTURE hv`. One test net: HS pin **1**; one HV-rated resistor `R`
connected between **HS pin 1** and **LS pin 2** at the HV connector (so net 1 leaks through `R` into a
conductor whose return relay is closed). Netlist with a single pair:
`>NETLIST BEGIN 1` → `>NETLIST ADD 1 1` → `>NETLIST END`.

**Per run:** `>FIXTURE hv` → `>INSUL ARM` → `>INSUL RUN` → wait for `!DONE insul` and `!SAFE` → wait 10 s.
Read `!INSUL 1 <leak_mohm> pass|fail`. `leak_mohm` is the megohm estimate in milliohms (e.g. 10 MΩ =
`10000000000`).

**What the firmware computes** (full stimulus, 500 V, R3004 = 1 kΩ, series estimate Rs = 1 MΩ):
leakage voltage `V = 500 V · 1 kΩ / (R + 1 MΩ)`, pass threshold `Vpass = 0.045 V · 11 MΩ / (L + 1 MΩ)`.
FAIL when `V ≥ Vpass`.

| Limit L | threshold at the ADC | ≈ ADC counts (1.22 mV) | flips at R ≈ |
|---|---|---|---|
| 1 MΩ | 0.2475 V | 203 | 1.02 MΩ |
| 2 MΩ | 0.1650 V | 135 | 2.03 MΩ |
| 5 MΩ | 0.0825 V | 68 | 5.06 MΩ |
| **10 MΩ (default)** | **0.0450 V** | 37 | 10.11 MΩ |
| 20 MΩ | 0.0236 V | 19 | 20.21 MΩ |
| 40 MΩ | 0.0121 V | **10** | 40.41 MΩ |

**Expected verdicts** (P = PASS, F = FAIL; `~` = within 15 % of the flip point — do not judge those, they
are noise-limited, especially at 40 MΩ where the threshold is only ~10 ADC counts):

| R \ L | 1 | 2 | 5 | 10 | 20 | 40 |
|---|---|---|---|---|---|---|
| 0.47 MΩ | F | F | F | F | F | F |
| 1 MΩ | ~F | F | F | F | F | F |
| 2.2 MΩ | P | ~P | F | F | F | F |
| 4.7 MΩ | P | P | ~F | F | F | F |
| 6.8 MΩ | P | P | P | F | F | F |
| 8.2 MΩ | P | P | P | F | F | F |
| 10 MΩ | P | P | P | ~F | F | F |
| 12 MΩ | P | P | P | ~P | F | F |
| 15 MΩ | P | P | P | P | F | F |
| 22 MΩ | P | P | P | P | ~P | F |
| 33 MΩ | P | P | P | P | P | F |
| 47 MΩ | P | P | P | P | P | ~P |

**Procedure**

1. Start with the **default 10 MΩ** (this is the board decision and must behave exactly as before):
   `R = 8.2 MΩ` → must FAIL; `R = 15 MΩ` → must PASS; open circuit (no resistor) → PASS with the
   "negligible leakage" estimate (~9999 MΩ). A shorted pair must FAIL.
2. Then set each limit with `>LIMITS SET r_max_mohm=5000 ins_min_mohm=<L in mΩ>` and run the non-`~` cells
   of the matrix for that column. Suggested set (about 12 runs): L = 5 MΩ with 2.2 / 4.7(~skip) / 6.8 MΩ;
   L = 20 MΩ with 15 / 33 MΩ; L = 2 MΩ with 1 / 4.7 MΩ.
3. For every run record the **sense voltage and the reported megohm value**. If they fit
   `V = 500·1000/(R+Rs)` with Rs ≠ 1 MΩ, solve for Rs and report it: only the **10 MΩ** point is anchored
   to the board decision, other limits follow the series estimate `INSULATION_R_SERIES_OHM`.
4. Finish with `>LIMITS SET … ins_min_mohm=10000000000` so the unit is left at the default.

| Run | L (MΩ) | R (MΩ) | Expected | Got (`pass`/`fail`) | `leak_mohm` | Notes |
|---|---|---|---|---|---|---|
| | | | | | | |

**Pass criteria for BU-16:** every non-`~` cell matches; the 10 MΩ default matches its old behaviour; no
`!FAULT` during any run; `!SAFE` and the rail back to 0 after each run. **Fail →** record the cells that
disagree and the measured voltages; do not widen the 100 kΩ–40 MΩ range until they are understood.

## 5. FW-19 — plan only (nothing implemented, no issues opened)

### 5a. `MANUAL RELAYTEST` (Diagnostics → relay test)

**Today:** `>MANUAL RELAY <board> <n> <0|1>` is **refused by design** (`ERR EHW`): closing a single HV reed
relay on command bypasses the insulation sequence's discharge/rail checks.

**Proposed design — to be reviewed before any code is written.** A relay test may only exist if all of
these hold; each is also a bench test:

| Rule | Why | Bench check |
|---|---|---|
| Refused unless HV is disarmed **and** the rail is proven below `INSULATION_DISCHARGED_V` right before closing | A relay closed with the rail live is a 500 V hot-switch | Arm HV, then send the command → refused |
| Refused while a run is in progress, a fault is latched, or the board is not ready | One owner of the hardware at a time | Send during `CONT RUN` → `ERR EBUSY` |
| Exactly one relay closed at a time, break-before-make, board and number range-checked | No accidental parallel paths | DMM across the contact: only the chosen one closes |
| Auto-release after a short fixed time (≤ 2 s) and on `>ABORT` / `>SAFE` / link loss | A forgotten closed relay must not persist | Close, wait, confirm it opens by itself |
| Matrix segments off the bus first for HV card 1 (already done by `pre_enable`) | HW-15 shared EN1 | Matrix state unchanged after the test |
| Reports what it did (`!RELAY board n state`) and logs it | Auditable | Compare against the DMM |

Order: (1) written safety review of the table above by someone other than the author; (2) implement behind
a compile-time switch, default off; (3) bench-test on a **dead** card (no HV supply connected) with a DMM;
(4) only then enable it. Exit criterion: all six bench checks pass on every one of the 128 relays of one card.

### 5b. Release configuration

The project already has a `Release` configuration (`.cproject`); it has never been built or compared with
`Debug` here.

1. Build `Release` in STM32CubeIDE. Record the optimisation level, `NDEBUG`/`DEBUG` defines (the IWDG
   freeze-while-halted is `#ifdef DEBUG` only), and flash size vs `Debug` (Debug today: text 74 100 B).
2. Check nothing the safety design depends on is compiled out: `configASSERT`, stack-overflow check = 2,
   malloc-failed hook, IWDG start, fault latching, `Insulation_*` rail checks.
3. Flash on the bench (no HV) and repeat Parts 1–3 above unchanged; then the BU-16 default-limit rows.
4. Provoke the watchdog on purpose with a **debug-only** build (never in the shipping image) and confirm
   the unit resets and comes up with the DAC at 0 V and every relay open.
5. Compare timing-sensitive paths (scan time, `>ABORT` latency inside ~1 measurement point, `>PING`
   answered inside 2 s during a run) between Debug and Release.

Exit criterion: Release passes every check Debug passes, with the same fault behaviour. Until then the
customer package stays on the Debug image, as the Flashing Procedure says.

## 6. Results summary

| Part | Date | Tester | Outcome | Notes |
|---|---|---|---|---|
| 1 Pre-flight | | | | |
| 2 HW-15 / BU-17 | | | | |
| 3 Low-risk | | | | |
| 4 BU-16 | | | | |
