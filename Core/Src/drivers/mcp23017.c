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

HAL_StatusTypeDef MCP23017_WriteReg(MCP23017_t *dev, uint8_t reg, uint8_t val)
{
  if (dev == NULL || dev->hi2c == NULL)
  {
    return HAL_ERROR;
  }
  return HAL_I2C_Mem_Write(dev->hi2c, MCP23017_HAL_ADDR(dev), reg,
                           I2C_MEMADD_SIZE_8BIT, &val, 1U, MCP23017_I2C_TIMEOUT);
}

HAL_StatusTypeDef MCP23017_ReadReg(MCP23017_t *dev, uint8_t reg, uint8_t *val)
{
  if (dev == NULL || dev->hi2c == NULL || val == NULL)
  {
    return HAL_ERROR;
  }
  return HAL_I2C_Mem_Read(dev->hi2c, MCP23017_HAL_ADDR(dev), reg,
                          I2C_MEMADD_SIZE_8BIT, val, 1U, MCP23017_I2C_TIMEOUT);
}

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

HAL_StatusTypeDef MCP23017_SetDirection(MCP23017_t *dev, uint16_t dir_mask)
{
  return MCP23017_WriteReg16(dev, MCP23017_REG_IODIRA, dir_mask);
}

HAL_StatusTypeDef MCP23017_SetPullups(MCP23017_t *dev, uint16_t pu_mask)
{
  return MCP23017_WriteReg16(dev, MCP23017_REG_GPPUA, pu_mask);
}

HAL_StatusTypeDef MCP23017_WritePins(MCP23017_t *dev, uint16_t val)
{
  HAL_StatusTypeDef st = MCP23017_WriteReg16(dev, MCP23017_REG_OLATA, val);
  if (st == HAL_OK)
  {
    dev->olat_cache = val;
  }
  return st;
}

HAL_StatusTypeDef MCP23017_ReadPins(MCP23017_t *dev, uint16_t *val)
{
  return MCP23017_ReadReg16(dev, MCP23017_REG_GPIOA, val);
}

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
