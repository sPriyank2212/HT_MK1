/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    board.h
  * @brief   Board support: binds the driver/card layers to the concrete HAL
  *          handles and pins, and exposes the global instances the test modules
  *          use. This is the single place where the still-open hardware points
  *          land - all such bindings are marked TODO/VERIFY here.
  *
  *          Bus/pin bindings below are best-guess placeholders pending:
  *            - Control-Card <-> Matrix connector (matrix select GPIOs)
  *            - Which I2C bus serves Matrix vs each HV board
  *            - CS pin assignments for SPI1 (ADC) and SPI2 (IDAC) - not yet in
  *              the generated GPIO config
  *            - OPT0_CNTR / HV_CARD_DT_x set to OUTPUT in CubeMX (now INPUT)
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __BOARD_H
#define __BOARD_H

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"
#include "i2c.h"
#include "spi.h"
#include "cards/matrix_card.h"
#include "cards/control_frontend.h"
#include "cards/hv_card.h"

/* Number of HV boards fitted in this build (1..4). TODO: confirm. */
#ifndef BOARD_HV_COUNT
#define BOARD_HV_COUNT        1
#endif

/* ADC reference voltage (precision Vref on the Control Card). TODO: confirm. */
#ifndef BOARD_VREF
#define BOARD_VREF            3.0f
#endif

/* Global instances (defined in board.c). */
extern MatrixCard_t      g_matrix;
extern ControlFrontend_t g_frontend;
extern HvCard_t          g_hv[BOARD_HV_COUNT];

/**
  * @brief  Initialise every card/driver to a safe idle state.
  * @retval HAL_OK only if all sub-inits succeed.
  */
HAL_StatusTypeDef Board_Init(void);

#ifdef __cplusplus
}
#endif

#endif /* __BOARD_H */