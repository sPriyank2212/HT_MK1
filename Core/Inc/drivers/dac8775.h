/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    dac8775.h
  * @brief   Driver for the TI DAC8775 quad 16-bit current/voltage-output DAC.
  *
  *          On the Control Card this is the precision Kelvin current source
  *          (IDAC). Channel A's current output (IOUT_A -> I_OUT net) is forced
  *          through the wire under test; the resulting drop is read back by the
  *          instrumentation amp + AD7476.
  *
  *          Transport (confident): 24-bit frames = 8-bit command + 16-bit data,
  *          MSB first. Command bit7 = R/W (0 = write). Sent as 3 bytes over an
  *          8-bit SPI (set SPI2 DataSize = 8-bit).
  *
  *          !! Register ADDRESSES and field encodings below are placeholders to
  *          VERIFY against the DAC8775 datasheet (Rev) before bring-up. The
  *          transport layer is correct regardless; only the constants need
  *          confirming. They are intentionally kept in one block so a single
  *          datasheet pass finalises them.
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __DAC8775_H
#define __DAC8775_H

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"

#ifndef DAC8775_SPI_TIMEOUT
#define DAC8775_SPI_TIMEOUT   50U
#endif

#define DAC8775_WRITE         0x00U   /* command bit7 = 0 */
#define DAC8775_READ          0x80U   /* command bit7 = 1 */

/* ---- VERIFY against datasheet ------------------------------------------- */
/* Register addresses (command byte, low 7 bits). Placeholder values. */
#define DAC8775_REG_NOP       0x00U
#define DAC8775_REG_RESET     0x01U   /* VERIFY */
#define DAC8775_REG_CONFIG    0x02U   /* VERIFY - per-channel config / range */
#define DAC8775_REG_DACDATA   0x03U   /* VERIFY - 16-bit output code          */
#define DAC8775_REG_SELECT    0x04U   /* VERIFY - channel page select         */
/* Output range field (in CONFIG): pick the current range that matches the    */
/* test current spec, e.g. 0-24 mA. VERIFY field encoding.                    */
#define DAC8775_RANGE_0_24MA  0x0000U /* VERIFY */
/* ------------------------------------------------------------------------- */

typedef enum
{
  DAC8775_CH_A = 0,
  DAC8775_CH_B = 1,
  DAC8775_CH_C = 2,
  DAC8775_CH_D = 3
} DAC8775_Channel_t;

typedef struct
{
  SPI_HandleTypeDef *hspi;     /* SPI2 (8-bit) */
  GPIO_TypeDef      *cs_port;
  uint16_t           cs_pin;
} DAC8775_t;

/**
  * @brief  Bind an instance and park CS high. (Does not issue a reset/config -
  *         call DAC8775_ConfigCurrentRange once the register map is confirmed.)
  */
HAL_StatusTypeDef DAC8775_Init(DAC8775_t *dev, SPI_HandleTypeDef *hspi,
                               GPIO_TypeDef *cs_port, uint16_t cs_pin);

/**
  * @brief  Raw 24-bit register write (command byte + 16-bit data). Always valid.
  */
HAL_StatusTypeDef DAC8775_WriteReg(DAC8775_t *dev, uint8_t reg, uint16_t data);

/**
  * @brief  Select a channel page (uses DAC8775_REG_SELECT - VERIFY).
  */
HAL_StatusTypeDef DAC8775_SelectChannel(DAC8775_t *dev, DAC8775_Channel_t ch);

/**
  * @brief  Configure a channel for current output at the chosen range
  *         (VERIFY register/field). Convenience wrapper over WriteReg.
  */
HAL_StatusTypeDef DAC8775_ConfigCurrentRange(DAC8775_t *dev, DAC8775_Channel_t ch,
                                             uint16_t range_field);

/**
  * @brief  Set a channel's 16-bit output code (current proportional to code).
  */
HAL_StatusTypeDef DAC8775_SetCode(DAC8775_t *dev, DAC8775_Channel_t ch, uint16_t code);

#ifdef __cplusplus
}
#endif

#endif /* __DAC8775_H */