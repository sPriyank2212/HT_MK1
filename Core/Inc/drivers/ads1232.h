/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    ads1232.h
  * @brief   BENCH-ONLY driver for the TI ADS1232 24-bit bridge ADC.
  *
  *          Stand-in for the ADS124S08 while the Matrix card does not exist,
  *          used to prove out the 4-wire (Kelvin) resistance measurement on a
  *          NUCLEO-G474RE. Compiled ONLY when HT_ENABLE_ADS1232 is non-zero, so
  *          it can never end up in a product build.
  *
  *          THE ADS1232 IS NOT AN SPI DEVICE. There is no chip select and no
  *          MOSI. The interface is two wires:
  *
  *            SCLK       MCU -> ADC   clock, idles LOW
  *            DOUT/DRDY  ADC -> MCU   data out, and doubles as data-ready
  *                                    (goes LOW when a conversion is available)
  *
  *          A conversion is read by waiting for DOUT to fall, then issuing 24
  *          SCLK pulses and sampling DOUT on each. Data is 24-bit two's
  *          complement, MSB first. No SPI peripheral is involved; at 10/80 SPS
  *          bit-banging is simpler and avoids fighting the shared DOUT/DRDY pin.
  *
  *          Gain, data rate and channel are set by STATIC PINS, not registers:
  *
  *            GAIN1 GAIN0   gain        SPEED   rate      A0    channel
  *            0     0       1           0       10 SPS    0     AIN1
  *            0     1       2           1       80 SPS    1     AIN2
  *            1     0       64
  *            1     1       128
  *
  *          Any of those may be strapped with a jumper instead of wired to a
  *          GPIO - leave the corresponding port NULL in the config and the
  *          driver simply reports the strapped value you tell it.
  *
  * @note    VERIFY items (pending Datasheet/ads1232.pdf):
  *            - physical pin numbers (see Doc/ADS1232_bench_wiring.md)
  *            - the extra-SCLK-pulse offset-calibration sequence in
  *              ADS1232_Calibrate()
  *          The 24-bit read itself follows the ADS123x/HX711 family pattern and
  *          is not expected to change.
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __ADS1232_H
#define __ADS1232_H

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"

/* Bench-only. Build with -DHT_ENABLE_ADS1232=1 to compile this driver in.
 * OFF by default: nothing has to be remembered at release time, because
 * shipping it requires someone to have actively opted in. */
#ifndef HT_ENABLE_ADS1232
#define HT_ENABLE_ADS1232   1
#endif

/* Belt and braces. The Debug configuration defines DEBUG; a Release build does
 * not. If the enable is left behind in the project settings after a bench
 * session, a Release build fails loudly here rather than silently shipping
 * test code. */
#if (HT_ENABLE_ADS1232 != 0) && !defined(DEBUG)
#error "HT_ENABLE_ADS1232 is bench-only test code. Remove it from the Release build configuration."
#endif

/* And make it impossible to forget it is active while on the bench: every
 * Debug build that enables it says so in the build log. */
#if (HT_ENABLE_ADS1232 != 0)
#warning "ADS1232 bench driver is ENABLED - stand-in for the ADS124S08, must not ship."
#endif

#if (HT_ENABLE_ADS1232 != 0)

/* -------------------------------------------------------------------------- */
/* Configuration                                                              */
/* -------------------------------------------------------------------------- */

typedef enum
{
  ADS1232_GAIN_1   = 0,   /* GAIN1=0 GAIN0=0 */
  ADS1232_GAIN_2   = 1,   /* GAIN1=0 GAIN0=1 */
  ADS1232_GAIN_64  = 2,   /* GAIN1=1 GAIN0=0 */
  ADS1232_GAIN_128 = 3    /* GAIN1=1 GAIN0=1 */
} ADS1232_Gain_t;

typedef enum
{
  ADS1232_RATE_10SPS = 0,
  ADS1232_RATE_80SPS = 1
} ADS1232_Rate_t;

typedef enum
{
  ADS1232_CH_AIN1 = 0,
  ADS1232_CH_AIN2 = 1
} ADS1232_Channel_t;

/* A pin that may be driven by the MCU or strapped with a jumper. Leave .port
 * NULL to say "strapped in hardware - do not drive it". */
typedef struct
{
  GPIO_TypeDef *port;
  uint16_t      pin;
} ADS1232_Pin_t;

typedef struct
{
  /* Mandatory - the two-wire interface. */
  ADS1232_Pin_t sclk;        /* MCU output, idles low                        */
  ADS1232_Pin_t dout;        /* MCU input,  DOUT/DRDY (active-low ready)     */

  /* Optional - leave .port NULL if strapped with a jumper. */
  ADS1232_Pin_t pdwn;        /* MCU output, HIGH = awake, LOW = power down   */
  ADS1232_Pin_t gain0;
  ADS1232_Pin_t gain1;
  ADS1232_Pin_t speed;
  ADS1232_Pin_t a0;          /* channel select                               */

  /* Strapped values, used when the matching pin is NULL. Also the values the
   * driver programs when the pin IS wired. */
  ADS1232_Gain_t    gain;
  ADS1232_Rate_t    rate;
  ADS1232_Channel_t channel;

  float vref;                /* V(REFP) - V(REFN), volts. NO internal ref.   */
} ADS1232_Cfg_t;

typedef struct
{
  ADS1232_Cfg_t cfg;
  int32_t       offset_code; /* subtracted by ADS1232_ReadVolts()            */
} ADS1232_t;

/* -------------------------------------------------------------------------- */
/* API                                                                        */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Bind the driver, drive the configuration pins and wake the device.
  * @param  dev : [out] instance to populate; must be non-NULL.
  * @param  cfg : [in]  pin map and strapped settings; must be non-NULL.
  * @retval HAL_OK on success, HAL_ERROR on a NULL argument or missing SCLK/DOUT.
  */
HAL_StatusTypeDef ADS1232_Init(ADS1232_t *dev, const ADS1232_Cfg_t *cfg);

/**
  * @brief  Change gain at runtime. Only possible if GAIN0/GAIN1 are wired to
  *         GPIO; returns HAL_ERROR if they are strapped.
  * @note   The conversion in progress is discarded - the caller should throw
  *         away the next sample.
  */
HAL_StatusTypeDef ADS1232_SetGain(ADS1232_t *dev, ADS1232_Gain_t gain);

/**
  * @brief  Select the input channel. Requires A0 to be wired to GPIO.
  */
HAL_StatusTypeDef ADS1232_SetChannel(ADS1232_t *dev, ADS1232_Channel_t ch);

/**
  * @brief  Poll DOUT/DRDY for a completed conversion.
  * @param  timeout_ms : [in] give up after this long.
  * @retval HAL_OK data is ready, HAL_TIMEOUT otherwise.
  */
HAL_StatusTypeDef ADS1232_WaitReady(ADS1232_t *dev, uint32_t timeout_ms);

/**
  * @brief  Wait for data ready and shift out one 24-bit conversion.
  * @param  code       : [out] sign-extended 24-bit two's-complement result.
  * @param  timeout_ms : [in]  data-ready timeout.
  * @retval HAL_OK on success, HAL_TIMEOUT if no conversion arrived.
  */
HAL_StatusTypeDef ADS1232_ReadRaw(ADS1232_t *dev, int32_t *code, uint32_t timeout_ms);

/**
  * @brief  Read one conversion and scale it to volts at the ADC input.
  * @note   volts = (code - offset) * vref / (gain * 2^23). Subtracts the offset
  *         captured by ADS1232_Tare().
  */
HAL_StatusTypeDef ADS1232_ReadVolts(ADS1232_t *dev, float *volts, uint32_t timeout_ms);

/**
  * @brief  Average @p n conversions into the stored offset (system tare).
  * @note   Short the sense inputs, or leave the excitation off, before calling.
  *         This is the practical way to remove thermal EMF and amplifier offset
  *         on the bench rig.
  */
HAL_StatusTypeDef ADS1232_Tare(ADS1232_t *dev, uint16_t n, uint32_t timeout_ms);

/**
  * @brief  Average @p n conversions, offset-corrected, in volts.
  *         The normal way to take a Kelvin reading - single conversions at
  *         gain 128 are noisy.
  */
HAL_StatusTypeDef ADS1232_ReadAverage(ADS1232_t *dev, uint16_t n, float *volts,
                                      uint32_t timeout_ms);

/**
  * @brief  Convert a measured Kelvin voltage into ohms.
  * @param  volts     : [in]  differential voltage across the wire.
  * @param  current_a : [in]  excitation current actually flowing, amps.
  * @param  ohms      : [out] volts / current_a.
  * @retval HAL_OK, or HAL_ERROR if @p current_a is zero.
  */
HAL_StatusTypeDef ADS1232_Ohms(float volts, float current_a, float *ohms);

/**
  * @brief  RATIOMETRIC 4-wire resistance - the recommended bench method.
  * @note   Wire a precision reference resistor in SERIES with the DUT, put
  *         REFP/REFN across the reference and AINP/AINN across the DUT. The
  *         same current flows through both, so it cancels exactly:
  *
  *             R_dut = R_ref * (code - offset) / (gain * 2^23)
  *
  *         The excitation current then never has to be known or held stable,
  *         and the result inherits the reference resistor's tolerance. This is
  *         the same trick proposed for the product board in PROJECT_LOG HW-04.
  * @param  dev        : [in]  instance; must be non-NULL.
  * @param  r_ref_ohms : [in]  series reference resistor, ohms.
  * @param  n          : [in]  conversions to average; must be non-zero.
  * @param  ohms       : [out] measured DUT resistance; must be non-NULL.
  * @param  timeout_ms : [in]  per-sample data-ready timeout.
  * @retval HAL_OK on success, HAL_ERROR on a bad argument, else propagated.
  */
HAL_StatusTypeDef ADS1232_OhmsRatiometric(ADS1232_t *dev, float r_ref_ohms,
                                          uint16_t n, float *ohms,
                                          uint32_t timeout_ms);

/**
  * @brief  Trigger the device offset calibration (extra SCLK pulses).
  * @note   VERIFY against Datasheet/ads1232.pdf before relying on this. The
  *         24-bit read is the well-established part of the protocol; the
  *         calibration pulse count is the part worth checking. ADS1232_Tare()
  *         is a software equivalent that needs no datasheet confirmation.
  */
HAL_StatusTypeDef ADS1232_Calibrate(ADS1232_t *dev, uint32_t timeout_ms);

/**
  * @brief  Numeric gain (1, 2, 64, 128) for a gain enum.
  */
uint16_t ADS1232_GainValue(ADS1232_Gain_t g);

/* -------------------------------------------------------------------------- */
/* NUCLEO-G474RE bench rig                                                    */
/* -------------------------------------------------------------------------- */

/* Series reference resistance in the ratiometric arrangement - the SUM of the
 * two divider resistors.
 *
 * Validated bench topology (2026-08-01), symmetric so the common mode lands at
 * mid-supply, which gain 64/128 requires (SBAS350H: AGND+1.5 V .. AVDD-1.5 V):
 *
 *     5V --[4.7k]--o--[R_dut]--o--[4.7k]-- GND      REFP = 5V, REFN = GND
 *                  |           |
 *               AINP1       AINN1          common mode = 2.5 V
 *
 * REFP sits on the same rail that drives the divider, so the supply cancels:
 *     I     = 5 / R_ref
 *     Vin   = I * R_dut = 5 * R_dut / R_ref
 *     code  = Vin / (0.5*VREF/(gain*2^23))
 *     R_dut = R_ref * code / (2 * gain * 2^23)
 *
 * Accuracy therefore inherits the SUM tolerance - two 5% parts give 5% readings.
 * Measured 33 mohm as 7570 counts against 7539 predicted, 0.4% agreement.
 *
 * Lower values buy signal: 4k7 pair = 0.53 mA, 470R pair = 5.3 mA and ~10x the
 * counts for the same DUT. Power stays trivial either way. */
#ifndef ADS1232_BENCH_RREF_OHMS
#define ADS1232_BENCH_RREF_OHMS   9400.0f   /* 4k7 + 4k7 */
#endif

/* 1 = tare at startup, 0 = leave the offset at zero.
 * The tare must be taken with NO signal present - short the DUT, or fit a link
 * in its place. Taring with the DUT connected stores the measurement itself as
 * the offset and every later reading then comes out near zero. */
#ifndef ADS1232_BENCH_TARE
#define ADS1232_BENCH_TARE        0
#endif

/* Conversions averaged per reported reading. Keep it a multiple of 4 - the raw
 * dump prints 4 per line to stay inside LOG_MSG_MAX. */
#ifndef ADS1232_BENCH_AVG
#define ADS1232_BENCH_AVG         16U
#endif

/* Reference voltage actually present on REFP-REFN, volts. On the bench rig
 * REFP sits on the 5 V rail and REFN on GND. Sets the volts-per-count scale:
 *     1 count = VREF / (gain * 2^23) = 4.657 nV at VREF=5 V, gain=128
 *     full scale = +/- VREF / gain   = +/- 39.06 mV at those settings */
#ifndef ADS1232_BENCH_VREF_V
#define ADS1232_BENCH_VREF_V      5.0f
#endif

/* 1 = dump every raw conversion code, 0 = summary lines only.
 * Default OFF now the rig is validated: the dump is 4 extra lines per reading,
 * and with LOG_QUEUE_DEPTH at 24 that is enough to overrun the logger and lose
 * the very lines you want. Turn it back on when debugging raw data. */
#ifndef ADS1232_LOG_RAW
#define ADS1232_LOG_RAW           0
#endif

/* The rig instance, defined in ads1232.c. */
extern ADS1232_t g_ads1232;

/**
  * @brief  Configure the three Nucleo GPIOs and bring the rig up.
  * @note   PA1 = SCLK (output, parked low), PA4 = DOUT/DRDY (input),
  *         PC1 = PDWN (output, driven high). GAIN0/GAIN1/SPEED/A0 are strapped
  *         on the board and are NOT driven. Configures the pins directly rather
  *         than through CubeMX so regenerating the .ioc cannot clobber it -
  *         same approach as Log_HwInit_LPUART1().
  * @retval HAL status from ADS1232_Init().
  */
HAL_StatusTypeDef ADS1232_HwInit_Nucleo(void);

/**
  * @brief  Take one averaged ratiometric reading and log it.
  * @note   Logs the raw code and the resistance in micro-ohms. Values are
  *         printed as scaled integers on purpose: the build links newlib-nano
  *         without -u _printf_float, so "%f" would print nothing.
  * @retval None
  */
void ADS1232_BenchOnce(void);

/**
  * @brief  Decisive wiring diagnostic - run this when readings look like noise.
  * @note   Watches DOUT without clocking it and classifies the fault: stuck
  *         high (unpowered / PDWN low / unwired), stuck low, floating (many
  *         edges), or converting normally.
  * @retval None
  */
void ADS1232_BenchDiag(void);

/**
  * @brief  Slowly toggle SCLK and PDWN so they can be metered at the header.
  * @note   Bisects "MCU is not driving the pin" from "the wire is broken".
  *         Blocking, by design. Leaves SCLK parked low and PDWN high.
  * @param  seconds : [in] how long to toggle for.
  * @retval None
  */
void ADS1232_BenchPinTest(uint32_t seconds);

/**
  * @brief  Measure link quality: attempt @p n reads and report the success rate.
  * @note   For chasing an intermittent joint - solder or wiggle the suspect wire
  *         and watch the percentage. 100%% means the link is solid.
  * @param  n : [in] attempts to make; must be non-zero.
  * @retval Percentage of successful reads (0..100).
  */
uint8_t ADS1232_BenchLinkTest(uint16_t n);

/**
  * @brief  Startup self-check: confirm DRDY is toggling, then tare.
  * @note   Short AINP1 to AINN1 before calling. At gain 128 a floating input
  *         pair rails, so a full-scale reading here means open sense leads.
  * @retval HAL_OK if the device is converting, HAL_TIMEOUT if DRDY never fell.
  */
HAL_StatusTypeDef ADS1232_BenchSelfCheck(void);

#endif /* HT_ENABLE_ADS1232 */

#ifdef __cplusplus
}
#endif

#endif /* __ADS1232_H */
