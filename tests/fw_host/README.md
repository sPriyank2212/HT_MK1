# Host-side firmware logic tests

`test_run_logic.c` checks the hardware-free rules that decide PASS/FAIL and which HV relays close:

* `app/run_logic.c`: wire-value conversion (clamping, NaN) and the return-relay planner
* `test/insulation_logic.h`: the pass limit and the "is the rail really up" check

Run from the repository root (Visual Studio 2022 Community, MSVC):

    tests\fw_host\run_tests.cmd

Any C11 compiler works: `gcc -I Core/Inc tests/fw_host/test_run_logic.c Core/Src/app/run_logic.c -lm`.
These do not replace bring-up on a real card (see PROJECT_LOG.md BU-13 .. BU-15).
