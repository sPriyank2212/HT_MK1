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
#include "bsp/board.h"
#include "test/continuity.h"
#include "test/kelvin.h"
#include "test/insulation.h"
#include "cmsis_os2.h"
#include <string.h>

/* Bench-only ADS1232 rig. Compiles to nothing unless HT_ENABLE_ADS1232=1. */
#include "drivers/ads1232.h"

/* ---- shared state -------------------------------------------------------- */
static osMessageQueueId_t s_cmdq;
static osMutexId_t        s_hwmtx;      /* serialises I2C/SPI bus access      */
static UART_HandleTypeDef *s_console;   /* VCP for the bring-up command input */
static volatile uint8_t   s_fault;
static volatile uint8_t   s_hv_active;

/* ---- thread handles + attributes ----------------------------------------- */
static osThreadId_t s_safety, s_seq, s_comms, s_logger;

static const osThreadAttr_t s_attr_safety = { .name = "tSafety",    .priority = osPriorityHigh,        .stack_size = 256 * 4 };
static const osThreadAttr_t s_attr_seq    = { .name = "tSequencer", .priority = osPriorityNormal,      .stack_size = 512 * 4 };
static const osThreadAttr_t s_attr_comms  = { .name = "tComms",     .priority = osPriorityBelowNormal, .stack_size = 256 * 4 };
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

  LOG_W("ADS", "BENCH BUILD - ADS1232 rig active, not for release");

  if (ADS1232_HwInit_Nucleo() != HAL_OK)
  {
    LOG_E("ADS", "hw init failed");
    for (;;) { osDelay(1000U); }
  }

  /* Localise wiring faults before trying to read anything meaningful. */
  ADS1232_BenchDiag();

  /* If the first self-check fails, prove the MCU pin once (readback), then fall
   * into a fast link-quality loop. The slow 10 s toggle is only worth running
   * once - after that the useful number is the read success rate, which updates
   * every couple of seconds while a joint is being soldered or wiggled. */
  if (ADS1232_BenchSelfCheck() != HAL_OK)
  {
    LOG_E("ADS", "self-check failed - proving the MCU pin, then measuring link");
    ADS1232_BenchPinTest(3U);

    /* Do NOT demand a perfect link before showing data. Reads retry internally,
     * so anything above a low floor still produces usable measurements - just
     * more slowly. Blocking on 100% only hides the numbers the bench is for. */
    while (ADS1232_BenchLinkTest(20U) < 25U)
    {
      LOG_E("ADS", "link too poor to measure - fix the SCLK joint");
      osDelay(1000U);
    }

    while (ADS1232_BenchSelfCheck() != HAL_OK)
    {
      osDelay(1000U);
    }
    LOG_W("ADS", "running on a marginal link - readings valid, still solder it");
  }
  LOG_I("ADS", "self-check passed");

  LOG_I("ADS", "rig ready, Rref=%ld ohm gain=128",
        (long)ADS1232_BENCH_RREF_OHMS);

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
void Safety_SignalFault(const char *reason)
{
  s_fault = 1U;
  LOG_E("SAFE", "fault: %s", (reason != NULL) ? reason : "?");
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
    (void)HvCard_HvEnable(&g_hv[i], 0U);
    (void)HvCard_OpenAllRelays(&g_hv[i]);
  }
  (void)MatrixCard_AllOff(&g_matrix);
}

/**
  * @brief  High-priority safety thread: enforce the safe state.
  * @note   Runs forever on a 10 ms tick. While a fault is latched it forces the
  *         instrument safe (under the bus mutex) and keeps it latched. When idle
  *         and no HV is active it re-asserts HV-disabled as a backstop. The IWDG
  *         refresh is a TODO pending the watchdog being enabled in CubeMX.
  * @param  arg : [in] unused FreeRTOS thread argument.
  * @retval None (does not return).
  */
static void SafetyTask(void *arg)
{
  (void)arg;
  LOG_I("SAFE", "task up");
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
      for (i = 0U; i < (uint8_t)BOARD_HV_COUNT; i++)
      {
        (void)HvCard_HvEnable(&g_hv[i], 0U);
      }
    }
    /* TODO: refresh IWDG here once the watchdog is enabled in CubeMX. */
    osDelay(10U);
  }
}

/* ---- sequencer ----------------------------------------------------------- */

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
  if (s_fault)
  {
    LOG_W("SEQ", "skip (fault)");
    return;
  }

  (void)osMutexAcquire(s_hwmtx, osWaitForever);
  switch (c->type)
  {
    case CMD_CONTINUITY:
    {
      ContinuityResult_t r;
      if (Continuity_TestPair(c->a, c->b, &r) == HAL_OK)
      {
        LOG_I("CONT", "%u-%u %dmV v=%d", c->a, c->b, (int)(r.volts * 1000.0f), (int)r.verdict);
      }
      else { LOG_E("CONT", "%u-%u bus err", c->a, c->b); }
      break;
    }
    case CMD_KELVIN:
    {
      KelvinResult_t r;
      if (Kelvin_MeasurePair(c->a, c->b, &r) == HAL_OK)
      {
        LOG_I("KELV", "%u-%u %dmohm v=%d", c->a, c->b, (int)(r.resistance_ohm * 1000.0f), (int)r.verdict);
      }
      else { LOG_E("KELV", "%u-%u bus err", c->a, c->b); }
      break;
    }
    case CMD_INSULATION:
    {
      InsulationResult_t r;
      s_hv_active = 1U;
      LOG_I("INS", "b%u %u-%u vf=%d start", c->board, c->a, c->b, (int)(c->vfrac * 100.0f));
      (void)Insulation_TestPair(c->board, (uint8_t)c->a, (uint8_t)c->b, c->vfrac, &r);
      s_hv_active = 0U;
      LOG_I("INS", "b%u sense=%dmV v=%d", c->board, (int)(r.sense_volts * 1000.0f), (int)r.verdict);
      break;
    }
    case CMD_FORCE_SAFE:
      force_safe_all();
      LOG_I("SEQ", "forced safe");
      break;
    default:
      break;
  }
  osMutexRelease(s_hwmtx);
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
  for (;;)
  {
    if (osMessageQueueGet(s_cmdq, &cmd, NULL, osWaitForever) == osOK)
    {
      run_command(&cmd);
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
static void post_simple(TestCmdType_t t, uint16_t a, uint16_t b, uint8_t board, float vf)
{
  TestCmd_t c = { t, a, b, board, vf };
  (void)Tasks_PostCommand(&c);
}

/**
  * @brief  Bring-up console thread: turn single VCP keystrokes into commands.
  * @note   Best-effort single-byte RX (shares the UART with the logger, so
  *         HAL_BUSY just retries next loop). Key map: c/k/i = continuity/kelvin/
  *         insulation, s = force-safe, f = signal fault, r = clear fault. Runs
  *         forever.
  * @param  arg : [in] unused FreeRTOS thread argument.
  * @retval None (does not return).
  */
static void CommsTask(void *arg)
{
  uint8_t ch;
  (void)arg;
  LOG_I("COM", "console: c/k/i continuity/kelvin/insul, s safe, f fault");
  for (;;)
  {
    /* Best-effort RX; shares the UART with the logger (HAL_BUSY just retries). */
    if (s_console != NULL &&
        HAL_UART_Receive(s_console, &ch, 1U, 100U) == HAL_OK)
    {
      switch (ch)
      {
        case 'c': post_simple(CMD_CONTINUITY, 1U, 2U, 0U, 0.0f); break;
        case 'k': post_simple(CMD_KELVIN,     1U, 2U, 0U, 0.0f); break;
        case 'i': post_simple(CMD_INSULATION, 1U, 1U, 0U, 0.5f); break;
        case 's': post_simple(CMD_FORCE_SAFE, 0U, 0U, 0U, 0.0f); break;
        case 'f': Safety_SignalFault("console"); break;
        case 'r': Safety_ClearFault(); LOG_I("COM", "fault cleared"); break;
        default:  break;
      }
    }
    else
    {
      osDelay(5U);
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
  s_console = Log_HwInit_LPUART1();   /* Nucleo VCP; swap for the product UART */
  console_puts("\r\n[boot] HT_MK1 console up @115200\r\n");
  if (Log_Init(s_console) != HAL_OK)
  {
    console_puts("[boot] LOG init FAILED\r\n");
  }

  s_hwmtx = osMutexNew(NULL);
  s_cmdq  = osMessageQueueNew(8U, sizeof(TestCmd_t), NULL);
  if (s_cmdq == NULL)
  {
    console_puts("[boot] cmd queue alloc FAILED (heap?)\r\n");
  }

  s_logger = osThreadNew(Log_Task,      NULL, &s_attr_logger);
  s_safety = osThreadNew(SafetyTask,    NULL, &s_attr_safety);
  s_seq    = osThreadNew(SequencerTask, NULL, &s_attr_seq);
  s_comms  = osThreadNew(CommsTask,     NULL, &s_attr_comms);

  /* Loud, synchronous report if any thread failed to allocate (heap too small). */
  if (s_logger == NULL || s_safety == NULL || s_seq == NULL || s_comms == NULL)
  {
    console_puts("[boot] TASK CREATE FAILED - increase configTOTAL_HEAP_SIZE\r\n");
  }

#if (HT_ENABLE_ADS1232 != 0)
  s_ads1232 = osThreadNew(Ads1232BenchTask, NULL, &s_attr_ads1232);
  if (s_ads1232 == NULL)
  {
    console_puts("[boot] ADS1232 bench task alloc FAILED\r\n");
  }
#endif

  LOG_I("SYS", "tasks started (hv boards=%u)", (unsigned)BOARD_HV_COUNT);
}
