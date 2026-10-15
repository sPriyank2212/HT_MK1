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

/* Voltage windows per the Operation Document (3V3 pull-up front end):
 *   connected wire  -> ~1.5 V  (band 1.3 .. 1.7 V)
 *   open  (no wire)  -> ~3.3 V  (>= ~3.0 V)
 *   anything else    -> anomalous (relay/wiring fault). */
#ifndef CONTINUITY_CONNECTED_V_MIN
#define CONTINUITY_CONNECTED_V_MIN   1.3f
#endif
#ifndef CONTINUITY_CONNECTED_V_MAX
#define CONTINUITY_CONNECTED_V_MAX   1.7f
#endif
#ifndef CONTINUITY_OPEN_V_MIN
#define CONTINUITY_OPEN_V_MIN        3.0f
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