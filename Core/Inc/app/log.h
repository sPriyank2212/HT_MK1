/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    log.h
  * @brief   Lightweight, layered, non-blocking event logger.
  *
  *          Design goals (per requirements):
  *            - Standard levels: ERROR / WARN / INFO / DEBUG, compile-time gated
  *              by LOG_LEVEL so disabled levels cost nothing.
  *            - Must NOT disturb real-time tasks: LOG_x() only formats a short
  *              line and drops it into a queue (non-blocking, drop-if-full). The
  *              actual UART transmit happens in the lowest-priority logger task.
  *            - Short lines: "<L>[tick] tag: msg".
  *            - UART-agnostic: bind any handle. For Nucleo bring-up a helper
  *              brings up LPUART1 on PA2/PA3 -> the ST-LINK virtual COM port.
  *
  *          Usage:  LOG_I("HV", "en board=%u", b);
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __LOG_H
#define __LOG_H

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"

typedef enum
{
  LOG_NONE  = 0,
  LOG_ERROR = 1,
  LOG_WARN  = 2,
  LOG_INFO  = 3,
  LOG_DEBUG = 4
} LogLevel_t;

/* Compile-time minimum level. Set lower (e.g. LOG_WARN) for release. */
#ifndef LOG_LEVEL
#define LOG_LEVEL        LOG_INFO
#endif
#ifndef LOG_MSG_MAX
#define LOG_MSG_MAX      72U     /* max bytes per line incl. prefix + CRLF */
#endif
#ifndef LOG_QUEUE_DEPTH
#define LOG_QUEUE_DEPTH  24U
#endif

/**
  * @brief  Create the log queue and bind the output UART. Call once at start.
  */
HAL_StatusTypeDef Log_Init(UART_HandleTypeDef *huart);

/**
  * @brief  Format + enqueue one line. Never blocks; drops the line if the queue
  *         is full. Safe to call from tasks and ISRs.
  */
void Log_Write(LogLevel_t lvl, const char *tag, const char *fmt, ...);

/**
  * @brief  Logger task body (drains the queue to the UART). Lowest priority.
  */
void Log_Task(void *argument);

/**
  * @brief  Nucleo helper: bring up LPUART1 on PA2/PA3 (AF12) at 115200 8N1,
  *         which reaches the ST-LINK virtual COM port. Returns the handle, or
  *         NULL on failure. (In the product these pins are USART2; swap there.)
  */
UART_HandleTypeDef *Log_HwInit_LPUART1(void);

#define LOG_E(tag, ...) do { if ((LOG_LEVEL) >= LOG_ERROR) Log_Write(LOG_ERROR, (tag), __VA_ARGS__); } while (0)
#define LOG_W(tag, ...) do { if ((LOG_LEVEL) >= LOG_WARN ) Log_Write(LOG_WARN , (tag), __VA_ARGS__); } while (0)
#define LOG_I(tag, ...) do { if ((LOG_LEVEL) >= LOG_INFO ) Log_Write(LOG_INFO , (tag), __VA_ARGS__); } while (0)
#define LOG_D(tag, ...) do { if ((LOG_LEVEL) >= LOG_DEBUG) Log_Write(LOG_DEBUG, (tag), __VA_ARGS__); } while (0)

#ifdef __cplusplus
}
#endif

#endif /* __LOG_H */
