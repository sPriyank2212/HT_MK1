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
/**
  * @brief  Map a 1-based harness pin to its CD4067 mux and channel.
  * @note   Linear layout: mux k carries pins k*16+1..k*16+16; within a mux the
  *         channel selects the pin. Replace the body with a LUT if the PCB
  *         routes the mux inputs to harness pins in a different order.
  * @param  pin     : [in]  1-based harness pin (1..256).
  * @param  mux     : [out] target mux index within the bank (0..15).
  * @param  channel : [out] channel within that mux (0..15).
  * @retval None
  */
static void matrix_map_pin(uint16_t pin, uint8_t *mux, uint8_t *channel)
{
  uint16_t idx = (uint16_t)(pin - 1U);   /* 0..255 */
  *mux     = (uint8_t)(idx >> 4);        /* 0..15  */
  *channel = (uint8_t)(idx & 0x0FU);     /* 0..15  */
}

/**
  * @brief  Drive a bank's 4 shared CD4067 select lines to a channel address.
  * @note   Bit b of @p channel drives select line b. Select lines whose GPIO
  *         port is NULL (connector not yet drawn) are skipped, so the layer is
  *         usable during bring-up before the select wiring exists.
  * @param  sel     : [in] array of 4 select-line GPIO descriptors for the bank.
  * @param  channel : [in] 4-bit channel address to present (0..15).
  * @retval None
  */
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

/**
  * @brief  Return the mux-enable expander for a bank (HI or LO).
  * @param  m    : [in] matrix-card instance.
  * @param  bank : [in] which bank to resolve.
  * @retval Pointer to the bank's MCP23017 enable expander.
  */
static MCP23017_t *matrix_bank_dev(MatrixCard_t *m, MatrixBank_t bank)
{
  return (bank == MATRIX_BANK_HI) ? &m->hi_en : &m->lo_en;
}

/**
  * @brief  Return the shared select-line descriptors for a bank (HI or LO).
  * @param  m    : [in] matrix-card instance.
  * @param  bank : [in] which bank to resolve.
  * @retval Pointer to the bank's array of 4 select-line GPIO descriptors.
  */
static const MatrixGpio_t *matrix_bank_sel(MatrixCard_t *m, MatrixBank_t bank)
{
  return (bank == MATRIX_BANK_HI) ? m->sel.hi_sel : m->sel.lo_sel;
}

/* -------------------------------------------------------------------------- */

/**
  * @brief  Initialise the matrix card and force all muxes open.
  * @note   Copies the select-line map, brings up the HI and LO enable
  *         expanders, then calls MatrixCard_AllOff(). The explicit all-off is
  *         essential: MCP23017_Init leaves outputs low, which for active-low
  *         enables would otherwise turn every mux ON.
  * @param  m    : [out] matrix-card instance to populate; must be non-NULL.
  * @param  hi2c : [in]  I2C handle shared by both enable expanders; non-NULL.
  * @param  sel  : [in]  select-line GPIO map (copied into the instance); non-NULL.
  * @retval HAL_OK    card initialised and all muxes open.
  * @retval HAL_ERROR any of @p m, @p hi2c or @p sel is NULL.
  * @retval other     first failing HAL status from expander bring-up.
  */
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

/**
  * @brief  Disable every mux on one bank (drive the all-open enable word).
  * @param  m    : [in] matrix-card instance; must be non-NULL.
  * @param  bank : [in] bank to turn off (HI or LO).
  * @retval HAL_OK on success, HAL_ERROR if @p m is NULL, else propagated status.
  */
HAL_StatusTypeDef MatrixCard_BankOff(MatrixCard_t *m, MatrixBank_t bank)
{
  if (m == NULL)
  {
    return HAL_ERROR;
  }
  return MCP23017_WritePins(matrix_bank_dev(m, bank), MATRIX_EN_ALL_OFF);
}

/**
  * @brief  Disable every mux on both banks (fully open the matrix).
  * @param  m : [in] matrix-card instance; must be non-NULL.
  * @retval HAL_OK    both banks turned off.
  * @retval HAL_ERROR @p m is NULL.
  * @retval other     first failing HAL status from MatrixCard_BankOff().
  */
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

/**
  * @brief  Route one harness pin through to a bank's common node.
  * @note   Break-before-make: the bank is opened, the shared select lines are
  *         driven to the target channel, and only then is the one target mux
  *         enabled. This stops the previously-enabled mux from briefly seeing
  *         the new channel address.
  * @param  m    : [in] matrix-card instance; must be non-NULL.
  * @param  bank : [in] bank to route through (HI or LO).
  * @param  pin  : [in] 1-based harness pin (MATRIX_PIN_MIN..MATRIX_PIN_MAX).
  * @retval HAL_OK    pin routed through the bank.
  * @retval HAL_ERROR @p m is NULL or @p pin is out of range.
  * @retval other     first failing HAL status from the expander writes.
  */
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

/**
  * @brief  Route a HI pin and a LO pin so a wire pair is bridged to the sense path.
  * @param  m      : [in] matrix-card instance; must be non-NULL.
  * @param  hi_pin : [in] 1-based harness pin to route on the HI bank.
  * @param  lo_pin : [in] 1-based harness pin to route on the LO bank.
  * @retval HAL_OK    both pins routed.
  * @retval other     first failing HAL status from MatrixCard_SelectPin().
  */
HAL_StatusTypeDef MatrixCard_ConnectPair(MatrixCard_t *m, uint16_t hi_pin, uint16_t lo_pin)
{
  HAL_StatusTypeDef st = MatrixCard_SelectPin(m, MATRIX_BANK_HI, hi_pin);
  if (st != HAL_OK)
  {
    return st;
  }
  return MatrixCard_SelectPin(m, MATRIX_BANK_LO, lo_pin);
}

/* -------------------------------------------------------------------------- */
/* On-card ADC (U33 on SPI1, reads HI_COM) - used for resistance measurement.  */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Bind the on-card sense ADC (U33) and record its reference.
  * @param  m       : [in] matrix-card instance; must be non-NULL.
  * @param  spi     : [in] SPI handle for the on-card AD7476 (SPI1).
  * @param  cs_port : [in] GPIO port of the ADC chip-select.
  * @param  cs_pin  : [in] GPIO pin mask of the ADC chip-select.
  * @param  vref    : [in] ADC reference voltage, in volts.
  * @retval HAL_OK on success, HAL_ERROR if @p m is NULL, else AD7476_Init() status.
  */
HAL_StatusTypeDef MatrixCard_InitAdc(MatrixCard_t *m, SPI_HandleTypeDef *spi,
                                     GPIO_TypeDef *cs_port, uint16_t cs_pin, float vref)
{
  if (m == NULL)
  {
    return HAL_ERROR;
  }
  m->vref = vref;
  return AD7476_Init(&m->adc, spi, cs_port, cs_pin);
}

/**
  * @brief  Read the on-card sense node (HI_COM) as a raw ADC code.
  * @param  m    : [in]  matrix-card instance; must be non-NULL.
  * @param  code : [out] destination for the raw sense code.
  * @retval HAL_OK on success, HAL_ERROR if @p m is NULL, else propagated status.
  */
HAL_StatusTypeDef MatrixCard_ReadRaw(MatrixCard_t *m, uint16_t *code)
{
  return (m == NULL) ? HAL_ERROR : AD7476_ReadRaw(&m->adc, code);
}

/**
  * @brief  Read the on-card sense node (HI_COM) scaled to volts.
  * @note   Uses the reference cached by MatrixCard_InitAdc().
  * @param  m     : [in]  matrix-card instance; must be non-NULL.
  * @param  volts : [out] destination for the sense voltage, in volts.
  * @retval HAL_OK on success, HAL_ERROR if @p m is NULL, else propagated status.
  */
HAL_StatusTypeDef MatrixCard_ReadVolts(MatrixCard_t *m, float *volts)
{
  return (m == NULL) ? HAL_ERROR : AD7476_ReadVolts(&m->adc, m->vref, volts);
}
