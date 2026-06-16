/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    mcp23017.h
  * @brief   Driver for the Microchip MCP23017 16-bit I2C GPIO expander.
  *
  *          Used across the Harness Tester:
  *            - Matrix Card : 2x MCP23017 drive the 32 mux enable lines
  *            - HV Card     : 8x MCP23017 (per board) drive the 128 reed-relay
  *                            gate-driver MOSFETs
  *
  *          The driver is bus-agnostic: each instance is bound to an I2C
  *          handle and a 7-bit address, so the same code serves every
  *          expander regardless of which (isolated or non-isolated) I2C bus
  *          it lives on.
  *
  *          Assumes the power-on default IOCON.BANK = 0 register map with
  *          sequential addressing enabled (IOCON.SEQOP = 0), so a 16-bit
  *          access to a port-A register auto-increments into the matching
  *          port-B register.
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __MCP23017_H
#define __MCP23017_H

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"   /* pulls in stm32g4xx_hal.h (I2C_HandleTypeDef, HAL_StatusTypeDef) */

/* -------------------------------------------------------------------------- */
/* Register map (IOCON.BANK = 0)                                              */
/* -------------------------------------------------------------------------- */
#define MCP23017_REG_IODIRA    0x00U  /* I/O direction      (1 = input)       */
#define MCP23017_REG_IODIRB    0x01U
#define MCP23017_REG_IPOLA     0x02U  /* input polarity                       */
#define MCP23017_REG_IPOLB     0x03U
#define MCP23017_REG_GPINTENA  0x04U  /* interrupt-on-change enable           */
#define MCP23017_REG_GPINTENB  0x05U
#define MCP23017_REG_DEFVALA   0x06U
#define MCP23017_REG_DEFVALB   0x07U
#define MCP23017_REG_INTCONA   0x08U
#define MCP23017_REG_INTCONB   0x09U
#define MCP23017_REG_IOCON     0x0AU  /* configuration (mirrored at 0x0B)     */
#define MCP23017_REG_GPPUA     0x0CU  /* pull-up enable                       */
#define MCP23017_REG_GPPUB     0x0DU
#define MCP23017_REG_INTFA     0x0EU
#define MCP23017_REG_INTFB     0x0FU
#define MCP23017_REG_INTCAPA   0x10U
#define MCP23017_REG_INTCAPB   0x11U
#define MCP23017_REG_GPIOA     0x12U  /* read = port state                    */
#define MCP23017_REG_GPIOB     0x13U
#define MCP23017_REG_OLATA     0x14U  /* output latch                         */
#define MCP23017_REG_OLATB     0x15U

/* IOCON bit definitions */
#define MCP23017_IOCON_BANK    0x80U
#define MCP23017_IOCON_MIRROR  0x40U
#define MCP23017_IOCON_SEQOP   0x20U
#define MCP23017_IOCON_DISSLW  0x10U
#define MCP23017_IOCON_HAEN    0x08U
#define MCP23017_IOCON_ODR     0x04U
#define MCP23017_IOCON_INTPOL  0x02U

/* Base hardware address; OR with the A2:A0 strap value (0..7).               */
#define MCP23017_ADDR_BASE     0x20U

/* Default per-transfer timeout (ms). */
#ifndef MCP23017_I2C_TIMEOUT
#define MCP23017_I2C_TIMEOUT   100U
#endif

/* -------------------------------------------------------------------------- */
/* Instance                                                                   */
/* -------------------------------------------------------------------------- */
typedef struct
{
  I2C_HandleTypeDef *hi2c;        /* bus this expander is wired to            */
  uint8_t            addr7;       /* 7-bit device address (0x20..0x27)        */
  uint16_t           olat_cache;  /* shadow of the output latch (A=lo, B=hi)  */
} MCP23017_t;

/* -------------------------------------------------------------------------- */
/* API                                                                        */
/*                                                                            */
/* 16-bit values are packed port-A in bits 0..7 (GPA0..7) and port-B in       */
/* bits 8..15 (GPB0..7). Direction mask: 1 = input, 0 = output (MCP default   */
/* is all-input).                                                             */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Bind an instance to a bus/address and apply a known-good baseline
  *         (all pins outputs driven low, sequential 16-bit addressing).
  * @param  dev    instance to initialise
  * @param  hi2c   I2C bus handle
  * @param  a2a1a0 hardware strap value 0..7 (added to MCP23017_ADDR_BASE)
  * @retval HAL status
  */
HAL_StatusTypeDef MCP23017_Init(MCP23017_t *dev, I2C_HandleTypeDef *hi2c, uint8_t a2a1a0);

/**
  * @brief  Probe the device on the bus (HAL_I2C_IsDeviceReady).
  */
HAL_StatusTypeDef MCP23017_IsReady(MCP23017_t *dev);

/* Raw register access ------------------------------------------------------ */
HAL_StatusTypeDef MCP23017_WriteReg(MCP23017_t *dev, uint8_t reg, uint8_t val);
HAL_StatusTypeDef MCP23017_ReadReg(MCP23017_t *dev, uint8_t reg, uint8_t *val);
HAL_StatusTypeDef MCP23017_WriteReg16(MCP23017_t *dev, uint8_t reg_a, uint16_t val);
HAL_StatusTypeDef MCP23017_ReadReg16(MCP23017_t *dev, uint8_t reg_a, uint16_t *val);

/* High-level port access --------------------------------------------------- */

/**
  * @brief  Set the data direction for all 16 pins (1 = input, 0 = output).
  */
HAL_StatusTypeDef MCP23017_SetDirection(MCP23017_t *dev, uint16_t dir_mask);

/**
  * @brief  Enable/disable the 100k internal pull-ups (1 = enabled), 16-bit.
  */
HAL_StatusTypeDef MCP23017_SetPullups(MCP23017_t *dev, uint16_t pu_mask);

/**
  * @brief  Drive all 16 outputs at once and refresh the shadow latch.
  */
HAL_StatusTypeDef MCP23017_WritePins(MCP23017_t *dev, uint16_t val);

/**
  * @brief  Read the live state of all 16 pins.
  */
HAL_StatusTypeDef MCP23017_ReadPins(MCP23017_t *dev, uint16_t *val);

/**
  * @brief  Drive a single output (0..15) without disturbing the others.
  *         Uses the shadow latch, so only one bus write is issued.
  * @param  pin   0..15 (0..7 = GPA0..7, 8..15 = GPB0..7)
  * @param  state 0 = low, non-zero = high
  */
HAL_StatusTypeDef MCP23017_WritePin(MCP23017_t *dev, uint8_t pin, uint8_t state);

#ifdef __cplusplus
}
#endif

#endif /* __MCP23017_H */
