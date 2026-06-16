/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    matrix_card.c
  * @brief   Matrix Card control implementation. See matrix_card.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "cards/matrix_card.h"

/* All-open enable word for one bank (all 16 muxes disabled). */
#if (MATRIX_EN_ACTIVE_LOW != 0)
#define MATRIX_EN_ALL_OFF   0xFFFFU
#define MATRIX_EN_PATTERN(mux)   ((uint16_t)(0xFFFFU & ~(1U << (mux))))  /* one low */
#else
#define MATRIX_EN_ALL_OFF   0x0000U
#define MATRIX_EN_PATTERN(mux)   ((uint16_t)(1U << (mux)))               /* one high */
#endif

/* -------------------------------------------------------------------------- */
/* Pin -> (mux, channel) mapping                                              */
/*                                                                            */
/* Linear mapping: mux k (0..15) carries pins k*16+1 .. k*16+16, and within a  */
/* mux, channel c selects the (c+1)-th of those pins. If the PCB routes the    */
/* CD4067 I0..I15 inputs to harness pins in a different order, replace the     */
/* body of matrix_map_pin() with a lookup table -- nothing else changes.       */
/* -------------------------------------------------------------------------- */
static void matrix_map_pin(uint16_t pin, uint8_t *mux, uint8_t *channel)
{
  uint16_t idx = (uint16_t)(pin - 1U);   /* 0..255 */
  *mux     = (uint8_t)(idx >> 4);        /* 0..15  */
  *channel = (uint8_t)(idx & 0x0FU);     /* 0..15  */
}

/* Drive a bank's 4 shared select lines to 'channel'. NULL ports (not yet
 * wired) are skipped so the layer is usable before the connector is drawn. */
static void matrix_drive_select(const MatrixGpio_t sel[4], uint8_t channel)
{
  uint8_t b;
  for (b = 0U; b < 4U; b++)
  {
    if (sel[b].port != NULL)
    {
      GPIO_PinState s = ((channel >> b) & 0x01U) ? GPIO_PIN_SET : GPIO_PIN_RESET;
      HAL_GPIO_WritePin(sel[b].port, sel[b].pin, s);
    }
  }
}

static MCP23017_t *matrix_bank_dev(MatrixCard_t *m, MatrixBank_t bank)
{
  return (bank == MATRIX_BANK_HI) ? &m->hi_en : &m->lo_en;
}

static const MatrixGpio_t *matrix_bank_sel(MatrixCard_t *m, MatrixBank_t bank)
{
  return (bank == MATRIX_BANK_HI) ? m->sel.hi_sel : m->sel.lo_sel;
}

/* -------------------------------------------------------------------------- */

HAL_StatusTypeDef MatrixCard_Init(MatrixCard_t *m, I2C_HandleTypeDef *hi2c,
                                  const MatrixSelectMap_t *sel)
{
  HAL_StatusTypeDef st;

  if (m == NULL || hi2c == NULL || sel == NULL)
  {
    return HAL_ERROR;
  }

  m->sel = *sel;

  st = MCP23017_Init(&m->hi_en, hi2c, MATRIX_HI_MCP_STRAP);
  if (st != HAL_OK)
  {
    return st;
  }
  st = MCP23017_Init(&m->lo_en, hi2c, MATRIX_LO_MCP_STRAP);
  if (st != HAL_OK)
  {
    return st;
  }

  /* MCP23017_Init leaves outputs low; for active-low enables that would turn
   * every mux ON. Force the proper all-open state immediately. */
  return MatrixCard_AllOff(m);
}

HAL_StatusTypeDef MatrixCard_BankOff(MatrixCard_t *m, MatrixBank_t bank)
{
  if (m == NULL)
  {
    return HAL_ERROR;
  }
  return MCP23017_WritePins(matrix_bank_dev(m, bank), MATRIX_EN_ALL_OFF);
}

HAL_StatusTypeDef MatrixCard_AllOff(MatrixCard_t *m)
{
  HAL_StatusTypeDef st;

  if (m == NULL)
  {
    return HAL_ERROR;
  }
  st = MatrixCard_BankOff(m, MATRIX_BANK_HI);
  if (st != HAL_OK)
  {
    return st;
  }
  return MatrixCard_BankOff(m, MATRIX_BANK_LO);
}

HAL_StatusTypeDef MatrixCard_SelectPin(MatrixCard_t *m, MatrixBank_t bank, uint16_t pin)
{
  uint8_t mux, channel;
  HAL_StatusTypeDef st;
  MCP23017_t *dev;

  if (m == NULL || pin < MATRIX_PIN_MIN || pin > MATRIX_PIN_MAX)
  {
    return HAL_ERROR;
  }

  matrix_map_pin(pin, &mux, &channel);
  dev = matrix_bank_dev(m, bank);

  /* Break-before-make: open the bank, drive the shared select, then enable the
   * one target mux. Prevents the previously-enabled mux from briefly seeing
   * the new channel address. */
  st = MCP23017_WritePins(dev, MATRIX_EN_ALL_OFF);
  if (st != HAL_OK)
  {
    return st;
  }

  matrix_drive_select(matrix_bank_sel(m, bank), channel);

  return MCP23017_WritePins(dev, MATRIX_EN_PATTERN(mux));
}

HAL_StatusTypeDef MatrixCard_ConnectPair(MatrixCard_t *m, uint16_t hi_pin, uint16_t lo_pin)
{
  HAL_StatusTypeDef st = MatrixCard_SelectPin(m, MATRIX_BANK_HI, hi_pin);
  if (st != HAL_OK)
  {
    return st;
  }
  return MatrixCard_SelectPin(m, MATRIX_BANK_LO, lo_pin);
}
