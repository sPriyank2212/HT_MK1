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

  st = HvCard_ReadSenseRaw(hv, &res->sense_code);
  if (st == HAL_OK)
  {
    res->sense_volts = AD7476_CodeToVolts(res->sense_code, hv->cfg.vref);

    /* ---- OPEN POINT #4: leakage-current -> insulation-resistance ----------
     * The HV measurement chain (leakage shunt + InAmp -> ADC vs HV_Sense
     * divider) is unconfirmed. Once known:
     *   I_leak  = f(sense_volts, shunt, gain)
     *   V_applied = g(v_fraction)  (or read back from sense)
     *   insulation_mohm = (V_applied / I_leak) / 1e6
     * Until then we expose the raw sense and report TEST_ERROR (cannot judge).
     */
    res->insulation_mohm = 0.0f;
    res->verdict         = TEST_ERROR;   /* unresolved measurement chain */
  }

safe_exit:
  /* Always de-energise, discharge and open relays before returning. */
  insulation_safe(hv);
  return st;
}