/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    control_frontend.h
  * @brief   Control-Card analogue front end: the shared measurement path used
  *          by the continuity and Kelvin tests.
  *
  *          Elements (per Control_Card.kicad_sch):
  *            - DAC8775 IDAC  -> forces the Kelvin test current (I_OUT)
  *            - TS5A3159 SPDT -> OPT0_CNTR selects the front end between the
  *              current source (impedance mode) and the +3V3 continuity divider
  *            - AD7476 ADC    -> digitises the resulting node voltage (ADC_IN)
  *
  *          This layer hides the three parts behind a small API; the test
  *          modules call SetMode / SetCurrent / Read.
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __CONTROL_FRONTEND_H
#define __CONTROL_FRONTEND_H

#ifdef __cplusplus
extern "C" {
#endif

#include "drivers/dac8775.h"
#include "drivers/ad7476.h"

/* OPT0_CNTR logic level per mode. VERIFY against the TS5A3159 wiring (which
 * throw is NO vs NC). Flip these two if continuity/impedance come out swapped. */
#ifndef FRONTEND_OPTO_LEVEL_CONTINUITY
#define FRONTEND_OPTO_LEVEL_CONTINUITY   GPIO_PIN_RESET
#endif
#ifndef FRONTEND_OPTO_LEVEL_IMPEDANCE
#define FRONTEND_OPTO_LEVEL_IMPEDANCE    GPIO_PIN_SET
#endif

typedef enum
{
  FRONTEND_MODE_CONTINUITY = 0,  /* +3V3 divider -> ADC                       */
  FRONTEND_MODE_IMPEDANCE  = 1   /* IDAC current source -> wire under test     */
} FrontendMode_t;

typedef struct
{
  DAC8775_t       idac;          /* Kelvin current source            */
  AD7476_t        adc;           /* front-end ADC                    */
  GPIO_TypeDef   *opto_port;     /* OPT0_CNTR (must be a GPIO OUTPUT) */
  uint16_t        opto_pin;
  float           vref;          /* ADC reference, volts             */
  FrontendMode_t  mode;
} ControlFrontend_t;

typedef struct
{
  SPI_HandleTypeDef *idac_spi;   /* SPI2 */
  GPIO_TypeDef      *idac_cs_port;
  uint16_t           idac_cs_pin;
  SPI_HandleTypeDef *adc_spi;    /* SPI1 */
  GPIO_TypeDef      *adc_cs_port;
  uint16_t           adc_cs_pin;
  GPIO_TypeDef      *opto_port;  /* OPT0_CNTR */
  uint16_t           opto_pin;
  float              vref;
} ControlFrontendCfg_t;

HAL_StatusTypeDef Frontend_Init(ControlFrontend_t *fe, const ControlFrontendCfg_t *cfg);

/**
  * @brief  Select continuity or impedance signal path (drives OPT0_CNTR).
  */
HAL_StatusTypeDef Frontend_SetMode(ControlFrontend_t *fe, FrontendMode_t mode);

/**
  * @brief  Set the Kelvin force current (raw IDAC code; channel A).
  */
HAL_StatusTypeDef Frontend_SetCurrentCode(ControlFrontend_t *fe, uint16_t code);

/**
  * @brief  Read the front-end node: raw 12-bit code / volts.
  */
HAL_StatusTypeDef Frontend_ReadRaw(ControlFrontend_t *fe, uint16_t *code);
HAL_StatusTypeDef Frontend_ReadVolts(ControlFrontend_t *fe, float *volts);

#ifdef __cplusplus
}
#endif

#endif /* __CONTROL_FRONTEND_H */