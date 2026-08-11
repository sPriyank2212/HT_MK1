/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    hv_card.h
  * @brief   HV Card control: one self-contained 500 V insulation-test channel
  *          covering 64 harness pins per side. Up to 4 boards instantiate this.
  *
  *          Per board (per HV_Card.kicad_sch, Doc/ folder = source of truth):
  *            - 8x MCP23017 (isolated I2C): 4 drive the 64 inject-relay gates
  *              (H_CONT1..64), 4 drive the 64 return-relay gates (L_CONT1..64).
  *              Relays use 2N7002 gate drivers -> ACTIVE-HIGH, so MCP23017_Init's
  *              all-low default already means "all relays open" (safe).
  *            - DAC8830 (isolated SPI) -> sets the 0..500 V program voltage
  *              (V_PGM) into the CA05P-5. There is NO separate HV-enable line:
  *              the CA05P-5 VIN is tied to +5V_ISO, so HV output simply follows
  *              this DAC. HV OFF == program the DAC to 0. There is also NO active
  *              discharge relay - the bus bleeds passively through the sense
  *              divider (~11 Mohm).
  *            - TWO AD7476 (isolated SPI, vref = +5V_ISO = 5.0 V):
  *                * RAIL  (U301) reads HV_Sense  ~0.25 V @ 500 V  (rail monitor)
  *                * LEAK  (U302) reads HV_RET    ~0.045 V @ short (insulation)
  *              Each ADC has its own soft-CS: these are the two per-board control
  *              lines the MCU brings to the card (HV_Card_x.0 -> LEAK CS,
  *              HV_Card_x.1 -> RAIL CS). They are ADC chip-selects, NOT HV
  *              enable/discharge.
  *
  *          BUS SHARING: the Matrix Card and every HV card slot sit on the same
  *          I2C bus (isolated I2C2, per the Control Card schematic), and every
  *          card - Matrix included - hard-straps its expanders to the same
  *          0x20..0x27 range. Nothing on the wire tells two cards apart except
  *          one isolated enable line per HV slot (HV_Card_EN1..4, Control_Card-5
  *          sheet /Isolator/ + /uC/), which this driver must assert before, and
  *          deassert after, every I2C transaction so at most one card answers on
  *          the bus at a time. See Doc/i2c_bus_sharing.md.
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

typedef struct
{
  I2C_HandleTypeDef *i2c;                 /* isolated I2C bus for this board    */
  uint8_t            inject_strap[HV_MCP_PER_SIDE]; /* A2:A0 of 4 inject MCPs   */
  uint8_t            return_strap[HV_MCP_PER_SIDE]; /* A2:A0 of 4 return MCPs   */

  /* This slot's segment enable on the shared I2C bus (HV_CARD_EN1..4 - a plain
   * MCU GPIO on the non-isolated side, buffered across the isolation boundary).
   * Must be non-NULL: without it every relay-expander access on this board
   * risks colliding with the Matrix Card or another HV board on the same bus. */
  GPIO_TypeDef      *en_port;          uint16_t en_pin;

  SPI_HandleTypeDef *spi;                 /* isolated SPI bus (DAC8830 + ADCs)  */
  GPIO_TypeDef      *dac_cs_port;      uint16_t dac_cs_pin;   /* DAC8830 CS      */
  GPIO_TypeDef      *adc_rail_cs_port; uint16_t adc_rail_cs_pin; /* U301 HV_Sense */
  GPIO_TypeDef      *adc_leak_cs_port; uint16_t adc_leak_cs_pin; /* U302 HV_RET   */

  float              vref;                /* ADC reference, volts (5.0 on HV)   */
} HvCardCfg_t;

typedef struct
{
  MCP23017_t  inject[HV_MCP_PER_SIDE];
  MCP23017_t  ret[HV_MCP_PER_SIDE];
  DAC8830_t   dac;
  AD7476_t    adc_rail;      /* HV_Sense  - rail monitor          */
  AD7476_t    adc_leak;      /* HV_RET    - leakage / insulation  */
  HvCardCfg_t cfg;
} HvCard_t;

/**
  * @brief  Init all 8 expanders (relays open), DAC (0 V), both ADCs, and force a
  *         safe state: HV programmed to 0 V, all relays open.
  */
HAL_StatusTypeDef HvCard_Init(HvCard_t *hv, const HvCardCfg_t *cfg);

/* Relay control (pin = 1..64). Each Close opens the whole side first so exactly
 * one relay on that side is ever closed. */
HAL_StatusTypeDef HvCard_OpenAllRelays(HvCard_t *hv);
HAL_StatusTypeDef HvCard_CloseInject(HvCard_t *hv, uint8_t pin);
HAL_StatusTypeDef HvCard_CloseReturn(HvCard_t *hv, uint8_t pin);
HAL_StatusTypeDef HvCard_ConnectPair(HvCard_t *hv, uint8_t inject_pin, uint8_t return_pin);

/* HV stimulus. Programming the DAC IS the HV control: a non-zero code raises the
 * CA05P-5 output; code 0 turns HV off. */
HAL_StatusTypeDef HvCard_SetVoltageCode(HvCard_t *hv, uint16_t code);
HAL_StatusTypeDef HvCard_SetVoltageFraction(HvCard_t *hv, float fraction);
HAL_StatusTypeDef HvCard_HvOff(HvCard_t *hv);                 /* DAC -> 0 V      */

/* Back-compat shims (no dedicated HV-enable / discharge hardware exists):
 *   HvEnable(0)  -> HvOff() ; HvEnable(1) -> no-op (level set via SetVoltage).
 *   Discharge()  -> no-op   ; the bus bleeds passively through the divider.
 * Callers should keep any post-off settle delay to allow that passive bleed. */
HAL_StatusTypeDef HvCard_HvEnable(HvCard_t *hv, uint8_t on);
HAL_StatusTypeDef HvCard_Discharge(HvCard_t *hv, uint8_t on);

/* Measurement. RAIL = HV_Sense (rail present?), LEAK = HV_RET (insulation). */
HAL_StatusTypeDef HvCard_ReadRailRaw(HvCard_t *hv, uint16_t *code);
HAL_StatusTypeDef HvCard_ReadRailVolts(HvCard_t *hv, float *volts);
HAL_StatusTypeDef HvCard_ReadLeakageRaw(HvCard_t *hv, uint16_t *code);
HAL_StatusTypeDef HvCard_ReadLeakageVolts(HvCard_t *hv, float *volts);

#ifdef __cplusplus
}
#endif

#endif /* __HV_CARD_H */
