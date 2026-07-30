# ADS1232 bench rig — 4-wire resistance, NUCLEO-G474RE

Stand-in for the ADS124S08 while the Matrix card does not exist. Enable the driver with
`-DHT_ENABLE_ADS1232=1`; it compiles to nothing otherwise.

> **The ADS1232 is not an SPI device.** There is no chip select and no MOSI, and `DOUT`
> doubles as `DRDY`. You need **two GPIOs**, not an SPI peripheral. Gain, data rate and
> channel are set by *static pins*, not registers.

> **Pin numbers are deliberately omitted.** Add `Datasheet/ads1232.pdf` and I will fill
> them in. Wire by *signal name* from the part's own pinout — a wrong pin number on a
> 24-bit ADC costs an afternoon at best.

---

## 1. Digital side — Nucleo to ADS1232

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

> **Cross-check this list against the datasheet pinout.** It was written without a copy of
> `ads1232.pdf` and has already been found short twice (`AVDD`, `CLKIN`). Every pin on the
> part needs a defined state — none may be left floating.

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

## 2. Analog side — the ratiometric arrangement

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

## 3. Bring-up order

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

## 4. What this rig does *not* prove

- Mux on-resistance and settling — there are no CD74HC4051s in the path here.
- The two-segment I2C bus, the enable maps, or anything about expanders.
- ADS124S08 register programming, which is a completely different interface.

It proves the **4-wire measurement principle, the ratiometric method, and the achievable
noise floor**. That is the useful part, and all three carry straight over.
