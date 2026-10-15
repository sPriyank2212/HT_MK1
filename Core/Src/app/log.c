/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    log.c
  * @brief   Non-blocking layered logger implementation. See log.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "app/log.h"
#include "cmsis_os2.h"
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

typedef struct
{
  uint8_t len;
  char    buf[LOG_MSG_MAX];
} LogMsg_t;

static osMessageQueueId_t s_logq;
static UART_HandleTypeDef *s_uart;
static osMutexId_t        s_txmtx;   /* serialises every console writer */

/**
  * @brief  Map a log level to its single-character prefix.
  * @param  lvl : [in] log level.
  * @retval char 'E', 'W', 'I', 'D' for the known levels, '?' otherwise.
  */
static char log_level_char(LogLevel_t lvl)
{
  switch (lvl)
  {
    case LOG_ERROR: return 'E';
    case LOG_WARN:  return 'W';
    case LOG_INFO:  return 'I';
    case LOG_DEBUG: return 'D';
    default:        return '?';
  }
}

/**
  * @brief  Initialise the logger: record the output UART and create the queue.
  * @note   Must be called before Log_Write()/Log_Task(). Does not start the
  *         drain thread; Log_Task() is created separately by the task layer.
  * @param  huart : [in] UART used to drain log lines; must be non-NULL.
  * @retval HAL_OK    queue created and UART recorded.
  * @retval HAL_ERROR queue allocation failed or @p huart is NULL.
  */
HAL_StatusTypeDef Log_Init(UART_HandleTypeDef *huart)
{
  s_uart  = huart;
  s_logq  = osMessageQueueNew(LOG_QUEUE_DEPTH, sizeof(LogMsg_t), NULL);
  s_txmtx = osMutexNew(NULL);
  return (s_logq != NULL && s_uart != NULL && s_txmtx != NULL) ? HAL_OK : HAL_ERROR;
}

HAL_StatusTypeDef Log_ConsoleWrite(const uint8_t *data, uint16_t len, uint32_t timeout)
{
  HAL_StatusTypeDef st;

  if (s_uart == NULL || data == NULL || len == 0U)
  {
    return HAL_ERROR;
  }

  /* Before the scheduler runs there is no mutex and no one to race with. */
  if (s_txmtx == NULL || osKernelGetState() != osKernelRunning)
  {
    return HAL_UART_Transmit(s_uart, (uint8_t *)data, len, timeout);
  }

  /* Wait long enough to outlast a full line in flight at 115200 rather than
   * dropping ours: a dropped protocol reply costs the GUI a 2 s timeout. */
  if (osMutexAcquire(s_txmtx, timeout) != osOK)
  {
    return HAL_ERROR;
  }
  st = HAL_UART_Transmit(s_uart, (uint8_t *)data, len, timeout);
  (void)osMutexRelease(s_txmtx);
  return st;
}

/**
  * @brief  Format one log line and enqueue it for the drain task.
  * @note   Builds "<L>[tick] tag: <message>\r\n", clamped to LOG_MSG_MAX, then
  *         posts it non-blocking: if the queue is full the line is dropped
  *         rather than stalling the caller, so this is safe from an ISR. No-op
  *         if the logger has not been initialised. Prefer the LOG_x() macros.
  * @param  lvl : [in] severity level (selects the prefix character).
  * @param  tag : [in] short subsystem tag; NULL is treated as empty.
  * @param  fmt : [in] printf-style format string for the message body.
  * @param  ... : [in] arguments consumed by @p fmt.
  * @retval None
  */
void Log_Write(LogLevel_t lvl, const char *tag, const char *fmt, ...)
{
  LogMsg_t m;
  int n;
  va_list ap;

  if (s_logq == NULL)
  {
    return;
  }

  /* Prefix: "<L>[tick] tag: " */
  /* Leading '#' marks a human-readable log line for the GUI protocol - see
   * Doc/GUI_development_brief.md 3.1. Anything not starting '<' or '!' is
   * display-only, and the '#' makes that explicit rather than implied. */
  n = snprintf(m.buf, sizeof(m.buf), "#%c[%lu] %s: ",
               log_level_char(lvl), (unsigned long)osKernelGetTickCount(),
               (tag != NULL) ? tag : "");
  if (n < 0)
  {
    return;
  }
  if (n > (int)(sizeof(m.buf) - 3))
  {
    n = (int)(sizeof(m.buf) - 3);
  }

  va_start(ap, fmt);
  n += vsnprintf(&m.buf[n], sizeof(m.buf) - (size_t)n - 2U, fmt, ap);
  va_end(ap);

  if (n < 0)
  {
    return;
  }
  if (n > (int)(sizeof(m.buf) - 3))
  {
    n = (int)(sizeof(m.buf) - 3);
  }
  m.buf[n++] = '\r';
  m.buf[n++] = '\n';
  m.len = (uint8_t)n;

  /* Non-blocking: drop the line rather than stall the caller. ISR-safe. */
  (void)osMessageQueuePut(s_logq, &m, 0U, 0U);
}

/**
  * @brief  Logger drain thread: block on the queue and transmit each line.
  * @note   Runs forever; the only place that touches the UART for logging, so
  *         formatting cost is kept off the producing threads. Bounded 100 ms
  *         TX timeout per line.
  * @param  argument : [in] unused FreeRTOS thread argument.
  * @retval None (does not return).
  */
void Log_Task(void *argument)
{
  LogMsg_t m;
  (void)argument;

  for (;;)
  {
    if (osMessageQueueGet(s_logq, &m, NULL, osWaitForever) == osOK)
    {
      (void)Log_ConsoleWrite((uint8_t *)m.buf, m.len, 100U);
    }
  }
}

/* -------------------------------------------------------------------------- */
/* Nucleo LPUART1 (PA2/PA3 -> ST-LINK VCP) bring-up                           */
/* -------------------------------------------------------------------------- */
static UART_HandleTypeDef s_hlpuart1;

/**
  * @brief  Bring up LPUART1 on the Nucleo (PA2/PA3 -> ST-LINK VCP) at 115200 8N1.
  * @note   Bring-up helper: selects the LPUART1 kernel clock, configures the
  *         PA2/PA3 alternate-function pins and initialises the peripheral. Swap
  *         for the product UART on the target hardware.
  * @retval UART_HandleTypeDef* pointer to the initialised static handle, or
  *                             NULL if clock or UART init failed.
  */
UART_HandleTypeDef *Log_HwInit_LPUART1(void)
{
  GPIO_InitTypeDef gpio = {0};
  RCC_PeriphCLKInitTypeDef pclk = {0};

  /* LPUART1 kernel clock = PCLK1 (default). */
  pclk.PeriphClockSelection = RCC_PERIPHCLK_LPUART1;
  pclk.Lpuart1ClockSelection = RCC_LPUART1CLKSOURCE_PCLK1;
  if (HAL_RCCEx_PeriphCLKConfig(&pclk) != HAL_OK)
  {
    return NULL;
  }

  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_LPUART1_CLK_ENABLE();

  /* PA2 = LPUART1_TX, PA3 = LPUART1_RX (AF12). */
  gpio.Pin       = GPIO_PIN_2 | GPIO_PIN_3;
  gpio.Mode      = GPIO_MODE_AF_PP;
  gpio.Pull      = GPIO_NOPULL;
  gpio.Speed     = GPIO_SPEED_FREQ_LOW;
  gpio.Alternate = GPIO_AF12_LPUART1;
  HAL_GPIO_Init(GPIOA, &gpio);

  s_hlpuart1.Instance                    = LPUART1;
  s_hlpuart1.Init.BaudRate               = 115200;
  s_hlpuart1.Init.WordLength             = UART_WORDLENGTH_8B;
  s_hlpuart1.Init.StopBits               = UART_STOPBITS_1;
  s_hlpuart1.Init.Parity                 = UART_PARITY_NONE;
  s_hlpuart1.Init.Mode                   = UART_MODE_TX_RX;
  s_hlpuart1.Init.HwFlowCtl              = UART_HWCONTROL_NONE;
  s_hlpuart1.Init.OverSampling           = UART_OVERSAMPLING_16;
  s_hlpuart1.Init.OneBitSampling         = UART_ONE_BIT_SAMPLE_DISABLE;
  s_hlpuart1.Init.ClockPrescaler         = UART_PRESCALER_DIV1;
  s_hlpuart1.AdvancedInit.AdvFeatureInit = UART_ADVFEATURE_NO_INIT;
  if (HAL_UART_Init(&s_hlpuart1) != HAL_OK)
  {
    return NULL;
  }

  /* RX is interrupt-driven (see CommsTask): the receiver must not depend on a
   * task being scheduled to catch a byte, or commands sent while the sequencer
   * is mid-run are lost to overrun - which is what made >ABORT useless (FW-07).
   *
   * Priority 5 == configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY, the most urgent
   * level still permitted to call the FreeRTOS *FromISR* API. Anything more
   * urgent would trip the configASSERT in the kernel.
   */
  HAL_NVIC_SetPriority(LPUART1_IRQn, 5U, 0U);
  HAL_NVIC_EnableIRQ(LPUART1_IRQn);

  return &s_hlpuart1;
}

/**
  * @brief  LPUART1 interrupt entry point.
  * @note   Defined here rather than in stm32g4xx_it.c because this file owns
  *         the peripheral: LPUART1 is brought up by hand above, not by CubeMX,
  *         so no generated handler exists. The startup file's symbol is weak,
  *         so this definition wins. HAL dispatches to HAL_UART_RxCpltCallback /
  *         HAL_UART_ErrorCallback, both implemented in app/tasks.c.
  * @retval None
  */
void LPUART1_IRQHandler(void)
{
  HAL_UART_IRQHandler(&s_hlpuart1);
}
