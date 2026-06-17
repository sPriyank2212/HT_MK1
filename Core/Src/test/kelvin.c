/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    kelvin.c
  * @brief   Kelvin impedance measurement implementation. See kelvin.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "test/kelvin.h"

HAL_StatusTypeDef Kelvin_MeasurePair(uint16_t hi_pin, uint16_t lo_pin,
                                     KelvinResult_t *res)
{
  HAL_StatusTypeDef st;

  if (res == NULL)
  {
    return HAL_ERROR;
  }
  res->code           = 0U;
  res->volts          = 0.0f;
  res->resistance_ohm = 0.0f;
  res->verdict        = TEST_ERROR;

  /* Route the wire, switch the front end to the current source, force current. */
  st = MatrixCard_ConnectPair(&g_matrix, hi_pin, lo_pin);
  if (st != HAL_OK)
  {
    return st;
  }
  st = Frontend_SetMode(&g_frontend, FRONTEND_MODE_IMPEDANCE);
  if (st != HAL_OK)
  {
    goto release;
  }
  st = Frontend_SetCurrentCode(&g_frontend, KELVIN_FORCE_CODE);
  if (st != HAL_OK)
  {
    goto release;
  }

  HAL_Delay(KELVIN_SETTLE_MS);

  st = Frontend_ReadRaw(&g_frontend, &res->code);
  if (st == HAL_OK)
  {
    res->volts = AD7476_CodeToVolts(res->code, g_frontend.vref);
    /* R = Vsense / I, Vsense = Vadc / gain. */
    res->resistance_ohm = (res->volts / KELVIN_INAMP_GAIN) / KELVIN_FORCE_CURRENT_A;
    res->verdict = (res->resistance_ohm <= KELVIN_R_MAX_OHM) ? TEST_PASS : TEST_FAIL;
  }

release:
  /* Stop forcing current and open the matrix. */
  (void)Frontend_SetCurrentCode(&g_frontend, 0U);
  (void)Frontend_SetMode(&g_frontend, FRONTEND_MODE_CONTINUITY);
  (void)MatrixCard_AllOff(&g_matrix);
  return st;
}