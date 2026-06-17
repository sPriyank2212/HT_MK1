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
  CMD_FORCE_SAFE  = 4    /* drop everything to safe                  */
} TestCmdType_t;

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
