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

/** Pass limit for the leakage node at a given stimulus (volts). The limit scales
 *  linearly with the applied voltage: V(HV_RET) = V_applied x R3004 / (R + ...). */
static inline float Insulation_PassLimitVolts(float v_fraction)
{
  return INSULATION_V_PASS_MAX * v_fraction;
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
