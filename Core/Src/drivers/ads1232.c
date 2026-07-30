/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    ads1232.c
  * @brief   BENCH-ONLY ADS1232 driver implementation. See ads1232.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "drivers/ads1232.h"

#if (HT_ENABLE_ADS1232 != 0)

#include "app/log.h"
#include <stdlib.h>

/* Nucleo bench pin map - see Doc/ADS1232_bench_wiring.md.
 * Overridable from the build so a suspect pin can be moved without editing
 * code: PA0 (A0) and PC7 (D9) are also free on this project. */
#ifndef ADS1232_SCLK_PORT
#define ADS1232_SCLK_PORT   GPIOA
#define ADS1232_SCLK_PIN    GPIO_PIN_1    /* Arduino A1 */
#endif
#ifndef ADS1232_DOUT_PORT
#define ADS1232_DOUT_PORT   GPIOA
#define ADS1232_DOUT_PIN    GPIO_PIN_4    /* Arduino A2 */
#endif
#ifndef ADS1232_PDWN_PORT
#define ADS1232_PDWN_PORT   GPIOC
#define ADS1232_PDWN_PIN    GPIO_PIN_1    /* Arduino A4 */
#endif

ADS1232_t g_ads1232;

/* SCLK half-period. The ADS1232 tolerates a slow clock, and a slow clock is
 * far more robust on flying leads, which is what a bench rig always has.
 * ~1 us per half-period gives roughly a 500 kHz SCLK; a 24-bit read then takes
 * about 50 us, negligible against a 10 or 80 SPS conversion. */
#ifndef ADS1232_SCLK_DELAY_LOOPS
#define ADS1232_SCLK_DELAY_LOOPS   40U
#endif

/* SCLK must not be held high longer than this or the device powers down
 * (ADS123x family behaviour). Never park the clock high. */

/**
  * @brief  Crude busy-wait used to shape the bit-banged SCLK.
  * @note   Deliberately not HAL_Delay(): the shortest HAL delay is 1 ms, which
  *         would stretch a 24-bit read to 50 ms and risk the SCLK-high timeout.
  * @param  loops : [in] iteration count.
  * @retval None
  */
static void ads1232_delay(volatile uint32_t loops)
{
  while (loops-- != 0U)
  {
    __NOP();
  }
}

/**
  * @brief  Drive an optional pin, if it is wired to a GPIO.
  * @param  p     : [in] pin descriptor; ignored when p->port is NULL (strapped).
  * @param  state : [in] 0 = low, non-zero = high.
  * @retval None
  */
static void ads1232_write_opt(const ADS1232_Pin_t *p, uint8_t state)
{
  if (p->port != NULL)
  {
    HAL_GPIO_WritePin(p->port, p->pin, (state != 0U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
  }
}

/**
  * @brief  Push the cached gain / rate / channel settings out to whichever of
  *         GAIN0, GAIN1, SPEED and A0 are actually wired to GPIO.
  * @param  dev : [in] instance.
  * @retval None
  */
static void ads1232_apply_cfg(ADS1232_t *dev)
{
  ads1232_write_opt(&dev->cfg.gain0, ((uint8_t)dev->cfg.gain) & 0x01U);
  ads1232_write_opt(&dev->cfg.gain1, (((uint8_t)dev->cfg.gain) >> 1) & 0x01U);
  ads1232_write_opt(&dev->cfg.speed, (uint8_t)dev->cfg.rate);
  ads1232_write_opt(&dev->cfg.a0,    (uint8_t)dev->cfg.channel);
}

/**
  * @brief  Issue one SCLK pulse and sample DOUT while the clock is high.
  * @param  dev : [in] instance.
  * @retval The DOUT level captured during the pulse (0 or 1).
  */
static uint8_t ads1232_clock_bit(ADS1232_t *dev)
{
  uint8_t bit;

  HAL_GPIO_WritePin(dev->cfg.sclk.port, dev->cfg.sclk.pin, GPIO_PIN_SET);
  ads1232_delay(ADS1232_SCLK_DELAY_LOOPS);

  bit = (HAL_GPIO_ReadPin(dev->cfg.dout.port, dev->cfg.dout.pin) == GPIO_PIN_SET) ? 1U : 0U;

  HAL_GPIO_WritePin(dev->cfg.sclk.port, dev->cfg.sclk.pin, GPIO_PIN_RESET);
  ads1232_delay(ADS1232_SCLK_DELAY_LOOPS);

  return bit;
}

/* Retries consumed since the last reset - a live measure of link health. */
static uint16_t s_retries;

/* Retries allowed per sample when the link is intermittent. At a 70% link,
 * 8 attempts fail together with probability 0.3^8 = 0.0066% - so a bad joint
 * slows the rig down but does not stop it producing data. */
#ifndef ADS1232_READ_ATTEMPTS
#define ADS1232_READ_ATTEMPTS   8U
#endif

/**
  * @brief  Read one conversion, retrying through a flaky connection.
  * @note   ADS1232_ReadRaw() fails when the device does not release DOUT, which
  *         on a bench rig usually means a momentary bad contact rather than a
  *         real fault. Retrying keeps the measurement running while the joint
  *         is still being fixed.
  * @param  dev        : [in]  instance.
  * @param  code       : [out] conversion result.
  * @param  timeout_ms : [in]  per-attempt data-ready timeout.
  * @retval HAL_OK if any attempt succeeded, HAL_ERROR if all failed.
  */
static HAL_StatusTypeDef ads1232_read_retry(ADS1232_t *dev, int32_t *code,
                                            uint32_t timeout_ms)
{
  uint8_t a;

  for (a = 0U; a < (uint8_t)ADS1232_READ_ATTEMPTS; a++)
  {
    if (ADS1232_ReadRaw(dev, code, timeout_ms) == HAL_OK)
    {
      s_retries += (uint16_t)a;   /* how hard the link made us work */
      return HAL_OK;
    }
  }
  s_retries += (uint16_t)ADS1232_READ_ATTEMPTS;
  return HAL_ERROR;
}

/**
  * @brief  Ascending insertion sort of a small code array.
  * @note   n is 16 here; insertion sort is the right tool and needs no scratch.
  * @param  a : [in,out] array to sort in place.
  * @param  n : [in]     element count.
  * @retval None
  */
static void ads1232_sort(int32_t *a, uint16_t n)
{
  uint16_t i, j;
  int32_t  key;

  for (i = 1U; i < n; i++)
  {
    key = a[i];
    j = i;
    while (j > 0U && a[j - 1U] > key)
    {
      a[j] = a[j - 1U];
      j--;
    }
    a[j] = key;
  }
}

/* -------------------------------------------------------------------------- */

/**
  * @brief  Bind the driver, drive the configuration pins and wake the device.
  * @param  dev : [out] instance to populate; must be non-NULL.
  * @param  cfg : [in]  pin map and strapped settings; must be non-NULL.
  * @retval HAL_OK    device configured and awake.
  * @retval HAL_ERROR NULL argument, or SCLK/DOUT not supplied.
  */
HAL_StatusTypeDef ADS1232_Init(ADS1232_t *dev, const ADS1232_Cfg_t *cfg)
{
  if (dev == NULL || cfg == NULL)
  {
    return HAL_ERROR;
  }
  if (cfg->sclk.port == NULL || cfg->dout.port == NULL)
  {
    return HAL_ERROR;   /* the two-wire interface is not optional */
  }

  dev->cfg         = *cfg;
  dev->offset_code = 0;

  /* Park the clock low before anything else: a high SCLK is the power-down
   * request on this family. */
  HAL_GPIO_WritePin(dev->cfg.sclk.port, dev->cfg.sclk.pin, GPIO_PIN_RESET);

  ads1232_apply_cfg(dev);

  /* PDWN high = awake. If it is strapped high in hardware this is a no-op. */
  ads1232_write_opt(&dev->cfg.pdwn, 1U);

  /* Settling after wake-up / range change. Generous on purpose. */
  HAL_Delay(10U);

  return HAL_OK;
}

/**
  * @brief  Change gain at runtime.
  * @param  dev  : [in] instance; must be non-NULL.
  * @param  gain : [in] new gain setting.
  * @retval HAL_OK on success, HAL_ERROR if @p dev is NULL or the gain pins are
  *         strapped in hardware rather than wired to GPIO.
  */
HAL_StatusTypeDef ADS1232_SetGain(ADS1232_t *dev, ADS1232_Gain_t gain)
{
  if (dev == NULL)
  {
    return HAL_ERROR;
  }
  if (dev->cfg.gain0.port == NULL || dev->cfg.gain1.port == NULL)
  {
    return HAL_ERROR;   /* strapped - cannot change from firmware */
  }

  dev->cfg.gain = gain;
  ads1232_apply_cfg(dev);
  HAL_Delay(10U);       /* discard whatever conversion was in flight */
  return HAL_OK;
}

/**
  * @brief  Select the input channel.
  * @param  dev : [in] instance; must be non-NULL.
  * @param  ch  : [in] AIN1 or AIN2.
  * @retval HAL_OK on success, HAL_ERROR if @p dev is NULL or A0 is strapped.
  */
HAL_StatusTypeDef ADS1232_SetChannel(ADS1232_t *dev, ADS1232_Channel_t ch)
{
  if (dev == NULL)
  {
    return HAL_ERROR;
  }
  if (dev->cfg.a0.port == NULL)
  {
    return HAL_ERROR;
  }

  dev->cfg.channel = ch;
  ads1232_apply_cfg(dev);
  HAL_Delay(10U);
  return HAL_OK;
}

/**
  * @brief  Poll DOUT/DRDY for a completed conversion.
  * @note   DOUT is high while a conversion is in progress and falls when a
  *         result is available. SCLK must be low throughout.
  * @param  dev        : [in] instance; must be non-NULL.
  * @param  timeout_ms : [in] give up after this long.
  * @retval HAL_OK      data ready.
  * @retval HAL_ERROR   @p dev is NULL.
  * @retval HAL_TIMEOUT no conversion within the timeout.
  */
HAL_StatusTypeDef ADS1232_WaitReady(ADS1232_t *dev, uint32_t timeout_ms)
{
  uint32_t start;

  if (dev == NULL)
  {
    return HAL_ERROR;
  }

  start = HAL_GetTick();
  while (HAL_GPIO_ReadPin(dev->cfg.dout.port, dev->cfg.dout.pin) == GPIO_PIN_SET)
  {
    if ((HAL_GetTick() - start) > timeout_ms)
    {
      return HAL_TIMEOUT;
    }
  }
  return HAL_OK;
}

/**
  * @brief  Wait for data ready and shift out one 24-bit conversion.
  * @note   24 SCLK pulses, MSB first, two's complement; the result is
  *         sign-extended into the returned int32_t.
  * @param  dev        : [in]  instance; must be non-NULL.
  * @param  code       : [out] sign-extended conversion result; must be non-NULL.
  * @param  timeout_ms : [in]  data-ready timeout.
  * @retval HAL_OK      conversion read.
  * @retval HAL_ERROR   NULL argument.
  * @retval HAL_TIMEOUT no conversion within the timeout.
  */
HAL_StatusTypeDef ADS1232_ReadRaw(ADS1232_t *dev, int32_t *code, uint32_t timeout_ms)
{
  HAL_StatusTypeDef st;
  uint32_t raw = 0U;
  uint8_t  i;

  if (dev == NULL || code == NULL)
  {
    return HAL_ERROR;
  }

  st = ADS1232_WaitReady(dev, timeout_ms);
  if (st != HAL_OK)
  {
    return st;
  }

  for (i = 0U; i < 24U; i++)
  {
    raw = (raw << 1) | (uint32_t)ads1232_clock_bit(dev);
  }

  /* A working device releases DOUT high once its 24 bits are out. Still low
   * means it never saw the clock, and every bit sampled as 0 - the exact
   * signature of code == 0 on a rig with a loose SCLK wire. Report it rather
   * than handing back a plausible-looking zero. */
  if (HAL_GPIO_ReadPin(dev->cfg.dout.port, dev->cfg.dout.pin) == GPIO_PIN_RESET)
  {
    return HAL_ERROR;
  }

  /* Reject the two bus-failure signatures. All-zeros means DOUT was held low
   * for the whole word; all-ones means it was held high - i.e. the shift never
   * happened and we sampled the idle line 24 times. Both are legal conversion
   * results in principle, but only 2 codes out of 16.7 million, so rejecting
   * them costs nothing real and removes the dominant error on a flaky link. */
  if (raw == 0x00000000U || raw == 0x00FFFFFFU)
  {
    return HAL_ERROR;
  }

  /* Sign-extend 24 -> 32 bits. */
  if ((raw & 0x00800000U) != 0U)
  {
    raw |= 0xFF000000U;
  }
  *code = (int32_t)raw;

  return HAL_OK;
}

/**
  * @brief  Read one conversion and scale it to volts at the ADC input.
  * @param  dev        : [in]  instance; must be non-NULL.
  * @param  volts      : [out] offset-corrected input voltage; must be non-NULL.
  * @param  timeout_ms : [in]  data-ready timeout.
  * @retval HAL_OK on success, else the status from ADS1232_ReadRaw().
  */
HAL_StatusTypeDef ADS1232_ReadVolts(ADS1232_t *dev, float *volts, uint32_t timeout_ms)
{
  int32_t code;
  HAL_StatusTypeDef st;

  if (dev == NULL || volts == NULL)
  {
    return HAL_ERROR;
  }

  st = ADS1232_ReadRaw(dev, &code, timeout_ms);
  if (st != HAL_OK)
  {
    return st;
  }

  /* Full scale is +/- VREF / gain over +/- 2^23 codes. */
  *volts = ((float)(code - dev->offset_code) * dev->cfg.vref)
           / ((float)ADS1232_GainValue(dev->cfg.gain) * 8388608.0f);

  return HAL_OK;
}

/**
  * @brief  Average @p n conversions into the stored offset (system tare).
  * @param  dev        : [in] instance; must be non-NULL.
  * @param  n          : [in] samples to average; must be non-zero.
  * @param  timeout_ms : [in] per-sample data-ready timeout.
  * @retval HAL_OK on success, HAL_ERROR on a bad argument, else propagated.
  */
HAL_StatusTypeDef ADS1232_Tare(ADS1232_t *dev, uint16_t n, uint32_t timeout_ms)
{
  int64_t acc = 0;
  uint16_t i;

  if (dev == NULL || n == 0U)
  {
    return HAL_ERROR;
  }

  for (i = 0U; i < n; i++)
  {
    int32_t code;
    if (ads1232_read_retry(dev, &code, timeout_ms) != HAL_OK)
    {
      return HAL_ERROR;
    }
    acc += code;
  }

  dev->offset_code = (int32_t)(acc / (int64_t)n);
  return HAL_OK;
}

/**
  * @brief  Average @p n offset-corrected conversions, in volts.
  * @param  dev        : [in]  instance; must be non-NULL.
  * @param  n          : [in]  samples to average; must be non-zero.
  * @param  volts      : [out] mean input voltage; must be non-NULL.
  * @param  timeout_ms : [in]  per-sample data-ready timeout.
  * @retval HAL_OK on success, HAL_ERROR on a bad argument, else propagated.
  */
HAL_StatusTypeDef ADS1232_ReadAverage(ADS1232_t *dev, uint16_t n, float *volts,
                                      uint32_t timeout_ms)
{
  int64_t acc = 0;
  uint16_t i;

  if (dev == NULL || volts == NULL || n == 0U)
  {
    return HAL_ERROR;
  }

  for (i = 0U; i < n; i++)
  {
    int32_t code;
    if (ads1232_read_retry(dev, &code, timeout_ms) != HAL_OK)
    {
      return HAL_ERROR;
    }
    acc += code;
  }

  *volts = ((float)((acc / (int64_t)n) - dev->offset_code) * dev->cfg.vref)
           / ((float)ADS1232_GainValue(dev->cfg.gain) * 8388608.0f);

  return HAL_OK;
}

/**
  * @brief  Convert a measured Kelvin voltage into ohms.
  * @param  volts     : [in]  differential voltage across the wire.
  * @param  current_a : [in]  excitation current actually flowing, amps.
  * @param  ohms      : [out] volts / current_a; must be non-NULL.
  * @retval HAL_OK on success, HAL_ERROR if @p ohms is NULL or @p current_a is 0.
  */
HAL_StatusTypeDef ADS1232_Ohms(float volts, float current_a, float *ohms)
{
  if (ohms == NULL || current_a == 0.0f)
  {
    return HAL_ERROR;
  }
  *ohms = volts / current_a;
  return HAL_OK;
}

/**
  * @brief  RATIOMETRIC 4-wire resistance - the recommended bench method.
  * @note   With the reference resistor in series with the DUT, the excitation
  *         current appears in both the signal and the reference and cancels:
  *         R_dut = R_ref * code / (gain * 2^23). vref is NOT used here, which
  *         is the whole point - nothing has to be calibrated but R_ref.
  * @param  dev        : [in]  instance; must be non-NULL.
  * @param  r_ref_ohms : [in]  series reference resistor, ohms.
  * @param  n          : [in]  conversions to average; must be non-zero.
  * @param  ohms       : [out] measured DUT resistance; must be non-NULL.
  * @param  timeout_ms : [in]  per-sample data-ready timeout.
  * @retval HAL_OK on success, HAL_ERROR on a bad argument, else propagated.
  */
HAL_StatusTypeDef ADS1232_OhmsRatiometric(ADS1232_t *dev, float r_ref_ohms,
                                          uint16_t n, float *ohms,
                                          uint32_t timeout_ms)
{
  int64_t acc = 0;
  uint16_t i;

  if (dev == NULL || ohms == NULL || n == 0U)
  {
    return HAL_ERROR;
  }

  for (i = 0U; i < n; i++)
  {
    int32_t code;
    if (ads1232_read_retry(dev, &code, timeout_ms) != HAL_OK)
    {
      return HAL_ERROR;
    }
    acc += code;
  }

  *ohms = (r_ref_ohms * (float)((acc / (int64_t)n) - dev->offset_code))
          / ((float)ADS1232_GainValue(dev->cfg.gain) * 8388608.0f);

  return HAL_OK;
}

/**
  * @brief  Trigger the device offset calibration (extra SCLK pulses).
  * @note   VERIFY the pulse count against Datasheet/ads1232.pdf before relying
  *         on this. ADS1232_Tare() is a software equivalent that needs no
  *         datasheet confirmation and is the safer choice for now.
  * @param  dev        : [in] instance; must be non-NULL.
  * @param  timeout_ms : [in] data-ready timeout.
  * @retval HAL_OK on success, HAL_ERROR if @p dev is NULL, else propagated.
  */
HAL_StatusTypeDef ADS1232_Calibrate(ADS1232_t *dev, uint32_t timeout_ms)
{
  HAL_StatusTypeDef st;
  int32_t discard;
  uint8_t i;

  if (dev == NULL)
  {
    return HAL_ERROR;
  }

  /* Read and throw away one conversion so we are aligned to a frame boundary. */
  st = ADS1232_ReadRaw(dev, &discard, timeout_ms);
  if (st != HAL_OK)
  {
    return st;
  }

  /* VERIFY: additional pulses beyond the 24 data bits request calibration on
   * this family. Pulse count is datasheet-dependent - confirm before use. */
  for (i = 0U; i < 2U; i++)
  {
    (void)ads1232_clock_bit(dev);
  }

  /* Calibration takes several conversion periods; at 10 SPS allow ~4 of them. */
  HAL_Delay(500U);
  return HAL_OK;
}

/**
  * @brief  Numeric gain (1, 2, 64, 128) for a gain enum.
  * @param  g : [in] gain enumeration.
  * @retval The numeric gain; 1 for an unrecognised value.
  */
uint16_t ADS1232_GainValue(ADS1232_Gain_t g)
{
  switch (g)
  {
    case ADS1232_GAIN_2:   return 2U;
    case ADS1232_GAIN_64:  return 64U;
    case ADS1232_GAIN_128: return 128U;
    case ADS1232_GAIN_1:
    default:               return 1U;
  }
}

/* -------------------------------------------------------------------------- */
/* NUCLEO-G474RE bench rig                                                    */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Configure the three Nucleo GPIOs and bring the rig up.
  * @note   PA1 = SCLK (output, parked LOW - a high SCLK requests power-down),
  *         PA4 = DOUT/DRDY (input), PC1 = PDWN (output, driven high).
  *         GAIN0/GAIN1/SPEED/A0 are strapped on the board and are left NULL in
  *         the config so the driver never drives them.
  * @retval HAL status from ADS1232_Init().
  */
HAL_StatusTypeDef ADS1232_HwInit_Nucleo(void)
{
  GPIO_InitTypeDef gpio = {0};
  ADS1232_Cfg_t    cfg  = {0};

  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_GPIOC_CLK_ENABLE();

  /* SCLK: push-pull output, parked low BEFORE it is driven anywhere else. */
  HAL_GPIO_WritePin(ADS1232_SCLK_PORT, ADS1232_SCLK_PIN, GPIO_PIN_RESET);
  gpio.Pin   = ADS1232_SCLK_PIN;
  gpio.Mode  = GPIO_MODE_OUTPUT_PP;
  gpio.Pull  = GPIO_NOPULL;
  gpio.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(ADS1232_SCLK_PORT, &gpio);

  /* PDWN: push-pull output, start asleep then Init() wakes it. */
  HAL_GPIO_WritePin(ADS1232_PDWN_PORT, ADS1232_PDWN_PIN, GPIO_PIN_RESET);
  gpio.Pin = ADS1232_PDWN_PIN;
  HAL_GPIO_Init(ADS1232_PDWN_PORT, &gpio);

  /* DOUT/DRDY: plain input. The ADS1232 drives it push-pull, so no pull. */
  gpio.Pin  = ADS1232_DOUT_PIN;
  gpio.Mode = GPIO_MODE_INPUT;
  gpio.Pull = GPIO_NOPULL;
  HAL_GPIO_Init(ADS1232_DOUT_PORT, &gpio);

  cfg.sclk.port = ADS1232_SCLK_PORT;  cfg.sclk.pin = ADS1232_SCLK_PIN;
  cfg.dout.port = ADS1232_DOUT_PORT;  cfg.dout.pin = ADS1232_DOUT_PIN;
  cfg.pdwn.port = ADS1232_PDWN_PORT;  cfg.pdwn.pin = ADS1232_PDWN_PIN;
  /* gain0/gain1/speed/a0 stay NULL - strapped on the board. */

  /* MUST match the straps. GAIN0 and GAIN1 are both pulled up = gain 128. */
  cfg.gain    = ADS1232_GAIN_128;
  cfg.rate    = ADS1232_RATE_10SPS;
  cfg.channel = ADS1232_CH_AIN1;
  cfg.vref    = 2.0f;   /* only used by ReadVolts(); ratiometric ignores it */

  return ADS1232_Init(&g_ads1232, &cfg);
}

/**
  * @brief  Startup self-check: confirm DRDY is toggling, then tare.
  * @note   At 10 SPS a conversion lands every ~100 ms, so a 500 ms timeout is
  *         generous. Failure here is nearly always SCLK parked high, PDWN low,
  *         or DOUT not actually connected.
  * @retval HAL_OK      device converting and offset captured.
  * @retval HAL_TIMEOUT DRDY never fell.
  */
HAL_StatusTypeDef ADS1232_BenchSelfCheck(void)
{
  HAL_StatusTypeDef st;
  int32_t code = 0;

  st = ADS1232_WaitReady(&g_ads1232, 500U);
  if (st != HAL_OK)
  {
    LOG_E("ADS", "DRDY never fell - check SCLK low, PDWN high, DOUT wired");
    return st;
  }

  st = ads1232_read_retry(&g_ads1232, &code, 500U);
  if (st != HAL_OK)
  {
    return st;
  }
  LOG_I("ADS", "alive, first code=%ld", (long)code);

  /* Near full scale with the inputs shorted means they are not actually
   * shorted - at gain 128 a floating pair rails. */
  if (labs((long)code) > 8000000L)
  {
    LOG_W("ADS", "code near full scale - sense inputs open, not shorted?");
  }

  st = ADS1232_Tare(&g_ads1232, 16U, 500U);
  if (st == HAL_OK)
  {
    LOG_I("ADS", "tare offset=%ld", (long)g_ads1232.offset_code);
  }
  return st;
}

/**
  * @brief  Take one averaged ratiometric reading and log it.
  * @note   Prints scaled integers, not floats: the build links newlib-nano
  *         without -u _printf_float, so "%f" would emit nothing.
  * @retval None
  */
void ADS1232_BenchOnce(void)
{
  int32_t codes[ADS1232_BENCH_AVG];
  int64_t acc = 0;
  int32_t mn, mx, median, trimmed;
  float   ohms;
  uint16_t i;

  s_retries = 0U;

  /* Take ONE set of samples and derive everything from it. Reporting a code
   * and a resistance from different reads (as this did originally) makes a
   * misbehaving rig much harder to diagnose - they never correlate. */
  for (i = 0U; i < (uint16_t)ADS1232_BENCH_AVG; i++)
  {
    if (ads1232_read_retry(&g_ads1232, &codes[i], 500U) != HAL_OK)
    {
      LOG_E("ADS", "read timeout - DRDY stopped");
      return;
    }
    acc += codes[i];
  }

  (void)acc;

  /* Sort so we can report robust statistics. A flaky SCLK produces occasional
   * badly-corrupted samples; the mean is dragged around by them but the median
   * is not. Comparing full spread against the trimmed (middle-half) spread
   * separates the two causes:
   *   trimmed << spread  -> a few wild outliers  -> LINK corruption
   *   trimmed ~= spread  -> the whole population is noisy -> ANALOG problem  */
  ads1232_sort(codes, (uint16_t)ADS1232_BENCH_AVG);

  mn     = codes[0];
  mx     = codes[ADS1232_BENCH_AVG - 1U];
  median = codes[ADS1232_BENCH_AVG / 2U];
  trimmed = codes[(ADS1232_BENCH_AVG * 3U) / 4U] - codes[ADS1232_BENCH_AVG / 4U];

  /* Median, not mean - robust against the outliers a bad joint produces. */
  ohms = (ADS1232_BENCH_RREF_OHMS * (float)(median - g_ads1232.offset_code))
         / ((float)ADS1232_GainValue(g_ads1232.cfg.gain) * 8388608.0f);

  LOG_I("ADS", "med=%ld spread=%ld trimmed=%ld retries=%u R=%ld uOhm",
        (long)median, (long)(mx - mn), (long)trimmed,
        (unsigned)s_retries, (long)(ohms * 1000000.0f));

  /* Interpretation. retries counts samples the link forced us to re-read, so it
   * separates the two causes far more reliably than spread shape does - a
   * roughly 50/50 corruption makes outliers look like a broad population and
   * fools any purely statistical test. */
  if (s_retries > (uint16_t)ADS1232_BENCH_AVG)
  {
    LOG_W("ADS", "  retries=%u high -> LINK still bad, solder the SCLK joint",
          (unsigned)s_retries);
  }
  else if ((mx - mn) > 10000L)
  {
    LOG_W("ADS", "  link ok but noisy -> ANALOG: check REFP/REFN, AINP1/AINN1, AVDD");
  }
  else
  {
    LOG_I("ADS", "  stable");
  }
}

/**
  * @brief  Measure link quality: attempt @p n reads and report the success rate.
  * @note   For chasing an intermittent joint. ADS1232_ReadRaw() fails when the
  *         device does not release DOUT, so the pass rate is a direct measure of
  *         connection quality. Solder or wiggle the suspect wire and watch the
  *         percentage - 100%% means the link is solid.
  * @param  n : [in] attempts to make; must be non-zero.
  * @retval Percentage of successful reads (0..100).
  */
uint8_t ADS1232_BenchLinkTest(uint16_t n)
{
  uint16_t ok = 0U, i;
  int32_t  code;
  uint8_t  pct;

  if (n == 0U)
  {
    return 0U;
  }

  for (i = 0U; i < n; i++)
  {
    if (ADS1232_ReadRaw(&g_ads1232, &code, 300U) == HAL_OK)
    {
      ok++;
    }
  }

  pct = (uint8_t)(((uint32_t)ok * 100U) / (uint32_t)n);
  LOG_I("ADS", "link: %u/%u reads ok (%u%%)",
        (unsigned)ok, (unsigned)n, (unsigned)pct);

  if (pct == 100U)
  {
    LOG_I("ADS", "  link solid");
  }
  else if (pct == 0U)
  {
    LOG_E("ADS", "  link dead - SCLK not connected");
  }
  else
  {
    LOG_W("ADS", "  INTERMITTENT - bad joint. Solder it, do not hold the wire");
  }
  return pct;
}

/**
  * @brief  Slowly toggle SCLK and PDWN so they can be metered at the header.
  * @note   Bisects "MCU is not driving the pin" from "the wire is broken". Put a
  *         meter on Arduino A1 (PA1) and A4 (PC1): both must swing 0 <-> 3V3 at
  *         1 Hz. If they swing at the header but the ADC still does not respond,
  *         the fault is the wire or the ADC end, not the firmware.
  *         Uses HAL_Delay deliberately - the project has a TIM-based HAL
  *         timebase, so this works regardless of the scheduler, and a blocking
  *         delay keeps the toggling regular while someone holds a probe.
  *         Leaves SCLK parked LOW on exit.
  * @param  seconds : [in] how long to toggle for.
  * @retval None
  */
void ADS1232_BenchPinTest(uint32_t seconds)
{
  uint32_t i;
  uint8_t  rb_hi, rb_lo;

  /* ---- Readback check: no meter required -------------------------------- */
  /* A push-pull output's IDR reflects the ACTUAL pin voltage. Drive it high
   * and low and read it back. If it does not follow, either the pin is not
   * configured as an output, or something external is holding it - which
   * settles "firmware fault" vs "wiring fault" without any test gear. */
  HAL_GPIO_WritePin(ADS1232_SCLK_PORT, ADS1232_SCLK_PIN, GPIO_PIN_SET);
  ads1232_delay(200U);
  rb_hi = (HAL_GPIO_ReadPin(ADS1232_SCLK_PORT, ADS1232_SCLK_PIN) == GPIO_PIN_SET) ? 1U : 0U;

  HAL_GPIO_WritePin(ADS1232_SCLK_PORT, ADS1232_SCLK_PIN, GPIO_PIN_RESET);
  ads1232_delay(200U);
  rb_lo = (HAL_GPIO_ReadPin(ADS1232_SCLK_PORT, ADS1232_SCLK_PIN) == GPIO_PIN_SET) ? 1U : 0U;

  LOG_I("ADS", "SCLK readback: drove 1 -> read %u, drove 0 -> read %u",
        (unsigned)rb_hi, (unsigned)rb_lo);

  if (rb_hi == 1U && rb_lo == 0U)
  {
    LOG_I("ADS", "  SCLK pin IS driving correctly -> fault is the WIRE or the ADC end");
  }
  else if (rb_hi == 0U && rb_lo == 0U)
  {
    LOG_E("ADS", "  SCLK stuck LOW - shorted to GND, or pin not configured as output");
  }
  else
  {
    LOG_E("ADS", "  SCLK stuck HIGH - shorted to 3V3");
  }

  LOG_W("ADS", "pin test: SCLK + PDWN toggling 1 Hz for %lu s",
        (unsigned long)seconds);
  LOG_W("ADS", "meter PA1 at Arduino A1, PC1 at A4 - both must swing 0<->3V3");

  for (i = 0U; i < seconds; i++)
  {
    HAL_GPIO_WritePin(ADS1232_SCLK_PORT, ADS1232_SCLK_PIN, GPIO_PIN_SET);
    HAL_GPIO_WritePin(ADS1232_PDWN_PORT, ADS1232_PDWN_PIN, GPIO_PIN_SET);
    HAL_Delay(500U);
    HAL_GPIO_WritePin(ADS1232_SCLK_PORT, ADS1232_SCLK_PIN, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(ADS1232_PDWN_PORT, ADS1232_PDWN_PIN, GPIO_PIN_RESET);
    HAL_Delay(500U);
  }

  /* Park SCLK low and PDWN high (awake) again. */
  HAL_GPIO_WritePin(ADS1232_SCLK_PORT, ADS1232_SCLK_PIN, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(ADS1232_PDWN_PORT, ADS1232_PDWN_PIN, GPIO_PIN_SET);
  LOG_I("ADS", "pin test done, SCLK parked low");
}

/**
  * @brief  Decisive wiring diagnostic. Run this when the numbers look like noise.
  * @note   Watches DOUT WITHOUT clocking it. Left alone, DOUT must start high
  *         and fall once when a conversion completes, then stay low until the
  *         data is clocked out. Anything else localises the fault immediately:
  *
  *           stuck HIGH  -> not powered, PDWN low, or DOUT not connected
  *           stuck LOW   -> DOUT shorted low
  *           many edges  -> pin is FLOATING (the classic all-ones / noise case)
  *           one edge    -> device is converting; wiring to this point is good
  * @retval None
  */
void ADS1232_BenchDiag(void)
{
  uint32_t hi = 0U, lo = 0U, edges = 0U;
  uint8_t  prev, now, after;
  uint32_t start;
  int32_t  code = 0;
  uint8_t  i;

  /* ---- Test 1: does the ADC respond to SCLK at all? ---------------------- */
  /* This is the decisive one. DOUT low means "data ready". After 24 SCLK
   * pulses a working device has shifted its result out and released DOUT
   * HIGH. If DOUT is still low afterwards, the device never saw the clock -
   * which reads back as code = 0 (all 24 bits sampled low). */
  LOG_I("ADS", "diag 1: SCLK response");
  if (ADS1232_WaitReady(&g_ads1232, 500U) != HAL_OK)
  {
    LOG_E("ADS", "  DOUT never went low - no AVDD/DVDD, PDWN low, or DOUT unwired");
  }
  else
  {
    for (i = 0U; i < 24U; i++)
    {
      code = (code << 1) | (int32_t)ads1232_clock_bit(&g_ads1232);
    }
    after = (HAL_GPIO_ReadPin(ADS1232_DOUT_PORT, ADS1232_DOUT_PIN) == GPIO_PIN_SET) ? 1U : 0U;

    if (after == 0U)
    {
      LOG_E("ADS", "  DOUT STILL LOW after 24 clocks - SCLK is not reaching the ADC");
      LOG_E("ADS", "  check the PA1 wire; this is what makes code read exactly 0");
    }
    else
    {
      LOG_I("ADS", "  DOUT released after 24 clocks - SCLK path OK (code=%ld)",
            (long)code);
    }
  }

  /* ---- Test 2: is it converting at the expected rate? -------------------- */
  /* Having just clocked a result out, DOUT should now be HIGH and fall again
   * when the next conversion lands - about 100 ms at 10 SPS. */
  LOG_I("ADS", "diag 2: watching DOUT 300 ms, not clocking");

  prev = (HAL_GPIO_ReadPin(ADS1232_DOUT_PORT, ADS1232_DOUT_PIN) == GPIO_PIN_SET) ? 1U : 0U;
  start = HAL_GetTick();
  while ((HAL_GetTick() - start) < 300U)
  {
    now = (HAL_GPIO_ReadPin(ADS1232_DOUT_PORT, ADS1232_DOUT_PIN) == GPIO_PIN_SET) ? 1U : 0U;
    if (now != 0U) { hi++; } else { lo++; }
    if (now != prev) { edges++; prev = now; }
  }

  LOG_I("ADS", "  hi=%lu lo=%lu edges=%lu",
        (unsigned long)hi, (unsigned long)lo, (unsigned long)edges);

  if (edges > 50U)
  {
    LOG_E("ADS", "  DOUT FLOATING (%lu edges) - loose wire, not driven",
          (unsigned long)edges);
  }
  else if (edges == 0U && lo == 0U)
  {
    LOG_E("ADS", "  DOUT stuck HIGH - no conversion completing");
  }
  else if (edges >= 1U)
  {
    LOG_I("ADS", "  DOUT fell once - device is converting normally");
  }
  else
  {
    /* All low with no edge: data was already pending when we started. Normal
     * if a conversion completed between the two tests. */
    LOG_I("ADS", "  DOUT low throughout - data pending, acceptable");
  }
}

#endif /* HT_ENABLE_ADS1232 */
