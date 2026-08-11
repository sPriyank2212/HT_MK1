# HT_MK1 — Project Log

One place to see where the project stands: what is open, what is closed, and what happened on
each working day.

- **Status snapshot** and **Open items** are live — edit them in place as things move.
- **Closed items** and **Activity log** are append-only. Newest day first.
- This file tracks *tasks and decisions*. See [README.md](README.md) for the document map —
  there are four living docs and this is the entry point to them.

ID prefixes: `HW-` schematic/hardware · `FW-` firmware · `BU-` bring-up/verify · `DOC-` documentation ·
`GUI-` raised against the external GUI effort (tracked here so nothing is only in the brief).

---

## Status snapshot — 2026-08-11

| Category | Count |
|---|---|
| Blocking — firmware cannot proceed | **0** |
| Agreed, awaiting schematic edit | 3 |
| Awaiting a decision | 7 |
| Firmware work queued | 4 |
| Awaiting the GUI side | 2 |
| Verify at bring-up | 10 |
| Closed to date | 25 |

**FW-02 is done: `RES RUN` now measures instead of failing every net.** `Kelvin_MeasurePair`
reads HI_SENSE/LO_SENSE on the Matrix Card's ADS124S08 (PGA auto-ranged, zero-current baseline
subtracted per point), instead of returning `HAL_ERROR` by design. Getting there also required
wiring the ADS124S08 into `bsp/board.c` for the first time (it had a driver since FW-01 but no
board-level instance), and fixing two things that would have made every reading silently wrong:
SPI1 was still 4-bit/mode 0 (the removed AD7476's leftover config; the ADS124S08 needs 8-bit
mode 1) and running at 32 MHz against the part's 10 MHz ceiling. See CL-23. **Unverified on real
hardware** — this closes the gap between "the protocol works" and "the instrument measures
resistance" in code, but BU-01 (excitation current / system offset) and BU-08 (formula) still
gate trusting a real number.

**The Matrix Card and every HV card share one I2C address range — firmware never gated it.**
All five cards' expanders hard-strap to 0x20–0x27. The Control Card wires the isolated I2C2 bus
out to every HV connector (J1–J4) as one shared set of wires, and the Matrix Card is confirmed on
that same bus too — so two cards live at once meant a guaranteed address collision. `HV_Card_EN1..4`
(PC5/PC6/PA10/PA9, one per slot — EN1 for the Matrix Card's own J1) exist in the schematic to gate
this, but nothing in firmware ever touched them; CubeMX still had the pins under a stale name
(`HV_CARD_DT_3_0` etc.) configured as unused inputs. Fixed for the HV cards (CL-24) and then for
the Matrix Card itself once confirmed (CL-25) — `MatrixCard_Init` now takes separate handles for
U21 (I2C3, local, never shared) and its own eight expanders (I2C2, shared, gated by `EN1`), and
U69 (the ADS124S08 control expander) follows the same gating. Diagram and plain-English write-up:
`Doc/i2c_bus_sharing.md`.

**HW-12 resolved: the ADC-control/sense-enable I2C straps were wrong in firmware, not just
unconfirmed.** Reading the actual address labels off `Matrix_Card-7.pdf` sheet 9 (cropped and
rendered from the PDF, not inferred) found the sense-side expanders at 0x20/0x21/0x22/0x24/0x26
for U66/U69/U67/U107/U108 — the U69-vs-U101 collision fw_status.txt warned about is gone (U69
moved to BUFF2, its own segment), but `matrix_card.h`'s strap constants still assumed the old
sequential 4..7 block. Fixed in code against the schematic; see CL-22. The force-side expanders
(U101/U102/U105/U106, sheet 3) were cross-checked the same way and matched the code exactly —
no change needed there.

**GUI: Flutter is now the primary build (decision 2026-08-10).** `gui_flutter/` (Dart/Flutter,
native Windows exe, no Python at runtime) landed 2026-08-07 as a full rebuild of `gui/` — same
design, same protocol, same safety rules, ported file-for-file. Verified: `flutter analyze`
clean, 130 tests, confirmed against both the simulator and a real NUCLEO-G474RE (connect,
netlist upload, netlist-mode continuity). **`gui/` (Python, htweb + Tk) is superseded** — kept
on disk for reference, no longer tracked for new work. GUI-03 is the one item still open
against it. See the 2026-08-07/08 activity entries.

**Firmware: the heartbeat closes a false "link lost."** `Proto_EvtHeartbeat()` re-announces
state every 2 s so an idle-but-healthy link never trips the GUI's 5 s watchdog — that watchdog
was firing on every connect before this, on both GUI builds, since the instrument said nothing
at all when idle. Verified on hardware: 90 s connected, no link loss, 65 beats at 1.997 s.

**FW-04 closed retroactively (CL-19).** Rereading `matrix_card.c` for this review found the U21
mux-addressing rework already landed in `f778ba7` (2026-08-01) as a side effect of the FW-03
rework — it was just never marked closed under its own ID. The 400 kHz-vs-100 kHz bus-speed
half of the original item is still unresolved (no I2C3 timing override found in `board.c`),
carried forward as a note under BU-03.

**Two new Doc/ files folded into the document map, not left as a fifth/sixth tracking doc.**
`GUI_protocol_command_coverage.md` and `GUI_protocol_proposed_commands.md` (both 2026-08-08)
audited every tappable control in `gui_flutter/` against the protocol. The wiring gaps they
found are already fixed (`FAULT CLEAR`, `MANUAL PATH`, `MANUAL OFF`, real netlist file
browsing); the real open items from that audit are now GUI-04 through GUI-07 below. README
updated to list both as reference material — this log stays the one place status is tracked.

**`>ABORT` is correct by inspection at last, but still unproven on hardware.** FW-07, FW-08 and
FW-09 closed 2026-08-05 (CL-12, CL-13, CL-15) fixed the scheduling bugs that made abort a
no-op. **BU-12 is still the gate** and this review found no evidence abort has been exercised
on real hardware since that fix — a clean build and a simulator prove nothing about scheduling.

**The 4-wire method is proven on the bench**, and now implemented (not yet hardware-verified) on
the product ADS124S08: the ADS1232 bench rig measured a 0.033 Ω resistor to **0.4 %** with no
current calibration at all, because the ratiometric arrangement cancels the excitation. Write-up
in `Doc/4wire_resistance_validation.md`.

**Next actions, in order:** BU-01 (excitation current / system offset on real hardware) is now
the thing standing between FW-02 and a trustworthy number. BU-12 (abort on real hardware) should
be exercised before anything ships. HW-04 and HW-09 are still awaiting a schematic decision from
2026-07-27 — the bench result is now the concrete argument for HW-04.

**Forward risk list** is in `Doc/4wire_resistance_validation.md` §7. Headline: the excitation
has a **usable window of roughly 1–8 mA**, target **5 mA** — below that the sense common mode
falls under the PGA floor (BU-07), above it the force loop runs out of compliance on 3.3 V.
At 5 mA both ends have wide margin.
Highest-value next measurement is **CD74HC4051 Rₒₙ at 3.3 V**, because it sets that whole
window and nothing downstream can be finalised without it.

---

## Open items

### Agreed — awaiting schematic edit

| ID | Item | Agreed |
|---|---|---|
| HW-03 | Matrix card moves to the non-isolated domain: `+5V_ISO` → plain `+5V`, no isolators in the Matrix path. Follow-ons: the Matrix card's ADuM1205 (U103) becomes redundant once both sides share ground — DNF with links or keep as a buffer; and feed the slot raw `I2C3_SDA`/`I2C3_SCL` rather than `ISO_SDA3`/`ISO_SCL3`. | 2026-07-29 |
| HW-08 | HV card R3003 50 kΩ → 5 kΩ, giving 0.245 V at 500 V from the 10 M : 5 k divider. **The PDF in the repo still shows 50 kOhms** (HV_Card-1.pdf sheet 2), so either the change is not exported or HV_Card-1 is stale — re-issue and re-check. | 2026-07-20 |
| HW-10 | Add pull resistors on the three ADC control lines that U69 drives, so they are defined while the MCP23017 is still in its power-on high-Z input state: `ADC_CS_1` and `ADC_RST_1` pulled **up** to +3V3 (CS deasserted, ADC out of reset), `Start_SYNC_1` pulled **down** to GND. Sheet 9 currently carries only 4.7 K (I2C and address strapping) and 47 Ω (series damping) — nothing on these nets. Same argument as the mux enables. | 2026-07-29 |

### Awaiting a decision

| ID | Item | Raised |
|---|---|---|
| HW-04 | **Current reference — on-card net, not a connector wire.** Route the `LO_COM` node (top of R131) to **U68 AIN2**, both on Matrix sheet 9, with 1 kΩ series + 100 nF to AINCOM. Purpose is measuring the excitation current, not sensing harness voltage: R = V_kelvin / I, and without measuring I across R131 the current comes from the DAC8775's programmed value, so resistance accuracy equals DAC tolerance plus tempco and R131's 0.01 % does nothing. AIN2–AIN5 are free. If declined, firmware calibrates the current against a reference resistor instead and the accuracy claim drops accordingly. | 2026-07-27 |
| HW-09 | **Four card slots, five cards.** The Control card has four 50-pin connectors (J2–J5). A 256-line harness needs four HV cards (64 HS lines each) *plus* the Matrix card. Not a problem while only one or two HV cards are fitted, but the full configuration cannot be assembled as drawn. Decide before the connector pinout is frozen. | 2026-07-27 |
| GUI-04 | **Netlist persistence** (brief §8 Q2): should an uploaded netlist survive a reboot, or is RAM-only + re-upload-every-boot the accepted behaviour? Confirmed on hardware that it does not persist today. Surfaced by `Doc/GUI_protocol_command_coverage.md` §6. | 2026-08-08 |
| GUI-05 | **Run history storage** (brief §8 Q4): stored on the instrument, or the GUI host? Blocks the Results view's Export CSV / Print report from being anything but decoration — that table is static mock data today. Surfaced by `Doc/GUI_protocol_command_coverage.md` §6. | 2026-08-08 |
| GUI-06 | **Seven proposed protocol commands** awaiting a firmware-side yes/no: `BUS SCAN`, `MANUAL READ`, `MANUAL SWEEP`, self-cal, PGA auto-range, compliance sweep, relay self-test. Full command-by-command writeup with size estimates in `Doc/GUI_protocol_proposed_commands.md` — two (auto-range PGA, compliance sweep) are recommended against as separate commands at all. Nothing in `Core/Src` touched for any of it. | 2026-08-08 |
| HW-11 | **DAC8775 (Kelvin current source, Control Card) is hard to source, and it's the wrong product category anyway.** DAC8775/DAC8760/AD5758/AD5755 are all "4-20 mA loop driver" parts that inherently need a wide supply (DAC8775: ±15 V typical; DAC8760: 10–36 V; AD5758: up to ±33 V) to drive long 2-wire process loops — none run from the 3.3 V this board actually has. Real operating current is 1–3 mA (§7.1, `Doc/4wire_resistance_validation.md`), and only channel A is used today, so the right category is a small-range precision current-source DAC, not an industrial loop driver. **Leading candidate, confirmed 2026-08-11: ADI LTC2662-16** (`LTC2662IUH-16#PBF`) — 5-channel (1 used, same as today), 16-bit, SPI, **2.85–5.5 V single supply** (direct fit for this board's 3.3 V rail), 8 selectable per-channel ranges down to **3.125 mA full scale** (16-bit over that span = 47.7 nA/LSB, far finer than needed), integrated 1.25 V reference (10 ppm/°C max). **214 units in stock at DigiKey, $49.18 @ qty 1, MOQ = 1.** Not yet verified: dropout/compliance voltage specifically at the 3.125 mA range (datasheet PDF fetch failed repeatedly this session — only the headline "1 V dropout @ 200 mA" spec is confirmed, and dropout is expected but not confirmed to scale down at lower ranges) and gain-error/TUE accuracy at 3.125 mA. Calibration is mandatory regardless of which part ships (see CL-21). Runner-up: TI DAC8760 (same family as DAC8775, easiest port, but still needs 10–36 V — would require adding a boost regulator this board doesn't have today, a real cost the LTC2662 avoids). | 2026-08-11 |
| GUI-08 | **The required netlist format has no connector concept; the parser and the wire protocol don't either.** `gui_flutter/required_format/example_netlist27072026.xlsx` numbers pins per-connector (`Conn ID` + `Src Pin #`), so a straight-through harness has `Src Pin # == Dst Pin #` on every row — but `NETLIST ADD <hi> <lo>` and the matrix routing use one flat `1..256` fixture address, so every row in that exact file collides and is rejected (correctly — pinned by a test, see CL-20). Needs a decision: either netlists must supply pre-globalised pin numbers, or a `Conn ID` → base-offset map gets built (real firmware/GUI work, not a header rename). See `gui_flutter/required_format/README.md`. | 2026-08-10 |

### Firmware work queued

| ID | Item | Raised |
|---|---|---|
| ~~FW-01~~ | **DONE 2026-08-01** — `drivers/ads124s08` written, see CL-10. Original scope: new `drivers/ads124s08` — reset, device-ID read, PGA / data-rate config, internal 2.5 V reference, offset self-calibration. **CS, RESET and START/SYNC are driven over I2C via U69 (0x25), not by MCU GPIO**, so each conversion sequences I2C(CS low) → SPI → I2C(CS high). `DRDY_1` is likewise an expander *input*: no interrupt is possible and polling costs a bus round-trip, so use a timed wait derived from the configured data rate and read DRDY only as a sanity check. | 2026-07-27 |
| ~~FW-02~~ | **DONE 2026-08-11** — `test/kelvin.c` rewritten for 4-wire, see CL-23. Original scope: Rewrite `test/kelvin.c` for 4-wire. It currently reads the AD7476 and hard-codes `KELVIN_FORCE_CURRENT_A = 0.010f`; both are wrong under the new scheme. Add PGA auto-ranging and system-offset subtraction. | 2026-07-27 |
| ~~FW-03~~ | **DONE 2026-08-01** — `matrix_card` reworked for the Matrix_Card 2 geometry: 8:1 muxes, 32 per bank, 3 select bits, 8 enable expanders across two buffered I2C segments, byte-swapped enable map, segment switching via `HI_S3`/`LO_S3`. AD7476 binding removed (rev 2 deleted U33). | 2026-07-27 |
| ~~FW-04~~ | **DONE, retroactively closed 2026-08-10 — see CL-19.** Mux address lines via MCP23017 U21 landed in `f778ba7` (2026-08-01) as part of the FW-03 rework; never marked closed under its own ID. Original scope: mux address lines come from MCP23017 U21 on I2C3, not MCU GPIO; add OLAT shadow registers, and consider 400 kHz — a 256 × 256 scan is roughly 70 s of pure bus time at 100 kHz versus 18 s at 400 kHz. **The 400 kHz question is still open** — no I2C3 timing override found in `board.c` — carried forward under BU-03. | 2026-07-27 |
| ~~FW-05~~ | **DONE 2026-08-01** — `app/proto.c`, see CL-11. Original scope: implement the instrument side of the GUI protocol defined in `Doc/GUI_development_brief.md` §3 — line-based ASCII over the VCP at 115200. Replaces the current single-keystroke bring-up console (`c`/`k`/`i`/`s`/`f`/`r`). Needs: command parser, `<` replies with 2 s worst-case latency, `!` result streaming during a run, and `!STATE`/`!FIXTURE`/`!HV`/`!SAFE` events. The GUI is being built against this contract, so changes to it must be agreed, not made. | 2026-08-01 |
| FW-06 | **`>STATUS` never reports `running` or `fault`.** `proto_exec` builds the reply from `s_armed` alone, so a GUI that reconnects mid-run and re-issues `>STATUS` — which the brief §3.5 rule 4 requires it to do — is told `idle` while a run is executing. `!STATE` does carry `running`, so the information exists; only the polled path is missing it. Documented as-is in the brief for now (§3.2, Appendix B) rather than changed silently: the reply is protocol-visible and the GUI is being built against it, so agree it first. Fix is to report from `s_busy` and `Safety_InFault()` as well. | 2026-08-05 |
| ~~FW-07~~ | **DONE 2026-08-05** — see CL-12. Original scope: **`>ABORT` cannot stop a run — the comms thread is starved for the whole run.** `tSequencer` is `osPriorityNormal`, `tComms` is `osPriorityBelowNormal`, and the sequencer never yields during a run: the settle delays are `HAL_Delay` (the stock `__weak` one — a busy-spin on `HAL_GetTick`, TIM1 timebase, nothing overrides it) and the I2C/SPI calls are polled. With `configUSE_PREEMPTION=1` a lower-priority task never runs while a higher-priority one is runnable, so `Proto_RxByte` is never called during a run: **the abort flag the run loops poll can never be set, and the polling in `tasks.c` is unreachable in practice.** Worse, RX is single-byte polled with no interrupt or DMA, so mid-run bytes are lost to overrun rather than buffered. Scale: insulation is 256 × ~250 ms ≈ 64 s, discover 65,536 × ~2 ms ≈ 131 s — an operator pressing Abort during a 500 V run has no effect for that long. Physical E-stop and the safety task (`osPriorityHigh`, blocks on `osDelay`) are unaffected. Found by the GUI-side task-2 review. Two candidate fixes, neither started: interrupt/DMA RX into a ring buffer with `tComms` blocking on it, or `osDelay` instead of `HAL_Delay` in the test settle paths so the sequencer yields. | 2026-08-05 |
| ~~FW-08~~ | **DONE 2026-08-05** — see CL-13. Original scope: **`Proto_SetFixture` announces `!SAFE` before the hardware is safe.** It posts `CMD_FORCE_SAFE` to the queue and then immediately emits `!HV 0` and `!SAFE`, without waiting for execution — so the instrument tells the GUI it is safe while the rail may still be up. Directly contradicts the brief's central rule that the GUI must never show a safe state it has not been told is real. Masked today by FW-07 (a fixture change cannot be received mid-run), so **fixing FW-07 unmasks this** — do them together. Also in the same path: the arm is dropped with no `!STATE idle`, and `!SAFE` is emitted twice (once inline, once when the queued force-safe runs). | 2026-08-05 |
| ~~FW-09~~ | **DONE 2026-08-05** — see CL-15. Original scope: **An abort in the first moments of a run is silently lost.** `proto_post_run` clears `s_abort` and posts; the sequencer then calls `Proto_ClearAbort()` *again* at run entry (`tasks.c` 281 / 348 / 396). An `>ABORT` processed in the window between the post and that second clear is wiped, the GUI has already had its `<OK`, and the run continues to completion — up to 64 s at 500 V for insulation. **The FW-07 fix made this more reachable, not less:** `tComms` now sits above the sequencer, so it can preempt and set the flag exactly in that window. Fix is to delete the three entry-side clears — `proto_post_run` is the only path that starts a run and it already clears the flag at the one point where clearing is correct, before the command is queued. Raised verbally on 2026-08-05 and not logged at the time; logged now. | 2026-08-05 |
| ~~FW-10~~ | **DONE 2026-08-05** — see CL-16. Original scope: **A latched fault wedges the run path permanently, and the GUI waits forever.** `run_command` returns early when `s_fault` is set, *before* the switch — so a dequeued run command never reaches `Proto_EvtDone`. `s_busy` stays 1, every later run is refused `ERR EBUSY`, and no `!DONE` is ever emitted, so a GUI that is waiting for the run to finish waits for ever. Compounded by there being **no protocol command to clear a fault** (`Safety_ClearFault` is not reachable from `proto.c`), so recovery is a power cycle. Fix is small — in the skip path, emit `!FAULT` and `!DONE` for run commands so the GUI is released, and add a way to clear the latch. Found while closing FW-09; **not a release blocker on its own** (it needs a fault first, and a faulted instrument is already unusable) but it turns one fault into a hung GUI. | 2026-08-05 |
| DOC-01 | `fw_status.txt` still describes the 2-wire path, 10 mA excitation, and Matrix U33 as the resistance ADC. Sync it with v1.4. | 2026-07-27 |
| DOC-03 | `Doc/4wire_resistance_validation.md` §7.1 still targets **~5 mA** excitation. Superseded 2026-08-01 by BU-09 (real CD74HC4051 datasheet, worst-case Rₒₙ 250–320 Ω) which revised the target to **3 mA**, but that revision was never propagated into §7.1's compliance table — only into the project log. The 1 mA lower bound in §7.1 is still correct (common-mode-limited, independent of the mux swap); only the upper end and the "target ~5 mA" callout need re-deriving against 3 mA. Flagged in the doc 2026-08-11. | 2026-08-11 |
| DOC-02 | **`HT_ENABLE_ADS1232` defaults to 1, but README.md says "default off".** `Core/Inc/drivers/ads1232.h` has `#ifndef HT_ENABLE_ADS1232 / #define HT_ENABLE_ADS1232 1`, so every Debug build compiles the bench driver in — which is why the current image carries it. One of the two is wrong. The bench validation is finished (CL-10 / the 2026-08-01 write-up), so the header default should probably become 0 and the rig be enabled explicitly with `-DHT_ENABLE_ADS1232=1`. Noticed while hand-linking on 2026-08-05. | 2026-08-05 |

### Awaiting the GUI side

Raised in `Doc/GUI_development_brief.md` §8.4 and `Doc/GUI_protocol_command_coverage.md`
against the GUI deliverables. Tracked here so the outstanding set is visible from one place,
not only from inside a brief or an audit doc. **As of 2026-08-10, `gui_flutter/` is the
primary build** — new items are filed against it. GUI-03 is against the now-superseded Python
`gui/` and kept only as a record.

| ID | Item | Raised |
|---|---|---|
| ~~GUI-01~~ | **FIXED 2026-08-05 (GUI side)** — `_link_lost` is now called after `_io_lock` is released, and there is a regression test (`TestSendFailure`: the `execute()` call runs in a thread, so a regression fails the test instead of hanging the suite). Re-verified on the fixed code: send failure now surfaces `LinkLostError` immediately and the link drops to `LINK_LOST`. Original scope: Blocker — a send failure deadlocks the connection manager; `_execute` called `_link_lost()` while holding the non-reentrant `_io_lock`. | 2026-08-05 |
| ~~GUI-02~~ | **FIXED 2026-08-05 (GUI side)** — `!RES` milliohms, `!INSUL` leak_mohm, `<STATUS hv_mv`, the `<LIMITS` values and `!HV` now parse as signed int32; pins, counts and progress stay unsigned. Regression test added (`test_signed_measurement_values`), and the old malformed-case test that asserted `hv_mv=-5` was invalid has been corrected — it was encoding the bug. Original scope: signed wire fields parsed as unsigned, so a valid negative reading was reported as a protocol violation. | 2026-08-05 |
| GUI-03 | **Three minors, in `gui/` (Python, superseded 2026-08-10 — low priority).** A single non-ASCII byte kills the reader thread and turns into a misleading 5 s "link lost" (`UnicodeDecodeError` is caught outside the read loop); `_link_lost` nulls `_transport` under a live reader/sender, so `AttributeError` escapes instead of `LinkLostError`; and `parse_line('')` raises, where ignoring empty lines would be safer. Acknowledged by the GUI side 2026-08-05, not yet done. | 2026-08-05 |
| GUI-07 | **`LIMITS SET` never wired, in `gui_flutter/`.** The codec encoder exists (`commands.limitsSet()`) and the firmware answers it, but nothing in `AppState` calls it — there is no way to change `r_max_mohm`/`ins_min_mohm` from the GUI at all. A real gap, not a proposal. Found by `Doc/GUI_protocol_command_coverage.md` §1. | 2026-08-08 |

### Verify at bring-up

| ID | Item | Raised |
|---|---|---|
| BU-01 | Excitation current — run the 0 Ω loopback compliance sweep. 10 mA is unachievable through two CD4067B plus 100 Ω on a 3.3 V rail; expect roughly 1–3 mA. Capture the system offset at the same time. | 2026-07-27 |
| BU-02 | ~~SPI1 shared by U33 and U68~~ **Dissolved** — Matrix_Card 2 removed the AD7476, so SPI1 has exactly one device. Mode confirmed from SBAS660C: DIN latched on the SCLK falling edge, DOUT changes on the rising edge → **CPOL=0, CPHA=1 (mode 1)**. `SPI1_CS` on J101 now has no consumer. | 2026-07-27 |
| BU-03 | U101 / U102 I2C addresses are set by strapping and not annotated, unlike the sheet-9 trio at 0x23 / 0x24 / 0x25. Scan and log. **Also carries the FW-04 400 kHz-vs-100 kHz decision** (moved here 2026-08-10 when FW-04 closed) — no I2C3 timing override found in `board.c`; confirm the bus speed at the same bring-up session. | 2026-07-27 |
| BU-04 | JP1 (AINCOM → GND, Matrix sheet 9) must be fitted, or the ADC's analog common floats. Populate with a 0 Ω link by default and mark it on the assembly drawing. | 2026-07-27 |
| BU-05 | ~~No differential RC filter~~ **DONE in Matrix rev 2** — R234/R235 4.99 k 0.1 % + C33 47 nF + C142/C143 4.7 nF fitted. | 2026-07-27 |
| BU-07 | **Common-mode: hold the excitation at ≥1 mA.** `LO_SENSE = I × (R_LOmux + R131) = I × 200 Ω` against an ADS124S08 floor of `0.15 + 15.5·\|V_IN\|`. At 1 mA that is 0.200 V vs 0.165 V (+35 mV); at the 5 mA target it is 1.000 V vs 0.227 V (+772 mV) — comfortable, **nothing to fix in hardware**. Revised 2026-08-01: the earlier "marginal" framing overstated it. The real caveat is that the floor grows with the measured resistance, capping R at ~11 Ω at 5 mA on gain 32 — handled by PGA auto-ranging, since gain ≤16 uses a much lower floor. See Doc/4wire_resistance_validation.md §5.1. | 2026-08-01 |
| BU-09 | **Measure CD74HC4051 Rₒₙ at 3.3 V** — reduced 2026-08-01 after reading SCHS122O. Channel-to-channel spread (ΔrON) is **10 Ω max**, so the "some wires read wrong" concern is largely closed; a sanity check across a few channels is enough. What remains is that rON is characterised only from **VCC = 4.5 V** (typ 70 Ω, max 160 Ω at 25 °C, 200 Ω at 85 °C) and the card runs at 3.3 V — extrapolate typ ~110–140 Ω, max ~250–320 Ω. **Excitation target revised 5 mA → 3 mA**, which stays inside both compliance and common-mode limits even at worst-case rON. | 2026-08-01 |
| BU-10 | **Thermal EMF is the accuracy floor below ~1 mΩ.** At 5 mA, 1 µV of junction EMF = 200 µΩ. A 256-line harness has hundreds of dissimilar-metal junctions. Mitigation to design in now: **current reversal** — the DAC8775 has a ±24 mA range, and R = (V_fwd − V_rev)/(2I) cancels EMF because it does not reverse with the current. The ADS124S08 `G_CHOP` bit cancels the ADC's own offset only; the two are complementary. See §7.3. | 2026-08-01 |
| BU-11 | **Measure sense-path leakage.** `HI_SENSE` is the common node of 32 CD74HC4051s with 31 disabled; summed off-channel leakage into the 4.99 kΩ series resistor could be a large offset (1 µA → 5 mV). Should largely cancel between HI and LO legs, but unverified. Cheap test: enable a sense bank with no excitation and check the differential reads near zero. Rises sharply with temperature. See §7.4. | 2026-08-01 |
| BU-08 | **Do not copy the bench resistance formula.** ADS1232 full scale is ±0.5·VREF/Gain, ADS124S08 is ±VREF/Gain. The bench divides by `2 × gain × 2²³`; the product must divide by `gain × 2²³`. Copy-pasting gives a silent 2× error. | 2026-08-01 |
| BU-06 | Harness build must encode `ISO_HV_CARD_ENx` per card slot (card 1 → EN1 … card 4 → EN4). HV_Card-1 sheet 1 states this is done in the cable, not the schematic. | 2026-07-27 |
| BU-12 | **Prove `>ABORT` on real hardware.** The FW-07 fix (CL-12) is verified only by inspection and a clean link — the failure was a scheduling one, and scheduling bugs do not show up in a build. Press abort during a 256-pin discover scan and again during an insulation run; the run must stop within roughly one measurement point and still emit its `!DONE`. Check at the same time that a mid-run `>PING` is answered inside 2 s, and that a `>FIXTURE` change during a run stops it. | 2026-08-05 |

---

## Closed items

| ID | Closed | Item | Resolution |
|---|---|---|---|
| CL-25 | 2026-08-11 | Matrix Card confirmed on the same shared bus, gated to match | User confirmed directly (not inferred): the Matrix Card's own onboard expanders are on the same bus as HV Card 1, closing what CL-24 had left open. `MatrixCard_Init` split onto two I2C handles - `hi2c_local` for U21 alone (I2C3, stays put, never shares an address with anything) and `hi2c_shared` for the eight Matrix-card expanders (I2C2, same bus as every HV card). Added `en_port`/`en_pin` (`HV_Card_EN1`/J1) to `MatrixCard_t` and public `MatrixCard_BusClaim()`/`BusRelease()`, called around every function that touches `hi_en`/`lo_en`/`hi_sns`/`lo_sns` (`Init`, `SetSensePaired`, `BankOff`, `SelectPin`, `ConnectPair`). U69 (the ADS124S08 control expander, also on the shared bus per HW-12) gets the same treatment in `board.c`'s io callbacks and `board_init_ads124s08()`, which also moved off `BOARD_MATRIX_I2C` onto `BOARD_HV_I2C` to match. `board_init_matrix()` updated for the new signature. Build verified clean (0 errors, 0 warnings). `Doc/i2c_bus_sharing.md` and `PROJECT_LOG.md` updated; the open question this closes was tracked only as prose in CL-24, never given its own BU- number, so nothing to formally close. |
| CL-24 | 2026-08-11 | Shared I2C bus between the Matrix Card and every HV card, ungated | User traced the schematic and confirmed the Matrix Card and all four HV cards share one isolated I2C bus while every card's expanders hard-strap to the same 0x20-0x27 range - a guaranteed address collision the moment two cards are live together. `HV_Card_EN1..4` (PC5/PC6/PA10/PA9, through isolators U18/U19 to each HV connector) exist for exactly this, but nothing in firmware touched them, and CubeMX still had the four pins under a stale pre-rename label (`HV_CARD_DT_3_0`/`_3_1`/`_4_0`/`_4_1`) configured as unused inputs. Fixed: pins relabelled `HV_CARD_EN1..4` and switched to push-pull outputs, default low, in `HT_MK1.ioc`/`main.h`/`gpio.c`. `HvCardCfg_t` gained `en_port`/`en_pin`; `hv_card.c` added `hv_bus_claim()`/`hv_bus_release()` and wraps every function that touches `hv->inject[]`/`hv->ret[]` (Init's expander loop, OpenAllRelays, CloseInject, CloseReturn) so exactly one card's segment is ever live, on every exit path including errors. `board.c` maps HV board index to physical slot as idx+1 (board 0 -> J2/EN2), reserving J1/EN1 for the Matrix Card per HW-09, with a compile-time guard against `BOARD_HV_COUNT` exceeding the 3 slots that leaves. Diagram + plain-English write-up: `Doc/i2c_bus_sharing.md`. Build verified clean (0 errors, 0 warnings). **Whether the Matrix Card itself was on this bus was left open at the time** — resolved same day, see CL-25. |
| CL-23 | 2026-08-11 | FW-02 4-wire Kelvin rewrite | `Kelvin_MeasurePair` now reads HI_SENSE/LO_SENSE on the Matrix Card's ADS124S08 instead of returning `HAL_ERROR`. Sequence: `MatrixCard_SetSensePaired`+`ConnectPair` route both force and sense arrays, `Frontend_SetCurrentCode` forces the excitation, then the PGA is auto-ranged (highest gain first, stepping down on saturation — most wires are near 0 Ω and want the resolution; a real fault falls through to unity gain instead of clipping). A second conversion at the same gain with the excitation off gives a per-point zero-current baseline that is subtracted before `ADS124S08_OhmsFromCurrent` — system-offset subtraction, complementary to the one-time `ADS124S08_SelfOffsetCal` now run at board init (cancels the ADC's own offset only). Current reversal for thermal EMF (BU-10, §7.3) is **not** included: it needs the DAC8775 configured for its bipolar ±24 mA range, and the DAC8775 register map is still placeholder/VERIFY (dac8775.h) — inventing a "reversed" code without knowing the real range encoding could silently drive the wrong current, which is worse than not reversing at all. Left as an explicit gap, not implemented unsafely. Getting a real reading also required work outside kelvin.c itself: `board.c` never had an ADS124S08 instance or U69 io-vtable wiring at all (only the driver existed, from FW-01) — added, including the segment-select dance every U69 access needs (it sits behind the same BUFF2 translator as the sense enables, see CL-22). SPI1 was still CubeMX's default 4-bit/mode-0 config left over from the removed AD7476, and clocked at 32 MHz against the ADS124S08's 10 MHz ceiling — both fixed in `spi.c` and `HT_MK1.ioc` (8-bit, mode 1, /8 prescaler = 8 MHz). Separately, `make` from the command line couldn't link at all: `proto.c` (FW-05, closed 2026-08-01) and `ads124s08.c` (FW-01) were never added to `Debug/Core/Src/{app,drivers}/subdir.mk` or `Debug/objects.list` — only the Eclipse IDE's own indexer knew about them. Fixed so a plain `make all` builds clean (64872 B text, 0 warnings) instead of only working from inside the IDE. **Unverified on real hardware** — BU-01 and BU-08 still gate trusting a specific number. |
| CL-22 | 2026-08-11 | HW-12 sense-side I2C straps confirmed and fixed | Read the actual address labels off `Matrix_Card-7.pdf` sheet 9 directly (PDF pages rendered to PNG with PyMuPDF and cropped around each expander, not inferred from the earlier text-extraction pass, which this sheet's binary-address labels don't survive `pdftotext` at all). Found: U66 = 0x20, U69 = 0x21, U67 = 0x22, U107 = 0x24, U108 = 0x26 — not the sequential 0x24..0x27 block `matrix_card.h` assumed for the sense enables, and not 0x20 for U69 as fw_status.txt's old collision note (U69 vs U101) had it either. The collision itself is confirmed gone: U69 sits on BUFF2 (its own segment) at 0x21, between U66 and U67, nowhere near U101 (0x20 on BUFF1, the force segment). Force-side straps (U101/U102/U105/U106, sheet 3) were cross-checked the same way and matched the existing code exactly (0x20/0x21/0x22/0x23) — confirmed, not changed. `MATRIX_HI_SNS_LO_STRAP`/`_HI_STRAP`, `MATRIX_LO_SNS_LO_STRAP`/`_HI_STRAP` and `MATRIX_ADCCTL_STRAP` corrected in `matrix_card.h` to match. Without this fix, FW-02 would have addressed the wrong I2C devices for every sense-array and ADC-control access. |
| CL-21 | 2026-08-11 | Verified a re-derived resistance-accuracy calculation against `Datasheet/ads124s08.pdf` and `Datasheet/dac8775.pdf` directly | Two real errors found and fixed. **(1)** The Table-1 (Sinc3, chop disabled) noise values quoted for Gain=128 at 2.5 SPS and 5 SPS were each one row off (true values 0.11 µVPP and 0.16 µVPP, not 0.16 and 0.23 — more margin than stated, not less); the 16.6 SPS row (0.30 µVPP) was correct. **(2)** DAC8775's TUE table has four rows gated on temperature range *and* whether the "4 to 20 mA" range specifically is configured; the design's actual 1–3 mA operating point (§7.1) is below that range's 4 mA floor, so the applicable row is the general ±0.14 %FSR one, not the ±0.4 % "4 to 20 mA"-specific one used in the corrected-but-still-wrong pass. Net effect on the conclusion: unchanged — calibration is mandatory either way, because none of the DAC-limited ceilings (30–107 mΩ depending on FSR) come close to the noise-floor target (sub-1 mΩ). `Doc/4wire_resistance_validation.md` §7.6 rewritten with the sourced numbers and both range-FSR cases; CM-floor formula and FSR-at-gain-128 math were independently re-verified and are correct as originally stated. |
| CL-20 | 2026-08-10 | Netlist parser rejected the required_format header spellings | `Src Pin #`/`Dst Pin #` (the headers `gui_flutter/required_format/example_netlist27072026.xlsx` actually uses) were not in `netlist_file.dart`'s recognised alias lists, so the required-format netlist could not be loaded at all. Added as aliases. Two regression tests in `test/netlist_file_test.dart`: one confirms the new spellings parse with distinct pin numbers, the other pins the still-open GUI-08 gap (the real example file's rows collide under the flat pin model and are correctly rejected, not silently misrouted). Full suite re-run: 181/182 pass — the one failure (`netlist_file_generated_test.dart`) is pre-existing WIP scaffolding from `ee1e0f7` expecting a `test_netlists/` directory that was never committed, unrelated to this change. |
| CL-19 | 2026-08-10 | FW-04 mux addressing (retroactive) | Confirmed already implemented: `matrix_card.c` stages `HI_S`/`LO_S` into a shared word and pushes it to MCP23017 U21 on I2C3 (`f778ba7`, 2026-08-01, bundled into the FW-03 rework). Never closed under its own ID until this review. The 400 kHz bus-speed half of the original item is unresolved and carried forward under BU-03. |
| CL-18 | 2026-08-05 | Frontend must match the approved HTML design | Web frontend in `gui/htweb/`. `index.html` is `Doc/HT_MK1_GUI_Proposal.html` **verbatim** — same markup, same CSS, same render code — so the running instrument looks exactly like the design that was signed off. The only change to it is a `window.HT_SEAM` export at the end of its closure, which lets `live.js` swap the three simulated run functions for protocol-driven ones and rebuild the net model from a real netlist. `server.py` is a stdlib HTTP bridge: page, `GET /api/events` (SSE), `POST /api/cmd`. Binds loopback unless `--allow-remote`, because the page can arm and fire 500 V. The Tk frontend stays as the fallback and as the home of the headless safety-rule tests. |
| CL-17 | 2026-08-05 | GUI tasks 3–10 | Operator GUI built in `gui/htgui/` — Tk, standard library only, no dependencies. `model.py` holds the instrument state and every safety rule and imports no Tk, so the rules are tested headlessly; `app.py` is the shell (HV banner on every screen, always-reachable abort, 100 ms redraw tick); `screens.py` is the eight screens. Commands always go out on a worker thread, because `execute()` blocks up to 2 s and freezing the UI would freeze the abort button with it. Suite is now **83 tests**, including a smoke test that drives the real Tk app against the real simulator over a socket and asserts the HV controls are gated by the instrument's reported fixture, not by what the GUI asked for. |
| CL-16 | 2026-08-05 | FW-10 latched fault wedged the run path | `run_command` now answers a run command it cannot execute: `!STATE fault` then `!DONE <kind> 0 0`, so `s_busy` clears and the GUI is released instead of waiting for a `!DONE` that never comes. Added **`>FAULT CLEAR`** (`CMD_CLEAR_FAULT`), handled *before* the fault gate since it is the only recovery short of a power cycle — it forces safe first, then clears the latch, so clearing can never be a way to re-energise something by accident. Protocol addition, so §3.2 and §3.2.1 of the brief were updated, and the simulator and codec now carry it too. |
| CL-15 | 2026-08-05 | FW-09 abort lost at run start | The three `Proto_ClearAbort()` calls at run entry are gone, and **the function itself is deleted** — `proto.h` carries a comment saying why, because the only thing it was ever used for was the bug. The flag now has exactly three writers: `proto_post_run` clears it before the run is queued (the one point where clearing is correct), `>ABORT` and an invalidating fixture change set it, and `Proto_EvtDone` clears it on the way out. No window remains in which an operator stop can be swallowed. Correct by inspection at every point in a run; **BU-12 still has to prove it on hardware.** |
| CL-14 | 2026-08-05 | Boot banner not protocol-framed | Found while reviewing the GUI codec, which was correctly rejecting it. The five `console_puts` lines carried no `<`, `!` or `#` marker, and the banner led with a bare `\r\n` that framed as an empty line — two parse errors at the GUI end on every reset, per brief §3.1. All five are now `#`-prefixed with no leading newline, and `console_puts` documents the requirement for future callers. Protocol-visible, hence a closed item rather than only an activity-log line. |
| CL-13 | 2026-08-05 | FW-08 premature `!SAFE` | `Proto_SetFixture` no longer announces safety it has not achieved. It drops the arm locally, posts `CMD_FORCE_SAFE` carrying the new fixture, and the **sequencer** emits `!HV 0` → `!SAFE` → `!FIXTURE` once the rail is really down — published ordering preserved. The duplicate `!SAFE` is gone with it. If the post fails the instrument latches a fault and emits `!STATE fault` rather than `!SAFE`. A fixture change now also sets the abort flag, so declaring a move stops a run in flight instead of letting 500 V continue for up to 64 s — newly reachable, and newly necessary, once FW-07 let the command through mid-run. `CMD_FORCE_SAFE` also emits `!HV 0` before `!SAFE` on every path now, so `>SAFE` no longer drops the rail silently. |
| CL-12 | 2026-08-05 | FW-07 `>ABORT` could not stop a run | Three causes, all fixed. **RX is interrupt-driven** — `LPUART1_IRQHandler` defined in `log.c` (which owns the hand-rolled LPUART1 bring-up, so CubeMX generated no handler), NVIC priority 5 = `configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY`, bytes pushed to a queue from the ISR and re-armed there; an error callback clears overrun and re-arms, without which one overrun would deafen the instrument permanently. **`tComms` moved `osPriorityBelowNormal` → `osPriorityAboveNormal`** — it blocks on the RX queue so it costs nothing until a byte lands, and it must outrank the sequencer or it is never scheduled during a run. **Settle delays yield** — new `Board_SettleMs()` uses `osDelay` under the RTOS (`+1` tick, so a settle can never come out shorter than `HAL_Delay` gave) and `HAL_Delay` before the scheduler; `continuity.c`, `kelvin.c` and `insulation.c` use it. Raising the comms priority also forced a fourth fix: three threads write the console UART and `HAL_UART_Transmit` is not reentrant, so a preempted line was silently dropped — a lost `<` reply is a 2 s GUI timeout. All console output now goes through `Log_ConsoleWrite()` under a mutex, and `proto_emit` builds the CRLF into its buffer so a line leaves as **one** write. +5,888 bytes: the HAL's IT-receive path was previously discarded by `--gc-sections`. |
| CL-11 | 2026-08-01 | FW-05 GUI protocol, instrument side | `app/proto.c` — line parser, one `<` reply per command on every path including errors, `!` event streaming from the sequencer, and `!STATE`/`!FIXTURE`/`!HV`/`!SAFE`. Replaces the single-keystroke console. Netlist upload/download, whole-run continuity (verify and discover) and insulation added to the sequencer as `CMD_CONT_RUN`/`CMD_RES_RUN`/`CMD_INSUL_RUN`. `>INSUL ARM` refuses unless the fixture is `hv`; `>MANUAL RELAY` refused outright. Log lines now `#`-prefixed so the GUI can separate them. |
| CL-10 | 2026-08-01 | FW-01 ADS124S08 driver | Written. io vtable for CS/RESET/START/DRDY (all on expander U69, not GPIO), SPI mode 1, internal 2.5 V reference explicitly switched ON (REFCON is 00 at reset — selecting the reference is not enough), device-ID check, SFOCAL, RDATA-based reads, timed conversion waits because polling DRDY costs an I2C round-trip. Compiles clean under -Wall -Wextra. |
| CL-09 | 2026-08-01 | HW-06 one clock net | **Done in Matrix_Card 2** — `SPI1_SCLK` throughout including J101; `SPI1_SCK` no longer exists on the Matrix card. |
| CL-08 | 2026-08-01 | HW-02 sense-enable net names | **Done in Matrix_Card 2** — `HI_SENSE_EN1..32` / `LO_SENSE_EN1..32` present and driven by U66/U67 (HI) and U107/U108 (LO) on BUFF2. |
| CL-07 | 2026-07-29 | Mux enable pull direction — full verification requested | All 64 verified: sheet 2 R1–R32 and sheet 8 R33–R64, every one 100 kΩ to **+3V3**, none to GND. The +3V3 label sits at an identical (−31, +11) offset from the refdes on all 64 instances, and R1 and R33 were wire-traced explicitly to the +3V3 label. No resistor has a GND nearer than its +3V3. Sense muxes are U34–**U65** (32 of them). |
| CL-06 | 2026-07-29 | `I2C_EN1` / `I2C_EN2` purpose | Leftover access GPIO from an earlier concept, deliberately kept on the connector as spare lines. No function. Firmware must not drive them; treat as reserved. |
| CL-05 | 2026-07-29 | ADS124S08 control lines believed unrouted | **Not a gap — this finding was wrong.** U69 (MCP23017 at 0x25) drives all four from sheet 9: GPB0 → `ADC_RST_1`, GPB1 → `DRDY_1`, GPB2 → `ADC_CS_1`, GPB3 → `Start_SYNC_1`. They never needed to leave the card. No connector pins and no MCU pins are required; the pin-budget proposal is withdrawn. The error was checking whether the nets reached J101 and concluding they dead-ended, without checking whether they were driven locally on the same sheet. Firmware consequences are tracked in FW-01. |
| CL-04 | 2026-07-20 | LO_COM pull-down value | Fixed at 100 Ω, now fitted as R131, 0.01 %, 1206. |
| CL-03 | 2026-07-27 | `LO_COM` reported missing from the Control Card | Needs no connector pin at all; it returns through R131 to Matrix Card ground locally. What matters instead is a continuous ground return — folded into HW-03. |
| CL-02 | 2026-07-27 | `HI_COM` reported missing from the Control Card | Not missing. It is net `IN` — the Opto SPDT common, switched between `ADC_IN` (10 kΩ pull-up via R26) and `I_OUT` (excitation) — present on card-connector pin 29. A naming difference, not a routing gap. |
| CL-01 | 2026-07-27 | Multiplexer enable polarity — contradictory in v1.3 | Every CD4067 E pin carries a 100 kΩ pull-up to +3V3, force and sense alike. E is active LOW, so expander bit 1 = disabled, 0 = enabled. Initialise all mux OLAT registers to `0xFF`. Safe from power-on while the MCP23017s are still high-Z. |

---

## Activity log

### 2026-08-11 (later still still — Matrix Card confirmed on the shared bus, CL-25)
- **User confirmed directly**: "We are using same I2C bus which we are using for the HV1 card" -
  settling what CL-24 had left open (whether the Matrix Card's own onboard expanders share the
  HV cards' I2C2, or sit on the separately-confirmed I2C3 that U20 uses).
- Working through the consequence: U21/U20 (local, generates `LO_S1-4`/`HI_S1-4`) is genuinely
  I2C3-only and needed no change, but the Matrix Card's *other* eight expanders (`hi_en`/`lo_en`/
  `hi_sns`/`lo_sns`, i.e. U101/102/105/106/66/67/107/108) had been going through the same single
  `hi2c` parameter as U21 in `MatrixCard_Init` - wrong once the two are confirmed to be on
  different buses. Also realised the existing BUFF1/BUFF2 NTS0102 segment-switch inside the
  Matrix Card (already implemented, addresses reused a second time within the card itself) is a
  second, inner layer of the same problem CL-24 solved at the card-to-card level - the Matrix
  Card needs its own outer `HV_Card_EN1` gate (J1) exactly like each HV card needs its EN2/3/4,
  wrapping around the existing inner segment switch, not replacing it.
- **CL-25**: `MatrixCard_Init` now takes `hi2c_local` (U21, I2C3) and `hi2c_shared` (the eight
  expanders, I2C2) separately, plus `en_port`/`en_pin` (`HV_Card_EN1`). New public
  `MatrixCard_BusClaim()`/`BusRelease()`, used internally by every function touching the shared
  expanders and externally by `board.c`'s U69 (ADS124S08 control) callbacks, since U69 sits on
  the same shared bus. `board_init_ads124s08()` moved from `BOARD_MATRIX_I2C` to `BOARD_HV_I2C`
  to match. Full rebuild after every step: 0 errors, 0 warnings.
- Net effect: the address-collision problem CL-24 fixed for HV-vs-HV is now also fixed for
  Matrix-vs-HV and Matrix-vs-itself-on-two-segments. Nothing left open on this thread.

### 2026-08-11 (later still — shared I2C bus / HV_Card_EN gating, CL-24)
- **User traced the Control Card schematic further and corrected two things from earlier this
  session's read**: the Matrix-vs-4-wire architecture is 2-wire (already logged, unchanged), and
  separately, that J1's `LO_S3`/`HI_S3` naming maps to NTS0102 buffer enables on the Matrix Card
  as `matrix_card.h` already documented, but the *Matrix Card and every HV card also share one
  I2C bus* - confirmed directly by the user against real hardware, not inferred by this session.
- Traced the consequence in the schematic (`Control_Card-5.pdf` sheets `/uC/`, `/Isolator/`,
  `/GPIO_Expander/`): U20 (generating `LO_S1-4`/`HI_S1-4`) is on I2C3; the isolated I2C2 bus
  (`ISO_SDA2`/`ISO_SCL2`) is wired to every HV connector J1-J4 identically; `HV_Card_EN1..4`
  (PC5/PC6/PA10/PA9) exist as per-slot bus-segment enables through isolators U18/U19. Checked the
  actual pin config: CubeMX had those four pins under a stale label (`HV_CARD_DT_3_0` etc., from
  before the schematic was renamed) and configured as unused inputs - confirming firmware had
  zero handling for this collision.
- **CL-24**: implemented the fix - `hv_card.c` now gates every I2C-touching call behind
  `hv_bus_claim`/`hv_bus_release`; CubeMX pins relabelled and switched to outputs; `board.c` maps
  HV board index to physical slot (J2-J4, reserving J1 for the Matrix Card per HW-09) with a
  compile-time bound. Full account and diagram in `Doc/i2c_bus_sharing.md`.
- **Left deliberately open, as BU-13**: whether the Matrix Card's own onboard expanders share this
  same I2C2 bus, or sit on the separately-confirmed I2C3 that U20 uses, isn't resolvable from the
  schematic alone (no `I2C3_SDA`/`SCL` label found anywhere on J1's 50 pins) - `BOARD_MATRIX_I2C`
  left unchanged rather than guessed, since a wrong guess would move the collision, not remove it.
- Full `make all` rebuild after every step this session: 0 errors, 0 warnings throughout.

### 2026-08-11 (new session — HW-12 address check; FW-02 implemented; build fixed)
- **Did the 10-minute HW-12 cross-check the last session's handoff flagged**, before starting
  FW-02: rendered `Matrix_Card-7.pdf` sheet 9 and sheet 3 to images (PyMuPDF, since the sense
  side's binary address labels don't survive `pdftotext` extraction at all — confirmed by
  grepping the extracted text for `0x2` and getting nothing) and read the address off each
  expander directly. Found the straps in `matrix_card.h` were wrong for the sense side (not just
  unconfirmed) — see **CL-22**. Force side matched exactly, no change needed.
- **FW-02 implemented**: `test/kelvin.c` rewritten for 4-wire Kelvin against the ADS124S08 — PGA
  auto-ranging, zero-current-baseline offset subtraction, ratiometric-vs-current-source formula
  chosen correctly (HW-04 isn't done, so `OhmsFromCurrent`, not `OhmsRatiometric`). See **CL-23**
  for the full account, including why current reversal (BU-10) was deliberately left out rather
  than implemented against an unverified DAC8775 register map.
- **`bsp/board.c` gained the ADS124S08 wiring it never had**: a global instance, the U69 io
  vtable (cs/reset/start/drdy, each paying the BUFF2 segment-select the driver's own header says
  it needs), and a `board_init_ads124s08()` hooked into `Board_Init()`. FW-01 had written the
  driver; nothing had ever instantiated it.
- **Found and fixed two things that would have made every reading wrong even with correct
  code**: SPI1 was still CubeMX's 4-bit/mode-0 default (leftover from the removed AD7476) against
  the ADS124S08's required 8-bit/mode 1, and clocked at 32 MHz against its 10 MHz max. Fixed in
  `spi.c` and `HT_MK1.ioc` together so it survives a CubeMX regeneration.
- **Found the command-line build was broken independent of any of this**: `proto.c` (FW-05,
  closed 2026-08-01) and `ads124s08.c` (FW-01) were missing from `Debug/Core/Src/{app,drivers}
  /subdir.mk` and `Debug/objects.list` — the Eclipse IDE's own project index knew about them
  (their `.o`/`.d` files already existed in `Debug/`) but the generated make fragments used for a
  plain `make all` did not. Added both. Full `make all` now builds and links clean: 64872 B
  text, 104 B data, 24456 B bss, 0 warnings.
- Net effect: **`RES RUN` no longer fails every net by design** — it measures. Still unverified
  on real hardware; BU-01 (excitation current / system offset) and BU-08 (formula) are the
  remaining gates before trusting a specific number.

### 2026-08-11 (later still — U68 false-negative corrected; README synced; handoff finalized)
- **Corrected my own error from earlier today.** The claim that U68 (ADS124S08) was missing from
  `Matrix_Card-7.pdf` was wrong — caused by a verification script that truncated each page's
  extracted text at 2500 characters before searching it; page 8 (where U68 lives) has 7,596.
  Re-verified against the untruncated text: U68 = `ADS124S08IRHBR`, full 33-pin list present,
  U69 alongside it on the same sheet. The "page 9" the user cited and "page 8" I found both
  point at the same sheet — its title block reads `Id: 9/8` (KiCad hierarchical sheet 9, 8th
  and last page of this PDF). **FW-02 is not blocked.** HW-12 rewritten to reflect this; the one
  thing still genuinely open from that finding is confirming the new I2C address strapping
  (0x20/21/22/24/26 across U66/U67/U69/U107/U108) actually resolves the old U101-vs-U69
  collision — not yet cross-checked against the force-side sheet.
- **`README.md`'s hardware baseline table updated** to the new file names
  (`Control_Card-5.pdf`/`Matrix_Card-7.pdf`/`HV_Card-3.pdf`), with pointers to HW-11/HW-12/HW-08
  so a reader lands on the open questions, not just the filenames.
- Handoff prompt for the next session finalized — see below.

### 2026-08-11 (later — DAC8760 datasheet confirmed incompatible; schematic swap found; HW-12 raised; handoff prepped)
- **User added `Datasheet/dac8760.pdf` and asked to check it.** Confirmed directly (not via search this time): `AVDD` recommended operating range is a hard **10–36 V minimum**, independent of current-range selection — `DVDD` alone being 2.7–5.5 V doesn't help, since that's only the digital side. This rules DAC8760 out for a 3.3 V-only board exactly as suspected; LTC2662-16 (HW-11) stands as the lead candidate.
- **Found the `Doc/` schematic set had been swapped locally and left uncommitted**: `Matrix_Card-7.pdf`/`Control_Card-5.pdf`/`HV_Card-3.pdf` replaced the files everything above is tracked against. Checked all three for what moved — **HW-08 (R3003 5 kΩ) looks fixed**, **HW-09 may be improved** (6 connectors now vs. 4), but **the ADS124S08 is absent from the new Matrix Card export entirely** (8 pages, no sheet 9, no U68/U69/ADS124/AIN/DRDY text anywhere). Raised as **HW-12** — this blocks starting FW-02 until resolved. Asked the user to confirm; they said it's present on "page 9" of what they're viewing, which does not match the file actually in `Doc/` (verified by page count, full-text search, and file hash) — flagged as unresolved, not assumed either way in either direction.
- **User asked to pause the DAC decision (HW-11 stays open) and prepare a handoff prompt for the next chat**, covering remaining FW/GUI work. Categorized: ready now (FW-06, GUI-07, DOC-01/02/03), blocked on a product decision (GUI-04/05/06/08), blocked on HW-12 (FW-02), out of scope for a coding session (BU-* hardware bring-up items).

### 2026-08-11 (DAC accuracy re-verified against source datasheets; DAC8775 alternatives; HW-11/DOC-03 raised)
- **Re-derived resistance-accuracy calculation checked line-by-line against `Datasheet/ads124s08.pdf` and
  `Datasheet/dac8775.pdf`.** CM-floor formula and FSR-at-gain-128 confirmed correct. Two real errors found —
  see CL-21: two mis-picked noise-table rows (more margin, not less) and a DAC8775 TUE row that doesn't apply
  at this design's actual 1–3 mA operating point (the applicable spec is ±0.14 %FSR, not the ±0.4 % "4 to
  20 mA"-specific row). Conclusion unchanged — calibration is mandatory regardless, because the noise floor
  binds before the DAC error does. `Doc/4wire_resistance_validation.md` §7.6 rewritten with sourced numbers.
- **DOC-03 raised**: the same doc's §7.1 still targets ~5 mA excitation, superseded by BU-09's 3 mA revision
  (closed 2026-08-01) that was never propagated into this section. Flagged in place, not re-derived this pass.
- **HW-11 raised**: DAC8775 is hard to source (mixed lifecycle signals across distributors). Researched
  alternatives — TI DAC8760 (same family, single-channel, easiest port, slightly worse TUE) and ADI AD5758
  (single-channel, better TUE per one search-sourced figure, different register map, full new driver). Only
  channel A of the DAC8775's four is used today, and the real current (1–3 mA) is well under any candidate's
  native range, so a single-channel part is not a functional downgrade — this is an availability/port-effort
  decision, not an accuracy hunt, since every candidate needs calibration anyway.
- **Later same day: reframed after confirming this board only has 3.3 V available.** DAC8775/DAC8760/AD5758
  are all industrial 4-20 mA loop drivers that need wide supplies (10 V+) as a matter of their fundamental
  purpose — not just DAC8775-specific, the whole product category is the wrong fit. Found **LTC2662-16**
  (ADI) instead: purpose-built low-range current-source DAC, 2.85–5.5 V single supply, ranges down to
  3.125 mA full scale, 16-bit, SPI. Confirmed in stock at DigiKey (214 units, $49.18 @ qty 1, MOQ 1) — this
  is now the lead candidate over DAC8760, which would need an added boost regulator this board doesn't have.
  HW-11 rewritten with this finding.

### 2026-08-10 (later — required_format report examples; netlist header fix; GUI-08 found)
- **`gui_flutter/required_format/`** (new, user-provided) sets the report format by example:
  the old GUI's continuity CSV/PDF, plus a real required netlist (`example_netlist27072026
  .xlsx`). Added the resistance and HV-insulation counterparts in the same convention
  (metadata block + Summary + Results table, same navy/green/red styling) — column names and
  status enums traced to `codec.dart`/`messages.dart`, not invented; see the new
  `required_format/README.md` for the field-by-field mapping. Neither report writer exists in
  code yet; these are the target shape for when GUI-05 (run history storage) is answered.
- **CL-20**: the required netlist's actual headers (`Src Pin #`/`Dst Pin #`) didn't match any
  alias `netlist_file.dart` recognised, so the file the user just declared required could not
  be loaded at all. Fixed, with a regression test.
- **GUI-08 found while verifying the fix**: the required-format example numbers pins
  per-connector (`Conn ID` + `Src Pin #`), so a straight-through harness has the same pin
  number on both sides of every row — but the parser, `NETLIST ADD`, and the matrix routing
  all use one flat `1..256` address with no connector concept. Every row in the actual example
  file collides and is correctly rejected. This is deeper than the header-naming issue: it
  needs either pre-globalised pin numbers in the sheet, or a `Conn ID` → base-offset map built
  into the firmware/GUI. Not fixed — pinned by a test and logged, per the standing rule that a
  real finding gets an ID, not just a comment.
- Full `flutter test` re-run: 181/182 pass. The one failure is pre-existing, unrelated WIP
  (`netlist_file_generated_test.dart` from `ee1e0f7`, expects an uncommitted `test_netlists/`
  directory) — flagged to the user, not silently fixed or deleted.

### 2026-08-10 (tracker sync — five days of untracked work folded in)
- Reviewed git history and code against this log for the first time since 2026-08-05 and found
  three real deliverables that had never been logged: the firmware heartbeat, the Flutter GUI
  port, and the netlist-file-browsing / protocol-coverage-audit session. All three folded in
  below and in Open/Closed items.
- **Flutter confirmed as the primary GUI build** (user decision, 2026-08-10). `gui/` (Python) is
  superseded — kept on disk for reference, not tracked for new work. GUI-03 is the one item that
  stays open against it, now marked legacy.
- **FW-04 closed retroactively as CL-19.** The mux-addressing rework it called for was already
  done in `f778ba7` (2026-08-01) as a side effect of FW-03, but nobody closed the ticket. Found
  by rereading `matrix_card.c` for this review, not by new work. The 400 kHz-vs-100 kHz half of
  the original item is still open, moved under BU-03.
- Two new Doc/ files (`GUI_protocol_command_coverage.md`, `GUI_protocol_proposed_commands.md`,
  both 2026-08-08) folded into the document map as reference material — README updated so they
  don't become an unlisted fifth/sixth tracking doc. New items GUI-04 through GUI-07 raised from
  their findings.
- Net effect: no code changed this session. **Biggest unresolved risk is unchanged** — FW-02
  (4-wire resistance) has not been started, so `RES RUN` still fails on every net. BU-12 (abort
  on real hardware) has no evidence of being exercised since the 2026-08-05 fix.

### 2026-08-08 (netlist file browsing; GUI protocol coverage audit)
- **Real Excel netlist browsing** (`gui_flutter/lib/htproto/netlist_file.dart` +
  `netlist_picker_io.dart`). Both netbars (MTX, HV) now open a real `.xlsx` file instead of a
  stub. MTX uploads the parsed pairs via `NETLIST BEGIN/ADD/END`, the same path a saved
  cross-continuity scan uses. A malformed file fails loudly (`NetlistFileFormatException`)
  instead of a silent no-op.
- **Folded in prior uncommitted GUI work**: `FAULT CLEAR` wiring, `MANUAL PATH`/`MANUAL OFF`
  diagnostics, a live wire-traffic Console tab in the log bar, and a serial port selector.
- **Full audit of every tappable control in `gui_flutter/lib/` against the protocol** —
  `Doc/GUI_protocol_command_coverage.md`. Found and fixed the real wiring gaps (group 1) and
  removed the controls that shouldn't exist (group 2 — `MANUAL RELAY`; the firmware refuses it
  by design, brief §0 says don't offer it). Two groups remain open: decide-then-build GUI-only
  features (Export CSV, Print report, Cal certificate — blocked on brief §8 Q2/Q4, now GUI-04/
  GUI-05) and firmware-side proposals (`Doc/GUI_protocol_proposed_commands.md`, now GUI-06).
- **One correctness bug found while wiring `FAULT CLEAR`**: `_onDone` computed `pass =
  m.failed == 0` unconditionally, so a run refused by a latched fault (`!STATE fault` then
  `!DONE <kind> 0 0`, per FW-10) read as a pass. Fixed — `_onDone` now checks `inFault` first
  and leaves the result unset.
- Test suite grew accordingly (`manual_and_fault_test.dart`, `netlist_file_test.dart`,
  `netlist_file_load_test.dart`, `netlist_select_flow_test.dart`, `netlist_upload_test.dart`,
  `port_selector_test.dart`, `wire_log_test.dart`, `diag_controls_flow_test.dart`).

### 2026-08-07 (firmware heartbeat; Flutter GUI port)
- **Heartbeat fixes a false "link lost."** Brief §3.5.3's 5 s no-traffic rule was firing on a
  perfectly healthy link about five seconds after connecting, because the instrument said
  nothing at all when idle. `Proto_EvtHeartbeat()` re-announces `!STATE` every
  `PROTO_HEARTBEAT_MS` (2000 ms — two beats inside the 5 s window), and `CommsTask` swapped
  `osWaitForever` for a timed wait clocked off `osKernelGetTickCount()` so a steady trickle of
  RX bytes can't starve it. Deliberately not shared with `>STATUS`'s reply logic
  (`proto_state_name()` is separate) — a heartbeat claiming `idle` mid-run would clear the
  GUI's arm. Verified on a NUCLEO-G474RE: 90 s connected, no link loss, 65 beats at 1.997 s.
- **`gui_flutter/` — a full Flutter/Dart rebuild of `gui/`, no Python at runtime.** `htproto`
  ported file-for-file (codec, messages, connection manager, simulator); the design brief's CSS
  tokens and every component class rebuilt as Flutter widgets with the page's own SVG icons
  parsed at runtime; the three canvases as `CustomPainter`s. The safety rules live only in
  `app_state.dart`, tested without a display: safe-to-handle comes from `!SAFE` and nothing
  else, link loss forces unknown, any fixture change drops the arm.
  Serial is the one third-party dependency (`flutter_libserialport`), confined to one file
  nothing else imports. `test/layout_test.dart` renders every view at four window sizes in both
  themes plus thirteen specific states — found 27 `RenderFlex` overflows on its first run that
  neither `flutter analyze` nor the headless tests could see.
  Verified: `flutter analyze` clean, 130 tests, runs against both the simulator and a real
  NUCLEO-G474RE over the ST-LINK VCP.

### 2026-08-05 (GUI-01 and GUI-02 fixed)
- **GUI-01 fixed.** `_execute` now releases `_io_lock` before calling `_link_lost`; the
  send-failure path surfaces `LinkLostError` and drops to `LINK_LOST` instead of hanging.
  Regression test `TestSendFailure` runs the call in a thread so a regression fails the test
  rather than deadlocking the suite. Re-verified with the original repro: prompt
  `LinkLostError`, link `link_lost`.
- **GUI-02 fixed.** Signed parsing for the five int32 wire fields (`!RES` milliohms,
  `!INSUL` leak_mohm, `hv_mv` in `<STATUS` and `!HV`, `<LIMITS` values); pins, counts and
  progress stay unsigned. One existing malformed-case test had `hv_mv=-5` listed as invalid —
  it was asserting the bug, now corrected. Regression test `test_signed_measurement_values`.
- Suite: **59 tests, all passing** (was 57), run repeatedly with no flakiness. The two defects
  survived their own verification precisely because no test covered them — both are covered
  now.
- **GUI-03 remains open** (acknowledged, not started): the three minor items from §8.4 —
  decode `errors="replace"`, the `_transport` nulling race, empty-line tolerance.
- Brief §8.2 updated to record the fixes.

### 2026-08-05 (packaged as a standalone exe)
- **`build_exe.cmd` produces `dist\HT_MK1_GUI.exe`**, ~8 MB, PyInstaller one-file. The exe needs
  no Python on the target machine; PyInstaller is a build-time dependency only. `--sim` runs the
  simulator in-process for demos and training, and says on the console that nothing shown is a
  measurement.
- **Two real defects surfaced only when running the packaged exe**, both now fixed:
  - `index.html` and `live.js` are data, not imports, so PyInstaller could not find them.
    Added explicitly at build time, and `server.py` resolves them via `sys._MEIPASS` when frozen.
  - **Session logs defaulted to a relative `sessions/`.** Launched from `C:\Windows` the exe
    died with `PermissionError: [WinError 5]` on *connect*, because the log is opened as part of
    connecting — so an unwritable working directory took the whole link down. Now
    `%LOCALAPPDATA%\HT_MK1\sessions` via a new `htproto/paths.py`, with a temp-dir fallback and
    a `--log-dir` override. The Tk frontend had the same bug and got the same fix.
- Also added `.cmd` launchers (`ht-demo`, `ht-sim`, `ht-gui`) after the module-not-found trap:
  `python -m htweb` only resolves from `gui\`, and running it from `gui\tests` fails.
- Verified by running the built exe from `C:\Windows` — page served, connect, fixture, discover
  all fine, session log written to LOCALAPPDATA. Suite 95 tests.

### 2026-08-05 (frontend rebuilt on the approved HTML design)
- **The frontend is now the mock-up itself** (CL-18). `gui/htweb/index.html` is
  `Doc/HT_MK1_GUI_Proposal.html` verbatim — markup, CSS and every render function — served by a
  stdlib HTTP + SSE bridge and driven by real instrument traffic. Tk could never have matched
  that design; using the design as the frontend is the only way to get "exactly the same".
- The one hole cut in the mock's closure is a `window.HT_SEAM` export, so `live.js` can replace
  the three simulated run functions and rebuild the net model from a real netlist. Nothing that
  draws was touched.
- **Recorded honestly in `gui/README.md`: what is live and what is still presentation.** The
  protocol is narrower than the design — it has no fixture/connector map, no net names, no HV
  card-stack detection. Those panels keep the mock's data. Everything else — link state, HV,
  fixture, results, progress, faults, netlist, cal, limits, abort, arm — is real.
- The server binds loopback unless `--allow-remote`; the page can arm and fire 500 V.
- Suite now **91 tests**. `node --check` used on `live.js` and on both inline blocks of the page
  after the seam edit, since a syntax error in the frontend would not show up in the Python suite.

### 2026-08-05 (FW-10 closed, GUI tasks 3–10 built)
- **FW-10 fixed** (CL-16). A run command that cannot execute now says so — `!STATE fault` then
  `!DONE <kind> 0 0` — instead of leaving `s_busy` latched and the GUI waiting forever. Added
  **`>FAULT CLEAR`**, handled before the fault gate because it is the only recovery short of a
  power cycle; it forces safe first, so clearing a latch can never re-energise anything.
  Protocol addition, so the brief, the codec and the simulator were updated with it.
- **GUI tasks 3–10 built** (CL-17) — `gui/htgui/`, Tk, standard library only. Eight screens,
  persistent HV banner, always-reachable abort, guided fixture handover, netlist manager,
  faults with the clear-latch action, history with first-pass yield and a fault pareto, and
  diagnostics.
- **The safety rules live in one Tk-free module** so they are testable without a display, and
  the model is deliberately pessimistic: `!SAFE` is the only thing that produces "safe to
  handle", and link loss forces "unknown".
- One design point worth recording: after a continuity or resistance run the GUI shows
  **unknown**, not "energised". Those runs never emit `!SAFE`, so there is no evidence either
  way — and claiming "energised" would assert something the instrument never said, just as
  claiming "safe" would. Both are wrong; unknown is the honest answer and is still fail-safe.
- Suite now **83 tests**, including a smoke test that drives the real Tk app against the real
  simulator over a socket. Firmware links clean at **65,184 bytes**.

### 2026-08-05 (FW-09 closed, GUI-01/02 verified fixed — release prep)
- **FW-09 fixed** (CL-15). Removed the three run-entry `Proto_ClearAbort()` calls and deleted the
  function, leaving a comment in `proto.h` explaining why it must not come back. The abort flag
  now has one clear before the run is queued and one after `!DONE`, and nothing in between.
- **GUI-01 and GUI-02 verified fixed on the GUI side.** Re-ran both probes: the send-failure case
  now returns `LinkLostError` instead of hanging, and `!RES 12 34 -5 pass` parses to
  `milliohms=-5`. GUI-03 (the three minors) is still open — `parse_line('')` still raises.
- **FW-10 raised** while closing FW-09: `run_command` returns early on a latched fault *before*
  the switch, so a dequeued run never reaches `Proto_EvtDone` — `s_busy` sticks at 1, every later
  run is refused `EBUSY`, and the GUI waits for a `!DONE` that never comes. No protocol command
  clears a fault either, so recovery is a power cycle.
- Links clean at **64,872 bytes**. Release readiness written into the snapshot: the one thing a
  user will notice immediately is that **`RES RUN` fails on every net** until FW-02.

### 2026-08-05 (GUI side acknowledged §8.4)
- The GUI side amended §8.2 of the brief: the codec and connection manager are conformant *to
  the brief as written*, with a pointer to §8.4 for the deadlock and the signed-value rejection,
  **both reproduced independently on their side**. Accurate — no correction needed.
- **Re-verified against their code: neither is fixed yet.** The send-failure repro still hangs
  `execute()` forever, and `!RES 12 34 -5 pass` is still rejected. Their suite still passes at
  57 tests, which is expected — neither defect has a test covering it, which is half of why
  they survived. GUI-01 and GUI-02 stay open, now marked acknowledged.

### 2026-08-05 (tracker audit)
- Checked the tracker against everything this session produced. Three things were being carried
  in prose or in the brief but were not tracked items — now fixed:
  - **FW-09** — the abort-clear race. I raised it verbally in the first exchange of the day,
    offered to log it, and then never did; FW-07 took the number and the point got lost. It is a
    real hole in the abort path and the FW-07 fix made it *more* reachable, so this is exactly
    the kind of thing that must not live only in conversation.
  - **GUI-01 … GUI-03** — the review findings existed only in brief §8.4. Added a `GUI-` prefix
    and an "Awaiting the GUI side" section so the outstanding set is visible from one place.
  - **DOC-02** — `HT_ENABLE_ADS1232` defaults to 1 while README says "default off". Noticed
    during the hand-link and mentioned in passing; now an item.
- Also promoted the boot-banner fix to **CL-14**. It changed protocol-visible behaviour, so it
  should be findable in the closed table, not only in an activity-log bullet.

### 2026-08-05 (GUI tasks 1 and 2 reviewed)
- Reviewed the `gui/` code against §6 of the brief — codec, messages, connection manager and
  tests. Suite runs clean: **57 tests, all passing**. Structure and intent are right; findings
  written up as **§8.4** of the brief. Their code is theirs to fix — not edited here.
- **One blocker.** A send failure deadlocks the connection manager: `_execute` calls
  `_link_lost()` while holding `_io_lock`, and `_link_lost` → `_fail_all_pending` takes the same
  non-reentrant lock. Reproduced — `execute()` never returns, and the lock is never released, so
  every later command hangs too. This is the ordinary "link dropped mid-run" path that §6 says
  gets tested by pulling the plug. Their failure tests only cover receive-side failures.
- **One conformance bug.** `!RES <milliohms>`, `!INSUL <leak_mohm>`, `hv_mv=` and the `LIMITS`
  values are printed `%ld` from `int32_t`, but the codec parses them as unsigned — a negative
  reading is rejected as a protocol violation. Masked today because `RES RUN` always reports
  `0`/`fail_high`; it will bite the moment FW-02 lands, since a near-zero 4-wire resistance goes
  negative once offset is subtracted (BU-10). Told them before it costs a debugging session.
- **A firmware bug fell out of the review.** The boot banner was not protocol-framed — `[boot]`
  lines carried no `#`, and the banner led with a bare `\r\n` that framed as an empty line, both
  parse errors at the GUI end per §3.1. Fixed: all five `console_puts` lines are now `#`-prefixed
  with no leading newline. The GUI was right to reject them.

### 2026-08-05 (FW-07 and FW-08 fixed)
- **`>ABORT` works.** The abort flag the run loops poll could never be set, because `tComms` sat
  below `tSequencer` and the sequencer never yielded — its settle delays were the stock
  busy-spin `HAL_Delay`. Fixed on three fronts: interrupt-driven console RX, `tComms` raised
  above the sequencer, and `Board_SettleMs()` yielding instead of spinning. CL-12.
- **A fourth fix fell out of the third.** Raising the comms priority meant it could preempt the
  sequencer mid-line, and `HAL_UART_Transmit` is not reentrant — three threads write that UART,
  so a preempted line would have been silently dropped. A dropped `<` reply is a 2 s GUI
  timeout and a "link lost". All console output now goes through `Log_ConsoleWrite()` under a
  mutex, and each protocol line leaves as a single write with its CRLF built in. **This one was
  a regression I introduced and caught in review, not a pre-existing bug** — worth remembering
  that raising a task's priority is a change to every shared resource it touches.
- **FW-08 fixed** — the fixture path posts the force-safe and lets the *sequencer* emit
  `!HV 0` → `!SAFE` → `!FIXTURE` once the rail is down, in the published order. CL-13.
- **New hazard closed while in there:** fixing FW-07 made "operator declares a fixture change
  during a live run" reachable for the first time. It now aborts the run rather than letting an
  insulation run continue at 500 V for up to 64 s.
- Also: every force-safe now emits `!HV 0` before `!SAFE`, so `>SAFE` no longer drops the rail
  without telling the GUI. Brief updated for all of it — the contract itself did not move.
- Links clean at **64,920 bytes**, up 5,888 from 58,932. The increase is the HAL's IT-receive
  path (`HAL_UART_IRQHandler`, `UART_RxISR_*`, `UART_Start_Receive_IT` ≈ 4.9 kB), which
  `--gc-sections` used to discard when the console was transmit-only. 12.4 % of flash.
- Raised **BU-12** — this was a scheduling bug, and a clean build proves nothing about
  scheduling. Abort must be exercised on real hardware.

### 2026-08-05 (later still — GUI side folded in the answers)
- The GUI side struck both §8.2 questions as answered, folded the §8.3 refinements into
  deviations 2, 3 and 9, and **added two more from reading the corrected §3.2**: `SAFE`,
  `MANUAL PATH`, `MANUAL OFF` and idle `ABORT` reply `<OK started` not `<OK` (13), and `STATUS`
  never reports `running` (14). Both verified against `proto.c` — correct, and 14 is FW-06.
- Running total from the GUI side: **fourteen items raised, thirteen real**, one caused by this
  brief. Three firmware defects found this way — the two fixed in `5d837d8`, plus FW-07.
- Still open and **not started**: FW-07 / FW-08, and the review of the `gui/` code itself
  (task 1 and task 2 are both sitting uncommitted in the working tree).

### 2026-08-05 (later — GUI task-2 review returned)
- The GUI side verified its protocol layer against the brief and added **§8.2**: two questions
  and twelve simulator deviations. Checked all fourteen against `proto.c`/`tasks.c`; answers in
  the new **§8.3**.
- **Their question 1 found FW-07**, which is the serious one. They asked whether the GUI should
  lengthen its 2 s timeout during a run, because §3.2.1 said non-run commands were "queued
  behind the run". That wording was mine and was wrong — replies are never queued. But chasing
  it down showed the comms thread is *starved* for the whole run: `tComms` sits below
  `tSequencer` in priority and the sequencer never yields, because the settle delays are the
  stock busy-spin `HAL_Delay`. **`>ABORT` therefore cannot stop a run at all.** Raised FW-07.
- **FW-08 found alongside it** — `Proto_SetFixture` emits `!SAFE` on *posting* the force-safe,
  not on its execution, so the instrument can claim safety while the rail is still up. Masked
  by FW-07 today; fixing FW-07 unmasks it. Do them together.
- Fixed the §3.2.1 wording that caused the question, and answered their question 2 from source:
  `!HV 0` is emitted even when the rail was already at 0; **no** `!STATE idle` accompanies the
  arm drop; and `!SAFE` arrives twice for one fixture change and is idempotent.
- Of their twelve simulator deviations, **eleven are correct**. Number 9 is backwards — their
  simulator answers mid-run commands immediately, which is right; the brief was wrong. Also
  told them the `HV SET` arm check runs *before* the range check, so an unarmed negative value
  gives `ENOTARMED` and not `ERANGE`, and that the 10 mV `!HV` deadband their ramp livelocked
  on never existed — it was a stale line in §3.4, already corrected earlier today.
- No firmware changed. FW-07 and FW-08 are logged, not started.

### 2026-08-05 (GUI brief reconciled with the firmware)
- **§3 of `Doc/GUI_development_brief.md` now matches `proto.c` / `tasks.c`.** Commit `5d837d8`
  changed protocol *behaviour* and only §8.1 was updated — §3 is the normative section the GUI
  is built from, so an AI reading §3 alone would have built to the old behaviour. Everything
  below was checked against the source, not the doc.
- New **§3.2.1 "When a command is accepted"** carries what were previously only answers in
  §8.1: run commands refused with `ERR EBUSY` and **not queued**; `ABORT` answered immediately
  and never queued; netlist required by `CONT RUN verify` *and* `RES RUN`; `HV SET` non-zero
  refused with `ERR ENOTARMED`; pins 1-based `1..256`; fixture change invalidates arming with
  `!HV 0` → `!SAFE` → `!FIXTURE`.
- Corrected the wrong notation in safety rule 5 — `EVT FIXTURE HV` is not a thing, the event is
  `!FIXTURE hv`.
- **Four reply strings in §3.2 did not match the firmware.** `SAFE`, `MANUAL PATH` and
  `MANUAL OFF` answer `<OK started`, not `<OK`, and `ABORT` answers `<OK` mid-run but
  `<OK started` when idle. The brief demands byte-for-byte conformance, so these mattered.
- **`!SAFE` is not emitted by continuity or resistance runs** — they never raise the rail. §8.1
  implied it was emitted after every abort. Now stated in §3.3, §3.4 and §8.1, together with
  the rule that "safe to handle" keys off `!SAFE` and never off `!DONE` or event ordering.
- Also documented, all verified in source: `NETLIST GET` is the one command with more than one
  `<` reply; `!FIXTURE mtx` can arrive unsolicited (and even alongside an `EBUSY`, because
  `CONT RUN`/`RES RUN` assert the fixture before the busy check); a bare `>` gives
  `ERR ESYNTAX empty` but a truly empty line gets no reply; the 72-character line limit;
  `!STATE fault` and `!RES fail_low` are defined but never emitted; `HV SET` does not yet drive
  the rail, the insulation run does.
- Raised **FW-06** — `>STATUS` never reports `running` or `fault`, so a GUI reconnecting mid-run
  is told `idle`. Documented rather than changed: the reply is protocol-visible and the GUI is
  being built against it.
- Docs only, no firmware change, so no rebuild.

### 2026-08-01 (docs + GUI)
- **Document clear-out.** Thirteen documents down to four living ones, with `README.md` as
  the map and the rule "no new parallel documents without removing one". Deleted as
  superseded: operation doc v1.1 and v1.3, `HT_MK1_Functionality.md` (described
  `Matrix_Card-2`, two revisions stale), `Operation.txt`, `working_principle.md` (described
  the CD4067 scheme that no longer exists), and the original SAD. All recoverable from git.
  `ADS1232_bench_wiring.md` merged into the validation doc as Appendix A.
- **CD74HC4051 datasheet read (SCHS122O).** ΔrON between channels is **10 Ω max**, which
  largely closes BU-09. rON is only characterised from 4.5 V though (typ 70 / max 160 at
  25 °C), and the card runs at 3.3 V — so the **excitation target drops from 5 mA to 3 mA**,
  which holds at worst-case rON on both the compliance and common-mode sides.
- **`Doc/GUI_development_brief.md`** written for the external GUI effort: protocol contract,
  task breakdown, acceptance criteria, and the safety rules the GUI must implement. The
  firmware↔GUI protocol **does not exist yet on either side** — the brief defines it as a
  contract, and implementing the instrument half is now a firmware task (FW-05).

### 2026-08-01 (later)
- **FW-03 done** — `matrix_card` reworked for Matrix_Card 2. The previous version was
  written against rev 6 and would have driven the wrong multiplexer on every call: 16 vs 32
  muxes per bank, 4 vs 3 select bits, `>>4` vs `>>3` pin decode, one vs two I2C segments.
- **FW-01 done** — `drivers/ads124s08`. Takes an io vtable for CS/RESET/START/DRDY because
  all four are on expander U69 rather than GPIO; conversions are timed from the data rate
  rather than polled on DRDY, since each poll would cost an I2C round-trip.
- Confirmed from SBAS660C: **SPI mode 1**, and the internal 2.5 V reference is **off at
  reset** — `REFSEL` selects it but `REFCON` must switch it on, an easy one to miss.
- Closed **HW-02** and **HW-06** (both already fixed in Matrix_Card 2) and **BU-02**
  (dissolved — rev 2 removed the AD7476, so SPI1 has one device).
- `kelvin.c` now fails loudly instead of reading a chip that no longer exists on the card;
  the FW-02 requirements are recorded in place.

### 2026-08-01
- Built and validated a 4-wire Kelvin bench rig on a NUCLEO-G474RE with an **ADS1232** as a
  stand-in for the ADS124S08. **Measured a 0.033 Ω resistor to 0.4 %** (predicted code
  7,539, measured 7,553–7,705). Full write-up in `Doc/4wire_resistance_validation.md`.
- Proved the ratiometric method end to end: because REFP sits on the same rail that drives
  the divider, the excitation cancels and no current calibration was needed at all. This is
  the concrete argument for HW-04 on the product board.
- Measured noise floor **±0.6 mΩ at 0.53 mA** on flying leads with a marginal joint; scales
  to ±0.06 mΩ with a 470 Ω divider pair.
- Root causes found along the way, all now documented as recognisable signatures: floating
  DOUT (`code = -1`), SCLK not reaching the ADC (`code = 0`), ~50 % silent link corruption,
  **inputs at ground outside the PGA common-mode window** (the expensive one), a misread
  full-scale convention, and a tare that captured the signal itself.
- Raised BU-07 (common-mode headroom shrank when the muxes improved) and BU-08 (the two ADCs
  use different full-scale conventions — do not copy the formula).
- Added `drivers/ads1232` — bench-only, gated on `HT_ENABLE_ADS1232`, 0 bytes when off,
  `#error` if left enabled in a Release build.

### 2026-07-29
- Hardware owner answered the eight open HW items; each checkable claim was verified against the
  schematics.
- **HW-01 withdrawn.** U69 (0x25) drives `ADC_RST_1`, `DRDY_1`, `ADC_CS_1` and `Start_SYNC_1` from
  GPB0–GPB3 on sheet 9. The "unrouted ADC control lines" finding was wrong, and with it the
  connector pin-budget and MCU pin proposal. Closed as CL-05.
- **HW-07 verified** across all 64 multiplexer enables — pull-ups to +3V3, none to GND. Closed as
  CL-07.
- **HW-05 closed** — the `I2C_EN` lines are deliberate spares from an earlier concept.
- HW-02 refined: the expanders to rename are U66 and U67; U69 must be left alone. Sheet-9 refdes
  confirmed as U66 @ 0x23 (HI), U67 @ 0x24 (LO), U69 @ 0x25 (ADC control).
- HW-03 agreed — Matrix card moves to the non-isolated domain.
- HW-08 flagged: the intent (0.245 V, so 10 M : 5 k) is right, but HV_Card-1.pdf in the repo still
  shows R3003 = 50 kOhms. Needs re-export.
- HW-10 raised: no pull resistors on the three U69-driven ADC control lines, which float until
  firmware configures the expander.
- HW-04 clarified — it is an on-card net to U68 AIN2 for measuring excitation current, not a wire
  to the Control card. Still open.
- Net effect: **zero blocking items.**

### 2026-07-28 — `f863c06`
- GUI front-end proposal added (`Doc/HT_MK1_GUI_Proposal.html`).

### 2026-07-27 — `cdb0520`
- Reviewed the revised schematics `Control_Card-4.pdf` (2026-07-12) and `Matrix_Card-6.pdf`
  (2026-07-11) against operation document v1.3. HV_Card-1 unchanged.
- Identified the headline change: **resistance measurement redesigned from 2-wire to 4-wire
  Kelvin.** New 32-multiplexer sense array (sheet 8, U34–U65) tapping all 512 harness pins;
  ADS124S08 24-bit Σ-Δ ADC (U68, sheet 9) reading `HI_SENSE` − `LO_SENSE` differentially;
  R131 changed 100 kΩ → 100 Ω 0.01 %; three more MCP23017 (0x23/0x24/0x25); mux address
  lines moved off MCU GPIO onto Control-card MCP23017 U21.
- Wrote `Doc/Harness_Tester_Operation_Document_v1.4.docx` — new §1.4 (Kelvin architecture),
  §7 rewritten (compliance characterisation, ratiometric options, PGA gain/range table),
  §5.3 sense-array init, faults F11–F14, open-items block at the front. §3 and §4 (HV)
  carried over unchanged.
- Raised HW-01 … HW-09, FW-01 … FW-04, BU-01 … BU-06. Closed CL-01, CL-02, CL-03.
- Created this log file.

### 2026-07-21 — `cff9623`
- Schematics re-issued: `Control_Card-4.pdf` and `Matrix_Card-6.pdf` replace `Control_Card-1.pdf`
  and `Matrix_Card-3.pdf`. `ht_architecture.html` removed.

### 2026-07-20 — `6a5c829`, `f4d028f`
- LO_COM pull-down fixed at 100 Ω; resistance self-calibration plan added to `fw_status.txt`.
- HV_Sense finalised at 0.245 V for 500 V, with R3003 50 kΩ → 5 kΩ deferred to the next
  schematic revision.

### 2026-07-17 — `c9a5d04`, `62488a3`
- Operation document renamed to v1.3; `fw_status.txt` synced with the v1.3 review; hardware
  owner's clarifications folded in.

### 2026-07-16 — `fe38b94`
- v1.3 firmware-engineering review of the Harness Tester operation document.

### 2026-07-14 — `9b45613`
- Firmware reconciled with the `Doc/` schematics: bus and ADC maps corrected, insulation
  measurement reworked to the leakage node, HV control model fixed (no enable/discharge GPIO).
- Established that the schematics are the source of truth over the prose documents.

### 2026-06-17 — `4318fb2`
- Device / card / test driver stack added, plus logging and RTOS tasks, and Nucleo bring-up.

### 2026-06-16 — `56553f0`, `18d6ed9`
- Project start. Peripherals configured in CubeMX; `fw_status.txt` created.
