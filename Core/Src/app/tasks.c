/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    tasks.c
  * @brief   FreeRTOS task architecture implementation. See tasks.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "app/tasks.h"
#include "app/log.h"
#include "app/proto.h"
#include "app/run_logic.h"
#include "bsp/board.h"
#include "test/continuity.h"
#include "test/kelvin.h"
#include "test/insulation.h"
#include "drivers/ds18b20.h"
#include "cmsis_os2.h"
#include <string.h>

/* Bench-only ADS1232 rig. Compiles to nothing unless HT_ENABLE_ADS1232=1. */
#include "drivers/ads1232.h"

/* ---- shared state -------------------------------------------------------- */
static osMessageQueueId_t s_cmdq;
static osMessageQueueId_t s_rxq;        /* console RX bytes, ISR -> tComms     */
static osMutexId_t        s_hwmtx;      /* serialises I2C/SPI bus access      */
static UART_HandleTypeDef *s_console;   /* USB-UART carrying the GUI protocol  */
static uint8_t            s_rx_byte;    /* landing slot for HAL_UART_Receive_IT */
static volatile uint8_t   s_fault;
static volatile uint8_t   s_hv_active;
static volatile uint32_t  s_hv_last_tick;   /* last time any code drove HV      */

/* ---- thread handles + attributes ----------------------------------------- */
static osThreadId_t s_safety, s_seq, s_comms, s_logger;

/* tComms sits ABOVE tSequencer deliberately (FW-07). It spends its life blocked
 * on the RX queue, so it costs nothing until a byte arrives; below the sequencer
 * it was never scheduled during a run, and >ABORT - which works by setting a
 * flag the run loops poll - could not be received at all. */
/* Stack sizes were doubled from the first bring-up values (256/512/256 words):
 * every thread formats printf-style text (nano newlib, floats via snprintf in
 * the log) and tSequencer also holds a BoardBusEntry_t array for BUS SCAN.
 * Stack-overflow checking is now ON (FreeRTOSConfig.h), but a smaller stack that
 * "passes" is no evidence it is big enough - measure with
 * uxTaskGetStackHighWaterMark() at bring-up before shrinking any of these. */
static const osThreadAttr_t s_attr_safety = { .name = "tSafety",    .priority = osPriorityHigh,        .stack_size = 512 * 4 };
static const osThreadAttr_t s_attr_seq    = { .name = "tSequencer", .priority = osPriorityNormal,      .stack_size = 1024 * 4 };
static const osThreadAttr_t s_attr_comms  = { .name = "tComms",     .priority = osPriorityAboveNormal, .stack_size = 512 * 4 };
static const osThreadAttr_t s_attr_logger = { .name = "tLogger",    .priority = osPriorityLow,         .stack_size = 256 * 4 };

#if (HT_ENABLE_ADS1232 != 0)
static osThreadId_t s_ads1232;
static const osThreadAttr_t s_attr_ads1232 = { .name = "tAds1232",  .priority = osPriorityBelowNormal, .stack_size = 384 * 4 };

/**
  * @brief  BENCH ONLY. Bring up the ADS1232 4-wire rig and log a reading a second.
  * @note   Not part of the product firmware - see Doc/ADS1232_bench_wiring.md.
  *         Runs standalone: it touches no card, no bus mutex and no matrix, so
  *         it cannot disturb the rest of the system.
  * @param  arg : [in] unused.
  * @retval Does not return.
  */
static void Ads1232BenchTask(void *arg)
{
  (void)arg;

  LOG_W("ADS", "BENCH BUILD - not for release");

  if (ADS1232_HwInit_Nucleo() != HAL_OK)
  {
    LOG_E("ADS", "hw init failed");
    for (;;) { osDelay(1000U); }
  }

  /* Diagnostics only speak up when something is wrong, so a healthy rig goes
   * straight to printing data. */
  ADS1232_BenchDiag();

  if (ADS1232_BenchSelfCheck() != HAL_OK)
  {
    ADS1232_BenchPinTest(3U);

    /* Do not demand a perfect link before showing data - reads retry
     * internally, so a marginal joint slows the rig rather than stopping it. */
    while (ADS1232_BenchLinkTest(20U) < 25U)
    {
      osDelay(1000U);
    }
    while (ADS1232_BenchSelfCheck() != HAL_OK)
    {
      osDelay(1000U);
    }
  }

  LOG_I("ADS", "Rref=%ld g=128", (long)ADS1232_BENCH_RREF_OHMS);

  for (;;)
  {
    ADS1232_BenchOnce();
    osDelay(1000U);
  }
}
#endif /* HT_ENABLE_ADS1232 */

/* ---- safety -------------------------------------------------------------- */

/**
  * @brief  Latch a global fault and log the reason.
  * @note   Sets the fault flag the safety task polls; stays latched until
  *         Safety_ClearFault(). Callable from any thread.
  * @param  reason : [in] short human-readable cause; NULL logs as "?".
  * @retval None
  */
void Safety_SignalFaultAt(const char *reason, const char *file, int line)
{
  s_fault = 1U;
  Log_WriteAt(LOG_ERROR, file, line, "SAFE", "fault: %s", (reason != NULL) ? reason : "?");
}

/**
  * @brief  Clear the latched fault so normal operation can resume.
  * @retval None
  */
void Safety_ClearFault(void) { s_fault = 0U; }

/**
  * @brief  Query whether the instrument is currently in a latched fault.
  * @retval int non-zero if a fault is latched, 0 otherwise.
  */
int  Safety_InFault(void)    { return (int)s_fault; }

/**
  * @brief  Force the whole instrument to a safe state.
  * @note   Disables HV and opens all relays on every HV board, then opens the
  *         matrix. Caller must already hold the hardware mutex.
  * @retval None
  */
static void force_safe_all(void)
{
  uint8_t i;
  for (i = 0U; i < (uint8_t)BOARD_HV_COUNT; i++)
  {
    if (Board_HvFitted(i) == 0U) { continue; }   /* no card: nothing to make safe */
    (void)HvCard_HvEnable(&g_hv[i], 0U);
    (void)HvCard_OpenAllRelays(&g_hv[i]);
  }
  (void)MatrixCard_AllOff(&g_matrix);
}

/* Note that HV was just driven (or just made safe). The idle rail monitor stays
 * quiet for RAIL_MON_HOLDOFF_MS afterwards: the rail bleeds down passively
 * through the sense divider, and a monitor that fired during that bleed would
 * latch a fault on every healthy run. */
static void hv_activity(void) { s_hv_last_tick = osKernelGetTickCount(); }

/* ---- idle HV rail monitor ------------------------------------------------ */

/* While nothing is driving HV, the rail monitor of every fitted card must read
 * "off". A rail that is live with no test running means the DAC, the supply or
 * a chip-select is wrong - latch a fault and force everything safe. Rail level
 * at the ADC for RAIL_MON_LIVE_RAIL_V volts on the rail. Bring-up tunable. */
#define RAIL_MON_PERIOD_MS    250U
#define RAIL_MON_HOLDOFF_MS   5000U
#define RAIL_MON_LIVE_RAIL_V  50.0f

static void rail_monitor(void)
{
  uint8_t i;
  uint8_t live = 0U;

  if (Board_IsReady() == 0U) { return; }              /* cards not initialised */
  if (osMutexAcquire(s_hwmtx, 0U) != osOK) { return; } /* a run owns the hardware */
  for (i = 0U; i < (uint8_t)BOARD_HV_COUNT; i++)
  {
    uint16_t code = 0U;
    if (Board_HvFitted(i) == 0U) { continue; }
    HvCard_Hold(&g_hv[i]);
    if (HvCard_ReadRailRaw(&g_hv[i], &code) == HAL_OK &&
        AD7476_CodeToVolts(code, g_hv[i].cfg.vref) >
            (RAIL_MON_LIVE_RAIL_V * INSULATION_HV_SENSE_RATIO))
    {
      live = 1U;
    }
    HvCard_Unhold(&g_hv[i]);
  }
  osMutexRelease(s_hwmtx);
  if (live != 0U)
  {
    Safety_SignalFault("HV rail live while idle");
  }
}

/* ---- independent watchdog ------------------------------------------------ */

/* IWDG on the LSI (~32 kHz): /32 prescaler -> ~1 kHz tick, reload 499 -> ~500 ms
 * timeout. Driven through the CMSIS registers directly: the HAL IWDG driver is
 * not part of this project's build. A reset re-runs Board_Init(), which leaves
 * the HV DAC at 0 V and every relay open, so a hung MCU can no longer hold the
 * last programmed HV level. */
#define WDG_PRESCALER_DIV32   3U
#define WDG_RELOAD_TICKS      499U

static void watchdog_start(void)
{
#ifdef DEBUG
  DBGMCU->APB1FZR1 |= DBGMCU_APB1FZR1_DBG_IWDG_STOP;   /* freeze while halted */
#endif
  /* Start FIRST. Writing 0xCCCC forces the LSI on; the PR/RLR update flags in
   * IWDG->SR are only cleared by the LSI domain, so with the LSI still off the
   * wait below would never end (the safety task, the highest priority, would
   * spin forever and starve comms and the logger). This is the order the ST HAL
   * uses. The wait is bounded so a dead LSI can never hang the thread. */
  uint32_t t0 = osKernelGetTickCount();
  IWDG->KR  = 0xCCCCU;                       /* start - cannot be stopped; LSI on */
  IWDG->KR  = 0x5555U;                       /* unlock PR/RLR */
  IWDG->PR  = WDG_PRESCALER_DIV32;
  IWDG->RLR = WDG_RELOAD_TICKS;
  while (IWDG->SR != 0U)                     /* wait for PVU/RVU/WVU to clear */
  {
    if ((osKernelGetTickCount() - t0) > 50U) { break; }
  }
  IWDG->KR  = 0xAAAAU;                       /* load the counter */
}

static inline void watchdog_refresh(void) { IWDG->KR = 0xAAAAU; }

/**
  * @brief  High-priority safety thread: enforce the safe state.
  * @note   Runs forever on a 10 ms tick. While a fault is latched it forces the
  *         instrument safe (under the bus mutex) and keeps it latched. When idle
  *         and no HV is active it re-asserts HV-disabled as a backstop. The IWDG
  *         is started here and refreshed every tick, so a hung MCU resets.
  * @param  arg : [in] unused FreeRTOS thread argument.
  * @retval None (does not return).
  */
static void SafetyTask(void *arg)
{
  uint32_t last_mon = 0U;
  (void)arg;
  LOG_I("SAFE", "task up");
  if ((RCC->CSR & RCC_CSR_IWDGRSTF) != 0U)
  {
    LOG_W("SAFE", "previous reset was the watchdog");
    RCC->CSR |= RCC_CSR_RMVF;
  }
  watchdog_start();
  for (;;)
  {
    if (s_fault)
    {
      /* Force safe under the bus mutex; keep latched until cleared. */
      if (osMutexAcquire(s_hwmtx, 50U) == osOK)
      {
        force_safe_all();
        osMutexRelease(s_hwmtx);
      }
    }
    else if (!s_hv_active)
    {
      /* Backstop: ensure HV outputs are disabled when idle (GPIO-only). */
      uint8_t i;
      uint32_t now = osKernelGetTickCount();
      for (i = 0U; i < (uint8_t)BOARD_HV_COUNT; i++)
      {
        if (Board_HvFitted(i) != 0U) { (void)HvCard_HvEnable(&g_hv[i], 0U); }
      }
      if ((now - last_mon) >= RAIL_MON_PERIOD_MS &&
          (now - s_hv_last_tick) >= RAIL_MON_HOLDOFF_MS)
      {
        last_mon = now;
        rail_monitor();
      }
    }
    watchdog_refresh();
    osDelay(10U);
  }
}

/* ---- sequencer ----------------------------------------------------------- */

/* Every F-code raised from this file is also logged with the line that raised it. */
static void task_fault(const char *code, const char *text, const char *file, int line)
{
  Log_WriteAt(LOG_ERROR, file, line, "FAULT", "%s %s", code, text);
  Proto_EvtFault(code, text);
}
#define Proto_EvtFault(code, text) task_fault((code), (text), __FILE_NAME__, __LINE__)

/* CL-111: MANUAL PATH hold (see CMD_CONTINUITY). 0 = nothing held. */
static volatile uint16_t s_hold_hi = 0U;
static volatile uint16_t s_hold_lo = 0U;
static uint32_t          s_hold_n  = 0U;
#define HOLD_REPORT_MS    1000U   /* !MANUAL every second while held        */
#define HOLD_LOG_EVERY    5U      /* and a log line (with raw frame) every 5 */
#define HOLD_RECHECK_MS   20U     /* CL-112: second read after close, settle check */

/* CL-112: the DS18B20 (U2) is read by the firmware every 60 s and printed to
 * the log. Only the sequencer reads it, and only while it is idle: never while
 * a test runs (tests run inside the sequencer, so none can be in progress) and
 * never while a manual path is held. The first read is 60 s after start-up. */
#define TEMP_PERIOD_MS    60000U
#define TEMP_RETRY_MS     1000U   /* hardware busy or path held: try again soon */
static uint32_t s_temp_next;

static void temp_read_and_report(const char *why)
{
  float c;
  if (DS18B20_ReadTemperature(&g_ds18b20, &c) == HAL_OK)
  {
    int32_t deci_c = (int32_t)((c >= 0.0f) ? (c * 10.0f + 0.5f) : (c * 10.0f - 0.5f));
    int32_t a = (deci_c < 0) ? -deci_c : deci_c;
    Proto_EvtTemp(deci_c);
    LOG_I("TEMP", "%s: board temperature %s%ld.%ld C", why, (deci_c < 0) ? "-" : "",
          (long)(a / 10), (long)(a % 10));
  }
  else
  {
    LOG_E("TEMP", "%s: DS18B20 read failed (missing/unpowered or bad CRC)", why);
  }
}

static void run_continuity_all(uint8_t discover);

/* A run that cannot read the ADC at all (SPI timeout, dead part, bad wiring) must
 * stop, not grind through every point: a full discovery is 65,536 reads and at the
 * AD7476's 50 ms timeout that is over an hour. This many failed reads IN A ROW
 * stops the run with a fault; any good read resets the count. */
#define RUN_GIVEUP_ERRORS  8U
static void run_resistance_all(void);
static void run_insulation_all(void);
static void run_manual_sweep(uint16_t hi);

/**
  * @brief  Execute one test command under the hardware mutex.
  * @note   Skips execution (logs a warning) if a fault is latched. Serialises
  *         all bus access by holding s_hwmtx for the whole operation, dispatches
  *         on the command type, and logs the result. For insulation it brackets
  *         the run with s_hv_active so the safety task knows HV is expected up.
  * @param  c : [in] command to run; must be non-NULL.
  * @retval None
  */
static void run_command(const TestCmd_t *c)
{
  /* Checked before the fault gate: clearing the latch is the one thing that has
   * to work WHILE faulted, or the only recovery is a power cycle. */
  if (c->type == CMD_CLEAR_FAULT)
  {
    (void)osMutexAcquire(s_hwmtx, osWaitForever);
    force_safe_all();
    hv_activity();
    Safety_ClearFault();
    Proto_ClearArm();
    Proto_EvtHv(0);
    Proto_EvtSafe();
    Proto_EvtState("idle");
    osMutexRelease(s_hwmtx);
    LOG_I("SEQ", "fault cleared");
    return;
  }

  if (s_fault)
  {
    LOG_W("SEQ", "skip (fault)");
    /* A run command that never reports !DONE leaves the GUI waiting for ever,
     * and s_busy stays latched so every later run is refused EBUSY. Say the run
     * is over, and say why, before returning (FW-10). */
    switch (c->type)
    {
      case CMD_CONT_RUN:     Proto_EvtState("fault"); Proto_EvtDone("cont",  0U, 0U); break;
      case CMD_RES_RUN:      Proto_EvtState("fault"); Proto_EvtDone("res",   0U, 0U); break;
      case CMD_INSUL_RUN:    Proto_EvtState("fault"); Proto_EvtDone("insul", 0U, 0U); break;
      case CMD_MANUAL_SWEEP: Proto_EvtState("fault"); Proto_EvtDone("sweep", 0U, 0U); break;
      default: break;
    }
    return;
  }

  (void)osMutexAcquire(s_hwmtx, osWaitForever);
  if (c->type != CMD_CONTINUITY && c->type != CMD_TEMP_READ && s_hold_hi != 0U)
  {
    LOG_I("HOLD", "HI%u-LO%u released", (unsigned)s_hold_hi, (unsigned)s_hold_lo);
    s_hold_hi = 0U;   /* every other command opens or re-routes the matrix itself */
  }
  switch (c->type)
  {
    case CMD_CONTINUITY:
    {
      /* MANUAL PATH = the GUI's "Close path". CL-111: the pair now STAYS
       * closed (continuity mode, calibration loopback off) until MANUAL OFF or
       * any other command, so the path can be probed end to end; the
       * sequencer reports the ADC once a second while it is held
       * (hold_report()). Before, Continuity_TestPair opened it again at once. */
      ContinuityResult_t r;
      HAL_StatusTypeDef  hst;
      (void)Board_CalLoop(0xFFU);
      (void)MatrixCard_AllOff(&g_matrix);
      hst = Continuity_TestPairRow(c->a, 0U, c->b, &r);   /* connects, does not open */
      if (hst == HAL_OK)
      {
        uint16_t first_raw = g_frontend.adc.last_raw;
        uint16_t code2 = r.code;
        int32_t  mv2;
        s_hold_hi = c->a;
        s_hold_lo = c->b;
        s_hold_n  = 0U;
        /* CL-112: read again after a longer settle. If the two differ a lot,
         * CONTINUITY_SETTLE_MS is too short for this harness. */
        Board_SettleMs(HOLD_RECHECK_MS);
        if (Frontend_ReadRaw(&g_frontend, &code2) != HAL_OK) { code2 = r.code; }
        mv2 = (int32_t)(AD7476_CodeToVolts(code2, g_frontend.vref) * 1000.0f);
        LOG_I("HOLD", "HI%u-LO%u closed and held (MANUAL OFF opens): %dmV raw 0x%04X at %ums, %ldmV raw 0x%04X at +%ums",
              c->a, c->b, (int)(r.volts * 1000.0f), (unsigned)first_raw,
              (unsigned)CONTINUITY_SETTLE_MS, (long)mv2, (unsigned)g_frontend.adc.last_raw,
              (unsigned)HOLD_RECHECK_MS);
        Proto_EvtManual(mv2, code2);
      }
      else
      {
        (void)MatrixCard_AllOff(&g_matrix);
        s_hold_hi = 0U;
        LOG_E("HOLD", "HI%u-LO%u: close failed hal=%u", c->a, c->b, (unsigned)hst);
      }
      break;
    }
    case CMD_KELVIN:
    {
      KelvinResult_t r;
      if (Kelvin_MeasurePair(c->a, c->b, &r) == HAL_OK)
      {
        LOG_I("KELV", "%u-%u %dmohm v=%d", c->a, c->b, (int)(r.resistance_ohm * 1000.0f), (int)r.verdict);
        /* CMD_KELVIN is only ever reached via CAL RUN (proto.c) - RES RUN
         * calls Kelvin_MeasurePair directly in its own loop, same reasoning
         * as CMD_CONTINUITY/MANUAL PATH above. */
        Proto_EvtCalResult((int32_t)(r.resistance_ohm * 1000.0f),
                           r.ratiometric, (r.verdict == TEST_PASS) ? 1U : 0U);
      }
      else { LOG_E("KELV", "%u-%u bus err", c->a, c->b); }
      break;
    }
    case CMD_INSULATION:
    {
      InsulationResult_t r;
      s_hv_active = 1U;
      LOG_I("INS", "b%u %u-%u vf=%d start", c->board, c->a, c->b, (int)(c->vfrac * 100.0f));
      if (c->a < 1U || c->a > HV_PINS_PER_SIDE || c->b < 1U || c->b > HV_PINS_PER_SIDE)
      {
        /* Pins are local to one HV card (1..64); never truncate into uint8_t. */
        LOG_E("INS", "b%u pins %u-%u outside 1..%u", c->board, c->a, c->b, HV_PINS_PER_SIDE);
        r.sense_volts = 0.0f;
        r.verdict = TEST_ERROR;
        r.hw_fault = INS_HW_NONE;
      }
      else
      {
        r.hw_fault = INS_HW_NONE;
        (void)Insulation_TestPair(c->board, (uint8_t)c->a, (uint8_t)c->b, c->vfrac, &r);
      }
      s_hv_active = 0U;
      hv_activity();
      if (r.hw_fault != INS_HW_NONE) { Safety_SignalFault("HV path fault during manual insulation test"); }
      LOG_I("INS", "b%u sense=%dmV v=%d", c->board, (int)(r.sense_volts * 1000.0f), (int)r.verdict);
      break;
    }
    case CMD_BUS_SCAN:
    {
      BoardBusEntry_t entries[BOARD_BUS_SCAN_MAX];
      uint8_t total = Board_ScanBus(entries, BOARD_BUS_SCAN_MAX);
      uint8_t i, ok_count = 0U, fault_count = 0U;
      Proto_EvtState("running");
      for (i = 0U; i < total; i++)
      {
        Proto_EvtBusLine(entries[i].name, entries[i].ok);
        if (entries[i].ok != 0U) { ok_count++; } else { fault_count++; }
      }
      Proto_EvtState("idle");
      Proto_EvtDone("bus", ok_count, fault_count);
      LOG_I("BUS", "scan: %u ok, %u fault", ok_count, fault_count);
      break;
    }
    case CMD_TEMP_READ:
      /* CL-112: a manual path counts as a test - do not touch the sensor and
       * do not release the path. Runs never overlap this: they execute in
       * the sequencer too, so a request queued during one waits for its end. */
      if (s_hold_hi != 0U)
      {
        LOG_W("TEMP", "read skipped: HI%u-LO%u is held (MANUAL OFF first)",
              (unsigned)s_hold_hi, (unsigned)s_hold_lo);
      }
      else
      {
        temp_read_and_report("on request");
        s_temp_next = osKernelGetTickCount() + TEMP_PERIOD_MS;
      }
      break;
    case CMD_FORCE_SAFE:
      force_safe_all();
      hv_activity();
      Proto_ClearArm();
      /* Announce only now, with the rail actually down. Emitting !SAFE at the
       * point the command was *posted* told the GUI it was safe to handle the
       * harness while the hardware had not been touched yet (FW-08). */
      Proto_EvtHv(0);
      Proto_EvtSafe();
      if (c->b == CMD_SAFE_ANNOUNCE_FIXTURE)
      {
        /* Ordering !HV 0 -> !SAFE -> !FIXTURE is the published contract
         * (GUI_development_brief.md 3.2.1); keep it. */
        Proto_EvtFixture((ProtoFixture_t)c->a);
      }
      LOG_I("SEQ", "forced safe");
      break;
    case CMD_CONT_RUN:
      run_continuity_all((uint8_t)c->a);
      break;
    case CMD_RES_RUN:
      run_resistance_all();
      break;
    case CMD_INSUL_RUN:
      run_insulation_all();
      break;
    case CMD_MANUAL_SWEEP:
      run_manual_sweep(c->a);
      break;
    default:
      break;
  }
  osMutexRelease(s_hwmtx);
}

/**
  * @brief  Continuity over the whole netlist, or a full discovery scan.
  * @note   Streams one !CONT per pair as it goes rather than accumulating -
  *         a discovery scan is 65,536 points and the operator should see
  *         progress, not a frozen screen.
  * @param  discover : [in] 0 = verify the loaded netlist, 1 = scan everything,
  *                    2 = cross continuity: every source pin of the netlist
  *                    against every destination pin of the netlist.
  * @retval None
  */
/* ---- CL-107: continuity scan statistics ------------------------------------
 * Discovery reports only pairs in the connected band; every other reading was
 * dropped without trace, so a scan that found nothing could not tell "path
 * dead (all ~3.3 V)" from "wires read just outside the band". These counters
 * and the summary lines say which. Diagnostic only - verdicts are unchanged. */
#define CSTAT_ANOMALY_LINES  12U

typedef struct
{
  uint32_t n_open, n_pass, n_low, n_mid, n_err;
  uint32_t n_badlead;   /* CL-108: frames whose 4 leading bits were not 0 */
  uint16_t first_bad_raw;
  int32_t  min_mv, max_mv;
  uint16_t min_hi, min_lo, max_hi, max_lo;
  uint8_t  shown;
} ContStats_t;

static void cstat_init(ContStats_t *s)
{
  (void)memset(s, 0, sizeof *s);
  s->min_mv = 0x7FFFFFFF;
  s->max_mv = -1;
}

static void cstat_add(ContStats_t *s, uint16_t hi, uint16_t lo, HAL_StatusTypeDef st,
                      const ContinuityResult_t *r)
{
  int32_t mv;
  if (st != HAL_OK) { s->n_err++; return; }
  if ((g_frontend.adc.last_raw & AD7476_LEAD_MASK) != 0U)
  {
    if (s->n_badlead == 0U) { s->first_bad_raw = g_frontend.adc.last_raw; }
    s->n_badlead++;
  }
  mv = (int32_t)(r->volts * 1000.0f);
  if (mv < s->min_mv) { s->min_mv = mv; s->min_hi = hi; s->min_lo = lo; }
  if (mv > s->max_mv) { s->max_mv = mv; s->max_hi = hi; s->max_lo = lo; }
  if (r->volts >= CONTINUITY_OPEN_V_MIN)        { s->n_open++; return; }
  if (r->verdict == TEST_PASS)                  { s->n_pass++; return; }
  if (r->volts < CONTINUITY_CONNECTED_V_MIN)    { s->n_low++; }
  else                                          { s->n_mid++; }
  if (s->shown < CSTAT_ANOMALY_LINES)
  {
    s->shown++;
    LOG_W("CONT", "anomaly %u-%u %ld mV (code %u)", (unsigned)hi, (unsigned)lo,
          (long)mv, (unsigned)r->code);
  }
}

static void cstat_report(const ContStats_t *s)
{
  LOG_I("CONT", "reads: open=%lu pass=%lu low<%umV=%lu mid=%lu err=%lu",
        (unsigned long)s->n_open, (unsigned long)s->n_pass,
        (unsigned)(CONTINUITY_CONNECTED_V_MIN * 1000.0f), (unsigned long)s->n_low,
        (unsigned long)s->n_mid, (unsigned long)s->n_err);
  LOG_I("CONT", "adc frames with leading bits set: %lu (first raw 0x%04X) - expect 0",
        (unsigned long)s->n_badlead, (unsigned)s->first_bad_raw);
  if (s->max_mv >= 0)
  {
    LOG_I("CONT", "min %ld mV at %u-%u, max %ld mV at %u-%u",
          (long)s->min_mv, (unsigned)s->min_hi, (unsigned)s->min_lo,
          (long)s->max_mv, (unsigned)s->max_hi, (unsigned)s->max_lo);
  }
}

/* CL-109: continuity self-test on the Matrix calibration loopback, before
 * any harness pair. Step 1, loopback open: R54 pulls ADC_IN to +3V3 -> must
 * read >= CONTINUITY_OPEN_V_MIN. Step 2, loopback ch 0 (R2065, 1.5 mOhm):
 * IN -> HI_COM -> U1065 -> R2065 -> U2065 -> LO_COM -> R131 -> GND -> must read
 * in the connected band. Logs both readings with the raw AD7476 frame.
 * Returns 1 if both steps pass. Caller holds the hardware mutex. */
static uint8_t cont_selftest_read(const char *what, uint8_t want_open)
{
  uint16_t code = 0U;
  HAL_StatusTypeDef st;
  float v;
  uint8_t ok;

  Board_SettleMs(CONTINUITY_SETTLE_MS);
  st = Frontend_ReadRaw(&g_frontend, &code);
  if (st != HAL_OK)
  {
    LOG_E("CONT", "selftest %s: ADC read failed hal=%u", what, (unsigned)st);
    return 0U;
  }
  v  = AD7476_CodeToVolts(code, g_frontend.vref);
  ok = (want_open != 0U) ? (uint8_t)(v >= CONTINUITY_OPEN_V_MIN)
                         : (uint8_t)(Continuity_Classify(v) == TEST_PASS);
  if (ok != 0U)
  {
    LOG_I("CONT", "selftest %s %ld mV raw 0x%04X ok", what, (long)(v * 1000.0f),
          (unsigned)g_frontend.adc.last_raw);
  }
  else
  {
    LOG_E("CONT", "selftest %s %ld mV raw 0x%04X FAIL (want %s)", what, (long)(v * 1000.0f),
          (unsigned)g_frontend.adc.last_raw, (want_open != 0U) ? ">=3000" : "20..500");
  }
  return ok;
}

static uint8_t cont_selftest(void)
{
  uint8_t ok_open, ok_loop;

  (void)MatrixCard_AllOff(&g_matrix);
  (void)Frontend_SetMode(&g_frontend, FRONTEND_MODE_CONTINUITY);
  (void)Board_CalLoop(0xFFU);
  ok_open = cont_selftest_read("open", 1U);
  if (Board_CalLoop(0U) != HAL_OK)
  {
    LOG_E("CONT", "selftest: loopback switch (U69) write failed");
    ok_loop = 0U;
  }
  else
  {
    ok_loop = cont_selftest_read("loop R2065", 0U);
  }
  (void)Board_CalLoop(0xFFU);
  return (uint8_t)(ok_open != 0U && ok_loop != 0U);
}

/* CL-114: the source / destination pins a cross-continuity run scans, sorted and
 * without duplicates (a pin used by several nets is tested once). */
static uint16_t s_cross_hi[PROTO_NETLIST_MAX];
static uint16_t s_cross_lo[PROTO_NETLIST_MAX];

/* Insert v into the sorted list a[0..*n-1] unless it is already there. */
static void cross_add(uint16_t *a, uint16_t *n, uint16_t v)
{
  uint16_t k = 0U, j;

  while (k < *n && a[k] < v) { k++; }
  if (k < *n && a[k] == v) { return; }
  for (j = *n; j > k; j--) { a[j] = a[j - 1U]; }
  a[k] = v;
  (*n)++;
}

static void run_continuity_all(uint8_t discover)
{
  ContStats_t cs;
  ContinuityResult_t r;
  uint16_t i, n, hi, lo;
  uint16_t hi_n = 256U, lo_n = 256U, hi_i, lo_i;
  uint16_t pass = 0U, fail = 0U;
  uint32_t bus_err = 0U;   /* 32-bit: a scan of nothing but errors is 65,536 of them,
                            * which wrapped a uint16_t to 0 and read as a clean PASS */
  uint8_t  consec = 0U;    /* failed reads in a row */
  uint8_t  giveup = 0U;

  /* Do NOT clear the abort flag here. proto_post_run() clears it before the
   * command is queued, which is the only point where clearing is correct; a
   * second clear at run start silently swallows an abort that arrived in
   * between - and comms runs above the sequencer, so it lands there easily
   * (FW-09). Proto_EvtDone() clears it again on the way out. */
  Proto_EvtState("running");

  if (discover != 0U)
  {
    /* Discovery: every HI against every LO. Report only what is found - a
     * complete 65,536-line dump would swamp the link and the operator. */
    /* CL-106: row scan - HI stays connected for the whole row and only the LO
     * side moves (3 I2C writes per pair instead of ~13), with EN1 held for
     * the row instead of raised and settled three times per pair. HI and LO
     * are separate connector sides (Matrix_Card-9: HI1..256 on the HV
     * connection sheet, LO1..256 on the LV one), so every HI x LO pair is
     * still tested - no symmetry shortcut is possible. */
    cstat_init(&cs);
    if (discover == 2U)
    {
      /* Cross continuity: only the netlist's own pins (CL-114). */
      hi_n = 0U;
      lo_n = 0U;
      n = Proto_NetlistCount();
      for (i = 0U; i < n; i++)
      {
        if (Proto_NetlistGet(i, &hi, &lo) != 0) { continue; }
        cross_add(s_cross_hi, &hi_n, hi);
        cross_add(s_cross_lo, &lo_n, lo);
      }
      LOG_I("CONT", "cross: %u source x %u destination pins = %lu combinations",
            (unsigned)hi_n, (unsigned)lo_n, (unsigned long)hi_n * (unsigned long)lo_n);
    }
    if (cont_selftest() == 0U)
    {
      /* CL-109: the instrument cannot see a known 1.5 mOhm loopback - a scan
       * would only report "nothing found". Stop and say so. */
      Proto_EvtFault("F01", "continuity self-test failed (calibration loopback): scan not run");
      Proto_EvtState("idle");
      Proto_EvtDone("cont", 0U, 1U);
      return;
    }
    for (hi_i = 0U; hi_i < hi_n; hi_i++)
    {
      uint16_t prev = 0U;   /* LO pin left connected by the previous pair; 0 = none */
      hi = (discover == 2U) ? s_cross_hi[hi_i] : (uint16_t)(hi_i + 1U);
      MatrixCard_BusHold(&g_matrix);
      for (lo_i = 0U; lo_i < lo_n; lo_i++)
      {
        lo = (discover == 2U) ? s_cross_lo[lo_i] : (uint16_t)(lo_i + 1U);
        HAL_StatusTypeDef pst = Continuity_TestPairRow(hi, prev, lo, &r);
        cstat_add(&cs, hi, lo, pst, &r);
        if (pst != HAL_OK)
        {
          bus_err++;        /* a bus error is NOT "no connection": count it */
          (void)MatrixCard_AllOff(&g_matrix);
          prev = 0U;        /* state unknown: reconnect from scratch next time */
          if (++consec >= RUN_GIVEUP_ERRORS) { giveup = 1U; break; }
        }
        else
        {
          prev = lo;
          consec = 0U;
          if (r.verdict == TEST_PASS)
          {
            Proto_EvtCont(hi, lo, "pass");
            pass++;
          }
        }
      }
      (void)MatrixCard_AllOff(&g_matrix);
      MatrixCard_BusUnhold(&g_matrix);
      if (giveup != 0U) { break; }
      Proto_EvtProgress((uint16_t)(hi_i + 1U), hi_n);
      if (s_fault != 0U || Proto_AbortRequested() != 0U) { break; }
    }
    cstat_report(&cs);
    if (bus_err != 0U)
    {
      /* The scan is incomplete: say so, and count the errors as failures so the
       * run cannot read as a clean pass (never 0 - see bus_err above). */
      Proto_EvtFault("F01", (giveup != 0U)
                     ? "ADC read failed 8 times in a row: scan stopped, nothing measured"
                     : "bus error during scan: result incomplete");
      fail = (bus_err > 0xFFFFU) ? 0xFFFFU : (uint16_t)bus_err;
    }
  }
  else
  {
    n = Proto_NetlistCount();
    for (i = 0U; i < n; i++)
    {
      if (Proto_NetlistGet(i, &hi, &lo) != 0) { continue; }
      if (Continuity_TestPair(hi, lo, &r) != HAL_OK)
      {
        /* Reported as open (the pair is NOT verified) but flagged as a bus error,
         * not as a missing wire. */
        Proto_EvtCont(hi, lo, "open");
        Proto_EvtFault("F01", "bus error: pair not verified");
        fail++;
        if (++consec >= RUN_GIVEUP_ERRORS)
        {
          Proto_EvtFault("F01", "ADC read failed 8 times in a row: run stopped");
          break;
        }
      }
      else if (r.verdict == TEST_PASS)
      {
        consec = 0U;
        Proto_EvtCont(hi, lo, "pass");
        pass++;
      }
      else
      {
        consec = 0U;
        Proto_EvtCont(hi, lo, "open");
        Proto_EvtFault("F06", "continuity open");
        fail++;
      }
      Proto_EvtProgress((uint16_t)(i + 1U), n);
      if (s_fault != 0U || Proto_AbortRequested() != 0U) { break; }
    }
  }

  Proto_EvtState("idle");
  Proto_EvtDone("cont", pass, fail);
}

/**
  * @brief  One HS pin against all 256 LS - a bounded version of
  *         run_continuity_all(discover=1)'s inner loop, for `MANUAL SWEEP`
  *         (GUI-06, 2026-08-21). Reports only matches found, same reasoning
  *         as full discovery: a 256-line dump of everything NOT found would
  *         swamp the link for no reason.
  * @param  hi : [in] the one HS pin to sweep, 1..256 (already range-checked
  *                    by proto.c).
  * @retval None
  */
static void run_manual_sweep(uint16_t hi)
{
  ContinuityResult_t r;
  uint16_t lo;
  uint16_t found = 0U;
  ContStats_t cs;
  uint8_t  consec = 0U;
  uint8_t  failed = 0U;
  uint16_t prev = 0U;   /* CL-106 row scan: LO pin left connected; 0 = none */

  Proto_EvtState("running");
  cstat_init(&cs);
  if (cont_selftest() == 0U)
  {
    Proto_EvtFault("F01", "continuity self-test failed (calibration loopback): sweep not run");
    Proto_EvtState("idle");
    Proto_EvtDone("sweep", 0U, 1U);
    return;
  }
  MatrixCard_BusHold(&g_matrix);
  for (lo = 1U; lo <= 256U; lo++)
  {
    HAL_StatusTypeDef pst = Continuity_TestPairRow(hi, prev, lo, &r);
    cstat_add(&cs, hi, lo, pst, &r);
    if (pst != HAL_OK)
    {
      (void)MatrixCard_AllOff(&g_matrix);
      prev = 0U;
      if (++consec >= RUN_GIVEUP_ERRORS)
      {
        Proto_EvtFault("F01", "ADC read failed 8 times in a row: sweep stopped");
        failed = 1U;
        break;
      }
    }
    else
    {
      prev = lo;
      consec = 0U;
      if (r.verdict == TEST_PASS)
      {
        Proto_EvtCont(hi, lo, "pass");
        found++;
      }
    }
    if ((lo % 16U) == 0U) { Proto_EvtProgress(lo, 256U); }
    if (s_fault != 0U || Proto_AbortRequested() != 0U) { break; }
  }
  (void)MatrixCard_AllOff(&g_matrix);
  MatrixCard_BusUnhold(&g_matrix);
  cstat_report(&cs);
  Proto_EvtState("idle");
  Proto_EvtDone("sweep", found, (failed != 0U) ? 1U : 0U);
}

/**
  * @brief  Resistance over the loaded netlist.
  * @note   Kelvin_MeasurePair (FW-02) reads HI_SENSE/LO_SENSE on the Matrix
  *         Card's ADS124S08, auto-ranging the PGA and subtracting a
  *         zero-current baseline per point. A bus/driver error (not a real
  *         over-limit reading) still reports fail_high here rather than a
  *         number computed from a failed conversion.
  * @retval None
  */

#define RES_NEG_TOL_MOHM   100L   /* a reading below -100 mOhm is not noise */

static void run_resistance_all(void)
{
  KelvinResult_t r;
  uint16_t i, n, hi, lo;
  uint16_t pass = 0U, fail = 0U;
  int32_t  limit = Proto_LimitRMaxMohm();

  /* Do NOT clear the abort flag here. proto_post_run() clears it before the
   * command is queued, which is the only point where clearing is correct; a
   * second clear at run start silently swallows an abort that arrived in
   * between - and comms runs above the sequencer, so it lands there easily
   * (FW-09). Proto_EvtDone() clears it again on the way out. */
  Proto_EvtState("running");
  n = Proto_NetlistCount();

  for (i = 0U; i < n; i++)
  {
    if (Proto_NetlistGet(i, &hi, &lo) != 0) { continue; }

    if (Kelvin_MeasurePair(hi, lo, &r) != HAL_OK)
    {
      Proto_EvtRes(hi, lo, 0, "fail_high");
      Proto_EvtFault("F08", "resistance path unavailable");
      fail++;
    }
    else
    {
      int32_t mohm;
      const char *v;
      if (RunLogic_ResMohmToWire(r.resistance_ohm, &mohm) != 0)
      {
        v = "fail_high";                    /* not a number: never a pass */
      }
      else if (mohm < -RES_NEG_TOL_MOHM)
      {
        v = "fail_low";                     /* negative: offset or wiring error */
        Proto_EvtFault("F09", "resistance negative: check wiring and calibration");
      }
      else
      {
        v = (mohm <= limit) ? "pass" : "fail_high";
      }
      Proto_EvtRes(hi, lo, mohm, v);
      if (v[0] == 'p') { pass++; } else { fail++; }
    }
    Proto_EvtProgress((uint16_t)(i + 1U), n);
    if (s_fault != 0U || Proto_AbortRequested() != 0U) { break; }
  }

  Proto_EvtState("idle");
  Proto_EvtDone("res", pass, fail);
}

/* Netlist accessor handed to the pure return-relay planner (run_logic.c). */
static int netlist_get(uint16_t i, uint16_t *hi, uint16_t *lo) { return Proto_NetlistGet(i, hi, lo); }

/**
  * @brief  Insulation over the loaded netlist.
  * @note   Refuses to run unless HV was armed, and always drops the rail and
  *         clears the arm on the way out - arming must never survive a run.
  * @retval None
  */
static void run_insulation_all(void)
{
  InsulationResult_t r;
  uint16_t i, n, hi, lo;
  uint16_t pass = 0U, fail = 0U;
  HAL_StatusTypeDef st_net;

  if (Proto_HvArmed() == 0U)
  {
    Proto_EvtFault("F05", "HV not armed");
    Proto_EvtDone("insul", 0U, 0U);
    return;
  }

  /* Do NOT clear the abort flag here. proto_post_run() clears it before the
   * command is queued, which is the only point where clearing is correct; a
   * second clear at run start silently swallows an abort that arrived in
   * between - and comms runs above the sequencer, so it lands there easily
   * (FW-09). Proto_EvtDone() clears it again on the way out. */
  n = Proto_NetlistCount();

  /* Refuse up front if any HS pin is beyond the HV cards fitted (each card has
   * HV_PINS_PER_SIDE relays): reporting that as a per-net measurement failure
   * would be a spurious fault on most of a 256-line netlist. */
  for (i = 0U; i < n; i++)
  {
    if (Proto_NetlistGet(i, &hi, &lo) != 0) { continue; }
    if (hi < 1U || lo < 1U || (hi - 1U) / HV_PINS_PER_SIDE >= (uint16_t)BOARD_HV_COUNT ||
        Board_HvFitted((uint8_t)((hi - 1U) / HV_PINS_PER_SIDE)) == 0U)
    {
      Proto_EvtFault("F05", "netlist pin outside fitted HV cards");
      Proto_ClearArm();
      Proto_EvtDone("insul", 0U, 0U);
      return;
    }
  }
  /* Prove the HV path before trusting a single reading: a wrong DAC/ADC
   * chip-select or a dead card enable would otherwise read ~0 V = PASS. */
  for (i = 0U; i < (uint16_t)BOARD_HV_COUNT; i++)
  {
    float v_idle = 0.0f, v_hv = 0.0f;
    if (Board_HvFitted((uint8_t)i) == 0U) { continue; }
    if (Insulation_HvSelfTest((uint8_t)i, &v_idle, &v_hv) != HAL_OK)
    {
      LOG_E("INS", "b%u HV self-test FAILED idle=%dmV rail=%dmV", (unsigned)i,
            (int)(v_idle * 1000.0f), (int)(v_hv * 1000.0f));
      Proto_EvtFault("F03", "HV path self-test failed");
      Safety_SignalFault("HV self-test failed");
      force_safe_all();
      hv_activity();
      Proto_ClearArm();
      Proto_EvtHv(0);
      Proto_EvtSafe();
      Proto_EvtDone("insul", 0U, 0U);
      return;
    }
  }
  hv_activity();
  Proto_EvtState("running");

  for (i = 0U; i < n; i++)
  {
    uint8_t  board, local;
    uint64_t rmask;
    if (Proto_NetlistGet(i, &hi, &lo) != 0) { continue; }

    board = (uint8_t)((hi - 1U) / HV_PINS_PER_SIDE);
    local = (uint8_t)((hi - 1U) % HV_PINS_PER_SIDE + 1U);
    rmask = RunLogic_ReturnMask(netlist_get, n, hi, lo, board, HV_PINS_PER_SIDE);

    r.hw_fault = INS_HW_NONE;
    s_hv_active = 1U;
    st_net = Insulation_TestNet(board, local, rmask, INSULATION_RUN_FRACTION, &r);
    s_hv_active = 0U;
    hv_activity();

    if (r.hw_fault != INS_HW_NONE)
    {
      /* The HV path itself misbehaved (relay bus, DAC/ADC, rail out of
       * tolerance, rail would not discharge). That is not a harness failure and
       * no further net can be trusted: report it, latch the fault, stop. */
      static const char *const why[] = {
        "none", "HV relay bus error", "HV DAC/ADC error",
        "HV rail out of tolerance", "HV rail did not discharge" };
      Proto_EvtInsul(hi, 0, "fail");
      Proto_EvtFault((r.hw_fault == INS_HW_BUS) ? "F01" :
                     (r.hw_fault == INS_HW_SPI) ? "F02" : "F03",
                     why[(r.hw_fault <= INS_HW_DISCHARGE) ? r.hw_fault : 0U]);
      Safety_SignalFault(why[(r.hw_fault <= INS_HW_DISCHARGE) ? r.hw_fault : 0U]);
      fail++;
      break;
    }
    if (st_net != HAL_OK)
    {
      Proto_EvtInsul(hi, 0, "fail");
      Proto_EvtFault("F04", "insulation measurement failed");
      fail++;
    }
    else
    {
      const char *v = (r.verdict == TEST_PASS) ? "pass" : "fail";
      /* insulation_mohm is the header's megohm estimate; the protocol
       * carries milliohms, so scale by 1e9. */
      Proto_EvtInsul(hi, RunLogic_InsulMohmToWire(r.insulation_mohm), v);
      if (r.verdict == TEST_PASS) { pass++; }
      else { Proto_EvtFault("F04", "insulation low"); fail++; }
    }
    Proto_EvtProgress((uint16_t)(i + 1U), n);
    if (s_fault != 0U || Proto_AbortRequested() != 0U) { break; }
  }

  /* Always leave HV down and disarmed. */
  force_safe_all();
  hv_activity();
  Proto_ClearArm();
  Proto_EvtHv(0);
  Proto_EvtSafe();
  Proto_EvtState("idle");
  Proto_EvtDone("insul", pass, fail);
}

/**
  * @brief  Sequencer thread: run queued test commands one at a time.
  * @note   Blocks on the command queue and hands each command to run_command(),
  *         which serialises hardware access. Runs forever.
  * @param  arg : [in] unused FreeRTOS thread argument.
  * @retval None (does not return).
  */
static void SequencerTask(void *arg)
{
  TestCmd_t cmd;
  (void)arg;
  LOG_I("SEQ", "task up");
  s_temp_next = osKernelGetTickCount() + TEMP_PERIOD_MS;
  for (;;)
  {
    uint32_t wait;
    if (s_hold_hi != 0U)
    {
      wait = HOLD_REPORT_MS;
    }
    else
    {
      int32_t left = (int32_t)(s_temp_next - osKernelGetTickCount());
      wait = (left > 0) ? (uint32_t)left : 0U;
    }
    if (osMessageQueueGet(s_cmdq, &cmd, NULL, wait) == osOK)
    {
      run_command(&cmd);
    }
    else if (s_hold_hi == 0U)
    {
      /* CL-112: idle and the 60 s period is up - read the board temperature.
       * Skipped (retried in 1 s) while start-up init or a bus scan holds the
       * hardware; not attempted at all before the board is ready. */
      if (Board_IsReady() == 0U)
      {
        s_temp_next = osKernelGetTickCount() + TEMP_PERIOD_MS;
      }
      else if (osMutexAcquire(s_hwmtx, 0U) == osOK)
      {
        temp_read_and_report("periodic");
        osMutexRelease(s_hwmtx);
        s_temp_next = osKernelGetTickCount() + TEMP_PERIOD_MS;
      }
      else
      {
        s_temp_next = osKernelGetTickCount() + TEMP_RETRY_MS;
      }
    }
    else if (s_hold_hi != 0U && osMutexAcquire(s_hwmtx, 100U) == osOK)
    {
      /* CL-111: path held - read the front end again and report it. */
      uint16_t code = 0U;
      if (s_hold_hi != 0U && Frontend_ReadRaw(&g_frontend, &code) == HAL_OK)
      {
        int32_t mv = (int32_t)(AD7476_CodeToVolts(code, g_frontend.vref) * 1000.0f);
        Proto_EvtManual(mv, code);
        if ((++s_hold_n % HOLD_LOG_EVERY) == 0U)
        {
          LOG_I("HOLD", "HI%u-LO%u held %lus: %ldmV raw 0x%04X", (unsigned)s_hold_hi,
                (unsigned)s_hold_lo, (unsigned long)s_hold_n, (long)mv,
                (unsigned)g_frontend.adc.last_raw);
        }
      }
      osMutexRelease(s_hwmtx);
    }
  }
}

/* ---- comms (Nucleo bring-up console over the VCP) ------------------------- */

/**
  * @brief  Build a TestCmd_t from loose fields and post it to the queue.
  * @note   Convenience helper for the bring-up console key handler.
  * @param  t     : [in] command type.
  * @param  a     : [in] first pin / primary argument.
  * @param  b     : [in] second pin / secondary argument.
  * @param  board : [in] HV board index (insulation only).
  * @param  vf    : [in] HV fraction (insulation only).
  * @retval None
  */
/* post_simple() removed with the single-keystroke console - the protocol layer
 * builds and posts commands itself (see Core/Src/app/proto.c). */

/**
  * @brief  Console RX complete: hand the byte to tComms and re-arm.
  * @note   Runs in the USART2 ISR at priority 5, the most urgent level allowed
  *         to call the FreeRTOS FromISR API. Re-arming here is what keeps the
  *         receiver alive; miss it once and the link goes deaf.
  * @param  huart : [in] UART reporting the completion.
  * @retval None
  */
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
  if (huart == s_console)
  {
    /* Drop-if-full rather than block: an ISR must not wait, and a full queue
     * means tComms is wedged, which losing one byte will not make worse. */
    (void)osMessageQueuePut(s_rxq, &s_rx_byte, 0U, 0U);
    (void)HAL_UART_Receive_IT(huart, &s_rx_byte, 1U);
  }
}

/**
  * @brief  Console UART error: clear the condition and re-arm RX.
  * @note   Overrun is the expected one - the GUI can send while the line is
  *         busy. HAL aborts the pending receive on any error, so without this
  *         re-arm a single overrun would silently deafen the instrument for
  *         good.
  * @param  huart : [in] UART reporting the error.
  * @retval None
  */
void HAL_UART_ErrorCallback(UART_HandleTypeDef *huart)
{
  if (huart == s_console)
  {
    __HAL_UART_CLEAR_OREFLAG(huart);
    __HAL_UART_CLEAR_NEFLAG(huart);
    __HAL_UART_CLEAR_FEFLAG(huart);
    __HAL_UART_CLEAR_PEFLAG(huart);
    (void)HAL_UART_Receive_IT(huart, &s_rx_byte, 1U);
  }
}

/**
  * @brief  Comms thread: feed received bytes to the protocol parser.
  * @note   Blocks on the RX queue, so it consumes nothing until a byte arrives -
  *         which is why it can afford to sit above the sequencer in priority.
  *         That placement is the point: a command must be parsed and answered
  *         while a run is executing, not after it (FW-07). Runs forever.
  * @param  arg : [in] unused FreeRTOS thread argument.
  * @retval None (does not return).
  */
static void CommsTask(void *arg)
{
  uint8_t ch;
  uint32_t last_beat;
  (void)arg;

  Proto_Init(s_console);

  if (s_console != NULL)
  {
    (void)HAL_UART_Receive_IT(s_console, &s_rx_byte, 1U);
  }

  LOG_I("COM", "proto ready (see GUI_development_brief.md)");
  Proto_EvtState("idle");
  Proto_EvtFixture(PROTO_FIXTURE_NONE);

  last_beat = osKernelGetTickCount();

  for (;;)
  {
    /* Timed wait rather than osWaitForever: this task also has to emit the
     * liveness heartbeat, and it cannot do that while parked on the queue. A
     * byte still wakes it immediately, so command latency is unchanged. */
    if (osMessageQueueGet(s_rxq, &ch, NULL, PROTO_HEARTBEAT_MS) == osOK)
    {
      Proto_RxByte(ch);
    }

    /* Measured against the clock, not against queue timeouts: a steady trickle
     * of received bytes would otherwise keep resetting the wait and starve the
     * heartbeat - which is precisely when the GUI is still waiting to hear
     * something back. configTICK_RATE_HZ is 1000, so ticks are milliseconds. */
    if ((osKernelGetTickCount() - last_beat) >= PROTO_HEARTBEAT_MS)
    {
      last_beat = osKernelGetTickCount();
      Proto_EvtHeartbeat();
    }
  }
}

/* ---- public -------------------------------------------------------------- */

/**
  * @brief  Post a test command to the sequencer queue (non-blocking).
  * @param  cmd : [in] command to enqueue; must be non-NULL.
  * @retval 0  command enqueued.
  * @retval -1 @p cmd is NULL or the queue does not exist.
  * @retval 1  queue full (command dropped).
  */
int Tasks_PostCommand(const TestCmd_t *cmd)
{
  if (cmd == NULL || s_cmdq == NULL)
  {
    return -1;
  }
  return (osMessageQueuePut(s_cmdq, cmd, 0U, 0U) == osOK) ? 0 : 1;
}

/**
  * @brief  Write a string straight to the console UART, synchronously.
  * @note   Bypasses the log queue so a boot banner / failure message appears
  *         even if tasks or the heap failed to come up, as long as the UART
  *         itself is alive. No-op if the console or @p s is NULL.
  *         Callers must prefix '#': every instrument -> GUI line has to carry a
  *         marker (GUI_development_brief.md 3.1), and a bare banner is a parse
  *         error at the other end. No leading newline either, for the same
  *         reason - an empty line is not a valid frame.
  * @param  s : [in] NUL-terminated string to transmit.
  * @retval None
  */
static void console_puts(const char *s)
{
  if (s_console != NULL && s != NULL)
  {
    (void)HAL_UART_Transmit(s_console, (uint8_t *)s, (uint16_t)strlen(s), 50U);
  }
}

/* Boot-failure bus scans. Run AFTER the kernel is up, from this low-priority
 * thread, never from Tasks_Init: the comms task (higher priority) keeps
 * answering the GUI whatever the scans do, and each scan is time-bounded
 * (board.c, BOARD_SCAN_BUDGET_MS) so it reports instead of hanging. Waits
 * SCAN_START_DELAY_MS first so the GUI handshake and the boot log go out
 * before any bus is touched. Runs once, only if Board_Init failed. */
#define SCAN_START_DELAY_MS  1500U

static osThreadId_t s_scan;
static const osThreadAttr_t s_attr_scan = { .name = "tScan", .priority = osPriorityLow, .stack_size = 1024 * 4 };   /* CL-105: runs Board_Init() too */

/* CL-105: one line per matrix-stage attempt of the last Board_Init() (I2C2
 * state before the bus clear and the result) - the cold-start evidence. */
void Tasks_LogMatrixRecords(void)
{
  char    line[80];
  uint8_t k;
  for (k = 0U; k < Board_MxRecCount(); k++)
  {
    Board_MxRecText(k, line, (uint8_t)sizeof line);
    LOG_I("BOARD", "mx %s", line);
  }
}

static void ScanTask(void *arg)
{
  char     where[28];
  uint32_t t0;
  uint8_t  run;
  (void)arg;

  osDelay(SCAN_START_DELAY_MS);
  if (Board_IsReady() != 0U)
  {
    osThreadExit();   /* board is fine: nothing to diagnose */
  }

  /* CL-105: cold start - Board_Init() failed before the kernel ran. Run it
   * again from here (each run clears and re-initialises I2C2 before every
   * matrix attempt) so the unit becomes ready without the reset switch. Under
   * the hardware mutex; nothing else uses the cards while not ready (runs are
   * refused, the rail monitor skips). Low priority: the GUI link keeps working. */
  for (run = 1U; run <= (uint8_t)BOARD_BG_INIT_RUNS && Board_IsReady() == 0U; run++)
  {
    HAL_StatusTypeDef bst;
    if (osMutexAcquire(s_hwmtx, 3000U) != osOK)
    {
      LOG_W("BOARD", "background init %u skipped: hardware busy", (unsigned)run);
    }
    else
    {
      bst = Board_Init();
      osMutexRelease(s_hwmtx);
      Board_InitFailText(where, (uint8_t)sizeof where);
      if (bst == HAL_OK)
      {
        LOG_W("BOARD", "init ok on background run %u (boot run failed) - cold-start recovery", (unsigned)run);
        Tasks_LogMatrixRecords();
        osThreadExit();
      }
      LOG_E("BOARD", "background init %u/%u failed at %s (hal=%u)", (unsigned)run,
            (unsigned)BOARD_BG_INIT_RUNS, where, (unsigned)Board_InitFailStatus());
      Tasks_LogMatrixRecords();
    }
    osDelay(BOARD_BG_INIT_GAP_MS);
  }

  Board_InitFailText(where, (uint8_t)sizeof where);
  t0 = osKernelGetTickCount();
  LOG_I("SCAN", "start (init failed at %s; each scan limited to %u ms)", where, (unsigned)BOARD_SCAN_BUDGET_MS);
  osDelay(20U);

  if (osMutexAcquire(s_hwmtx, 3000U) != osOK)
  {
    LOG_W("SCAN", "skipped: hardware busy (mutex not free within 3 s)");
    osThreadExit();
  }

  if (strncmp(where, "matrix/", 7U) == 0 && Board_InitFailStatus() != 0U)
  {
    Board_ScanI2c3Log();   /* who DOES answer on U20's bus? */
    if (strncmp(where, "matrix/U20", 10U) != 0 && strncmp(where, "matrix/flush", 12U) != 0)
    {
      Board_ScanMatrixBusLog();   /* U20 is fine: who answers on the card's bus? */
    }
  }
  else if (strcmp(where, "ads124s08") == 0 && Board_InitFailStatus() != 0U)
  {
    /* U69 (ADC control) is reached through the force segment (BUFF1, 0x21).
     * Show who answers where. */
    Board_ScanMatrixBusLog();
  }
  else
  {
    LOG_W("SCAN", "no bus scan defined for stage '%s'", where);
  }
  osMutexRelease(s_hwmtx);
  LOG_I("SCAN", "done in %lu ms", (unsigned long)(osKernelGetTickCount() - t0));
  osThreadExit();
}

/**
  * @brief  Bring up the console, logger, IPC objects and all RTOS threads.
  * @note   Brings up the VCP first so boot progress is always visible, then
  *         creates the hardware mutex, command queue and the four threads
  *         (logger, safety, sequencer, comms). Allocation failures are reported
  *         synchronously on the console (heap too small). Call once, after the
  *         scheduler primitives are available.
  * @retval None
  */
void Tasks_Init(void)
{
  s_console = Log_HwInit_Console();   /* USART2 -> MCP2221A USB-UART (Nucleo: ST-LINK VCP) */
  console_puts("#[boot] HT_MK1 console up @115200\r\n");
  if (Log_Init(s_console) != HAL_OK)
  {
    console_puts("#[boot] LOG init FAILED\r\n");
  }
  Diag_Go();   /* print every failure recorded during Board_Init(), with file:line */
  {
    /* Why did the MCU start? A watchdog / brown-out / pin reset right after the
     * host connects explains a "link lost" with no other trace. Read-only: the
     * flags are left for SafetyTask's own IWDG check. */
    const uint32_t csr = RCC->CSR;
    LOG_I("BOOT", "reset cause:%s%s%s%s%s%s%s",
          ((csr & RCC_CSR_IWDGRSTF) != 0U) ? " IWDG" : "",
          ((csr & RCC_CSR_WWDGRSTF) != 0U) ? " WWDG" : "",
          ((csr & RCC_CSR_SFTRSTF)  != 0U) ? " SW" : "",
          ((csr & RCC_CSR_BORRSTF)  != 0U) ? " BOR/POR" : "",
          ((csr & RCC_CSR_PINRSTF)  != 0U) ? " PIN" : "",
          ((csr & RCC_CSR_LPWRRSTF) != 0U) ? " LPWR" : "",
          ((csr & RCC_CSR_OBLRSTF)  != 0U) ? " OBL" : "");
  }

  s_hwmtx = osMutexNew(NULL);
  s_cmdq  = osMessageQueueNew(8U, sizeof(TestCmd_t), NULL);
  /* One command line's worth of headroom, so a burst arriving while tComms is
   * mid-reply is buffered rather than dropped. */
  s_rxq   = osMessageQueueNew(PROTO_RX_MAX + 8U, sizeof(uint8_t), NULL);
  if (s_cmdq == NULL || s_rxq == NULL)
  {
    console_puts("#[boot] queue alloc FAILED (heap?)\r\n");
  }

  s_logger = osThreadNew(Log_Task,      NULL, &s_attr_logger);
  s_safety = osThreadNew(SafetyTask,    NULL, &s_attr_safety);
  s_seq    = osThreadNew(SequencerTask, NULL, &s_attr_seq);
  s_comms  = osThreadNew(CommsTask,     NULL, &s_attr_comms);

  if (Board_IsReady() == 0U)   /* init failed: diagnose the buses once the kernel runs */
  {
    s_scan = osThreadNew(ScanTask, NULL, &s_attr_scan);
    if (s_scan == NULL) { console_puts("#[boot] SCAN task alloc FAILED\r\n"); }
  }

  /* Loud, synchronous report if any thread failed to allocate (heap too small). */
  if (s_logger == NULL || s_safety == NULL || s_seq == NULL || s_comms == NULL)
  {
    console_puts("#[boot] TASK CREATE FAILED - increase configTOTAL_HEAP_SIZE\r\n");
  }

#if (HT_ENABLE_ADS1232 != 0)
  s_ads1232 = osThreadNew(Ads1232BenchTask, NULL, &s_attr_ads1232);
  if (s_ads1232 == NULL)
  {
    console_puts("#[boot] ADS1232 bench task alloc FAILED\r\n");
  }
#endif

  console_puts("#[boot] tasks created\r\n");
  LOG_I("SYS", "tasks started (hv boards=%u)", (unsigned)BOARD_HV_COUNT);
  if (Board_MatrixTries() > 1U)
  {
    LOG_W("BOARD", "matrix stage needed %u attempts (%u ms apart): Matrix Card slow to power up or an intermittent contact",
          (unsigned)Board_MatrixTries(), (unsigned)BOARD_MATRIX_RETRY_MS);
  }
  Tasks_LogMatrixRecords();   /* CL-105: I2C2 state per matrix attempt of the boot run */
  /* Board_Init() ran before the logger existed; report its outcome now. */
  if (Board_IsReady() != 0U)
  {
    uint8_t k;
    LOG_I("BOARD", "init ok: matrix, ads124s08, frontend");
    for (k = 0U; k < (uint8_t)BOARD_HV_COUNT; k++)
    {
      if (Board_HvFitted(k) != 0U) { LOG_I("BOARD", "hv%u fitted", (unsigned)(k + 1U)); }
      else
      {
        LOG_W("BOARD", "hv%u NOT fitted (hal=%u) - continuity/resistance only",
              (unsigned)(k + 1U), (unsigned)Board_HvStatus(k));
      }
    }
  }
  else
  {
    char where[28];
    char site[36];
    Board_InitFailText(where, (uint8_t)sizeof where);
    Diag_FirstText(site, (uint8_t)sizeof site);
    LOG_E("BOARD", "init FAILED at %s (hal=%u) first: %s", where,
          (unsigned)Board_InitFailStatus(), site);
    /* The I2C/SPI bus scans that used to run here (Board_ScanI2c3Log /
     * Board_ScanMatrixBusLog) are NOT called any more: they ran before the
     * scheduler started and the board went silent after "bus scans" on the
     * bench (2026-11-18), so no GUI connect. The functions stay in board.c. */
  }
  console_puts("#[boot] Tasks_Init done, starting scheduler\r\n");
}
