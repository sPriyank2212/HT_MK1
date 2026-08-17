/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    ds18b20.c
  * @brief   DS18B20 1-Wire driver implementation. See ds18b20.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "drivers/ds18b20.h"

/* -------------------------------------------------------------------------- */
/* Microsecond delay - DWT cycle counter                                      */
/* -------------------------------------------------------------------------- */

/* HCLK = 64 MHz (main.c SystemClock_Config: HSI -> PLL, "64 MHz SYSCLK"
 * comment there) -> 64 cycles per microsecond. A NOP-loop guess (the pattern
 * ads1232.c uses on its own bench rig) is not precise enough for 1-Wire's
 * 1-6 us write/read slot edges; the DWT cycle counter is exact against the
 * known, fixed core clock instead. */
#define DS18B20_CYCLES_PER_US   64U

static void ds18b20_dwt_init(void)
{
  static uint8_t s_inited = 0U;

  if (s_inited == 0U)
  {
    CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
    DWT->CYCCNT       = 0U;
    DWT->CTRL        |= DWT_CTRL_CYCCNTENA_Msk;
    s_inited = 1U;
  }
}

/**
  * @brief  Busy-wait for at least @p us microseconds.
  * @note   Unsigned subtraction against a free-running counter wraps
  *         correctly even across a DWT->CYCCNT overflow.
  */
static void ds18b20_delay_us(uint32_t us)
{
  uint32_t start  = DWT->CYCCNT;
  uint32_t cycles = us * DS18B20_CYCLES_PER_US;

  while ((DWT->CYCCNT - start) < cycles)
  {
    __NOP();
  }
}

/* -------------------------------------------------------------------------- */
/* Bus primitives - open-drain: SET = released (pulled high by R2), RESET =   */
/* driven low. Standard (non-overdrive) 1-Wire slot times, Maxim AN126.       */
/* -------------------------------------------------------------------------- */

#define DS18B20_T_RSTL_US       480U   /* reset low pulse                    */
#define DS18B20_T_PDSAMPLE_US    70U   /* release -> sample the presence pulse */
#define DS18B20_T_RSTH_US       410U   /* rest of the reset/presence slot    */

#define DS18B20_T_W1LOW_US        6U   /* write '1': low pulse               */
#define DS18B20_T_W0LOW_US       60U   /* write '0': low pulse               */
#define DS18B20_T_WSLOT_US       66U   /* total write slot (either bit)      */

#define DS18B20_T_RINIT_US        6U   /* read: initiating low pulse         */
#define DS18B20_T_RSAMPLE_US       9U   /* read: release -> sample            */
#define DS18B20_T_RSLOT_US        55U   /* rest of the read slot              */

static void ds18b20_low(const DS18B20_t *dev)
{
  HAL_GPIO_WritePin(dev->port, dev->pin, GPIO_PIN_RESET);
}

static void ds18b20_release(const DS18B20_t *dev)
{
  HAL_GPIO_WritePin(dev->port, dev->pin, GPIO_PIN_SET);
}

static uint8_t ds18b20_sample(const DS18B20_t *dev)
{
  return (HAL_GPIO_ReadPin(dev->port, dev->pin) == GPIO_PIN_SET) ? 1U : 0U;
}

/**
  * @brief  Reset pulse and presence detect.
  * @retval HAL_OK the sensor pulled the bus low (present), HAL_TIMEOUT it did not.
  */
static HAL_StatusTypeDef ds18b20_reset_presence(const DS18B20_t *dev)
{
  uint8_t present;

  ds18b20_low(dev);
  ds18b20_delay_us(DS18B20_T_RSTL_US);
  ds18b20_release(dev);
  ds18b20_delay_us(DS18B20_T_PDSAMPLE_US);
  present = (ds18b20_sample(dev) == 0U) ? 1U : 0U;   /* device pulls low = present */
  ds18b20_delay_us(DS18B20_T_RSTH_US);

  return (present != 0U) ? HAL_OK : HAL_TIMEOUT;
}

static void ds18b20_write_bit(const DS18B20_t *dev, uint8_t bit)
{
  ds18b20_low(dev);
  if (bit != 0U)
  {
    ds18b20_delay_us(DS18B20_T_W1LOW_US);
    ds18b20_release(dev);
    ds18b20_delay_us(DS18B20_T_WSLOT_US - DS18B20_T_W1LOW_US);
  }
  else
  {
    ds18b20_delay_us(DS18B20_T_W0LOW_US);
    ds18b20_release(dev);
    ds18b20_delay_us(DS18B20_T_WSLOT_US - DS18B20_T_W0LOW_US);
  }
}

static uint8_t ds18b20_read_bit(const DS18B20_t *dev)
{
  uint8_t bit;

  ds18b20_low(dev);
  ds18b20_delay_us(DS18B20_T_RINIT_US);
  ds18b20_release(dev);
  ds18b20_delay_us(DS18B20_T_RSAMPLE_US);
  bit = ds18b20_sample(dev);
  ds18b20_delay_us(DS18B20_T_RSLOT_US);

  return bit;
}

/* 1-Wire transmits/receives LSB first. */
static void ds18b20_write_byte(const DS18B20_t *dev, uint8_t v)
{
  uint8_t i;

  for (i = 0U; i < 8U; i++)
  {
    ds18b20_write_bit(dev, (uint8_t)(v & 0x01U));
    v = (uint8_t)(v >> 1);
  }
}

static uint8_t ds18b20_read_byte(const DS18B20_t *dev)
{
  uint8_t i, v = 0U;

  for (i = 0U; i < 8U; i++)
  {
    v = (uint8_t)(v >> 1);
    if (ds18b20_read_bit(dev) != 0U)
    {
      v |= 0x80U;
    }
  }
  return v;
}

/**
  * @brief  Maxim/Dallas 1-Wire CRC8 (poly x^8+x^5+x^4+1, reflected 0x8C).
  * @note   Running this over the scratchpad bytes PLUS the received CRC byte
  *         itself yields 0 when the data is clean - the check used below.
  */
static uint8_t ds18b20_crc8(const uint8_t *data, uint8_t len)
{
  uint8_t crc = 0U;
  uint8_t i, j;

  for (i = 0U; i < len; i++)
  {
    uint8_t inbyte = data[i];
    for (j = 0U; j < 8U; j++)
    {
      uint8_t mix = (uint8_t)((crc ^ inbyte) & 0x01U);
      crc = (uint8_t)(crc >> 1);
      if (mix != 0U)
      {
        crc ^= 0x8CU;
      }
      inbyte = (uint8_t)(inbyte >> 1);
    }
  }
  return crc;
}

/* -------------------------------------------------------------------------- */
/* Commands                                                                   */
/* -------------------------------------------------------------------------- */

#define DS18B20_CMD_SKIP_ROM       0xCCU
#define DS18B20_CMD_CONVERT_T      0x44U
#define DS18B20_CMD_READ_SCRATCH   0xBEU

/* Worst case at the sensor's default 12-bit power-on resolution. */
#define DS18B20_CONVERT_MS         750U

#define DS18B20_SCRATCHPAD_LEN     9U

/* -------------------------------------------------------------------------- */
/* API                                                                        */
/* -------------------------------------------------------------------------- */

HAL_StatusTypeDef DS18B20_Init(DS18B20_t *dev, GPIO_TypeDef *port, uint16_t pin)
{
  if (dev == NULL || port == NULL)
  {
    return HAL_ERROR;
  }

  dev->port = port;
  dev->pin  = pin;

  ds18b20_dwt_init();
  ds18b20_release(dev);   /* idle released - the bus is pulled high by R2 */

  return HAL_OK;
}

HAL_StatusTypeDef DS18B20_ReadTemperature(DS18B20_t *dev, float *celsius)
{
  uint8_t sp[DS18B20_SCRATCHPAD_LEN];
  uint8_t i;
  int16_t raw;
  HAL_StatusTypeDef st;

  if (dev == NULL || celsius == NULL)
  {
    return HAL_ERROR;
  }

  st = ds18b20_reset_presence(dev);
  if (st != HAL_OK)
  {
    return st;
  }
  ds18b20_write_byte(dev, DS18B20_CMD_SKIP_ROM);
  ds18b20_write_byte(dev, DS18B20_CMD_CONVERT_T);

  /* Externally-powered assumption (see file header) - a fixed worst-case wait
   * rather than busy-bit polling, which needs a strong parasitic pull-up
   * during conversion that is not assumed present here. */
  HAL_Delay(DS18B20_CONVERT_MS);

  st = ds18b20_reset_presence(dev);
  if (st != HAL_OK)
  {
    return st;
  }
  ds18b20_write_byte(dev, DS18B20_CMD_SKIP_ROM);
  ds18b20_write_byte(dev, DS18B20_CMD_READ_SCRATCH);
  for (i = 0U; i < DS18B20_SCRATCHPAD_LEN; i++)
  {
    sp[i] = ds18b20_read_byte(dev);
  }

  if (ds18b20_crc8(sp, DS18B20_SCRATCHPAD_LEN) != 0U)
  {
    return HAL_ERROR;
  }

  /* Scratchpad bytes 0-1 = temperature LSB/MSB, 12-bit default resolution,
   * 0.0625 degC per count, two's complement. */
  raw      = (int16_t)((uint16_t)sp[0] | ((uint16_t)sp[1] << 8));
  *celsius = (float)raw * 0.0625f;

  return HAL_OK;
}
