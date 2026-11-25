/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    log.c
  * @brief   Non-blocking layered logger implementation. See log.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "app/log.h"
#include "usart.h"
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
  * @note   Builds "#<L>[tick] tag: <message> @file:line\r\n", clamped to
  *         LOG_MSG_MAX. The " @file:line" tail is reserved first, so a long
  *         message is truncated rather than losing the location. Posted
  *         non-blocking: if the queue is full the line is dropped rather than
  *         stalling the caller, so this is safe from an ISR. No-op if the
  *         logger has not been initialised.
  * @param  lvl  : [in] severity level (selects the prefix character).
  * @param  file : [in] source file name, or NULL for no location tail.
  * @param  line : [in] source line.
  * @param  tag  : [in] short subsystem tag; NULL is treated as empty.
  * @param  fmt  : [in] printf-style format string for the message body.
  * @param  ap   : [in] arguments consumed by @p fmt.
  */
static void log_vemit(LogLevel_t lvl, const char *file, int line,
                      const char *tag, const char *fmt, va_list ap)
{
  LogMsg_t m;
  char tail[32];
  int n, tl = 0, room, k;

  if (s_logq == NULL)
  {
    return;
  }

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

  tail[0] = '\0';
  if (file != NULL)
  {
    tl = snprintf(tail, sizeof(tail), " @%s:%d", file, line);
    if (tl < 0) { tl = 0; tail[0] = '\0'; }
    if (tl > (int)sizeof(tail) - 1) { tl = (int)sizeof(tail) - 1; }
  }

  room = (int)sizeof(m.buf) - 2 - n - tl;     /* body bytes, leaving CRLF + tail */
  if (room < 0)
  {
    room = 0;
  }
  k = vsnprintf(&m.buf[n], (size_t)room + 1U, fmt, ap);
  if (k < 0)
  {
    return;
  }
  if (k > room)
  {
    k = room;
  }
  n += k;
  memcpy(&m.buf[n], tail, (size_t)tl);
  n += tl;
  m.buf[n++] = '\r';
  m.buf[n++] = '\n';
  m.len = (uint8_t)n;

  /* Non-blocking: drop the line rather than stall the caller. ISR-safe. */
  (void)osMessageQueuePut(s_logq, &m, 0U, 0U);
}

void Log_Write(LogLevel_t lvl, const char *tag, const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  log_vemit(lvl, NULL, 0, tag, fmt, ap);
  va_end(ap);
}

void Log_WriteAt(LogLevel_t lvl, const char *file, int line, const char *tag,
                 const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  log_vemit(lvl, file, line, tag, fmt, ap);
  va_end(ap);
}

/* ========================================================================== */
/* Failure diagnostics                                                         */
/* ========================================================================== */

#define DIAG_SITES  12U

typedef enum { DK_GENERIC = 0, DK_I2C = 1, DK_SPI = 2 } DiagKind_t;

typedef struct
{
  const char *file;
  const char *what;
  uint16_t    line;
  uint8_t     kind;
  uint8_t     hal;
  uint8_t     bus;     /* I2C2 -> 2, I2C3 -> 3, SPI1..3 -> 1..3, else 0 */
  uint8_t     addr;
  uint8_t     reg;
  uint32_t    err;     /* the peripheral's ErrorCode */
  uint32_t    count;
  uint32_t    printed; /* count at the last print */
  uint8_t     used;
} DiagSite_t;

static DiagSite_t s_site[DIAG_SITES];
static uint8_t    s_site_next;
static uint8_t    s_diag_live;
static DiagSite_t s_first;
static uint8_t    s_first_valid;

static const char *diag_i2c_err(uint32_t e)
{
  if ((e & HAL_I2C_ERROR_AF) != 0U)      { return "NAK"; }
  if ((e & HAL_I2C_ERROR_TIMEOUT) != 0U) { return "TIMEOUT"; }
  if ((e & HAL_I2C_ERROR_ARLO) != 0U)    { return "ARLO"; }
  if ((e & HAL_I2C_ERROR_BERR) != 0U)    { return "BERR"; }
  if ((e & HAL_I2C_ERROR_OVR) != 0U)     { return "OVR"; }
  return (e == 0U) ? "none" : "ERR";
}

static void diag_print(const DiagSite_t *r, uint32_t count)
{
  char rep[16];
  rep[0] = '\0';
  if (count > 1U)
  {
    (void)snprintf(rep, sizeof(rep), " x%lu", (unsigned long)count);
  }
  switch (r->kind)
  {
    case DK_I2C:
      Log_Write(LOG_ERROR, "DIAG", "%s:%u i2c%u %s 0x%02X r0x%02X hal=%u e=0x%02lX(%s)%s",
                r->file, (unsigned)r->line, (unsigned)r->bus, r->what,
                (unsigned)r->addr, (unsigned)r->reg, (unsigned)r->hal,
                (unsigned long)r->err, diag_i2c_err(r->err), rep);
      break;
    case DK_SPI:
      Log_Write(LOG_ERROR, "DIAG", "%s:%u spi%u %s hal=%u e=0x%02lX%s",
                r->file, (unsigned)r->line, (unsigned)r->bus, r->what,
                (unsigned)r->hal, (unsigned long)r->err, rep);
      break;
    default:
      Log_Write(LOG_ERROR, "DIAG", "%s:%u %s hal=%u%s",
                r->file, (unsigned)r->line, r->what, (unsigned)r->hal, rep);
      break;
  }
}

static void diag_record(const DiagSite_t *in)
{
  DiagSite_t snap;
  uint32_t   primask = __get_PRIMASK();
  uint8_t    i, hit = 0U, idx = 0U, emit = 0U;

  __disable_irq();
  for (i = 0U; i < DIAG_SITES; i++)
  {
    const DiagSite_t *x = &s_site[i];
    if (x->used != 0U && x->file == in->file && x->line == in->line &&
        x->hal == in->hal && x->addr == in->addr && x->reg == in->reg &&
        x->err == in->err && x->what == in->what)
    {
      hit = 1U;
      idx = i;
      break;
    }
  }
  if (hit == 0U)
  {
    idx = s_site_next;
    s_site_next = (uint8_t)((s_site_next + 1U) % DIAG_SITES);
    s_site[idx] = *in;
    s_site[idx].used = 1U;
    s_site[idx].count = 0U;
    s_site[idx].printed = 0U;
  }
  s_site[idx].count++;
  if (s_first_valid == 0U)
  {
    s_first = s_site[idx];
    s_first_valid = 1U;
  }
  /* Print the 1st, 2nd, 4th, 8th ... occurrence of the same failure. */
  emit = (uint8_t)((s_site[idx].count & (s_site[idx].count - 1U)) == 0U);
  if (emit != 0U && s_diag_live != 0U)
  {
    s_site[idx].printed = s_site[idx].count;
  }
  snap = s_site[idx];
  if (primask == 0U)
  {
    __enable_irq();
  }

  if (emit != 0U && s_diag_live != 0U)
  {
    diag_print(&snap, snap.count);
  }
}

void Diag_Mark(void)
{
  s_first_valid = 0U;
}

void Diag_Go(void)
{
  uint8_t i;
  s_diag_live = 1U;
  for (i = 0U; i < DIAG_SITES; i++)
  {
    if (s_site[i].used != 0U && s_site[i].count > s_site[i].printed)
    {
      s_site[i].printed = s_site[i].count;
      diag_print(&s_site[i], s_site[i].count);
    }
  }
}

void Diag_I2c(const char *file, int line, const char *what, HAL_StatusTypeDef st,
              const I2C_HandleTypeDef *h, uint8_t addr7, uint8_t reg)
{
  DiagSite_t r = {0};
  r.file = file; r.line = (uint16_t)line; r.what = what; r.kind = DK_I2C;
  r.hal = (uint8_t)st; r.addr = addr7; r.reg = reg;
  r.bus = (h == &hi2c2) ? 2U : (h == &hi2c3) ? 3U : 0U;
  r.err = (h != NULL) ? h->ErrorCode : 0U;
  diag_record(&r);
}

void Diag_Spi(const char *file, int line, const char *what, HAL_StatusTypeDef st,
              const SPI_HandleTypeDef *h)
{
  DiagSite_t r = {0};
  r.file = file; r.line = (uint16_t)line; r.what = what; r.kind = DK_SPI;
  r.hal = (uint8_t)st;
  r.bus = (h == &hspi1) ? 1U : (h == &hspi2) ? 2U : (h == &hspi3) ? 3U : 0U;
  r.err = (h != NULL) ? h->ErrorCode : 0U;
  diag_record(&r);
}

void Diag_Fail(const char *file, int line, const char *what, HAL_StatusTypeDef st)
{
  DiagSite_t r = {0};
  r.file = file; r.line = (uint16_t)line; r.what = what; r.kind = DK_GENERIC;
  r.hal = (uint8_t)st;
  diag_record(&r);
}

HAL_StatusTypeDef Diag_Check(HAL_StatusTypeDef st, const char *file, int line, const char *what)
{
  if (st != HAL_OK)
  {
    Diag_Fail(file, line, what, st);
  }
  return st;
}

void Diag_FirstText(char *buf, uint8_t n)
{
  if (buf == NULL || n == 0U)
  {
    return;
  }
  buf[0] = '\0';
  if (s_first_valid == 0U)
  {
    return;
  }
  switch (s_first.kind)
  {
    case DK_I2C:
      (void)snprintf(buf, n, "%s:%u i2c%u %s", s_first.file, (unsigned)s_first.line,
                     (unsigned)s_first.bus, diag_i2c_err(s_first.err));
      break;
    case DK_SPI:
      (void)snprintf(buf, n, "%s:%u spi%u e=%lX", s_first.file, (unsigned)s_first.line,
                     (unsigned)s_first.bus, (unsigned long)s_first.err);
      break;
    default:
      (void)snprintf(buf, n, "%s:%u", s_first.file, (unsigned)s_first.line);
      break;
  }
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
/* Product console: USART2 (PA2/PA3) -> MCP2221A USB-UART bridge (Control Card */
/* "USB to UART" sheet, U12). The same two pins reach the ST-LINK VCP on a     */
/* Nucleo-G474RE, so the bench board needs no separate path.                   */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Bind the GUI/log console to USART2 (115200 8N1, PA2 TX / PA3 RX).
  * @note   USART2 itself - clock, PA2/PA3 alternate function (AF7), baud,
  *         framing - is brought up by CubeMX's MX_USART2_UART_Init() in main();
  *         this only checks that it ran and arms the interrupt the RX path
  *         depends on. Replaces the old Log_HwInit_LPUART1() Nucleo helper,
  *         which fought MX_USART2_UART_Init() over the same two pins (AF12 vs
  *         AF7) - the schematic net is USART2_TX/USART2_RX.
  * @retval UART_HandleTypeDef* &huart2, or NULL if USART2 was never initialised.
  */
UART_HandleTypeDef *Log_HwInit_Console(void)
{
  if (huart2.Instance != USART2 || huart2.gState == HAL_UART_STATE_RESET)
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
  HAL_NVIC_SetPriority(USART2_IRQn, 5U, 0U);
  HAL_NVIC_EnableIRQ(USART2_IRQn);

  return &huart2;
}

/**
  * @brief  USART2 interrupt entry point.
  * @note   Defined here rather than in stm32g4xx_it.c because this file owns
  *         the console binding: the CubeMX project does not enable the USART2
  *         global interrupt, so no generated handler exists. The startup
  *         file's symbol is weak, so this definition wins. HAL dispatches to
  *         HAL_UART_RxCpltCallback / HAL_UART_ErrorCallback, both implemented
  *         in app/tasks.c. If the interrupt is ever enabled in the .ioc, delete
  *         this and keep CubeMX's handler.
  * @retval None
  */
void USART2_IRQHandler(void)
{
  HAL_UART_IRQHandler(&huart2);
}
