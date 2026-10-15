/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    dac8830.c
  * @brief   Driver implementation for the DAC8830 16-bit DAC. See dac8830.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "drivers/dac8830.h"

/**
  * @brief  Write a raw 16-bit code to the DAC8830 output register.
  * @note   The DAC8830 has no command byte: the 16-bit word is the value. The
  *         code is latched on the rising edge of CS at the end of the transfer.
  * @param  dev  : [in] bound driver instance; dev->hspi must be non-NULL.
  * @param  code : [in] 16-bit output code (0x0000 = 0 V, 0xFFFF = full scale).
  * @retval HAL_OK    code transmitted and latched.
  * @retval HAL_ERROR @p dev or dev->hspi is NULL.
  * @retval other     HAL status propagated from HAL_SPI_Transmit().
  */
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

/**
  * @brief  Bind a DAC8830 instance and drive its output to 0 V.
  * @note   Records the handles, parks CS high, then writes code 0 so the part
  *         comes up at a known-safe 0 V rather than an undefined power-on level.
  * @param  dev     : [out] driver instance to populate; must be non-NULL.
  * @param  hspi    : [in]  SPI handle the DAC hangs off; must be non-NULL.
  * @param  cs_port : [in]  GPIO port of the chip-select line; must be non-NULL.
  * @param  cs_pin  : [in]  GPIO pin mask of the chip-select line.
  * @retval HAL_OK    instance bound and output driven to 0 V.
  * @retval HAL_ERROR any of @p dev, @p hspi or @p cs_port is NULL.
  * @retval other     HAL status propagated from the initial DAC8830_WriteCode().
  */
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

/**
  * @brief  Drive the DAC output to a fraction of full scale.
  * @note   @p fraction is clamped to [0.0, 1.0]; values in between are scaled
  *         to a 16-bit code with round-to-nearest and saturated at 0xFFFF.
  * @param  dev      : [in] bound driver instance.
  * @param  fraction : [in] desired output as a fraction of full scale (0..1).
  * @retval HAL status from the underlying DAC8830_WriteCode().
  */
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