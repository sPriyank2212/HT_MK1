/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    run_logic.c
  * @brief   Pure helpers of the run loops. See run_logic.h.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "app/run_logic.h"

/* Largest float below 2^31: anything at or above this would overflow int32. */
#define RL_F32_MAX_BELOW_2P31   2147483520.0f

/* Largest float below 2^63: anything at or above this would overflow int64. */
#define RL_F32_MAX_BELOW_2P63   9223371487098961920.0f

int64_t RunLogic_InsulMohmToWire(float mohm)
{
  float v = mohm * 1.0e9f;                          /* Mohm -> mohm */
  if (!(v > 0.0f)) { return 0; }                    /* also catches NaN */
  if (v >= RL_F32_MAX_BELOW_2P63) { return INT64_MAX; }
  return (int64_t)v;
}

size_t RunLogic_FormatI64(char *buf, size_t cap, int64_t v)
{
  char     tmp[20];
  uint8_t  n = 0U;
  uint64_t mag;
  size_t   i = 0U;

  if (buf == NULL || cap == 0U) { return 0U; }
  if (cap < 21U)                { buf[0] = '\0'; return 0U; }

  if (v < 0)
  {
    buf[i++] = '-';
    mag = (v == INT64_MIN) ? 9223372036854775808ULL : (uint64_t)(-v);
  }
  else
  {
    mag = (uint64_t)v;
  }
  do
  {
    tmp[n++] = (char)('0' + (mag % 10U));
    mag /= 10U;
  } while (mag != 0U);

  while (n > 0U) { buf[i++] = tmp[--n]; }
  buf[i] = '\0';
  return i;
}

int RunLogic_ParseI64(const char *s, int64_t *v)
{
  uint64_t mag = 0U;
  uint8_t  neg = 0U;

  if (s == NULL || v == NULL || *s == '\0') { return -1; }
  if (*s == '-')      { neg = 1U; s++; }
  else if (*s == '+') { s++; }
  if (*s == '\0') { return -1; }
  while (*s != '\0')
  {
    if (*s < '0' || *s > '9') { return -1; }
    if (mag > (UINT64_MAX - (uint64_t)(*s - '0')) / 10U) { return -1; }   /* overflow */
    mag = mag * 10U + (uint64_t)(*s - '0');
    s++;
  }
  if (neg != 0U)
  {
    if (mag > 9223372036854775808ULL) { return -1; }
    *v = (mag == 9223372036854775808ULL) ? INT64_MIN : -(int64_t)mag;
  }
  else
  {
    if (mag > (uint64_t)INT64_MAX) { return -1; }
    *v = (int64_t)mag;
  }
  return 0;
}

int RunLogic_ResMohmToWire(float ohm, int32_t *out)
{
  float v = ohm * 1000.0f;
  if (!(v == v))                { *out = 0;         return 1; }   /* NaN */
  if (v >=  RL_F32_MAX_BELOW_2P31) { *out = INT32_MAX; return 0; }
  if (v <= -RL_F32_MAX_BELOW_2P31) { *out = INT32_MIN; return 0; }
  *out = (int32_t)v;
  return 0;
}

static uint8_t pin_test(const uint8_t *set, uint16_t pin)
{
  return (uint8_t)((set[(pin - 1U) >> 3] >> ((pin - 1U) & 7U)) & 1U);
}

static void pin_set(uint8_t *set, uint16_t pin)
{
  set[(pin - 1U) >> 3] |= (uint8_t)(1U << ((pin - 1U) & 7U));
}

uint64_t RunLogic_ReturnMask(RunLogic_NetGet get, uint16_t n, uint16_t hi, uint16_t lo,
                             uint8_t board, uint16_t pins_per_board)
{
  uint8_t  hs[32] = {0}, ls[32] = {0};   /* pin 1..256 bitsets */
  uint16_t i, h, l, p;
  uint8_t  changed;
  uint64_t mask = 0ULL;

  if (get == NULL || hi < 1U || hi > 256U || lo < 1U || lo > 256U) { return 0ULL; }

  pin_set(hs, hi);
  pin_set(ls, lo);
  do
  {
    changed = 0U;
    for (i = 0U; i < n; i++)
    {
      if (get(i, &h, &l) != 0 || h < 1U || h > 256U || l < 1U || l > 256U) { continue; }
      if (pin_test(hs, h) != pin_test(ls, l))
      {
        pin_set(hs, h); pin_set(ls, l); changed = 1U;
      }
    }
  } while (changed != 0U);

  for (p = 1U; p <= pins_per_board && p <= 64U; p++)
  {
    uint16_t flat = (uint16_t)(board * pins_per_board + p);
    if (flat <= 256U && pin_test(ls, flat) == 0U) { mask |= (1ULL << (p - 1U)); }
  }
  return mask;
}
