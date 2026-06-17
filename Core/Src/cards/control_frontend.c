/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    control_frontend.c
  * @brief   Control-Card analogue front-end implementation. See header.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "cards/control_frontend.h"

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

HAL_StatusTypeDef Frontend_SetCurrentCode(ControlFrontend_t *fe, uint16_t code)
{
  if (fe == NULL)
  {
    return HAL_ERROR;
  }
  return DAC8775_SetCode(&fe->idac, DAC8775_CH_A, code);
}

HAL_StatusTypeDef Frontend_ReadRaw(ControlFrontend_t *fe, uint16_t *code)
{
  if (fe == NULL)
  {
    return HAL_ERROR;
  }
  return AD7476_ReadRaw(&fe->adc, code);
}

HAL_StatusTypeDef Frontend_ReadVolts(ControlFrontend_t *fe, float *volts)
{
  if (fe == NULL)
  {
    return HAL_ERROR;
  }
  return AD7476_ReadVolts(&fe->adc, fe->vref, volts);
}