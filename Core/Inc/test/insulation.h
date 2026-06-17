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

typedef struct
{
  uint16_t      sense_code;
  float         sense_volts;
  float         insulation_mohm;   /* STUB until measurement chain confirmed */
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