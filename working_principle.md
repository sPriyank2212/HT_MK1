Here are tight descriptions with the actual end-to-end signal path for each. All three share the harness fixture; the difference is which sub-system drives it and how the result is judged.

1. ***Continuity test — "is the wire there?" (netlist + cross / one-to-many)
   What: For every expected HS[i] → LS[j] pair in the netlist, confirm a low-resistance wire exists. In cross / one-to-many mode you enable one HS and scan all LS, capturing every LS that reads connected — this reveals splices, multi-drop nets, and mis-wires (one source feeding several destinations).***

**Path (low-voltage, 3.3 V domain):**

+3.3V ─[10k pull-up]─ ADC_IN ─ Opto U3 (OPTO_CNTR=LOW) ─ HI_COM
   → Matrix HI mux (CD4067, chan = HI_S0..3, enable HI_EN[m] via U101@0x20)
   → HS pin → HARNESS WIRE → LS pin
   → Matrix LO mux (CD4067, LO_S0..3, LO_EN[k] via U102@0x21) → LO_COM
   → [pull-down] → GND
Sense: Control AD7476 U4 (SPI3) reads ADC_IN
Verdict: connected ≈ 1.5 V (pull-up/pull-down divider), open ≈ 3.3 V. Missing planned wire = OPEN (F06).

2. ***Precision resistance test — "what is the wire's resistance?"
   What: For each connected HS[i] → LS[j] (from the netlist or continuity discovery), inject a known current and measure the voltage drop across the wire — R = V_drop / I (Ohm's law). Used to catch partial breaks, corrosion, crimp/contact resistance, and undersized conductors that still "pass" continuity.***

Path (current-source mode, 3.3 V domain):

DAC8775 Ch.A (SPI2, current-source mode, 10 mA)
   → I_OUT → Opto U3 (OPTO_CNTR=HIGH → current path, pull-up disconnected) → HI_COM
   → Matrix HI mux (CD4067, chan = HI_S0..3, enable HI_EN[m] via U101@0x20)
   → HS pin → HARNESS WIRE → LS pin
   → Matrix LO mux (CD4067, LO_S0..3, LO_EN[k] via U102@0x21) → LO_COM → GND
Sense: Matrix AD7476 U33 (SPI1) reads V_drop at HI_COM
Compute: R_wire = V_drop / I − R_offset   (R_offset = the two CD4067 on-resistances, cal'd out)
Verdict: R_min ≤ R_wire ≤ R_max = PASS; > R_max = HIGH (F08) (partial break/corrosion); < R_min = LOW (F09) (parallel path or cal error).
Calibration: a known 100 Ω across the path sets the current/gain; the 0 Ω loopback captures R_offset.
Bring-up check (open): confirm the 2-mux drop stays < 3.3 V at 10 mA — if it clamps, lower the current.

Where it sits vs the others:

Continuity (Control U4 / SPI3, 3.3 V pull-up, OPTO_CNTR=LOW) — is the wire there?
Precision resistance (Matrix U33 / SPI1, DAC current source, OPTO_CNTR=HIGH) — how good is the wire?
HV insulation (HV U302 / SPI2-iso, 500 V reed-relay path) — is it isolated from everything else?
Note the same HI_COM node is shared: the Opto SPDT swaps it between the continuity pull-up (U4) and the resistance current-source (U33) via OPTO_CNTR. Continuity and resistance therefore can't run simultaneously — they're sequential passes on the same path.

Want me to fold this corrected three-test "Test Path Reference" into the v1.3 operation document?

3. ***HV test — insulation at 500 V
   What: Verify insulation resistance ≥ 10 MΩ between the net under test and every other conductor, at 500 V DC. Energise one net on the high side; tie all other conductors to the return; measure leakage.***

Path (high-voltage, isolated):

DAC8830 (SPI2-iso) → CA05P-5 → +500V
   → R3002 (1M) → INS_VIN → HS reed relay[n] (MHV05, 2N7002 via MCP23017 0x20-0x27)
   → H_PWR[n] → HARNESS conductor (net under test)
   → [insulation leakage] → adjacent conductor
   → L_PWR → LS reed relay → HV_RET → R3004 (1k) → GND
Return scheme: close ALL LS relays EXCEPT net n's own return
Leak sense: HV AD7476 U302 (SPI2-iso) reads V across R3004 (HV_RET)
Rail monitor: HV AD7476 U301 reads HV_Sense (10M:5k → 0.245 V @500V) confirms 500 V present
Verdict: V_HV_RET < 0.045 V = PASS (>10 MΩ); ≥ 0.045 V = FAIL; dead short ≈ 0.50 V (F04-CRITICAL).

One-line contrast: continuity & short are the same 3.3 V matrix scan read at Control-U4 (pass/fail logic differs); the HV test is the isolated 500 V reed-relay path on the HV card read at HV-U302. Continuity/short prove the wiring map; HV proves the wiring's isolation.

Want this as a one-page diagram/artifact you can share, or added into the operation document as a "Test Path Reference" section?
