/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    hv_card.c
  * @brief   HV Card control implementation. See hv_card.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "cards/hv_card.h"

/* Settle time after asserting this board's bus-enable line, before the first
 * I2C transaction: the isolator's own propagation delay is nanoseconds, but
 * this gives margin without costing anything meaningful against I2C's own
 * per-transaction overhead. VERIFY against the isolator datasheet if this
 * ever needs to shrink. */
#ifndef HV_BUS_ENABLE_SETTLE_MS
#define HV_BUS_ENABLE_SETTLE_MS  1U
#endif

/**
  * @brief  Put this board, and only this board, on the shared I2C bus.
  * @note   The Matrix Card and every HV slot hard-strap their expanders to the
  *         same 0x20..0x27 range (see hv_card.h header) - HV_Card_EN1..4 is the
  *         only thing that keeps two of them from answering the same address
  *         at once. Every function below that touches hv->inject[]/hv->ret[]
  *         must bracket the transfer with claim/release; nothing else may run
  *         between them.
  * @param  hv : [in] instance; must be non-NULL, en_port must be configured.
  * @retval None (GPIO writes do not fail).
  */
static void hv_bus_claim(HvCard_t *hv)
{
  HAL_GPIO_WritePin(hv->cfg.en_port, hv->cfg.en_pin, GPIO_PIN_SET);
  HAL_Delay(HV_BUS_ENABLE_SETTLE_MS);
}

/**
  * @brief  Take this board back off the shared I2C bus.
  * @note   Leaving EN asserted after the transaction is what would let this
  *         board's addresses collide with the Matrix Card's - deassert on
  *         every exit path, including error returns.
  * @param  hv : [in] instance; must be non-NULL, en_port must be configured.
  * @retval None
  */
static void hv_bus_release(HvCard_t *hv)
{
  HAL_GPIO_WritePin(hv->cfg.en_port, hv->cfg.en_pin, GPIO_PIN_RESET);
}

/**
  * @brief  Map a 1-based side pin to its expander index and bit position.
  * @note   Linear layout: pin 1..64 -> expander 0..3, bit 0..15. VERIFY the
  *         routing against the connector netlist; swap for a LUT if it differs.
  * @param  pin : [in]  1-based pin number on one side (1..64).
  * @param  exp : [out] expander index within the side array (0..3).
  * @param  bit : [out] bit/relay position within that expander (0..15).
  * @retval None
  */
static void hv_map(uint8_t pin, uint8_t *exp, uint8_t *bit)
{
  uint8_t idx = (uint8_t)(pin - 1U);     /* 0..63 */
  *exp = (uint8_t)(idx >> 4);            /* 0..3  */
  *bit = (uint8_t)(idx & 0x0FU);         /* 0..15 */
}

/**
  * @brief  Open every relay on one side by clearing all four expanders.
  * @param  side : [in] array of HV_MCP_PER_SIDE expanders for one side.
  * @retval HAL_OK    all expanders driven low (relays open).
  * @retval other     first failing HAL status from MCP23017_WritePins().
  */
static HAL_StatusTypeDef hv_side_open(MCP23017_t side[HV_MCP_PER_SIDE])
{
  uint8_t i;
  HAL_StatusTypeDef st;
  for (i = 0U; i < HV_MCP_PER_SIDE; i++)
  {
    st = MCP23017_WritePins(&side[i], 0x0000U);
    if (st != HAL_OK)
    {
      return st;
    }
  }
  return HAL_OK;
}

/**
  * @brief  Close exactly one relay on a side, break-before-make.
  * @note   Opens the whole side first, then energises only the target relay, so
  *         no two pins are ever momentarily bridged during the switch.
  * @param  side : [in] array of HV_MCP_PER_SIDE expanders for one side.
  * @param  pin  : [in] 1-based pin to close (1..HV_PINS_PER_SIDE).
  * @retval HAL_OK    side opened and the single target relay closed.
  * @retval HAL_ERROR @p pin is out of range.
  * @retval other     first failing HAL status from the expander writes.
  */
static HAL_StatusTypeDef hv_side_close_one(MCP23017_t side[HV_MCP_PER_SIDE], uint8_t pin)
{
  uint8_t exp, bit;
  HAL_StatusTypeDef st;

  if (pin < 1U || pin > HV_PINS_PER_SIDE)
  {
    return HAL_ERROR;
  }
  hv_map(pin, &exp, &bit);

  st = hv_side_open(side);
  if (st != HAL_OK)
  {
    return st;
  }
  return MCP23017_WritePins(&side[exp], (uint16_t)(1U << bit));
}

/**
  * @brief  Open every relay on both the inject and return sides.
  * @param  hv : [in] HV-card instance; must be non-NULL.
  * @retval HAL_OK    both sides fully opened.
  * @retval HAL_ERROR @p hv is NULL.
  * @retval other     first failing HAL status from hv_side_open().
  */
HAL_StatusTypeDef HvCard_OpenAllRelays(HvCard_t *hv)
{
  HAL_StatusTypeDef st;
  if (hv == NULL)
  {
    return HAL_ERROR;
  }
  hv_bus_claim(hv);
  st = hv_side_open(hv->inject);
  if (st == HAL_OK)
  {
    st = hv_side_open(hv->ret);
  }
  hv_bus_release(hv);
  return st;
}

/**
  * @brief  Initialise a full HV card and leave it in the safe idle state.
  * @note   Brings up all eight relay expanders (4 inject + 4 return), the HV
  *         DAC8830 and the two sense ADCs (rail + leakage) that share the
  *         isolated SPI, then forces HV to 0 V and opens every relay.
  * @param  hv  : [out] HV-card instance to populate; must be non-NULL.
  * @param  cfg : [in]  static configuration (I2C/SPI handles, straps, CS pins,
  *                    vref); copied into the instance. Must be non-NULL.
  * @retval HAL_OK    card initialised and parked safe.
  * @retval HAL_ERROR @p hv or @p cfg is NULL.
  * @retval other     first failing HAL status from device bring-up.
  */
HAL_StatusTypeDef HvCard_Init(HvCard_t *hv, const HvCardCfg_t *cfg)
{
  HAL_StatusTypeDef st;
  uint8_t i;

  if (hv == NULL || cfg == NULL || cfg->en_port == NULL)
  {
    return HAL_ERROR;
  }
  hv->cfg = *cfg;

  hv_bus_claim(hv);
  for (i = 0U; i < HV_MCP_PER_SIDE; i++)
  {
    st = MCP23017_Init(&hv->inject[i], cfg->i2c, cfg->inject_strap[i]);
    if (st != HAL_OK)
    {
      break;
    }
    st = MCP23017_Init(&hv->ret[i], cfg->i2c, cfg->return_strap[i]);
    if (st != HAL_OK)
    {
      break;
    }
  }
  hv_bus_release(hv);
  if (st != HAL_OK)
  {
    return st;
  }

  /* DAC8830 -> 0 V program (HV off). */
  st = DAC8830_Init(&hv->dac, cfg->spi, cfg->dac_cs_port, cfg->dac_cs_pin);
  if (st != HAL_OK)
  {
    return st;
  }
  /* Two sense ADCs share the isolated SPI, each with its own soft-CS. */
  st = AD7476_Init(&hv->adc_rail, cfg->spi, cfg->adc_rail_cs_port, cfg->adc_rail_cs_pin);
  if (st != HAL_OK)
  {
    return st;
  }
  st = AD7476_Init(&hv->adc_leak, cfg->spi, cfg->adc_leak_cs_port, cfg->adc_leak_cs_pin);
  if (st != HAL_OK)
  {
    return st;
  }

  /* Safe state: HV at 0 V, all relays open. */
  (void)HvCard_HvOff(hv);
  return HvCard_OpenAllRelays(hv);
}

/**
  * @brief  Close a single relay on the inject side (break-before-make).
  * @param  hv  : [in] HV-card instance; must be non-NULL.
  * @param  pin : [in] 1-based inject pin to close.
  * @retval HAL_OK on success, HAL_ERROR if @p hv is NULL, else propagated status.
  */
HAL_StatusTypeDef HvCard_CloseInject(HvCard_t *hv, uint8_t pin)
{
  HAL_StatusTypeDef st;

  if (hv == NULL)
  {
    return HAL_ERROR;
  }
  hv_bus_claim(hv);
  st = hv_side_close_one(hv->inject, pin);
  hv_bus_release(hv);
  return st;
}

/**
  * @brief  Close a single relay on the return side (break-before-make).
  * @param  hv  : [in] HV-card instance; must be non-NULL.
  * @param  pin : [in] 1-based return pin to close.
  * @retval HAL_OK on success, HAL_ERROR if @p hv is NULL, else propagated status.
  */
HAL_StatusTypeDef HvCard_CloseReturn(HvCard_t *hv, uint8_t pin)
{
  HAL_StatusTypeDef st;

  if (hv == NULL)
  {
    return HAL_ERROR;
  }
  hv_bus_claim(hv);
  st = hv_side_close_one(hv->ret, pin);
  hv_bus_release(hv);
  return st;
}

/**
  * @brief  Connect one inject/return conductor pair for an insulation test.
  * @note   Closes the inject-side relay first, then the return-side relay; each
  *         side is broken before making internally. Intended to be called while
  *         the HV line is dead (see the insulation sequence).
  * @param  hv         : [in] HV-card instance; must be non-NULL.
  * @param  inject_pin : [in] 1-based pin on the inject side.
  * @param  return_pin : [in] 1-based pin on the return side.
  * @retval HAL_OK    both relays closed.
  * @retval other     first failing HAL status from the two close operations.
  */
HAL_StatusTypeDef HvCard_ConnectPair(HvCard_t *hv, uint8_t inject_pin, uint8_t return_pin)
{
  HAL_StatusTypeDef st = HvCard_CloseInject(hv, inject_pin);
  if (st != HAL_OK)
  {
    return st;
  }
  return HvCard_CloseReturn(hv, return_pin);
}

/**
  * @brief  Set the HV rail via a raw DAC8830 code.
  * @warning Programming a non-zero code raises real high voltage: there is no
  *          separate HV-enable gate, the DAC level IS the HV output.
  * @param  hv   : [in] HV-card instance; must be non-NULL.
  * @param  code : [in] raw 16-bit DAC code (0 = 0 V).
  * @retval HAL_OK on success, HAL_ERROR if @p hv is NULL, else propagated status.
  */
HAL_StatusTypeDef HvCard_SetVoltageCode(HvCard_t *hv, uint16_t code)
{
  return (hv == NULL) ? HAL_ERROR : DAC8830_WriteCode(&hv->dac, code);
}

/**
  * @brief  Set the HV rail as a fraction of full-scale output.
  * @warning A non-zero fraction raises real high voltage (see HvCard_SetVoltageCode).
  * @param  hv       : [in] HV-card instance; must be non-NULL.
  * @param  fraction : [in] target output as a fraction of full scale (0..1).
  * @retval HAL_OK on success, HAL_ERROR if @p hv is NULL, else propagated status.
  */
HAL_StatusTypeDef HvCard_SetVoltageFraction(HvCard_t *hv, float fraction)
{
  return (hv == NULL) ? HAL_ERROR : DAC8830_WriteFraction(&hv->dac, fraction);
}

/**
  * @brief  Force the HV rail to 0 V by zeroing the DAC.
  * @note   Primary means of de-energising the card (no dedicated HV-off line).
  * @param  hv : [in] HV-card instance; must be non-NULL.
  * @retval HAL_OK on success, HAL_ERROR if @p hv is NULL, else propagated status.
  */
HAL_StatusTypeDef HvCard_HvOff(HvCard_t *hv)
{
  return (hv == NULL) ? HAL_ERROR : DAC8830_WriteCode(&hv->dac, 0U);
}

/**
  * @brief  Enable/disable the HV output (schematic has no dedicated gate line).
  * @note   There is no hardware HV-enable, so Enable(1) is a no-op (the level
  *         was already programmed via HvCard_SetVoltage*), and Enable(0) simply
  *         zeroes the DAC via HvCard_HvOff(). Kept for API symmetry.
  * @param  hv : [in] HV-card instance; must be non-NULL.
  * @param  on : [in] non-zero = leave output as programmed; 0 = force 0 V.
  * @retval HAL_OK on success, HAL_ERROR if @p hv is NULL, else propagated status.
  */
HAL_StatusTypeDef HvCard_HvEnable(HvCard_t *hv, uint8_t on)
{
  if (hv == NULL)
  {
    return HAL_ERROR;
  }
  return (on != 0U) ? HAL_OK : HvCard_HvOff(hv);
}

/**
  * @brief  Request an active HV discharge (no-op on this hardware).
  * @note   The schematic has no active discharge relay; the HV bus bleeds down
  *         passively through the ~11 Mohm sense divider. This entry point exists
  *         only for API compatibility with the test sequences.
  * @param  hv : [in] HV-card instance; must be non-NULL.
  * @param  on : [in] ignored (no discharge hardware to actuate).
  * @retval HAL_OK on success, HAL_ERROR if @p hv is NULL.
  */
HAL_StatusTypeDef HvCard_Discharge(HvCard_t *hv, uint8_t on)
{
  (void)on;
  return (hv == NULL) ? HAL_ERROR : HAL_OK;
}

/**
  * @brief  Read the HV rail sense node (U301) as a raw ADC code.
  * @param  hv   : [in]  HV-card instance; must be non-NULL.
  * @param  code : [out] destination for the raw rail-sense code.
  * @retval HAL_OK on success, HAL_ERROR if @p hv is NULL, else propagated status.
  */
HAL_StatusTypeDef HvCard_ReadRailRaw(HvCard_t *hv, uint16_t *code)
{
  return (hv == NULL) ? HAL_ERROR : AD7476_ReadRaw(&hv->adc_rail, code);
}

/**
  * @brief  Read the HV rail sense node (U301) scaled to volts (at the ADC).
  * @note   This is the divided-down sense voltage, not the actual rail voltage;
  *         apply the divider ratio externally to recover the true HV level.
  * @param  hv    : [in]  HV-card instance; must be non-NULL.
  * @param  volts : [out] destination for the rail-sense voltage at the ADC.
  * @retval HAL_OK on success, HAL_ERROR if @p hv is NULL, else propagated status.
  */
HAL_StatusTypeDef HvCard_ReadRailVolts(HvCard_t *hv, float *volts)
{
  return (hv == NULL) ? HAL_ERROR : AD7476_ReadVolts(&hv->adc_rail, hv->cfg.vref, volts);
}

/**
  * @brief  Read the HV leakage/return node (U302) as a raw ADC code.
  * @note   This is the node the insulation test evaluates (HV_RET), not the rail.
  * @param  hv   : [in]  HV-card instance; must be non-NULL.
  * @param  code : [out] destination for the raw leakage-sense code.
  * @retval HAL_OK on success, HAL_ERROR if @p hv is NULL, else propagated status.
  */
HAL_StatusTypeDef HvCard_ReadLeakageRaw(HvCard_t *hv, uint16_t *code)
{
  return (hv == NULL) ? HAL_ERROR : AD7476_ReadRaw(&hv->adc_leak, code);
}

/**
  * @brief  Read the HV leakage/return node (U302) scaled to volts (at the ADC).
  * @param  hv    : [in]  HV-card instance; must be non-NULL.
  * @param  volts : [out] destination for the leakage-sense voltage at the ADC.
  * @retval HAL_OK on success, HAL_ERROR if @p hv is NULL, else propagated status.
  */
HAL_StatusTypeDef HvCard_ReadLeakageVolts(HvCard_t *hv, float *volts)
{
  return (hv == NULL) ? HAL_ERROR : AD7476_ReadVolts(&hv->adc_leak, hv->cfg.vref, volts);
}
