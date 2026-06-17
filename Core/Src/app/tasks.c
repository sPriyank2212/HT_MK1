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

/* ---- safety -------------------------------------------------------------- */

void Safety_SignalFault(const char *reason)
{
  s_fault = 1U;
  LOG_E("SAFE", "fault: %s", (reason != NULL) ? reason : "?");
}

void Safety_ClearFault(void) { s_fault = 0U; }
int  Safety_InFault(void)    { return (int)s_fault; }

/* Drop the whole instrument to a safe state (HV off, relays + muxes open). */
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

static void post_simple(TestCmdType_t t, uint16_t a, uint16_t b, uint8_t board, float vf)
{
  TestCmd_t c = { t, a, b, board, vf };
  (void)Tasks_PostCommand(&c);
}

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

int Tasks_PostCommand(const TestCmd_t *cmd)
{
  if (cmd == NULL || s_cmdq == NULL)
  {
    return -1;
  }
  return (osMessageQueuePut(s_cmdq, cmd, 0U, 0U) == osOK) ? 0 : 1;
}

/* Synchronous, no-queue console write - works even if tasks/heap fail, so a
 * boot banner always appears if the UART itself is alive. */
static void console_puts(const char *s)
{
  if (s_console != NULL && s != NULL)
  {
    (void)HAL_UART_Transmit(s_console, (uint8_t *)s, (uint16_t)strlen(s), 50U);
  }
}

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

  LOG_I("SYS", "tasks started (hv boards=%u)", (unsigned)BOARD_HV_COUNT);
}
