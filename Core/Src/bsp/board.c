/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    board.c
  * @brief   Board support implementation: instantiate and bind everything.
  *          PLACEHOLDER bindings are marked TODO - see board.h header and
  *          fw_status.txt. Compiles and brings all layers to a safe idle state.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "bsp/board.h"

MatrixCard_t      g_matrix;
ControlFrontend_t g_frontend;
HvCard_t          g_hv[BOARD_HV_COUNT];

/* ---------------------------------------------------------------------------
 * Bus assignment - corrected against the Doc/ schematics (2026-07):
 *   SPI1 = Matrix-Card AD7476 (U33, HI_COM)      [not bound here yet]
 *   SPI2 = DAC8775 (Kelvin) + HV-card AD7476s + DAC8830, all isolated (shared)
 *   SPI3 = Control-Card AD7476 (U4, ADC_IN off the Opto SPDT)
 * TODO(CubeMX): SPI2 carries 8-bit (DAC8775) and 16-bit (DAC8830/AD7476)
 *   devices - data size must be set per transaction, or run 8-bit with the
 *   drivers doing byte framing. See fw_status CONFIG TODO.
 * ------------------------------------------------------------------------- */
#define BOARD_MATRIX_I2C      (&hi2c3)   /* TODO: confirm matrix vs HV I2C bus */
#define BOARD_HV_I2C          (&hi2c2)   /* TODO: per-board bus when >1 board  */
#define BOARD_IDAC_SPI        (&hspi2)   /* DAC8775 (Kelvin)                   */
#define BOARD_ADC_SPI         (&hspi3)   /* AD7476 (Control front end, U4)     */
#define BOARD_HV_SPI          (&hspi2)   /* HV DAC8830 + both AD7476 (isolated)*/
#define BOARD_MATRIX_ADC_SPI  (&hspi1)   /* AD7476 (Matrix U33, HI_COM)        */
/* Matrix ADC CS = SPI1_CS (PB0). TODO(CubeMX): assign PB0 as a GPIO output. */
#define BOARD_MATRIX_ADC_CS_PORT  GPIOB
#define BOARD_MATRIX_ADC_CS_PIN   GPIO_PIN_0

/* ---------------------------------------------------------------------------
 * CS / control pins. Confirmed where the schematic is unambiguous; the isolated
 * HV DAC CS is still a placeholder pending the connector netlist (VERIFY).
 * ------------------------------------------------------------------------- */
#define BOARD_ADC_CS_PORT     SPI3_CS_GPIO_Port   /* PB1 - Control ADC (U4)     */
#define BOARD_ADC_CS_PIN      SPI3_CS_Pin
#define BOARD_IDAC_CS_PORT    SPI3_CSB2_GPIO_Port /* PB2 = physical SPI2_CS     */
#define BOARD_IDAC_CS_PIN     SPI3_CSB2_Pin
#define BOARD_HV_DAC_CS_PORT  I2C2_CS_GPIO_Port   /* PC2 placeholder (CS_ISO); VERIFY */
#define BOARD_HV_DAC_CS_PIN   I2C2_CS_Pin

/* HV-card ADC chip-selects = the two per-board control lines (isolated).
 *   HV_Card_x.1 -> RAIL ADC (U301 HV_Sense) ; HV_Card_x.0 -> LEAK ADC (U302 HV_RET).
 * TODO: set these to OUTPUT in CubeMX (currently INPUT) and extend per board. */
#define BOARD_HV0_ADC_RAIL_CS_PORT  HV_CARD_DT_1_1_GPIO_Port  /* PC14 */
#define BOARD_HV0_ADC_RAIL_CS_PIN   HV_CARD_DT_1_1_Pin
#define BOARD_HV0_ADC_LEAK_CS_PORT  HV_CARD_DT_1_0_GPIO_Port  /* PC13 */
#define BOARD_HV0_ADC_LEAK_CS_PIN   HV_CARD_DT_1_0_Pin

/**
  * @brief  Instantiate and bind the Matrix card (enable expanders + on-card ADC).
  * @note   The Control<->Matrix select-line connector is not yet drawn, so the
  *         select GPIOs are left NULL (the layer is inert on the select lines).
  *         Binds the on-card AD7476 (U33, SPI1) used for resistance sensing.
  * @retval HAL_OK    matrix card and its ADC initialised.
  * @retval other     first failing HAL status from the two init calls.
  */
static HAL_StatusTypeDef board_init_matrix(void)
{
  /* Five expanders on I2C3: U21 (channel address, Control-Card side of the
   * isolator) plus the four Matrix-card enable expanders. */
  HAL_StatusTypeDef st = MatrixCard_Init(&g_matrix, BOARD_MATRIX_I2C);
  if (st != HAL_OK)
  {
    return st;
  }
  /* On-card AD7476 (U33 on SPI1) - CONTINUITY sense point. Resistance is read
   * by the ADS124S08 across HI_SENSE/LO_SENSE (see FW-01). */
  return MatrixCard_InitAdc(&g_matrix, BOARD_MATRIX_ADC_SPI,
                            BOARD_MATRIX_ADC_CS_PORT, BOARD_MATRIX_ADC_CS_PIN,
                            BOARD_VREF);
}

/**
  * @brief  Instantiate and bind the Control-Card analogue front end.
  * @note   Fills a ControlFrontendCfg_t from the board pin map (IDAC on SPI2,
  *         control ADC on SPI3, OPT0_CNTR select GPIO, vref) and initialises
  *         the front end, which comes up in continuity mode.
  * @retval HAL status from Frontend_Init().
  */
static HAL_StatusTypeDef board_init_frontend(void)
{
  ControlFrontendCfg_t cfg;
  cfg.idac_spi     = BOARD_IDAC_SPI;
  cfg.idac_cs_port = BOARD_IDAC_CS_PORT;
  cfg.idac_cs_pin  = BOARD_IDAC_CS_PIN;
  cfg.adc_spi      = BOARD_ADC_SPI;
  cfg.adc_cs_port  = BOARD_ADC_CS_PORT;
  cfg.adc_cs_pin   = BOARD_ADC_CS_PIN;
  cfg.opto_port    = OPT0_CNTR_GPIO_Port;
  cfg.opto_pin     = OPT0_CNTR_Pin;
  cfg.vref         = BOARD_VREF;
  return Frontend_Init(&g_frontend, &cfg);
}

/**
  * @brief  Instantiate and bind one HV card at board index @p idx.
  * @note   Fills an HvCardCfg_t: shared HV I2C bus, per-side expander straps
  *         (inject 0x20..0x23, return 0x24..0x27), isolated SPI2 for the DAC8830
  *         and both sense ADCs, and the HV-card ADC reference (+5V_ISO). Several
  *         straps/CS lines are placeholders pending the connector netlist (TODO).
  * @param  idx : [in] HV board index into g_hv[] (0..BOARD_HV_COUNT-1).
  * @retval HAL status from HvCard_Init().
  */
static HAL_StatusTypeDef board_init_hv(uint8_t idx)
{
  HvCardCfg_t cfg = {0};
  uint8_t i;

  cfg.i2c = BOARD_HV_I2C;          /* TODO: per-board bus when >1 board */
  for (i = 0U; i < HV_MCP_PER_SIDE; i++)
  {
    cfg.inject_strap[i] = i;       /* 0x20..0x23 - TODO verify straps   */
    cfg.return_strap[i] = (uint8_t)(i + HV_MCP_PER_SIDE); /* 0x24..0x27  */
  }
  cfg.spi              = BOARD_HV_SPI;
  cfg.dac_cs_port      = BOARD_HV_DAC_CS_PORT;
  cfg.dac_cs_pin       = BOARD_HV_DAC_CS_PIN;
  cfg.adc_rail_cs_port = BOARD_HV0_ADC_RAIL_CS_PORT;  /* TODO: per-board lines */
  cfg.adc_rail_cs_pin  = BOARD_HV0_ADC_RAIL_CS_PIN;
  cfg.adc_leak_cs_port = BOARD_HV0_ADC_LEAK_CS_PORT;
  cfg.adc_leak_cs_pin  = BOARD_HV0_ADC_LEAK_CS_PIN;
  cfg.vref             = BOARD_VREF_HV;   /* HV-card ADCs run off +5V_ISO */
  return HvCard_Init(&g_hv[idx], &cfg);
}

/**
  * @brief  Initialise the whole board: matrix, control front end and all HV cards.
  * @note   Runs the per-subsystem init helpers in order and aborts on the first
  *         failure. On success every layer is left in its safe idle state (HV at
  *         0 V, relays and muxes open). Call once from the application after the
  *         HAL peripherals (I2C/SPI/GPIO) have been initialised.
  * @retval HAL_OK    all subsystems initialised.
  * @retval other     first failing HAL status from a subsystem init.
  */
HAL_StatusTypeDef Board_Init(void)
{
  HAL_StatusTypeDef st;
  uint8_t i;

  st = board_init_matrix();
  if (st != HAL_OK)
  {
    return st;
  }
  st = board_init_frontend();
  if (st != HAL_OK)
  {
    return st;
  }
  for (i = 0U; i < (uint8_t)BOARD_HV_COUNT; i++)
  {
    st = board_init_hv(i);
    if (st != HAL_OK)
    {
      return st;
    }
  }
  return HAL_OK;
}