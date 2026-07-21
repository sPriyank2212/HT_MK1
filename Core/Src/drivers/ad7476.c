/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    ad7476.c
  * @brief   Driver implementation for the AD7476 SPI SAR ADC. See ad7476.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "drivers/ad7476.h"

/**
  * @brief  Bind an AD7476 instance to its SPI bus and chip-select line.
  * @note   Does not perform any bus traffic; it only records the handles and
  *         parks CS high so the device is deselected (not converting).
  * @param  dev     : [out] driver instance to populate; must be non-NULL.
  * @param  hspi    : [in]  SPI handle the ADC hangs off; must be non-NULL.
  * @param  cs_port : [in]  GPIO port of the chip-select line; must be non-NULL.
  * @param  cs_pin  : [in]  GPIO pin mask of the chip-select line.
  * @retval HAL_OK    instance bound and CS parked high.
  * @retval HAL_ERROR any of @p dev, @p hspi or @p cs_port is NULL.
  */
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

/**
  * @brief  Trigger one conversion and return the raw ADC code.
  * @note   Pulling CS low starts the conversion; a single 16-clock SPI frame
  *         clocks the result out. The leading status/leading-zero bits are
  *         masked off with AD7476_CODE_MASK to leave the 12-bit sample.
  * @param  dev  : [in]  bound driver instance; dev->hspi must be non-NULL.
  * @param  code : [out] destination for the masked raw code.
  * @retval HAL_OK    conversion clocked out into @p code.
  * @retval HAL_ERROR @p dev, dev->hspi or @p code is NULL.
  * @retval other     HAL status propagated from HAL_SPI_Receive().
  */
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

/**
  * @brief  Convert a raw ADC code to volts for a given reference.
  * @note   Pure helper (no device access): volts = (code / full_scale) * vref.
  * @param  code : [in] raw code; masked with AD7476_CODE_MASK before scaling.
  * @param  vref : [in] ADC reference voltage, in volts.
  * @retval float the input node voltage, in volts.
  */
float AD7476_CodeToVolts(uint16_t code, float vref)
{
  return ((float)(code & AD7476_CODE_MASK) / AD7476_FULL_SCALE) * vref;
}

/**
  * @brief  Read one conversion and return it already scaled to volts.
  * @note   Convenience wrapper around AD7476_ReadRaw() + AD7476_CodeToVolts().
  * @param  dev   : [in]  bound driver instance.
  * @param  vref  : [in]  ADC reference voltage, in volts.
  * @param  volts : [out] destination for the node voltage, in volts.
  * @retval HAL_OK    voltage read into @p volts.
  * @retval HAL_ERROR @p volts is NULL (or @p dev invalid via AD7476_ReadRaw()).
  * @retval other     HAL status propagated from AD7476_ReadRaw().
  */
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