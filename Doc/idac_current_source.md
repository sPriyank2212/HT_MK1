# Kelvin Excitation Now Comes From the ADS124S08's Own IDAC, Not the DAC8775

Write-up of a schematic finding from 2026-08-12: the DAC8775 (Control Card, the chip
`Frontend_SetCurrentCode`/`kelvin.h` currently assume forces the Kelvin excitation current) has
been removed. The excitation current now comes from a current source built into the ADS124S08
itself — the same chip that already does the resistance measurement. **Firmware has not been
updated for this yet.** This doc is the reference for the session that does that.

Related: `PROJECT_LOG.md` HW-11 (closed, superseded) and the new FW item it opened; supersedes
`Doc/4wire_resistance_validation.md` §7.1's 3 mA target (CL-29, closed the same day this was
found — see the flag left in that section).

## 1. The schematic evidence

Two independent things changed between `Matrix_Card-7.pdf`/`Control_Card-5.pdf` (the revisions
this project's code and docs were written against) and the current `Matrix_Card-8.pdf`/
`Control_Card 1.pdf`:

- **DAC8775 is gone.** It doesn't appear anywhere in the new Control Card schematic. The sheet
  that used to hold it (`DAC.kicad_sch`) is now four pull-up resistors on unrelated GPIO lines —
  the component was deleted, not relabelled or moved.
- **ADS124S08 pin `GPIO1_AIN9` (pin 21) is now wired directly to `HI_COM`** — the Matrix Card's
  force bus. In the previous revision this pin fed a calibration-resistor tap (`HI_SENSE5_IN`,
  part of a 5-channel calibration mux network); that network is still physically present, it just
  lost this one duplicate tap. Its old partner pin (`AIN8`, pin 22) is now unconnected.

That second point is the ADS124S08's built-in excitation current source (**IDAC**) architecture:
the chip has two internal, independently-routable current sources that TI's own datasheet routes
to any `AINx` pin via the `IDACMUX` register, specifically for 2-/4-wire resistance and RTD
sensing. That register, and its companion `IDACMAG` (current magnitude), are already in this
project's own register map (`Core/Inc/drivers/ads124s08.h` — `ADS124S08_REG_IDACMUX` /
`ADS124S08_REG_IDACMAG`), just never used: FW-02's Kelvin rewrite (this session, before this
finding) assumed the DAC8775 was still the current source, because at the time it was.

**Worth flagging, not alarming:** the embedded title-block date on both new PDFs is identical to
the files they replace (2026-08-06 / 2026-07-11) — this reads as a design-sync re-export, not a
freshly-dated revision. Doesn't change the finding (the content differences above are real and
directly read, not inferred), but the file naming itself is inconsistent with the project's `-N`
convention (`Control_Card 1.pdf` instead of `Control_Card-6.pdf`) and is still uncommitted. Worth
sorting out — either confirm the naming is intentional or rename for consistency — before the next
schematic sync makes it worse.

## 2. Why this is a good change, not just a different change

1. **Closes HW-11 outright.** DAC8775/DAC8760/AD5758/AD5755 were all wrong-category parts (4-20 mA
   industrial loop drivers needing 10 V+ supplies this board doesn't have) — the whole reason HW-11
   was open. There's no replacement DAC to source anymore; the LTC2662-16 investigation in HW-11
   is moot.
2. **Better accuracy story than any external DAC offered.** An IDAC referenced to the same chip
   that does the conversion is the standard architecture TI documents for this exact measurement
   (RTD/resistance sensing) — not a repurposed loop driver. See §4 for the real numbers.
3. **Simpler board.** One fewer chip, one fewer SPI2 consumer, `control_frontend.c`'s DAC8775 half
   becomes dead code to delete rather than a placeholder register map to keep chasing (`dac8775.h`
   has said "VERIFY against datasheet" since it was written — this makes that moot too).

## 3. The one hard constraint: 2 mA, not 3 mA

`Datasheet/ads124s08.pdf`, `IDACMAG` register (Table 32): the magnitude codes run `0001`&nbsp;=&nbsp;10 µA
up to `1001`&nbsp;=&nbsp;**2000 µA**. There is no higher setting. BU-09 revised this project's excitation
target to **3 mA** (to clear the CD74HC4051 mux's worst-case Rₒₙ with margin) — the IDAC cannot
produce that.

This is not a blocker, and it does not reopen the compliance/common-mode analysis in a bad
direction — 2 mA is *less* current than 3 mA, so:
- **Compliance** (force-loop headroom on the 3.3 V rail): more margin at 2 mA, not less.
- **Common-mode floor** (BU-07, `LO_SENSE = I × (R_LOmux + R131)` against the ADS124S08's input
  floor): 2 mA still clears it — BU-07's own table already showed 1 mA had 35 mV of margin, and
  2 mA only adds more.
- **Resolution**: the only real cost. A given resistance produces a smaller voltage at 2 mA than
  3 mA (2/3 the signal). PGA auto-ranging (added this session, FW-02/CL-23) already compensates by
  stepping to a higher gain — not a blocking issue, just worth knowing the noise floor moves.

**IDAC accuracy at the 2 mA range** (`Datasheet/ads124s08.pdf`, Excitation Current Sources table,
`TA = 25°C, 250 µA to 2 mA` row): typical ±0.5%, worst-case ±3%. Current *matching* between the
two IDACs at 1–2 mA: typical 0.07%, worst-case 0.4%. Compliance voltage headroom at 1–2 mA: down
to `AVDD − 0.6 V`. None of this is free-lunch precision, but it's a real, characterized spec from
the chip vendor for this exact use case — a stronger foundation than the DAC8775 path ever had,
where the whole accuracy chain depended on a register map still marked "VERIFY."

## 4. What DOC-03 (just closed, CL-29) needs revisiting

Unfortunate timing, not a mistake by that session: `Doc/4wire_resistance_validation.md` §7.1 was
re-derived against a 3 mA target *the same day* this finding surfaced, using the DAC8775-era
assumption that excitation current was unbounded (limited only by mux Rₒₙ and rail compliance).
That derivation is sound for a DAC8775-sourced design; it's now superseded by the IDAC's hard
2 mA ceiling. §7.1's table needs re-deriving a second time, this session's replacement, against
2 mA as the fixed operating point rather than a target to justify. A flag is left in place in that
section rather than silently rewriting CL-29's work.

## 5. What firmware needs to change

Not done in this pass — this is the scope for the next session:

| File | Change needed |
|---|---|
| `Core/Src/test/kelvin.c` | Stop calling `Frontend_SetCurrentCode`/`Frontend_SetMode(FRONTEND_MODE_IMPEDANCE)`. Configure `g_ads124s08`'s `IDACMUX` (route IDAC1 to AIN9) and `IDACMAG` (2 mA code) directly instead. |
| `Core/Inc/drivers/ads124s08.h` / `.c` | Register addresses already exist (`ADS124S08_REG_IDACMUX`/`IDACMAG`); no read/write helper functions exist yet for them specifically — add `ADS124S08_SetIdac()` or similar, following the pattern of `ADS124S08_SetGain()`. |
| `Core/Src/cards/control_frontend.c` / `.h` | Remove the DAC8775 half (`Frontend_SetCurrentCode`, the `idac` field, `FRONTEND_MODE_IMPEDANCE`'s DAC-driving behavior) — the front end's remaining job is just the continuity divider + OPT0_CNTR select. Decide whether `FRONTEND_MODE_IMPEDANCE` still means anything once the current source moves off this card entirely. |
| `Core/Src/bsp/board.c` | Drop the SPI2/DAC8775 CS wiring (`BOARD_IDAC_SPI`, `BOARD_IDAC_CS_PORT/PIN`) once nothing references it — check `board_init_frontend()`. |
| `Core/Inc/test/kelvin.h` | `KELVIN_FORCE_CODE`/`KELVIN_FORCE_CURRENT_A` (DAC-code-based) get replaced by an IDAC magnitude code constant (2 mA = `IDACMAG` code `1001`). |
| `Core/Inc/drivers/dac8775.h` / `.c` | Becomes dead code. Delete, or leave and mark unused — team's call. |

Also worth deciding while in there: does **current reversal** (BU-10, thermal-EMF cancellation)
become easier or harder with IDAC excitation? The IDACs are current *sources* only (no documented
bipolar/reverse mode in the register map), so reversal would need swapping which AIN pin sources
vs. sinks (IDAC1 → AIN9/HI_COM forward, then reconfigure so current flows the other way) rather
than a DAC8775-style bipolar code — a different mechanism than BU-10's write-up assumed, worth
re-reading against the real register options before implementing.
