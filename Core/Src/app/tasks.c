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
static osMessageQueueId_t s_rxq;        /* console RX bytes, ISR -> tComms     */
static osMutexId_t        s_hwmtx;      /* serialises I2C/SPI bus access      */
static UART_HandleTypeDef *s_console;   /* VCP carrying the GUI protocol      */
static uint8_t            s_rx_byte;    /* landing slot for HAL_UART_Receive_IT */
static volatile uint8_t   s_fault;
static volatile uint8_t   s_hv_active;

/* ---- thread handles + attributes ----------------------------------------- */
static osThreadId_t s_safety, s_seq, s_comms, s_logger;

/* tComms sits ABOVE tSequencer deliberately (FW-07). It spends its life blocked
 * on the RX queue, so it costs nothing until a byte arrives; below the sequencer
 * it was never scheduled during a run, and >ABORT - which works by setting a
 * flag the run loops poll - could not be received at all. */
static const osThreadAttr_t s_attr_safety = { .name = "tSafety",    .priority = osPriorityHigh,        .stack_size = 256 * 4 };
static const osThreadAttr_t s_attr_seq    = { .name = "tSequencer", .priority = osPriorityNormal,      .stack_size = 512 * 4 };
static const osThreadAttr_t s_attr_comms  = { .name = "tComms",     .priority = osPriorityAboveNormal, .stack_size = 256 * 4 };
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

static void run_continuity_all(uint8_t discover);
static void run_resistance_all(void);
static void run_insulation_all(void);

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
      case CMD_CONT_RUN:  Proto_EvtState("fault"); Proto_EvtDone("cont",  0U, 0U); break;
      case CMD_RES_RUN:   Proto_EvtState("fault"); Proto_EvtDone("res",   0U, 0U); break;
      case CMD_INSUL_RUN: Proto_EvtState("fault"); Proto_EvtDone("insul", 0U, 0U); break;
      default: break;
    }
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
  * @param  discover : [in] 0 = verify the loaded netlist, 1 = scan everything.
  * @retval None
  */
static void run_continuity_all(uint8_t discover)
{
  ContinuityResult_t r;
  uint16_t i, n, hi, lo;
  uint16_t pass = 0U, fail = 0U;

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
    for (hi = 1U; hi <= 256U; hi++)
    {
      for (lo = 1U; lo <= 256U; lo++)
      {
        if (Continuity_TestPair(hi, lo, &r) == HAL_OK && r.verdict == TEST_PASS)
        {
          Proto_EvtCont(hi, lo, "pass");
          pass++;
        }
      }
      Proto_EvtProgress(hi, 256U);
      if (s_fault != 0U || Proto_AbortRequested() != 0U) { break; }
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
        Proto_EvtCont(hi, lo, "open");
        fail++;
      }
      else if (r.verdict == TEST_PASS)
      {
        Proto_EvtCont(hi, lo, "pass");
        pass++;
      }
      else
      {
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
  * @brief  Resistance over the loaded netlist.
  * @note   Kelvin_MeasurePair (FW-02) reads HI_SENSE/LO_SENSE on the Matrix
  *         Card's ADS124S08, auto-ranging the PGA and subtracting a
  *         zero-current baseline per point. A bus/driver error (not a real
  *         over-limit reading) still reports fail_high here rather than a
  *         number computed from a failed conversion.
  * @retval None
  */
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
      int32_t mohm = (int32_t)(r.resistance_ohm * 1000.0f);
      const char *v = (mohm <= limit) ? "pass" : "fail_high";
      Proto_EvtRes(hi, lo, mohm, v);
      if (mohm <= limit) { pass++; } else { fail++; }
    }
    Proto_EvtProgress((uint16_t)(i + 1U), n);
    if (s_fault != 0U || Proto_AbortRequested() != 0U) { break; }
  }

  Proto_EvtState("idle");
  Proto_EvtDone("res", pass, fail);
}

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

  if (Proto_HvArmed() == 0U)
  {
    Proto_EvtFault("F03", "HV not armed");
    Proto_EvtDone("insul", 0U, 0U);
    return;
  }

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

    if (Insulation_TestPair(0U, (uint8_t)hi, (uint8_t)lo, 0.5f, &r) != HAL_OK)
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
      Proto_EvtInsul(hi, (int32_t)(r.insulation_mohm * 1.0e9f), v);
      if (r.verdict == TEST_PASS) { pass++; }
      else { Proto_EvtFault("F04", "insulation low"); fail++; }
    }
    Proto_EvtProgress((uint16_t)(i + 1U), n);
    if (s_fault != 0U || Proto_AbortRequested() != 0U) { break; }
  }

  /* Always leave HV down and disarmed. */
  force_safe_all();
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
/* post_simple() removed with the single-keystroke console - the protocol layer
 * builds and posts commands itself (see Core/Src/app/proto.c). */

/**
  * @brief  Console RX complete: hand the byte to tComms and re-arm.
  * @note   Runs in the LPUART1 ISR at priority 5, the most urgent level allowed
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
  console_puts("#[boot] HT_MK1 console up @115200\r\n");
  if (Log_Init(s_console) != HAL_OK)
  {
    console_puts("#[boot] LOG init FAILED\r\n");
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

  LOG_I("SYS", "tasks started (hv boards=%u)", (unsigned)BOARD_HV_COUNT);
}
