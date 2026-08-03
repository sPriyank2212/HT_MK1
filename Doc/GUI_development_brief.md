# HT_MK1 Operator GUI — Development Brief

**For:** the AI/developer building the GUI · **From:** the firmware side
**Visual reference:** `Doc/HT_MK1_GUI_Proposal.html` (mock-up — screens and layout)
**Status:** protocol defined below, firmware side not yet implemented

---

## 0. Read this first

You are building the **operator GUI** for an automated wire-harness tester. You are **not**
writing firmware, and you will **not** have the instrument on your desk.

The single most important thing to understand: **the communication protocol in §3 does not
exist yet on either side.** It is a contract. The firmware team implements its half; you
implement yours and develop against the simulator described in §4. Build to the contract,
not to guesses about the hardware.

If something in this brief is ambiguous, **do not invent behaviour** — list the question and
hand it back. A wrong assumption here becomes a wrong assumption in a machine that puts
500 V across a harness.

---

## 1. What the machine does

It tests wire harnesses — the bundles of wires in a vehicle or aircraft. Up to **256 wires**
at once. Three tests, always in this order:

| # | Test | Question it answers | Typical result |
|---|---|---|---|
| 1 | **Continuity** | Is the wire there, and does it go where the drawing says? | connected / open / wrong destination |
| 2 | **Resistance** | Is the wire *good*, or thinned by corrosion or a partial break? | milliohms, pass/fail against limits |
| 3 | **Insulation** | Does 500 V leak between wires that should be isolated? | leakage resistance, pass/fail |

**Two physical fixtures.** Tests 1 and 2 run with the harness plugged into the **Matrix**
connector (J-MTX). Test 3 needs it moved to the **HV** connector (J-HV). The operator
physically moves the harness between them. **The GUI must make this handover explicit and
must not let the operator skip it** — insulation cannot be tested from the Matrix fixture,
and 500 V appearing while someone thinks they are in continuity mode is the worst thing this
machine can do.

**Netlist.** A harness is described by a netlist: which pin connects to which. Two modes:
- **Verify** — load a known-good netlist, check the harness matches
- **Discover** — unknown harness, scan all 256×256 combinations and build the netlist

---

## 2. What to build

Follow `HT_MK1_GUI_Proposal.html` for layout and screen inventory. Functionally:

| Screen | Must do |
|---|---|
| **Run / fixture sequence** | Guide the operator through: load harness → continuity → resistance → **move to HV fixture** → insulation → report. Show which fixture is required *now* |
| **Continuity** | Per-net pass/open/short; the harness wiring view; net inspector; discovered-netlist view for discover mode |
| **Resistance** | Per-net milliohms, distribution, ranked by margin to limit, and the measurement conditions used (current, gain) |
| **HV insulation** | Per-net leakage, relay state, rail voltage, and an explicit arm/confirm step before energising |
| **Faults** | Live fault list with the codes from the operation document (F01–F14) |
| **Netlist manager** | Load, edit, save; separate Matrix and HV netlists |
| **Diagnostics** | Bus map, card presence, manual switch/relay control, calibration values, instrument limits |
| **History** | Run history, first-pass yield, fault pareto |

### Non-negotiable safety behaviour

1. **HV is armed by an explicit, deliberate action** — never a side effect of navigation.
2. **The HV state is always visible**, on every screen, whenever the rail is above ~50 V.
3. **An abort control is reachable at all times** during any HV operation.
4. If the link to the instrument drops mid-test, the GUI shows **"state unknown"** — never
   "safe". It cannot know.
5. Insulation controls are **disabled** until the GUI has seen `EVT FIXTURE HV` (§3.4).

---

## 3. Protocol contract

Line-based ASCII over the USB virtual COM port. **115200 8N1.** Every message is one line
ending `\n`. Fields are space-separated. This is deliberately simple so it can be driven
from a terminal by hand during bring-up.

### 3.1 Direction and framing

| Prefix | Direction | Meaning |
|---|---|---|
| `>` | GUI → instrument | command |
| `<` | instrument → GUI | direct reply to a command |
| `!` | instrument → GUI | asynchronous event (may arrive at any time) |
| `#` | instrument → GUI | human-readable log line — display, do not parse |

Every `>` command gets exactly one `<` reply, in order. Events `!` are independent.

### 3.2 Commands

```
>PING                          -> <PONG
>ID                            -> <ID HT_MK1 fw=<semver> proto=1
>STATUS                        -> <STATUS state=<idle|running|fault|hv_armed> fixture=<none|mtx|hv> hv_mv=<int>
>SAFE                          -> <OK            force everything to the safe state
>ABORT                         -> <OK            stop the running test now

>NETLIST BEGIN <n>             -> <OK            start upload of n entries
>NETLIST ADD <hi> <lo>         -> <OK
>NETLIST END                   -> <OK loaded=<n>
>NETLIST GET                   -> <NETLIST <n> then n lines of  <NET <hi> <lo>

>CONT RUN <verify|discover>    -> <OK started
>RES  RUN                      -> <OK started
>INSUL ARM                     -> <OK armed     required before INSUL RUN
>INSUL RUN                     -> <OK started
>HV SET <millivolts>           -> <OK           0 = off; ramping is the firmware's job

>MANUAL PATH <hi> <lo>         -> <OK           close one matrix path, diagnostics only
>MANUAL RELAY <board> <n> <0|1>-> <OK
>MANUAL OFF                    -> <OK

>CAL GET                       -> <CAL current_ua=<int> gain=<int> rref_mohm=<int>
>LIMITS GET                    -> <LIMITS r_max_mohm=<int> ins_min_mohm=<int>
>LIMITS SET r_max_mohm=<int> ins_min_mohm=<int>  -> <OK
```

Errors: `<ERR <code> <text>` — e.g. `<ERR EFIXTURE harness is on the matrix fixture`.

Defined codes: `EBUSY`, `EFIXTURE`, `ENOTARMED`, `ERANGE`, `EHW`, `ESYNTAX`.

### 3.3 Result events

Results stream as they are measured — do **not** wait for the run to finish before showing
anything. A 256×256 discovery scan takes tens of seconds.

```
!PROGRESS <done> <total>
!CONT <hi> <lo> <pass|open|short>
!RES  <hi> <lo> <milliohms> <pass|fail_high|fail_low>
!INSUL <net> <leak_mohm> <pass|fail>
!FAULT <code> <text>                   e.g.  !FAULT F04 insulation low on net 37
!DONE <cont|res|insul> <passed> <failed>
```

### 3.4 State events

```
!STATE <idle|running|fault|hv_armed>
!FIXTURE <none|mtx|hv>                 which fixture the instrument expects NOW
!HV <millivolts>                       rail voltage, sent on every change >10 mV
!SAFE                                  everything forced safe (abort, fault, or command)
```

### 3.5 Rules you must implement

1. **Never assume a command succeeded** — wait for `<`. Time out at **2 s** and surface it.
2. **`!HV` above 50 000 mV means the rail is live.** Show the HV indicator, everywhere.
3. **If the port closes or 5 s pass with no traffic**, show "link lost — state unknown" and
   disable every control that could energise anything.
4. **Reconnect must re-issue `>STATUS`** before enabling controls. Never assume idle.
5. Log every line sent and received to a session file. Field failures get diagnosed from it.

---

## 4. How to develop without hardware

**Write a simulator first.** A small script that opens a pseudo-serial port (or TCP socket),
speaks §3, and can be told to produce: a clean pass, a run with two opens and one short, a
resistance fail, an insulation fail, and a mid-run disconnect.

Build the whole GUI against it. When real hardware appears, only the transport changes.

The simulator is a **deliverable**, not scaffolding — it is how the GUI gets regression
tested afterwards.

---

## 5. Task breakdown

Each task is independently reviewable. Do them in order.

| # | Task | Done when |
|---|---|---|
| **1** | Protocol library + simulator | Every command in §3 round-trips; all five scenarios reproducible; unit tests pass |
| **2** | Connection manager | Connect/disconnect/reconnect, 2 s command timeout, 5 s link-loss detection, `>STATUS` on reconnect, session logging |
| **3** | Shell + navigation | Screens from the mock-up, persistent HV indicator, always-reachable abort |
| **4** | Netlist manager | Load/edit/save, upload via `>NETLIST`, download via `>NETLIST GET`, separate MTX and HV lists |
| **5** | Continuity screen | Verify + discover, live `!CONT` streaming, wiring view, net inspector |
| **6** | Resistance screen | Live `!RES`, distribution, ranked-by-margin, measurement conditions from `>CAL GET` |
| **7** | HV insulation screen | Arm/confirm flow, `!INSUL` streaming, relay state, rail display, abort |
| **8** | Fixture sequencing | Enforces the MTX → HV handover; insulation locked until `!FIXTURE hv` |
| **9** | Faults + history | Live faults with F-codes, run history, yield, pareto |
| **10** | Diagnostics | Bus map, card presence, manual switch/relay, calibration, limits |

**Stop after task 2 and hand back for review.** If the protocol layer is wrong, everything
above it is wrong, and it is much cheaper to find that at task 2 than at task 10.

---

## 6. How your work gets verified

Submit each task with:

1. **What you built** — one paragraph, plus anything you changed from this brief and why
2. **How to run it** — exact commands, from a clean checkout
3. **The simulator scenario** that demonstrates it
4. **Open questions** — anything you had to assume

Review checks, in order:

| | |
|---|---|
| **Protocol conformance** | Byte-for-byte against §3. Extra fields, reordered fields and missing `\n` all count as failures |
| **Safety behaviour** | The five rules in §2 and §3.5. Tested by pulling the simulator's plug mid-run |
| **Failure handling** | Link loss, timeout, malformed line, unexpected event. The GUI must degrade to "unknown", never to "safe" |
| **No invented behaviour** | Anything not in this brief must appear in your open-questions list |

**Rejected outright:** a GUI that shows a safe state it has not been told, that enables HV
controls before `!FIXTURE hv`, or that hides a link failure.

---

## 7. Out of scope

- Firmware changes — the instrument side is implemented by the firmware team
- Protocol changes — propose them, do not make them
- Anything to do with the actual measurement physics
- Cloud, multi-user, authentication — single operator, single machine, local

---

## 8. Open questions for the firmware side

Recorded here so they are visible; **do not build around them**, ask.

1. Discovery scan takes tens of seconds. Is `!PROGRESS` fine-grained enough, or does the GUI
   need per-pin position?
2. Should the netlist persist in instrument flash, or be uploaded every run?
3. `>MANUAL RELAY` on a live HV card — should the firmware refuse it outright, or is a
   GUI-side confirm sufficient?
4. Run history — stored on the instrument or the GUI host?

---

## 9. Context files

Read-only, for understanding. Do not edit.

| | |
|---|---|
| `Doc/HT_MK1_GUI_Proposal.html` | Visual mock-up — layout and screen inventory |
| `Doc/Harness_Tester_Operation_Document_v1.4.docx` | How tests actually run; **fault codes F01–F14 are here** |
| `README.md` | Project map |

The firmware, schematics and datasheets are not needed to build the GUI. If you think you
need them, that probably means something is missing from this brief — say so.
