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
  * @brief  Shared 500 V insulation sequence: energise one inject (HS) pin and
  *         measure leakage into every return (LS) relay in @p return_mask.
  * @warning Energises real high voltage. The sequence connects the reed relays
  *          while the line is dead, THEN programs the DAC (which is the HV
  *          control), to avoid hot-switching the contacts at 500 V.
  * @note   Sequence: force safe, connect dead, ramp HV to @p v_fraction, settle
  *         INSULATION_RAMP_MS, then read the LEAKAGE node (HV_RET, U302 - not
  *         the rail). Verdict is TEST_FAIL when leakage voltage >=
  *         INSULATION_V_PASS_MAX, else TEST_PASS. The card is always
  *         de-energised, discharged and opened before return.
  * @param  board       : [in]  HV board index (0..BOARD_HV_COUNT-1).
  * @param  inject_pin  : [in]  1-based pin on the inject side (1..64).
  * @param  return_mask : [in]  bit (pin-1) set = close that return relay. Must
  *                             be non-zero: no closed return relay reads ~0 V,
  *                             i.e. a false PASS.
  * @param  v_fraction  : [in]  applied HV as a fraction of full scale (0..1).
  * @param  res         : [out] result. Left TEST_ERROR on early failure.
  * @retval HAL_OK    test completed (inspect res->verdict for the outcome).
  * @retval HAL_ERROR @p res is NULL, @p board out of range, @p inject_pin out
  *                   of 1..64, or @p return_mask empty.
  * @retval other     first failing HAL status from relay/HV/ADC access.
  */
static HAL_StatusTypeDef insulation_run(uint8_t board, uint8_t inject_pin,
                                        uint64_t return_mask, float v_fraction,
                                        InsulationResult_t *res)
{
  HvCard_t *hv;
  HAL_StatusTypeDef st;

  if (res == NULL || board >= (uint8_t)BOARD_HV_COUNT ||
      inject_pin < 1U || inject_pin > (uint8_t)HV_PINS_PER_SIDE ||
      return_mask == 0ULL || v_fraction < INSULATION_MIN_FRACTION)
  {
    return HAL_ERROR;
  }
  hv = &g_hv[board];

  /* Keep this card's enable asserted for the whole sequence: its chip-select
   * buffers are gated by the same line, so the DAC and ADCs are unreachable
   * without it. */
  HvCard_Hold(hv);

  res->sense_code      = 0U;
  res->sense_volts     = 0.0f;
  res->insulation_mohm = 0.0f;
  res->verdict         = TEST_ERROR;

  /* Pre-condition: known safe state (HV at 0 V, all relays open). */
  insulation_safe(hv);

  /* Connect the conductor pair FIRST, while the line is dead. There is no HV
   * enable line: programming the DAC is what raises HV. Closing the reed relays
   * after energising would hot-switch them at 500 V and erode the contacts. */
  st = HvCard_CloseInject(hv, inject_pin);
  if (st == HAL_OK)
  {
    st = HvCard_CloseReturnMask(hv, return_mask);
  }
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
    res->verdict = (v_leak >= Insulation_PassLimitVolts(v_fraction)) ? TEST_FAIL : TEST_PASS;
  }

safe_exit:
  /* Always de-energise, discharge and open relays before returning. */
  insulation_safe(hv);
  HvCard_Unhold(hv);
  return st;
}
HAL_StatusTypeDef Insulation_HvSelfTest(uint8_t board, float *v_idle, float *v_hv)
{
  HvCard_t *hv;
  HAL_StatusTypeDef st;
  uint16_t code = 0U;
  float idle = 0.0f, rail = 0.0f;
  const float expect = INSULATION_SELFTEST_FRACTION * INSULATION_V_FULL *
                       INSULATION_HV_SENSE_RATIO;

  if (board >= (uint8_t)BOARD_HV_COUNT)
  {
    return HAL_ERROR;
  }
  hv = &g_hv[board];
  HvCard_Hold(hv);

  insulation_safe(hv);                       /* 0 V, relays open */
  st = HvCard_ReadRailRaw(hv, &code);
  if (st == HAL_OK)
  {
    idle = AD7476_CodeToVolts(code, hv->cfg.vref);
    st = HvCard_SetVoltageFraction(hv, INSULATION_SELFTEST_FRACTION);
  }
  if (st == HAL_OK)
  {
    Board_SettleMs(INSULATION_SELFTEST_SETTLE_MS);
    st = HvCard_ReadRailRaw(hv, &code);
    rail = AD7476_CodeToVolts(code, hv->cfg.vref);
  }
  insulation_safe(hv);                       /* always back to 0 V */
  HvCard_Unhold(hv);

  if (v_idle != NULL) { *v_idle = idle; }
  if (v_hv   != NULL) { *v_hv   = rail; }
  if (st != HAL_OK) { return st; }
  return Insulation_RailPlausible(idle, rail, expect) ? HAL_OK : HAL_ERROR;
}

/**
  * @brief  Insulation test of one inject pin against ONE return pin (manual
  *         pair test). See insulation_run().
  * @retval HAL_ERROR if either pin is outside 1..64, else as insulation_run().
  */
HAL_StatusTypeDef Insulation_TestPair(uint8_t board, uint8_t inject_pin,
                                      uint8_t return_pin, float v_fraction,
                                      InsulationResult_t *res)
{
  if (return_pin < 1U || return_pin > (uint8_t)HV_PINS_PER_SIDE)
  {
    return HAL_ERROR;
  }
  return insulation_run(board, inject_pin, 1ULL << (return_pin - 1U),
                        v_fraction, res);
}

/**
  * @brief  Insulation test of one net against every OTHER conductor: energise
  *         the net's inject pin and close all return relays in @p return_mask
  *         (every return pin except the net's own). This is the scheme the
  *         project requires - a single return relay only sees one neighbour.
  * @retval as insulation_run().
  */
HAL_StatusTypeDef Insulation_TestNet(uint8_t board, uint8_t inject_pin,
                                     uint64_t return_mask, float v_fraction,
                                     InsulationResult_t *res)
{
  return insulation_run(board, inject_pin, return_mask, v_fraction, res);
}
