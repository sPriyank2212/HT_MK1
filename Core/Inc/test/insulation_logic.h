/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    insulation_logic.h
  * @brief   Pure (hardware-free) rules of the insulation test: the pass limit and
  *          the "is the rail really up" check. Kept free of HAL includes so the
  *          host-side unit tests (tests/fw_host) can compile it.
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __INSULATION_LOGIC_H
#define __INSULATION_LOGIC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Leakage-node (HV_RET, across R3004 = 1 kohm) GO/NO-GO threshold. Higher V =
 * worse insulation. Board decision: 10 Mohm insulation -> 0.045 V leakage is
 * the pass/fail boundary (below 0.045 V => PASS >10 Mohm, at/above => FAIL).
 * Absolute volts, independent of the ADC vref. */
#ifndef INSULATION_V_PASS_MAX
#define INSULATION_V_PASS_MAX    0.045f
#endif


/** Pass limit for the leakage node at a given stimulus (volts), for the DEFAULT
 *  10 Mohm limit. The limit scales linearly with the applied voltage:
 *  V(HV_RET) = V_applied x R3004 / (R + ...). */
static inline float Insulation_PassLimitVolts(float v_fraction)
{
  return INSULATION_V_PASS_MAX * v_fraction;
}

/* ---------------------------------------------------------------------------
 * Configurable minimum insulation resistance (FW-11, "LIMITS SET ins_min_mohm").
 *
 * The verdict stays a voltage comparison on the leakage node (so the board's
 * 10 Mohm <-> 0.045 V decision is untouched at the default); the operator's limit
 * only moves the voltage threshold. Higher limit -> lower threshold voltage.
 * Units are milliohms in int64: 10 Mohm = 1e10 mohm, which does not fit int32.
 * ------------------------------------------------------------------------- */
#define INSULATION_LIMIT_DEFAULT_MOHM  10000000000LL   /* 10 Mohm: the board decision */
#define INSULATION_LIMIT_MIN_MOHM        100000000LL   /* 100 kohm                    */
#define INSULATION_LIMIT_MAX_MOHM      40000000000LL   /*  40 Mohm                    */

/* The limit the INSULATION_V_PASS_MAX constant was worked out for, and the
 * effective series resistance of the leakage path (same model as the informational
 * Mohm estimate in insulation.c). Both in ohms. */
#define INSULATION_LIMIT_REF_OHM       10000000.0f
#ifndef INSULATION_R_SERIES_OHM
#define INSULATION_R_SERIES_OHM        1000000.0f
#endif

/* Below this the pass threshold is only a handful of 12-bit/5 V ADC counts
 * (1.2 mV each) and a verdict against it is not trustworthy: refuse. 40 Mohm at
 * full stimulus is ~12 mV, which is why that is the upper bound above. */
#define INSULATION_MIN_PASS_V          0.010f

/** True when @p mohm is a limit the hardware can actually resolve. Anything else
 *  is REFUSED by the protocol, never clamped (a silent clamp is a wrong limit
 *  that looks right), and 0 / negative would make every net pass. */
static inline int Insulation_LimitValid(int64_t mohm)
{
  return (mohm >= INSULATION_LIMIT_MIN_MOHM) && (mohm <= INSULATION_LIMIT_MAX_MOHM);
}

/** Pass limit for the leakage node at a given stimulus and operator limit
 *  (volts). Anchored at the board decision so the default limit gives exactly
 *  INSULATION_V_PASS_MAX x v_fraction, then follows the divider model
 *  V ~ 1 / (R_limit + R_series). */
static inline float Insulation_PassLimitVoltsFor(float v_fraction, int64_t limit_mohm)
{
  const float limit_ohm = (float)limit_mohm / 1000.0f;
  return INSULATION_V_PASS_MAX * v_fraction *
         ((INSULATION_LIMIT_REF_OHM + INSULATION_R_SERIES_OHM) /
          (limit_ohm + INSULATION_R_SERIES_OHM));
}

/** True when the HV_Sense reading proves the DAC raised the rail and the rail ADC
 *  answered: idle reading near 0, energised reading within 0.5x..1.5x of the
 *  expected value. */
static inline int Insulation_RailPlausible(float v_idle, float v_hv, float v_expect)
{
  return (v_idle < 0.2f * v_expect) && (v_hv > 0.5f * v_expect) && (v_hv < 1.5f * v_expect);
}

#ifdef __cplusplus
}
#endif

#endif /* __INSULATION_LOGIC_H */
