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

/**
  * @brief  Write one 16-bit register over the 24-bit DAC8775 SPI frame.
  * @note   Frame layout is [ WRITE | reg(7) ][ data_hi ][ data_lo ]. CS is
  *         asserted low for the whole 3-byte transfer and released afterwards.
  * @param  dev  : [in] bound driver instance; dev->hspi must be non-NULL.
  * @param  reg  : [in] target register address (low 7 bits are used).
  * @param  data : [in] 16-bit payload to write, MSB first.
  * @retval HAL_OK    frame transmitted.
  * @retval HAL_ERROR @p dev or dev->hspi is NULL.
  * @retval other     HAL status propagated from HAL_SPI_Transmit().
  */
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

/**
  * @brief  Bind a DAC8775 instance to its SPI bus and chip-select line.
  * @note   Records the handles and parks CS high (device deselected). No
  *         register configuration is performed here.
  * @param  dev     : [out] driver instance to populate; must be non-NULL.
  * @param  hspi    : [in]  SPI handle the DAC hangs off; must be non-NULL.
  * @param  cs_port : [in]  GPIO port of the chip-select line; must be non-NULL.
  * @param  cs_pin  : [in]  GPIO pin mask of the chip-select line.
  * @retval HAL_OK    instance bound and CS parked high.
  * @retval HAL_ERROR any of @p dev, @p hspi or @p cs_port is NULL.
  */
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

/**
  * @brief  Point the device's shared register file at one output channel.
  * @note   Subsequent CONFIG/DACDATA writes apply to the selected channel.
  * @param  dev : [in] bound driver instance.
  * @param  ch  : [in] channel to select (DAC8775_Channel_t).
  * @retval HAL status from the underlying DAC8775_WriteReg().
  */
HAL_StatusTypeDef DAC8775_SelectChannel(DAC8775_t *dev, DAC8775_Channel_t ch)
{
  return DAC8775_WriteReg(dev, DAC8775_REG_SELECT, (uint16_t)ch);
}

/**
  * @brief  Select a channel and program its output current range.
  * @note   Two writes: SELECT (channel) then CONFIG (range field). Aborts on
  *         the first failing transfer.
  * @param  dev         : [in] bound driver instance.
  * @param  ch          : [in] channel to configure.
  * @param  range_field : [in] raw CONFIG-register range bits for the channel.
  * @retval HAL_OK    channel selected and range programmed.
  * @retval other     first failing HAL status from the two register writes.
  */
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

/**
  * @brief  Load a channel's DAC data register with a raw output code.
  * @note   Two writes: SELECT (channel) then DACDATA (code). Aborts on the
  *         first failing transfer.
  * @param  dev  : [in] bound driver instance.
  * @param  ch   : [in] channel to drive.
  * @param  code : [in] raw output code to load into DACDATA.
  * @retval HAL_OK    channel selected and code loaded.
  * @retval other     first failing HAL status from the two register writes.
  */
HAL_StatusTypeDef DAC8775_SetCode(DAC8775_t *dev, DAC8775_Channel_t ch, uint16_t code)
{
  HAL_StatusTypeDef st = DAC8775_SelectChannel(dev, ch);
  if (st != HAL_OK)
  {
    return st;
  }
  return DAC8775_WriteReg(dev, DAC8775_REG_DACDATA, code);
}