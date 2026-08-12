/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    kelvin.c
  * @brief   Kelvin impedance measurement implementation. See kelvin.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "test/kelvin.h"

#define KELVIN_FULLSCALE_CODE  8388608.0f   /* 2^23 */

/* PGA gain sequence for auto-ranging, highest first. Most harness wires are a
 * fraction of an ohm, so starting high gives the best resolution on the
 * common case; a genuinely large R (near-open fault) falls through to a lower
 * gain instead of saturating the conversion. */
static const ADS124S08_Gain_t kelvin_gain_seq[] = {
  ADS124S08_GAIN_128, ADS124S08_GAIN_64, ADS124S08_GAIN_32, ADS124S08_GAIN_16,
  ADS124S08_GAIN_8,   ADS124S08_GAIN_4,  ADS124S08_GAIN_2,  ADS124S08_GAIN_1
};
#define KELVIN_GAIN_STEPS  (sizeof(kelvin_gain_seq) / sizeof(kelvin_gain_seq[0]))

/**
  * @brief  Convert at each gain in kelvin_gain_seq, stopping at the first that
  *         does not saturate.
  * @param  code : [out] the accepted conversion.
  * @retval HAL_OK on success, HAL_ERROR if every gain (including unity)
  *         saturates, else the first failing status from the ADC driver.
  */
static HAL_StatusTypeDef kelvin_ranged_read(int32_t *code)
{
  HAL_StatusTypeDef st;
  int32_t limit = (int32_t)(KELVIN_FULLSCALE_CODE * KELVIN_SATURATION_FRACTION);
  uint8_t i;

  for (i = 0U; i < KELVIN_GAIN_STEPS; i++)
  {
    st = ADS124S08_SetGain(&g_ads124s08, kelvin_gain_seq[i]);
    if (st != HAL_OK)
    {
      return st;
    }
    st = ADS124S08_ConvertOnce(&g_ads124s08, code);
    if (st != HAL_OK)
    {
      return st;
    }
    if (*code > -limit && *code < limit)
    {
      return HAL_OK;
    }
  }
  /* Saturated even at unity gain: open circuit or a gross fault, not a
   * measurable resistance. */
  return HAL_ERROR;
}

/**
  * @brief  Measure the 4-wire (Kelvin) resistance of one harness pair.
  * @note   Sequence: pair the sense array with the force array, route the
  *         pins, switch the front end to impedance mode (isolates the
  *         Control-Card continuity divider's 10 k pull-up from HI_COM - it
  *         would otherwise steal a chunk of the 2 mA excitation), then
  *         route the ADS124S08's own IDAC1 onto AIN9 (= HI_COM) at
  *         KELVIN_IDAC_MAG and read HI_SENSE - LO_SENSE on the same chip with
  *         the PGA auto-ranged to the highest gain that does not saturate.
  *         A second conversion at the same gain with the excitation off gives
  *         a system-offset baseline (mux charge injection, lead offset - not
  *         just the ADC's own offset, which ADS124S08_SelfOffsetCal cancels
  *         once at board init); the two codes are subtracted before
  *         converting to ohms. The front end and matrix are always released
  *         before returning, even on error. FW-12: the excitation current
  *         source used to be the Control-Card DAC8775; that chip is gone from
  *         the schematic and the IDAC inside the ADS124S08 itself does this
  *         now - see Doc/idac_current_source.md.
  * @param  hi_pin : [in]  1-based HI-side harness pin.
  * @param  lo_pin : [in]  1-based LO-side harness pin.
  * @param  res    : [out] result (code, volts, resistance, verdict). On any
  *                       early error the verdict is left TEST_ERROR. Must be non-NULL.
  * @retval HAL_OK    measurement completed (inspect res->verdict for pass/fail).
  * @retval HAL_ERROR @p res is NULL, or every PGA gain saturated.
  * @retval other     first failing HAL status from routing/front-end/ADC access.
  */
HAL_StatusTypeDef Kelvin_MeasurePair(uint16_t hi_pin, uint16_t lo_pin,
                                     KelvinResult_t *res)
{
  HAL_StatusTypeDef st;
  int32_t code_excited, code_zero;

  if (res == NULL)
  {
    return HAL_ERROR;
  }
  res->code           = 0;
  res->volts          = 0.0f;
  res->resistance_ohm = 0.0f;
  res->verdict        = TEST_ERROR;

  st = MatrixCard_SetSensePaired(&g_matrix, 1U);
  if (st != HAL_OK)
  {
    return st;
  }

  /* Route the wire, switch the front end to impedance mode (isolates the
   * continuity divider from HI_COM - see the function note above). */
  st = MatrixCard_ConnectPair(&g_matrix, hi_pin, lo_pin);
  if (st != HAL_OK)
  {
    goto release;
  }
  st = Frontend_SetMode(&g_frontend, FRONTEND_MODE_IMPEDANCE);
  if (st != HAL_OK)
  {
    goto release;
  }

  st = ADS124S08_SetIdac(&g_ads124s08, ADS124S08_MUX_AIN9, ADS124S08_IDAC_OFF,
                         KELVIN_IDAC_MAG);
  if (st != HAL_OK)
  {
    goto release;
  }
  Board_SettleMs(KELVIN_SETTLE_MS);
  st = kelvin_ranged_read(&code_excited);
  if (st != HAL_OK)
  {
    goto release;
  }

  /* Same gain, no excitation: the system-offset baseline. */
  st = ADS124S08_SetIdac(&g_ads124s08, ADS124S08_IDAC_OFF, ADS124S08_IDAC_OFF,
                         ADS124S08_IMAG_OFF);
  if (st != HAL_OK)
  {
    goto release;
  }
  Board_SettleMs(KELVIN_SETTLE_MS);
  st = ADS124S08_ConvertOnce(&g_ads124s08, &code_zero);
  if (st != HAL_OK)
  {
    goto release;
  }

  res->code           = code_excited - code_zero;
  res->volts          = ADS124S08_CodeToVolts(&g_ads124s08, res->code);
  res->resistance_ohm = ADS124S08_OhmsFromCurrent(&g_ads124s08, res->code,
                                                   KELVIN_FORCE_CURRENT_A);
  res->verdict        = (res->resistance_ohm <= KELVIN_R_MAX_OHM) ? TEST_PASS
                                                                   : TEST_FAIL;

release:
  /* Stop forcing current and open the matrix. */
  (void)ADS124S08_SetIdac(&g_ads124s08, ADS124S08_IDAC_OFF, ADS124S08_IDAC_OFF,
                          ADS124S08_IMAG_OFF);
  (void)Frontend_SetMode(&g_frontend, FRONTEND_MODE_CONTINUITY);
  (void)MatrixCard_AllOff(&g_matrix);
  return st;
}
