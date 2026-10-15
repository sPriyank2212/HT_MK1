/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    ds18b20.h
  * @brief   Bit-banged 1-Wire driver for the Maxim/Dallas DS18B20U+T&R digital
  *          temperature sensor.
  *
  *          NEW HARDWARE (HW-13, 2026-08-16): U2 on the Control Card `uC`
  *          sheet, wired to PA0 (net `1_Wire`) with R2 (4.7 k pull-up) and R3
  *          (47 R series on DQ) - see PROJECT_LOG.md HW-13/FW-14.
  *
  *          Single device, no ROM search: the schematic shows exactly one
  *          DS18B20 on this net, so every transaction uses SKIP ROM (0xCC)
  *          instead of implementing the 1-Wire search algorithm.
  *
  *          Bus timing follows the standard (non-overdrive) 1-Wire slot times
  *          (Maxim AN126), timed with a DWT-cycle-counter microsecond delay
  *          (HCLK = 64 MHz - see main.c's SystemClock_Config) rather than a
  *          NOP-loop guess.
  *
  * @note    VERIFY at bring-up (no hardware to test bit-banged timing against
  *          yet - same caveat this project already carries for ads1232.c):
  *            - Assumes the sensor is externally (VDD-)powered, not
  *              parasite-powered off DQ: DS18B20_ReadTemperature() waits a
  *              fixed worst-case 750 ms after CONVERT T rather than polling a
  *              busy bit, which needs a strong parasitic pull-up during
  *              conversion that is not confirmed present here.
  *            - Open-drain PA0 through R3 (47R series) to DQ, R2 (4.7k) as
  *              the only pull-up - not bench-confirmed against real timing.
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __DS18B20_H
#define __DS18B20_H

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"

typedef struct
{
  GPIO_TypeDef *port;
  uint16_t      pin;
} DS18B20_t;

/**
  * @brief  Bind the driver to an already-configured open-drain GPIO.
  * @note   Does not touch RCC or GPIO mode - the caller (board.c for the
  *         product binding) configures the pin GPIO_MODE_OUTPUT_OD before
  *         calling this, the same division of responsibility board.c already
  *         uses for every other card/driver binding.
  * @param  dev  : [out] instance to populate; must be non-NULL.
  * @param  port : [in]  GPIO port, already configured open-drain output.
  * @param  pin  : [in]  GPIO pin.
  * @retval HAL_OK on success, HAL_ERROR if @p dev or @p port is NULL.
  */
HAL_StatusTypeDef DS18B20_Init(DS18B20_t *dev, GPIO_TypeDef *port, uint16_t pin);

/**
  * @brief  Reset, start a conversion, wait for it, and read the result.
  * @note   Blocking for a little over 750 ms (12-bit default resolution's
  *         worst-case conversion time) - matches ads124s08.c's own
  *         driver-layer convention of a plain HAL_Delay() for a conversion
  *         period (as opposed to the test-layer settle delays, which go
  *         through Board_SettleMs() instead - see board.h). Call this from
  *         the sequencer task (tasks.c), not from tComms, so a `>TEMP READ`
  *         command does not stall the protocol parser for most of a second.
  *         Validates the scratchpad's CRC8 before trusting the reading.
  * @param  dev     : [in]  instance; must be non-NULL and DS18B20_Init()ed.
  * @param  celsius : [out] temperature; must be non-NULL.
  * @retval HAL_OK      reading valid (CRC checked).
  * @retval HAL_TIMEOUT no presence pulse on either reset (sensor missing or
  *                     unpowered).
  * @retval HAL_ERROR   bad argument, or scratchpad CRC mismatch.
  */
HAL_StatusTypeDef DS18B20_ReadTemperature(DS18B20_t *dev, float *celsius);

#ifdef __cplusplus
}
#endif

#endif /* __DS18B20_H */
