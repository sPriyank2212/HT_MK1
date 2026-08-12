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
#include "cmsis_os2.h"

/**
  * @brief  Wait for hardware to settle, yielding the CPU if the RTOS is running.
  * @note   See board.h. The +1 mirrors what HAL_Delay() does internally: the
  *         first tick may be about to fire, so without it a request for 2 ms
  *         could return after barely 1. Settle times must never shrink.
  * @param  ms : [in] settle time, milliseconds.
  * @retval None
  */
void Board_SettleMs(uint32_t ms)
{
  if (osKernelGetState() == osKernelRunning)
  {
    (void)osDelay(ms + 1U);
  }
  else
  {
    HAL_Delay(ms);
  }
}

MatrixCard_t      g_matrix;
ControlFrontend_t g_frontend;
HvCard_t          g_hv[BOARD_HV_COUNT];
ADS124S08_t       g_ads124s08;

/* ---------------------------------------------------------------------------
 * Bus assignment - corrected against the Doc/ schematics (2026-07):
 *   SPI1 = Matrix-Card ADS124S08 (U68, HI_SENSE/LO_SENSE + its own IDAC)
 *   SPI2 = HV-card AD7476s + DAC8830, isolated (shared)
 *   SPI3 = Control-Card AD7476 (U4, ADC_IN off the Opto SPDT)
 * FW-12 (2026-08-12): SPI2 no longer carries a DAC8775 - that chip is gone
 *   from the schematic (Doc/idac_current_source.md). Kelvin excitation is
 *   now sourced by the ADS124S08's own IDAC on SPI1, not a separate SPI2
 *   device, so SPI2's mixed-frame-size TODO below is DAC8830/AD7476 only now.
 * TODO(CubeMX): SPI2 carries 16-bit (DAC8830/AD7476) devices only - data size
 *   must be set per transaction, or run 8-bit with the drivers doing byte
 *   framing. See fw_status CONFIG TODO.
 * ------------------------------------------------------------------------- */
#define BOARD_MATRIX_I2C      (&hi2c3)   /* U21/U20 ONLY - local to the Control
                                           * Card (Control_Card-5 sheet
                                           * /GPIO_Expander/). The Matrix Card's
                                           * OWN onboard expanders are NOT on
                                           * this bus - see BOARD_HV_I2C. */
#define BOARD_HV_I2C          (&hi2c2)   /* Isolated I2C2 (ISO_SDA2/ISO_SCL2) -
                                           * confirmed shared by every HV slot
                                           * AND the Matrix Card's own onboard
                                           * expanders (confirmed against real
                                           * hardware, same bus as HV Card 1 -
                                           * see Doc/i2c_bus_sharing.md). Every
                                           * card straps its expanders to the
                                           * same 0x20..0x27, so HV_Card_EN1..4
                                           * must gate exactly one card's
                                           * segment onto this bus at a time -
                                           * see hv_card.c and
                                           * MatrixCard_BusClaim/Release. */
#define BOARD_ADC_SPI         (&hspi3)   /* AD7476 (Control front end, U4)     */
#define BOARD_HV_SPI          (&hspi2)   /* HV DAC8830 + both AD7476 (isolated)*/
#define BOARD_MATRIX_ADC_SPI  (&hspi1)   /* ADS124S08 (Matrix U68) - the only  */
                                          /* device left on SPI1 since         */
                                          /* Matrix_Card 2 removed U33 (AD7476)*/
/* ADS124S08 CS/RESET/START/DRDY are NOT MCU GPIOs - they are driven through
 * U69 (MCP23017) on the matrix's own I2C segment. See board_init_ads124s08(). */

/* ---------------------------------------------------------------------------
 * CS / control pins. Confirmed where the schematic is unambiguous; the isolated
 * HV DAC CS is still a placeholder pending the connector netlist (VERIFY).
 * ------------------------------------------------------------------------- */
#define BOARD_ADC_CS_PORT     SPI3_CS_GPIO_Port   /* PB1 - Control ADC (U4)     */
#define BOARD_ADC_CS_PIN      SPI3_CS_Pin
/* SPI3_CSB2 (PB2) drove the DAC8775 CS; FW-12 removed the last reference to
 * it in board_init_frontend() below. Left configured in CubeMX rather than
 * repurposed - that's a hardware-config decision, not a firmware one. */
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
  /* U21 is local (I2C3, BOARD_MATRIX_I2C). The Matrix Card's own eight
   * expanders are on the shared bus (I2C2, BOARD_HV_I2C) behind HV_Card_EN1 -
   * confirmed against real hardware, same bus HV Card 1 uses. See
   * Doc/i2c_bus_sharing.md. */
  HAL_StatusTypeDef st = MatrixCard_Init(&g_matrix, BOARD_MATRIX_I2C, BOARD_HV_I2C,
                                         HV_CARD_EN1_GPIO_Port, HV_CARD_EN1_Pin);
  if (st != HAL_OK)
  {
    return st;
  }
  /* Matrix_Card 2 REMOVED the on-card AD7476 (U33). Continuity is now measured
   * on the Control Card: HI_COM -> J101 -> IN -> Opto SPDT -> ADC_IN, which the
   * front end already owns. Resistance will be read by the ADS124S08 across
   * HI_SENSE/LO_SENSE once FW-01 lands. Nothing further to bind here. */
  return st;
}

/* -----------------------------------------------------------------------
 * ADS124S08 (Matrix Card U68) control lines. All four live on U69
 * (MCP23017 @ MATRIX_ADCCTL_STRAP), which sits behind the same BUFF2
 * translator as the sense-enable expanders - see matrix_card.h HW-12 - AND
 * on the same card-vs-card shared bus as every other Matrix expander (see
 * Doc/i2c_bus_sharing.md), so every access claims g_matrix's bus enable
 * before selecting the sense segment, and releases it after.
 * -------------------------------------------------------------------- */
static MCP23017_t s_adcctl;   /* U69 */

/* U69 pin numbers in the mcp23017 driver's packing (0..7 = GPA, 8..15 = GPB).
 * Matrix_Card-7.pdf sheet 9: GPB0 = ADC_RST_1, GPB1 = DRDY_1 (input),
 * GPB2 = ADC_CS_1, GPB3 = Start_SYNC_1. */
#define BOARD_ADS_PIN_RESET   8U
#define BOARD_ADS_PIN_DRDY    9U
#define BOARD_ADS_PIN_CS      10U
#define BOARD_ADS_PIN_START   11U

/**
  * @brief  Claim the shared bus, select the sense segment, drive one U69 pin.
  * @note   Common path for cs/reset/start: all three cost a possible segment
  *         switch (free if the sense segment is already selected - see
  *         MatrixCard_SelectSegment) plus one expander write, bracketed by
  *         the shared-bus claim/release every card must use.
  */
static HAL_StatusTypeDef board_ads_line(uint8_t pin, uint8_t state)
{
  HAL_StatusTypeDef st;

  MatrixCard_BusClaim(&g_matrix);
  st = MatrixCard_SelectSegment(&g_matrix, MATRIX_ADCCTL_SEG);
  if (st == HAL_OK)
  {
    st = MCP23017_WritePin(&s_adcctl, pin, state);
  }
  MatrixCard_BusRelease(&g_matrix);
  return st;
}

/**
  * @brief  io.cs callback. assert=1 means CS low (device selected).
  */
static HAL_StatusTypeDef board_ads_cs(void *ctx, uint8_t assert)
{
  (void)ctx;
  return board_ads_line(BOARD_ADS_PIN_CS, (uint8_t)(assert == 0U));
}

/**
  * @brief  io.reset callback. assert=1 means RESET low (device held in reset).
  */
static HAL_StatusTypeDef board_ads_reset(void *ctx, uint8_t assert)
{
  (void)ctx;
  return board_ads_line(BOARD_ADS_PIN_RESET, (uint8_t)(assert == 0U));
}

/**
  * @brief  io.start callback. assert=1 means START/SYNC high (conversions run).
  */
static HAL_StatusTypeDef board_ads_start(void *ctx, uint8_t assert)
{
  (void)ctx;
  return board_ads_line(BOARD_ADS_PIN_START, assert);
}

/**
  * @brief  io.drdy callback. DRDY_1 is active low (SBAS660C), so "ready"
  *         means the pin reads 0.
  */
static HAL_StatusTypeDef board_ads_drdy(void *ctx, uint8_t *ready)
{
  uint16_t pins;
  HAL_StatusTypeDef st;

  (void)ctx;
  MatrixCard_BusClaim(&g_matrix);
  st = MatrixCard_SelectSegment(&g_matrix, MATRIX_ADCCTL_SEG);
  if (st == HAL_OK)
  {
    st = MCP23017_ReadPins(&s_adcctl, &pins);
  }
  MatrixCard_BusRelease(&g_matrix);
  if (st != HAL_OK)
  {
    return st;
  }
  *ready = (uint8_t)(((pins >> BOARD_ADS_PIN_DRDY) & 1U) == 0U);
  return HAL_OK;
}

/**
  * @brief  Instantiate U69 and the ADS124S08 itself.
  * @note   Must run after board_init_matrix(), which brings up U21 - U69 is
  *         unreachable until the sense segment can be selected. Runs a self
  *         offset calibration once at bring-up (cancels the ADC's own offset;
  *         Kelvin_MeasurePair separately subtracts a fresh zero-current
  *         baseline per point for the rest of the path - see BU-10).
  * @retval HAL status from the first failing step.
  */
static HAL_StatusTypeDef board_init_ads124s08(void)
{
  static const ADS124S08_Io_t io = {
    board_ads_cs, board_ads_reset, board_ads_start, board_ads_drdy, NULL
  };
  HAL_StatusTypeDef st;

  /* U69 is on the shared bus (BOARD_HV_I2C), same as every other Matrix
   * expander - see the note above board_ads_line(). */
  MatrixCard_BusClaim(&g_matrix);
  st = MatrixCard_SelectSegment(&g_matrix, MATRIX_ADCCTL_SEG);
  if (st == HAL_OK)
  {
    st = MCP23017_Init(&s_adcctl, BOARD_HV_I2C, MATRIX_ADCCTL_STRAP);
  }
  if (st == HAL_OK)
  {
    /* DRDY_1 is the only input on this expander. */
    st = MCP23017_SetDirection(&s_adcctl, (uint16_t)(1U << BOARD_ADS_PIN_DRDY));
  }
  MatrixCard_BusRelease(&g_matrix);
  if (st != HAL_OK)
  {
    return st;
  }

  st = ADS124S08_Init(&g_ads124s08, BOARD_MATRIX_ADC_SPI, &io,
                      ADS124S08_GAIN_128, ADS124S08_DR_20);
  if (st != HAL_OK)
  {
    return st;
  }
  return ADS124S08_SelfOffsetCal(&g_ads124s08);
}

/**
  * @brief  Instantiate and bind the Control-Card analogue front end.
  * @note   Fills a ControlFrontendCfg_t from the board pin map (control ADC on
  *         SPI3, OPT0_CNTR select GPIO, vref) and initialises the front end,
  *         which comes up in continuity mode. FW-12: no longer configures an
  *         IDAC here - the DAC8775 is gone from the schematic (see
  *         Doc/idac_current_source.md); Kelvin excitation is now the
  *         ADS124S08's own IDAC, configured in test/kelvin.c.
  * @retval HAL status from Frontend_Init().
  */
static HAL_StatusTypeDef board_init_frontend(void)
{
  ControlFrontendCfg_t cfg;
  cfg.adc_spi      = BOARD_ADC_SPI;
  cfg.adc_cs_port  = BOARD_ADC_CS_PORT;
  cfg.adc_cs_pin   = BOARD_ADC_CS_PIN;
  cfg.opto_port    = OPT0_CNTR_GPIO_Port;
  cfg.opto_pin     = OPT0_CNTR_Pin;
  cfg.vref         = BOARD_VREF;
  return Frontend_Init(&g_frontend, &cfg);
}

/* HV_Card_EN1..4 (Control_Card-5 /uC/ + /Isolator/): one bus-segment enable
 * per physical slot, J1..J4. J1 is the Matrix Card's own connector (it carries
 * LO_S1-4, HI_S1-4, the SPI1 bus and IN - see PROJECT_LOG HW-09), not a free
 * HV slot - EN1 is used directly by MatrixCard_Init() (board_init_matrix()
 * above), not through this table. So board index 0 maps to slot 1 (J2/EN2)
 * below: at most 3 HV boards fit alongside the Matrix Card. */
static GPIO_TypeDef * const board_hv_en_port[4] = {
  HV_CARD_EN1_GPIO_Port, HV_CARD_EN2_GPIO_Port,
  HV_CARD_EN3_GPIO_Port, HV_CARD_EN4_GPIO_Port
};
static const uint16_t board_hv_en_pin[4] = {
  HV_CARD_EN1_Pin, HV_CARD_EN2_Pin, HV_CARD_EN3_Pin, HV_CARD_EN4_Pin
};

/* board_init_hv() maps board index -> slot idx+1, so at most 3 boards fit
 * (idx 0..2 -> J2..J4) once J1 is reserved for the Matrix Card. */
#if BOARD_HV_COUNT > 3
#error "BOARD_HV_COUNT > 3 needs J1 to also serve as an HV slot - see HW-09"
#endif

/**
  * @brief  Instantiate and bind one HV card at board index @p idx.
  * @note   Fills an HvCardCfg_t: shared HV I2C bus (gated by this slot's
  *         HV_Card_EN line - see the bus-sharing note above), per-side expander
  *         straps (inject 0x20..0x23, return 0x24..0x27), isolated SPI2 for the
  *         DAC8830 and both sense ADCs, and the HV-card ADC reference
  *         (+5V_ISO). Several straps/CS lines are placeholders pending the
  *         connector netlist (TODO).
  * @param  idx : [in] HV board index into g_hv[] (0..BOARD_HV_COUNT-1); maps to
  *                    physical slot idx+1 (J2..J5) - see board_hv_en_port above.
  * @retval HAL status from HvCard_Init().
  */
static HAL_StatusTypeDef board_init_hv(uint8_t idx)
{
  HvCardCfg_t cfg = {0};
  uint8_t i;
  uint8_t slot = (uint8_t)(idx + 1U);   /* 0 -> J2/EN2, reserving J1 for Matrix */

  cfg.i2c = BOARD_HV_I2C;
  cfg.en_port = board_hv_en_port[slot];
  cfg.en_pin  = board_hv_en_pin[slot];
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
  st = board_init_ads124s08();
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