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

/* Cold-start record (CL-105): one entry per matrix-stage attempt of the LAST
 * Board_Init() call - I2C2 bus state before the bus clear, the clear itself,
 * and how the attempt ended. Read with Board_MxRecText(). */
#ifndef BOARD_MX_REC_MAX
#define BOARD_MX_REC_MAX  BOARD_MATRIX_TRIES
#endif
typedef struct
{
  uint32_t    t_ms;        /* HAL tick at the start of the attempt */
  const char *step;        /* MatrixCard_InitStep() at the end */
  uint16_t    err;         /* hi2c2.ErrorCode after the attempt */
  uint8_t     addr;        /* MatrixCard_InitAddr() at the end */
  uint8_t     hal;         /* attempt result (0 = OK) */
  uint8_t     busy_pre;    /* I2C2 ISR.BUSY before the bus clear */
  uint8_t     sda_pre;     /* PA8 level before the bus clear */
  uint8_t     scl_pre;     /* PC4 level before the bus clear */
  uint8_t     pulses;      /* SCL pulses the clear needed (0..9) */
  uint8_t     sda_post;    /* levels after the clear + STOP */
  uint8_t     scl_post;
  uint8_t     busy_after;  /* I2C2 ISR.BUSY after the attempt */
} BoardMxRec_t;

/* I2C2 (Matrix/HV expanders) and I2C3 (U20) speed, applied in Board_Init()
 * over the CubeMX value so a regeneration cannot undo it (CL-106).
 * I2C kernel clock = PCLK1 = 64 MHz (HSI 16 MHz x8 /2, .ioc I2C2/3Freq_Value).
 *   0x10B17DB5 = CubeMX 100 kHz (PRESC 1, SCLL 182, SCLH 126 x 31.25 ns).
 *   0x10C7172C = 400 kHz Fast mode, computed from RM0440 I2C_TIMINGR rules:
 *     PRESC 1 (31.25 ns); SCLL 0x2C -> tLOW 1.41 us (>= 1.3); SCLH 0x17 ->
 *     tHIGH 0.75 us (>= 0.6); SCLDEL 0xC -> 406 ns (>= tr 300 + tSU;DAT 100);
 *     SDADEL 7 -> 219 ns (203..278 ns window with the analog filter on).
 *     ~2.2 us + sync/rise = ~380-400 kHz. All parts on both buses are rated
 *     for 400 kHz (MCP23017, ADuM1250 1 MHz, NTS0102). Rise time must stay
 *     <= 300 ns: with 2.2 kOhm that allows ~160 pF of loom - check on a scope.
 * Set BOARD_I2C_FAST 0 to go back to 100 kHz. */
#ifndef BOARD_I2C_FAST
#define BOARD_I2C_FAST          1
#endif
#define BOARD_I2C_TIMING_100K   0x10B17DB5U
#define BOARD_I2C_TIMING_400K   0x10C7172CU
#if (BOARD_I2C_FAST != 0)
#define BOARD_I2C_TIMING        BOARD_I2C_TIMING_400K
#else
#define BOARD_I2C_TIMING        BOARD_I2C_TIMING_100K
#endif

/**
  * @brief  Matrix calibration loopback (CL-109): ch 0..4 ties HI_COM to LO_COM
  *         through R2065/R2067..R2070 (1.5/2/5/7/10 mOhm); 0xFF opens it.
  *         Caller holds the hardware mutex.
  */
HAL_StatusTypeDef Board_CalLoop(uint8_t ch);

/** @brief Number of matrix-attempt records from the last Board_Init(). */
uint8_t Board_MxRecCount(void);
/** @brief Record @p k (0-based) as one short line; "" if it does not exist. */
void Board_MxRecText(uint8_t k, char *buf, uint8_t n);
/** @brief How many times Board_Init() has run (1 = boot only; more = tScan retried it). */
uint8_t Board_InitRuns(void);

/* After a failed boot, tScan re-runs Board_Init() (each run = up to
 * BOARD_MATRIX_TRIES attempts) this many times, this far apart, before it
 * falls back to the diagnostic bus scans. Runs in the background: the GUI
 * link is never blocked by it. */
#ifndef BOARD_BG_INIT_RUNS
#define BOARD_BG_INIT_RUNS      5
#endif
#ifndef BOARD_BG_INIT_GAP_MS
#define BOARD_BG_INIT_GAP_MS    1000
#endif

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