/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    continuity.h
  * @brief   Continuity / connectivity test. Routes a pin pair onto HI/LO, puts
  *          the front end in continuity mode, samples the divider mid-point and
  *          classifies open / connected.
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __CONTINUITY_H
#define __CONTINUITY_H

#ifdef __cplusplus
extern "C" {
#endif

#include "test/harness_test.h"

/* Settling time after switching the matrix before sampling (ms). TUNE. */
#ifndef CONTINUITY_SETTLE_MS
#define CONTINUITY_SETTLE_MS    2U
#endif

/* Voltage window for a confirmed connection (volts). TUNE to the actual divider.
 * A connected pair collapses the divider toward this band; an open sits at the
 * unloaded reference (outside the band). */
#ifndef CONTINUITY_CONNECTED_V_MAX
#define CONTINUITY_CONNECTED_V_MAX   0.5f
#endif

typedef struct
{
  uint16_t      code;
  float         volts;
  TestVerdict_t verdict;   /* TEST_PASS (connected) / TEST_OPEN / TEST_ERROR */
} ContinuityResult_t;

/**
  * @brief  Test one pin pair (1..256 each). Connects hi->HI, lo->LO, samples,
  *         then opens the matrix again.
  */
HAL_StatusTypeDef Continuity_TestPair(uint16_t hi_pin, uint16_t lo_pin,
                                      ContinuityResult_t *res);

#ifdef __cplusplus
}
#endif

#endif /* __CONTINUITY_H */