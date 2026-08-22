/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    tasks.h
  * @brief   FreeRTOS task architecture for the harness tester.
  *
  *          Tasks (priority high -> low):
  *            tSafety    - supervises the HV domain; forces a safe state on any
  *                         fault; backstops HV-disable when no test is running.
  *            tSequencer - executes test commands (continuity/kelvin/insulation)
  *                         one at a time under the hardware mutex.
  *            tComms     - reads single-char commands from the VCP (Nucleo
  *                         bring-up console) and posts them to the sequencer.
  *            tLogger    - drains the log queue to the UART (lowest priority).
  *
  *          A single hardware mutex serialises all shared-bus (I2C/SPI) access
  *          between the sequencer and the safety task.
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __TASKS_H
#define __TASKS_H

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"

typedef enum
{
  CMD_NONE        = 0,
  CMD_CONTINUITY  = 1,   /* a=hi pin, b=lo pin                       */
  CMD_KELVIN      = 2,   /* a=hi pin, b=lo pin                       */
  CMD_INSULATION  = 3,   /* board, a=inject, b=return, vfrac         */
  CMD_FORCE_SAFE  = 4,   /* drop everything to safe; b=1 also announces
                          * the new fixture carried in a (see below)  */
  /* Whole-run commands driven by the GUI protocol. These iterate the netlist
   * (or the full 256x256 grid for discovery) and stream '!' events as they go,
   * rather than returning a single result. */
  CMD_CONT_RUN    = 5,   /* a=0 verify against netlist, a=1 discover  */
  CMD_RES_RUN     = 6,
  CMD_INSUL_RUN   = 7,
  /* Forces safe, then clears the fault latch. Handled BEFORE the sequencer's
   * fault gate - it is the only recovery from a latched fault short of a power
   * cycle, so it has to run while faulted. */
  CMD_CLEAR_FAULT = 8,
  /* Reads the Control Card's DS18B20 (U2, PA0 - see HW-13/FW-14). Diagnostic
   * only, no netlist/fixture involved. Routed through the sequencer rather
   * than answered inline in proto.c because a real conversion blocks for a
   * little over 750 ms - doing that in tComms would stall the protocol
   * parser (and every other command's reply) for most of a second. */
  CMD_TEMP_READ   = 9,
  /* One HS pin against all 256 LS - a bounded CMD_CONT_RUN discover=1, for
   * probing a single suspect line without a full 65,536-point scan
   * (GUI-06, 2026-08-21). a=hi pin. Whole-run gating (s_busy/EBUSY) applies,
   * same as the CMD_*_RUN family above. */
  CMD_MANUAL_SWEEP = 10,
  /* Probes every I2C device this project has a confirmed address for
   * (Board_ScanBus, board.c) plus the ADS124S08. Routed through the
   * sequencer, not answered inline in proto.c, for the same reason
   * CMD_TEMP_READ is: it touches the shared hardware mutex/bus state the
   * sequencer already serialises everything else through (GUI-06,
   * 2026-08-21). */
  CMD_BUS_SCAN     = 11
} TestCmdType_t;

/* CMD_FORCE_SAFE.b: ask the sequencer to emit !FIXTURE (value in .a) after the
 * hardware is safe. A fixture change that invalidates arming must not announce
 * itself before the rail is actually down - see Proto_SetFixture(). */
#define CMD_SAFE_ANNOUNCE_FIXTURE  1U

typedef struct
{
  TestCmdType_t type;
  uint16_t      a;
  uint16_t      b;
  uint8_t       board;
  float         vfrac;
} TestCmd_t;

/**
  * @brief  Create queues/mutex, bring up the log UART, and start all tasks.
  *         Call from MX_FREERTOS_Init (kernel initialised, not yet started).
  */
void Tasks_Init(void);

/**
  * @brief  Post a test command to the sequencer. Non-blocking.
  * @retval 0 on success, non-zero if the queue was full.
  */
int Tasks_PostCommand(const TestCmd_t *cmd);

/**
  * @brief  Raise a system fault; the safety task forces a safe state.
  */
void Safety_SignalFault(const char *reason);

/**
  * @brief  Clear the fault latch (after the cause is handled).
  */
void Safety_ClearFault(void);

/**
  * @brief  1 while a fault is latched.
  */
int Safety_InFault(void);

#ifdef __cplusplus
}
#endif

#endif /* __TASKS_H */
