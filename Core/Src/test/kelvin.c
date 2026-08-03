/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    kelvin.c
  * @brief   Kelvin impedance measurement implementation. See kelvin.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "test/kelvin.h"

/**
  * @brief  Measure the 4-wire (Kelvin) resistance of one harness pair.
  * @note   Sequence: route the pair through the matrix, switch the control
  *         front end to the current source, force KELVIN_FORCE_CODE, settle,
  *         then read the node. In impedance mode the Opto SPDT disconnects the
  *         control ADC, so the node is read through the matrix ADC (U33).
  *         Resistance is R = (Vadc / INAMP_GAIN) / I_force and the verdict is
  *         PASS when R <= KELVIN_R_MAX_OHM. The front end and matrix are always
  *         released before returning, even on error.
  * @param  hi_pin : [in]  1-based HI-side harness pin.
  * @param  lo_pin : [in]  1-based LO-side harness pin.
  * @param  res    : [out] result (raw code, volts, resistance, verdict). On any
  *                       early error the verdict is left TEST_ERROR. Must be non-NULL.
  * @retval HAL_OK    measurement completed (inspect res->verdict for pass/fail).
  * @retval HAL_ERROR @p res is NULL.
  * @retval other     first failing HAL status from routing/front-end/ADC access.
  */
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

  /* NOT IMPLEMENTED - awaiting FW-01 (drivers/ads124s08).
   *
   * This used to read HI_COM through the Matrix card's AD7476 (U33) and divide
   * by a hard-coded 10 mA. Matrix_Card 2 deleted U33 entirely, and the
   * measurement moved to a genuine 4-wire read of HI_SENSE - LO_SENSE on the
   * ADS124S08. Failing loudly is better than returning a number produced by
   * reading a chip that is no longer on the board.
   *
   * The rewrite (FW-02) needs, per Doc/4wire_resistance_validation.md:
   *   - sense pairing on: MatrixCard_SetSensePaired(&g_matrix, 1)
   *   - excitation ~5 mA (window is 1..8 mA; below 1 mA the sense common mode
   *     falls under the ADS124S08 PGA floor, above 8 mA the force loop runs out
   *     of compliance on 3.3 V)
   *   - PGA auto-ranging, which also keeps the common mode legal on large R
   *   - R = R_ref * code / (gain * 2^23)   <- NO factor of 2; that belongs to
   *     the ADS1232 bench rig only (BU-08)
   *   - current reversal to cancel thermal EMF (BU-10) */
  st = HAL_ERROR;
  res->verdict = TEST_ERROR;

release:
  /* Stop forcing current and open the matrix. */
  (void)Frontend_SetCurrentCode(&g_frontend, 0U);
  (void)Frontend_SetMode(&g_frontend, FRONTEND_MODE_CONTINUITY);
  (void)MatrixCard_AllOff(&g_matrix);
  return st;
}