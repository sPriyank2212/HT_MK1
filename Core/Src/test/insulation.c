/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    insulation.c
  * @brief   500 V insulation-resistance test implementation. See insulation.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "test/insulation.h"

/**
  * @brief  Drive an HV card to the fully-safe state.
  * @note   Disables HV, programs the DAC to 0 V, pulses discharge for
  *         INSULATION_DISCHARGE_MS, then opens all relays. Called both on entry
  *         (pre-condition) and on every exit path of Insulation_TestPair().
  * @param  hv : [in] HV-card instance to make safe.
  * @retval None
  */
static void insulation_safe(HvCard_t *hv)
{
  (void)HvCard_HvEnable(hv, 0U);
  (void)HvCard_SetVoltageCode(hv, 0U);
  (void)HvCard_Discharge(hv, 1U);
  Board_SettleMs(INSULATION_DISCHARGE_MS);
  (void)HvCard_Discharge(hv, 0U);
  (void)HvCard_OpenAllRelays(hv);
}

/**
  * @brief  Run a 500 V insulation-resistance test on one conductor pair.
  * @warning Energises real high voltage. The sequence connects the reed relays
  *          while the line is dead, THEN programs the DAC (which is the HV
  *          control), to avoid hot-switching the contacts at 500 V.
  * @note   Sequence: force safe, connect the pair dead, ramp HV to @p v_fraction,
  *         settle INSULATION_RAMP_MS, then read the LEAKAGE node (HV_RET, U302 -
  *         not the rail). Insulation resistance is estimated from the leakage
  *         node (approximate; the transimpedance is unconfirmed). Verdict is
  *         TEST_FAIL when leakage voltage >= INSULATION_V_PASS_MAX, else TEST_PASS.
  *         The card is always de-energised, discharged and opened before return.
  * @param  board      : [in]  HV board index (0..BOARD_HV_COUNT-1).
  * @param  inject_pin : [in]  1-based pin on the inject side.
  * @param  return_pin : [in]  1-based pin on the return side.
  * @param  v_fraction : [in]  applied HV as a fraction of full scale (0..1).
  * @param  res        : [out] result (leakage code/volts, insulation Mohm,
  *                           verdict). Left TEST_ERROR on early failure. Non-NULL.
  * @retval HAL_OK    test completed (inspect res->verdict for the outcome).
  * @retval HAL_ERROR @p res is NULL or @p board is out of range.
  * @retval other     first failing HAL status from relay/HV/ADC access.
  */
HAL_StatusTypeDef Insulation_TestPair(uint8_t board, uint8_t inject_pin,
                                      uint8_t return_pin, float v_fraction,
                                      InsulationResult_t *res)
{
  HvCard_t *hv;
  HAL_StatusTypeDef st;

  if (res == NULL || board >= (uint8_t)BOARD_HV_COUNT)
  {
    return HAL_ERROR;
  }
  hv = &g_hv[board];

  res->sense_code      = 0U;
  res->sense_volts     = 0.0f;
  res->insulation_mohm = 0.0f;
  res->verdict         = TEST_ERROR;

  /* Pre-condition: known safe state (HV at 0 V, all relays open). */
  insulation_safe(hv);

  /* Connect the conductor pair FIRST, while the line is dead. There is no HV
   * enable line: programming the DAC is what raises HV. Closing the reed relays
   * after energising would hot-switch them at 500 V and erode the contacts. */
  st = HvCard_ConnectPair(hv, inject_pin, return_pin);
  if (st != HAL_OK)
  {
    goto safe_exit;
  }

  /* Energise (the DAC IS the HV control), let the rail ramp/settle. */
  st = HvCard_SetVoltageFraction(hv, v_fraction);
  if (st != HAL_OK)
  {
    goto safe_exit;
  }
  Board_SettleMs(INSULATION_RAMP_MS);

  /* The insulation reading is the LEAKAGE node (HV_RET, U302), NOT the rail. */
  st = HvCard_ReadLeakageRaw(hv, &res->sense_code);
  if (st == HAL_OK)
  {
    float v_leak = AD7476_CodeToVolts(res->sense_code, hv->cfg.vref);
    res->sense_volts = v_leak;

    /* Approximate insulation resistance from the leakage node:
     *   I_leak = V_leak / R_bottom
     *   V_applied ~= v_fraction * full-scale HV
     *   R_ins ~= V_applied / I_leak - R_series   (clamped >= 0)
     * Approximate: exact transimpedance of R3003/R3004 is unconfirmed. */
    if (v_leak > 0.0005f)
    {
      float i_leak = v_leak / INSULATION_R_BOTTOM_OHM;
      float v_app  = v_fraction * INSULATION_V_FULL;
      float r_ohm  = (v_app / i_leak) - INSULATION_R_SERIES_OHM;
      res->insulation_mohm = (r_ohm > 0.0f) ? (r_ohm / 1.0e6f) : 0.0f;
    }
    else
    {
      res->insulation_mohm = 9999.0f;   /* negligible leakage -> effectively open */
    }

    /* Verdict: higher leakage voltage = worse insulation. */
    res->verdict = (v_leak >= INSULATION_V_PASS_MAX) ? TEST_FAIL : TEST_PASS;
  }

safe_exit:
  /* Always de-energise, discharge and open relays before returning. */
  insulation_safe(hv);
  return st;
}