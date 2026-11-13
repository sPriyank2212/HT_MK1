/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    run_logic.h
  * @brief   Pure helpers of the run loops (tasks.c): wire-value conversion and
  *          the insulation return-relay planner. No HAL, no RTOS: compiled by the
  *          firmware and by the host-side unit tests (tests/fw_host).
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __RUN_LOGIC_H
#define __RUN_LOGIC_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

/** Netlist accessor: entry @p i -> (hi, lo). Returns 0 on success. */
typedef int (*RunLogic_NetGet)(uint16_t i, uint16_t *hi, uint16_t *lo);

/**
  * @brief  Insulation reading (megohms, float) -> protocol milliohms (int64).
  * @note   10 Mohm is 1e10 mohm, which does not fit int32, so the wire field is
  *         64-bit. Readings beyond the int64 range (the 9999 Mohm "negligible
  *         leakage" sentinel fits; only INFINITY/huge floats do not) clamp to
  *         INT64_MAX; the verdict beside the number is authoritative. NaN, zero
  *         and negative readings give 0. Never undefined behaviour.
  */
int64_t RunLogic_InsulMohmToWire(float mohm);

/**
  * @brief  Format a 64-bit signed value as decimal.
  * @note   Hand-rolled: this build links newlib-nano, whose printf has never been
  *         exercised with "%lld" here, and a wrong conversion would silently
  *         corrupt every !INSUL / LIMITS GET line.
  * @param  buf : [out] destination.
  * @param  cap : [in]  size of @p buf; 21 is always enough (sign + 19 digits + NUL).
  * @retval Characters written, excluding the NUL; 0 (and buf[0] = 0 when cap > 0)
  *         if @p buf is NULL or too small.
  */
size_t RunLogic_FormatI64(char *buf, size_t cap, int64_t v);

/**
  * @brief  Parse a decimal token into a 64-bit signed value.
  * @note   Accepts an optional leading '+' or '-' then digits only; no spaces,
  *         no trailing junk, nothing out of INT64_MIN..INT64_MAX. Hand-rolled for
  *         the same reason as RunLogic_FormatI64().
  * @retval 0 on success (*v set), -1 otherwise (*v untouched).
  */
int RunLogic_ParseI64(const char *s, int64_t *v);

/**
  * @brief  Resistance (ohms, float) -> protocol milliohms (int32), saturating.
  * @retval 0 on success, 1 when @p ohm is NaN (not a usable reading; *out = 0).
  */
int RunLogic_ResMohmToWire(float ohm, int32_t *out);

/**
  * @brief  Return-relay mask for the net containing (hi, lo): every LS pin of HV
  *         card @p board EXCEPT the net's own return pins.
  * @note   A net is the connected component of the netlist containing (hi, lo):
  *         pairs sharing an HS pin or an LS pin are one net (Y branch, merge,
  *         multi-drop). Closing no return relay would read ~0 V and give a false
  *         PASS, so a mask that would be empty is the caller's problem (the
  *         insulation sequence refuses a zero mask).
  * @param  get            netlist accessor.
  * @param  n              number of netlist entries.
  * @param  pins_per_board relays per HV card (64).
  * @retval bit (p-1) set = close return relay p of card @p board.
  */
uint64_t RunLogic_ReturnMask(RunLogic_NetGet get, uint16_t n, uint16_t hi, uint16_t lo,
                             uint8_t board, uint16_t pins_per_board);

#ifdef __cplusplus
}
#endif

#endif /* __RUN_LOGIC_H */
