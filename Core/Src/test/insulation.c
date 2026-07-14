/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    insulation.c
  * @brief   500 V insulation-resistance test implementation. See insulation.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "test/insulation.h"

/* Bring a board to the fully-safe state: HV off, discharge asserted briefly,
 * relays open, 0 V programmed. Used on entry and on every exit path. */
static void insulation_safe(HvCard_t *hv)
{
  (void)HvCard_HvEnable(hv, 0U);
  (void)HvCard_SetVoltageCode(hv, 0U);
  (void)HvCard_Discharge(hv, 1U);
  HAL_Delay(INSULATION_DISCHARGE_MS);
  (void)HvCard_Discharge(hv, 0U);
  (void)HvCard_OpenAllRelays(hv);
}

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

  /* Pre-condition: known safe state. */
  insulation_safe(hv);

  /* Program the stress voltage and connect the conductor pair BEFORE enabling
   * HV (relays switch cold). */
  st = HvCard_SetVoltageFraction(hv, v_fraction);
  if (st != HAL_OK)
  {
    goto safe_exit;
  }
  st = HvCard_ConnectPair(hv, inject_pin, return_pin);
  if (st != HAL_OK)
  {
    goto safe_exit;
  }

  /* Energise, let the rail ramp/settle, then measure the sense node. */
  st = HvCard_HvEnable(hv, 1U);
  if (st != HAL_OK)
  {
    goto safe_exit;
  }
  HAL_Delay(INSULATION_RAMP_MS);

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