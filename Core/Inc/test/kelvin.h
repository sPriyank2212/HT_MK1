/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    kelvin.h
  * @brief   4-wire (Kelvin) resistance measurement. Forces a known current via
  *          the Control-Card IDAC (DAC8775) and reads the drop directly across
  *          HI_SENSE/LO_SENSE on the Matrix Card's ADS124S08 - a true 4-wire
  *          measurement, since the sense taps carry no force current and so
  *          exclude mux/contact resistance from the force path.
  *
  *          R = V / I_force, with V from the ADS124S08 at auto-ranged PGA gain
  *          and I_force from KELVIN_FORCE_CURRENT_A (TUNE/VERIFY - see below).
  *          Ratiometric measurement (R = R_ref * code / (gain * 2^23), which
  *          would cancel DAC error entirely) needs HW-04 and is not available
  *          yet - see ads124s08.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __KELVIN_H
#define __KELVIN_H

#ifdef __cplusplus
extern "C" {
#endif

#include "test/harness_test.h"

#ifndef KELVIN_SETTLE_MS
#define KELVIN_SETTLE_MS        2U
#endif

/* Force current setup. TUNE/VERIFY against the DAC8775 range + Vref - the
 * DAC8775 driver's register map is itself still placeholder (dac8775.h). */
#ifndef KELVIN_FORCE_CODE
#define KELVIN_FORCE_CODE       0x8000U     /* mid-scale IDAC code            */
#endif
#ifndef KELVIN_FORCE_CURRENT_A
#define KELVIN_FORCE_CURRENT_A  0.010f       /* amps actually forced at CODE   */
#endif

/* Acceptance limits (ohms). TUNE per harness spec. */
#ifndef KELVIN_R_MAX_OHM
#define KELVIN_R_MAX_OHM        5.0f
#endif

/* Reject a reading whose code saturates the PGA even at unity gain, rather
 * than report a number computed from a clipped conversion. */
#ifndef KELVIN_SATURATION_FRACTION
#define KELVIN_SATURATION_FRACTION  0.90f
#endif

typedef struct
{
  int32_t       code;           /* ADS124S08 code, excited minus zero-current */
  float         volts;          /* corresponding volts at the ADC input       */
  float         resistance_ohm; /* computed wire resistance                   */
  TestVerdict_t verdict;
} KelvinResult_t;

/**
  * @brief  Measure one wire (hi_pin forced, lo_pin return).
  */
HAL_StatusTypeDef Kelvin_MeasurePair(uint16_t hi_pin, uint16_t lo_pin,
                                     KelvinResult_t *res);

#ifdef __cplusplus
}
#endif

#endif /* __KELVIN_H */