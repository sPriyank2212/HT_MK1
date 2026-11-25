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
  *              binds USART2 (PA2/PA3): the MCP2221A USB-UART on the product, the ST-LINK VCP on a Nucleo.
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
#include "i2c.h"
#include "spi.h"

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
#define LOG_MSG_MAX      112U    /* max bytes per line incl. prefix + CRLF */
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
  * @brief  Transmit a block on the console UART, serialised against every other
  *         writer.
  * @note   Three threads write this UART: the logger, the sequencer (result
  *         events) and comms (command replies). HAL_UART_Transmit is not
  *         reentrant - a second caller gets HAL_BUSY and its line is silently
  *         lost, which for a protocol reply means the GUI times out and declares
  *         the link dead. Everything that writes the console must go through
  *         here. Falls back to a direct transmit before the scheduler is
  *         running, when there is nothing to race with.
  * @param  data    : [in] bytes to send.
  * @param  len     : [in] byte count.
  * @param  timeout : [in] per-transmit HAL timeout, milliseconds.
  * @retval HAL_OK on success, HAL_ERROR if the UART is unbound or the mutex
  *         could not be taken in time.
  */
HAL_StatusTypeDef Log_ConsoleWrite(const uint8_t *data, uint16_t len, uint32_t timeout);

/**
  * @brief  Bind the console to USART2 (PA2 TX / PA3 RX, 115200 8N1) and arm its
  *         RX interrupt. On the product these pins go to the MCP2221A USB-UART
  *         bridge; on a Nucleo-G474RE they reach the ST-LINK virtual COM port.
  *         USART2 itself is initialised by CubeMX's MX_USART2_UART_Init().
  * @retval The UART handle, or NULL if USART2 was never initialised.
  */
UART_HandleTypeDef *Log_HwInit_Console(void);

/* Source location of the call site. GCC 12+ gives the bare file name. */
#ifndef __FILE_NAME__
#define __FILE_NAME__ __FILE__
#endif

/**
  * @brief  Like Log_Write() but appends " @file:line" of the call site. The
  *         location is reserved first, so a long message is cut, never the
  *         location. LOG_E / LOG_W use this, so every error and warning in the
  *         firmware says exactly where it was raised.
  */
void Log_WriteAt(LogLevel_t lvl, const char *file, int line, const char *tag, const char *fmt, ...);

#define LOG_E(tag, ...) do { if ((LOG_LEVEL) >= LOG_ERROR) Log_WriteAt(LOG_ERROR, __FILE_NAME__, __LINE__, (tag), __VA_ARGS__); } while (0)
#define LOG_W(tag, ...) do { if ((LOG_LEVEL) >= LOG_WARN ) Log_WriteAt(LOG_WARN , __FILE_NAME__, __LINE__, (tag), __VA_ARGS__); } while (0)
#define LOG_I(tag, ...) do { if ((LOG_LEVEL) >= LOG_INFO ) Log_Write(LOG_INFO , (tag), __VA_ARGS__); } while (0)
#define LOG_D(tag, ...) do { if ((LOG_LEVEL) >= LOG_DEBUG) Log_Write(LOG_DEBUG, (tag), __VA_ARGS__); } while (0)

/* -------------------------------------------------------------------------- */
/* Failure diagnostics (implemented in log.c)                                  */
/*                                                                             */
/* Every failed I2C / SPI transaction and every error return in the drivers,   */
/* cards and test code is recorded with file, line, bus, device address,       */
/* register, HAL status and the peripheral's own error code, and printed as    */
/*   #E[tick] DIAG: mcp23017.c:55 i2c2 wr 0x22 r0x0A hal=1 e=0x04(NAK) x3      */
/* Repeats of the same failure are counted and printed only at 1, 2, 4, 8 ...  */
/* so a dead card cannot flood the console. Records made before the logger     */
/* exists (Board_Init) are kept and printed by Diag_Go().                      */
/* -------------------------------------------------------------------------- */

/** @brief Forget the "first failure" record; call at the start of a bring-up. */
void Diag_Mark(void);
/** @brief The logger is up: print everything recorded so far, and print new records immediately. */
void Diag_Go(void);
/** @brief Record a failed I2C transaction. @p what e.g. "wr", "rd". */
void Diag_I2c(const char *file, int line, const char *what, HAL_StatusTypeDef st,
              const I2C_HandleTypeDef *h, uint8_t addr7, uint8_t reg);
/** @brief Record a failed SPI transaction. */
void Diag_Spi(const char *file, int line, const char *what, HAL_StatusTypeDef st,
              const SPI_HandleTypeDef *h);
/** @brief Record any other failure (logic error, NULL argument, timeout, bad ID ...). */
void Diag_Fail(const char *file, int line, const char *what, HAL_StatusTypeDef st);
/** @brief Diag_Fail() only if @p st is not HAL_OK; returns @p st unchanged. */
HAL_StatusTypeDef Diag_Check(HAL_StatusTypeDef st, const char *file, int line, const char *what);
/** @brief Text of the FIRST failure since Diag_Mark(), e.g. "mcp23017.c:55 i2c2 NAK"; "" if none. */
void Diag_FirstText(char *buf, uint8_t n);

/** Use as   st = DIAG_ST(MCP23017_Init(...), "matrix force exp");   */
#define DIAG_ST(expr, what)  Diag_Check((expr), __FILE_NAME__, __LINE__, (what))
/** Use as   return DIAG_RET(HAL_ERROR);   - records file:line and returns the status. */
#define DIAG_RET(st)         Diag_Check((st), __FILE_NAME__, __LINE__, "return")
/** Use as   DIAG_FAIL("bad id", HAL_ERROR);  */
#define DIAG_FAIL(what, st)  Diag_Fail(__FILE_NAME__, __LINE__, (what), (st))

#ifdef __cplusplus
}
#endif

#endif /* __LOG_H */
