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

/* Voltage windows for the continuity front end (R54: 10 kohm from +3V3 to the
 * ADC input; the wire then returns through the HI mux, the LO mux and R131):
 *
 *   V = 3.3 V x R_low / (10 kohm + R_low),  R_low = Ron_HI + R_wire + Ron_LO + 100 ohm
 *
 *   good wire: Ron 60..320 ohm per mux, wire <= 5 ohm
 *              -> R_low 220..745 ohm -> V = 0.07 .. 0.23 V   (typical ~0.11 V)
 *   open (no wire)                   -> V ~= 3.3 V
 *
 * The windows below leave about 2x margin around the good-wire range and sit
 * well away from "open". The mux Ron at 3.3 V is only extrapolated from the
 * datasheet (BU-09), so confirm with one known-good loopback at bring-up.
 *   - V < MIN                 : reading stuck at ~0 (a connection cannot read
 *                               below ~0.033 V even with zero mux Ron) -> error
 *   - MIN .. MAX              : wire present, up to about 1.4 kohm of wire
 *   - MAX .. OPEN_MIN         : high-resistance or leaky path -> error
 *   - >= OPEN_MIN             : no wire. */
#ifndef CONTINUITY_CONNECTED_V_MIN
#define CONTINUITY_CONNECTED_V_MIN   0.02f
#endif
#ifndef CONTINUITY_CONNECTED_V_MAX
#define CONTINUITY_CONNECTED_V_MAX   0.50f
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

/** Classify an ADC input voltage: TEST_OPEN (no wire), TEST_PASS (wire present)
 *  or TEST_ERROR (outside both windows). */
static inline TestVerdict_t Continuity_Classify(float volts)
{
  if (volts >= CONTINUITY_OPEN_V_MIN)
  {
    return TEST_OPEN;
  }
  if (volts >= CONTINUITY_CONNECTED_V_MIN && volts <= CONTINUITY_CONNECTED_V_MAX)
  {
    return TEST_PASS;
  }
  return TEST_ERROR;
}

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