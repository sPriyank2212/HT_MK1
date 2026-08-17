/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    proto.c
  * @brief   Instrument side of the GUI protocol. See proto.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "app/proto.h"
#include "app/tasks.h"
#include "app/log.h"
#include "bsp/board.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>

#define PROTO_TX_MAX      96U
#define PROTO_TX_TIMEOUT  50U
#define PROTO_MAX_TOKENS  6U

static UART_HandleTypeDef *s_uart;

static char     s_rx[PROTO_RX_MAX + 1U];
static uint16_t s_rx_len;
static uint8_t  s_overflow;      /* line too long - discard to the newline */

static uint16_t s_net_hi[PROTO_NETLIST_MAX];
static uint16_t s_net_lo[PROTO_NETLIST_MAX];
static uint16_t s_net_count;
static uint16_t s_net_pending;   /* entries promised by NETLIST BEGIN */
static uint8_t  s_net_loading;

static ProtoFixture_t s_fixture = PROTO_FIXTURE_NONE;
static uint8_t  s_armed;
static int32_t  s_hv_mv;
static int32_t  s_lim_r_mohm   = 5000;    /* 5 ohm  */
static int32_t  s_lim_ins_mohm = 10000000;/* 10 Mohm */
static volatile uint8_t s_busy;    /* a whole-run command is executing */
static volatile uint8_t s_abort;   /* operator asked the run to stop    */

/* -------------------------------------------------------------------------- */
/* Output                                                                     */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Send one complete line, terminator included, as a single write.
  * @note   Must be ONE transmit. Three threads write this UART - the logger, the
  *         sequencer streaming results, and comms answering commands - so a line
  *         split across two calls can have another thread's line spliced into
  *         the middle of it. Log_ConsoleWrite() holds the console mutex for the
  *         whole line.
  * @param  s   : [in] line bytes, CRLF included.
  * @param  len : [in] byte count.
  * @retval None
  */
static void proto_line(const char *s, uint16_t len)
{
  if (s_uart == NULL || s == NULL)
  {
    return;
  }
  (void)Log_ConsoleWrite((const uint8_t *)s, len, PROTO_TX_TIMEOUT);
}

/**
  * @brief  Format and send a line with a leading marker character.
  * @note   Reserves three bytes of the buffer: one for the marker and two for
  *         the CRLF appended here, so the line leaves as one frame.
  * @param  mark : [in] '<' reply, '!' event.
  * @param  fmt  : [in] printf-style format for the body.
  * @retval None
  */
static void proto_emit(char mark, const char *fmt, ...)
{
  char buf[PROTO_TX_MAX];
  va_list ap;
  size_t len;
  int n;

  buf[0] = mark;
  va_start(ap, fmt);
  n = vsnprintf(&buf[1], sizeof(buf) - 3U, fmt, ap);
  va_end(ap);
  if (n < 0)
  {
    return;
  }

  /* vsnprintf reports what it WOULD have written; clamp to what it did. */
  len = (size_t)n;
  if (len > (sizeof(buf) - 4U))
  {
    len = sizeof(buf) - 4U;
  }
  len += 1U;                     /* marker */
  buf[len++] = '\r';
  buf[len++] = '\n';
  proto_line(buf, (uint16_t)len);
}

/**
  * @brief  Send an error reply.
  * @param  code : [in] one of EBUSY / EFIXTURE / ENOTARMED / ERANGE / EHW / ESYNTAX.
  * @param  text : [in] short human-readable explanation.
  * @retval None
  */
static void proto_err(const char *code, const char *text)
{
  proto_emit('<', "ERR %s %s", code, text);
}

void Proto_EvtProgress(uint16_t done, uint16_t total)
{
  proto_emit('!', "PROGRESS %u %u", (unsigned)done, (unsigned)total);
}

void Proto_EvtCont(uint16_t hi, uint16_t lo, const char *verdict)
{
  proto_emit('!', "CONT %u %u %s", (unsigned)hi, (unsigned)lo, verdict);
}

void Proto_EvtRes(uint16_t hi, uint16_t lo, int32_t milliohms, const char *verdict)
{
  proto_emit('!', "RES %u %u %ld %s", (unsigned)hi, (unsigned)lo,
             (long)milliohms, verdict);
}

void Proto_EvtInsul(uint16_t net, int32_t leak_mohm, const char *verdict)
{
  proto_emit('!', "INSUL %u %ld %s", (unsigned)net, (long)leak_mohm, verdict);
}

void Proto_EvtFault(const char *code, const char *text)
{
  proto_emit('!', "FAULT %s %s", code, text);
}

/**
  * @brief  Announce that a run has finished.
  * @note   Always the LAST event of a run - the rail is already down, the state
  *         is already idle and every result has been sent. The GUI can treat
  *         !DONE as "everything about this run has been reported" without
  *         depending on the ordering of anything else.
  */
void Proto_EvtDone(const char *what, uint16_t passed, uint16_t failed)
{
  s_busy  = 0U;
  s_abort = 0U;
  proto_emit('!', "DONE %s %u %u", what, (unsigned)passed, (unsigned)failed);
}

void Proto_EvtState(const char *state)
{
  proto_emit('!', "STATE %s", state);
}

/**
  * @brief  Name the state this instrument is in right now.
  * @note   Shared by the heartbeat and the polled >STATUS reply (FW-06) - a
  *         GUI that reconnects mid-run or mid-fault and re-issues >STATUS
  *         (brief 3.5.3 rule 4) must see the same truth the heartbeat would
  *         have told it, not the older hv_armed-or-idle-only answer.
  * @retval const char* one of "fault" / "running" / "hv_armed" / "idle".
  */
static const char *proto_state_name(void)
{
  if (Safety_InFault() != 0)
  {
    return "fault";
  }
  if (s_busy != 0U)
  {
    return "running";
  }
  return (s_armed != 0U) ? "hv_armed" : "idle";
}

/**
  * @brief  Re-announce the current state as a liveness heartbeat.
  * @note   The GUI treats five seconds without traffic as link loss and shows
  *         "state unknown" (brief 3.5.3). A healthy idle instrument otherwise
  *         says nothing at all, so that rule used to fire on a perfectly good
  *         link about five seconds after the operator connected.
  *
  *         !STATE is the right carrier: the GUI already folds a repeat into the
  *         state it holds, so this costs nothing beyond the traffic it exists
  *         to provide, and it stays off the operator's log - which a periodic
  *         '#' line would have filled.
  * @retval None
  */
void Proto_EvtHeartbeat(void)
{
  proto_emit('!', "STATE %s", proto_state_name());
}

/**
  * @brief  Report the rail voltage to the GUI.
  * @note   Emitted on every change; the GUI treats >= PROTO_HV_LIVE_MV as live
  *         and must show the HV indicator from that point.
  */
void Proto_EvtHv(int32_t millivolts)
{
  s_hv_mv = millivolts;
  proto_emit('!', "HV %ld", (long)millivolts);
}

void Proto_EvtSafe(void)
{
  s_armed = 0U;
  s_hv_mv = 0;
  proto_emit('!', "SAFE");
}

void Proto_EvtTemp(int32_t deci_celsius)
{
  proto_emit('!', "TEMP %ld", (long)deci_celsius);
}

/* -------------------------------------------------------------------------- */
/* State accessors                                                            */
/* -------------------------------------------------------------------------- */

uint16_t Proto_NetlistCount(void) { return s_net_count; }
uint8_t  Proto_Busy(void)           { return s_busy; }
uint8_t  Proto_AbortRequested(void) { return s_abort; }
uint8_t  Proto_HvArmed(void)      { return s_armed; }
void     Proto_ClearArm(void)     { s_armed = 0U; }
int32_t  Proto_LimitRMaxMohm(void)   { return s_lim_r_mohm; }
int32_t  Proto_LimitInsMinMohm(void) { return s_lim_ins_mohm; }

int Proto_NetlistGet(uint16_t i, uint16_t *hi, uint16_t *lo)
{
  if (i >= s_net_count || hi == NULL || lo == NULL)
  {
    return -1;
  }
  *hi = s_net_hi[i];
  *lo = s_net_lo[i];
  return 0;
}

const char *proto_fixture_name(ProtoFixture_t fx)
{
  switch (fx)
  {
    case PROTO_FIXTURE_MTX: return "mtx";
    case PROTO_FIXTURE_HV:  return "hv";
    default:                return "none";
  }
}

/**
  * @brief  Record which fixture the harness is on, and tell the GUI.
  * @note   A fixture change INVALIDATES arming. The harness has physically
  *         moved, so whatever was armed no longer describes what is connected.
  *         Trusting the sequence instead would permit: arm on the HV fixture,
  *         declare the harness moved back to the matrix, then energise. The arm
  *         is dropped and the hardware forced safe on any change.
  */
void Proto_SetFixture(ProtoFixture_t fx)
{
  if (fx != s_fixture && (s_armed != 0U || s_hv_mv != 0))
  {
    TestCmd_t c = { CMD_FORCE_SAFE, (uint16_t)fx, CMD_SAFE_ANNOUNCE_FIXTURE,
                    0U, 0.0f };

    /* Drop the arm here - it is our own state and must not survive the call
     * even for a moment - but let the SEQUENCER announce !HV 0 / !SAFE /
     * !FIXTURE once the rail is really down. Announcing them here said "safe
     * to handle" while the hardware had not been touched yet (FW-08). */
    s_armed   = 0U;
    s_fixture = fx;

    /* Stop any run in flight. The operator is telling us the harness has moved;
     * continuing to drive the old one - at 500 V, in the insulation case - is
     * not an option, and the queued force-safe alone would not execute until
     * the run finished. Harmless when nothing is running: every run clears the
     * flag on entry. */
    s_abort = 1U;

    if (Tasks_PostCommand(&c) == 0)
    {
      return;
    }

    /* Could not queue it: we cannot claim safety we have not achieved, so latch
     * a fault - the safety task forces safe on its own 10 ms tick - and tell the
     * GUI the truth, which is "fault", not !SAFE. No F-code: the numbered faults
     * are measurement outcomes from the operation document, and this is an
     * internal one. */
    Safety_SignalFault("fixture change could not be queued");
    Proto_EvtState("fault");
    Proto_EvtFixture(fx);
    return;
  }
  s_fixture = fx;
  Proto_EvtFixture(fx);
}

void Proto_EvtFixture(ProtoFixture_t fx)
{
  proto_emit('!', "FIXTURE %s", proto_fixture_name(fx));
}

/* -------------------------------------------------------------------------- */
/* Command handling                                                           */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Split a line into whitespace-separated tokens, in place.
  * @param  line : [in,out] NUL-terminated line; separators are overwritten.
  * @param  tok  : [out]    token pointers.
  * @param  max  : [in]     capacity of @p tok.
  * @retval Token count.
  */
static uint8_t proto_split(char *line, char **tok, uint8_t max)
{
  uint8_t n = 0U;
  char *p = line;

  while (*p != '\0' && n < max)
  {
    while (*p == ' ' || *p == '\t') { *p++ = '\0'; }
    if (*p == '\0') { break; }
    tok[n++] = p;
    while (*p != '\0' && *p != ' ' && *p != '\t') { p++; }
  }
  return n;
}

/**
  * @brief  Parse a decimal integer token.
  * @param  s  : [in]  token.
  * @param  v  : [out] parsed value.
  * @retval 0 on success, non-zero if the token is not a clean integer.
  */
static int proto_int(const char *s, long *v)
{
  char *end;

  if (s == NULL || *s == '\0')
  {
    return -1;
  }
  *v = strtol(s, &end, 10);
  return (*end == '\0') ? 0 : -1;
}

/**
  * @brief  Post a command to the sequencer and reply.
  * @param  t  : [in] command type.
  * @param  a  : [in] first argument.
  * @param  b  : [in] second argument.
  * @retval None. Replies OK on success, ERR EBUSY if the queue is full.
  */
static void proto_post(TestCmdType_t t, uint16_t a, uint16_t b)
{
  TestCmd_t c = { t, a, b, 0U, 0.0f };

  if (Tasks_PostCommand(&c) == 0)
  {
    proto_emit('<', "OK started");
  }
  else
  {
    proto_err("EBUSY", "queue full");
  }
}

/**
  * @brief  Refuse a hardware command with a clean ERR EHW if Board_Init() did
  *         not fully succeed.
  * @note   A card that failed to come up (unseated, missing, or faulty)
  *         leaves its driver instance un-initialised; hv_bus_claim() and
  *         MatrixCard_BusClaim() are NULL-guarded against writing through it
  *         (see hv_card.c/matrix_card.c), so nothing crashes any more, but a
  *         RUN or SAFE that silently does nothing against dead hardware is
  *         still worse than one that says why. Checked once per command here
  *         rather than in every driver call.
  * @retval Non-zero if the caller should proceed, 0 if ERR EHW was already sent.
  */
static int proto_hw_ready(void)
{
  if (Board_IsReady() == 0U)
  {
    proto_err("EHW", "board init failed - card missing or unseated");
    return 0;
  }
  return 1;
}

/**
  * @brief  Post a whole-run command, refusing if one is already executing.
  * @note   The sequencer queue would happily accept a second run and execute it
  *         afterwards, which looks like success to the GUI and then behaves
  *         nothing like it. Refuse instead.
  * @param  t : [in] run command type.
  * @param  a : [in] first argument.
  * @retval None
  */
static void proto_post_run(TestCmdType_t t, uint16_t a)
{
  if (s_busy != 0U)
  {
    proto_err("EBUSY", "a run is already in progress");
    return;
  }
  s_abort = 0U;
  s_busy  = 1U;
  proto_post(t, a, 0U);
}

/**
  * @brief  Execute one complete command line.
  * @note   Exactly one '<' reply is emitted on every path, including errors -
  *         the GUI blocks on that reply with a 2 s timeout, so a silent path
  *         would stall it.
  * @param  line : [in,out] NUL-terminated line, without the leading '>'.
  * @retval None
  */
static void proto_exec(char *line)
{
  char *t[PROTO_MAX_TOKENS];
  uint8_t n = proto_split(line, t, PROTO_MAX_TOKENS);
  long a, b;

  if (n == 0U)
  {
    proto_err("ESYNTAX", "empty");
    return;
  }

  if (strcmp(t[0], "PING") == 0)
  {
    proto_emit('<', "PONG");
  }
  else if (strcmp(t[0], "ID") == 0)
  {
    proto_emit('<', "ID HT_MK1 fw=0.1.0 proto=1");
  }
  else if (strcmp(t[0], "STATUS") == 0)
  {
    proto_emit('<', "STATUS state=%s fixture=%s hv_mv=%ld",
               proto_state_name(),
               proto_fixture_name(s_fixture), (long)s_hv_mv);
  }
  else if (strcmp(t[0], "SAFE") == 0)
  {
    if (proto_hw_ready() != 0) { proto_post(CMD_FORCE_SAFE, 0U, 0U); }
  }
  else if (strcmp(t[0], "ABORT") == 0)
  {
    /* Cannot be queued: the sequencer holds the hardware mutex for the whole
     * run, so a queued force-safe would not execute until the run it is meant
     * to stop had already finished. Set the flag the run loops poll, and answer
     * immediately. */
    s_abort = 1U;
    s_armed = 0U;
    if (s_busy == 0U)
    {
      proto_post(CMD_FORCE_SAFE, 0U, 0U);
    }
    else
    {
      proto_emit('<', "OK");
    }
  }
  else if (strcmp(t[0], "NETLIST") == 0 && n >= 2U)
  {
    if (strcmp(t[1], "BEGIN") == 0 && n >= 3U && proto_int(t[2], &a) == 0)
    {
      if (a < 0 || a > (long)PROTO_NETLIST_MAX)
      {
        proto_err("ERANGE", "too many entries");
      }
      else
      {
        s_net_pending = (uint16_t)a;
        s_net_count   = 0U;
        s_net_loading = 1U;
        proto_emit('<', "OK");
      }
    }
    else if (strcmp(t[1], "ADD") == 0 && n >= 4U &&
             proto_int(t[2], &a) == 0 && proto_int(t[3], &b) == 0)
    {
      if (s_net_loading == 0U)
      {
        proto_err("ESYNTAX", "no BEGIN");
      }
      else if (s_net_count >= s_net_pending || s_net_count >= PROTO_NETLIST_MAX)
      {
        proto_err("ERANGE", "more entries than promised");
      }
      else if (a < 1 || a > 256 || b < 1 || b > 256)
      {
        proto_err("ERANGE", "pin out of range");
      }
      else
      {
        s_net_hi[s_net_count] = (uint16_t)a;
        s_net_lo[s_net_count] = (uint16_t)b;
        s_net_count++;
        proto_emit('<', "OK");
      }
    }
    else if (strcmp(t[1], "END") == 0)
    {
      s_net_loading = 0U;
      proto_emit('<', "OK loaded=%u", (unsigned)s_net_count);
    }
    else if (strcmp(t[1], "GET") == 0)
    {
      uint16_t i;
      proto_emit('<', "NETLIST %u", (unsigned)s_net_count);
      for (i = 0U; i < s_net_count; i++)
      {
        proto_emit('<', "NET %u %u", (unsigned)s_net_hi[i], (unsigned)s_net_lo[i]);
      }
    }
    else
    {
      proto_err("ESYNTAX", "NETLIST");
    }
  }
  else if (strcmp(t[0], "CONT") == 0 && n >= 3U && strcmp(t[1], "RUN") == 0)
  {
    if (strcmp(t[2], "verify") == 0)
    {
      if (s_net_count == 0U) { proto_err("ERANGE", "no netlist"); }
      else if (proto_hw_ready() != 0)
      {
        Proto_SetFixture(PROTO_FIXTURE_MTX); proto_post_run(CMD_CONT_RUN, 0U);
      }
    }
    else if (strcmp(t[2], "discover") == 0)
    {
      if (proto_hw_ready() != 0)
      {
        Proto_SetFixture(PROTO_FIXTURE_MTX);
        proto_post_run(CMD_CONT_RUN, 1U);
      }
    }
    else
    {
      proto_err("ESYNTAX", "verify|discover");
    }
  }
  else if (strcmp(t[0], "RES") == 0 && n >= 2U && strcmp(t[1], "RUN") == 0)
  {
    if (s_net_count == 0U) { proto_err("ERANGE", "no netlist"); }
    else if (proto_hw_ready() != 0)
    {
      Proto_SetFixture(PROTO_FIXTURE_MTX); proto_post_run(CMD_RES_RUN, 0U);
    }
  }
  else if (strcmp(t[0], "INSUL") == 0 && n >= 2U)
  {
    if (strcmp(t[1], "ARM") == 0)
    {
      /* Arming is refused unless the harness has been moved to the HV fixture.
       * The GUI enforces this too, but it must not be the only thing that does. */
      if (s_fixture != PROTO_FIXTURE_HV)
      {
        proto_err("EFIXTURE", "move harness to the HV fixture");
      }
      else
      {
        s_armed = 1U;
        proto_emit('<', "OK armed");
        Proto_EvtState("hv_armed");
      }
    }
    else if (strcmp(t[1], "RUN") == 0)
    {
      if (s_armed == 0U) { proto_err("ENOTARMED", "INSUL ARM first"); }
      else if (proto_hw_ready() != 0) { proto_post_run(CMD_INSUL_RUN, 0U); }
    }
    else
    {
      proto_err("ESYNTAX", "ARM|RUN");
    }
  }
  else if (strcmp(t[0], "HV") == 0 && n >= 3U && strcmp(t[1], "SET") == 0 &&
           proto_int(t[2], &a) == 0)
  {
    if (a != 0 && s_armed == 0U)
    {
      proto_err("ENOTARMED", "INSUL ARM first");
    }
    else if (a < 0 || a > 500000)
    {
      proto_err("ERANGE", "0..500000 mV");
    }
    else
    {
      Proto_EvtHv((int32_t)a);
      proto_emit('<', "OK");
    }
  }
  else if (strcmp(t[0], "MANUAL") == 0 && n >= 2U)
  {
    if (strcmp(t[1], "PATH") == 0 && n >= 4U &&
        proto_int(t[2], &a) == 0 && proto_int(t[3], &b) == 0)
    {
      if (a < 1 || a > 256 || b < 1 || b > 256) { proto_err("ERANGE", "pin"); }
      else { proto_post(CMD_CONTINUITY, (uint16_t)a, (uint16_t)b); }
    }
    else if (strcmp(t[1], "OFF") == 0)
    {
      proto_post(CMD_FORCE_SAFE, 0U, 0U);
    }
    else if (strcmp(t[1], "RELAY") == 0)
    {
      /* Deliberately refused: driving a single HV relay by hand while the rail
       * may be live is not something the instrument should allow over a serial
       * link. Raised as an open question in the GUI brief section 8. */
      proto_err("EHW", "manual relay not permitted");
    }
    else
    {
      proto_err("ESYNTAX", "MANUAL");
    }
  }
  else if (strcmp(t[0], "FAULT") == 0 && n >= 2U && strcmp(t[1], "CLEAR") == 0)
  {
    /* Recovery from a latched fault. Forces safe first, so clearing the latch
     * can never be a way to re-energise something by accident. */
    proto_post(CMD_CLEAR_FAULT, 0U, 0U);
  }
  else if (strcmp(t[0], "CAL") == 0 && n >= 2U && strcmp(t[1], "GET") == 0)
  {
    proto_emit('<', "CAL current_ua=3000 gain=32 rref_mohm=100000");
  }
  else if (strcmp(t[0], "LIMITS") == 0 && n >= 2U)
  {
    if (strcmp(t[1], "GET") == 0)
    {
      proto_emit('<', "LIMITS r_max_mohm=%ld ins_min_mohm=%ld",
                 (long)s_lim_r_mohm, (long)s_lim_ins_mohm);
    }
    else if (strcmp(t[1], "SET") == 0)
    {
      uint8_t i;
      for (i = 2U; i < n; i++)
      {
        if (strncmp(t[i], "r_max_mohm=", 11U) == 0 &&
            proto_int(&t[i][11], &a) == 0) { s_lim_r_mohm = (int32_t)a; }
        else if (strncmp(t[i], "ins_min_mohm=", 13U) == 0 &&
                 proto_int(&t[i][13], &a) == 0) { s_lim_ins_mohm = (int32_t)a; }
      }
      proto_emit('<', "OK");
    }
    else
    {
      proto_err("ESYNTAX", "LIMITS");
    }
  }
  else if (strcmp(t[0], "TEMP") == 0 && n >= 2U && strcmp(t[1], "READ") == 0)
  {
    /* Routed through the sequencer, not answered inline - a real conversion
     * blocks for a little over 750 ms (see CMD_TEMP_READ in tasks.h) and
     * doing that here would stall every other command's reply for as long.
     * Result arrives as a !TEMP event, same "<OK started then an event"
     * shape as MANUAL PATH. */
    if (proto_hw_ready() != 0) { proto_post(CMD_TEMP_READ, 0U, 0U); }
  }
  else if (strcmp(t[0], "FIXTURE") == 0 && n >= 2U)
  {
    /* Operator confirmation that the harness has been physically moved. */
    if      (strcmp(t[1], "mtx") == 0)  { Proto_SetFixture(PROTO_FIXTURE_MTX);  proto_emit('<', "OK"); }
    else if (strcmp(t[1], "hv") == 0)   { Proto_SetFixture(PROTO_FIXTURE_HV);   proto_emit('<', "OK"); }
    else if (strcmp(t[1], "none") == 0) { Proto_SetFixture(PROTO_FIXTURE_NONE); proto_emit('<', "OK"); }
    else { proto_err("ESYNTAX", "none|mtx|hv"); }
  }
  else
  {
    proto_err("ESYNTAX", "unknown command");
  }
}

/* -------------------------------------------------------------------------- */

void Proto_Init(UART_HandleTypeDef *huart)
{
  s_uart        = huart;
  s_rx_len      = 0U;
  s_overflow    = 0U;
  s_net_count   = 0U;
  s_net_pending = 0U;
  s_net_loading = 0U;
  s_fixture     = PROTO_FIXTURE_NONE;
  s_armed       = 0U;
  s_hv_mv       = 0;
  s_busy        = 0U;
  s_abort       = 0U;
}

/**
  * @brief  Feed one received byte to the line assembler.
  * @note   A line longer than PROTO_RX_MAX is discarded up to the next
  *         terminator and answered once with ERR ESYNTAX, so a garbled or
  *         desynchronised sender cannot leave the parser wedged.
  * @param  ch : [in] received byte.
  * @retval None
  */
void Proto_RxByte(uint8_t ch)
{
  if (ch == '\r')
  {
    return;                       /* tolerate CRLF from terminals */
  }

  if (ch != '\n')
  {
    if (s_rx_len < PROTO_RX_MAX)
    {
      s_rx[s_rx_len++] = (char)ch;
    }
    else
    {
      s_overflow = 1U;
    }
    return;
  }

  s_rx[s_rx_len] = '\0';

  if (s_overflow != 0U)
  {
    proto_err("ESYNTAX", "line too long");
  }
  else if (s_rx_len > 0U)
  {
    /* The leading '>' is optional so the link can be driven by hand from a
     * plain terminal during bring-up. */
    proto_exec((s_rx[0] == '>') ? &s_rx[1] : &s_rx[0]);
  }

  s_rx_len   = 0U;
  s_overflow = 0U;
}
