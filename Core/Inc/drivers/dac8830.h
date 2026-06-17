/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    dac8830.h
  * @brief   Driver for the TI DAC8830 16-bit unbuffered voltage-output DAC.
  *
  *          On each HV Card the DAC8830 sets the HV DC-DC programming voltage
  *          (V_PGM, buffered by an OPA376) within the isolated domain, over the
  *          isolated SPI3 bus. Output is monotonic 16-bit:
  *              Vout = (code / 65536) * Vref
  *          and that V_PGM maps (via the CA05P-5 converter gain) to the 0..500 V
  *          HV rail - so the volts->code mapping for "set 350 V" lives one layer
  *          up (hv_card), not here.
  *
  *          Transport: a single 16-bit frame, MSB first, latched on CS rising.
  *          SPI requirements: DataSize = 16-bit, master. Confirm CPOL/CPHA per
  *          the DAC8830 datasheet (data clocked on SCLK falling edge).
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __DAC8830_H
#define __DAC8830_H

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"

#ifndef DAC8830_SPI_TIMEOUT
#define DAC8830_SPI_TIMEOUT   50U
#endif

#define DAC8830_FULL_SCALE    65536.0f

typedef struct
{
  SPI_HandleTypeDef *hspi;     /* isolated SPI bus              */
  GPIO_TypeDef      *cs_port;  /* chip-select GPIO port         */
  uint16_t           cs_pin;   /* chip-select GPIO pin          */
} DAC8830_t;

/**
  * @brief  Bind an instance, park CS high, and zero the output.
  */
HAL_StatusTypeDef DAC8830_Init(DAC8830_t *dev, SPI_HandleTypeDef *hspi,
                               GPIO_TypeDef *cs_port, uint16_t cs_pin);

/**
  * @brief  Write the raw 16-bit DAC code.
  */
HAL_StatusTypeDef DAC8830_WriteCode(DAC8830_t *dev, uint16_t code);

/**
  * @brief  Write the output as a fraction (0.0..1.0) of full scale.
  */
HAL_StatusTypeDef DAC8830_WriteFraction(DAC8830_t *dev, float fraction);

#ifdef __cplusplus
}
#endif

#endif /* __DAC8830_H */