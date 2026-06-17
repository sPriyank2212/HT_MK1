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

HAL_StatusTypeDef Log_Init(UART_HandleTypeDef *huart)
{
  s_uart = huart;
  s_logq = osMessageQueueNew(LOG_QUEUE_DEPTH, sizeof(LogMsg_t), NULL);
  return (s_logq != NULL && s_uart != NULL) ? HAL_OK : HAL_ERROR;
}

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
  n = snprintf(m.buf, sizeof(m.buf), "%c[%lu] %s: ",
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

void Log_Task(void *argument)
{
  LogMsg_t m;
  (void)argument;

  for (;;)
  {
    if (osMessageQueueGet(s_logq, &m, NULL, osWaitForever) == osOK)
    {
      if (s_uart != NULL)
      {
        (void)HAL_UART_Transmit(s_uart, (uint8_t *)m.buf, m.len, 100U);
      }
    }
  }
}

/* -------------------------------------------------------------------------- */
/* Nucleo LPUART1 (PA2/PA3 -> ST-LINK VCP) bring-up                           */
/* -------------------------------------------------------------------------- */
static UART_HandleTypeDef s_hlpuart1;

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
  return &s_hlpuart1;
}
