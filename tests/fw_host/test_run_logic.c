/* Host-side unit tests for the hardware-free firmware logic.
 *
 *   tests\fw_host\run_tests.cmd        (MSVC)   or   gcc -I Core/Inc ... (see README.md)
 *
 * They cover the rules that decide PASS/FAIL and which relays close, because those
 * are the ones a wrong edit turns into a false PASS on a 500 V instrument.
 */
#include <math.h>
#include <stdio.h>
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
  CHECK(RunLogic_InsulMohmToWire(2.0f) == 2000000000);
  CHECK(RunLogic_InsulMohmToWire(2.2f) == INT32_MAX);      /* > 2.147 MOhm clamps */
  CHECK(RunLogic_InsulMohmToWire(9999.0f) == INT32_MAX);   /* "negligible leakage" sentinel */
  CHECK(RunLogic_InsulMohmToWire(INFINITY) == INT32_MAX);
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

int main(void)
{
  test_insul_wire();
  test_res_wire();
  test_return_mask();
  test_insulation_rules();
  printf("%d checks, %d failed\n", g_run, g_fail);
  return g_fail != 0;
}
