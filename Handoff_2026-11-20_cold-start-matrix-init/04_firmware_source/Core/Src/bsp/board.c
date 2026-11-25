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
#include "app/log.h"
#include "cmsis_os2.h"
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

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
DS18B20_t         g_ds18b20;

/* Set by Board_Init() on its way out; see Board_IsReady(). Starts 0 so any
 * hardware command that runs before Board_Init() is even called (should not
 * happen, but costs nothing to cover) is refused rather than assumed safe. */
static uint8_t s_board_ready = 0U;

/* Where Board_Init() stopped, for diagnostics: the failing stage name (NULL if
 * none / not run) and the HAL status it returned (1 = ERROR, 2 = BUSY,
 * 3 = TIMEOUT). Read by Board_InitFailStage()/Board_InitFailStatus(). */
static const char *s_init_stage = NULL;
static uint8_t     s_init_hal   = 0U;
static uint8_t     s_matrix_tries = 0U;   /* attempts the matrix stage needed, see Board_Init() */

/* Per HV slot: 1 if its card came up in Board_Init(), 0 if absent/unseated/dead
 * (and the HAL status it returned). A missing HV card does NOT fail Board_Init():
 * a unit with only a Matrix Card must still run continuity and resistance. */
static uint8_t s_hv_fitted[BOARD_HV_COUNT];
static uint8_t s_hv_hal[BOARD_HV_COUNT];

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
#define BOARD_MATRIX_I2C      (&hi2c3)   /* U20 ONLY - local to the Control
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
/* DAC8830 CS = HV card net ISO_HV_CARD_4 = Control Card HV_Card_1.3 = PC0
 * (CubeMX calls it HV_CARD_DT_2_1). The old placeholder, PC2 (I2C2_CS), goes
 * only to an isolator and reaches no connector pin, so it could never select
 * the DAC. The n -> HV_Card_1.(n-1) correspondence is the same one the ADC
 * chip-selects below already rely on; Insulation_HvSelfTest() proves it. */
#define BOARD_HV_DAC_CS_PORT  HV_CARD_DT_2_1_GPIO_Port   /* PC0 */
#define BOARD_HV_DAC_CS_PIN   HV_CARD_DT_2_1_Pin

/* HV-card ADC chip-selects = the two per-board control lines (isolated).
 *   HV_Card_x.1 -> RAIL ADC (U301 HV_Sense) ; HV_Card_x.0 -> LEAK ADC (U302 HV_RET).
 * TODO: set these to OUTPUT in CubeMX (currently INPUT) and extend per board. */
#define BOARD_HV0_ADC_RAIL_CS_PORT  HV_CARD_DT_1_1_GPIO_Port  /* PC14 */
#define BOARD_HV0_ADC_RAIL_CS_PIN   HV_CARD_DT_1_1_Pin
#define BOARD_HV0_ADC_LEAK_CS_PORT  HV_CARD_DT_1_0_GPIO_Port  /* PC13 */
#define BOARD_HV0_ADC_LEAK_CS_PIN   HV_CARD_DT_1_0_Pin

/* U2 (DS18B20U+T&R), Control Card `uC` sheet - HW-13, 2026-08-16. Confirmed
 * from the schematic diff, not yet carried into the CubeMX .ioc/gpio.c (no
 * main.h macro exists for PA0 yet) - configured directly in board_init_temp()
 * below, the same "configure directly so a regen can't clobber it" approach
 * ADS1232_HwInit_Nucleo() uses for pins ahead of
 * their own CubeMX registration. TODO: fold into the .ioc at the next real
 * CubeMX sync. */
#define BOARD_TEMP_PORT   GPIOA
#define BOARD_TEMP_PIN    GPIO_PIN_0

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
  /* U20 is local (I2C3, BOARD_MATRIX_I2C). The Matrix Card's own eight
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
 * (MCP23017 @ MATRIX_ADCCTL_STRAP), which sits behind the same BUFF1
 * translator as the force-enable expanders - see matrix_card.h - AND
 * on the same card-vs-card shared bus as every other Matrix expander (see
 * Doc/i2c_bus_sharing.md), so every access claims g_matrix's bus enable
 * before selecting its segment, and releases it after.
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
  * @brief  Claim the shared bus, select U69's segment, drive one U69 pin.
  * @note   Common path for cs/reset/start: all three cost a possible segment
  *         switch (free if that segment is already selected - see
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
  * @note   Must run after board_init_matrix(), which brings up U20 - U69 is
  *         unreachable until its (force) segment can be selected. Runs a self
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

  st = DIAG_ST(ADS124S08_Init(&g_ads124s08, BOARD_MATRIX_ADC_SPI, &io,
                              ADS124S08_GAIN_128, ADS124S08_DR_20), "ADS124S08_Init");
  if (st != HAL_OK)
  {
    return st;
  }
  return DIAG_ST(ADS124S08_SelfOffsetCal(&g_ads124s08), "ADS124S08 self offset cal");
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
  HAL_StatusTypeDef    spi_st;

  /* SPI3 carries the Control Card AD7476 (U4). spi.c / the .ioc leave SPI3 at the
   * CubeMX defaults - 4-bit frames at 32 MHz - which the AD7476 cannot work with
   * (ad7476.h says so: 16-bit frame, SCLK <= 20 MHz) and every read timed out
   * (hal=3) in the 2026-11-20 bench log. Reconfigured here, not in spi.c, so a
   * CubeMX regeneration cannot undo it. AD7476 datasheet p.18: data is valid on
   * SCLK falling edges, first leading zero already present when CS falls
   * -> idle-high clock, sample on the first (falling) edge = CPOL 1 / CPHA 0.
   * 64 MHz / 8 = 8 MHz, well inside the 20 MHz limit. */
  hspi3.Init.DataSize          = SPI_DATASIZE_16BIT;
  hspi3.Init.CLKPolarity       = SPI_POLARITY_HIGH;
  hspi3.Init.CLKPhase          = SPI_PHASE_1EDGE;
  hspi3.Init.BaudRatePrescaler = SPI_BAUDRATEPRESCALER_8;
  spi_st = DIAG_ST(HAL_SPI_Init(&hspi3), "board: SPI3 (AD7476) config");
  if (spi_st != HAL_OK)
  {
    return spi_st;
  }

  cfg.adc_spi      = BOARD_ADC_SPI;
  cfg.adc_cs_port  = BOARD_ADC_CS_PORT;
  cfg.adc_cs_pin   = BOARD_ADC_CS_PIN;
  cfg.opto_port    = OPT0_CNTR_GPIO_Port;
  cfg.opto_pin     = OPT0_CNTR_Pin;
  cfg.vref         = BOARD_VREF;
  return Frontend_Init(&g_frontend, &cfg);
}

/* HV_Card_EN1..4 (Control_Card /uC/ + /Isolator/): one bus-segment enable per
 * physical slot, J1..J4. HW-15 (decided by the hardware owner, 2026-11-13): the
 * Control Card's J1 (the Matrix Card's J101) is SHARED between the Matrix Card
 * and HV Card 1; J2 carries HV Card 2, J3 HV Card 3, J4 HV Card 4. So HV board
 * index i is on slot i: EN1 (PC5) for HV1 .. EN4 (PA9) for HV4, and EN1 is
 * ALSO the Matrix Card's enable (MatrixCard_Init()). Both cards strap their
 * expanders to 0x20..0x27, so board_init_hv() installs a pre-enable hook that
 * switches the Matrix segments off the bus before EN1 goes high for HV1. */
static GPIO_TypeDef * const board_hv_en_port[4] = {
  HV_CARD_EN1_GPIO_Port, HV_CARD_EN2_GPIO_Port,
  HV_CARD_EN3_GPIO_Port, HV_CARD_EN4_GPIO_Port
};
static const uint16_t board_hv_en_pin[4] = {
  HV_CARD_EN1_Pin, HV_CARD_EN2_Pin, HV_CARD_EN3_Pin, HV_CARD_EN4_Pin
};

/* board_init_hv() maps board index -> slot idx (J1..J4), so at most 4 boards. */
#if BOARD_HV_COUNT > 4
#error "BOARD_HV_COUNT > 4: the Control Card has four HV slots (J1..J4)"
#endif

/**
  * @brief  HvCardCfg_t.pre_enable for a slot that shares its enable with the
  *         Matrix Card: take both Matrix segments off the shared I2C bus.
  * @param  ctx : [in] unused.
  */
static HAL_StatusTypeDef board_matrix_off_bus(void *ctx)
{
  (void)ctx;
  return MatrixCard_Deselect(&g_matrix);
}

/**
  * @brief  Instantiate and bind one HV card at board index @p idx.
  * @note   Fills an HvCardCfg_t: shared HV I2C bus (gated by this slot's
  *         HV_Card_EN line - see the bus-sharing note above), per-side expander
  *         straps (inject 0x20..0x23, return 0x24..0x27), isolated SPI2 for the
  *         DAC8830 and both sense ADCs, and the HV-card ADC reference
  *         (+5V_ISO). Expander straps are confirmed (HV_Card sheet 5); some CS lines are placeholders pending the
  *         connector netlist (TODO).
  * @param  idx : [in] HV board index into g_hv[] (0..BOARD_HV_COUNT-1); maps to
  *                    physical slot idx (J1..J4, EN1..EN4) - see board_hv_en_port.
  * @retval HAL status from HvCard_Init().
  */
static HAL_StatusTypeDef board_init_hv(uint8_t idx)
{
  HvCardCfg_t cfg = {0};
  uint8_t i;
  uint8_t slot = idx;                   /* HV1 -> J1/EN1 (shared with Matrix) ... HV4 -> J4/EN4 */

  cfg.i2c = BOARD_HV_I2C;
  cfg.en_port = board_hv_en_port[slot];
  cfg.en_pin  = board_hv_en_pin[slot];
  if (cfg.en_port == g_matrix.en_port && cfg.en_pin == g_matrix.en_pin)
  {
    cfg.pre_enable = board_matrix_off_bus;   /* HW-15: shared with the Matrix Card */
  }
  for (i = 0U; i < HV_MCP_PER_SIDE; i++)
  {
    cfg.inject_strap[i] = i;       /* 0x20..0x23 - confirmed vs HV_Card sheet 5 */
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
  * @brief  Configure PA0 open-drain and bind the DS18B20 (U2) temperature sensor.
  * @note   No bus/mutex dependency (unlike board_init_matrix()/board_init_ads124s08()) -
  *         it is a single GPIO, not on the shared I2C segments.
  * @retval HAL status from DS18B20_Init().
  */
static HAL_StatusTypeDef board_init_temp(void)
{
  GPIO_InitTypeDef gpio = {0};

  __HAL_RCC_GPIOA_CLK_ENABLE();   /* already enabled by MX_GPIO_Init(); harmless twice */

  gpio.Pin   = BOARD_TEMP_PIN;
  gpio.Mode  = GPIO_MODE_OUTPUT_OD;
  gpio.Pull  = GPIO_NOPULL;         /* R2 (4.7k) on the schematic is the pull-up */
  gpio.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(BOARD_TEMP_PORT, &gpio);

  return DS18B20_Init(&g_ds18b20, BOARD_TEMP_PORT, BOARD_TEMP_PIN);
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

  s_init_stage = NULL;
  s_init_hal   = 0U;
  Diag_Mark();

  /* The Matrix Card is powered (isolated rails, I2C2 buffers) independently of
   * the Control Card and can come up AFTER this code runs at power-up: bench
   * 2026-11-18 - U101 NAKed on the cold boot ("matrix/force-exp@0x20") and the
   * same card passed after a reset. So a failed matrix stage is retried, with a
   * delay, before it counts as a failure. Bounded: BOARD_MATRIX_TRIES x
   * BOARD_MATRIX_RETRY_MS (a card that is really absent costs ~1 s once). */
  s_matrix_tries = 1U;
  st = DIAG_ST(board_init_matrix(), "Board_Init: matrix stage");
  while (st != HAL_OK && s_matrix_tries < (uint8_t)BOARD_MATRIX_TRIES)
  {
    HAL_Delay((uint32_t)BOARD_MATRIX_RETRY_MS);
    s_matrix_tries++;
    Diag_Mark();   /* "first failure" must describe the LAST attempt */
    st = DIAG_ST(board_init_matrix(), "Board_Init: matrix stage");
  }
  if (st != HAL_OK) { s_init_stage = "matrix"; s_init_hal = (uint8_t)st; return st; }
  st = DIAG_ST(board_init_ads124s08(), "Board_Init: ads124s08 stage");
  if (st != HAL_OK) { s_init_stage = "ads124s08"; s_init_hal = (uint8_t)st; return st; }
  st = DIAG_ST(board_init_frontend(), "Board_Init: frontend stage");
  if (st != HAL_OK) { s_init_stage = "frontend"; s_init_hal = (uint8_t)st; return st; }
  /* HV cards are optional: a failure marks that slot "not fitted" and carries on. */
  for (i = 0U; i < (uint8_t)BOARD_HV_COUNT; i++)
  {
    st = DIAG_ST(board_init_hv(i), "Board_Init: HV card stage");
    s_hv_fitted[i] = (st == HAL_OK) ? 1U : 0U;
    s_hv_hal[i]    = (uint8_t)st;
  }
  /* Not gated into the abort-on-failure chain above: DS18B20_Init() only
   * fails on a NULL argument (never happens here - the pointers are fixed
   * local constants), and a missing/unpowered sensor is not detected until
   * DS18B20_ReadTemperature() is actually called (>TEMP READ). A diagnostic
   * temperature sensor should not be able to block the electrical-test
   * subsystems from coming up. */
  (void)board_init_temp();
  s_board_ready = 1U;
  return HAL_OK;
}

const char *Board_InitFailStage(void)
{
  return s_init_stage;
}

void Board_InitFailText(char *buf, uint8_t n)
{
  if (buf == NULL || n == 0U) { return; }
  if (s_init_stage == NULL)
  {
    (void)snprintf(buf, n, "none");
  }
  else if (strcmp(s_init_stage, "matrix") == 0)
  {
    (void)snprintf(buf, n, "matrix/%s@0x%02X", MatrixCard_InitStep(),
                   (unsigned)MatrixCard_InitAddr());
  }
  else
  {
    (void)snprintf(buf, n, "%s", s_init_stage);
  }
}

uint8_t Board_InitFailStatus(void)
{
  return s_init_hal;
}

uint8_t Board_HvFitted(uint8_t idx)
{
  return (idx < (uint8_t)BOARD_HV_COUNT) ? s_hv_fitted[idx] : 0U;
}

uint8_t Board_HvStatus(uint8_t idx)
{
  return (idx < (uint8_t)BOARD_HV_COUNT) ? s_hv_hal[idx] : 0U;
}

uint8_t Board_HvAnyFitted(void)
{
  uint8_t i;
  for (i = 0U; i < (uint8_t)BOARD_HV_COUNT; i++)
  {
    if (s_hv_fitted[i] != 0U) { return 1U; }
  }
  return 0U;
}

uint8_t Board_MatrixTries(void)
{
  return s_matrix_tries;
}

uint8_t Board_IsReady(void)
{
  return s_board_ready;
}

/* ---- bus scans (boot-failure diagnosis) ------------------------------------
 * Run from the low-priority tScan thread AFTER the kernel is up (tasks.c), never
 * from Tasks_Init: a stuck bus must not be able to stop the comms task answering
 * the GUI. Every scan is bounded three ways so it can only ever report, never
 * hang: HAL_I2C_IsDeviceReady() has a 3 ms timeout per address, each whole scan
 * has a time budget (BOARD_SCAN_BUDGET_MS), and BOARD_SCAN_BUSY_MAX consecutive
 * HAL_BUSY answers (SDA/SCL held low, or a transfer left the peripheral locked)
 * end it early with a message that names the bus. */

typedef struct
{
  uint8_t  n_ack;
  uint8_t  n_busy;
  uint8_t  n_probed;
  uint8_t  busy_run;     /* consecutive HAL_BUSY, resets on any other answer */
  uint8_t  stop;         /* 1 = gave up: budget or busy limit */
  uint8_t  last_addr;
  char     line[40];     /* room for 8 addresses; more are counted, not listed */
  size_t   len;
  uint32_t t0;
} ScanAcc_t;

static void scan_begin(ScanAcc_t *s)
{
  s->n_ack = 0U; s->n_busy = 0U; s->n_probed = 0U; s->busy_run = 0U;
  s->stop = 0U; s->last_addr = 0U; s->len = 0U; s->line[0] = '\0';
  s->t0 = HAL_GetTick();
}

/* Probe addresses 0x08..0x77 on one bus; fills @p s. */
static void scan_bus(I2C_HandleTypeDef *bus, ScanAcc_t *s)
{
  uint8_t a;

  scan_begin(s);
  for (a = 0x08U; a <= 0x77U; a++)
  {
    HAL_StatusTypeDef r;

    if ((HAL_GetTick() - s->t0) > (uint32_t)BOARD_SCAN_BUDGET_MS) { s->stop = 1U; break; }
    s->last_addr = a;
    r = HAL_I2C_IsDeviceReady(bus, (uint16_t)(a << 1U), 1U, 3U);
    s->n_probed++;
    if (r == HAL_OK)
    {
      int w = snprintf(s->line + s->len, sizeof s->line - s->len, " 0x%02X", (unsigned)a);
      if (w > 0 && (size_t)w < sizeof s->line - s->len) { s->len += (size_t)w; }
      s->n_ack++;
      s->busy_run = 0U;
    }
    else if (r == HAL_BUSY)
    {
      s->n_busy++;
      if (++s->busy_run >= (uint8_t)BOARD_SCAN_BUSY_MAX) { s->stop = 1U; break; }
    }
    else
    {
      s->busy_run = 0U;   /* HAL_ERROR = NAK or 3 ms timeout: normal for an empty address */
    }
  }
}

/* One summary line per scan: who answered, and why it stopped early if it did. */
static void scan_report(const char *what, const ScanAcc_t *s)
{
  const uint32_t ms = HAL_GetTick() - s->t0;

  if (s->stop != 0U && s->busy_run >= (uint8_t)BOARD_SCAN_BUSY_MAX)
  {
    LOG_E("SCAN", "%s: bus BUSY at 0x%02X (SDA/SCL held low or peripheral stuck) - gave up after %u probes, %lu ms",
          what, (unsigned)s->last_addr, (unsigned)s->n_probed, (unsigned long)ms);
  }
  else if (s->stop != 0U)
  {
    LOG_E("SCAN", "%s: TIMEOUT - %lu ms budget used, stopped at 0x%02X after %u probes (%u ack)",
          what, (unsigned long)ms, (unsigned)s->last_addr, (unsigned)s->n_probed, (unsigned)s->n_ack);
  }
  else if (s->n_ack == 0U)
  {
    LOG_W("SCAN", "%s: nothing answers (%u probes, %lu ms)", what, (unsigned)s->n_probed, (unsigned long)ms);
  }
  else
  {
    LOG_W("SCAN", "%s: %u ack:%s (%lu ms)", what, (unsigned)s->n_ack, s->line, (unsigned long)ms);
  }
  Board_SettleMs(15U);   /* let the logger drain: 24-deep queue, non-blocking put */
}

/* Matrix-card bus diagnosis, for when the first Matrix expander on the shared
 * I2C2 NAKs although U20 answers. With the Matrix segment claimed (EN1 high),
 * drive U20's two buffer-enable bits through all four combinations and scan
 * I2C2 under each: "none" everywhere = nothing electrically reaches the card
 * (unpowered / unseated / ISO_SDA2-SCL2 not connected); answers under only one
 * combination = the enable bit or its polarity is not what the firmware
 * assumes. Channel-select bits stay 0, no Matrix expander is written, and the
 * buffers are left disabled afterwards. Caller holds the hardware mutex. */
void Board_ScanMatrixBusLog(void)
{
  static const uint16_t combo[4] = {
    0U,
    (uint16_t)(1U << MATRIX_SEL_BUFF2_OE_BIT),
    (uint16_t)(1U << MATRIX_SEL_BUFF1_OE_BIT),
    (uint16_t)((1U << MATRIX_SEL_BUFF2_OE_BIT) | (1U << MATRIX_SEL_BUFF1_OE_BIT))
  };
  static const char *const name[4] = { "both off", "sense/BUFF2", "force/BUFF1", "both on" };
  uint8_t c;

  if (g_matrix.en_port == NULL)
  {
    LOG_W("SCAN", "i2c2: skipped - init never reached the Matrix bus claim");
    return;
  }

  MatrixCard_BusClaim(&g_matrix);
  for (c = 0U; c < 4U; c++)
  {
    ScanAcc_t s;
    char      what[40];

    if (MCP23017_WritePins(&g_matrix.sel, combo[c]) != HAL_OK)
    {
      LOG_E("SCAN", "i2c2: U20 write failed (%s) - scan aborted", name[c]);
      break;
    }
    Board_SettleMs(2U);
    (void)snprintf(what, sizeof what, "i2c2 U20=0x%04X (%s)", combo[c], name[c]);
    scan_bus(BOARD_HV_I2C, &s);
    scan_report(what, &s);
    if (s.stop != 0U) { break; }   /* a stuck bus will not get better under another combination */
  }
  if (c == 4U)
  {
    /* Identify, not just detect: the same address answers on both segments
     * (0x20/0x22/0x24/0x26), so an ACK cannot say whether it is one device or two.
     * Read IODIRA (register 0x00, read-only) of each candidate with ONLY the
     * sense buffer on, then ONLY the force buffer on. Different values = two
     * separate parts; identical values prove nothing either way. A part Board_Init
     * never reached (e.g. U69 after an ads124s08 failure) still holds its power-on
     * 0xFF while the configured expanders read 0x00. "--" = no ACK. */
    static const uint8_t ident[5] = { 0x20U, 0x21U, 0x22U, 0x24U, 0x26U };
    int16_t v[2][5];
    uint8_t k, j;
    char    out[80];
    size_t  n = 0U;

    for (k = 0U; k < 2U; k++)
    {
      for (j = 0U; j < 5U; j++) { v[k][j] = -1; }
      if (MCP23017_WritePins(&g_matrix.sel, combo[k + 1U]) != HAL_OK) { break; }
      Board_SettleMs(2U);
      for (j = 0U; j < 5U; j++)
      {
        uint8_t b = 0U;
        if (HAL_I2C_Mem_Read(BOARD_HV_I2C, (uint16_t)(ident[j] << 1U), 0x00U,
                             I2C_MEMADD_SIZE_8BIT, &b, 1U, 5U) == HAL_OK)
        {
          v[k][j] = (int16_t)b;
        }
      }
    }
    for (j = 0U; j < 5U && n < sizeof out; j++)
    {
      char a[6], f[6];
      if (v[0][j] < 0) { (void)snprintf(a, sizeof a, "--"); } else { (void)snprintf(a, sizeof a, "%02X", (unsigned)v[0][j]); }
      if (v[1][j] < 0) { (void)snprintf(f, sizeof f, "--"); } else { (void)snprintf(f, sizeof f, "%02X", (unsigned)v[1][j]); }
      n += (size_t)snprintf(out + n, sizeof out - n, " %02X=%s/%s", (unsigned)ident[j], a, f);
    }
    LOG_W("SCAN", "IODIRA sense-only/force-only:%s", out);
    Board_SettleMs(15U);
  }
  (void)MCP23017_WritePins(&g_matrix.sel, 0U);   /* buffers disabled again */
  MatrixCard_BusRelease(&g_matrix);
}

/* Probe every legal 7-bit address on I2C3 and log who answers. I2C3 carries
 * U20 only, so the expected answer is exactly "0x20". A probe is address-only,
 * so it cannot disturb any device. Caller holds the hardware mutex. */
void Board_ScanI2c3Log(void)
{
  ScanAcc_t s;

  scan_bus(&hi2c3, &s);
  scan_report("i2c3 (U20 wants its strap address)", &s);
}

/**
  * @brief  Probe one MCP23017 by address only - a real transaction (a
  *         register read would need to know each part's own state), so a
  *         genuine ACK/NAK, not a guess.
  */
static uint8_t board_probe(BoardBusEntry_t *e, I2C_HandleTypeDef *hi2c,
                           uint8_t addr7)
{
  e->addr7 = addr7;
  e->ok = (HAL_I2C_IsDeviceReady(hi2c, (uint16_t)(addr7 << 1U), 2U, 25U)
           == HAL_OK) ? 1U : 0U;
  return e->ok;
}

uint8_t Board_ScanBus(BoardBusEntry_t *out, uint8_t max)
{
  uint8_t n = 0U;

  if (out == NULL || max == 0U)
  {
    return 0U;
  }

  /* U20 - channel/segment select. Local to I2C3, no bus-claim needed. Names
   * are single tokens (no spaces) - Proto_EvtBusLine emits them on the wire,
   * a space-delimited protocol. */
  out[n].name = "U20";
  (void)board_probe(&out[n], g_matrix.sel.hi2c, g_matrix.sel.addr7);
  n++;

  /* Everything else is on the shared bus behind this card's own segment
   * enable - claim it for the whole scan, same discipline as any other
   * multi-register Matrix Card access. */
  MatrixCard_BusClaim(&g_matrix);

  if (MatrixCard_SelectSegment(&g_matrix, MATRIX_SEG_FORCE) == HAL_OK)
  {
    static const char *const force_names[MATRIX_EXP_PER_BANK * 2U] = {
      "U101", "U105", "U102", "U106"
    };
    const MCP23017_t *force[MATRIX_EXP_PER_BANK * 2U] = {
      &g_matrix.hi_en[0], &g_matrix.hi_en[1], &g_matrix.lo_en[0], &g_matrix.lo_en[1]
    };
    uint8_t i;
    for (i = 0U; i < (MATRIX_EXP_PER_BANK * 2U) && n < max; i++)
    {
      out[n].name = force_names[i];
      (void)board_probe(&out[n], force[i]->hi2c, force[i]->addr7);
      n++;
    }
    /* U69, the ADS124S08 control expander, lives on this same segment
     * (board.c's own s_adcctl, not part of MatrixCard_t - see
     * board_init_ads124s08()). Corrected 2026-11-20: it was probed on the
     * sense segment, where it is not. */
    if (n < max)
    {
      out[n].name = "U69";
      (void)board_probe(&out[n], s_adcctl.hi2c, s_adcctl.addr7);
      n++;
    }
  }

  if (MatrixCard_SelectSegment(&g_matrix, MATRIX_SEG_SENSE) == HAL_OK)
  {
    static const char *const sense_names[MATRIX_EXP_PER_BANK * 2U] = {
      "U66", "U67", "U107", "U108"
    };
    const MCP23017_t *sense[MATRIX_EXP_PER_BANK * 2U] = {
      &g_matrix.hi_sns[0], &g_matrix.hi_sns[1], &g_matrix.lo_sns[0], &g_matrix.lo_sns[1]
    };
    uint8_t i;
    for (i = 0U; i < (MATRIX_EXP_PER_BANK * 2U) && n < max; i++)
    {
      out[n].name = sense_names[i];
      (void)board_probe(&out[n], sense[i]->hi2c, sense[i]->addr7);
      n++;
    }
  }

  MatrixCard_BusRelease(&g_matrix);

  /* ADS124S08 itself: a real identity check (DEVID field), not just a bus
   * ACK - SPI devices don't ACK/NAK the way I2C does. */
  if (n < max)
  {
    uint8_t id = 0U;
    out[n].name = "U68";
    out[n].addr7 = 0U; /* SPI, not I2C-addressed */
    out[n].ok = (ADS124S08_CheckId(&g_ads124s08, &id) == HAL_OK) ? 1U : 0U;
    n++;
  }

  /* HV cards: 4 high-side (HS, 0x20..0x23) + 4 low-side (LS, 0x24..0x27)
   * relay expanders each. Straps confirmed against HV_Card schematic sheet 5
   * (/GPIO_Expander/, the address annotations beside U1xx). Every card straps
   * to the same range, so each is put on the shared bus alone via its own
   * HV_Card_ENx - the same Hold/Unhold discipline as any relay access. A card
   * that is not fitted simply NAKs and is reported as a fault. Names are
   * single tokens (wire format: "!BUSLINE <name> ok|fault"). */
  {
    static const char *const hv_names[4][2U * HV_MCP_PER_SIDE] = {
      { "HV1_HS1", "HV1_HS2", "HV1_HS3", "HV1_HS4",
        "HV1_LS1", "HV1_LS2", "HV1_LS3", "HV1_LS4" },
      { "HV2_HS1", "HV2_HS2", "HV2_HS3", "HV2_HS4",
        "HV2_LS1", "HV2_LS2", "HV2_LS3", "HV2_LS4" },
      { "HV3_HS1", "HV3_HS2", "HV3_HS3", "HV3_HS4",
        "HV3_LS1", "HV3_LS2", "HV3_LS3", "HV3_LS4" },
      { "HV4_HS1", "HV4_HS2", "HV4_HS3", "HV4_HS4",
        "HV4_LS1", "HV4_LS2", "HV4_LS3", "HV4_LS4" },
    };
    uint8_t c;
    for (c = 0U; c < (uint8_t)BOARD_HV_COUNT; c++)
    {
      HvCard_t *hv = &g_hv[c];
      uint8_t   usable = (hv->cfg.i2c != NULL && hv->cfg.en_port != NULL) ? 1U : 0U;
      uint8_t   k;

      if (usable != 0U) { HvCard_Hold(hv); }
      for (k = 0U; k < (2U * HV_MCP_PER_SIDE) && n < max; k++)
      {
        uint8_t strap = (k < HV_MCP_PER_SIDE) ? hv->cfg.inject_strap[k]
                                              : hv->cfg.return_strap[k - HV_MCP_PER_SIDE];
        uint8_t addr7 = (uint8_t)(MCP23017_ADDR_BASE | strap);
        out[n].name = hv_names[c][k];
        if (usable != 0U)
        {
          (void)board_probe(&out[n], hv->cfg.i2c, addr7);
        }
        else
        {
          /* Board_Init() never configured this card (no I2C handle / enable
           * line): report the address it would have used as a fault. */
          out[n].addr7 = addr7;
          out[n].ok    = 0U;
        }
        n++;
      }
      if (usable != 0U) { HvCard_Unhold(hv); }
    }
  }

  return n;
}