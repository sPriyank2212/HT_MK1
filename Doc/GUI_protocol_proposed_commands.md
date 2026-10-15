# Proposed New Protocol Commands

## Resolved 2026-08-21 (GUI-06 decided and built)

`MANUAL READ`, `BUS SCAN`, `MANUAL SWEEP <hi>` and `CAL RUN` are all built now (`PROJECT_LOG.md`
FW-16/GUI-33; see `Doc/GUI_development_brief.md` §3.2/§3.3 for the shipped wire formats, which
differ from two of the drafts below in real ways, not just naming):

- **`MANUAL READ` was never built as its own command.** The draft below assumed `MANUAL PATH`
  holds the path closed until `MANUAL OFF`, so a separate on-demand read made sense. Checking
  `Continuity_TestPair` directly found that assumption wrong — the matrix is released again
  immediately after `MANUAL PATH`'s own one-shot read, on every exit path. Fixed the real gap
  instead: `MANUAL PATH` now reports the reading it already takes internally, via a new `!MANUAL`
  event.
- **`BUS SCAN`** shipped scoped down from "every bus" to the Matrix Card + ADS124S08 only — the
  HV cards' address straps are still unconfirmed (`hv_card.c`, BU-03), and reporting ok/fault
  against them would have claimed a confidence this project doesn't have yet.
- **`MANUAL SWEEP <hi>`** and **`CAL RUN <hi> <lo>`** shipped close to the drafts below — `CAL RUN`
  once HW-04 (the ratiometric R131 reference this section's write-up was waiting on) landed the
  same session.
- Auto-range PGA's button was already removed in an earlier session (GUI-09/CL-40), confirmed
  before doing anything, not re-done. Compliance sweep and `MANUAL RELAYTEST` are unchanged —
  still a bench tool and still pending a safety review, respectively.

The rest of this document is kept as the original analysis record, not updated in place.

## Re-checked 2026-08-12 against current firmware (GUI-06)

This document was written 2026-08-08, before **FW-02** (Kelvin measurement path wired up,
CL-23) and **FW-12** (excitation moved from the DAC8775 to the ADS124S08's own IDAC, CL-33).
Two of the seven items below were explicitly gated on exactly the hardware-reachability gap
those two closed, so their verdicts changed. Re-checked each entry against `Core/Src` as it
stands today rather than assuming the 2026-08-08 pass still holds:

| Command | 2026-08-08 verdict | 2026-08-12 status | What changed |
|---|---|---|---|
| `MANUAL READ` | Build | **Unchanged — still buildable** | Continuity's ADC read path wasn't touched by FW-02/FW-12 |
| `BUS SCAN` | Build | **Unchanged — still buildable** | No bus-enumeration code exists yet either way; re-confirmed by re-reading `board.c` |
| `MANUAL SWEEP <hi>` | Build | **Unchanged — still buildable** | `run_continuity_all`'s inner loop is untouched |
| `CAL RUN` | Blocked on FW-01/FW-02 | **Unblocked — the hardware gap it cited is closed** | FW-02 (CL-23) wired the ADS124S08 into `board.c` and made it electrically reachable; `Kelvin_MeasurePair` measures for real now. See the updated write-up below — the design question has changed, not just the blocker |
| `MANUAL RELAYTEST <board>` | Safety review first | **Unchanged — still needs a safety review first** | Unrelated subsystem (HV relays), FW-02/FW-12 didn't touch it |
| Auto-range PGA | Recommend against; fold into FW-02 once it lands | **Confirmed done — remove the button** | `kelvin.c`'s `kelvin_ranged_read()` already auto-ranges the PGA automatically, exactly as this doc recommended. Nothing left to build; the GUI button should come out rather than get a command |
| Compliance sweep | Keep as a bench tool | **Unchanged — still a bench tool, not an operator control** | The actual compliance window has since been characterized twice more in `Doc/4wire_resistance_validation.md` §7.1 (3 mA, then 2 mA) — as a document, not a live on-instrument command; the reasoning against exposing it as a button stands |

**Net effect: five of seven are buildable today with no hardware blocker (`MANUAL READ`,
`BUS SCAN`, `MANUAL SWEEP`, `CAL RUN` now, `MANUAL RELAYTEST` pending a safety review); one is
already done and just needs its button removed (Auto-range PGA); one stays a deliberate
non-command (Compliance sweep).** This document still only proposes wire formats — nothing in
`Core/Src` has been touched for any of the buildable ones. See `PROJECT_LOG.md` GUI-06 for the
open per-command go/no-go this still needs.

### `CAL RUN`, revisited

The 2026-08-08 entry recommended deferring the wire-format design itself until the hardware
gap closed. It has closed, so the design question is now real, and it's worth being precise
about what a persistent `CAL RUN` would add on top of what already exists:

- `ADS124S08_SelfOffsetCal` (SFOCAL) already runs once at board init — cancels the **ADC's own**
  offset only.
- `Kelvin_MeasurePair` already takes a **per-point** zero-current baseline and subtracts it
  before every single measurement (CL-23) — cancels mux charge-injection and lead offset,
  fresh every time, not stored.
- Neither of those touches **current-magnitude accuracy** — the IDAC's own tolerance (typ
  ±0.5 %, worst-case ±3 % per `Doc/idac_current_source.md` §3) is not calibrated out by
  anything today.

So a `CAL RUN` that duplicates the per-point offset subtraction `kelvin.c` already does would
add nothing. One that measures R131 (100 Ω, 0.01 %) as a known reference and derives a
current/gain correction factor from it would be new and useful — but that's the same
measurement HW-04 (now agreed, awaiting the schematic edit that adds a ratiometric tap on
`AIN8`) is meant to enable properly. Recommend deciding `CAL RUN`'s scope *after* HW-04 lands,
so it can do the ratiometric measurement HW-04 was proposed for instead of building a
current-source-only stand-in now and redesigning it later.

---

Companion to `GUI_protocol_command_coverage.md` §4. That document found seven GUI buttons
with no matching firmware command at all: Rescan, Read ADC, Sweep this HS, Run self-cal,
Auto-range PGA, Compliance sweep, Relay self-test. Per the brief §7, protocol changes are
"propose them, do not make them" — so this is a proposal, not an implementation. Nothing in
`Core/Src` has been touched for any of this.

Each entry below follows the existing contract's conventions from brief §3.2: `<OK` for
anything answered on the spot, `<OK started` for anything handed to the sequencer, defined
error codes only (`EBUSY`, `EFIXTURE`, `ENOTARMED`, `ERANGE`, `EHW`, `ESYNTAX`), and streamed
events for anything that takes real time rather than a single blocking reply.

**Priority order below is by how much new engineering it needs, not by how the audit found
them** — two of these are a few lines against code that already exists; three are genuine
firmware feature work; two should probably not be built as separate commands at all.

## Tier 1 — small, self-contained, no new measurement logic

### `MANUAL READ` — read back the last closed manual path

**Button:** Diagnostics — "Read ADC"

```
>MANUAL READ                  -> <MANUAL adc_mv=<int> adc_code=<int>
```

Reads whatever the continuity ADC (AD7476, the same one `CONT RUN` uses) currently reports on
the path `MANUAL PATH` last closed — no new hardware access, just a readback of a value the
firmware already produces internally per continuity test point. Instant reply, not queued;
matches `CAL GET`/`LIMITS GET`'s pattern of "state that already exists, just not yet on the
wire." Refuse with `ERR ESYNTAX no path closed` if `MANUAL PATH` hasn't been sent since the
last `MANUAL OFF`/fixture change — reading a floating input and presenting it as a number
would be worse than refusing, same reasoning `Kelvin_MeasurePair` already uses for FW-02.

**Estimate:** small. `Continuity_TestPair`'s ADC read path already exists; this exposes its
raw result instead of only the pass/fail verdict.

### `BUS SCAN` — bus enumeration

**Button:** Diagnostics — "Rescan"

```
>BUS SCAN                     -> <BUS <n>
                                  then n lines: <BUSLINE <name> <ok|fault> <detail...>
```

Checked `bsp/board.c` directly for this document — **there is no bus enumeration in firmware
at all**, on demand or at boot. The "I2C3 scan: 0x20 0x21 0x23 0x24 0x25 — 5 devices" line the
GUI shows before connecting is cosmetic placeholder text (`AppState._bootLog()`), not
something the instrument has ever reported. This is new firmware work, not just a new command
— probing each expected address on I2C2/I2C3 and each SPI device's ID register — but it's
self-contained (no shared state, no safety interaction) and mirrors the header+N-lines shape
`NETLIST GET` already uses, so the GUI-side parsing is a known pattern.

**Estimate:** small-to-medium. The probing itself (`HAL_I2C_IsDeviceReady`, reading known ID
registers over SPI) is straightforward; deciding what counts as "fault" per bus needs the
same per-device knowledge the boot log already encodes, just made real.

## Tier 2 — real firmware feature work

### `MANUAL SWEEP <hi>` — one HS against all 256 LS

**Button:** Diagnostics — "Sweep this HS"

```
>MANUAL SWEEP <hi>            -> <OK started
                                  streams !CONT <hi> <lo> pass for each match
                                  !DONE sweep <found> 0
```

A bounded version of `CONT RUN discover` — reuses the exact same `!CONT` event the GUI already
parses, so this needs no new message type on the GUI side, only a new command to send and a
new `kind` value (`sweep`) on `!DONE`. Pin range validation matches `MANUAL PATH`'s existing
`ERR ERANGE pin` behavior. Queued like any other run — refuse with `EBUSY` while one is already
in progress, same as `CONT RUN`/`RES RUN`/`INSUL RUN`.

**Estimate:** small. `run_continuity_all(discover=1)`'s inner loop (`Core/Src/app/tasks.c:318`)
already does exactly this per HS column; this exposes it for one column on demand instead of
all 256.

### `CAL RUN` — self-calibration against the loopback reference

**Button:** Diagnostics — "Run self-cal"

```
>CAL RUN                      -> <OK started
                                  !DONE cal 1 0   (or 0 1 on failure)
                                  then <CAL ...> reads the updated values
```

**Unblocked 2026-08-12 — FW-02/CL-23 closed the routing gap this was waiting on.** Originally
blocked, not just unbuilt: self-cal means measuring the loopback/reference path (R131, 100 Ω
0.01 %) through the real signal chain and storing the resulting offset, and the ADS124S08 path
was electrically unreachable from this MCU at the time this was written. It isn't anymore —
`board.c` now instantiates and drives it, and `Kelvin_MeasurePair` measures real resistance.
The design question is real now; see "`CAL RUN`, revisited" above for what it should actually
do given `kelvin.c` already subtracts a per-point offset, and why its scope is best decided
after HW-04 (ratiometric `AIN8` tap) lands rather than before.

### `MANUAL RELAYTEST <board>` — HV relay self-check without energising

**Button:** HV view — "Relay self-test"

The brief refuses manual relay *control* outright (`MANUAL RELAY` → `ERR EHW` by design,
§0/§8 Q3) because driving one relay by hand while the rail may be live is not safe to allow
over a serial link. A self-test is a different shape of request — verify each relay
individually *opens and closes correctly*, but it still moves the same relays the brief was
protecting. Recommend, if this gets built at all:

- Refuse unless `hv_mv == 0` and the instrument is **not armed** — check both, not just one;
  the existing `INSUL RUN` refusal pattern (`ENOTARMED`) and the fixture-change safety logic
  (`Proto_SetFixture`) are the right precedent to reuse, not new logic invented for this alone.
- Verify via continuity (low-voltage), never by applying HV — the point of a self-test is
  confirming the relay mechanically works, not exercising it under load.
- Streams `!DONE relaytest <passed> <failed>` the same shape as every other run.

**This one needs a safety design review before a wire format is worth finalizing** — it is
the one item on this whole list where "propose the command" and "propose the safety
interlock" are the same task, not two.

## Not recommended as separate commands

### Auto-range PGA

**Button:** Resistance view — "Auto-range PGA"

**Done 2026-08-12: confirmed already automatic, no command needed.** `Doc/4wire_resistance_
validation.md` §4 already listed PGA auto-ranging as a **requirement of the FW-02 resistance
rewrite itself**, not a separate operator-triggered step, and that's what landed —
`kelvin.c`'s `kelvin_ranged_read()` steps the PGA from gain 128 down to gain 1 automatically on
every measurement, the same way a real DMM auto-ranges without being asked. There is nothing
left to build here. **Recommend removing the button** rather than adding a command for it —
this was the plan even in the original write-up, just contingent on FW-02 landing, and it has.

### Compliance sweep

**Buttons:** Resistance view and Diagnostics — "Compliance sweep" (appears on both)

This is bench-characterization work — finding the excitation-current window before the
force loop runs out of headroom — exactly what `Doc/4wire_resistance_validation.md` §7.1
already did once, on the bench rig, to establish a usable compliance window for that
hardware. (The bench rig's window and the actual Matrix_Card-6 mux's window are not
necessarily the same number — confirm against the current schematic before quoting one, this
document is not the place to pin that figure down.) An operator mid-test does not need to
re-run this; it's a hardware validation step, not an operational one. If it needs to exist
on the instrument at all, it belongs behind an explicit engineering/bring-up mode, not a
button an operator can reach from the normal Resistance or Diagnostics screens.

## Summary

| Command | New measurement logic? | Blocked on hardware? | Recommend (2026-08-12) |
|---|---|---|---|
| `MANUAL READ` | No — readback only | No | Build |
| `BUS SCAN` | Some (new enumeration) | No | Build |
| `MANUAL SWEEP <hi>` | No — reuses discovery's inner loop | No | Build |
| `CAL RUN` | Yes | **No — unblocked by FW-02/CL-23** | Design after HW-04 (`AIN8`) lands, not before |
| `MANUAL RELAYTEST <board>` | Some | No, but safety-critical | Safety review before protocol design |
| Auto-range PGA | N/A | N/A — **done** | Already automatic (FW-02/CL-23); remove the button |
| Compliance sweep | N/A | No | Keep as a bench tool, not an operator control |
