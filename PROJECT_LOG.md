# HT_MK1 — Project Log

One place to see where the project stands: what is open, what is closed, and what happened on
each working day.

- **Status snapshot** and **Open items** are live — edit them in place as things move.
- **Closed items** and **Activity log** are append-only. Newest day first.
- This file tracks *tasks and decisions*. See [README.md](README.md) for the document map —
  there are four living docs and this is the entry point to them.

ID prefixes: `HW-` schematic/hardware · `FW-` firmware · `BU-` bring-up/verify · `DOC-` documentation.

---

## Status snapshot — 2026-08-05

| Category | Count |
|---|---|
| Blocking — firmware cannot proceed | **0** |
| Agreed, awaiting schematic edit | 3 |
| Awaiting a decision | 2 |
| Firmware work queued | 6 |
| Verify at bring-up | 9 |
| Closed to date | 11 |

**FW-07 is the one to look at first.** `>ABORT` does not stop a run — the comms thread is
starved for the entire run, so the abort never reaches the flag the run loops poll. Found by
the GUI-side review, confirmed in the source. FW-08 sits behind it and is unmasked by the fix.

**The 4-wire method is now proven on real hardware**, not just on paper: the ADS1232 bench rig
measured a 0.033 Ω resistor to **0.4 %** with no current calibration at all, because the
ratiometric arrangement cancels the excitation. Write-up in
`Doc/4wire_resistance_validation.md`.

**Next actions:** answer HW-04 — the bench result is now the concrete argument for it — and
HW-09 (four card slots, five cards). Then the next schematic revision can pick up HW-02, HW-03,
HW-06, HW-08 and HW-10 in one pass.

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

### Firmware work queued

| ID | Item | Raised |
|---|---|---|
| ~~FW-01~~ | **DONE 2026-08-01** — `drivers/ads124s08` written, see CL-10. Original scope: new `drivers/ads124s08` — reset, device-ID read, PGA / data-rate config, internal 2.5 V reference, offset self-calibration. **CS, RESET and START/SYNC are driven over I2C via U69 (0x25), not by MCU GPIO**, so each conversion sequences I2C(CS low) → SPI → I2C(CS high). `DRDY_1` is likewise an expander *input*: no interrupt is possible and polling costs a bus round-trip, so use a timed wait derived from the configured data rate and read DRDY only as a sanity check. | 2026-07-27 |
| FW-02 | Rewrite `test/kelvin.c` for 4-wire. It currently reads the AD7476 and hard-codes `KELVIN_FORCE_CURRENT_A = 0.010f`; both are wrong under the new scheme. Add PGA auto-ranging and system-offset subtraction. | 2026-07-27 |
| ~~FW-03~~ | **DONE 2026-08-01** — `matrix_card` reworked for the Matrix_Card 2 geometry: 8:1 muxes, 32 per bank, 3 select bits, 8 enable expanders across two buffered I2C segments, byte-swapped enable map, segment switching via `HI_S3`/`LO_S3`. AD7476 binding removed (rev 2 deleted U33). | 2026-07-27 |
| FW-04 | Mux address lines come from MCP23017 U21 on I2C3, not MCU GPIO. Update `bsp/board.c`, add OLAT shadow registers, and consider 400 kHz — a 256 × 256 scan is roughly 70 s of pure bus time at 100 kHz versus 18 s at 400 kHz. | 2026-07-27 |
| ~~FW-05~~ | **DONE 2026-08-01** — `app/proto.c`, see CL-11. Original scope: implement the instrument side of the GUI protocol defined in `Doc/GUI_development_brief.md` §3 — line-based ASCII over the VCP at 115200. Replaces the current single-keystroke bring-up console (`c`/`k`/`i`/`s`/`f`/`r`). Needs: command parser, `<` replies with 2 s worst-case latency, `!` result streaming during a run, and `!STATE`/`!FIXTURE`/`!HV`/`!SAFE` events. The GUI is being built against this contract, so changes to it must be agreed, not made. | 2026-08-01 |
| FW-06 | **`>STATUS` never reports `running` or `fault`.** `proto_exec` builds the reply from `s_armed` alone, so a GUI that reconnects mid-run and re-issues `>STATUS` — which the brief §3.5 rule 4 requires it to do — is told `idle` while a run is executing. `!STATE` does carry `running`, so the information exists; only the polled path is missing it. Documented as-is in the brief for now (§3.2, Appendix B) rather than changed silently: the reply is protocol-visible and the GUI is being built against it, so agree it first. Fix is to report from `s_busy` and `Safety_InFault()` as well. | 2026-08-05 |
| FW-07 | **`>ABORT` cannot stop a run — the comms thread is starved for the whole run.** `tSequencer` is `osPriorityNormal`, `tComms` is `osPriorityBelowNormal`, and the sequencer never yields during a run: the settle delays are `HAL_Delay` (the stock `__weak` one — a busy-spin on `HAL_GetTick`, TIM1 timebase, nothing overrides it) and the I2C/SPI calls are polled. With `configUSE_PREEMPTION=1` a lower-priority task never runs while a higher-priority one is runnable, so `Proto_RxByte` is never called during a run: **the abort flag the run loops poll can never be set, and the polling in `tasks.c` is unreachable in practice.** Worse, RX is single-byte polled with no interrupt or DMA, so mid-run bytes are lost to overrun rather than buffered. Scale: insulation is 256 × ~250 ms ≈ 64 s, discover 65,536 × ~2 ms ≈ 131 s — an operator pressing Abort during a 500 V run has no effect for that long. Physical E-stop and the safety task (`osPriorityHigh`, blocks on `osDelay`) are unaffected. Found by the GUI-side task-2 review. Two candidate fixes, neither started: interrupt/DMA RX into a ring buffer with `tComms` blocking on it, or `osDelay` instead of `HAL_Delay` in the test settle paths so the sequencer yields. | 2026-08-05 |
| FW-08 | **`Proto_SetFixture` announces `!SAFE` before the hardware is safe.** It posts `CMD_FORCE_SAFE` to the queue and then immediately emits `!HV 0` and `!SAFE`, without waiting for execution — so the instrument tells the GUI it is safe while the rail may still be up. Directly contradicts the brief's central rule that the GUI must never show a safe state it has not been told is real. Masked today by FW-07 (a fixture change cannot be received mid-run), so **fixing FW-07 unmasks this** — do them together. Also in the same path: the arm is dropped with no `!STATE idle`, and `!SAFE` is emitted twice (once inline, once when the queued force-safe runs). | 2026-08-05 |
| DOC-01 | `fw_status.txt` still describes the 2-wire path, 10 mA excitation, and Matrix U33 as the resistance ADC. Sync it with v1.4. | 2026-07-27 |

### Verify at bring-up

| ID | Item | Raised |
|---|---|---|
| BU-01 | Excitation current — run the 0 Ω loopback compliance sweep. 10 mA is unachievable through two CD4067B plus 100 Ω on a 3.3 V rail; expect roughly 1–3 mA. Capture the system offset at the same time. | 2026-07-27 |
| BU-02 | ~~SPI1 shared by U33 and U68~~ **Dissolved** — Matrix_Card 2 removed the AD7476, so SPI1 has exactly one device. Mode confirmed from SBAS660C: DIN latched on the SCLK falling edge, DOUT changes on the rising edge → **CPOL=0, CPHA=1 (mode 1)**. `SPI1_CS` on J101 now has no consumer. | 2026-07-27 |
| BU-03 | U101 / U102 I2C addresses are set by strapping and not annotated, unlike the sheet-9 trio at 0x23 / 0x24 / 0x25. Scan and log. | 2026-07-27 |
| BU-04 | JP1 (AINCOM → GND, Matrix sheet 9) must be fitted, or the ADC's analog common floats. Populate with a 0 Ω link by default and mark it on the assembly drawing. | 2026-07-27 |
| BU-05 | ~~No differential RC filter~~ **DONE in Matrix rev 2** — R234/R235 4.99 k 0.1 % + C33 47 nF + C142/C143 4.7 nF fitted. | 2026-07-27 |
| BU-07 | **Common-mode: hold the excitation at ≥1 mA.** `LO_SENSE = I × (R_LOmux + R131) = I × 200 Ω` against an ADS124S08 floor of `0.15 + 15.5·\|V_IN\|`. At 1 mA that is 0.200 V vs 0.165 V (+35 mV); at the 5 mA target it is 1.000 V vs 0.227 V (+772 mV) — comfortable, **nothing to fix in hardware**. Revised 2026-08-01: the earlier "marginal" framing overstated it. The real caveat is that the floor grows with the measured resistance, capping R at ~11 Ω at 5 mA on gain 32 — handled by PGA auto-ranging, since gain ≤16 uses a much lower floor. See Doc/4wire_resistance_validation.md §5.1. | 2026-08-01 |
| BU-09 | **Measure CD74HC4051 Rₒₙ at 3.3 V** — reduced 2026-08-01 after reading SCHS122O. Channel-to-channel spread (ΔrON) is **10 Ω max**, so the "some wires read wrong" concern is largely closed; a sanity check across a few channels is enough. What remains is that rON is characterised only from **VCC = 4.5 V** (typ 70 Ω, max 160 Ω at 25 °C, 200 Ω at 85 °C) and the card runs at 3.3 V — extrapolate typ ~110–140 Ω, max ~250–320 Ω. **Excitation target revised 5 mA → 3 mA**, which stays inside both compliance and common-mode limits even at worst-case rON. | 2026-08-01 |
| BU-10 | **Thermal EMF is the accuracy floor below ~1 mΩ.** At 5 mA, 1 µV of junction EMF = 200 µΩ. A 256-line harness has hundreds of dissimilar-metal junctions. Mitigation to design in now: **current reversal** — the DAC8775 has a ±24 mA range, and R = (V_fwd − V_rev)/(2I) cancels EMF because it does not reverse with the current. The ADS124S08 `G_CHOP` bit cancels the ADC's own offset only; the two are complementary. See §7.3. | 2026-08-01 |
| BU-11 | **Measure sense-path leakage.** `HI_SENSE` is the common node of 32 CD74HC4051s with 31 disabled; summed off-channel leakage into the 4.99 kΩ series resistor could be a large offset (1 µA → 5 mV). Should largely cancel between HI and LO legs, but unverified. Cheap test: enable a sense bank with no excitation and check the differential reads near zero. Rises sharply with temperature. See §7.4. | 2026-08-01 |
| BU-08 | **Do not copy the bench resistance formula.** ADS1232 full scale is ±0.5·VREF/Gain, ADS124S08 is ±VREF/Gain. The bench divides by `2 × gain × 2²³`; the product must divide by `gain × 2²³`. Copy-pasting gives a silent 2× error. | 2026-08-01 |
| BU-06 | Harness build must encode `ISO_HV_CARD_ENx` per card slot (card 1 → EN1 … card 4 → EN4). HV_Card-1 sheet 1 states this is done in the cable, not the schematic. | 2026-07-27 |

---

## Closed items

| ID | Closed | Item | Resolution |
|---|---|---|---|
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
