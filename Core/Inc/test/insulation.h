/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    insulation.h
  * @brief   500 V insulation-resistance test for one HV board. Implements the
  *          full safe HV sequence (set V -> connect relays -> enable HV ->
  *          settle -> measure -> disable -> mandatory discharge -> open relays).
  *
  *          OPEN POINT (#4 in fw_status.txt): the leakage-current sense chain is
  *          unconfirmed, so the final leakage -> insulation-resistance maths is
  *          STUBBED. The sequencing, timing and safety are complete; only the
  *          conversion of HvCard sense into ohms is pending the measurement
  *          topology. Verdict is TEST_ERROR until that is resolved.
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __INSULATION_H
#define __INSULATION_H

#ifdef __cplusplus
extern "C" {
#endif

#include "test/harness_test.h"

#ifndef INSULATION_RAMP_MS
#define INSULATION_RAMP_MS       50U    /* settle after HV enable, before read  */
#endif
#ifndef INSULATION_DISCHARGE_MS
#define INSULATION_DISCHARGE_MS  200U   /* mandatory bleed time before relay sw  */
#endif

/* Acceptance threshold (Mohm). TUNE per harness standard. */
#ifndef INSULATION_R_MIN_MOHM
#define INSULATION_R_MIN_MOHM    100.0f
#endif

/* Leakage-node (HV_RET, across R3004 = 1 kohm) GO/NO-GO threshold. Higher V =
 * worse insulation. Board decision: 10 Mohm insulation -> 0.045 V leakage is
 * the pass/fail boundary (below 0.045 V => PASS >10 Mohm, at/above => FAIL).
 * Absolute volts, independent of the ADC vref. */
#ifndef INSULATION_V_PASS_MAX
#define INSULATION_V_PASS_MAX    0.045f
#endif

/* Sense-divider constants for the (informational) leakage -> ohms estimate.
 * R_series ~= 1 Mohm makes 10 Mohm insulation land at 0.045 V across R3004. */
#ifndef INSULATION_R_BOTTOM_OHM
#define INSULATION_R_BOTTOM_OHM  1000.0f     /* R3004                          */
#endif
#ifndef INSULATION_R_SERIES_OHM
#define INSULATION_R_SERIES_OHM  1000000.0f  /* effective leakage-path series  */
#endif
#ifndef INSULATION_V_FULL
#define INSULATION_V_FULL        500.0f      /* HV at full-scale DAC           */
#endif

typedef struct
{
  uint16_t      sense_code;        /* leakage-node (HV_RET) raw code         */
  float         sense_volts;       /* leakage-node volts                     */
  float         insulation_mohm;   /* approximate estimate (see .c)          */
  TestVerdict_t verdict;
} InsulationResult_t;

/**
  * @brief  Apply a controlled stress between two conductors on one HV board and
  *         measure. v_fraction sets the HV DAC (0.0..1.0 of full scale).
  * @param  board       HV board index (0..BOARD_HV_COUNT-1)
  * @param  inject_pin  1..64 inject side
  * @param  return_pin  1..64 return side
  * @param  v_fraction  HV program fraction
  * @param  res         result out
  * @note   Always discharges and opens relays before returning, even on error.
  */
HAL_StatusTypeDef Insulation_TestPair(uint8_t board, uint8_t inject_pin,
                                      uint8_t return_pin, float v_fraction,
                                      InsulationResult_t *res);

#ifdef __cplusplus
}
#endif

#endif /* __INSULATION_H */