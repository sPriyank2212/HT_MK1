/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    mcp23017.c
  * @brief   Driver implementation for the MCP23017 I2C GPIO expander.
  *          See mcp23017.h for the device map and packing convention.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "drivers/mcp23017.h"

/* HAL expects the address left-shifted into bits 7:1. */
#define MCP23017_HAL_ADDR(dev)   ((uint16_t)((dev)->addr7 << 1))

/* -------------------------------------------------------------------------- */
/* Raw register access                                                        */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Write one 8-bit device register over I2C.
  * @param  dev : [in] bound driver instance; dev->hi2c must be non-NULL.
  * @param  reg : [in] register address (bank-0 map).
  * @param  val : [in] byte to write.
  * @retval HAL_OK    register written.
  * @retval HAL_ERROR @p dev or dev->hi2c is NULL.
  * @retval other     HAL status propagated from HAL_I2C_Mem_Write().
  */
HAL_StatusTypeDef MCP23017_WriteReg(MCP23017_t *dev, uint8_t reg, uint8_t val)
{
  if (dev == NULL || dev->hi2c == NULL)
  {
    return HAL_ERROR;
  }
  return HAL_I2C_Mem_Write(dev->hi2c, MCP23017_HAL_ADDR(dev), reg,
                           I2C_MEMADD_SIZE_8BIT, &val, 1U, MCP23017_I2C_TIMEOUT);
}

/**
  * @brief  Read one 8-bit device register over I2C.
  * @param  dev : [in]  bound driver instance; dev->hi2c must be non-NULL.
  * @param  reg : [in]  register address (bank-0 map).
  * @param  val : [out] destination for the read byte.
  * @retval HAL_OK    register read into @p val.
  * @retval HAL_ERROR @p dev, dev->hi2c or @p val is NULL.
  * @retval other     HAL status propagated from HAL_I2C_Mem_Read().
  */
HAL_StatusTypeDef MCP23017_ReadReg(MCP23017_t *dev, uint8_t reg, uint8_t *val)
{
  if (dev == NULL || dev->hi2c == NULL || val == NULL)
  {
    return HAL_ERROR;
  }
  return HAL_I2C_Mem_Read(dev->hi2c, MCP23017_HAL_ADDR(dev), reg,
                          I2C_MEMADD_SIZE_8BIT, val, 1U, MCP23017_I2C_TIMEOUT);
}

/**
  * @brief  Write an A/B register pair as one 16-bit value over I2C.
  * @note   Relies on sequential addressing (SEQOP=0, bank 0): byte 0 goes to
  *         the port-A register @p reg_a, byte 1 to the adjacent port-B register.
  *         Value is little-endian across the pair (low byte = port A).
  * @param  dev   : [in] bound driver instance; dev->hi2c must be non-NULL.
  * @param  reg_a : [in] port-A register address of the pair (e.g. IODIRA).
  * @param  val   : [in] 16-bit value; low byte -> port A, high byte -> port B.
  * @retval HAL_OK    both bytes written.
  * @retval HAL_ERROR @p dev or dev->hi2c is NULL.
  * @retval other     HAL status propagated from HAL_I2C_Mem_Write().
  */
HAL_StatusTypeDef MCP23017_WriteReg16(MCP23017_t *dev, uint8_t reg_a, uint16_t val)
{
  uint8_t buf[2];

  if (dev == NULL || dev->hi2c == NULL)
  {
    return HAL_ERROR;
  }
  /* Sequential addressing: byte 0 -> port-A reg, byte 1 -> port-B reg. */
  buf[0] = (uint8_t)(val & 0xFFU);
  buf[1] = (uint8_t)(val >> 8);
  return HAL_I2C_Mem_Write(dev->hi2c, MCP23017_HAL_ADDR(dev), reg_a,
                           I2C_MEMADD_SIZE_8BIT, buf, 2U, MCP23017_I2C_TIMEOUT);
}

/**
  * @brief  Read an A/B register pair as one 16-bit value over I2C.
  * @note   Sequential addressing companion to MCP23017_WriteReg16(); the two
  *         bytes are reassembled little-endian (port A = low byte).
  * @param  dev   : [in]  bound driver instance; dev->hi2c must be non-NULL.
  * @param  reg_a : [in]  port-A register address of the pair (e.g. GPIOA).
  * @param  val   : [out] destination for the reassembled 16-bit value.
  * @retval HAL_OK    pair read into @p val.
  * @retval HAL_ERROR @p dev, dev->hi2c or @p val is NULL.
  * @retval other     HAL status propagated from HAL_I2C_Mem_Read().
  */
HAL_StatusTypeDef MCP23017_ReadReg16(MCP23017_t *dev, uint8_t reg_a, uint16_t *val)
{
  uint8_t buf[2];
  HAL_StatusTypeDef st;

  if (dev == NULL || dev->hi2c == NULL || val == NULL)
  {
    return HAL_ERROR;
  }
  st = HAL_I2C_Mem_Read(dev->hi2c, MCP23017_HAL_ADDR(dev), reg_a,
                        I2C_MEMADD_SIZE_8BIT, buf, 2U, MCP23017_I2C_TIMEOUT);
  if (st == HAL_OK)
  {
    *val = (uint16_t)buf[0] | ((uint16_t)buf[1] << 8);
  }
  return st;
}

/* -------------------------------------------------------------------------- */
/* Init / probe                                                               */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Initialise an expander to a defined, all-outputs-low state.
  * @note   Computes the 7-bit address from the base address and the A2:A0
  *         straps, enables hardware addressing (IOCON.HAEN), latches all
  *         outputs low, then sets every pin as an output. Ordering guarantees
  *         mux enables / relay drivers come up de-asserted.
  * @param  dev    : [out] driver instance to populate; must be non-NULL.
  * @param  hi2c   : [in]  I2C handle the expander hangs off; must be non-NULL.
  * @param  a2a1a0 : [in]  hardware address straps, 0..7.
  * @retval HAL_OK    expander initialised; olat_cache reset to 0.
  * @retval HAL_ERROR @p dev/@p hi2c is NULL, or @p a2a1a0 > 7.
  * @retval other     first failing HAL status from the setup writes.
  */
HAL_StatusTypeDef MCP23017_Init(MCP23017_t *dev, I2C_HandleTypeDef *hi2c, uint8_t a2a1a0)
{
  HAL_StatusTypeDef st;

  if (dev == NULL || hi2c == NULL || a2a1a0 > 7U)
  {
    return HAL_ERROR;
  }

  dev->hi2c       = hi2c;
  dev->addr7      = (uint8_t)(MCP23017_ADDR_BASE | a2a1a0);
  dev->olat_cache = 0x0000U;

  /* Keep the power-on default map (BANK=0, SEQOP=0) but enable hardware
   * address pins so the A2:A0 straps are honoured. */
  st = MCP23017_WriteReg(dev, MCP23017_REG_IOCON, MCP23017_IOCON_HAEN);
  if (st != HAL_OK)
  {
    return st;
  }

  /* Drive everything to a defined, safe state before enabling outputs:
   * latch low first, then turn all pins into outputs. This guarantees mux
   * enables / relay drivers come up de-asserted. */
  st = MCP23017_WriteReg16(dev, MCP23017_REG_OLATA, 0x0000U);
  if (st != HAL_OK)
  {
    return st;
  }
  st = MCP23017_SetDirection(dev, 0x0000U);   /* 0 = output on all 16 pins */
  if (st == HAL_OK)
  {
    dev->olat_cache = 0x0000U;
  }
  return st;
}

/**
  * @brief  Probe whether the expander acknowledges on the I2C bus.
  * @param  dev : [in] bound driver instance; dev->hi2c must be non-NULL.
  * @retval HAL_OK    device acknowledged within the retry budget.
  * @retval HAL_ERROR @p dev or dev->hi2c is NULL.
  * @retval other     HAL status propagated from HAL_I2C_IsDeviceReady().
  */
HAL_StatusTypeDef MCP23017_IsReady(MCP23017_t *dev)
{
  if (dev == NULL || dev->hi2c == NULL)
  {
    return HAL_ERROR;
  }
  return HAL_I2C_IsDeviceReady(dev->hi2c, MCP23017_HAL_ADDR(dev), 3U,
                               MCP23017_I2C_TIMEOUT);
}

/* -------------------------------------------------------------------------- */
/* High-level port access                                                     */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Set the data direction of all 16 pins (IODIRA/B).
  * @param  dev      : [in] bound driver instance.
  * @param  dir_mask : [in] per-pin direction bits; 1 = input, 0 = output.
  * @retval HAL status from the underlying MCP23017_WriteReg16().
  */
HAL_StatusTypeDef MCP23017_SetDirection(MCP23017_t *dev, uint16_t dir_mask)
{
  return MCP23017_WriteReg16(dev, MCP23017_REG_IODIRA, dir_mask);
}

/**
  * @brief  Enable or disable the 100k input pull-ups on all 16 pins (GPPUA/B).
  * @param  dev     : [in] bound driver instance.
  * @param  pu_mask : [in] per-pin pull-up bits; 1 = pull-up enabled.
  * @retval HAL status from the underlying MCP23017_WriteReg16().
  */
HAL_StatusTypeDef MCP23017_SetPullups(MCP23017_t *dev, uint16_t pu_mask)
{
  return MCP23017_WriteReg16(dev, MCP23017_REG_GPPUA, pu_mask);
}

/**
  * @brief  Drive all 16 output latches to @p val (OLATA/B).
  * @note   On success the shadow olat_cache is updated so single-pin updates
  *         via MCP23017_WritePin() can do read-modify-write without a bus read.
  * @param  dev : [in] bound driver instance.
  * @param  val : [in] 16-bit output pattern; low byte -> port A.
  * @retval HAL_OK    latches written and cache updated.
  * @retval other     HAL status propagated from MCP23017_WriteReg16().
  */
HAL_StatusTypeDef MCP23017_WritePins(MCP23017_t *dev, uint16_t val)
{
  HAL_StatusTypeDef st = MCP23017_WriteReg16(dev, MCP23017_REG_OLATA, val);
  if (st == HAL_OK)
  {
    dev->olat_cache = val;
  }
  return st;
}

/**
  * @brief  Read the live logic level of all 16 pins (GPIOA/B).
  * @param  dev : [in]  bound driver instance.
  * @param  val : [out] destination for the 16-bit pin state; low byte = port A.
  * @retval HAL status from the underlying MCP23017_ReadReg16().
  */
HAL_StatusTypeDef MCP23017_ReadPins(MCP23017_t *dev, uint16_t *val)
{
  return MCP23017_ReadReg16(dev, MCP23017_REG_GPIOA, val);
}

/**
  * @brief  Set or clear a single output pin without disturbing the others.
  * @note   Read-modify-write against the cached latch value (olat_cache), so no
  *         bus read is needed; the full 16-bit latch is then rewritten.
  * @param  dev   : [in] bound driver instance.
  * @param  pin   : [in] pin index 0..15 (0..7 = port A, 8..15 = port B).
  * @param  state : [in] non-zero drives the pin high, zero drives it low.
  * @retval HAL_OK    latch updated.
  * @retval HAL_ERROR @p dev is NULL or @p pin > 15.
  * @retval other     HAL status propagated from MCP23017_WritePins().
  */
HAL_StatusTypeDef MCP23017_WritePin(MCP23017_t *dev, uint8_t pin, uint8_t state)
{
  uint16_t next;

  if (dev == NULL || pin > 15U)
  {
    return HAL_ERROR;
  }

  next = dev->olat_cache;
  if (state != 0U)
  {
    next |= (uint16_t)(1U << pin);
  }
  else
  {
    next &= (uint16_t)~(1U << pin);
  }

  return MCP23017_WritePins(dev, next);
}
