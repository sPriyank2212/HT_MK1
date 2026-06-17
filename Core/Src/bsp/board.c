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
 * Bus assignment (TODO: confirm which MCU bus reaches which card)
 * ------------------------------------------------------------------------- */
#define BOARD_MATRIX_I2C      (&hi2c3)   /* TODO: matrix isolated I2C bus      */
#define BOARD_HV_I2C          (&hi2c2)   /* TODO: HV isolated I2C bus          */
#define BOARD_IDAC_SPI        (&hspi2)   /* DAC8775 (Kelvin)                   */
#define BOARD_ADC_SPI         (&hspi1)   /* AD7476 (Control front end)         */
#define BOARD_HV_SPI          (&hspi3)   /* HV DAC8830 + AD7476                */

/* ---------------------------------------------------------------------------
 * CS / control pins. Several are placeholders reusing existing GPIO labels
 * until dedicated pins are assigned in CubeMX (TODO/VERIFY).
 * ------------------------------------------------------------------------- */
#define BOARD_ADC_CS_PORT     I2C2_CS_GPIO_Port   /* PC2 - reused; TODO dedicate */
#define BOARD_ADC_CS_PIN      I2C2_CS_Pin
#define BOARD_IDAC_CS_PORT    I2C3_CS_GPIO_Port   /* PC3 - placeholder; TODO    */
#define BOARD_IDAC_CS_PIN     I2C3_CS_Pin
#define BOARD_HV_DAC_CS_PORT  SPI3_CS_GPIO_Port   /* PB1                        */
#define BOARD_HV_DAC_CS_PIN   SPI3_CS_Pin
#define BOARD_HV_ADC_CS_PORT  SPI3_CSB2_GPIO_Port /* PB2                        */
#define BOARD_HV_ADC_CS_PIN   SPI3_CSB2_Pin

/* HV enable/discharge for board 0 use the two per-board control lines.
 * TODO: set these to OUTPUT in CubeMX (currently INPUT) and extend per board. */
#define BOARD_HV0_EN_PORT     HV_CARD_DT_1_0_GPIO_Port
#define BOARD_HV0_EN_PIN      HV_CARD_DT_1_0_Pin
#define BOARD_HV0_DISCHG_PORT HV_CARD_DT_1_1_GPIO_Port
#define BOARD_HV0_DISCHG_PIN  HV_CARD_DT_1_1_Pin

static HAL_StatusTypeDef board_init_matrix(void)
{
  /* Select-line GPIOs come over the (still-undrawn) Control<->Matrix connector;
   * leave them NULL so the layer is inert on the select lines for now. */
  MatrixSelectMap_t sel = {0};
  return MatrixCard_Init(&g_matrix, BOARD_MATRIX_I2C, &sel);
}

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
  cfg.spi          = BOARD_HV_SPI;
  cfg.dac_cs_port  = BOARD_HV_DAC_CS_PORT;
  cfg.dac_cs_pin   = BOARD_HV_DAC_CS_PIN;
  cfg.adc_cs_port  = BOARD_HV_ADC_CS_PORT;
  cfg.adc_cs_pin   = BOARD_HV_ADC_CS_PIN;
  cfg.hv_en_port   = BOARD_HV0_EN_PORT;     /* TODO: per-board lines     */
  cfg.hv_en_pin    = BOARD_HV0_EN_PIN;
  cfg.dischg_port  = BOARD_HV0_DISCHG_PORT;
  cfg.dischg_pin   = BOARD_HV0_DISCHG_PIN;
  cfg.vref         = BOARD_VREF;
  return HvCard_Init(&g_hv[idx], &cfg);
}

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