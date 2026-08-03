/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    ads124s08.c
  * @brief   ADS124S08 driver implementation. See ads124s08.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "drivers/ads124s08.h"

#ifndef ADS124S08_SPI_TIMEOUT
#define ADS124S08_SPI_TIMEOUT   100U
#endif

/* td(RSSC): delay after RESET before the first serial command. The datasheet
 * figure is in microseconds; 4 ms is generous and costs nothing at init. */
#ifndef ADS124S08_RESET_MS
#define ADS124S08_RESET_MS      4U
#endif

/* Extra margin on every timed conversion wait. The first conversion after START
 * carries the digital filter's latency, so a bare conversion period is not
 * enough - see the DELAY[2:0] field and the filter description in SBAS660C. */
#ifndef ADS124S08_CONV_MARGIN_MS
#define ADS124S08_CONV_MARGIN_MS  3U
#endif

/* -------------------------------------------------------------------------- */
/* Low level                                                                  */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Assert or release CS through the io vtable.
  * @param  dev    : [in] instance.
  * @param  assert : [in] 1 = select the device, 0 = release it.
  * @retval HAL status from the callback.
  */
static HAL_StatusTypeDef ads_cs(ADS124S08_t *dev, uint8_t assert)
{
  return dev->io.cs(dev->io.ctx, assert);
}

/**
  * @brief  Full-duplex SPI transfer with CS already asserted.
  * @param  dev : [in]  instance.
  * @param  tx  : [in]  bytes to send; must be non-NULL.
  * @param  rx  : [out] bytes received; may be NULL to discard.
  * @param  n   : [in]  byte count.
  * @retval HAL status from the SPI transfer.
  */
static HAL_StatusTypeDef ads_xfer(ADS124S08_t *dev, const uint8_t *tx,
                                  uint8_t *rx, uint16_t n)
{
  uint8_t scratch[8];

  if (rx == NULL)
  {
    if (n > sizeof(scratch))
    {
      return HAL_ERROR;
    }
    rx = scratch;
  }
  return HAL_SPI_TransmitReceive(dev->spi, (uint8_t *)tx, rx, n,
                                 ADS124S08_SPI_TIMEOUT);
}

/**
  * @brief  Select, transfer, release. The unit of work for this device.
  * @note   Each call costs two I2C writes (CS assert and release) because the
  *         chip select lives on an expander. Batch where it matters.
  * @param  dev : [in]  instance.
  * @param  tx  : [in]  bytes to send.
  * @param  rx  : [out] bytes received; may be NULL.
  * @param  n   : [in]  byte count.
  * @retval HAL_OK on success, else the first failing status. CS is released on
  *         every path, including failure.
  */
static HAL_StatusTypeDef ads_framed(ADS124S08_t *dev, const uint8_t *tx,
                                    uint8_t *rx, uint16_t n)
{
  HAL_StatusTypeDef st, st_rel;

  st = ads_cs(dev, 1U);
  if (st != HAL_OK)
  {
    return st;
  }
  st = ads_xfer(dev, tx, rx, n);

  st_rel = ads_cs(dev, 0U);
  return (st != HAL_OK) ? st : st_rel;
}

/* -------------------------------------------------------------------------- */
/* Public                                                                     */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Numeric gain (1..128) for a gain enum.
  * @param  g : [in] gain enumeration.
  * @retval 1 << g, i.e. 1, 2, 4, ... 128.
  */
uint16_t ADS124S08_GainValue(ADS124S08_Gain_t g)
{
  return (uint16_t)(1U << (uint8_t)g);
}

/**
  * @brief  Nominal conversion period in milliseconds for a data rate.
  * @param  r : [in] data-rate enumeration.
  * @retval Period rounded up; 400 ms for the slowest rate, 1 ms for the fastest.
  */
uint32_t ADS124S08_PeriodMs(ADS124S08_Rate_t r)
{
  static const uint16_t ms[] = {
    400U, 200U, 100U, 61U, 50U, 20U, 17U, 10U, 5U, 3U, 2U, 1U, 1U, 1U
  };
  return (r < (ADS124S08_Rate_t)(sizeof(ms) / sizeof(ms[0]))) ? ms[r] : 400U;
}

/**
  * @brief  Issue a single-byte command.
  * @param  dev : [in] instance; must be non-NULL.
  * @param  cmd : [in] ADS124S08_CMD_* opcode.
  * @retval HAL_OK on success, HAL_ERROR if @p dev is NULL, else propagated.
  */
HAL_StatusTypeDef ADS124S08_Command(ADS124S08_t *dev, uint8_t cmd)
{
  uint8_t tx = cmd;

  if (dev == NULL)
  {
    return HAL_ERROR;
  }
  return ads_framed(dev, &tx, NULL, 1U);
}

/**
  * @brief  Write one configuration register.
  * @note   WREG is three bytes: 0x40|addr, count-1, data.
  * @param  dev : [in] instance; must be non-NULL.
  * @param  reg : [in] register address.
  * @param  val : [in] value to write.
  * @retval HAL_OK on success, HAL_ERROR if @p dev is NULL, else propagated.
  */
HAL_StatusTypeDef ADS124S08_WriteReg(ADS124S08_t *dev, uint8_t reg, uint8_t val)
{
  uint8_t tx[3];

  if (dev == NULL)
  {
    return HAL_ERROR;
  }
  tx[0] = (uint8_t)(ADS124S08_CMD_WREG | (reg & 0x1FU));
  tx[1] = 0U;      /* one register */
  tx[2] = val;
  return ads_framed(dev, tx, NULL, 3U);
}

/**
  * @brief  Read one configuration register.
  * @note   RREG is 0x20|addr, count-1, then one clocked byte for the data.
  * @param  dev : [in]  instance; must be non-NULL.
  * @param  reg : [in]  register address.
  * @param  val : [out] destination; must be non-NULL.
  * @retval HAL_OK on success, HAL_ERROR on a NULL argument, else propagated.
  */
HAL_StatusTypeDef ADS124S08_ReadReg(ADS124S08_t *dev, uint8_t reg, uint8_t *val)
{
  uint8_t tx[3] = {0U, 0U, ADS124S08_CMD_NOP};
  uint8_t rx[3] = {0U, 0U, 0U};
  HAL_StatusTypeDef st;

  if (dev == NULL || val == NULL)
  {
    return HAL_ERROR;
  }
  tx[0] = (uint8_t)(ADS124S08_CMD_RREG | (reg & 0x1FU));

  st = ads_framed(dev, tx, rx, 3U);
  if (st == HAL_OK)
  {
    *val = rx[2];
  }
  return st;
}

/**
  * @brief  Pulse RESET, then wait the recovery time.
  * @note   Also drives START/SYNC inactive. The START command is NOT decoded
  *         while the START/SYNC pin is high, so leaving it high would silently
  *         break every later conversion.
  * @param  dev : [in] instance; must be non-NULL.
  * @retval HAL_OK on success, HAL_ERROR if @p dev is NULL, else propagated.
  */
HAL_StatusTypeDef ADS124S08_Reset(ADS124S08_t *dev)
{
  HAL_StatusTypeDef st;

  if (dev == NULL)
  {
    return HAL_ERROR;
  }

  st = dev->io.start(dev->io.ctx, 0U);
  if (st != HAL_OK)
  {
    return st;
  }
  st = dev->io.reset(dev->io.ctx, 1U);
  if (st != HAL_OK)
  {
    return st;
  }
  HAL_Delay(1U);
  st = dev->io.reset(dev->io.ctx, 0U);
  if (st != HAL_OK)
  {
    return st;
  }
  HAL_Delay(ADS124S08_RESET_MS);
  return HAL_OK;
}

/**
  * @brief  Read the ID register and confirm it is an ADS124S08.
  * @param  dev : [in]  instance; must be non-NULL.
  * @param  id  : [out] raw register value; may be NULL.
  * @retval HAL_OK if DEV_ID = 000, HAL_ERROR otherwise.
  */
HAL_StatusTypeDef ADS124S08_CheckId(ADS124S08_t *dev, uint8_t *id)
{
  uint8_t v = 0U;
  HAL_StatusTypeDef st;

  st = ADS124S08_ReadReg(dev, ADS124S08_REG_ID, &v);
  if (st != HAL_OK)
  {
    return st;
  }
  if (id != NULL)
  {
    *id = v;
  }
  return ((v & ADS124S08_DEVID_MASK) == ADS124S08_DEVID_124S08) ? HAL_OK : HAL_ERROR;
}

/**
  * @brief  Select the differential input pair.
  * @param  dev  : [in] instance.
  * @param  p, n : [in] ADS124S08_MUX_* codes for the positive and negative input.
  * @retval HAL status from the register write.
  */
HAL_StatusTypeDef ADS124S08_SetMux(ADS124S08_t *dev, uint8_t p, uint8_t n)
{
  return ADS124S08_WriteReg(dev, ADS124S08_REG_INPMUX,
                            (uint8_t)(((p & 0x0FU) << 4) | (n & 0x0FU)));
}

/**
  * @brief  Set the PGA gain, PGA enabled.
  * @param  dev  : [in] instance; must be non-NULL.
  * @param  gain : [in] new gain.
  * @retval HAL status; the cached gain is only updated on success, so a failed
  *         write cannot leave the scaling maths disagreeing with the hardware.
  */
HAL_StatusTypeDef ADS124S08_SetGain(ADS124S08_t *dev, ADS124S08_Gain_t gain)
{
  HAL_StatusTypeDef st;

  if (dev == NULL)
  {
    return HAL_ERROR;
  }
  st = ADS124S08_WriteReg(dev, ADS124S08_REG_PGA,
                          (uint8_t)(ADS124S08_PGA_ENABLE | ((uint8_t)gain & 0x07U)));
  if (st == HAL_OK)
  {
    dev->gain = gain;
  }
  return st;
}

/**
  * @brief  Bypass the PGA entirely; gain becomes 1.
  * @param  dev : [in] instance; must be non-NULL.
  * @retval HAL status from the register write.
  */
HAL_StatusTypeDef ADS124S08_BypassPga(ADS124S08_t *dev)
{
  HAL_StatusTypeDef st;

  if (dev == NULL)
  {
    return HAL_ERROR;
  }
  /* Datasheet requires GAIN[2:0] = 000 when the PGA is bypassed. */
  st = ADS124S08_WriteReg(dev, ADS124S08_REG_PGA, ADS124S08_PGA_BYPASS);
  if (st == HAL_OK)
  {
    dev->gain = ADS124S08_GAIN_1;
  }
  return st;
}

/**
  * @brief  Set the output data rate.
  * @note   Keeps continuous-conversion mode, the internal oscillator and the
  *         low-latency filter (the reset defaults for those fields).
  * @param  dev  : [in] instance; must be non-NULL.
  * @param  rate : [in] new data rate.
  * @retval HAL status; the cached rate is only updated on success.
  */
HAL_StatusTypeDef ADS124S08_SetRate(ADS124S08_t *dev, ADS124S08_Rate_t rate)
{
  HAL_StatusTypeDef st;

  if (dev == NULL)
  {
    return HAL_ERROR;
  }
  st = ADS124S08_WriteReg(dev, ADS124S08_REG_DATARATE,
                          (uint8_t)(0x10U | ((uint8_t)rate & 0x0FU)));
  if (st == HAL_OK)
  {
    dev->rate = rate;
  }
  return st;
}

/**
  * @brief  Reset, verify the ID and apply a known-good baseline.
  * @param  dev  : [out] instance; must be non-NULL.
  * @param  spi  : [in]  SPI handle in mode 1; must be non-NULL.
  * @param  io   : [in]  control-line callbacks; cs/reset/start must be non-NULL.
  * @param  gain : [in]  initial gain.
  * @param  rate : [in]  initial data rate.
  * @retval HAL_OK on success, HAL_ERROR on a bad argument or an ID mismatch.
  */
HAL_StatusTypeDef ADS124S08_Init(ADS124S08_t *dev, SPI_HandleTypeDef *spi,
                                 const ADS124S08_Io_t *io,
                                 ADS124S08_Gain_t gain, ADS124S08_Rate_t rate)
{
  HAL_StatusTypeDef st;

  if (dev == NULL || spi == NULL || io == NULL ||
      io->cs == NULL || io->reset == NULL || io->start == NULL)
  {
    return HAL_ERROR;
  }

  dev->spi  = spi;
  dev->io   = *io;
  dev->vref = ADS124S08_VREF_INTERNAL;
  dev->gain = gain;
  dev->rate = rate;

  st = ADS124S08_Reset(dev);
  if (st != HAL_OK)
  {
    return st;
  }
  st = ADS124S08_CheckId(dev, NULL);
  if (st != HAL_OK)
  {
    return st;   /* wrong part, or the SPI/CS path is not working */
  }

  /* Internal reference: selecting it is not enough, REFCON must switch it on -
   * it is OFF at reset. Both reference buffers are bypassed, which the
   * datasheet recommends when the reference sits near a rail. */
  st = ADS124S08_WriteReg(dev, ADS124S08_REG_REF,
                          (uint8_t)(ADS124S08_REF_BUF_OFF |
                                    ADS124S08_REF_SEL_INT |
                                    ADS124S08_REF_CON_ON));
  if (st != HAL_OK)
  {
    return st;
  }

  st = ADS124S08_SetGain(dev, gain);
  if (st != HAL_OK)
  {
    return st;
  }
  st = ADS124S08_SetRate(dev, rate);
  if (st != HAL_OK)
  {
    return st;
  }
  /* The Kelvin pair: AIN0 = HI_SENSE, AIN1 = LO_SENSE. */
  st = ADS124S08_SetMux(dev, ADS124S08_MUX_AIN0, ADS124S08_MUX_AIN1);
  if (st != HAL_OK)
  {
    return st;
  }

  /* Settle the newly enabled reference before anyone converts. */
  HAL_Delay(10U);
  return ADS124S08_Command(dev, ADS124S08_CMD_STOP);
}

/**
  * @brief  Run the self offset calibration.
  * @note   SFOCAL shorts the inputs internally. Calibration commands are only
  *         decoded while converting, so this starts conversions, calibrates,
  *         waits several conversion periods, and stops again.
  * @param  dev : [in] instance; must be non-NULL.
  * @retval HAL_OK on success, HAL_ERROR if @p dev is NULL, else propagated.
  */
HAL_StatusTypeDef ADS124S08_SelfOffsetCal(ADS124S08_t *dev)
{
  HAL_StatusTypeDef st;
  uint32_t period;

  if (dev == NULL)
  {
    return HAL_ERROR;
  }
  period = ADS124S08_PeriodMs(dev->rate);

  st = ADS124S08_Command(dev, ADS124S08_CMD_START);
  if (st != HAL_OK)
  {
    return st;
  }
  HAL_Delay(period + ADS124S08_CONV_MARGIN_MS);

  st = ADS124S08_Command(dev, ADS124S08_CMD_SFOCAL);
  if (st != HAL_OK)
  {
    return st;
  }
  /* The calibration averages several conversions internally. */
  HAL_Delay((period * 20U) + ADS124S08_CONV_MARGIN_MS);

  return ADS124S08_Command(dev, ADS124S08_CMD_STOP);
}

/**
  * @brief  Read one conversion result with the RDATA command.
  * @note   RDATA returns data regardless of where the device is in its
  *         conversion cycle, which avoids the corruption risk that direct-read
  *         mode carries when DRDY timing is not tracked precisely - and DRDY
  *         timing cannot be tracked precisely when DRDY is on an I2C expander.
  * @param  dev  : [in]  instance.
  * @param  code : [out] sign-extended 24-bit result.
  * @retval HAL status from the transfer.
  */
static HAL_StatusTypeDef ads_rdata(ADS124S08_t *dev, int32_t *code)
{
  uint8_t tx[4] = {ADS124S08_CMD_RDATA, ADS124S08_CMD_NOP,
                   ADS124S08_CMD_NOP,   ADS124S08_CMD_NOP};
  uint8_t rx[4] = {0U, 0U, 0U, 0U};
  uint32_t raw;
  HAL_StatusTypeDef st;

  st = ads_framed(dev, tx, rx, 4U);
  if (st != HAL_OK)
  {
    return st;
  }

  raw = ((uint32_t)rx[1] << 16) | ((uint32_t)rx[2] << 8) | (uint32_t)rx[3];
  if ((raw & 0x00800000U) != 0U)
  {
    raw |= 0xFF000000U;      /* sign-extend 24 -> 32 */
  }
  *code = (int32_t)raw;
  return HAL_OK;
}

/**
  * @brief  Start conversions, wait one period, read, stop.
  * @param  dev  : [in]  instance; must be non-NULL.
  * @param  code : [out] result; must be non-NULL.
  * @retval HAL_OK on success, HAL_TIMEOUT if DRDY is available and never
  *         asserted, HAL_ERROR on a bad argument.
  */
HAL_StatusTypeDef ADS124S08_ConvertOnce(ADS124S08_t *dev, int32_t *code)
{
  HAL_StatusTypeDef st;
  uint8_t ready = 1U;

  if (dev == NULL || code == NULL)
  {
    return HAL_ERROR;
  }

  st = ADS124S08_Command(dev, ADS124S08_CMD_START);
  if (st != HAL_OK)
  {
    return st;
  }

  /* Timed, not polled: DRDY sits on an I2C expander, so polling it would cost
   * a bus round-trip per check and still be slower than simply waiting. */
  HAL_Delay(ADS124S08_PeriodMs(dev->rate) + ADS124S08_CONV_MARGIN_MS);

  if (dev->io.drdy != NULL)
  {
    (void)dev->io.drdy(dev->io.ctx, &ready);   /* sanity check only */
  }

  st = ads_rdata(dev, code);
  (void)ADS124S08_Command(dev, ADS124S08_CMD_STOP);

  if (st != HAL_OK)
  {
    return st;
  }
  return (ready != 0U) ? HAL_OK : HAL_TIMEOUT;
}

/**
  * @brief  Average @p n conversions with the device free-running.
  * @note   Conversions are started once, so only the reads cost bus traffic -
  *         materially cheaper than n ConvertOnce() calls, each of which would
  *         pay a START and a STOP.
  * @param  dev  : [in]  instance; must be non-NULL.
  * @param  n    : [in]  sample count; must be non-zero.
  * @param  code : [out] mean result; must be non-NULL.
  * @retval HAL_OK on success, HAL_ERROR on a bad argument, else propagated.
  */
HAL_StatusTypeDef ADS124S08_ConvertAverage(ADS124S08_t *dev, uint16_t n, int32_t *code)
{
  HAL_StatusTypeDef st;
  int64_t  acc = 0;
  uint32_t period;
  uint16_t i;
  int32_t  c;

  if (dev == NULL || code == NULL || n == 0U)
  {
    return HAL_ERROR;
  }
  period = ADS124S08_PeriodMs(dev->rate);

  st = ADS124S08_Command(dev, ADS124S08_CMD_START);
  if (st != HAL_OK)
  {
    return st;
  }
  /* Discard the first conversion - it carries the filter's start-up latency. */
  HAL_Delay(period + ADS124S08_CONV_MARGIN_MS);
  (void)ads_rdata(dev, &c);

  for (i = 0U; i < n; i++)
  {
    HAL_Delay(period + ADS124S08_CONV_MARGIN_MS);
    st = ads_rdata(dev, &c);
    if (st != HAL_OK)
    {
      (void)ADS124S08_Command(dev, ADS124S08_CMD_STOP);
      return st;
    }
    acc += c;
  }

  (void)ADS124S08_Command(dev, ADS124S08_CMD_STOP);
  *code = (int32_t)(acc / (int64_t)n);
  return HAL_OK;
}

/**
  * @brief  Convert a code to volts at the ADC input.
  * @param  dev  : [in] instance; must be non-NULL.
  * @param  code : [in] conversion result.
  * @retval Volts. Full scale is +/- VREF/Gain - no factor of 2, unlike the
  *         ADS1232 bench rig (BU-08).
  */
float ADS124S08_CodeToVolts(const ADS124S08_t *dev, int32_t code)
{
  if (dev == NULL)
  {
    return 0.0f;
  }
  return ((float)code * dev->vref)
         / ((float)ADS124S08_GainValue(dev->gain) * 8388608.0f);
}

/**
  * @brief  Ratiometric resistance.
  * @param  dev        : [in] instance; must be non-NULL.
  * @param  code       : [in] conversion result.
  * @param  r_ref_ohms : [in] reference resistor carrying the same current.
  * @retval R_ref * code / (gain * 2^23).
  */
float ADS124S08_OhmsRatiometric(const ADS124S08_t *dev, int32_t code, float r_ref_ohms)
{
  if (dev == NULL)
  {
    return 0.0f;
  }
  return (r_ref_ohms * (float)code)
         / ((float)ADS124S08_GainValue(dev->gain) * 8388608.0f);
}

/**
  * @brief  Resistance from a known excitation current.
  * @param  dev       : [in] instance; must be non-NULL.
  * @param  code      : [in] conversion result.
  * @param  current_a : [in] excitation current in amps; must be non-zero.
  * @retval V / I, or 0 on a bad argument.
  */
float ADS124S08_OhmsFromCurrent(const ADS124S08_t *dev, int32_t code, float current_a)
{
  if (dev == NULL || current_a == 0.0f)
  {
    return 0.0f;
  }
  return ADS124S08_CodeToVolts(dev, code) / current_a;
}
