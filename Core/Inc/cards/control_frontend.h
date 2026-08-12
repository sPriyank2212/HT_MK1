/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    control_frontend.h
  * @brief   Control-Card analogue front end: the shared measurement path used
  *          by the continuity and Kelvin tests.
  *
  *          Elements (per Control_Card.kicad_sch):
  *            - TS5A3159 SPDT -> OPT0_CNTR selects the front end between
  *              impedance mode (I_OUT, isolates ADC_IN's pull-up from HI_COM)
  *              and the +3V3 continuity divider
  *            - AD7476 ADC    -> digitises the resulting node voltage (ADC_IN)
  *
  *          FW-12 (2026-08-12): the DAC8775 that used to force the Kelvin
  *          current through I_OUT is gone from the schematic - excitation now
  *          comes from the ADS124S08's own IDAC on the Matrix Card (see
  *          Doc/idac_current_source.md, test/kelvin.c). This layer no longer
  *          drives any current; FRONTEND_MODE_IMPEDANCE still means something
  *          real, though - the continuity divider's 10 k pull-up on ADC_IN
  *          would otherwise load HI_COM in parallel with the IDAC's 2 mA, so
  *          Kelvin still swings the SPDT to isolate it before exciting.
  *
  *          This layer hides the remaining two parts behind a small API; the
  *          test modules call SetMode / Read.
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __CONTROL_FRONTEND_H
#define __CONTROL_FRONTEND_H

#ifdef __cplusplus
extern "C" {
#endif

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
  AD7476_t        adc;           /* front-end ADC                    */
  GPIO_TypeDef   *opto_port;     /* OPT0_CNTR (must be a GPIO OUTPUT) */
  uint16_t        opto_pin;
  float           vref;          /* ADC reference, volts             */
  FrontendMode_t  mode;
} ControlFrontend_t;

typedef struct
{
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
  * @brief  Read the front-end node: raw 12-bit code / volts.
  */
HAL_StatusTypeDef Frontend_ReadRaw(ControlFrontend_t *fe, uint16_t *code);
HAL_StatusTypeDef Frontend_ReadVolts(ControlFrontend_t *fe, float *volts);

#ifdef __cplusplus
}
#endif

#endif /* __CONTROL_FRONTEND_H */