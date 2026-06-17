/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    ad7476.c
  * @brief   Driver implementation for the AD7476 SPI SAR ADC. See ad7476.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "drivers/ad7476.h"

HAL_StatusTypeDef AD7476_Init(AD7476_t *dev, SPI_HandleTypeDef *hspi,
                              GPIO_TypeDef *cs_port, uint16_t cs_pin)
{
  if (dev == NULL || hspi == NULL || cs_port == NULL)
  {
    return HAL_ERROR;
  }
  dev->hspi    = hspi;
  dev->cs_port = cs_port;
  dev->cs_pin  = cs_pin;

  /* Park CS high so the device is deselected / not converting. */
  HAL_GPIO_WritePin(dev->cs_port, dev->cs_pin, GPIO_PIN_SET);
  return HAL_OK;
}

HAL_StatusTypeDef AD7476_ReadRaw(AD7476_t *dev, uint16_t *code)
{
  uint16_t rx = 0U;
  HAL_StatusTypeDef st;

  if (dev == NULL || dev->hspi == NULL || code == NULL)
  {
    return HAL_ERROR;
  }

  /* CS low starts the conversion; the 16-clock frame reads the result. */
  HAL_GPIO_WritePin(dev->cs_port, dev->cs_pin, GPIO_PIN_RESET);
  st = HAL_SPI_Receive(dev->hspi, (uint8_t *)&rx, 1U, AD7476_SPI_TIMEOUT);
  HAL_GPIO_WritePin(dev->cs_port, dev->cs_pin, GPIO_PIN_SET);

  if (st == HAL_OK)
  {
    *code = (uint16_t)(rx & AD7476_CODE_MASK);
  }
  return st;
}

float AD7476_CodeToVolts(uint16_t code, float vref)
{
  return ((float)(code & AD7476_CODE_MASK) / AD7476_FULL_SCALE) * vref;
}

HAL_StatusTypeDef AD7476_ReadVolts(AD7476_t *dev, float vref, float *volts)
{
  uint16_t code = 0U;
  HAL_StatusTypeDef st;

  if (volts == NULL)
  {
    return HAL_ERROR;
  }
  st = AD7476_ReadRaw(dev, &code);
  if (st == HAL_OK)
  {
    *volts = AD7476_CodeToVolts(code, vref);
  }
  return st;
}