/* Host-side unit tests for the hardware-free firmware logic.
 *
 *   tests\fw_host\run_tests.cmd        (MSVC)   or   gcc -I Core/Inc ... (see README.md)
 *
 * They cover the rules that decide PASS/FAIL and which relays close, because those
 * are the ones a wrong edit turns into a false PASS on a 500 V instrument.
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "app/run_logic.h"
#include "test/insulation_logic.h"

static int g_fail, g_run;

#define CHECK(cond) do { g_run++; if (!(cond)) { g_fail++; \
    printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); } } while (0)

/* ---- a tiny in-memory netlist for the planner ---------------------------- */
static uint16_t NH[64], NL[64];
static uint16_t NN;
static void nl_clear(void) { NN = 0; }
static void nl_add(uint16_t h, uint16_t l) { NH[NN] = h; NL[NN] = l; NN++; }
static int nl_get(uint16_t i, uint16_t *h, uint16_t *l)
{
  if (i >= NN) { return -1; }
  *h = NH[i]; *l = NL[i];
  return 0;
}

#define ALL64   0xFFFFFFFFFFFFFFFFULL
#define BIT(p)  (1ULL << ((p) - 1))

static void test_insul_wire(void)
{
  CHECK(RunLogic_InsulMohmToWire(0.0f) == 0);
  CHECK(RunLogic_InsulMohmToWire(-3.0f) == 0);
  CHECK(RunLogic_InsulMohmToWire(NAN) == 0);
  CHECK(RunLogic_InsulMohmToWire(0.001f) == 1000000);
  CHECK(RunLogic_InsulMohmToWire(2.0f) == 2000000000LL);
  /* the wire field is int64 now: a real 10 MOhm limit/reading (1e10 mohm) fits, no int32 clamp */
  CHECK(RunLogic_InsulMohmToWire(2.2f) > INT32_MAX);
  CHECK(llabs(RunLogic_InsulMohmToWire(10.0f) - 10000000000LL) < 2000LL);   /* float rounding */
  CHECK(RunLogic_InsulMohmToWire(9999.0f) > 9.9e12);       /* "negligible leakage" sentinel, ~9.999e12 */
  CHECK(RunLogic_InsulMohmToWire(INFINITY) == INT64_MAX);
  CHECK(RunLogic_InsulMohmToWire(1.0e30f) == INT64_MAX);
}

static void test_res_wire(void)
{
  int32_t v = 123;
  CHECK(RunLogic_ResMohmToWire(0.1f, &v) == 0 && v == 100);
  CHECK(RunLogic_ResMohmToWire(5.0f, &v) == 0 && v == 5000);
  CHECK(RunLogic_ResMohmToWire(-0.5f, &v) == 0 && v == -500);
  CHECK(RunLogic_ResMohmToWire(NAN, &v) == 1 && v == 0);   /* never a usable number */
  CHECK(RunLogic_ResMohmToWire(1.0e12f, &v) == 0 && v == INT32_MAX);
  CHECK(RunLogic_ResMohmToWire(-1.0e12f, &v) == 0 && v == INT32_MIN);
  CHECK(RunLogic_ResMohmToWire(INFINITY, &v) == 0 && v == INT32_MAX);
}

static void test_return_mask(void)
{
  /* straight wires: only the net's own relay is left open */
  nl_clear(); nl_add(1, 1); nl_add(2, 2); nl_add(3, 3);
  CHECK(RunLogic_ReturnMask(nl_get, NN, 3, 3, 0, 64) == (ALL64 & ~BIT(3)));
  CHECK(RunLogic_ReturnMask(nl_get, NN, 1, 1, 0, 64) == (ALL64 & ~BIT(1)));

  /* Y branch: one source, three destinations = ONE net, all three LS are "own" */
  nl_clear(); nl_add(5, 5); nl_add(5, 6); nl_add(5, 7); nl_add(9, 9);
  CHECK(RunLogic_ReturnMask(nl_get, NN, 5, 6, 0, 64) == (ALL64 & ~(BIT(5) | BIT(6) | BIT(7))));
  CHECK(RunLogic_ReturnMask(nl_get, NN, 9, 9, 0, 64) == (ALL64 & ~BIT(9)));

  /* merge: two sources into one destination */
  nl_clear(); nl_add(1, 1); nl_add(2, 1);
  CHECK(RunLogic_ReturnMask(nl_get, NN, 2, 1, 0, 64) == (ALL64 & ~BIT(1)));

  /* chained connectivity (needs two passes of the grouping) */
  nl_clear(); nl_add(2, 11); nl_add(1, 10); nl_add(2, 10);
  CHECK(RunLogic_ReturnMask(nl_get, NN, 1, 10, 0, 64) == (ALL64 & ~(BIT(10) | BIT(11))));

  /* second HV card: pins 65..128 map to relays 1..64 of board 1 */
  nl_clear(); nl_add(70, 70); nl_add(1, 1);
  CHECK(RunLogic_ReturnMask(nl_get, NN, 70, 70, 1, 64) == (ALL64 & ~BIT(6)));
  /* a net that lives on card 2 leaves card 1's relays untouched */
  CHECK(RunLogic_ReturnMask(nl_get, NN, 70, 70, 0, 64) == ALL64);

  /* never a mask that would silently be empty for a valid net, and bad pins give 0 */
  CHECK(RunLogic_ReturnMask(nl_get, NN, 0, 5, 0, 64) == 0ULL);
  CHECK(RunLogic_ReturnMask(nl_get, NN, 5, 300, 0, 64) == 0ULL);
  CHECK(RunLogic_ReturnMask(NULL, NN, 5, 5, 0, 64) == 0ULL);
}

static void test_insulation_rules(void)
{
  const float expect = 0.2455f;     /* HV_Sense at 500 V: 500 * 5k / 10.005M, volts at the ADC */

  /* the pass limit scales with the stimulus: 10 MOhm is 0.045 V at 500 V only */
  CHECK(fabsf(Insulation_PassLimitVolts(1.0f) - 0.045f) < 1e-6f);
  CHECK(fabsf(Insulation_PassLimitVolts(0.5f) - 0.0225f) < 1e-6f);

  /* rail plausibility: refuse a dead, weak or runaway rail */
  CHECK(Insulation_RailPlausible(0.0f, expect, expect) != 0);
  CHECK(Insulation_RailPlausible(0.0f, 0.0f, expect) == 0);              /* rail never rose */
  CHECK(Insulation_RailPlausible(0.0f, 0.5f * expect, expect) == 0);     /* only half way: refuse */
  CHECK(Insulation_RailPlausible(0.0f, 0.6f * expect, expect) != 0);
  CHECK(Insulation_RailPlausible(0.0f, 1.6f * expect, expect) == 0);     /* runaway */
  CHECK(Insulation_RailPlausible(0.2f * expect, expect, expect) == 0);   /* rail stuck on while idle */
}

static void test_i64_text(void)
{
  char     b[24];
  int64_t  v = 12345;

  CHECK(RunLogic_FormatI64(b, sizeof b, 0) == 1 && strcmp(b, "0") == 0);
  CHECK(RunLogic_FormatI64(b, sizeof b, 10000000000LL) == 11 && strcmp(b, "10000000000") == 0);
  CHECK(RunLogic_FormatI64(b, sizeof b, -42) == 3 && strcmp(b, "-42") == 0);
  CHECK(strcmp((RunLogic_FormatI64(b, sizeof b, INT64_MAX), b), "9223372036854775807") == 0);
  CHECK(strcmp((RunLogic_FormatI64(b, sizeof b, INT64_MIN), b), "-9223372036854775808") == 0);
  CHECK(RunLogic_FormatI64(b, 5, 7) == 0 && b[0] == 0);          /* too small: refuses, never overruns */
  CHECK(RunLogic_FormatI64(NULL, 24, 7) == 0);

  CHECK(RunLogic_ParseI64("0", &v) == 0 && v == 0);
  CHECK(RunLogic_ParseI64("10000000000", &v) == 0 && v == 10000000000LL);
  CHECK(RunLogic_ParseI64("-5", &v) == 0 && v == -5);
  CHECK(RunLogic_ParseI64("+7", &v) == 0 && v == 7);
  CHECK(RunLogic_ParseI64("9223372036854775807", &v) == 0 && v == INT64_MAX);
  CHECK(RunLogic_ParseI64("-9223372036854775808", &v) == 0 && v == INT64_MIN);
  v = 99;
  CHECK(RunLogic_ParseI64("9223372036854775808", &v) == -1 && v == 99);    /* INT64_MAX + 1 */
  CHECK(RunLogic_ParseI64("-9223372036854775809", &v) == -1 && v == 99);   /* INT64_MIN - 1 */
  CHECK(RunLogic_ParseI64("99999999999999999999999", &v) == -1);           /* overflow */
  CHECK(RunLogic_ParseI64("", &v) == -1);
  CHECK(RunLogic_ParseI64("-", &v) == -1);
  CHECK(RunLogic_ParseI64("12a", &v) == -1);
  CHECK(RunLogic_ParseI64("1 2", &v) == -1);
  CHECK(RunLogic_ParseI64("1e10", &v) == -1);
  CHECK(RunLogic_ParseI64(NULL, &v) == -1 && RunLogic_ParseI64("1", NULL) == -1);
  CHECK(v == 99);                                                          /* never touched on failure */

  /* round trip across the limit range */
  {
    const int64_t t[] = { 0, 1, -1, 100000000LL, 10000000000LL, 40000000000LL, INT64_MAX, INT64_MIN };
    size_t i;
    for (i = 0; i < sizeof t / sizeof t[0]; i++)
    {
      int64_t back = 7;
      RunLogic_FormatI64(b, sizeof b, t[i]);
      CHECK(RunLogic_ParseI64(b, &back) == 0 && back == t[i]);
    }
  }
}

static void test_insulation_limit(void)
{
  /* the default limit IS the board decision: bit-for-bit the old constant */
  CHECK(INSULATION_LIMIT_DEFAULT_MOHM == 10000000000LL);
  CHECK(Insulation_PassLimitVoltsFor(1.0f, INSULATION_LIMIT_DEFAULT_MOHM) == Insulation_PassLimitVolts(1.0f));
  CHECK(Insulation_PassLimitVoltsFor(0.5f, INSULATION_LIMIT_DEFAULT_MOHM) == Insulation_PassLimitVolts(0.5f));

  /* a stricter (higher) limit means a LOWER leakage voltage is already a fail, and vice versa */
  CHECK(Insulation_PassLimitVoltsFor(1.0f, 20000000000LL) < Insulation_PassLimitVolts(1.0f));
  CHECK(Insulation_PassLimitVoltsFor(1.0f,  5000000000LL) > Insulation_PassLimitVolts(1.0f));
  /* monotonic over the whole allowed range */
  {
    int64_t m;
    float   prev = 1.0e9f;
    for (m = INSULATION_LIMIT_MIN_MOHM; m <= INSULATION_LIMIT_MAX_MOHM; m += 1000000000LL)
    {
      float v = Insulation_PassLimitVoltsFor(1.0f, m);
      CHECK(v < prev);
      prev = v;
    }
  }
  /* sanity of the model: 1 MOhm limit ~ 0.045 * 11/2 = 0.2475 V; 40 MOhm ~ 12 mV */
  CHECK(fabsf(Insulation_PassLimitVoltsFor(1.0f, 1000000000LL) - 0.2475f) < 0.001f);
  CHECK(fabsf(Insulation_PassLimitVoltsFor(1.0f, INSULATION_LIMIT_MAX_MOHM) - 0.01207f) < 0.0005f);
  /* the upper bound is exactly what stays above the "too few ADC counts" refusal */
  CHECK(Insulation_PassLimitVoltsFor(1.0f, INSULATION_LIMIT_MAX_MOHM) >= INSULATION_MIN_PASS_V);

  /* range check: a limit the hardware cannot resolve is refused, never clamped */
  CHECK(Insulation_LimitValid(INSULATION_LIMIT_DEFAULT_MOHM) != 0);
  CHECK(Insulation_LimitValid(INSULATION_LIMIT_MIN_MOHM) != 0);
  CHECK(Insulation_LimitValid(INSULATION_LIMIT_MAX_MOHM) != 0);
  CHECK(Insulation_LimitValid(INSULATION_LIMIT_MIN_MOHM - 1) == 0);
  CHECK(Insulation_LimitValid(INSULATION_LIMIT_MAX_MOHM + 1) == 0);
  CHECK(Insulation_LimitValid(0) == 0);                      /* 0 would make every net pass */
  CHECK(Insulation_LimitValid(-1) == 0);
  CHECK(Insulation_LimitValid(INT64_MAX) == 0);
  CHECK(Insulation_LimitValid(INT64_MIN) == 0);
}

int main(void)
{
  test_insul_wire();
  test_res_wire();
  test_return_mask();
  test_insulation_rules();
  test_i64_text();
  test_insulation_limit();
  printf("%d checks, %d failed\n", g_run, g_fail);
  return g_fail != 0;
}
