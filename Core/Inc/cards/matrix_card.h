/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    matrix_card.h
  * @brief   Matrix Card control: routes any of the 256 harness pins onto the
  *          HI or LO analogue bus, and onto the matching 4-wire sense bus.
  *
  *          Hardware: "Matrix_Card 2" (2026-07-30). This revision changed the
  *          geometry substantially from Matrix_Card-6 - see the notes below
  *          before assuming anything carries over.
  *
  *          MULTIPLEXERS - 128x CD74HC4051, 8:1 (was 32x CD4067BF3A, 16:1):
  *            force array : 32 HI (HI1..HI256 -> HI_COM), 32 LO (-> LO_COM)
  *            sense array : 32 HI (-> HI_SENSE),          32 LO (-> LO_SENSE)
  *          8:1 parts mean THREE channel-select bits, not four, and 32 enables
  *          per bank, not 16.
  *
  *          To route harness pin p (1..256):
  *            mux     = (p-1) >> 3     (0..31)  -> assert that one enable
  *            channel = (p-1) & 0x07   (0..7)   -> drive S[2:0]
  *
  *          TWO BUFFERED I2C SEGMENTS. Nine expanders will not fit in the
  *          MCP23017's eight addresses, so the bus is split by NTS0102DP level
  *          shifters, each enabled by one of the freed 4th select bits:
  *
  *            U141 OE = HI_S3 -> BUFF1 : force enables + the ADC-control expander
  *            U142 OE = LO_S3 -> BUFF2 : sense enables
  *
  *          Exactly one segment may be enabled at a time. Every expander access
  *          therefore costs a segment selection first - which is itself an I2C
  *          write to U21 on the Control Card.
  *
  *          ENABLE BIT ORDER IS BYTE-SWAPPED. Within each 16-enable block the
  *          schematic wires GPB0..7 to EN1..8 and GPA0..7 to EN9..16. In the
  *          mcp23017 driver's packing (bits 0..7 = GPA, 8..15 = GPB) that puts
  *          EN1..8 at bits 8..15 and EN9..16 at bits 0..7.
  *
  *          CD74HC4051 ~E is active-low with a 100k pull-up to +3V3 on every
  *          part, so an expander bit of 1 DISABLES and every mux is open while
  *          the MCP23017s are still in their power-on high-Z state.
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
/* Geometry                                                                   */
/* -------------------------------------------------------------------------- */

#define MATRIX_PIN_MIN          1U
#define MATRIX_PIN_MAX          256U
#define MATRIX_MUX_PER_BANK     32U    /* 8:1 parts */
#define MATRIX_CH_PER_MUX       8U
#define MATRIX_MUX_SHIFT        3U     /* (p-1) >> 3 */
#define MATRIX_CH_MASK          0x07U  /* (p-1) & 0x07 */
#define MATRIX_EN_PER_EXPANDER  16U
#define MATRIX_EXP_PER_BANK     2U     /* 32 enables over two expanders */

/* All-open enable word. E is active low, so 1 = disabled. */
#define MATRIX_EN_ALL_OFF       0xFFFFU

/* -------------------------------------------------------------------------- */
/* I2C segments and expander addresses                                        */
/* -------------------------------------------------------------------------- */

typedef enum
{
  MATRIX_SEG_FORCE = 0,   /* BUFF1, OE = HI_S3 */
  MATRIX_SEG_SENSE = 1    /* BUFF2, OE = LO_S3 */
} MatrixSeg_t;

/* BUFF1 - force enables. Straps read off Matrix_Card 2 sheet 3. */
#define MATRIX_HI_EN_LO_STRAP    0U   /* U101 0x20  HI_EN1..16  */
#define MATRIX_LO_EN_LO_STRAP    1U   /* U102 0x21  LO_EN1..16  */
#define MATRIX_HI_EN_HI_STRAP    2U   /* U105 0x22  HI_EN17..32 */
#define MATRIX_LO_EN_HI_STRAP    3U   /* U106 0x23  LO_EN17..32 */

/* BUFF2 - sense enables. Straps read off sheet 8. */
#define MATRIX_HI_SNS_LO_STRAP   4U   /* U66  0x24  HI_SENSE_EN1..16  */
#define MATRIX_HI_SNS_HI_STRAP   5U   /* U67  0x25  HI_SENSE_EN17..32 */
#define MATRIX_LO_SNS_LO_STRAP   6U   /* U107 0x26  LO_SENSE_EN1..16  */
#define MATRIX_LO_SNS_HI_STRAP   7U   /* U108 0x27  LO_SENSE_EN17..32 */

/* U69, the ADS124S08 control expander.
 *
 * !! As drawn it is strapped 0x20 on BUFF1, which COLLIDES with U101. Every
 *    HI_EN1..16 write also lands on U69 GPB0..3 = ADC_RST_1 / DRDY_1 /
 *    ADC_CS_1 / Start_SYNC_1, so the matrix and the ADC cannot be used together
 *    until it is restrapped. PROJECT_LOG: move it to BUFF2 @ 0x20.
 *
 * This layer never touches U69 - it belongs to the ADS124S08 driver - but the
 * collision is recorded here because it is the matrix writes that trip it. */
#ifndef MATRIX_ADCCTL_SEG
#define MATRIX_ADCCTL_SEG        MATRIX_SEG_SENSE  /* recommended: BUFF2 */
#endif
#ifndef MATRIX_ADCCTL_STRAP
#define MATRIX_ADCCTL_STRAP      0U                /* -> 0x20 on that segment */
#endif

/* -------------------------------------------------------------------------- */
/* U21 - channel address + segment select, on the Control Card (I2C3)         */
/* -------------------------------------------------------------------------- */

/* Control_Card-4 sheet 11 wires U21 GPA0..GPA7 to
 *   LO_S1, LO_S2, LO_S3, LO_S4, HI_S1, HI_S2, HI_S3, HI_S4
 * and the Matrix Card names the same eight wires LO_S0..S3 / HI_S0..S3, i.e.
 * the two cards number them from a different base. Mapping Control Sn+1 to
 * Matrix Sn gives the layout below, all inside GPA (bits 0..7):
 *
 *   bit 0..2  LO_S0..LO_S2   LO channel address
 *   bit 3     LO_S3          BUFF2 output enable
 *   bit 4..6  HI_S0..HI_S2   HI channel address
 *   bit 7     HI_S3          BUFF1 output enable
 *
 * VERIFY: the off-by-one mapping is inferred from the naming, and the two
 * cards' connector pinouts do not currently correspond (PROJECT_LOG HW-03).
 * Confirm against the final connector assignment before trusting a scan. */
#define MATRIX_SEL_LO_SHIFT      0U
#define MATRIX_SEL_BUFF2_OE_BIT  3U
#define MATRIX_SEL_HI_SHIFT      4U
#define MATRIX_SEL_BUFF1_OE_BIT  7U

/* NTS0102DP OE is active high: 1 enables that translator's outputs.
 * VERIFY against the datasheet before first use. */
#ifndef MATRIX_SEG_OE_ACTIVE_HIGH
#define MATRIX_SEG_OE_ACTIVE_HIGH  1
#endif

/* U21's own strap. Shares I2C3 with the Matrix expanders (which sit behind the
 * translators), so it must avoid 0x20..0x27. Not annotated - confirm by scan. */
#ifndef MATRIX_SEL_MCP_STRAP
#define MATRIX_SEL_MCP_STRAP     7U   /* -> 0x27 (assumed) */
#endif

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
  /* BUFF1 */
  MCP23017_t hi_en[MATRIX_EXP_PER_BANK];   /* HI_EN1..16, 17..32       */
  MCP23017_t lo_en[MATRIX_EXP_PER_BANK];   /* LO_EN1..16, 17..32       */
  /* BUFF2 */
  MCP23017_t hi_sns[MATRIX_EXP_PER_BANK];  /* HI_SENSE_EN1..16, 17..32 */
  MCP23017_t lo_sns[MATRIX_EXP_PER_BANK];  /* LO_SENSE_EN1..16, 17..32 */

  MCP23017_t  sel;          /* U21 - channel address + segment OEs       */
  uint16_t    sel_cache;    /* shadow of the U21 output word             */
  MatrixSeg_t seg;          /* which segment is currently enabled        */
  uint8_t     sense_paired; /* mirror every enable onto the sense array  */
} MatrixCard_t;

/* -------------------------------------------------------------------------- */
/* API                                                                        */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Bring up U21 and all eight enable expanders, and open every mux.
  * @note   Walks both segments in turn. Leaves the force segment selected and
  *         sense pairing OFF.
  * @param  m    instance
  * @param  hi2c I2C bus shared by U21 and (behind the translators) the Matrix
  *              expanders
  * @retval HAL status (first failing operation)
  */
HAL_StatusTypeDef MatrixCard_Init(MatrixCard_t *m, I2C_HandleTypeDef *hi2c);

/**
  * @brief  Enable exactly one I2C segment. No-op if already selected.
  * @note   Costs one I2C write to U21. Everything that touches an expander must
  *         go through here first.
  */
HAL_StatusTypeDef MatrixCard_SelectSegment(MatrixCard_t *m, MatrixSeg_t seg);

/**
  * @brief  Mirror every bank enable onto the sense array.
  * @note   Off by default - continuity does not need the sense taps, and a
  *         256x256 scan would otherwise pay two extra expander writes AND a
  *         segment switch per point.
  */
HAL_StatusTypeDef MatrixCard_SetSensePaired(MatrixCard_t *m, uint8_t on);

/**
  * @brief  Open every mux on both banks, both arrays.
  */
HAL_StatusTypeDef MatrixCard_AllOff(MatrixCard_t *m);

/**
  * @brief  Open every mux on one bank (force, plus sense when paired).
  */
HAL_StatusTypeDef MatrixCard_BankOff(MatrixCard_t *m, MatrixBank_t bank);

/**
  * @brief  Connect one harness pin (1..256) to the given bank's common bus.
  *         Break-before-make: the bank is opened, the shared 3-bit channel
  *         address is driven via U21, then exactly one enable is asserted.
  */
HAL_StatusTypeDef MatrixCard_SelectPin(MatrixCard_t *m, MatrixBank_t bank, uint16_t pin);

/**
  * @brief  Connect a HI pin and a LO pin. Both channel addresses live in one
  *         U21 byte, so they are staged and flushed together.
  */
HAL_StatusTypeDef MatrixCard_ConnectPair(MatrixCard_t *m, uint16_t hi_pin, uint16_t lo_pin);

/**
  * @brief  Map a 1-based harness pin to its mux index and channel.
  * @param  pin     [in]  1..256
  * @param  mux     [out] 0..31
  * @param  channel [out] 0..7
  * @retval HAL_OK, or HAL_ERROR if @p pin is out of range or a pointer is NULL.
  */
HAL_StatusTypeDef MatrixCard_MapPin(uint16_t pin, uint8_t *mux, uint8_t *channel);

#ifdef __cplusplus
}
#endif

#endif /* __MATRIX_CARD_H */
