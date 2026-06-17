/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    kelvin.h
  * @brief   Kelvin wire-impedance measurement. Forces a known current via the
  *          IDAC and reads the resulting drop through the InAmp + ADC, then
  *          R = (Vadc / InAmp_gain) / I_force.
  *
  *          NOTE: the matrix as drawn is 2-wire (HI/LO), not 4-wire, so this is
  *          a 2-wire resistance until separate sense routing exists. Parasitic
  *          mux/contact resistance is included in the result for now.
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

/* Force current setup. TUNE/VERIFY against the DAC8775 range + Vref. */
#ifndef KELVIN_FORCE_CODE
#define KELVIN_FORCE_CODE       0x8000U     /* mid-scale IDAC code            */
#endif
#ifndef KELVIN_FORCE_CURRENT_A
#define KELVIN_FORCE_CURRENT_A  0.010f       /* amps actually forced at CODE   */
#endif
#ifndef KELVIN_INAMP_GAIN
#define KELVIN_INAMP_GAIN       10.0f        /* instrumentation-amp gain V/V   */
#endif

/* Acceptance limits (ohms). TUNE per harness spec. */
#ifndef KELVIN_R_MAX_OHM
#define KELVIN_R_MAX_OHM        5.0f
#endif

typedef struct
{
  uint16_t      code;
  float         volts;          /* ADC volts (post-InAmp)          */
  float         resistance_ohm; /* computed wire resistance        */
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