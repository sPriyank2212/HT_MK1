# 4-Wire Resistance — Bench Validation and What It Means for the Matrix Card

**Date:** 2026-08-01 · **Rig:** NUCLEO-G474RE + ADS1232 · **Result:** 33 mΩ measured to 0.4 %

---

## 1. Why we built it

The Matrix Card's precision resistance path (Matrix_Card rev 2 + ADS124S08) does not exist in
hardware yet. Rather than wait, we built a bench rig that exercises the **same measurement
principle** with a different converter, to answer three questions before committing:

1. Does 4-wire Kelvin with a ratiometric reference actually work as designed?
2. What noise floor is realistically achievable on a 24-bit Σ-Δ at these signal levels?
3. What will bite us during bring-up of the real board?

All three are now answered. Question 3 turned out to be the most valuable.

---

## 2. The validated circuit

```
5V ──[4.7k]──●──[R_dut]──●──[4.7k]── GND        REFP = 5V, REFN = GND
              │           │                      AVDD = 5V, DVDD = 3.3V
           AINP1       AINN1                     gain = 128 (GAIN0/1 strapped high)
                                                 common mode = 2.500 V
```

Because `REFP` sits on the **same 5 V rail** that drives the divider, the supply cancels out
of the ratio and the measurement is inherently ratiometric:

```
I      = 5 / R_ref
Vin    = I × R_dut = 5 × R_dut / R_ref
code   = Vin / (0.5 × VREF / (gain × 2²³))        ← the 5 V divides out
R_dut  = R_ref × code / (2 × gain × 2²³)
```

`R_ref` is the **sum** of both divider resistors (4.7 k + 4.7 k = 9400 Ω), so its tolerance —
not the ADC — sets the accuracy.

### Result

| | |
|---|---|
| DUT | 0.033 Ω ±1 % (R033F) |
| Predicted code | **7,539** |
| Measured median | **7,553 – 7,705** |
| Agreement | **0.4 %** |
| Computed resistance | 33.00 – 33.73 mΩ |
| Excitation | 0.532 mA, 17.6 µV across the DUT |
| Resolution | 4.38 µΩ per count |
| Noise (`spr`) | 218–370 counts ≈ **±0.6 mΩ**, ~2 % of a 33 mΩ part |

Dropping to a 470 Ω pair (5.3 mA) scales the signal ~10× and the noise floor to **±0.06 mΩ**
for no other change.

---

## 3. What went wrong, and what each symptom teaches

The rig took several iterations. Every failure mode below is one we can now recognise in
minutes rather than hours on the real board — that is the main deliverable.

| Symptom | Root cause | Diagnostic that found it |
|---|---|---|
| `code = -1` (0xFFFFFF) | DOUT floating — not driven | all-ones is a bus artifact, never a conversion |
| `code = 0` (0x000000) | SCLK not reaching the ADC; DOUT never released | check DOUT is **high** after the 24 clocks |
| Wildly bimodal readings | ~50 % of reads silently corrupted by a bad joint | `retries` counter, not spread shape — a 50/50 corruption defeats any statistical test |
| Reading 24× too small, wrong sign | **Common mode at ground**, outside the PGA's valid window | datasheet, after everything else was eliminated |
| Reading 2× off | Misread full-scale convention | datasheet |
| Constant reading, ignores input | Tare captured the signal itself | offset ≈ expected signal |
| `R` never changed | `R_ref` set to one divider resistor, not the sum | — |

### Diagnostics now built into the driver

- `ADS1232_BenchDiag()` — classifies DOUT as stuck-high / stuck-low / floating / converting,
  and separately tests whether SCLK reaches the device
- `ADS1232_BenchPinTest()` — GPIO **readback**, which separates "MCU isn't driving" from
  "the wire is broken" with no test equipment
- `ADS1232_BenchLinkTest()` — read success rate as a percentage, for chasing a joint live
- Sentinel rejection of `0x000000` / `0xFFFFFF` as link faults, retry-tolerant reads,
  `spr` / `drift` / `rty` reported every batch

### Two lessons that cost the most time

**A bad connection does not fail cleanly.** It produced valid-looking numbers that drifted,
and it defeated a statistical outlier test. The `retries` counter — measuring the link
directly rather than inferring it — was what finally separated link faults from analog ones.

**Common-mode range is not a detail.** Roughly half the debugging went into a circuit that
could never have worked, because both inputs sat at ground. Nothing in the readings said
"common mode"; only the datasheet did.

---

## 4. Does this transfer to the ADS124S08? Mostly — with three real differences

**The topology and the principle carry over unchanged.** What differs is the excitation
source, the reference arrangement, and — critically — the arithmetic.

| | Bench (ADS1232) | Matrix Card (ADS124S08) |
|---|---|---|
| Force path | 5 V through a resistive divider | DAC8775 programmable current source |
| Sense path | direct Kelvin taps | 32-mux sense array → HI_SENSE / LO_SENSE |
| Reference | external, **same rail as excitation** → ratiometric by construction | **internal 2.5 V**; REFP0/REFN0 are no-connect → **not ratiometric** |
| **Full scale** | **±0.5 × VREF / Gain** | **±VREF / Gain** — *no 0.5* |
| Common-mode floor (high gain) | AGND + **1.5 V** | AVSS + **0.15 V** + 15.5·\|V_IN\| |
| Common-mode provision | symmetric divider → 2.500 V | R131 (100 Ω) lifts LO_COM off ground |
| Gain | pin-strapped 1/2/64/128 | register, 1–128 |
| Interface | 2-wire bit-bang, no SPI | SPI + expander-driven CS/RESET/START |

### ⚠ Do not copy the formula

The full-scale conventions genuinely differ. The bench code divides by **2 × gain × 2²³**;
the ADS124S08 must divide by **gain × 2²³**. Copy-pasting the bench maths gives a silent 2×
error — exactly the error we made in the other direction here before reading SBAS350H.

```
ADS1232      R_dut = R_ref × code / (2 × gain × 2²³)
ADS124S08    R_dut = R_ref × code / (gain × 2²³)
```

---

## 5. What this tells us to change on the Matrix Card

### 5.1 Common-mode headroom — adequate at ≥1 mA, not a design flaw

*(Revised 2026-08-01 after hardware-owner review. The earlier wording overstated this.)*

The lift comes from two 100 Ω elements in series — the CD74HC4051 on-resistance and R131:

```
LO_SENSE ≈ I × (R_LOmux + R131) ≈ I × 200 Ω
floor    = 0.15 + 15.5 × |V_IN|     (ADS124S08, gain 32–128)
```

| I | LO_SENSE | floor (1 Ω wire) | margin |
|---|---|---|---|
| 0.5 mA | 0.100 V | 0.158 V | **FAIL** |
| 0.75 mA | 0.150 V | 0.162 V | **FAIL (just)** |
| 1 mA | 0.200 V | 0.165 V | +35 mV |
| 2 mA | 0.400 V | 0.181 V | +219 mV |
| **5 mA** | **1.000 V** | **0.227 V** | **+772 mV** |

**At the 5 mA target this is comfortable and there is nothing to fix.** The constraint is
simply that firmware must not run the excitation below ~1 mA — which the compliance analysis
(§7.1) says it should not do anyway.

**The subtlety worth keeping:** the floor is not flat. It grows as `15.5 × |V_IN|`, so it
rises with the resistance being measured. At gain 32 the common-mode limit caps the
measurable resistance:

| I | max R before the common mode fails at gain 32 |
|---|---|
| 1 mA | 3.2 Ω |
| 2 mA | 8.1 Ω |
| 5 mA | 11.0 Ω |

Irrelevant for harness wire (well under 1 Ω), but it bites exactly where you want it least —
detecting a *high-resistance fault*, a partial break or corrosion. **The fix is already in
the plan: PGA auto-ranging.** At gain ≤16 the floor is `0.15 + |V_IN|·(Gain−1)/2`, which is
far lower, and at gain 1 it is just 0.15 V. So dropping gain for a large reading keeps both
the full scale *and* the common mode legal — auto-ranging is not only about range.

### 5.2 The ratiometric case is now demonstrated, not theoretical

The bench measured 33 mΩ to 0.4 % with **no current calibration whatsoever**, because the
excitation cancelled. The Matrix Card as drawn cannot do this — it uses the internal 2.5 V
reference, so accuracy rides entirely on DAC8775 tolerance and drift.

**This is PROJECT_LOG HW-04**, and the bench result is the argument for it: route `LO_COM`
to a spare ADS124S08 input (AIN2–AIN5 are free) so firmware can measure the current across
the 0.01 % R131 and divide it out.

### 5.3 Expected performance on the real board

At 1 mA, gain 32, internal 2.5 V reference:

| | |
|---|---|
| LSB | 2.5 / (32 × 2²³) = **9.31 nV** |
| Resolution | **9.31 µΩ per count** |
| Full-scale DUT | 78 Ω |

The bench achieved ±0.6 mΩ at 0.53 mA with flying leads and a marginal joint. A soldered
board at 1 mA should do better, but **treat ±0.5 mΩ as the realistic expectation** until
measured — that is a real number from real hardware, not a datasheet extrapolation.

### 5.4 Bring-up order for the Matrix Card

Straight from what worked here:

1. Confirm the ADS124S08 responds — device ID over SPI (equivalent to "is DOUT toggling")
2. Short the sense inputs, confirm a small stable code
3. Verify the **common mode** at LO_SENSE with a meter *before* trusting any reading
4. Fit a known resistor, check the code matches prediction — the single test that validates
   gain, reference and topology together
5. Only then measure harness wire

Step 3 is the one we learned the hard way.

---

## 6. Firmware status

`Core/{Inc,Src}/drivers/ads1232.{h,c}` — bench-only, gated on `HT_ENABLE_ADS1232`, default
**off**. A Release build with the enable left in place fails at compile time; a Debug build
that enables it prints a `#warning` on every compile. With the macro off the translation
unit produces **0 bytes and 0 symbols**.

It is a validation tool, not product code, and it is not on the path to the ADS124S08
driver (FW-01) — that is a different interface entirely. What transfers is this document,
the bring-up order, and the diagnostics pattern.

---

## 7. Concern study — what could still go wrong on the Matrix Card

Forward-looking risk list for when this is picked up again. Ordered by how much
damage each does if missed. Numbers assume CD74HC4051 at ~100 Ω, R131 = 100 Ω,
ADS124S08 at gain 32 with the internal 2.5 V reference.

### 7.1 There is a usable current window

**STALE (2026-08-11): this section's "target ~5 mA" was superseded 2026-08-01
by BU-09 (real CD74HC4051 datasheet, worst-case Rₒₙ 250–320 Ω at 3.3 V) —
current target is 3 mA, not 5 mA. The lower bound below is correct (1 mA,
common-mode-limited, independent of the mux swap) but the table and the "target
~5 mA" callout need re-deriving against the 3 mA ceiling. Not done in this
pass — see `PROJECT_LOG.md` HW-11.**

The excitation is bounded at both ends. Too little and the sense common mode
falls below the PGA floor; too much and the force loop runs out of compliance on
the 3.3 V rail. The window is wide enough — the point is to sit in it
deliberately rather than by accident.

```
force loop  = 2 × R_mux + R131 + R_wire  ≈ 300 Ω + R_wire
LO_SENSE    = I × (R_mux + R131)         ≈ I × 200 Ω
CM floor    = 0.15 + 15.5 × |V_IN|       (ADS124S08, gain 32–128)
```

| I | HI_COM (1 Ω wire) | LO_SENSE | CM floor | verdict |
|---|---|---|---|---|
| 0.5 mA | 0.15 V | 0.100 V | 0.158 V | **common-mode FAIL** |
| 1 mA | 0.30 V | 0.200 V | 0.165 V | OK, 35 mV margin |
| 2 mA | 0.60 V | 0.400 V | 0.181 V | OK |
| **5 mA** | **1.51 V** | **1.000 V** | **0.227 V** | **comfortable — target this** |
| 8 mA | 2.41 V | 1.600 V | 0.274 V | OK, near compliance |
| 10 mA | 3.01 V | 2.000 V | 0.305 V | **compliance FAIL** |

**Target ~5 mA.** That is a good outcome of the CD74HC4051 swap — with the old
CD4067B the ceiling was under 1 mA and this window did not exist.

The lower bound comes from `LO_SENSE = I × (R_LOmux + R131) = I × 200 Ω` against
a floor of `0.15 + 15.5·|V_IN|`. Anywhere from 1 mA up is fine; at 5 mA there is
772 mV of margin. See §5.1 for the one caveat — the floor rises with the
resistance being measured, which auto-ranging handles.

At 5 mA, gain 32: 1 count = **1.86 µΩ**, a 1 Ω wire gives 5 mV against a 78 mV
full scale. Comfortable everywhere.

### 7.2 Per-channel Rₒₙ spread narrows that window

Every one of the 128 multiplexers has its own on-resistance, and HC Rₒₙ varies
with signal level and part to part. If real Rₒₙ spans, say, 80–200 Ω, then:

- worst-case loop = 2 × 200 + 100 = 500 Ω → at 5 mA, HI_COM = 2.5 V (tight)
- best-case lift = 5 mA × 180 = 0.9 V (still fine)

So compliance is the side that bites. **Characterise Rₒₙ across a sample of
channels at bring-up, not just one.** A channel that works at pin 1 may be in
compliance limiting at pin 200. This is the failure mode most likely to look
like "some wires read wrong" rather than an obvious fault.

### 7.3 Thermal EMF is the accuracy floor below ~1 mΩ

The bench rig drifted ~25 µV over 80 s from contact resistance and junction
EMFs. At 5 mA, 1 µV of thermal EMF = **200 µΩ of error**. A 256-line harness has
hundreds of connector junctions, all dissimilar metals, all at slightly
different temperatures.

**Mitigation worth designing in now: current reversal.** The DAC8775 has a
±24 mA range, so the excitation can be reversed. Thermal EMF does not reverse
with the current, so averaging a forward and reverse measurement cancels it:

```
R = (V_forward − V_reverse) / (2 × I)
```

This costs one extra conversion per point and removes the single largest error
term. The ADS124S08's `G_CHOP` bit cancels *its own* offset but does nothing
about EMF out in the harness — the two are complementary, not alternatives.

### 7.4 Sense-path leakage from 32 parallel multiplexers

`HI_SENSE` is the common node of 32 CD74HC4051s, only one enabled. The other 31
contribute off-channel leakage into a node that then sees the 4.99 kΩ series
resistor. Even 1 µA of summed leakage is 5 mV of offset — far larger than the
signal.

It should largely cancel between the HI and LO legs (symmetric arrangement), and
HC leakage at room temperature is nanoamps, but this is **unverified and worth
measuring**: enable a sense bank with no excitation and see whether the
differential reading is near zero. Leakage also rises sharply with temperature.

### 7.5 Settling time

The anti-alias network (R234/R235 4.99 k, C33 47 nF differential) gives:

```
τ = 2 × 4.99k × ~49 nF ≈ 0.5 ms
24-bit settling ≈ 17τ ≈ 8.4 ms per point
```

Fine at 20 SPS (50 ms conversions) but it sets a floor. Resistance runs only on
discovered connections (~256 points → ~2–3 s), so this is not a problem — but
do not expect to speed it up by raising the data rate alone.

### 7.6 Accuracy is DAC-limited until HW-04 is done

**Corrected 2026-08-11** — the "~0.5 %" figure below was unsourced. Re-derived
from `Datasheet/dac8775.pdf` directly, with the specific gotcha that its TUE
table has **four rows depending on temperature range *and* which current range
is configured**, not one number:

```
TUE, -40..125°C, general (0-20/0-24/±24 mA ranges)   ±0.14 %FSR
TUE, -40..125°C, "4 to 20 mA" range specifically       ±0.4 %FSR
TUE, 25°C only,  "4 to 20 mA" range specifically       ±0.2 %FSR
TUE, 25°C only,  general                              ±0.12 %FSR
```

§7.1's window is 1–3 mA — below the 4 mA floor of the "4 to 20 mA" range
option, so the DAC has to be configured to 0–20 mA or 0–24 mA here. **The
applicable row is the general ±0.14 %FSR one, not the ±0.4 % "4 to 20 mA" row**
— that row characterizes a different range setting than this design can even
use. (`DAC8775_RANGE_0_24MA` in `dac8775.h` is still a VERIFY placeholder,
so which of 20 mA/24 mA FSR is real is itself unresolved — the table below
gives both.)

| FSR (range setting) | abs. error, ±0.14 %FSR, full temp | R_max for ±1 mΩ before cal, at 1 / 2 / 3 mA |
|---|---|---|
| 0–24 mA | 33.6 µA | 29.8 mΩ / 59.5 mΩ / 89.3 mΩ |
| 0–20 mA | 28.0 µA | 35.7 mΩ / 71.4 mΩ / 107.1 mΩ |

So: **~2.4× more headroom than a ±0.4 %/80 µA calculation would suggest** — but
the conclusion does not change, because none of these ceilings (30–107 mΩ) are
anywhere near the sub-1 mΩ noise-floor target from §7.9/the noise table.
**Calibration is mandatory either way**; the DAC error was never actually the
binding constraint once the correct row is used — the noise floor at a
practical data rate is. Realistic *pre-calibration* accuracy is closer to
**~0.15 %** (general row, 24 mA FSR) than either the old "~0.5 %" guess or a
±0.4 %-row calculation, but "realistic accuracy" isn't the number that matters
here — R_max-before-cal vs. the ±1 mΩ target is.

An order of magnitude better again is available for one on-card net and two
passives if HW-04 lands: dominant error becomes R131 tolerance (0.01 %) + ADC
gain error, not DAC accuracy at all. The bench measured 0.4 % with a **5 %
divider** and no current calibration at all — that is what the ratiometric
method buys, independent of which DAC ships.

### 7.7 Two-segment I2C latency

With U69 (ADC control) on BUFF1 and the sense enables on BUFF2, a single Kelvin
measurement needs **three** segment switches — and each switch is itself an I2C
write to U21 on the Control Card.

**Moving U69 to BUFF2 @ 0x20 reduces that to one** (force on BUFF1, then sense
enables *and* all CS toggling together on BUFF2). Worth doing when the address
collision is fixed anyway.

### 7.8 Open items this depends on

| | |
|---|---|
| HW-04 | ratiometric current reference — §7.6 |
| BU-07 | common-mode headroom — §7.1 |
| BU-08 | do not copy the bench formula — full-scale conventions differ |
| HW-09 | four card slots, five cards |
| BU-01 | compliance sweep, now with a real target (~5 mA) |

### 7.9 What would most reduce risk, in order

1. **Measure CD74HC4051 Rₒₙ at 3.3 V** across several channels — it sets the
   whole current window and nothing else can be finalised without it
2. **Decide HW-04** — 10× accuracy for one net
3. **Design in current reversal** — it is a firmware feature if the DAC is put in
   a bipolar range, and it removes the dominant error term
4. **Measure sense-path leakage** with no excitation — cheap test, potentially
   large offset
5. Fix the U69 address collision and move it to BUFF2 while you are there


---

## Appendix A — ADS1232 bench rig wiring

*(was Doc/ADS1232_bench_wiring.md; merged here 2026-08-01 so the whole bench story is one file)*

Stand-in for the ADS124S08 while the Matrix card does not exist. Enable the driver with
`-DHT_ENABLE_ADS1232=1`; it compiles to nothing otherwise.

> **The ADS1232 is not an SPI device.** There is no chip select and no MOSI, and `DOUT`
> doubles as `DRDY`. You need **two GPIOs**, not an SPI peripheral. Gain, data rate and
> channel are set by *static pins*, not registers.

> Pin numbers below are from **SBAS350H**, 24-pin TSSOP (PW package).

---

### 1. Digital side — Nucleo to ADS1232

All five MCU pins are unused by the project and land on the Arduino header.

**As built: `GAIN0` and `GAIN1` are pulled up on the board**, so the gain is fixed in
hardware and only three MCU pins are needed.

| ADS1232 signal | Dir | Nucleo pin | Arduino label | Notes |
|---|---|---|---|---|
| `SCLK` | MCU → ADC | **PA1** | A1 | idles LOW — never park it high, that requests power-down |
| `DOUT/DRDY` | ADC → MCU | **PA4** | A2 | input, no pull needed; EXTI4-capable if you want interrupts later |
| `PDWN` | MCU → ADC | **PC1** | A4 | HIGH = awake. Strap to VDD if you prefer |
| `GAIN0` | — | *pulled up* | — | **strapped high** |
| `GAIN1` | — | *pulled up* | — | **strapped high** |
| `SPEED` | — | *strap* | — | GND = 10 SPS (quieter), VDD = 80 SPS |
| `A0` (channel) | — | *strap* | — | GND = AIN1. Only one channel is needed |
| `CLKIN` | — | *strap* | — | **tie LOW for the internal oscillator.** Floating = undefined clock source, device may never convert |
| `DVDD` | — | Nucleo 3V3 | — | digital supply |
| `AVDD` | — | Nucleo 3V3 (or 5V) | — | **analog supply — separate pin, must be connected** |
| `DGND` | — | Nucleo GND | — | |
| `AGND` | — | Nucleo GND | — | tie to the same ground as DGND |

### Hard limits from SBAS350H — the ones that bit us

| Spec | Value |
|---|---|
| **Full-scale input** | **±0.5 × VREF / Gain** — note the 0.5. At VREF=5 V, gain=128 that is **±19.53 mV**, and 1 count = **2.328 nV** |
| **Common-mode range, gain 64/128** | **AGND + 1.5 V … AVDD − 1.5 V** → with AVDD=5 V that is **1.5 V to 3.5 V** |
| Common-mode range, gain 1/2 | AGND − 0.1 V … AVDD + 0.1 V |
| VREF | 1.5 V min, AVDD nom; V(REFP) ≥ V(REFN) + 1.5 V |
| `CAP` pins 9–10 | **0.1 µF across them** — PGA bypass, not optional |
| Digital VIH | 0.7 × DVDD (2.31 V at DVDD=3.3 V, so 3.3 V logic is fine) |
| DRDY/DOUT | data shifts out MSB first **on the first rising SCLK edge** |

**A ground-referenced input CANNOT be measured at gain 64 or 128.** The common mode must sit
between 1.5 V and AVDD−1.5 V. This is the single most important constraint on the rig.

### Full 24-pin TSSOP pinout

| Pin | Name | Pin | Name |
|---|---|---|---|
| 1 | DVDD | 24 | DRDY/DOUT |
| 2 | DGND | 23 | SCLK |
| 3 | CLKIN/XTAL1 | 22 | PDWN |
| 4 | XTAL2 | 21 | SPEED |
| 5 | DGND | 20 | GAIN1 |
| 6 | DGND | 19 | GAIN0 |
| 7 | TEMP | 18 | AVDD |
| 8 | A0 | 17 | AGND |
| 9 | CAP | 16 | REFP |
| 10 | CAP | 15 | REFN |
| 11 | AINP1 | 14 | AINP2 |
| 12 | AINN1 | 13 | AINN2 |

> **The analog side is not optional.** `AVDD`, `AGND` and the `REFP`/`REFN` reference are
> all required before any reading means anything. With `AVDD` unconnected, or no reference
> fitted, the digital interface may still clock but the conversion result is undefined —
> typically all-ones (`code = -1`) mixed with noise. See §5.

PA0 and PC7 are therefore free. **Minimum viable wiring is two signals** — `SCLK` and
`DOUT/DRDY` — plus power and ground; `PDWN` can be strapped high too.

```
   NUCLEO-G474RE                         ADS1232
   ┌──────────────┐                    ┌──────────────┐
   │      PA1 (A1)├───────────────────►│SCLK          │
   │      PA4 (A2)│◄───────────────────┤DOUT/DRDY     │
   │      PC1 (A4)├───────────────────►│PDWN          │
   │          3V3 ├───────────────────►│DVDD          │
   │          GND ├───────────────────►│DGND   AGND   │
   └──────────────┘         3V3 ──[PU]─►│GAIN0        │
                            3V3 ──[PU]─►│GAIN1        │
                                        └──────────────┘
                     LPUART1 PA2/PA3 → ST-LINK VCP, 115200 8N1, for the log
```

### ⚠ The driver must be TOLD the strapped gain

It cannot read the gain pins back. If `cfg.gain` does not match the straps, every volts
and ohms result is wrong by that factor — and wrong by 128× is easy to mistake for a
wiring fault. Both pins high is **gain 128** (confirm against your datasheet copy):

```c
ADS1232_Cfg_t cfg = {0};

cfg.sclk.port = GPIOA;  cfg.sclk.pin = GPIO_PIN_1;   /* PA1 */
cfg.dout.port = GPIOA;  cfg.dout.pin = GPIO_PIN_4;   /* PA4 */
cfg.pdwn.port = GPIOC;  cfg.pdwn.pin = GPIO_PIN_1;   /* PC1 */

/* gain0/gain1/speed/a0 left NULL = strapped in hardware, do not drive */

cfg.gain    = ADS1232_GAIN_128;   /* MUST match the pull-ups */
cfg.rate    = ADS1232_RATE_10SPS; /* match the SPEED strap   */
cfg.channel = ADS1232_CH_AIN1;    /* match the A0 strap      */
cfg.vref    = 2.0f;               /* unused by the ratiometric call */

ADS1232_Init(&g_ads1232, &cfg);
```

`ADS1232_SetGain()` will return `HAL_ERROR` now, by design — the pins are strapped, so
firmware genuinely cannot change it. That is the correct behaviour, not a bug.

Keep the ground return short and shared. On flying leads the driver's slow bit-banged
clock (~500 kHz) is deliberate — do not speed it up until it works.

---

### 2. Analog side — the ratiometric arrangement

**Use this, not a calibrated current source.** Put a precision reference resistor in
*series* with the DUT. The same current flows through both, so it cancels completely and
you never have to know or stabilise it:

```
                    ┌───────────────── REFP
                    │
   I ──────►  ┌─────┴─────┐
              │   R_ref   │   precision, 0.1 % or better
              └─────┬─────┘
                    │
                    ├───────────────── REFN
                    │
                    ├───────────────── AINP1   ◄─ Kelvin tap, ON the DUT lead
              ┌─────┴─────┐
              │   R_DUT   │   the wire under test
              └─────┬─────┘
                    ├───────────────── AINN1   ◄─ Kelvin tap, ON the DUT lead
                    │
                   GND
```

```
R_DUT = R_ref × code / (gain × 2²³)          ← ADS1232_OhmsRatiometric()
```

The excitation current cancels out entirely; accuracy inherits `R_ref`'s tolerance. This
is the same trick proposed for the product board as HW-04.

**The Kelvin taps must land on the DUT terminals themselves**, not on the wire carrying
the current — that is the entire point of 4-wire. Two separate pairs of leads.

### Choosing R_ref — now the only range control you have

With the gain strapped at 128, `R_ref` is the **only** thing that sets the measurement
range. In the ratiometric arrangement the maths collapses to something convenient:

```
R_DUT(full scale) = R_ref / gain = R_ref / 128
```

| | |
|---|---|
| Rule of thumb | `R_ref ≈ 128 × (largest DUT you want to read)` |
| For harness wire up to ~10 Ω | `R_ref` ≥ 1.28 kΩ → use **2 kΩ** |
| Range with R_ref = 2 kΩ | **±15.6 Ω** of DUT |
| Resolution | 2000 Ω / (128 × 2²³) ≈ **1.9 µΩ per code** |
| Reference voltage | `I × R_ref` = 1 mA × 2 kΩ = **2 V** — comfortably inside a sane band |

Practical resolution will be noise-limited, not code-limited. Measure it: take a few
hundred conversions on a fixed resistor and look at the standard deviation.

Note the trade you no longer control from firmware: a bigger `R_ref` buys range and costs
resolution, and vice versa. If a DUT reads pinned at full scale, the fix is a larger
`R_ref`, not a gain change.

⚠ **VERIFY from the datasheet:** the ADS1232 has **no internal reference**, and its
`REFP/REFN` inputs have a minimum differential voltage. Keeping VREF in the 1–2.5 V band
above should stay clear of it, but confirm before trusting a reading.

---

### 3. Bring-up order

Gain is strapped at 128, so there is no "start wide and narrow down" step — the ADC is at
its most sensitive from the first reading. Work up from a shorted input instead.

1. Power up, strap `SPEED`=GND and `A0`=GND. Set `cfg.gain = ADS1232_GAIN_128`.
2. Confirm `DOUT` toggles — it should fall roughly every 100 ms at 10 SPS. If it never
   falls, check `PDWN` is high and `SCLK` is parked **low**.
3. **Short AINP1 to AINN1** and run `ADS1232_ReadRaw()`. It should sit near zero and be
   stable to a few counts. At gain 128 a *floating* input pair rails instead — if you see
   full scale, the sense leads are open, not broken.
4. `ADS1232_Tare()` with the inputs still shorted — captures amplifier offset and thermal
   EMF. Prefer it over `ADS1232_Calibrate()` until the datasheet confirms the calibration
   pulse sequence.
5. Fit `R_ref` (2 kΩ), apply the excitation, and read a **small known resistor** —
   1 Ω or so, well inside the 15.6 Ω range — with `ADS1232_OhmsRatiometric(&dev, 2000.0f,
   16, &ohms, 500)`. Check against a DMM.
6. Sanity-check the scaling by swapping in a second known resistor of a different value.
   If both read correct, the strapped gain matches `cfg.gain`; if both are wrong by the
   same factor, it does not.
7. Only then measure real harness wire.

Measure the actual excitation current with a DMM once, even though the ratiometric maths
does not need it — it tells you whether the compliance headroom is what you expect, which
is exactly the number the product board needs for BU-01.

---

### 4. What this rig does *not* prove

- Mux on-resistance and settling — there are no CD74HC4051s in the path here.
- The two-segment I2C bus, the enable maps, or anything about expanders.
- ADS124S08 register programming, which is a completely different interface.

It proves the **4-wire measurement principle, the ratiometric method, and the achievable
noise floor**. That is the useful part, and all three carry straight over.