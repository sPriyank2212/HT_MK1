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
`STATUS`, `SAFE` and `ABORT` always work. Everything else is accepted.

**Replies are never queued behind a run.** Corrected 2026-08-05 — an earlier wording here said
"accepted and queued behind the run", which was wrong and is what prompted §8.2 question 1.
Commands are parsed and answered by the instrument's comms path; only the *execution* of the
few commands that touch hardware (`SAFE`, `ABORT` when idle, `MANUAL PATH`, `MANUAL OFF`) goes
onto the sequencer queue, and those are answered `<OK started` the moment they are enqueued,
not when they run. **Every command is answered well inside the 2 s timeout.** Do not lengthen
or suspend the timeout during a run.

> ✅ **`FW-07` is fixed** (2026-08-05). The comms thread used to be starved for the whole
> duration of a run, so mid-run commands went unanswered and `ABORT` did nothing. Console RX is
> now interrupt-driven, the comms thread runs above the sequencer, and the settle delays inside
> a run yield instead of busy-spinning. Commands are answered mid-run and `ABORT` stops a run at
> the next measurement point, as §3.2.1 has always said. Nothing for the GUI to change — the
> contract did not move.

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

Three details, all confirmed in the firmware (§8.3 Q2): **`!HV 0` is emitted even when the rail
was already at 0** — an armed-but-idle change still produces it; **no `!STATE idle` accompanies
the arm drop**, so do not wait for one; and **the three events arrive only once the hardware is
actually safe**, not when the command was accepted. The `<OK` comes back immediately; the events
follow.

**A fixture change also stops a run in progress.** Changed 2026-08-05 with the FW-08 fix. If the
operator declares a move while a run is executing, the run aborts at the next measurement point
and emits its `!DONE` as usual, and the `!HV 0` / `!SAFE` / `!FIXTURE` follow after that. So on
this path the three events can be delayed by up to one measurement point, and an insulation run
will emit its own `!HV 0` / `!SAFE` first — `!SAFE` is idempotent (§3.4), so treat the repeat as
confirmation. The GUI must not block waiting for `!FIXTURE` before letting the operator continue.

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

- **`!SAFE` is emitted when the hardware is forced safe**: at the end of an insulation run, on
  `>SAFE`, on `>ABORT` while idle, and on a fixture change that invalidates arming (§3.2.1). It
  is *not* emitted at the end of a continuity or resistance run.
- **`!SAFE` is idempotent and may repeat.** One force-safe emits it once, but a run aborted by a
  fixture change produces the run's own `!SAFE` and then the fixture change's (§3.2.1). Treat a
  repeat as confirmation, not as a new event to reconcile.
- **Every force-safe emits `!HV 0` immediately before its `!SAFE`** — on `>SAFE`, on `>ABORT`
  while idle, and on a fixture change. Changed 2026-08-05; previously `>SAFE` dropped the rail
  without saying so, leaving the GUI's rail reading stale.
- **`!FIXTURE` can arrive unsolicited.** `CONT RUN` and `RES RUN` assert `mtx` themselves, so
  the GUI will see `!FIXTURE mtx` it did not ask for. Treat any `!FIXTURE` as authoritative and
  drop any armed state you are showing.
- **`!HV` is emitted on every change the firmware makes**, and by `HV SET` ahead of its `<OK`.
  `>= 50000` mV is live (§3.5 rule 2).
- `!STATE fault` is emitted only in one internal case — a force-safe that could not be queued,
  where the instrument refuses to claim safety it has not achieved. Measurement faults arrive as
  `!FAULT` instead. Handle both.
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

1. ~~Discovery scan takes tens of seconds. Is `!PROGRESS` fine-grained enough?~~ **Answered**
   in §8.1.5: per-high-pin granularity is what the firmware emits; it is fine.
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

### 8.2 Raised during task-2 protocol verification (GUI side)

The protocol layer was verified against this brief: codec byte-for-byte, connection-manager
safety behaviour, and live wire captures against the simulator. Codec and connection manager
are **conformant**. What remains open:

**Questions for the firmware side**

1. ~~**Queued-command latency vs the 2 s timeout.**~~ **Answered in §8.3 Q1:** the "queued"
   wording was a brief error — replies are never queued, the 2 s timeout stands. The question
   exposed a real firmware defect (**FW-07**: comms thread starved during runs; `ABORT`
   currently does not stop a run). Build to the contract; do not model the defect.
2. ~~**Fixture-change force-safe: exact event set.**~~ **Answered in §8.3 Q2:** `!HV 0` is
   unconditional on an invalidating change; **no** `!STATE idle` accompanies the arm-drop;
   `!SAFE` may arrive twice and is idempotent.

**Simulator deviations found (GUI-side action — fix the simulator, not the GUI)**

Captured on a live socket during verification; all are places where the simulator teaches
behaviour the firmware does not have:

1. `ABORT` mid-run: simulator emits `!SAFE !STATE idle !DONE` **before** the `<OK`; the
   firmware replies immediately (§3.2.1). Idle `ABORT` should reply `<OK started`, not `<OK`.
2. `HV SET -100` while armed is accepted with `<OK`; must be `ERR ERANGE` (range 0..500000).
   Per §8.3: the arm check runs **before** the range check — unarmed, *any* non-zero value
   (negative or >500000 included) gives `ERR ENOTARMED`. Both orders needed.
3. HV ramp livelocks when a ramp step lands within the 10 mV `!HV` deadband (e.g. `HV SET 10`,
   `50`, `250001`): `<OK` is sent, the rail never arrives, the ramp thread spins forever.
   Per §8.3: there is **no deadband** (the §3.4 line that caused this was stale, now fixed) —
   `!HV` is emitted on every change. Simplest fix: echo `!HV <mv>` once, no ramp; Appendix B
   confirms `HV SET` does not move the rail yet.
4. `INSUL ARM` success ordering is reversed: simulator sends `!STATE hv_armed` then
   `<OK armed`; contract is `<OK armed`, then `!STATE hv_armed` (§3.2.1).
5. `HV SET` success: contract emits `!HV <mv>` **before** the `<OK` (§3.2.1); simulator
   replies first and ramps afterwards.
6. `RES RUN` without a netlist runs instead of `ERR ERANGE no netlist` (§3.2.1).
7. `NETLIST BEGIN <n>` with `n > 256`, and `ADD` beyond the promised `n`, are not refused
   (§3.2.1: `ERR ERANGE too many entries` / `ERR ERANGE more entries than promised`).
8. A refused (`EBUSY`) `CONT RUN`/`RES RUN` must still be preceded by `!FIXTURE mtx` — and by
   `!HV 0`/`!SAFE` if armed (§3.2.1 side effect). The simulator's refusal is event-free.
9. ~~Commands sent mid-run are answered immediately by the simulator; the firmware queues
   them~~ **Reversed by §8.3 Q1:** the simulator's answer-immediately behaviour is correct —
   it was the brief that was wrong. Not a deviation; keep it.
10. Re-declaring the current fixture drops the arm in the simulator; the firmware treats it as
    a no-op emitting `!FIXTURE` alone (§3.2.1).
11. Aborted continuity/resistance runs emit `!SAFE` in the simulator; per §8.1.3 they must not
    (rail was never up — `!STATE idle`, `!DONE` only).
12. §3.2.1 malformed-input rules are not modelled: >72-char lines discarded with one
    `ERR ESYNTAX line too long`, bare `>` → `ERR ESYNTAX empty`, and empty lines get **no
    reply** (the simulator answers empty lines with `ERR ESYNTAX`).
13. `SAFE`, `MANUAL PATH` and `MANUAL OFF` reply `<OK` in the simulator; per §3.2 they are
    sequencer-queued and reply `<OK started` (as does idle `ABORT`, deviation 1).
14. `STATUS` can report `state=running` in the simulator; per §3.2 the firmware only ever
    reports `idle` or `hv_armed` — `running`/`fault` reach the GUI via `!STATE`/`!FAULT` only.

### 8.3 Answers to §8.2

Checked against `proto.c` and `tasks.c`, not against this brief. **Your question 1 found a real
firmware defect** — a more serious one than the wording suggested. Thank you; that is twice now.

**Q1 — queued-command latency. Neither option: the premise was my error.** Replies are never
queued. Commands are parsed and answered by the comms path; only the *execution* of the four
hardware-touching commands is queued, and those are answered `<OK started` at enqueue time. The
"accepted and queued behind the run" wording in §3.2.1 was wrong and is now corrected. **Keep
the 2 s timeout as it is** — do not lengthen or suspend it during a run.

*But you were right that something was broken.* The comms thread ran below the sequencer in
priority, and the sequencer never yielded during a run — its settle delays busy-spun rather than
blocking. So the comms thread was starved for the entire run: mid-run commands went unanswered
and **`ABORT` did not stop a run at all**. Raised as **FW-07**, with a second defect it hid
(below). Deviation 9 in your list is therefore backwards: your simulator's answer-immediately
behaviour is correct and should stay.

> **Both are now fixed** (2026-08-05, same day). RX is interrupt-driven, comms runs above the
> sequencer, settle delays yield, `!SAFE` is emitted where the hardware is actually made safe,
> and a fixture change now stops a run in flight. The contract did not move — §3.2.1 already
> described the intended behaviour, and the firmware now meets it. Two knock-on details worth
> picking up in the simulator: every force-safe now emits `!HV 0` immediately before `!SAFE`
> (including plain `>SAFE`), and a fixture change during a run aborts it, so the run's `!DONE`
> arrives before the fixture change's `!HV 0` / `!SAFE` / `!FIXTURE`.

**Q2 — fixture-change force-safe. Both gaps confirmed, and there is a third.**

- **`!HV 0` is always emitted** on an invalidating change, including the armed-with-rail-at-0
  case. It is unconditional inside that branch, not conditioned on the rail being up.
- **No `!STATE idle` is emitted.** The arm is dropped silently as far as `!STATE` is concerned,
  so a GUI tracking state purely from `!STATE` would still be showing `hv_armed`. Treat
  `!SAFE`, and any `!FIXTURE`, as disarming (§3.5 rule 8). This is a firmware gap rather than a
  deliberate design — logged, but do not wait for it.
- **`!SAFE` can arrive twice** for one fixture change: once inline, once when the queued
  force-safe actually executes. `!SAFE` is idempotent — treat a repeat as confirmation, never
  as a second event to reconcile. Applies to any `!SAFE`, not just this path.

**On your deviations list.** Of the original twelve, eleven are right — 2, 4, 5, 6, 7, 8, 10, 11
and 12 match the firmware exactly as written. Three notes:

- **2 — the error code depends on arm state.** `HV SET -100` gives `ERR ERANGE` only *while
  armed*. **Unarmed, any non-zero value gives `ERR ENOTARMED`**, negative included — the arm
  check runs before the range check. Your simulator needs both orders.
- **3 — there is no 10 mV deadband.** That came from a stale line in §3.4, now corrected:
  `!HV` is emitted on every change, full stop. The livelock is your own ramp logic, but the
  doc caused it. Also note `HV SET` does not yet move the rail at all (Appendix B) — a
  simulated ramp is fine, but nothing on the instrument produces one today.
- **9 — reversed, see Q1.** Your simulator is correct; the brief was wrong.

**13 and 14, which you added after reading §8.3, are both confirmed.** `SAFE`, `MANUAL PATH`
and `MANUAL OFF` go through the same enqueue path and reply `<OK started`, as does `ABORT` when
idle; `STATUS` is built from the armed flag alone and can never say `running` or `fault`. That
`STATUS` gap is logged as **FW-06** — the information exists, it just isn't in the polled reply,
so on reconnect keep treating `idle` as "not armed" rather than "not running" (§3.2).

**Net: fourteen raised, thirteen real, one (9) caused by this brief.** The scoreboard across
both rounds is three firmware defects found from the GUI side — the two in `5d837d8`, and now
FW-07. Verifying the contract against a simulator you wrote from it is doing exactly what it
should.

### 8.4 Review of tasks 1 and 2 (firmware side, 2026-08-05)

Per §6. Read `codec.py`, `messages.py`, `connection.py` and the tests; ran the suite (**57 tests,
all passing**) and a targeted probe of the failure paths. **Structure and intent are right** —
the codec is genuinely byte-exact on the commands, the framer is correct, `_Pending` handles the
`NETLIST GET` multi-line reply properly, reply ordering is protected by serialising append+send
under one lock, and the session logger flushes per line as §3.5 rule 5 requires. The three items
below are what stands between this and a pass.

**1 — BLOCKER: a send failure deadlocks the connection manager.**
`_execute` calls `_link_lost()` from *inside* `with self._io_lock:` (the `except OSError` around
`_send_line`). `_link_lost` → `_fail_all_pending` → `with self._io_lock` again, and
`threading.Lock` is not reentrant. The lock is never released, so the calling thread hangs
forever **and every later command hangs with it** — if that is the UI thread, the GUI freezes
solid with HV possibly still live. Reproduced with a transport whose `send` raises `OSError`:
`execute()` never returns.

This is the ordinary link-drop path, not an exotic one — a closed port usually lets one send
buffer and fails on the next, so "pull the plug mid-run" (§6) lands here. Your failure tests
cover *receive*-side failures only: silent server, garbage, closed socket. There is no test where
`send` itself raises. Fix: call `_link_lost` after releasing the lock, or give `_fail_all_pending`
a no-lock variant. Then add the missing test.

**2 — Signed fields are parsed as unsigned; a valid reading will be rejected.**
`_uint` refuses a leading `-`, but the firmware prints these with `%ld` from `int32_t`, and
negative is a legal wire value:

| Field | Why it goes negative |
|---|---|
| `!RES <milliohms>` | a near-zero resistance reads negative once system offset is subtracted — that is the whole subject of BU-10, and `fail_low` exists as a verdict for exactly this |
| `!INSUL <leak_mohm>` | same `int32_t` path |
| `<STATUS hv_mv=` / `<LIMITS ...` | `int32_t`; `LIMITS SET` accepts any value and echoes it back |

`parse_line('!RES 12 34 -5 pass')` raises `ProtocolError`, so the GUI would classify a correct
measurement as a contract violation. It has not bitten yet only because `RES RUN` currently
reports `0`/`fail_high` on every net (Appendix B) — it will the moment FW-02 lands. Use a signed
parse for those four fields; keep `_uint` for pins, counts and progress, which really are
unsigned.

**3 — Minor, worth fixing while you are in there.**

- **A single non-ASCII byte costs a 5 s link-loss.** `UnicodeDecodeError` is caught *outside* the
  read loop, so the reader thread exits, events stop, and the watchdog eventually reports "no
  traffic" — a misleading diagnosis for one corrupted byte on a 115200 line. Decode with
  `errors="replace"`, surface one protocol error for that line, and keep reading.
- **`AttributeError` instead of `LinkLostError`.** `_link_lost` sets `self._transport = None`
  while the reader is in `self._transport.recv(...)` and a sender may be in `_send_line`. Neither
  `except OSError` catches `AttributeError`. Take a local reference once, or guard for `None`.
- **Empty lines.** `parse_line('')` raises. The firmware no longer emits one (see below), but a
  `\r\n` pair or a reset mid-line can still produce one. Ignoring empty lines is safer than
  reporting them.

**Not your bug — fixed on the firmware side today.** The boot banner was not protocol-framed:
`[boot] HT_MK1 console up @115200` and the `[boot] ... FAILED` lines carried no `<`, `!` or `#`,
and the banner led with a bare `\r\n` that framed as an empty line. Your codec was right to
reject them. They are now `#`-prefixed with no leading newline. If you saw a burst of protocol
errors at connect, that was why.

**Verdict:** finding 1 must be fixed before task 3 — it is a hang in the exact scenario §6 tests.
Finding 2 before FW-02 lands. Neither is a design problem; the design is sound.


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
| **Not emitted yet** | `!RES` verdict `fail_low`, and `>STATUS` still never reports `running` or `fault` (FW-06, see §3.2). `!STATE fault` is now emitted, but only in the one internal case in §3.4. Handle all of them; they are part of the contract |
| **Fixed 2026-08-05** | **FW-07** — `ABORT` now stops a run, and commands sent mid-run are answered mid-run. Console RX became interrupt-driven, comms moved above the sequencer, and settle delays yield instead of busy-spinning. **FW-08** — `!SAFE` is now emitted where the hardware is actually made safe, not where the request was posted. Both found by the GUI-side task-2 review |

Two conveniences for hand-testing over a terminal:

- the leading `>` on commands is **optional**, so you can type `PING` and press enter
- log lines are prefixed `#`, so anything not starting `<` or `!` is display-only

Firmware build note: the last clean hand-link came to **64,920 bytes** (text 64,816 + data 104),
up from 58,932 — the FW-07 fix pulls in the HAL's interrupt-driven UART receive path, which
`--gc-sections` used to discard when the console was transmit-only. 12.4 % of the 512 kB flash.
