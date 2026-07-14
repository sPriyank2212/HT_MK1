/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    continuity.c
  * @brief   Continuity test implementation. See continuity.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "test/continuity.h"

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

  HAL_Delay(CONTINUITY_SETTLE_MS);

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