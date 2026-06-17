/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    dac8830.c
  * @brief   Driver implementation for the DAC8830 16-bit DAC. See dac8830.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "drivers/dac8830.h"

HAL_StatusTypeDef DAC8830_WriteCode(DAC8830_t *dev, uint16_t code)
{
  uint16_t tx = code;
  HAL_StatusTypeDef st;

  if (dev == NULL || dev->hspi == NULL)
  {
    return HAL_ERROR;
  }

  HAL_GPIO_WritePin(dev->cs_port, dev->cs_pin, GPIO_PIN_RESET);
  st = HAL_SPI_Transmit(dev->hspi, (uint8_t *)&tx, 1U, DAC8830_SPI_TIMEOUT);
  HAL_GPIO_WritePin(dev->cs_port, dev->cs_pin, GPIO_PIN_SET);  /* latch on rise */

  return st;
}

HAL_StatusTypeDef DAC8830_Init(DAC8830_t *dev, SPI_HandleTypeDef *hspi,
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
  return DAC8830_WriteCode(dev, 0U);   /* start at 0 V */
}

HAL_StatusTypeDef DAC8830_WriteFraction(DAC8830_t *dev, float fraction)
{
  uint32_t code;

  if (fraction <= 0.0f)
  {
    code = 0U;
  }
  else if (fraction >= 1.0f)
  {
    code = 0xFFFFU;
  }
  else
  {
    code = (uint32_t)(fraction * DAC8830_FULL_SCALE + 0.5f);
    if (code > 0xFFFFU)
    {
      code = 0xFFFFU;
    }
  }
  return DAC8830_WriteCode(dev, (uint16_t)code);
}