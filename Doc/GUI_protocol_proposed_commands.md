# Proposed New Protocol Commands

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

**Blocked on FW-01/FW-02, not just unbuilt.** Self-cal means measuring the loopback/reference
path (R131, 100 Ω 0.01 %) through the real signal chain and storing the resulting offset —
and the signal chain it needs to measure through, for resistance, is the ADS124S08 path that
is currently electrically unreachable from this MCU (`Doc/matrix-card-kelvin-resistance-rework`
memory; `ADC_CS_1`/`ADC_RST_1`/`Start_SYNC_1`/`DRDY_1`/`SPI1_SCLK` exist only on the Matrix
Card). Designing this command's wire format is easy; implementing it usefully is not possible
until that routing gap closes. Recommend deferring the protocol design itself until FW-02 lands
— a command that can only ever answer `ERR EHW` isn't worth adding yet.

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

`Doc/4wire_resistance_validation.md` §4 already lists PGA auto-ranging as a **requirement of
the FW-02 resistance rewrite itself** — "PGA auto-ranging, which also keeps the common mode
legal on large R" — not a separate operator-triggered step. Recommend this happens
automatically inside `Kelvin_MeasurePair` once FW-02 is built, the same way a real DMM
auto-ranges without being asked. Building it as a standalone manual command would mean two
copies of the same ranging logic to keep in sync. Suggest removing this button rather than
building a command for it, once FW-02 ships and resistance measurement auto-ranges by itself.

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

| Command | New measurement logic? | Blocked on hardware? | Recommend |
|---|---|---|---|
| `MANUAL READ` | No — readback only | No | Build |
| `BUS SCAN` | Some (new enumeration) | No | Build |
| `MANUAL SWEEP <hi>` | No — reuses discovery's inner loop | No | Build |
| `CAL RUN` | Yes | **Yes — FW-01/FW-02** | Design after the ADC routing gap closes |
| `MANUAL RELAYTEST <board>` | Some | No, but safety-critical | Safety review before protocol design |
| Auto-range PGA | N/A | Tied to FW-02 | Fold into `RES RUN`, don't add a command |
| Compliance sweep | N/A | No | Keep as a bench tool, not an operator control |
