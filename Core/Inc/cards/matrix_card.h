/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    matrix_card.h
  * @brief   Matrix Card control: routes any of the 256 harness pins onto the
  *          HI or LO analogue bus.
  *
  *          Hardware (per Matrix_Card.kicad_sch):
  *            - 32x CD4067BF3A 16:1 muxes, split into a HI bank (16 muxes,
  *              HI1..HI256 -> HI_COM) and a LO bank (16 muxes, LO1..LO256 ->
  *              LO_COM).
  *            - Channel select is a SHARED 4-bit bus per bank: HI_S0..3 /
  *              LO_S0..3, driven by MCU GPIO over the J101 ribbon.
  *            - Mux select is ONE-HOT enable: HI_EN1..16 from MCP23017 U101,
  *              LO_EN1..16 from MCP23017 U102 (shared isolated I2C).
  *
  *          To route harness pin p (1..256) onto a bus:
  *            mux     = (p-1) >> 4     (0..15) -> assert that one EN
  *            channel = (p-1) & 0x0F   (0..15) -> drive S[3:0]
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __MATRIX_CARD_H
#define __MATRIX_CARD_H

#ifdef __cplusplus
extern "C" {
#endif

#include "drivers/mcp23017.h"

/* -------------------------------------------------------------------------- */
/* Build-time configuration                                                   */
/* -------------------------------------------------------------------------- */

/* CD4067 ~E (pin 15) is active-low: a mux conducts when its enable line is
 * LOW. If the board interposes an inverting buffer between the MCP23017 and
 * the mux ~E pins, set this to 0. */
#ifndef MATRIX_EN_ACTIVE_LOW
#define MATRIX_EN_ACTIVE_LOW   1
#endif

/* MCP23017 hardware-strap addresses (A2:A0), per board decision:
 * U101 (HI enables) = 0x20, U102 (LO enables) = 0x21. */
#define MATRIX_HI_MCP_STRAP    0U   /* -> I2C 0x20 */
#define MATRIX_LO_MCP_STRAP    1U   /* -> I2C 0x21 */

#define MATRIX_PIN_MIN         1U
#define MATRIX_PIN_MAX         256U
#define MATRIX_MUX_PER_BANK    16U
#define MATRIX_CH_PER_MUX      16U

/* -------------------------------------------------------------------------- */
/* Types                                                                      */
/* -------------------------------------------------------------------------- */

typedef enum
{
  MATRIX_BANK_HI = 0,
  MATRIX_BANK_LO = 1
} MatrixBank_t;

typedef struct
{
  GPIO_TypeDef *port;   /* NULL = not yet wired (Control-Card connector TBD) */
  uint16_t      pin;
} MatrixGpio_t;

/* The 4 shared select lines for each bank, S0 (lsb) .. S3 (msb). */
typedef struct
{
  MatrixGpio_t hi_sel[4];   /* HI_S0..HI_S3 */
  MatrixGpio_t lo_sel[4];   /* LO_S0..LO_S3 */
} MatrixSelectMap_t;

typedef struct
{
  MCP23017_t        hi_en;  /* U101 - HI_EN1..16 */
  MCP23017_t        lo_en;  /* U102 - LO_EN1..16 */
  MatrixSelectMap_t sel;
} MatrixCard_t;

/* -------------------------------------------------------------------------- */
/* API                                                                        */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Initialise both expanders and bring the matrix to all-open (no pin
  *         connected to either bus).
  * @param  m    instance
  * @param  hi2c I2C bus the two expanders share
  * @param  sel  GPIO map for the 8 shared select lines (may contain NULL ports
  *              until the Control-Card connector is finalised; those lines are
  *              simply skipped)
  * @retval HAL status (first failing operation)
  */
HAL_StatusTypeDef MatrixCard_Init(MatrixCard_t *m, I2C_HandleTypeDef *hi2c,
                                  const MatrixSelectMap_t *sel);

/**
  * @brief  Open every mux on both banks (idle / safe state).
  */
HAL_StatusTypeDef MatrixCard_AllOff(MatrixCard_t *m);

/**
  * @brief  Open every mux on a single bank.
  */
HAL_StatusTypeDef MatrixCard_BankOff(MatrixCard_t *m, MatrixBank_t bank);

/**
  * @brief  Connect one harness pin (1..256) onto the given bank's common bus.
  *         Drives the shared select lines and asserts exactly one enable
  *         (break-before-make: the bank is opened before the new select is
  *         applied).
  */
HAL_StatusTypeDef MatrixCard_SelectPin(MatrixCard_t *m, MatrixBank_t bank, uint16_t pin);

/**
  * @brief  Connect a HI pin and a LO pin simultaneously (the usual two-terminal
  *         measurement setup: stimulus on HI_COM, return on LO_COM).
  */
HAL_StatusTypeDef MatrixCard_ConnectPair(MatrixCard_t *m, uint16_t hi_pin, uint16_t lo_pin);

#ifdef __cplusplus
}
#endif

#endif /* __MATRIX_CARD_H */
