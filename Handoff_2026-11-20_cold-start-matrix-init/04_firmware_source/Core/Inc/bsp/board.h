/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    board.h
  * @brief   Board support: binds the driver/card layers to the concrete HAL
  *          handles and pins, and exposes the global instances the test modules
  *          use. This is the single place where the still-open hardware points
  *          land - all such bindings are marked TODO/VERIFY here.
  *
  *          Bus/pin bindings below are best-guess placeholders pending:
  *            - Control-Card <-> Matrix connector (matrix select GPIOs)
  *            - Which I2C bus serves Matrix vs each HV board
  *            - CS pin assignments for SPI1 (ADC) and SPI2 (IDAC) - not yet in
  *              the generated GPIO config
  *            - OPT0_CNTR / HV_CARD_DT_x set to OUTPUT in CubeMX (now INPUT)
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __BOARD_H
#define __BOARD_H

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"
#include "i2c.h"
#include "spi.h"
#include "cards/matrix_card.h"
#include "cards/control_frontend.h"
#include "cards/hv_card.h"
#include "drivers/ads124s08.h"
#include "drivers/ds18b20.h"

/* Number of HV boards fitted in this build (1..4). HV card N is on Control Card
 * slot N (J1..J4, HV_Card_EN1..EN4); J1 is shared with the Matrix Card (HW-15). */
#ifndef BOARD_HV_COUNT
#define BOARD_HV_COUNT        1
#endif

/* ADC reference voltages. Confirmed from schematics:
 *   Control-Card AD7476 (U4) and Matrix-Card AD7476 (U33) run off +3V3.
 *   HV-Card AD7476 (U301/U302) run off +5V_ISO -> full-scale 5.0 V. */
#ifndef BOARD_VREF
#define BOARD_VREF            3.3f
#endif
#ifndef BOARD_VREF_HV
#define BOARD_VREF_HV         5.0f
#endif

/* Matrix stage of Board_Init(): attempts and the delay between them (the Matrix
 * Card can power up after the Control Card's firmware has started). */
#ifndef BOARD_MATRIX_TRIES
#define BOARD_MATRIX_TRIES      5
#endif
#ifndef BOARD_MATRIX_RETRY_MS
#define BOARD_MATRIX_RETRY_MS   250
#endif

/** @brief Attempts the Matrix stage of Board_Init() needed (1 = first try worked). */
uint8_t Board_MatrixTries(void);

/* Boot-failure bus scans (Board_ScanI2c3Log / Board_ScanMatrixBusLog): each whole
 * scan gives up after this many ms, and after this many consecutive HAL_BUSY
 * answers, and reports why - a scan can only ever report, never hang. They run
 * from the low-priority tScan thread once the kernel is up (tasks.c), after
 * SCAN_START_DELAY_MS, so the GUI handshake is answered first. */
#ifndef BOARD_SCAN_BUDGET_MS
#define BOARD_SCAN_BUDGET_MS  1500
#endif
#ifndef BOARD_SCAN_BUSY_MAX
#define BOARD_SCAN_BUSY_MAX   3
#endif

/* Global instances (defined in board.c). */
extern MatrixCard_t      g_matrix;
extern ControlFrontend_t g_frontend;
extern HvCard_t          g_hv[BOARD_HV_COUNT];
extern ADS124S08_t       g_ads124s08;   /* Matrix Card U68, SPI1 - see HW-12  */
extern DS18B20_t         g_ds18b20;     /* Control Card U2, PA0 - see HW-13   */

/**
  * @brief  Initialise every card/driver to a safe idle state.
  * @retval HAL_OK only if all sub-inits succeed.
  */
HAL_StatusTypeDef Board_Init(void);

/**
  * @brief  Query whether Board_Init() has run and every sub-init succeeded.
  * @note   Returns 0 before Board_Init() is called at all. The sequencer
  *         (proto.c) checks this before CONT/RES/INSUL RUN and >SAFE so a
  *         card that failed to bring up (unseated/missing/faulty) gets a
  *         clean ERR EHW instead of the run silently doing nothing against
  *         un-initialised card state.
  * @retval Non-zero if Board_Init() returned HAL_OK, 0 otherwise.
  */
uint8_t Board_IsReady(void);

/**
  * @brief  Name of the Board_Init() stage that failed ("matrix", "ads124s08",
  *         "frontend"), or NULL if init succeeded / has not run.
  * @note   Board_Init() stops at the first failing stage among matrix / ads124s08 /
  *         frontend. HV cards are not in this list: they are optional, see
  *         Board_HvFitted().
  */
const char *Board_InitFailStage(void);

/**
  * @brief  Human-readable failure point for logs/replies, e.g. "matrix/U20@0x27",
  *         "matrix/force-exp@0x22", "ads124s08" or "frontend". "none" if init succeeded.
  * @param  buf : [out] destination.
  * @param  n   : [in]  its size (>= 28 recommended).
  */
void Board_InitFailText(char *buf, uint8_t n);

/**
  * @brief  Probe every address 0x08-0x77 on I2C3 (U20's local bus) and log which
  *         ones ACK. For the boot failure path: tells a wrong address strap
  *         (something answers elsewhere) from a dead/unpowered/absent U20
  *         (nothing answers). Address-only probes; needs the logger running.
  */
void Board_ScanI2c3Log(void);

/**
  * @brief  Scan the shared I2C2 bus under each of the four U20 buffer-enable
  *         combinations and log who answers - for a Matrix-stage failure past
  *         U20. Separates "nothing reaches the card" (none in every combination)
  *         from "wrong enable bit / polarity" (answers under one combination).
  *         Leaves the buffers disabled and the Matrix segment released.
  */
void Board_ScanMatrixBusLog(void);

/**
  * @brief  Whether HV card @p idx (0 = HV1 ... ) came up in Board_Init().
  * @note   A missing HV card does not make Board_IsReady() false: continuity and
  *         resistance (Matrix Card + control front end only) still run. Anything
  *         that touches an HV card must check this first - an unfitted card has
  *         no valid driver state and shares the Matrix Card's bus enable (EN1).
  * @retval 1 if fitted and initialised, 0 if absent/failed or @p idx out of range.
  */
uint8_t Board_HvFitted(uint8_t idx);

/** @brief HAL status HV card @p idx returned at init (0 = OK, 1 = ERROR, 2 = BUSY, 3 = TIMEOUT). */
uint8_t Board_HvStatus(uint8_t idx);

/** @brief Non-zero if at least one HV card is fitted. */
uint8_t Board_HvAnyFitted(void);

/** @brief HAL status the failing stage returned (1 = ERROR, 2 = BUSY, 3 = TIMEOUT); 0 if none. */
uint8_t Board_InitFailStatus(void);

/**
  * @brief  Wait for hardware to settle, yielding the CPU if the RTOS is running.
  * @note   Use this instead of HAL_Delay() anywhere inside a test. HAL_Delay
  *         busy-spins, so a settle inside a run held the CPU at sequencer
  *         priority and starved everything below it - the protocol parser
  *         included, which is what stopped >ABORT working (FW-07). Never waits
  *         less than HAL_Delay() would.
  * @param  ms : [in] settle time, milliseconds.
  * @retval None
  */
void Board_SettleMs(uint32_t ms);

/* -------------------------------------------------------------------------- */
/* Bus scan (BUS SCAN, GUI-06 2026-08-21)                                     */
/* -------------------------------------------------------------------------- */

/** One probed device. `name` is a literal, never freed. */
typedef struct
{
  const char *name;
  uint8_t     addr7;
  uint8_t     ok;   /* 1 = responded, 0 = fault */
} BoardBusEntry_t;

/* Matrix Card: 9 expanders (U101/102/105/106 force, U66/67/69/107/108
 * sense) + U20 (local, no bus-claim) + the ADS124S08 itself (SPI, probed by
 * identity rather than an I2C ACK) = 11, plus 8 relay expanders (4 HS + 4 LS)
 * per HV card. */
#define BOARD_BUS_SCAN_MAX  (11U + 8U * (uint8_t)BOARD_HV_COUNT)

/**
  * @brief  Probe every device this project has a schematic-confirmed I2C
  *         address for, without disturbing anything - each is claimed/
  *         segment-selected/released exactly the way a normal access would
  *         be, then the bus is left however it was.
  * @note   Scope: the Matrix Card, the ADS124S08, and each HV card's eight
  *         relay expanders (HVn_HS1..4 = 0x20..0x23, HVn_LS1..4 = 0x24..0x27,
  *         straps confirmed against HV_Card schematic sheet 5). Each HV card
  *         is put on the shared bus alone through its own HV_Card_ENx; a card
  *         that is not fitted is reported as a fault. The HV DAC/ADCs (SPI2)
  *         are not covered.
  * @param  out : [out] array to fill, at least BOARD_BUS_SCAN_MAX entries.
  * @param  max : [in]  capacity of @p out.
  * @retval Number of entries written.
  */
uint8_t Board_ScanBus(BoardBusEntry_t *out, uint8_t max);

#ifdef __cplusplus
}
#endif

#endif /* __BOARD_H */