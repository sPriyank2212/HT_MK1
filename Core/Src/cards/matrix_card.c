/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    matrix_card.c
  * @brief   Matrix Card control implementation. See matrix_card.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "cards/matrix_card.h"

/* -------------------------------------------------------------------------- */
/* Pin -> (mux, channel) mapping                                              */
/*                                                                            */
/* Linear mapping: mux k (0..15) carries pins k*16+1 .. k*16+16, and within a  */
/* mux, channel c selects the (c+1)-th of those pins. If the PCB routes the    */
/* CD4067 I0..I15 inputs to harness pins in a different order, replace the     */
/* body of matrix_map_pin() with a lookup table -- nothing else changes.       */
/* The force and sense arrays share the select bus, so one mapping serves both.*/
/* -------------------------------------------------------------------------- */
/**
  * @brief  Map a 1-based harness pin to its CD4067 mux and channel.
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
  * @brief  Return the force-array enable expander for a bank.
  * @param  m    : [in] matrix-card instance.
  * @param  bank : [in] which bank to resolve.
  * @retval Pointer to the bank's force MCP23017.
  */
static MCP23017_t *matrix_force_dev(MatrixCard_t *m, MatrixBank_t bank)
{
  return (bank == MATRIX_BANK_HI) ? &m->hi_en : &m->lo_en;
}

/**
  * @brief  Return the sense-array enable expander for a bank.
  * @param  m    : [in] matrix-card instance.
  * @param  bank : [in] which bank to resolve.
  * @retval Pointer to the bank's sense MCP23017.
  */
static MCP23017_t *matrix_sense_dev(MatrixCard_t *m, MatrixBank_t bank)
{
  return (bank == MATRIX_BANK_HI) ? &m->hi_sense_en : &m->lo_sense_en;
}

/**
  * @brief  Drive one enable word onto a bank, on the force array and - when
  *         pairing is enabled - the matching sense array.
  * @note   The two arrays are always driven to the SAME word. They share the
  *         select bus, so mirroring the enable is all that is needed to keep
  *         the sense tap on the same harness pin the force path is driving.
  * @param  m    : [in] matrix-card instance.
  * @param  bank : [in] bank to drive.
  * @param  word : [in] enable word (MATRIX_EN_ALL_OFF or MATRIX_EN_PATTERN).
  * @retval HAL_OK on success, else the first failing status.
  */
static HAL_StatusTypeDef matrix_drive_enables(MatrixCard_t *m, MatrixBank_t bank, uint16_t word)
{
  HAL_StatusTypeDef st = MCP23017_WritePins(matrix_force_dev(m, bank), word);
  if (st != HAL_OK)
  {
    return st;
  }
  if (m->sense_paired != 0U)
  {
    st = MCP23017_WritePins(matrix_sense_dev(m, bank), word);
  }
  return st;
}

/**
  * @brief  Present a channel address on a bank's shared select nibble.
  * @note   Updates the U21 shadow word and issues one 16-bit write. Because the
  *         HI and LO nibbles share the same expander byte, the caller can stage
  *         both nibbles and flush once - see MatrixCard_ConnectPair().
  * @param  m       : [in] matrix-card instance.
  * @param  bank    : [in] bank whose nibble to update.
  * @param  channel : [in] 4-bit channel address (0..15).
  * @retval None (the shadow is updated; the caller flushes).
  */
static void matrix_stage_channel(MatrixCard_t *m, MatrixBank_t bank, uint8_t channel)
{
  uint8_t  shift = (bank == MATRIX_BANK_HI) ? MATRIX_SEL_HI_SHIFT : MATRIX_SEL_LO_SHIFT;
  uint16_t mask  = (uint16_t)(MATRIX_SEL_NIBBLE_MASK << shift);

  m->sel_cache = (uint16_t)((m->sel_cache & ~mask) |
                            (((uint16_t)channel & MATRIX_SEL_NIBBLE_MASK) << shift));
}

/**
  * @brief  Push the staged select word out to U21.
  * @param  m : [in] matrix-card instance.
  * @retval HAL status from the expander write.
  */
static HAL_StatusTypeDef matrix_flush_select(MatrixCard_t *m)
{
  return MCP23017_WritePins(&m->sel, m->sel_cache);
}

/* -------------------------------------------------------------------------- */

/**
  * @brief  Initialise the matrix card and force all muxes open.
  * @note   Brings up U21 (select) plus the four enable expanders, then calls
  *         MatrixCard_AllOff(). The explicit all-off is essential: MCP23017_Init
  *         leaves outputs low, which for active-low enables would otherwise turn
  *         every mux ON. Sense pairing starts OFF; callers that need 4-wire
  *         behaviour turn it on with MatrixCard_SetSensePaired().
  * @param  m    : [out] matrix-card instance to populate; must be non-NULL.
  * @param  hi2c : [in]  I2C handle shared by U21 and the Matrix expanders.
  * @retval HAL_OK    card initialised and all muxes open.
  * @retval HAL_ERROR @p m or @p hi2c is NULL.
  * @retval other     first failing HAL status from expander bring-up.
  */
HAL_StatusTypeDef MatrixCard_Init(MatrixCard_t *m, I2C_HandleTypeDef *hi2c)
{
  HAL_StatusTypeDef st;

  if (m == NULL || hi2c == NULL)
  {
    return HAL_ERROR;
  }

  m->sense_paired = 0U;
  m->sel_cache    = MATRIX_SEL_SPARE_DEFAULT;   /* channel 0 on both banks */

  st = MCP23017_Init(&m->sel, hi2c, MATRIX_SEL_MCP_STRAP);
  if (st != HAL_OK)
  {
    return st;
  }
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
  st = MCP23017_Init(&m->hi_sense_en, hi2c, MATRIX_HI_SENSE_MCP_STRAP);
  if (st != HAL_OK)
  {
    return st;
  }
  st = MCP23017_Init(&m->lo_sense_en, hi2c, MATRIX_LO_SENSE_MCP_STRAP);
  if (st != HAL_OK)
  {
    return st;
  }

  /* Defined default channel (0) on both banks. */
  st = matrix_flush_select(m);
  if (st != HAL_OK)
  {
    return st;
  }

  /* MCP23017_Init leaves outputs low; for active-low enables that would turn
   * every mux ON. Force the proper all-open state on BOTH arrays immediately,
   * regardless of the pairing setting. */
  st = MCP23017_WritePins(&m->hi_sense_en, MATRIX_EN_ALL_OFF);
  if (st != HAL_OK)
  {
    return st;
  }
  st = MCP23017_WritePins(&m->lo_sense_en, MATRIX_EN_ALL_OFF);
  if (st != HAL_OK)
  {
    return st;
  }
  return MatrixCard_AllOff(m);
}

/**
  * @brief  Enable or disable mirroring of bank enables onto the sense array.
  * @note   Turning pairing OFF also opens both sense banks, so the sense taps
  *         are never left closed behind the caller's back.
  * @param  m  : [in] matrix-card instance; must be non-NULL.
  * @param  on : [in] 0 = force array only, non-zero = force + sense.
  * @retval HAL_OK on success, HAL_ERROR if @p m is NULL, else propagated status.
  */
HAL_StatusTypeDef MatrixCard_SetSensePaired(MatrixCard_t *m, uint8_t on)
{
  HAL_StatusTypeDef st;

  if (m == NULL)
  {
    return HAL_ERROR;
  }

  if (on == 0U)
  {
    st = MCP23017_WritePins(&m->hi_sense_en, MATRIX_EN_ALL_OFF);
    if (st != HAL_OK)
    {
      return st;
    }
    st = MCP23017_WritePins(&m->lo_sense_en, MATRIX_EN_ALL_OFF);
    if (st != HAL_OK)
    {
      return st;
    }
  }

  m->sense_paired = (on != 0U) ? 1U : 0U;
  return HAL_OK;
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
  return matrix_drive_enables(m, bank, MATRIX_EN_ALL_OFF);
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
  * @note   Break-before-make: the bank is opened, the shared select nibble is
  *         driven via U21, and only then is the one target mux enabled. This
  *         stops the previously-enabled mux from briefly seeing the new channel
  *         address. When sense pairing is on, the matching sense mux follows.
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

  if (m == NULL || pin < MATRIX_PIN_MIN || pin > MATRIX_PIN_MAX)
  {
    return HAL_ERROR;
  }

  matrix_map_pin(pin, &mux, &channel);

  st = matrix_drive_enables(m, bank, MATRIX_EN_ALL_OFF);
  if (st != HAL_OK)
  {
    return st;
  }

  matrix_stage_channel(m, bank, channel);
  st = matrix_flush_select(m);
  if (st != HAL_OK)
  {
    return st;
  }

  return matrix_drive_enables(m, bank, MATRIX_EN_PATTERN(mux));
}

/**
  * @brief  Route a HI pin and a LO pin so a wire pair is bridged.
  * @note   Both channel addresses live in one U21 byte, so this stages both
  *         nibbles and flushes once - one I2C write instead of two. Both banks
  *         are opened first, so the sequence is still break-before-make.
  * @param  m      : [in] matrix-card instance; must be non-NULL.
  * @param  hi_pin : [in] 1-based harness pin to route on the HI bank.
  * @param  lo_pin : [in] 1-based harness pin to route on the LO bank.
  * @retval HAL_OK    both pins routed.
  * @retval HAL_ERROR @p m is NULL or either pin is out of range.
  * @retval other     first failing HAL status from the expander writes.
  */
HAL_StatusTypeDef MatrixCard_ConnectPair(MatrixCard_t *m, uint16_t hi_pin, uint16_t lo_pin)
{
  uint8_t hi_mux, hi_ch, lo_mux, lo_ch;
  HAL_StatusTypeDef st;

  if (m == NULL ||
      hi_pin < MATRIX_PIN_MIN || hi_pin > MATRIX_PIN_MAX ||
      lo_pin < MATRIX_PIN_MIN || lo_pin > MATRIX_PIN_MAX)
  {
    return HAL_ERROR;
  }

  matrix_map_pin(hi_pin, &hi_mux, &hi_ch);
  matrix_map_pin(lo_pin, &lo_mux, &lo_ch);

  st = MatrixCard_AllOff(m);
  if (st != HAL_OK)
  {
    return st;
  }

  matrix_stage_channel(m, MATRIX_BANK_HI, hi_ch);
  matrix_stage_channel(m, MATRIX_BANK_LO, lo_ch);
  st = matrix_flush_select(m);
  if (st != HAL_OK)
  {
    return st;
  }

  st = matrix_drive_enables(m, MATRIX_BANK_HI, MATRIX_EN_PATTERN(hi_mux));
  if (st != HAL_OK)
  {
    return st;
  }
  return matrix_drive_enables(m, MATRIX_BANK_LO, MATRIX_EN_PATTERN(lo_mux));
}

/* -------------------------------------------------------------------------- */
/* On-card AD7476 (U33 on SPI1, reads HI_COM) - CONTINUITY measurement.        */
/* Resistance now goes through the ADS124S08 across HI_SENSE/LO_SENSE.         */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Bind the on-card continuity ADC (U33) and record its reference.
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
  * @param  m     : [in]  matrix-card instance; must be non-NULL.
  * @param  volts : [out] destination for the sense voltage, in volts.
  * @retval HAL_OK on success, HAL_ERROR if @p m is NULL, else propagated status.
  */
HAL_StatusTypeDef MatrixCard_ReadVolts(MatrixCard_t *m, float *volts)
{
  return (m == NULL) ? HAL_ERROR : AD7476_ReadVolts(&m->adc, m->vref, volts);
}
