/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    kelvin.h
  * @brief   4-wire (Kelvin) resistance measurement. Forces a known current via
  *          the ADS124S08's OWN internal IDAC1 (routed to AIN9, which the
  *          schematic wires directly to HI_COM) and reads the drop across
  *          HI_SENSE/LO_SENSE on the same chip - a true 4-wire measurement,
  *          since the sense taps carry no force current and so exclude
  *          mux/contact resistance from the force path.
  *
  *          FW-12 (2026-08-12): the Control-Card DAC8775 that used to force
  *          this current has been removed from the schematic - see
  *          Doc/idac_current_source.md. The excitation and the measurement
  *          are now the same chip.
  *
  *          R = V / I_force, with V from the ADS124S08 at auto-ranged PGA gain
  *          and I_force fixed at KELVIN_FORCE_CURRENT_A - 2 mA, the IDAC's
  *          hard ceiling (IDACMAG code 1001, there is no higher code; see
  *          Doc/idac_current_source.md S3). Not a TUNE placeholder like the
  *          old DAC8775 code was - this is the actual, only current the
  *          hardware can produce.
  *
  *          HW-04 (landed): R131 (KELVIN_CAL_R_REF_OHM, 0.01%) sits in the
  *          same current loop as the DUT (IDAC -> HI_COM -> DUT -> LO_COM ->
  *          R131 -> GND) and is tapped on AIN8. Every measurement also reads
  *          that channel and computes R ratiometrically against R131
  *          (ADS124S08_OhmsRatiometric) - this cancels the IDAC's own
  *          tolerance (+/-3% worst case) entirely, leaving R131's 0.01% as
  *          the accuracy floor instead. If the reference-channel read fails
  *          for any reason, the result falls back to the older R = V / I_force
  *          estimate (KelvinResult_t.ratiometric reports which one was used).
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __KELVIN_H
#define __KELVIN_H

#ifdef __cplusplus
extern "C" {
#endif

#include "test/harness_test.h"

#ifndef KELVIN_SETTLE_MS
#define KELVIN_SETTLE_MS        2U
#endif

/* Excitation via the ADS124S08's own IDAC1, routed to AIN9 (= HI_COM).
 * KELVIN_IDAC_MAG is the ADS124S08_IMAG_* code passed to ADS124S08_SetIdac();
 * KELVIN_FORCE_CURRENT_A is the amps that code actually produces, used for
 * ADS124S08_OhmsFromCurrent(). 2 mA (code 1001) is the highest magnitude the
 * IDAC has - not a tunable target, the hardware ceiling. See
 * Doc/idac_current_source.md S3. */
#ifndef KELVIN_IDAC_MAG
#define KELVIN_IDAC_MAG         ADS124S08_IMAG_2000UA
#endif
#ifndef KELVIN_FORCE_CURRENT_A
#define KELVIN_FORCE_CURRENT_A  0.002f       /* amps actually forced at KELVIN_IDAC_MAG */
#endif

/* HW-04: R131, the LO_COM pull-down (Matrix sheet, 1206 0.01%), tapped on
 * AIN8 for a ratiometric read. Carries the same excitation current as the
 * DUT, so its own tolerance - not the IDAC's - sets the accuracy floor. */
#ifndef KELVIN_CAL_R_REF_OHM
#define KELVIN_CAL_R_REF_OHM    100.0f
#endif
#ifndef KELVIN_CAL_R_REF_TOL_PCT
#define KELVIN_CAL_R_REF_TOL_PCT 0.01f
#endif

/* Acceptance limits (ohms). TUNE per harness spec. */
#ifndef KELVIN_R_MAX_OHM
#define KELVIN_R_MAX_OHM        5.0f
#endif

/* Reject a reading whose code saturates the PGA even at unity gain, rather
 * than report a number computed from a clipped conversion. */
#ifndef KELVIN_SATURATION_FRACTION
#define KELVIN_SATURATION_FRACTION  0.90f
#endif

typedef struct
{
  int32_t       code;           /* ADS124S08 code, excited minus zero-current */
  float         volts;          /* corresponding volts at the ADC input       */
  float         resistance_ohm; /* computed wire resistance                   */
  uint8_t       ratiometric;    /* 1 = resistance_ohm came from the real HW-04
                                  * ratiometric read against R131; 0 = the
                                  * reference-channel read failed and this
                                  * fell back to R = V / KELVIN_FORCE_CURRENT_A */
  TestVerdict_t verdict;
} KelvinResult_t;

/**
  * @brief  Measure one wire (hi_pin forced, lo_pin return).
  */
HAL_StatusTypeDef Kelvin_MeasurePair(uint16_t hi_pin, uint16_t lo_pin,
                                     KelvinResult_t *res);

#ifdef __cplusplus
}
#endif

#endif /* __KELVIN_H */