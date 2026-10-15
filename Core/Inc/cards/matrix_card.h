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

/* BUFF2 - sense enables. Straps confirmed 2026-08-11 against Matrix_Card-7.pdf
 * sheet 9 (HW-12): each expander's binary address label was read directly off
 * the schematic (crops of U66/U67/U69/U107/U108), not inferred. They are NOT
 * the sequential 4..7 block the earlier revision used - straps 3, 5 and 7 are
 * unused on this segment. */
#define MATRIX_HI_SNS_LO_STRAP   0U   /* U66  0x20  HI_SENSE_EN1..16  */
#define MATRIX_HI_SNS_HI_STRAP   2U   /* U67  0x22  HI_SENSE_EN17..32 */
#define MATRIX_LO_SNS_LO_STRAP   4U   /* U107 0x24  LO_SENSE_EN1..16  */
#define MATRIX_LO_SNS_HI_STRAP   6U   /* U108 0x26  LO_SENSE_EN17..32 */

/* U69, the ADS124S08 control expander.
 *
 * RESOLVED 2026-08-11 (HW-12): the schematic swap that brought in
 * Matrix_Card-7.pdf also moved U69 to BUFF2 at strap 1 (0x21), sitting between
 * U66 (0x20) and U67 (0x22) - it no longer collides with U101 (which stays at
 * 0x20 on BUFF1, the force segment). Confirmed by reading both sheets, not
 * assumed. This layer never touches U69 - it belongs to the ADS124S08 driver
 * (bsp/board.c) - but the strap is recorded here since it is the matrix's own
 * segment-select (U21/BUFF2) that every U69 access must go through first. */
#ifndef MATRIX_ADCCTL_SEG
#define MATRIX_ADCCTL_SEG        MATRIX_SEG_SENSE  /* BUFF2, confirmed */
#endif
#ifndef MATRIX_ADCCTL_STRAP
#define MATRIX_ADCCTL_STRAP      1U                /* -> 0x21 on that segment */
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

/* U21's own strap. Not annotated - confirm by scan. U21 is local to the
 * Control Card on I2C3 and does NOT share a bus with the Matrix expanders -
 * see the bus-sharing note above matrix_card_t below. */
#ifndef MATRIX_SEL_MCP_STRAP
#define MATRIX_SEL_MCP_STRAP     7U   /* -> 0x27 (assumed) */
#endif

/* -------------------------------------------------------------------------- */
/* Card-level bus sharing (confirmed 2026-08-11, see Doc/i2c_bus_sharing.md)   */
/* -------------------------------------------------------------------------- */

/* The Matrix Card's own onboard expanders (everything above except U21, which
 * is local to the Control Card on I2C3) sit on the SAME isolated I2C bus as
 * HV Card 1 - confirmed against real hardware, not inferred. Every card on
 * that bus straps its expanders to the same 0x20..0x27, so the Matrix Card
 * must be switched onto the bus the same way each HV card is: one dedicated
 * enable line, asserted only for the duration of a transaction. This one is
 * HV_Card_EN1 (J1 is the Matrix Card's own connector - see PROJECT_LOG HW-09),
 * reused here under its own name so this file does not need to know about the
 * HV card slots. */
#define MATRIX_BUS_EN_SETTLE_MS  1U

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

  /* This card's segment enable on the shared I2C bus (HV_Card_EN1) - must be
   * asserted before, and deasserted after, every access to hi_en/lo_en/
   * hi_sns/lo_sns above (and, via MatrixCard_BusClaim/Release, U69 - see
   * bsp/board.c). Never needed for sel (U21), which is local to I2C3. */
  GPIO_TypeDef *en_port;    uint16_t en_pin;
} MatrixCard_t;

/* -------------------------------------------------------------------------- */
/* API                                                                        */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Bring up U21 and all eight enable expanders, and open every mux.
  * @note   Walks both segments in turn. Leaves the force segment selected and
  *         sense pairing OFF. Claims the shared-bus enable (@p en_port/
  *         @p en_pin) around the expander bring-up, same as every other
  *         function that touches hi_en/lo_en/hi_sns/lo_sns.
  * @param  m          instance
  * @param  hi2c_local  I2C bus for U21 only (I2C3 - local to the Control Card)
  * @param  hi2c_shared I2C bus for the eight Matrix-card expanders (shared
  *                      with the HV cards - see the header note above)
  * @param  en_port/en_pin  this card's segment-enable line on the shared bus
  *                          (HV_Card_EN1)
  * @retval HAL status (first failing operation)
  */
HAL_StatusTypeDef MatrixCard_Init(MatrixCard_t *m, I2C_HandleTypeDef *hi2c_local,
                                  I2C_HandleTypeDef *hi2c_shared,
                                  GPIO_TypeDef *en_port, uint16_t en_pin);

/**
  * @brief  Put the Matrix Card, and only the Matrix Card, on the shared bus.
  * @note   Public because U69 (the ADS124S08 control expander) sits on this
  *         same shared bus but is driven from bsp/board.c, not from here -
  *         see the io callbacks in board_init_ads124s08(). Every caller must
  *         pair this with MatrixCard_BusRelease(), including on error paths.
  */
void MatrixCard_BusClaim(MatrixCard_t *m);

/**
  * @brief  Take the Matrix Card back off the shared bus.
  */
void MatrixCard_BusRelease(MatrixCard_t *m);

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
