/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    control_frontend.c
  * @brief   Control-Card analogue front-end implementation. See header.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "cards/control_frontend.h"

/**
  * @brief  Initialise the Control-Card front end and its underlying devices.
  * @note   Brings up the DAC8775 IDAC and AD7476 ADC, caches the OPT0_CNTR
  *         GPIO and ADC reference from @p cfg, then leaves the front end in
  *         continuity mode (no forced current).
  * @param  fe  : [out] front-end instance to populate; must be non-NULL.
  * @param  cfg : [in]  static configuration (SPI handles, CS/OPT0 GPIOs,
  *                     vref); must be non-NULL.
  * @retval HAL_OK    front end initialised and set to continuity mode.
  * @retval HAL_ERROR @p fe or @p cfg is NULL.
  * @retval other     first failing HAL status from IDAC/ADC bring-up or
  *                   Frontend_SetMode().
  */
HAL_StatusTypeDef Frontend_Init(ControlFrontend_t *fe, const ControlFrontendCfg_t *cfg)
{
  HAL_StatusTypeDef st;

  if (fe == NULL || cfg == NULL)
  {
    return HAL_ERROR;
  }

  fe->opto_port = cfg->opto_port;
  fe->opto_pin  = cfg->opto_pin;
  fe->vref      = cfg->vref;

  st = DAC8775_Init(&fe->idac, cfg->idac_spi, cfg->idac_cs_port, cfg->idac_cs_pin);
  if (st != HAL_OK)
  {
    return st;
  }
  st = AD7476_Init(&fe->adc, cfg->adc_spi, cfg->adc_cs_port, cfg->adc_cs_pin);
  if (st != HAL_OK)
  {
    return st;
  }

  /* Default to continuity mode (no forced current) at start-up. */
  return Frontend_SetMode(fe, FRONTEND_MODE_CONTINUITY);
}

/**
  * @brief  Select the front-end signal path by driving OPT0_CNTR.
  * @note   Drives the TS5A3159 SPDT throw: FRONTEND_MODE_IMPEDANCE routes the
  *         IDAC current source to the wire under test, FRONTEND_MODE_CONTINUITY
  *         routes the +3V3 divider. The cached fe->mode is updated on success.
  * @param  fe   : [in,out] front-end instance; fe->opto_port must be a valid
  *                        GPIO OUTPUT.
  * @param  mode : [in]     desired signal path (FrontendMode_t).
  * @retval HAL_OK    OPT0_CNTR driven and mode cached.
  * @retval HAL_ERROR @p fe is NULL or fe->opto_port is NULL.
  */
HAL_StatusTypeDef Frontend_SetMode(ControlFrontend_t *fe, FrontendMode_t mode)
{
  GPIO_PinState level;

  if (fe == NULL || fe->opto_port == NULL)
  {
    return HAL_ERROR;
  }

  level = (mode == FRONTEND_MODE_IMPEDANCE) ? FRONTEND_OPTO_LEVEL_IMPEDANCE
                                            : FRONTEND_OPTO_LEVEL_CONTINUITY;
  HAL_GPIO_WritePin(fe->opto_port, fe->opto_pin, level);
  fe->mode = mode;
  return HAL_OK;
}

/**
  * @brief  Program the Kelvin force current via the IDAC (channel A).
  * @note   Writes the raw DAC8775 code on DAC8775_CH_A; only meaningful while
  *         the front end is in FRONTEND_MODE_IMPEDANCE.
  * @param  fe   : [in] front-end instance; must be non-NULL.
  * @param  code : [in] raw IDAC output code to load.
  * @retval HAL_OK    code accepted by the IDAC.
  * @retval HAL_ERROR @p fe is NULL.
  * @retval other     HAL status propagated from DAC8775_SetCode().
  */
HAL_StatusTypeDef Frontend_SetCurrentCode(ControlFrontend_t *fe, uint16_t code)
{
  if (fe == NULL)
  {
    return HAL_ERROR;
  }
  return DAC8775_SetCode(&fe->idac, DAC8775_CH_A, code);
}

/**
  * @brief  Sample the front-end node voltage as a raw ADC code.
  * @param  fe   : [in]  front-end instance; must be non-NULL.
  * @param  code : [out] destination for the raw 12-bit AD7476 code.
  * @retval HAL_OK    conversion read into @p code.
  * @retval HAL_ERROR @p fe is NULL.
  * @retval other     HAL status propagated from AD7476_ReadRaw().
  */
HAL_StatusTypeDef Frontend_ReadRaw(ControlFrontend_t *fe, uint16_t *code)
{
  if (fe == NULL)
  {
    return HAL_ERROR;
  }
  return AD7476_ReadRaw(&fe->adc, code);
}

/**
  * @brief  Sample the front-end node voltage and scale it to volts.
  * @note   Converts the raw AD7476 code using the cached fe->vref reference.
  * @param  fe    : [in]  front-end instance; must be non-NULL.
  * @param  volts : [out] destination for the node voltage, in volts.
  * @retval HAL_OK    voltage read into @p volts.
  * @retval HAL_ERROR @p fe is NULL.
  * @retval other     HAL status propagated from AD7476_ReadVolts().
  */
HAL_StatusTypeDef Frontend_ReadVolts(ControlFrontend_t *fe, float *volts)
{
  if (fe == NULL)
  {
    return HAL_ERROR;
  }
  return AD7476_ReadVolts(&fe->adc, fe->vref, volts);
}