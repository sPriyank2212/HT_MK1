/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    hv_card.c
  * @brief   HV Card control implementation. See hv_card.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "cards/hv_card.h"

/* pin 1..64 -> expander index 0..3 and bit 0..15. Linear; VERIFY routing. */
static void hv_map(uint8_t pin, uint8_t *exp, uint8_t *bit)
{
  uint8_t idx = (uint8_t)(pin - 1U);     /* 0..63 */
  *exp = (uint8_t)(idx >> 4);            /* 0..3  */
  *bit = (uint8_t)(idx & 0x0FU);         /* 0..15 */
}

/* Open all relays on one side (array of 4 expanders). */
static HAL_StatusTypeDef hv_side_open(MCP23017_t side[HV_MCP_PER_SIDE])
{
  uint8_t i;
  HAL_StatusTypeDef st;
  for (i = 0U; i < HV_MCP_PER_SIDE; i++)
  {
    st = MCP23017_WritePins(&side[i], 0x0000U);
    if (st != HAL_OK)
    {
      return st;
    }
  }
  return HAL_OK;
}

/* Close exactly one relay on one side (break-before-make). */
static HAL_StatusTypeDef hv_side_close_one(MCP23017_t side[HV_MCP_PER_SIDE], uint8_t pin)
{
  uint8_t exp, bit;
  HAL_StatusTypeDef st;

  if (pin < 1U || pin > HV_PINS_PER_SIDE)
  {
    return HAL_ERROR;
  }
  hv_map(pin, &exp, &bit);

  st = hv_side_open(side);
  if (st != HAL_OK)
  {
    return st;
  }
  return MCP23017_WritePins(&side[exp], (uint16_t)(1U << bit));
}

HAL_StatusTypeDef HvCard_OpenAllRelays(HvCard_t *hv)
{
  HAL_StatusTypeDef st;
  if (hv == NULL)
  {
    return HAL_ERROR;
  }
  st = hv_side_open(hv->inject);
  if (st != HAL_OK)
  {
    return st;
  }
  return hv_side_open(hv->ret);
}

HAL_StatusTypeDef HvCard_Init(HvCard_t *hv, const HvCardCfg_t *cfg)
{
  HAL_StatusTypeDef st;
  uint8_t i;

  if (hv == NULL || cfg == NULL)
  {
    return HAL_ERROR;
  }
  hv->cfg = *cfg;

  for (i = 0U; i < HV_MCP_PER_SIDE; i++)
  {
    st = MCP23017_Init(&hv->inject[i], cfg->i2c, cfg->inject_strap[i]);
    if (st != HAL_OK)
    {
      return st;
    }
    st = MCP23017_Init(&hv->ret[i], cfg->i2c, cfg->return_strap[i]);
    if (st != HAL_OK)
    {
      return st;
    }
  }

  st = DAC8830_Init(&hv->dac, cfg->spi, cfg->dac_cs_port, cfg->dac_cs_pin);
  if (st != HAL_OK)
  {
    return st;
  }
  st = AD7476_Init(&hv->adc, cfg->spi, cfg->adc_cs_port, cfg->adc_cs_pin);
  if (st != HAL_OK)
  {
    return st;
  }

  /* Safe state: HV off, not actively discharging, all relays open, 0 V set. */
  (void)HvCard_HvEnable(hv, 0U);
  (void)HvCard_Discharge(hv, 0U);
  return HvCard_OpenAllRelays(hv);
}

HAL_StatusTypeDef HvCard_CloseInject(HvCard_t *hv, uint8_t pin)
{
  return (hv == NULL) ? HAL_ERROR : hv_side_close_one(hv->inject, pin);
}

HAL_StatusTypeDef HvCard_CloseReturn(HvCard_t *hv, uint8_t pin)
{
  return (hv == NULL) ? HAL_ERROR : hv_side_close_one(hv->ret, pin);
}

HAL_StatusTypeDef HvCard_ConnectPair(HvCard_t *hv, uint8_t inject_pin, uint8_t return_pin)
{
  HAL_StatusTypeDef st = HvCard_CloseInject(hv, inject_pin);
  if (st != HAL_OK)
  {
    return st;
  }
  return HvCard_CloseReturn(hv, return_pin);
}

HAL_StatusTypeDef HvCard_SetVoltageCode(HvCard_t *hv, uint16_t code)
{
  return (hv == NULL) ? HAL_ERROR : DAC8830_WriteCode(&hv->dac, code);
}

HAL_StatusTypeDef HvCard_SetVoltageFraction(HvCard_t *hv, float fraction)
{
  return (hv == NULL) ? HAL_ERROR : DAC8830_WriteFraction(&hv->dac, fraction);
}

HAL_StatusTypeDef HvCard_HvEnable(HvCard_t *hv, uint8_t on)
{
  if (hv == NULL || hv->cfg.hv_en_port == NULL)
  {
    return HAL_ERROR;
  }
  HAL_GPIO_WritePin(hv->cfg.hv_en_port, hv->cfg.hv_en_pin,
                    on ? HV_ENABLE_ACTIVE : (GPIO_PinState)!HV_ENABLE_ACTIVE);
  return HAL_OK;
}

HAL_StatusTypeDef HvCard_Discharge(HvCard_t *hv, uint8_t on)
{
  if (hv == NULL || hv->cfg.dischg_port == NULL)
  {
    return HAL_ERROR;
  }
  HAL_GPIO_WritePin(hv->cfg.dischg_port, hv->cfg.dischg_pin,
                    on ? HV_DISCHARGE_ACTIVE : (GPIO_PinState)!HV_DISCHARGE_ACTIVE);
  return HAL_OK;
}

HAL_StatusTypeDef HvCard_ReadSenseRaw(HvCard_t *hv, uint16_t *code)
{
  return (hv == NULL) ? HAL_ERROR : AD7476_ReadRaw(&hv->adc, code);
}

HAL_StatusTypeDef HvCard_ReadSenseVolts(HvCard_t *hv, float *volts)
{
  return (hv == NULL) ? HAL_ERROR : AD7476_ReadVolts(&hv->adc, hv->cfg.vref, volts);
}