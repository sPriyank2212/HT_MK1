# HT_MK1 Operator GUI — Development Brief

**For:** the AI/developer building the GUI · **From:** the firmware side
**Visual reference:** `Doc/HT_MK1_GUI_Proposal.html` (mock-up — screens and layout)
**Status:** protocol defined below · **instrument side implemented** (`Core/Src/app/proto.c`)
**§3 last reconciled against the firmware:** 2026-08-05 — §3 is normative, §8.1 is rationale

---

## 0. Read this first

You are building the **operator GUI** for an automated wire-harness tester. You are **not**
writing firmware, and you will **not** have the instrument on your desk.

The communication protocol in §3 is a **contract**. The instrument half is implemented and on
hardware; you implement the GUI half and develop against the simulator described in §4.
Build to the contract, not to guesses about the hardware.

Two deviations from an earlier draft, both now live in the firmware:

- **`>FIXTURE <none|mtx|hv>`** exists — the operator confirms through the GUI that the harness
  has been physically moved, and the instrument records it. `>INSUL ARM` is refused with
  `ERR EFIXTURE` until it has been told `hv`.
- **`>MANUAL RELAY`** is refused with `ERR EHW`. Driving a single HV relay by hand over a
  serial link while the rail may be live is not something the instrument will allow. Open
  question 3 in §8 is answered: the firmware refuses, a GUI confirm is not sufficient.

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
5. Insulation controls are **disabled** until the GUI has seen `!FIXTURE hv` (§3.4).

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

One exception: **`>NETLIST GET` replies with `1 + n` lines** — a `<NETLIST <n>` header followed
by `n` × `<NET <hi> <lo>`. The header tells you how many more `<` lines to expect. Nothing else
in the protocol does this.

### 3.2 Commands

```
>PING                          -> <PONG
>ID                            -> <ID HT_MK1 fw=<semver> proto=1
>STATUS                        -> <STATUS state=<idle|hv_armed> fixture=<none|mtx|hv> hv_mv=<int>
>SAFE                          -> <OK started   force everything to the safe state
>ABORT                         -> <OK           stop the running test now — see 3.2.1

>NETLIST BEGIN <n>             -> <OK           start upload of n entries, n <= 256
>NETLIST ADD <hi> <lo>         -> <OK
>NETLIST END                   -> <OK loaded=<n>
>NETLIST GET                   -> <NETLIST <n> then n lines of  <NET <hi> <lo>

>CONT RUN <verify|discover>    -> <OK started
>RES  RUN                      -> <OK started
>INSUL ARM                     -> <OK armed     required before INSUL RUN
>INSUL RUN                     -> <OK started
>HV SET <millivolts>           -> <OK           0 = off; ramping is the firmware's job

>FIXTURE <none|mtx|hv>         -> <OK           operator confirms the harness location
>MANUAL PATH <hi> <lo>         -> <OK started   close one matrix path, diagnostics only
>MANUAL RELAY <board> <n> <0|1>-> <ERR EHW      refused by design, see section 0
>MANUAL OFF                    -> <OK started

>CAL GET                       -> <CAL current_ua=<int> gain=<int> rref_mohm=<int>
>LIMITS GET                    -> <LIMITS r_max_mohm=<int> ins_min_mohm=<int>
>LIMITS SET r_max_mohm=<int> ins_min_mohm=<int>  -> <OK
```

`<OK started` is the literal reply for every command that is handed to the sequencer queue,
`<OK` for everything answered on the spot. Match both exactly — the difference is not
cosmetic, it tells you whether the instrument has begun work or merely recorded something.

`>STATUS` reports only `idle` or `hv_armed`. It does **not** report `running` or `fault`, even
while a run is executing — those two states reach you through `!STATE` and `!FAULT` only. On
reconnect (§3.5 rule 4) treat a `STATUS` of `idle` as "not armed", not as "not running", and
wait for the next event before concluding the instrument is quiet.

Errors: `<ERR <code> <text>` — e.g. `<ERR EFIXTURE harness is on the matrix fixture`.

Defined codes: `EBUSY`, `EFIXTURE`, `ENOTARMED`, `ERANGE`, `EHW`, `ESYNTAX`.

### 3.2.1 When a command is accepted

**Normative.** The firmware enforces every rule below; the simulator must reproduce them.
None of this is advisory — a GUI that assumes otherwise will look correct on the bench and
misbehave on the machine.

**Pins are 1-based, `1..256`.** `0` is invalid. Out of range gives `<ERR ERANGE pin out of
range` on `NETLIST ADD`, and `<ERR ERANGE pin` on `MANUAL PATH`.

**One run at a time; run commands are not queued.** While a run is in progress — accepted and
not yet `!DONE` — `CONT RUN`, `RES RUN` and `INSUL RUN` are refused with
`<ERR EBUSY a run is already in progress`. The refusal is final: nothing is remembered, and if
the operator still wants that run the GUI must issue it again after `!DONE`. `PING`, `ID`,
`STATUS`, `SAFE` and `ABORT` always work. Everything else is accepted and queued behind the
run.

> Side effect to expect: `CONT RUN` and `RES RUN` assert the matrix fixture *before* the busy
> check, so a refused run is still preceded by `!FIXTURE mtx` — and, if HV was armed, by
> `!HV 0` and `!SAFE` as well. An `EBUSY` is therefore not always event-free.

**`ABORT` is never queued.** It answers immediately — `<OK` while a run is in progress, or
`<OK started` when idle, where it instead queues a force-safe. The run stops at the next
measurement point, which is *roughly* one point away rather than instantaneous, and **still
emits its `!DONE`**. An aborted run is never a silent run; do not close out the run on the
`<OK`.

**A loaded netlist is required by `CONT RUN verify` and by `RES RUN`.** Without one, both give
`<ERR ERANGE no netlist`. `CONT RUN discover` needs no netlist — that is what it is for.
Capacity is 256 entries; `NETLIST BEGIN <n>` with `n > 256` gives `<ERR ERANGE too many
entries`, and an `ADD` beyond the promised `n` gives `<ERR ERANGE more entries than promised`.

**`HV SET` non-zero requires arming.** `HV SET 0` is accepted at any time. Any non-zero value
while unarmed is refused with `<ERR ENOTARMED INSUL ARM first`. Above 500000 gives
`<ERR ERANGE 0..500000 mV`. On success the `!HV <mv>` event is emitted **before** the `<OK`.

**`INSUL ARM` requires the HV fixture** — otherwise `<ERR EFIXTURE move harness to the HV
fixture`. On success: `<OK armed`, then `!STATE hv_armed`.

**`INSUL RUN` requires arming** — otherwise `<ERR ENOTARMED INSUL ARM first`.

**A fixture change invalidates arming.** If the fixture changes while armed, or with the rail
up, the firmware forces the hardware safe and emits, in this order:

```
!HV 0
!SAFE
!FIXTURE <new>
```

The arm is dropped. This holds whether the change came from `>FIXTURE` or implicitly from
`CONT RUN` / `RES RUN`. Re-declaring the fixture the instrument is already on changes nothing
and emits `!FIXTURE` alone. Mirror all of this in the simulator: the case it guards against is
arm on the HV fixture, declare a move back to the matrix, then energise.

**Malformed input.** Anything unknown or unparseable gives `<ERR ESYNTAX <what>`. A line longer
than **72 characters** is discarded up to the next newline and answered once with
`<ERR ESYNTAX line too long`. A bare `>` gives `<ERR ESYNTAX empty`. A completely empty line
gets **no reply at all** — do not send one, and do not let a stray newline sit consuming a
command timeout.

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

**`!DONE` is the last event of every run**, for all three test types. When it arrives,
everything about that run has already been reported — including an aborted run, which still
gets its `!DONE`.

**`!DONE` does not mean "safe to handle". `!SAFE` does.** `!DONE` says the run finished; only
`!SAFE` says the hardware has been forced safe. Continuity and resistance runs never raise the
rail and so never emit `!SAFE` — their `!DONE` says nothing about HV in either direction. Key
the handling prompt off `!SAFE` and nothing else, and never off event ordering.

**Discover reports only what it finds.** `!CONT` is emitted for connections found, not for all
65,536 combinations tested; progress comes from `!PROGRESS <hi> 256`, once per high-side pin.

`!RES` verdict `fail_low` is defined but not emitted by the current firmware. Handle it anyway.

### 3.4 State events

```
!STATE <idle|running|fault|hv_armed>
!FIXTURE <none|mtx|hv>                 which fixture the instrument expects NOW
!HV <millivolts>                       rail voltage, sent on every change
!SAFE                                  everything forced safe (abort, fault, or command)
```

- **`!SAFE` is emitted when the hardware is actually forced safe**: at the end of an insulation
  run, on `>SAFE`, on `>ABORT` while idle, and on a fixture change that invalidates arming
  (§3.2.1). It is *not* emitted at the end of a continuity or resistance run.
- **`!FIXTURE` can arrive unsolicited.** `CONT RUN` and `RES RUN` assert `mtx` themselves, so
  the GUI will see `!FIXTURE mtx` it did not ask for. Treat any `!FIXTURE` as authoritative and
  drop any armed state you are showing.
- **`!HV` is emitted on every change the firmware makes**, and by `HV SET` ahead of its `<OK`.
  `>= 50000` mV is live (§3.5 rule 2).
- `!STATE fault` is defined but not emitted by the current firmware — faults arrive as
  `!FAULT`. Handle it anyway.
- **At boot the instrument emits `!STATE idle` then `!FIXTURE none`**, unprompted. If the GUI
  is already attached it will see these; if it connects later it will not, which is why
  reconnect re-issues `>STATUS` (§3.5 rule 4).

### 3.5 Rules you must implement

1. **Never assume a command succeeded** — wait for `<`. Time out at **2 s** and surface it.
2. **`!HV` at or above 50 000 mV means the rail is live.** Show the HV indicator, everywhere.
   (The firmware carries the same threshold as `PROTO_HV_LIVE_MV`.)
3. **If the port closes or 5 s pass with no traffic**, show "link lost — state unknown" and
   disable every control that could energise anything.
4. **Reconnect must re-issue `>STATUS`** before enabling controls. Never assume idle.
5. Log every line sent and received to a session file. Field failures get diagnosed from it.
6. **Never queue a run yourself, and never retry one automatically.** `ERR EBUSY` means the
   instrument refused and forgot; surface it and let the operator decide (§3.2.1).
7. **`!DONE` closes a run; `!SAFE` says the hardware is safe.** Never infer either from the
   other, and never infer "safe" from the order events arrived in.
8. **An unsolicited `!FIXTURE` invalidates arming.** When one arrives, drop the armed state in
   the UI — the instrument has already dropped it.

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
3. ~~`>MANUAL RELAY` on a live HV card~~ **Answered:** the firmware refuses it outright with
   `ERR EHW`. Do not offer the control.
4. Run history — stored on the instrument or the GUI host?

### 8.1 Answers to the GUI-side questions raised during task 1

All checked against the firmware, not from memory. **Two of these found real bugs**, now
fixed — thank you, they were worth raising.

> Everything in this section is now also written into the contract itself — §3.2.1 for command
> acceptance, §3.3 and §3.4 for event semantics. **§3 is normative and takes precedence.** This
> section is kept for the reasoning behind the rules, not as a second source of truth.

**1. Pin numbering — 1-based, valid range 1..256.** Out of range gives `ERR ERANGE pin out of
range`, on both `NETLIST ADD` and `MANUAL PATH`. Tighten the codec to match; do not accept 0.

**2. `HV SET` — 0..500000 mV, `ERR ERANGE` above.** Your simulator is correct. One extra rule
it is missing: a **non-zero** `HV SET` while not armed is refused with `ERR ENOTARMED`. Only
`HV SET 0` is accepted unarmed.

**3. Command rejection while running — you were right, the firmware was wrong.**
It previously accepted a second run command and queued it, which looks like success to the
GUI and then behaves nothing like it. **Fixed:** run-starting commands (`CONT RUN`, `RES RUN`,
`INSUL RUN`) now return `ERR EBUSY a run is already in progress`. `PING`/`ID`/`STATUS`/`SAFE`/
`ABORT` always work, as in your simulator. Everything else is accepted and queued.

**`ABORT` also had a real bug.** It was queued behind the running test — and because the
sequencer holds the hardware mutex for the whole run, the abort would not have executed until
the run it was meant to stop had already finished. **Fixed:** `ABORT` now sets a flag that the
run loops poll between points, and replies immediately (`<OK` mid-run, `<OK started` when
idle). Expect the run to stop within roughly one measurement point, then:

```
insulation:   !HV 0, !SAFE, !STATE idle, !DONE insul <p> <f>
cont / res:   !STATE idle, !DONE <cont|res> <p> <f>          <- no !SAFE, the rail was never up
```

The aborted run always emits its `!DONE`.

**4. `CONT RUN verify` with no netlist — the firmware errors.** `ERR ERANGE no netlist`.
`RES RUN` is the same; only `CONT RUN discover` runs without one.
Remove the simulator's fallback to a built-in golden harness: it would let the GUI look like
it works in a case that fails on hardware, which is the worst kind of simulator bug.

**5. Discover progress — your granularity is right.** The firmware emits `!PROGRESS <hi> 256`
once per high-side pin, exactly as you have it. Per-combination progress over 65,536 points
would swamp the link for no benefit.

**6. Fixture change while armed — you found the second bug.**
The firmware just recorded it. That allowed: arm on the HV fixture, declare the harness moved
back to the matrix, then energise. **Fixed:** any fixture change now drops the arm, forces the
hardware safe, and emits `!HV 0` and `!SAFE` before `!FIXTURE`. Mirror that in the simulator.

**7. Discharge ordering — do not key off ordering. Key off `!SAFE`.**
Ordering is now fixed and guaranteed, but the robust signal is the explicit event:

```
!HV 0
!SAFE                  <- "safe to handle" keys off THIS
!STATE idle
!DONE insul <p> <f>    <- always the last event of any run
```

**`!DONE` is now guaranteed to be the final event of every run**, for all three test types.
When it arrives, everything about that run has already been reported. Change the simulator to
match — it currently emits `idle` before `DONE` for insulation but the reverse elsewhere.

The block above is the **insulation** sequence. Continuity and resistance never raise the rail,
so they emit `!STATE idle` and `!DONE` with **no `!SAFE` at all** — which is exactly why "safe
to handle" has to key off the explicit `!SAFE` event rather than off the end of a run.


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


---

## Appendix B — what the instrument does today

Implemented in `Core/Src/app/proto.c`, on hardware now.

| | |
|---|---|
| **Works** | `PING` `ID` `STATUS` `SAFE` `ABORT` `FIXTURE` `NETLIST *` `CONT RUN verify\|discover` `INSUL ARM\|RUN` `HV SET` `MANUAL PATH\|OFF` `CAL GET` `LIMITS GET\|SET` |
| **Refused by design** | `MANUAL RELAY` → `ERR EHW` |
| **Runs but always fails** | `RES RUN` — every net reports `fail_high` with `!FAULT F08`. The resistance measurement path is mid-rewrite for a new ADC (firmware task FW-02); reporting a plausible number from a measurement path that no longer exists would be worse than reporting a failure. **Build the resistance screen anyway** — the event format is final, and your simulator should exercise it properly |
| **Accepted, not yet driven** | `HV SET` — the arm check and the range check are real, and the value is echoed as `!HV <mv>`, but it does not yet move the rail. The rail is raised by the insulation run itself, at a fixed fraction. Build to the contract; the command's behaviour will not change, only what it drives |
| **Not emitted yet** | `!STATE fault` (faults arrive as `!FAULT`), and `!RES` verdict `fail_low`. `>STATUS` never reports `running` or `fault` either — see §3.2. Handle all three, they are part of the contract |

Two conveniences for hand-testing over a terminal:

- the leading `>` on commands is **optional**, so you can type `PING` and press enter
- log lines are prefixed `#`, so anything not starting `<` or `!` is display-only

Firmware build note: the last clean hand-link came to **58,932 bytes**.
