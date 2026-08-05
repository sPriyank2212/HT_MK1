/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    continuity.c
  * @brief   Continuity test implementation. See continuity.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "test/continuity.h"

/**
  * @brief  Test continuity of one harness pair via the +3V3 divider.
  * @note   Sequence: put the control front end in continuity mode, route the
  *         pair through the matrix, settle, then read the node through the
  *         control ADC. Verdict bands:
  *           - >= CONTINUITY_OPEN_V_MIN                       -> TEST_OPEN (no wire)
  *           - CONNECTED_V_MIN..CONNECTED_V_MAX (~1.5 V)      -> TEST_PASS (wire present)
  *           - anything else                                  -> TEST_ERROR (anomaly)
  *         The matrix is always released before returning.
  * @param  hi_pin : [in]  1-based HI-side harness pin.
  * @param  lo_pin : [in]  1-based LO-side harness pin.
  * @param  res    : [out] result (raw code, volts, verdict). On any early error
  *                       the verdict is left TEST_ERROR. Must be non-NULL.
  * @retval HAL_OK    test completed (inspect res->verdict for the outcome).
  * @retval HAL_ERROR @p res is NULL.
  * @retval other     first failing HAL status from front-end/matrix/ADC access.
  */
HAL_StatusTypeDef Continuity_TestPair(uint16_t hi_pin, uint16_t lo_pin,
                                      ContinuityResult_t *res)
{
  HAL_StatusTypeDef st;

  if (res == NULL)
  {
    return HAL_ERROR;
  }
  res->code    = 0U;
  res->volts   = 0.0f;
  res->verdict = TEST_ERROR;

  st = Frontend_SetMode(&g_frontend, FRONTEND_MODE_CONTINUITY);
  if (st != HAL_OK)
  {
    return st;
  }
  st = MatrixCard_ConnectPair(&g_matrix, hi_pin, lo_pin);
  if (st != HAL_OK)
  {
    return st;
  }

  Board_SettleMs(CONTINUITY_SETTLE_MS);

  st = Frontend_ReadRaw(&g_frontend, &res->code);
  if (st == HAL_OK)
  {
    res->volts = AD7476_CodeToVolts(res->code, g_frontend.vref);
    if (res->volts >= CONTINUITY_OPEN_V_MIN)
    {
      res->verdict = TEST_OPEN;      /* sits at the unloaded 3V3 reference */
    }
    else if (res->volts >= CONTINUITY_CONNECTED_V_MIN &&
             res->volts <= CONTINUITY_CONNECTED_V_MAX)
    {
      res->verdict = TEST_PASS;      /* ~1.5 V divider point -> wire present */
    }
    else
    {
      res->verdict = TEST_ERROR;     /* out of both bands -> anomaly */
    }
  }

  /* Always release the matrix, but report the measurement error if any. */
  (void)MatrixCard_AllOff(&g_matrix);
  return st;
}