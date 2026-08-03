/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    ads124s08.h
  * @brief   Driver for the TI ADS124S08 24-bit delta-sigma ADC (SBAS660C).
  *
  *          Matrix Card U68. Reads AIN0 (HI_SENSE) - AIN1 (LO_SENSE)
  *          differentially: the 4-wire Kelvin measurement. AINCOM is tied to
  *          GND through jumper JP1; REFP0/REFN0 are no-connect, so the internal
  *          2.5 V reference is used.
  *
  *          THE CONTROL LINES ARE NOT GPIO. CS, RESET and START/SYNC are driven
  *          by MCP23017 U69 over I2C, and DRDY is an expander INPUT. That has
  *          three consequences the API is shaped around:
  *
  *            - every SPI transaction costs two I2C writes (assert CS, release
  *              CS) on top of the SPI itself
  *            - DRDY cannot raise an interrupt, and polling it costs a bus
  *              round-trip each time, so conversions are timed from the
  *              configured data rate and DRDY is only a sanity check
  *            - the driver takes an io vtable rather than port/pin, so it never
  *              depends on how those lines happen to be wired
  *
  *          SPI: mode 1 (CPOL = 0, CPHA = 1). DIN is latched on the SCLK falling
  *          edge and DOUT changes on the rising edge. Max 10 MHz. Since
  *          Matrix_Card 2 removed the AD7476, SPI1 has exactly one device.
  *
  *          Full scale is +/- VREF / Gain over +/- 2^23 codes. NOTE this differs
  *          from the ADS1232 bench rig, which is +/- 0.5 * VREF / Gain - do not
  *          carry that factor of 2 across (PROJECT_LOG BU-08).
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __ADS124S08_H
#define __ADS124S08_H

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"

/* -------------------------------------------------------------------------- */
/* Commands (SBAS660C Table 24)                                               */
/* -------------------------------------------------------------------------- */
#define ADS124S08_CMD_NOP        0x00U
#define ADS124S08_CMD_WAKEUP     0x02U
#define ADS124S08_CMD_POWERDOWN  0x04U
#define ADS124S08_CMD_RESET      0x06U
#define ADS124S08_CMD_START      0x08U
#define ADS124S08_CMD_STOP       0x0AU
#define ADS124S08_CMD_SYOCAL     0x16U   /* system offset  */
#define ADS124S08_CMD_SYGCAL     0x17U   /* system gain    */
#define ADS124S08_CMD_SFOCAL     0x19U   /* self offset    */
#define ADS124S08_CMD_RDATA      0x12U
#define ADS124S08_CMD_RREG       0x20U   /* OR with register address */
#define ADS124S08_CMD_WREG       0x40U   /* OR with register address */

/* -------------------------------------------------------------------------- */
/* Registers (SBAS660C Table 25)                                              */
/* -------------------------------------------------------------------------- */
#define ADS124S08_REG_ID         0x00U
#define ADS124S08_REG_STATUS     0x01U
#define ADS124S08_REG_INPMUX     0x02U
#define ADS124S08_REG_PGA        0x03U
#define ADS124S08_REG_DATARATE   0x04U
#define ADS124S08_REG_REF        0x05U
#define ADS124S08_REG_IDACMAG    0x06U
#define ADS124S08_REG_IDACMUX    0x07U
#define ADS124S08_REG_VBIAS      0x08U
#define ADS124S08_REG_SYS        0x09U
#define ADS124S08_REG_OFCAL0     0x0AU
#define ADS124S08_REG_FSCAL0     0x0DU
#define ADS124S08_REG_GPIODAT    0x10U
#define ADS124S08_REG_GPIOCON    0x11U

/* ID register: DEV_ID[2:0]. 000 = ADS124S08, 001 = ADS124S06. */
#define ADS124S08_DEVID_MASK     0x07U
#define ADS124S08_DEVID_124S08   0x00U

/* Input multiplexer codes. */
#define ADS124S08_MUX_AIN0       0x0U
#define ADS124S08_MUX_AIN1       0x1U
#define ADS124S08_MUX_AIN2       0x2U
#define ADS124S08_MUX_AIN3       0x3U
#define ADS124S08_MUX_AINCOM     0xCU

/* PGA register fields. PGA_EN = 01 enables; 00 powers down and bypasses, which
 * removes the common-mode headroom requirement entirely (useful for
 * single-ended reads). */
#define ADS124S08_PGA_BYPASS     0x00U
#define ADS124S08_PGA_ENABLE     0x08U   /* PGA_EN[4:3] = 01 */

/* REF register. The internal reference is OFF at reset (REFCON = 00) - it must
 * be switched on explicitly as well as selected. */
#define ADS124S08_REF_SEL_INT    0x08U   /* REFSEL[3:2] = 10 */
#define ADS124S08_REF_CON_ON     0x01U   /* REFCON[1:0] = 01 */
#define ADS124S08_REF_BUF_OFF    0x30U   /* bypass both reference buffers */

#define ADS124S08_VREF_INTERNAL  2.5f

/* -------------------------------------------------------------------------- */
/* Types                                                                      */
/* -------------------------------------------------------------------------- */

typedef enum
{
  ADS124S08_GAIN_1 = 0, ADS124S08_GAIN_2, ADS124S08_GAIN_4, ADS124S08_GAIN_8,
  ADS124S08_GAIN_16,    ADS124S08_GAIN_32, ADS124S08_GAIN_64, ADS124S08_GAIN_128
} ADS124S08_Gain_t;

typedef enum
{
  ADS124S08_DR_2_5 = 0, ADS124S08_DR_5,   ADS124S08_DR_10,  ADS124S08_DR_16_6,
  ADS124S08_DR_20,      ADS124S08_DR_50,  ADS124S08_DR_60,  ADS124S08_DR_100,
  ADS124S08_DR_200,     ADS124S08_DR_400, ADS124S08_DR_800, ADS124S08_DR_1000,
  ADS124S08_DR_2000,    ADS124S08_DR_4000
} ADS124S08_Rate_t;

/**
  * @brief  Control-line access. All four lines are on MCP23017 U69, so they are
  *         reached through callbacks rather than GPIO descriptors.
  * @note   assert = 1 means "make the line active": CS low, RESET low,
  *         START/SYNC high. The callback owns the polarity so callers never
  *         have to remember which lines are active-low.
  *         drdy may be NULL - the driver then relies purely on timed waits.
  */
typedef struct
{
  HAL_StatusTypeDef (*cs)(void *ctx, uint8_t assert);
  HAL_StatusTypeDef (*reset)(void *ctx, uint8_t assert);
  HAL_StatusTypeDef (*start)(void *ctx, uint8_t assert);
  HAL_StatusTypeDef (*drdy)(void *ctx, uint8_t *ready);   /* optional */
  void *ctx;
} ADS124S08_Io_t;

typedef struct
{
  SPI_HandleTypeDef *spi;
  ADS124S08_Io_t     io;
  float              vref;      /* volts across REFP-REFN in use      */
  ADS124S08_Gain_t   gain;
  ADS124S08_Rate_t   rate;
} ADS124S08_t;

/* -------------------------------------------------------------------------- */
/* API                                                                        */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Reset the device, verify its ID and apply a known-good baseline.
  * @note   Baseline: internal 2.5 V reference selected AND switched on, PGA
  *         enabled at the requested gain, requested data rate, continuous
  *         conversion, inputs AIN0(+)/AIN1(-). Leaves conversions stopped.
  * @param  dev  : [out] instance to populate; must be non-NULL.
  * @param  spi  : [in]  SPI handle, mode 1; must be non-NULL.
  * @param  io   : [in]  control-line callbacks; cs/reset/start must be non-NULL.
  * @param  gain : [in]  initial PGA gain.
  * @param  rate : [in]  initial data rate.
  * @retval HAL_OK on success, HAL_ERROR on a bad argument or ID mismatch.
  */
HAL_StatusTypeDef ADS124S08_Init(ADS124S08_t *dev, SPI_HandleTypeDef *spi,
                                 const ADS124S08_Io_t *io,
                                 ADS124S08_Gain_t gain, ADS124S08_Rate_t rate);

/**
  * @brief  Pulse RESET, then wait the specified recovery time.
  */
HAL_StatusTypeDef ADS124S08_Reset(ADS124S08_t *dev);

/**
  * @brief  Read the ID register and confirm it is an ADS124S08.
  * @param  id : [out] raw ID register value; may be NULL.
  * @retval HAL_OK if DEV_ID = 000, HAL_ERROR otherwise.
  */
HAL_StatusTypeDef ADS124S08_CheckId(ADS124S08_t *dev, uint8_t *id);

/* Register and command access ---------------------------------------------- */
HAL_StatusTypeDef ADS124S08_WriteReg(ADS124S08_t *dev, uint8_t reg, uint8_t val);
HAL_StatusTypeDef ADS124S08_ReadReg(ADS124S08_t *dev, uint8_t reg, uint8_t *val);
HAL_StatusTypeDef ADS124S08_Command(ADS124S08_t *dev, uint8_t cmd);

/**
  * @brief  Select the differential input pair.
  * @param  p, n : [in] ADS124S08_MUX_* codes.
  */
HAL_StatusTypeDef ADS124S08_SetMux(ADS124S08_t *dev, uint8_t p, uint8_t n);

/**
  * @brief  Set the PGA gain (PGA enabled).
  */
HAL_StatusTypeDef ADS124S08_SetGain(ADS124S08_t *dev, ADS124S08_Gain_t gain);

/**
  * @brief  Bypass the PGA entirely (gain forced to 1).
  * @note   Removes the common-mode headroom requirement - the absolute input
  *         range becomes AVSS-0.05 to AVDD+0.05. The right mode for a
  *         single-ended read such as the current-reference measurement.
  */
HAL_StatusTypeDef ADS124S08_BypassPga(ADS124S08_t *dev);

/**
  * @brief  Set the output data rate.
  */
HAL_StatusTypeDef ADS124S08_SetRate(ADS124S08_t *dev, ADS124S08_Rate_t rate);

/**
  * @brief  Run the self offset calibration (SFOCAL).
  * @note   The device shorts its own inputs internally. Must be issued while
  *         converting, so this starts conversions, calibrates, and stops.
  */
HAL_StatusTypeDef ADS124S08_SelfOffsetCal(ADS124S08_t *dev);

/**
  * @brief  Start conversions, wait one conversion period, read, stop.
  * @note   The wait is derived from the configured data rate rather than polled
  *         on DRDY, because DRDY is an expander input and each poll costs an
  *         I2C round-trip. When io.drdy is supplied it is checked once at the
  *         end as a sanity check, not used for timing.
  * @param  code : [out] sign-extended 24-bit result; must be non-NULL.
  * @retval HAL_OK on success, HAL_TIMEOUT if DRDY never asserted.
  */
HAL_StatusTypeDef ADS124S08_ConvertOnce(ADS124S08_t *dev, int32_t *code);

/**
  * @brief  Average @p n conversions in continuous mode.
  * @note   Cheaper than n calls to ConvertOnce - conversions are started once
  *         and the device free-runs, so only the reads cost bus traffic.
  */
HAL_StatusTypeDef ADS124S08_ConvertAverage(ADS124S08_t *dev, uint16_t n, int32_t *code);

/**
  * @brief  Convert a code to volts at the ADC input.
  * @note   volts = code * VREF / (gain * 2^23). No factor of 2 - see BU-08.
  */
float ADS124S08_CodeToVolts(const ADS124S08_t *dev, int32_t code);

/**
  * @brief  Ratiometric resistance: R = R_ref * code / (gain * 2^23).
  * @note   Valid only when the reference is derived from the same current that
  *         flows through the DUT. With the internal 2.5 V reference this does
  *         NOT hold - use ADS124S08_OhmsFromCurrent() instead until HW-04 is
  *         implemented.
  */
float ADS124S08_OhmsRatiometric(const ADS124S08_t *dev, int32_t code, float r_ref_ohms);

/**
  * @brief  Resistance from a known excitation current: R = V / I.
  */
float ADS124S08_OhmsFromCurrent(const ADS124S08_t *dev, int32_t code, float current_a);

/**
  * @brief  Numeric gain (1..128) for a gain enum.
  */
uint16_t ADS124S08_GainValue(ADS124S08_Gain_t g);

/**
  * @brief  Nominal conversion period in milliseconds for a data rate.
  */
uint32_t ADS124S08_PeriodMs(ADS124S08_Rate_t r);

#ifdef __cplusplus
}
#endif

#endif /* __ADS124S08_H */
