/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    harness_test.h
  * @brief   Shared types for the three test modes (continuity / kelvin /
  *          insulation). The orchestration modules drive the card layers via
  *          the global instances in bsp/board.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __HARNESS_TEST_H
#define __HARNESS_TEST_H

#ifdef __cplusplus
extern "C" {
#endif

#include "bsp/board.h"

typedef enum
{
  TEST_PASS  = 0,
  TEST_FAIL  = 1,
  TEST_OPEN  = 2,   /* expected connection missing            */
  TEST_SHORT = 3,   /* unexpected connection present          */
  TEST_ERROR = 4    /* bus / driver error during the test     */
} TestVerdict_t;

#ifdef __cplusplus
}
#endif

#endif /* __HARNESS_TEST_H */