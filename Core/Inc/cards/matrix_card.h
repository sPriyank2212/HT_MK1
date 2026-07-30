/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    matrix_card.h
  * @brief   Matrix Card control: routes any of the 256 harness pins onto the
  *          HI or LO analogue bus, and (for 4-wire work) onto the matching
  *          sense bus.
  *
  *          Hardware (per Matrix_Card-6 / Control_Card-4, 2026-07):
  *            - FORCE array: 32x CD4067BF3A, HI bank (16 muxes, HI1..HI256 ->
  *              HI_COM) and LO bank (16 muxes, LO1..LO256 -> LO_COM). Enables
  *              HI_EN1..16 from U101, LO_EN1..16 from U102.
  *            - SENSE array: a further 32x CD4067BF3A tapping the SAME harness
  *              pins onto HI_SENSE / LO_SENSE, read differentially by the
  *              ADS124S08. Enables HI_SENSE_EN1..16 from U66 (0x23),
  *              LO_SENSE_EN1..16 from U67 (0x24).
  *            - Channel select is a SHARED 4-bit bus per bank, and both arrays
  *              share it: selecting harness pin p on the force array selects
  *              the same pin on the sense array automatically. Only the bank
  *              ENABLE has to be mirrored.
  *            - The select lines are NOT MCU GPIO. They come from MCP23017 U21
  *              on the Control Card (I2C3), which also carries the two spare
  *              I2C_EN lines.
  *
  *          To route harness pin p (1..256) onto a bus:
  *            mux     = (p-1) >> 4     (0..15) -> assert that one EN
  *            channel = (p-1) & 0x0F   (0..15) -> drive S[3:0] via U21
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __MATRIX_CARD_H
#define __MATRIX_CARD_H

#ifdef __cplusplus
extern "C" {
#endif

#include "drivers/mcp23017.h"
#include "drivers/ad7476.h"

/* -------------------------------------------------------------------------- */
/* Build-time configuration                                                   */
/* -------------------------------------------------------------------------- */

/* CD4067 ~E (pin 15) is active-low. CONFIRMED against Matrix_Card-6: every E
 * pin on both arrays (R1..R32 on the force sheet, R33..R64 on the sense sheet)
 * carries a 100k pull-up to +3V3. So an expander bit of 1 DISABLES its mux, 0
 * ENABLES it, and every mux is open while the MCP23017s are still in their
 * power-on high-Z input state. There is deliberately no active-high variant:
 * the opposite polarity would close all 512 paths whenever the expanders are
 * unpowered or uninitialised. */
#define MATRIX_EN_ALL_OFF        0xFFFFU
#define MATRIX_EN_PATTERN(mux)   ((uint16_t)(0xFFFFU & ~(1U << (mux))))

/* MCP23017 hardware straps (A2:A0), offset from MCP23017_ADDR_BASE (0x20).
 * The sense straps are annotated on Matrix_Card-6 sheet 9; the force straps are
 * not annotated on sheet 3 and are assumed - confirm by bus scan (BU-03). */
#define MATRIX_HI_MCP_STRAP        0U   /* U101 -> 0x20, HI_EN1..16       (assumed) */
#define MATRIX_LO_MCP_STRAP        1U   /* U102 -> 0x21, LO_EN1..16       (assumed) */
#define MATRIX_HI_SENSE_MCP_STRAP  3U   /* U66  -> 0x23, HI_SENSE_EN1..16 (annotated) */
#define MATRIX_LO_SENSE_MCP_STRAP  4U   /* U67  -> 0x24, LO_SENSE_EN1..16 (annotated) */

/* U21, the channel-address expander on the Control Card. Shares I2C3 with the
 * Matrix expanders (they sit behind the isolator, U21 does not), so its strap
 * must avoid 0x20/0x21 and 0x23/0x24/0x25. Not annotated - confirm by scan. */
#ifndef MATRIX_SEL_MCP_STRAP
#define MATRIX_SEL_MCP_STRAP       7U   /* -> 0x27 (assumed) */
#endif

/* U21 bit layout, in the mcp23017 driver's 16-bit packing (bits 0..7 = GPA0..7,
 * bits 8..15 = GPB0..7), per Control_Card-4 sheet 11:
 *   GPA0..GPA3 = LO_S1..LO_S4  (= Matrix LO_S0..S3), LSB first
 *   GPA4..GPA7 = HI_S1..HI_S4  (= Matrix HI_S0..S3), LSB first
 *   GPB0, GPB1 = I2C_EN1, I2C_EN2 - leftover spares with no consumer on any
 *                card (PROJECT_LOG CL-06). Held low and never driven otherwise.
 *   GPB2..GPB7 = unused
 * Both channel addresses therefore live in one byte, so a HI+LO pair costs a
 * single I2C write rather than two. */
#define MATRIX_SEL_LO_SHIFT      0U
#define MATRIX_SEL_HI_SHIFT      4U
#define MATRIX_SEL_NIBBLE_MASK   0x0FU
#define MATRIX_SEL_SPARE_DEFAULT 0x0000U   /* I2C_EN1/2 and unused GPB bits */

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
  MCP23017_t hi_en;        /* U101 - HI_EN1..16       (force)             */
  MCP23017_t lo_en;        /* U102 - LO_EN1..16       (force)             */
  MCP23017_t hi_sense_en;  /* U66  - HI_SENSE_EN1..16 (sense)             */
  MCP23017_t lo_sense_en;  /* U67  - LO_SENSE_EN1..16 (sense)             */
  MCP23017_t sel;          /* U21  - shared channel address (Control Card)*/
  uint16_t   sel_cache;    /* shadow of the U21 output word               */
  uint8_t    sense_paired; /* 1 = mirror every enable onto the sense array */
  AD7476_t   adc;          /* U33 on SPI1 - reads HI_COM (continuity)     */
  float      vref;         /* matrix ADC reference, volts (+3V3)          */
} MatrixCard_t;

/* -------------------------------------------------------------------------- */
/* API                                                                        */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Initialise all five expanders and bring the matrix to all-open.
  * @note   U21 (select) sits directly on the bus; the four enable expanders sit
  *         behind the Matrix-card isolator on the same MCU peripheral.
  * @param  m    instance
  * @param  hi2c I2C bus shared by U21 and the Matrix expanders
  * @retval HAL status (first failing operation)
  */
HAL_StatusTypeDef MatrixCard_Init(MatrixCard_t *m, I2C_HandleTypeDef *hi2c);

/**
  * @brief  Mirror every bank enable onto the sense array (needed for 4-wire
  *         resistance, pointless for continuity).
  * @note   Off by default. Continuity leaves it off so a 256x256 discovery scan
  *         does not pay for two extra I2C writes per point.
  * @param  m  instance
  * @param  on 0 = force array only, non-zero = force + sense
  */
HAL_StatusTypeDef MatrixCard_SetSensePaired(MatrixCard_t *m, uint8_t on);

/**
  * @brief  Open every mux on both banks, both arrays (idle / safe state).
  */
HAL_StatusTypeDef MatrixCard_AllOff(MatrixCard_t *m);

/**
  * @brief  Open every mux on a single bank (force array, and sense array when
  *         pairing is enabled).
  */
HAL_StatusTypeDef MatrixCard_BankOff(MatrixCard_t *m, MatrixBank_t bank);

/**
  * @brief  Connect one harness pin (1..256) onto the given bank's common bus.
  *         Break-before-make: the bank is opened, the shared select nibble is
  *         driven via U21, then exactly one enable is asserted.
  */
HAL_StatusTypeDef MatrixCard_SelectPin(MatrixCard_t *m, MatrixBank_t bank, uint16_t pin);

/**
  * @brief  Connect a HI pin and a LO pin simultaneously. Both channel addresses
  *         are written to U21 in one transaction.
  */
HAL_StatusTypeDef MatrixCard_ConnectPair(MatrixCard_t *m, uint16_t hi_pin, uint16_t lo_pin);

/**
  * @brief  Bind the on-card AD7476 (U33, reads HI_COM).
  * @note   CONTINUITY ONLY as of Matrix_Card-6. Resistance is measured by the
  *         ADS124S08 across HI_SENSE/LO_SENSE, not by this ADC.
  */
HAL_StatusTypeDef MatrixCard_InitAdc(MatrixCard_t *m, SPI_HandleTypeDef *spi,
                                     GPIO_TypeDef *cs_port, uint16_t cs_pin, float vref);

/**
  * @brief  Read the HI_COM node via the matrix ADC (raw 12-bit code / volts).
  */
HAL_StatusTypeDef MatrixCard_ReadRaw(MatrixCard_t *m, uint16_t *code);
HAL_StatusTypeDef MatrixCard_ReadVolts(MatrixCard_t *m, float *volts);

#ifdef __cplusplus
}
#endif

#endif /* __MATRIX_CARD_H */
