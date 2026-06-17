/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    dac8775.c
  * @brief   Driver implementation for the DAC8775 IDAC. See dac8775.h.
  *          NOTE: register constants are placeholders to verify; the 24-bit
  *          transport is correct.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "drivers/dac8775.h"

HAL_StatusTypeDef DAC8775_WriteReg(DAC8775_t *dev, uint8_t reg, uint16_t data)
{
  uint8_t frame[3];
  HAL_StatusTypeDef st;

  if (dev == NULL || dev->hspi == NULL)
  {
    return HAL_ERROR;
  }

  frame[0] = (uint8_t)(DAC8775_WRITE | (reg & 0x7FU));
  frame[1] = (uint8_t)(data >> 8);
  frame[2] = (uint8_t)(data & 0xFFU);

  HAL_GPIO_WritePin(dev->cs_port, dev->cs_pin, GPIO_PIN_RESET);
  st = HAL_SPI_Transmit(dev->hspi, frame, 3U, DAC8775_SPI_TIMEOUT);
  HAL_GPIO_WritePin(dev->cs_port, dev->cs_pin, GPIO_PIN_SET);

  return st;
}

HAL_StatusTypeDef DAC8775_Init(DAC8775_t *dev, SPI_HandleTypeDef *hspi,
                               GPIO_TypeDef *cs_port, uint16_t cs_pin)
{
  if (dev == NULL || hspi == NULL || cs_port == NULL)
  {
    return HAL_ERROR;
  }
  dev->hspi    = hspi;
  dev->cs_port = cs_port;
  dev->cs_pin  = cs_pin;

  HAL_GPIO_WritePin(dev->cs_port, dev->cs_pin, GPIO_PIN_SET);
  return HAL_OK;
}

HAL_StatusTypeDef DAC8775_SelectChannel(DAC8775_t *dev, DAC8775_Channel_t ch)
{
  return DAC8775_WriteReg(dev, DAC8775_REG_SELECT, (uint16_t)ch);
}

HAL_StatusTypeDef DAC8775_ConfigCurrentRange(DAC8775_t *dev, DAC8775_Channel_t ch,
                                             uint16_t range_field)
{
  HAL_StatusTypeDef st = DAC8775_SelectChannel(dev, ch);
  if (st != HAL_OK)
  {
    return st;
  }
  return DAC8775_WriteReg(dev, DAC8775_REG_CONFIG, range_field);
}

HAL_StatusTypeDef DAC8775_SetCode(DAC8775_t *dev, DAC8775_Channel_t ch, uint16_t code)
{
  HAL_StatusTypeDef st = DAC8775_SelectChannel(dev, ch);
  if (st != HAL_OK)
  {
    return st;
  }
  return DAC8775_WriteReg(dev, DAC8775_REG_DACDATA, code);
}