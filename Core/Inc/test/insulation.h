/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    insulation.h
  * @brief   500 V insulation-resistance test for one HV board. Implements the
  *          full safe HV sequence (set V -> connect relays -> enable HV ->
  *          settle -> measure -> disable -> mandatory discharge -> open relays).
  *
  *          OPEN POINT (#4 in fw_status.txt): the leakage-current sense chain is
  *          unconfirmed, so the final leakage -> insulation-resistance maths is
  *          STUBBED. The sequencing, timing and safety are complete; only the
  *          conversion of HvCard sense into ohms is pending the measurement
  *          topology. Verdict is TEST_ERROR until that is resolved.
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __INSULATION_H
#define __INSULATION_H

#ifdef __cplusplus
extern "C" {
#endif

#include "test/harness_test.h"
#include "test/insulation_logic.h"

#ifndef INSULATION_RAMP_MS
#define INSULATION_RAMP_MS       50U    /* settle after HV enable, before read  */
#endif
#ifndef INSULATION_DISCHARGE_MS
#define INSULATION_DISCHARGE_MS  200U   /* mandatory bleed time before relay sw  */
#endif

/* Acceptance threshold (Mohm). TUNE per harness standard. */
#ifndef INSULATION_R_MIN_MOHM
#define INSULATION_R_MIN_MOHM    100.0f
#endif

/* Sense-divider constants for the (informational) leakage -> ohms estimate.
 * R_series ~= 1 Mohm makes 10 Mohm insulation land at 0.045 V across R3004. */
#ifndef INSULATION_R_BOTTOM_OHM
#define INSULATION_R_BOTTOM_OHM  1000.0f     /* R3004                          */
#endif
#ifndef INSULATION_R_SERIES_OHM
#define INSULATION_R_SERIES_OHM  1000000.0f  /* effective leakage-path series  */
#endif
#ifndef INSULATION_V_FULL
#define INSULATION_V_FULL        500.0f      /* HV at full-scale DAC           */
#endif

/* Stimulus used by a full insulation run, as a fraction of full scale. INSULATION_
 * V_PASS_MAX is worked out for 500 V, so a lower stimulus would silently relax
 * the 10 Mohm limit (250 V -> ~4.5 Mohm). The verdict now scales the limit with
 * the applied voltage, but the product is a 500 V test: run at full scale. */
#ifndef INSULATION_RUN_FRACTION
#define INSULATION_RUN_FRACTION  1.0f
#endif
/* Below this the pass limit (0.045 V x fraction) is only a few ADC counts
 * (12-bit, 5 V: 1.2 mV/count) and the verdict is not trustworthy: refuse. */
#ifndef INSULATION_MIN_FRACTION
#define INSULATION_MIN_FRACTION  0.1f
#endif

/* HV_Sense = HV x R3003 / (R3001 + R3003) = HV x 5 k / 10.005 M. */
#define INSULATION_HV_SENSE_RATIO   (5000.0f / 10005000.0f)

/* Self-test stimulus: 20 % of full scale (100 V), all relays open. */
#define INSULATION_SELFTEST_FRACTION  0.2f
#define INSULATION_SELFTEST_SETTLE_MS 100U

/* Per-net HV supervision. The rail monitor (HV_Sense, U301) is read before every
 * leakage measurement and the result is refused unless the rail is inside
 * 0.5x..1.5x of the expected level; it is read again after the measurement to
 * prove the rail did not collapse. After every net the rail must fall below
 * INSULATION_DISCHARGED_V (volts at the ADC = about 25 V on the rail) before the
 * relays are opened, within INSULATION_DISCHARGE_TIMEOUT_MS. All three are
 * bring-up tunable: the passive bleed time of the real card is not known yet. */
#ifndef INSULATION_RAIL_TIMEOUT_MS
#define INSULATION_RAIL_TIMEOUT_MS      500U
#endif
#ifndef INSULATION_DISCHARGED_V
#define INSULATION_DISCHARGED_V         0.0125f
#endif
#ifndef INSULATION_DISCHARGE_TIMEOUT_MS
#define INSULATION_DISCHARGE_TIMEOUT_MS 2000U
#endif

/* Hardware fault classes reported in InsulationResult_t.hw_fault. Any non-zero
 * value means the HV path itself misbehaved (not "the harness failed"), so the
 * caller must latch a fault and stop. */
#define INS_HW_NONE       0U
#define INS_HW_BUS        1U   /* relay expander (I2C) access failed               */
#define INS_HW_SPI        2U   /* DAC / ADC (SPI) access failed                    */
#define INS_HW_RAIL       3U   /* rail never reached, or left, the expected level  */
#define INS_HW_DISCHARGE  4U   /* rail did not fall to the discharged level        */

typedef struct
{
  uint16_t      sense_code;        /* leakage-node (HV_RET) raw code         */
  float         sense_volts;       /* leakage-node volts                     */
  float         insulation_mohm;   /* approximate estimate (see .c)          */
  TestVerdict_t verdict;
  uint8_t       hw_fault;          /* INS_HW_*: HV path fault, 0 = none      */
  float         rail_volts;        /* HV_Sense (at the ADC) at measurement   */
} InsulationResult_t;

/**
  * @brief  Apply a controlled stress between two conductors on one HV board and
  *         measure. v_fraction sets the HV DAC (0.0..1.0 of full scale).
  * @param  board       HV board index (0..BOARD_HV_COUNT-1)
  * @param  inject_pin  1..64 inject side
  * @param  return_pin  1..64 return side
  * @param  v_fraction  HV program fraction
  * @param  res         result out
  * @note   Always discharges and opens relays before returning, even on error.
  */
HAL_StatusTypeDef Insulation_TestPair(uint8_t board, uint8_t inject_pin,
                                      uint8_t return_pin, float v_fraction,
                                      InsulationResult_t *res);

/**
  * @brief  Test one net against every other conductor on the board.
  * @param  inject_pin   1..64 inject side (the net's HS pin)
  * @param  return_mask  bit (pin-1) set = close that return relay; build it as
  *                      "every return pin except the net's own". Must be non-zero
  *                      (no closed return relay reads ~0 V = false PASS).
  */
HAL_StatusTypeDef Insulation_TestNet(uint8_t board, uint8_t inject_pin,
                                     uint64_t return_mask, float v_fraction,
                                     InsulationResult_t *res);

/**
  * @brief  Prove the HV path end to end before a run: with every relay open,
  *         program INSULATION_SELFTEST_FRACTION and read the rail monitor
  *         (HV_Sense). If the DAC chip-select, the rail-ADC chip-select or the
  *         card enable is wrong, the rail never answers and this fails.
  * @param  v_idle : [out] HV_Sense before energising (volts), may be NULL.
  * @param  v_hv   : [out] HV_Sense while energised (volts), may be NULL.
  * @retval HAL_OK the rail rose to the expected level; HAL_ERROR otherwise.
  *         The card is always returned to 0 V / relays open.
  */
HAL_StatusTypeDef Insulation_HvSelfTest(uint8_t board, float *v_idle, float *v_hv);

#ifdef __cplusplus
}
#endif

#endif /* __INSULATION_H */