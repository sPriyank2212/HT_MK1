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

/* Number of HV boards fitted in this build (1..4). TODO: confirm. */
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
 * sense) + U21 (local, no bus-claim) + the ADS124S08 itself (SPI, probed by
 * identity rather than an I2C ACK) = 11. */
#define BOARD_BUS_SCAN_MAX  11U

/**
  * @brief  Probe every device this project has a schematic-confirmed I2C
  *         address for, without disturbing anything - each is claimed/
  *         segment-selected/released exactly the way a normal access would
  *         be, then the bus is left however it was.
  * @note   HV card expanders are deliberately NOT probed: `hv_card.c`'s own
  *         strap assignment is still marked "TODO verify" pending bring-up
  *         (BU-03), so reporting ok/fault against an address that hasn't
  *         been confirmed would claim a confidence this project doesn't
  *         have yet. Scope is Matrix Card + the ADS124S08 only.
  * @param  out : [out] array to fill, at least BOARD_BUS_SCAN_MAX entries.
  * @param  max : [in]  capacity of @p out.
  * @retval Number of entries written.
  */
uint8_t Board_ScanBus(BoardBusEntry_t *out, uint8_t max);

#ifdef __cplusplus
}
#endif

#endif /* __BOARD_H */