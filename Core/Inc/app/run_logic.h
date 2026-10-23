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
  * @brief  Insulation reading (megohms, float) -> protocol milliohms (int32).
  * @note   The wire field tops out at 2.147 MOhm, so larger readings clamp to
  *         INT32_MAX (the verdict beside the number is authoritative). NaN,
  *         zero and negative readings give 0. Never undefined behaviour.
  */
int32_t RunLogic_InsulMohmToWire(float mohm);

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
