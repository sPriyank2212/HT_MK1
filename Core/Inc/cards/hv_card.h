/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    hv_card.h
  * @brief   HV Card control: one self-contained 500 V insulation-test channel
  *          covering 64 harness pins per side. Up to 4 boards instantiate this.
  *
  *          Per board (per HV_Card.kicad_sch):
  *            - 8x MCP23017 (isolated I2C): 4 drive the 64 inject-relay gates
  *              (H_CONT1..64), 4 drive the 64 return-relay gates (L_CONT1..64).
  *              Relays use 2N7002 gate drivers -> ACTIVE-HIGH, so MCP23017_Init's
  *              all-low default already means "all relays open" (safe).
  *            - DAC8830 (isolated SPI) -> sets the 0..500 V program voltage.
  *            - AD7476 (isolated SPI)  -> reads HV_Sense.
  *            - HV-enable + discharge GPIO lines (isolated).
  *
  *          OPEN POINT (see fw_status.txt): the leakage-CURRENT sense path is
  *          unconfirmed - ReadSense reads the HV_Sense node only. The leakage
  *          -> insulation-resistance maths is stubbed in the insulation test
  *          until the measurement chain is confirmed.
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __HV_CARD_H
#define __HV_CARD_H

#ifdef __cplusplus
extern "C" {
#endif

#include "drivers/mcp23017.h"
#include "drivers/dac8830.h"
#include "drivers/ad7476.h"

#define HV_PINS_PER_SIDE      64U
#define HV_MCP_PER_SIDE       4U    /* 4 expanders x 16 = 64 relay gates */

/* HV enable / discharge active level. VERIFY against the isolated driver. */
#ifndef HV_ENABLE_ACTIVE
#define HV_ENABLE_ACTIVE      GPIO_PIN_SET
#endif
#ifndef HV_DISCHARGE_ACTIVE
#define HV_DISCHARGE_ACTIVE   GPIO_PIN_SET
#endif

typedef struct
{
  I2C_HandleTypeDef *i2c;                 /* isolated I2C bus for this board   */
  uint8_t            inject_strap[HV_MCP_PER_SIDE]; /* A2:A0 of 4 inject MCPs  */
  uint8_t            return_strap[HV_MCP_PER_SIDE]; /* A2:A0 of 4 return MCPs  */

  SPI_HandleTypeDef *spi;                 /* isolated SPI bus (DAC + ADC)      */
  GPIO_TypeDef      *dac_cs_port;  uint16_t dac_cs_pin;
  GPIO_TypeDef      *adc_cs_port;  uint16_t adc_cs_pin;

  GPIO_TypeDef      *hv_en_port;   uint16_t hv_en_pin;
  GPIO_TypeDef      *dischg_port;  uint16_t dischg_pin;

  float              vref;                /* ADC reference, volts              */
} HvCardCfg_t;

typedef struct
{
  MCP23017_t  inject[HV_MCP_PER_SIDE];
  MCP23017_t  ret[HV_MCP_PER_SIDE];
  DAC8830_t   dac;
  AD7476_t    adc;
  HvCardCfg_t cfg;
} HvCard_t;

/**
  * @brief  Init all 8 expanders (relays open), DAC (0 V), ADC, and force a safe
  *         state: HV disabled, all relays open.
  */
HAL_StatusTypeDef HvCard_Init(HvCard_t *hv, const HvCardCfg_t *cfg);

/* Relay control (pin = 1..64). Each Close opens the whole side first so exactly
 * one relay on that side is ever closed. */
HAL_StatusTypeDef HvCard_OpenAllRelays(HvCard_t *hv);
HAL_StatusTypeDef HvCard_CloseInject(HvCard_t *hv, uint8_t pin);
HAL_StatusTypeDef HvCard_CloseReturn(HvCard_t *hv, uint8_t pin);
HAL_StatusTypeDef HvCard_ConnectPair(HvCard_t *hv, uint8_t inject_pin, uint8_t return_pin);

/* HV stimulus */
HAL_StatusTypeDef HvCard_SetVoltageCode(HvCard_t *hv, uint16_t code);
HAL_StatusTypeDef HvCard_SetVoltageFraction(HvCard_t *hv, float fraction);
HAL_StatusTypeDef HvCard_HvEnable(HvCard_t *hv, uint8_t on);
HAL_StatusTypeDef HvCard_Discharge(HvCard_t *hv, uint8_t on);

/* Measurement (HV_Sense node) */
HAL_StatusTypeDef HvCard_ReadSenseRaw(HvCard_t *hv, uint16_t *code);
HAL_StatusTypeDef HvCard_ReadSenseVolts(HvCard_t *hv, float *volts);

#ifdef __cplusplus
}
#endif

#endif /* __HV_CARD_H */