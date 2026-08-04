/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    proto.h
  * @brief   Instrument side of the GUI protocol.
  *
  *          Line-based ASCII over the console UART at 115200 8N1. The contract
  *          is specified in Doc/GUI_development_brief.md section 3 and the GUI
  *          is being built against it independently - DO NOT change the wire
  *          format here without agreeing it there first, or the two halves stop
  *          meeting.
  *
  *            >  GUI -> instrument   command
  *            <  instrument -> GUI   reply, exactly one per command, in order
  *            !  instrument -> GUI   asynchronous event
  *            #  instrument -> GUI   human-readable log, display but do not parse
  *
  *          Replaces the single-keystroke bring-up console (c/k/i/s/f/r).
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __PROTO_H
#define __PROTO_H

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"

/* Longest accepted command line, excluding the terminator. Anything longer is
 * discarded to the next newline and answered with ERR ESYNTAX. */
#ifndef PROTO_RX_MAX
#define PROTO_RX_MAX        72U
#endif

/* Netlist capacity. One entry per expected harness connection. */
#ifndef PROTO_NETLIST_MAX
#define PROTO_NETLIST_MAX   256U
#endif

/* Rail voltage at or above which the GUI must treat HV as live (millivolts).
 * Mirrors the 50 V threshold in the brief section 3.5. */
#define PROTO_HV_LIVE_MV    50000

typedef enum
{
  PROTO_FIXTURE_NONE = 0,
  PROTO_FIXTURE_MTX,
  PROTO_FIXTURE_HV
} ProtoFixture_t;

/**
  * @brief  Bind the console UART and reset protocol state.
  * @param  huart : [in] console UART; may be NULL, in which case every emit is
  *                      a no-op so the rest of the system still runs.
  * @retval None
  */
void Proto_Init(UART_HandleTypeDef *huart);

/**
  * @brief  Feed one received byte to the line assembler.
  * @note   Executes the command inline once a terminator arrives, so call it
  *         from a task, not an ISR.
  * @param  ch : [in] received byte.
  * @retval None
  */
void Proto_RxByte(uint8_t ch);

/* -------------------------------------------------------------------------- */
/* Event emitters - called by the sequencer as a run progresses                */
/* -------------------------------------------------------------------------- */

void Proto_EvtProgress(uint16_t done, uint16_t total);
void Proto_EvtCont(uint16_t hi, uint16_t lo, const char *verdict);
void Proto_EvtRes(uint16_t hi, uint16_t lo, int32_t milliohms, const char *verdict);
void Proto_EvtInsul(uint16_t net, int32_t leak_mohm, const char *verdict);
void Proto_EvtFault(const char *code, const char *text);
void Proto_EvtDone(const char *what, uint16_t passed, uint16_t failed);
void Proto_EvtState(const char *state);
void Proto_EvtFixture(ProtoFixture_t fx);
void Proto_EvtHv(int32_t millivolts);
void Proto_EvtSafe(void);

/* -------------------------------------------------------------------------- */
/* State shared with the sequencer                                            */
/* -------------------------------------------------------------------------- */

/**
  * @brief  Number of netlist entries currently loaded.
  */
uint16_t Proto_NetlistCount(void);

/**
  * @brief  Fetch one netlist entry.
  * @param  i  : [in]  index, 0 .. Proto_NetlistCount()-1.
  * @param  hi : [out] high-side pin.
  * @param  lo : [out] low-side pin.
  * @retval 0 on success, non-zero if @p i is out of range or a pointer is NULL.
  */
int Proto_NetlistGet(uint16_t i, uint16_t *hi, uint16_t *lo);

/**
  * @brief  Record the fixture the instrument expects, and tell the GUI.
  * @note   Insulation is refused unless this is PROTO_FIXTURE_HV - the harness
  *         has to be physically moved, and the GUI cannot be the only thing
  *         enforcing that.
  */
void Proto_SetFixture(ProtoFixture_t fx);

/**
  * @brief  Whether the operator has armed HV via >INSUL ARM.
  * @retval Non-zero when armed.
  */
uint8_t Proto_HvArmed(void);

/**
  * @brief  Clear the armed flag. Called on abort, fault, or run completion so
  *         arming never persists across runs.
  */
void Proto_ClearArm(void);

/**
  * @brief  Whether a whole-run command is in progress.
  * @retval Non-zero while a run is executing. Run-starting commands are refused
  *         with ERR EBUSY in that state; PING/ID/STATUS/SAFE/ABORT always work.
  */
uint8_t Proto_Busy(void);

/**
  * @brief  Whether the operator has asked for the current run to stop.
  * @note   ABORT cannot be queued behind a running test - the sequencer holds
  *         the hardware mutex for the whole run - so it sets a flag that the
  *         run loops poll between points instead.
  */
uint8_t Proto_AbortRequested(void);

/**
  * @brief  Clear the abort flag. Called at the start of every run.
  */
void Proto_ClearAbort(void);

/**
  * @brief  Configured resistance limit, milliohms.
  */
int32_t Proto_LimitRMaxMohm(void);

/**
  * @brief  Configured insulation limit, milliohms.
  */
int32_t Proto_LimitInsMinMohm(void);

#ifdef __cplusplus
}
#endif

#endif /* __PROTO_H */
