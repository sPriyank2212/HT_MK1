/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    ad7476.h
  * @brief   Driver for the Analog Devices AD7476 12-bit SAR ADC (SPI read-only).
  *
  *          Used twice in the system, same driver both times:
  *            - Control Card : on the FREE SPI1 (PA5 SCK / PA6 MISO / soft CS),
  *              digitises the continuity / Kelvin front-end (ADC_IN).
  *            - HV Card      : on the isolated SPI3 bus, digitises HV_Sense.
  *
  *          Conversion model: a falling CS edge starts the conversion and the
  *          16 SCLK cycles clock out the result MSB-first as 4 leading zeros
  *          followed by the 12 data bits. The driver reads one 16-bit frame and
  *          masks the low 12 bits.
  *
  *          SPI requirements (set in CubeMX for the chosen instance):
  *            - DataSize  = 16-bit   (generated default is 4-bit -> MUST change)
  *            - Baud      <= 20 MHz  (AD7476 max SCLK; the 32 MHz default is too
  *                                    fast -> drop one prescaler notch)
  *            - Direction = RX-only (or 2-line full duplex; MOSI is unused)
  *            - CPOL/CPHA : sample MISO so the 16-clock frame lands correctly;
  *                          confirm against the AD7476 datasheet on bring-up.
  *            - NSS       = software (CS driven as a GPIO by this driver)
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __AD7476_H
#define __AD7476_H

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"

#ifndef AD7476_SPI_TIMEOUT
#define AD7476_SPI_TIMEOUT   50U
#endif

/* 12-bit full scale. */
#define AD7476_FULL_SCALE    4096.0f
#define AD7476_CODE_MASK     0x0FFFU

typedef struct
{
  SPI_HandleTypeDef *hspi;       /* SPI bus (SPI1 on Control Card)            */
  GPIO_TypeDef      *cs_port;    /* chip-select GPIO port                    */
  uint16_t           cs_pin;     /* chip-select GPIO pin                     */
  uint16_t           last_raw;   /* CL-108: whole 16-bit frame of the last read.
                                  * A real AD7476 frame starts with 4 zero bits;
                                  * 0xFFFF = MISO high / ADC not driving.      */
} AD7476_t;

/* Leading-zero bits of a valid frame (diagnostic check only). */
#define AD7476_LEAD_MASK     0xF000U

/**
  * @brief  Bind an instance and park CS high (idle).
  */
HAL_StatusTypeDef AD7476_Init(AD7476_t *dev, SPI_HandleTypeDef *hspi,
                              GPIO_TypeDef *cs_port, uint16_t cs_pin);

/**
  * @brief  Perform one acquisition and return the raw 12-bit code (0..4095).
  */
HAL_StatusTypeDef AD7476_ReadRaw(AD7476_t *dev, uint16_t *code);
/* CL-112: one dummy conversion, result discarded. AD7476 datasheet: the part
 * may come up in power-down, and the first conversion after power-up is not
 * valid. Call once after AD7476_Init(), before the first real reading. */
HAL_StatusTypeDef AD7476_WakeUp(AD7476_t *dev);

/**
  * @brief  Convert a raw code to volts for a given reference voltage.
  */
float AD7476_CodeToVolts(uint16_t code, float vref);

/**
  * @brief  Acquire and convert to volts in one call.
  */
HAL_StatusTypeDef AD7476_ReadVolts(AD7476_t *dev, float vref, float *volts);

#ifdef __cplusplus
}
#endif

#endif /* __AD7476_H */