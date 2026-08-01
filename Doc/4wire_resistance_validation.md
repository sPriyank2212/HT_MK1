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

### 5.1 Common-mode headroom is now marginal — verify it

The ADS124S08 is far more forgiving than the ADS1232 (0.15 V floor vs 1.5 V), but the mux
swap to CD74HC4051 cut the available lift:

```
LO_SENSE ≈ I × (R_LOmux + R131)
```

| Excitation | with CD4067B (~900 Ω) | with CD74HC4051 (~100 Ω) |
|---|---|---|
| 1.0 mA | 1.0 V — comfortable | **0.20 V** |
| 0.5 mA | 0.50 V | **0.10 V — below the 0.15 V floor** |

The required floor at gain 32 with a 1 mV signal is `0.15 + 15.5 × 0.001 = 0.166 V`, leaving
only ~34 mV of margin at 1 mA and **violating it below ~0.85 mA**.

**Action:** confirm CD74HC4051 Rₒₙ at 3.3 V, then either hold the excitation at ≥1 mA or
raise R131. Note the irony — improving the multiplexers made the common-mode margin worse,
because R131 was sized when the mux drop was doing most of the lifting.

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
