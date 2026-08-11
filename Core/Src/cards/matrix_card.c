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
/* Shared-bus arbitration                                                     */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Put the Matrix Card, and only the Matrix Card, on the shared bus.
  * @note   See matrix_card.h - the Matrix Card's own expanders (everything
  *         except U21) share an I2C bus with the HV cards, all at the same
  *         0x20..0x27, so exactly one card's segment may be live at a time.
  * @param  m : [in] instance; must be non-NULL, en_port must be configured.
  * @retval None (GPIO writes do not fail).
  */
void MatrixCard_BusClaim(MatrixCard_t *m)
{
  HAL_GPIO_WritePin(m->en_port, m->en_pin, GPIO_PIN_SET);
  HAL_Delay(MATRIX_BUS_EN_SETTLE_MS);
}

/**
  * @brief  Take the Matrix Card back off the shared bus.
  * @param  m : [in] instance; must be non-NULL, en_port must be configured.
  * @retval None
  */
void MatrixCard_BusRelease(MatrixCard_t *m)
{
  HAL_GPIO_WritePin(m->en_port, m->en_pin, GPIO_PIN_RESET);
}

/* -------------------------------------------------------------------------- */
/* Helpers                                                                    */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Map a 1-based harness pin to its mux index and channel.
  * @note   Linear layout for 8:1 parts: mux k carries pins k*8+1 .. k*8+8. If
  *         the PCB routes I0..I7 to harness pins in a different order, replace
  *         the body with a lookup table - nothing else changes. The force and
  *         sense arrays share the select bus, so one mapping serves both.
  * @param  pin     : [in]  1-based harness pin (1..256).
  * @param  mux     : [out] mux index within the bank (0..31).
  * @param  channel : [out] channel within that mux (0..7).
  * @retval HAL_OK, or HAL_ERROR on a bad argument.
  */
HAL_StatusTypeDef MatrixCard_MapPin(uint16_t pin, uint8_t *mux, uint8_t *channel)
{
  uint16_t idx;

  if (mux == NULL || channel == NULL ||
      pin < MATRIX_PIN_MIN || pin > MATRIX_PIN_MAX)
  {
    return HAL_ERROR;
  }

  idx      = (uint16_t)(pin - 1U);              /* 0..255 */
  *mux     = (uint8_t)(idx >> MATRIX_MUX_SHIFT);/* 0..31  */
  *channel = (uint8_t)(idx & MATRIX_CH_MASK);   /* 0..7   */
  return HAL_OK;
}

/**
  * @brief  Enable word for one 16-enable expander, one-hot on @p n.
  * @note   The schematic wires GPB0..7 to EN1..8 and GPA0..7 to EN9..16, so in
  *         the driver's packing (bits 0..7 = GPA, 8..15 = GPB) enable n lands at
  *         bit ((n-1)+8) % 16. E is active low, hence the inversion.
  * @param  n : [in] 1-based enable within this expander (1..16).
  * @retval Word with exactly that enable asserted, all others off.
  */
static uint16_t matrix_en_word(uint8_t n)
{
  uint8_t bit = (uint8_t)(((uint16_t)(n - 1U) + 8U) % 16U);
  return (uint16_t)(MATRIX_EN_ALL_OFF & ~(1U << bit));
}

/**
  * @brief  Resolve a bank + array to its pair of enable expanders.
  * @param  m     : [in] instance.
  * @param  bank  : [in] HI or LO.
  * @param  sense : [in] 0 = force array, non-zero = sense array.
  * @retval Pointer to a 2-element MCP23017 array: [0] = EN1..16, [1] = EN17..32.
  */
static MCP23017_t *matrix_exp(MatrixCard_t *m, MatrixBank_t bank, uint8_t sense)
{
  if (sense != 0U)
  {
    return (bank == MATRIX_BANK_HI) ? m->hi_sns : m->lo_sns;
  }
  return (bank == MATRIX_BANK_HI) ? m->hi_en : m->lo_en;
}

/**
  * @brief  Push the staged select word out to U21.
  * @param  m : [in] instance.
  * @retval HAL status from the expander write.
  */
static HAL_StatusTypeDef matrix_flush_select(MatrixCard_t *m)
{
  return MCP23017_WritePins(&m->sel, m->sel_cache);
}

/**
  * @brief  Stage a bank's 3-bit channel address into the U21 shadow word.
  * @param  m       : [in] instance.
  * @param  bank    : [in] bank whose address to set.
  * @param  channel : [in] 0..7.
  * @retval None (the caller flushes).
  */
static void matrix_stage_channel(MatrixCard_t *m, MatrixBank_t bank, uint8_t channel)
{
  uint8_t  shift = (bank == MATRIX_BANK_HI) ? MATRIX_SEL_HI_SHIFT : MATRIX_SEL_LO_SHIFT;
  uint16_t mask  = (uint16_t)((uint16_t)MATRIX_CH_MASK << shift);

  m->sel_cache = (uint16_t)((m->sel_cache & ~mask) |
                            (((uint16_t)channel & MATRIX_CH_MASK) << shift));
}

/**
  * @brief  Drive one enable word across a bank's two expanders.
  * @note   Callers must have selected the right segment first.
  * @param  m     : [in] instance.
  * @param  bank  : [in] bank to drive.
  * @param  sense : [in] 0 = force array, non-zero = sense array.
  * @param  mux   : [in] 0..31, or 0xFF for "all off".
  * @retval HAL_OK on success, else the first failing status.
  */
static HAL_StatusTypeDef matrix_drive_bank(MatrixCard_t *m, MatrixBank_t bank,
                                           uint8_t sense, uint8_t mux)
{
  MCP23017_t *exp = matrix_exp(m, bank, sense);
  uint16_t w0 = MATRIX_EN_ALL_OFF;
  uint16_t w1 = MATRIX_EN_ALL_OFF;
  HAL_StatusTypeDef st;

  if (mux != 0xFFU)
  {
    uint8_t n = (uint8_t)((mux % MATRIX_EN_PER_EXPANDER) + 1U);
    if (mux < MATRIX_EN_PER_EXPANDER) { w0 = matrix_en_word(n); }
    else                              { w1 = matrix_en_word(n); }
  }

  st = MCP23017_WritePins(&exp[0], w0);
  if (st != HAL_OK)
  {
    return st;
  }
  return MCP23017_WritePins(&exp[1], w1);
}

/* -------------------------------------------------------------------------- */

/**
  * @brief  Enable exactly one I2C segment.
  * @note   The two NTS0102DP output enables are HI_S3 (BUFF1) and LO_S3 (BUFF2),
  *         both bits in the U21 word. Only one may be on at a time - with both
  *         enabled the two address spaces overlap on the same wires. Returns
  *         immediately if the segment is already selected, so callers can invoke
  *         it freely without paying for redundant I2C traffic.
  * @param  m   : [in] instance; must be non-NULL.
  * @param  seg : [in] segment to enable.
  * @retval HAL_OK on success, HAL_ERROR if @p m is NULL, else propagated status.
  */
HAL_StatusTypeDef MatrixCard_SelectSegment(MatrixCard_t *m, MatrixSeg_t seg)
{
  uint16_t b1, b2;

  if (m == NULL)
  {
    return HAL_ERROR;
  }
  if (m->seg == seg)
  {
    return HAL_OK;
  }

  b1 = (uint16_t)(1U << MATRIX_SEL_BUFF1_OE_BIT);
  b2 = (uint16_t)(1U << MATRIX_SEL_BUFF2_OE_BIT);

  m->sel_cache &= (uint16_t)~(b1 | b2);
#if (MATRIX_SEG_OE_ACTIVE_HIGH != 0)
  m->sel_cache |= (seg == MATRIX_SEG_FORCE) ? b1 : b2;
#else
  m->sel_cache |= (seg == MATRIX_SEG_FORCE) ? b2 : b1;
#endif

  if (matrix_flush_select(m) != HAL_OK)
  {
    return HAL_ERROR;
  }
  m->seg = seg;
  return HAL_OK;
}

/**
  * @brief  Bring up U21 and all eight enable expanders, and open every mux.
  * @note   Order matters twice over. U21 comes first because nothing else is
  *         reachable until a segment is enabled. Within each expander the output
  *         latch is written 0xFF BEFORE the direction is set to output, so no
  *         mux is ever briefly enabled - MCP23017_Init leaves outputs low, which
  *         for active-low enables would close every path on the card.
  * @param  m    : [out] instance; must be non-NULL.
  * @param  hi2c : [in]  shared I2C bus; must be non-NULL.
  * @retval HAL_OK on success, HAL_ERROR on a NULL argument, else propagated.
  */
HAL_StatusTypeDef MatrixCard_Init(MatrixCard_t *m, I2C_HandleTypeDef *hi2c_local,
                                  I2C_HandleTypeDef *hi2c_shared,
                                  GPIO_TypeDef *en_port, uint16_t en_pin)
{
  static const uint8_t force_straps[2][MATRIX_EXP_PER_BANK] = {
    { MATRIX_HI_EN_LO_STRAP, MATRIX_HI_EN_HI_STRAP },
    { MATRIX_LO_EN_LO_STRAP, MATRIX_LO_EN_HI_STRAP }
  };
  static const uint8_t sense_straps[2][MATRIX_EXP_PER_BANK] = {
    { MATRIX_HI_SNS_LO_STRAP, MATRIX_HI_SNS_HI_STRAP },
    { MATRIX_LO_SNS_LO_STRAP, MATRIX_LO_SNS_HI_STRAP }
  };
  HAL_StatusTypeDef st;
  uint8_t b, i;

  if (m == NULL || hi2c_local == NULL || hi2c_shared == NULL || en_port == NULL)
  {
    return HAL_ERROR;
  }

  m->sense_paired = 0U;
  m->sel_cache    = 0U;          /* channel 0 both banks, both segments off */
  m->seg          = MATRIX_SEG_FORCE;
  m->en_port      = en_port;
  m->en_pin       = en_pin;

  /* U21 is local to the Control Card on hi2c_local - no bus claim needed. */
  st = MCP23017_Init(&m->sel, hi2c_local, MATRIX_SEL_MCP_STRAP);
  if (st != HAL_OK)
  {
    return st;
  }
  st = matrix_flush_select(m);   /* both segments disabled, channel 0 */
  if (st != HAL_OK)
  {
    return st;
  }

  /* Everything from here on reaches the Matrix Card's own expanders over
   * hi2c_shared, which the HV cards also sit on - claim the segment first. */
  MatrixCard_BusClaim(m);

  /* Force segment. */
  m->seg = (MatrixSeg_t)0xFF;    /* force SelectSegment to act */
  st = MatrixCard_SelectSegment(m, MATRIX_SEG_FORCE);
  if (st != HAL_OK)
  {
    goto release;
  }
  for (b = 0U; b < 2U; b++)
  {
    MCP23017_t *exp = (b == 0U) ? m->hi_en : m->lo_en;
    for (i = 0U; i < MATRIX_EXP_PER_BANK; i++)
    {
      st = MCP23017_Init(&exp[i], hi2c_shared, force_straps[b][i]);
      if (st != HAL_OK)
      {
        goto release;
      }
      st = MCP23017_WritePins(&exp[i], MATRIX_EN_ALL_OFF);
      if (st != HAL_OK)
      {
        goto release;
      }
    }
  }

  /* Sense segment. */
  st = MatrixCard_SelectSegment(m, MATRIX_SEG_SENSE);
  if (st != HAL_OK)
  {
    goto release;
  }
  for (b = 0U; b < 2U; b++)
  {
    MCP23017_t *exp = (b == 0U) ? m->hi_sns : m->lo_sns;
    for (i = 0U; i < MATRIX_EXP_PER_BANK; i++)
    {
      st = MCP23017_Init(&exp[i], hi2c_shared, sense_straps[b][i]);
      if (st != HAL_OK)
      {
        goto release;
      }
      st = MCP23017_WritePins(&exp[i], MATRIX_EN_ALL_OFF);
      if (st != HAL_OK)
      {
        goto release;
      }
    }
  }

  /* Leave the force segment selected - the common case. */
  st = MatrixCard_SelectSegment(m, MATRIX_SEG_FORCE);

release:
  MatrixCard_BusRelease(m);
  return st;
}

/**
  * @brief  Enable or disable mirroring of bank enables onto the sense array.
  * @note   Turning pairing off also opens both sense banks, so the sense taps
  *         are never left closed behind the caller's back.
  * @param  m  : [in] instance; must be non-NULL.
  * @param  on : [in] 0 = force only, non-zero = force + sense.
  * @retval HAL_OK on success, HAL_ERROR if @p m is NULL, else propagated.
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
    MatrixCard_BusClaim(m);
    st = MatrixCard_SelectSegment(m, MATRIX_SEG_SENSE);
    if (st == HAL_OK)
    {
      st = matrix_drive_bank(m, MATRIX_BANK_HI, 1U, 0xFFU);
    }
    if (st == HAL_OK)
    {
      st = matrix_drive_bank(m, MATRIX_BANK_LO, 1U, 0xFFU);
    }
    if (st == HAL_OK)
    {
      st = MatrixCard_SelectSegment(m, MATRIX_SEG_FORCE);
    }
    MatrixCard_BusRelease(m);
    if (st != HAL_OK)
    {
      return st;
    }
  }

  m->sense_paired = (on != 0U) ? 1U : 0U;
  return HAL_OK;
}

/**
  * @brief  Open every mux on one bank (force, plus sense when paired).
  * @param  m    : [in] instance; must be non-NULL.
  * @param  bank : [in] bank to open.
  * @retval HAL_OK on success, HAL_ERROR if @p m is NULL, else propagated.
  */
HAL_StatusTypeDef MatrixCard_BankOff(MatrixCard_t *m, MatrixBank_t bank)
{
  HAL_StatusTypeDef st;

  if (m == NULL)
  {
    return HAL_ERROR;
  }

  MatrixCard_BusClaim(m);

  st = MatrixCard_SelectSegment(m, MATRIX_SEG_FORCE);
  if (st == HAL_OK)
  {
    st = matrix_drive_bank(m, bank, 0U, 0xFFU);
  }
  if (st == HAL_OK && m->sense_paired != 0U)
  {
    st = MatrixCard_SelectSegment(m, MATRIX_SEG_SENSE);
    if (st == HAL_OK)
    {
      st = matrix_drive_bank(m, bank, 1U, 0xFFU);
    }
    if (st == HAL_OK)
    {
      st = MatrixCard_SelectSegment(m, MATRIX_SEG_FORCE);
    }
  }

  MatrixCard_BusRelease(m);
  return st;
}

/**
  * @brief  Open every mux on both banks, both arrays.
  * @param  m : [in] instance; must be non-NULL.
  * @retval HAL_OK on success, HAL_ERROR if @p m is NULL, else propagated.
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
  * @brief  Connect one harness pin to the given bank's common bus.
  * @note   Break-before-make. The sense array, when paired, is driven to the
  *         same mux index - both arrays share the channel-address bus, so
  *         mirroring the enable is all that is needed to keep the sense tap on
  *         the pin the force path is driving.
  * @param  m    : [in] instance; must be non-NULL.
  * @param  bank : [in] bank to route through.
  * @param  pin  : [in] 1-based harness pin (1..256).
  * @retval HAL_OK on success, HAL_ERROR on a bad argument, else propagated.
  */
HAL_StatusTypeDef MatrixCard_SelectPin(MatrixCard_t *m, MatrixBank_t bank, uint16_t pin)
{
  uint8_t mux, channel;
  HAL_StatusTypeDef st;

  if (m == NULL || MatrixCard_MapPin(pin, &mux, &channel) != HAL_OK)
  {
    return HAL_ERROR;
  }

  MatrixCard_BusClaim(m);

  st = MatrixCard_SelectSegment(m, MATRIX_SEG_FORCE);
  if (st == HAL_OK)
  {
    st = matrix_drive_bank(m, bank, 0U, 0xFFU);    /* break */
  }
  if (st == HAL_OK)
  {
    matrix_stage_channel(m, bank, channel);
    st = matrix_flush_select(m);
  }
  if (st == HAL_OK)
  {
    st = matrix_drive_bank(m, bank, 0U, mux);      /* make */
  }
  if (st == HAL_OK && m->sense_paired != 0U)
  {
    st = MatrixCard_SelectSegment(m, MATRIX_SEG_SENSE);
    if (st == HAL_OK)
    {
      st = matrix_drive_bank(m, bank, 1U, mux);
    }
    if (st == HAL_OK)
    {
      st = MatrixCard_SelectSegment(m, MATRIX_SEG_FORCE);
    }
  }

  MatrixCard_BusRelease(m);
  return st;
}

/**
  * @brief  Connect a HI pin and a LO pin.
  * @note   Both channel addresses live in the same U21 byte, so they are staged
  *         and flushed once. With sense pairing on this costs two segment
  *         switches for the pair rather than four for two SelectPin calls.
  * @param  m      : [in] instance; must be non-NULL.
  * @param  hi_pin : [in] 1-based harness pin on the HI bank.
  * @param  lo_pin : [in] 1-based harness pin on the LO bank.
  * @retval HAL_OK on success, HAL_ERROR on a bad argument, else propagated.
  */
HAL_StatusTypeDef MatrixCard_ConnectPair(MatrixCard_t *m, uint16_t hi_pin, uint16_t lo_pin)
{
  uint8_t hi_mux, hi_ch, lo_mux, lo_ch;
  HAL_StatusTypeDef st;

  if (m == NULL ||
      MatrixCard_MapPin(hi_pin, &hi_mux, &hi_ch) != HAL_OK ||
      MatrixCard_MapPin(lo_pin, &lo_mux, &lo_ch) != HAL_OK)
  {
    return HAL_ERROR;
  }

  MatrixCard_BusClaim(m);

  st = MatrixCard_SelectSegment(m, MATRIX_SEG_FORCE);
  if (st == HAL_OK)
  {
    st = matrix_drive_bank(m, MATRIX_BANK_HI, 0U, 0xFFU);
  }
  if (st == HAL_OK)
  {
    st = matrix_drive_bank(m, MATRIX_BANK_LO, 0U, 0xFFU);
  }
  if (st == HAL_OK)
  {
    matrix_stage_channel(m, MATRIX_BANK_HI, hi_ch);
    matrix_stage_channel(m, MATRIX_BANK_LO, lo_ch);
    st = matrix_flush_select(m);
  }
  if (st == HAL_OK)
  {
    st = matrix_drive_bank(m, MATRIX_BANK_HI, 0U, hi_mux);
  }
  if (st == HAL_OK)
  {
    st = matrix_drive_bank(m, MATRIX_BANK_LO, 0U, lo_mux);
  }
  if (st == HAL_OK && m->sense_paired != 0U)
  {
    st = MatrixCard_SelectSegment(m, MATRIX_SEG_SENSE);
    if (st == HAL_OK)
    {
      st = matrix_drive_bank(m, MATRIX_BANK_HI, 1U, hi_mux);
    }
    if (st == HAL_OK)
    {
      st = matrix_drive_bank(m, MATRIX_BANK_LO, 1U, lo_mux);
    }
    if (st == HAL_OK)
    {
      st = MatrixCard_SelectSegment(m, MATRIX_SEG_FORCE);
    }
  }

  MatrixCard_BusRelease(m);
  return st;
}
