# HT_MK1 Operator GUI

GUI half of the HT_MK1 harness tester, built against the protocol contract in
`../Doc/GUI_development_brief.md` (section 3). Pure Python 3, standard library
only — no dependencies to install.

## Layout

```
htproto/codec.py       wire codec: byte-exact command encoders, strict line parser
htproto/messages.py    reply/event dataclasses
htproto/connection.py  connection manager: timeouts, link-loss, reconnect, session log
htproto/simulator.py   instrument simulator (TCP) with the five test scenarios
htproto/handtest.py    interactive terminal client (bring-up aid)
htweb/index.html       THE frontend — the approved design, markup and CSS verbatim
htweb/live.js          live protocol layer that drives that design
htweb/server.py        local HTTP + SSE bridge between the page and htproto
htgui/model.py         instrument state + the safety rules (no Tk — testable headless)
htgui/app.py           fallback Tk shell: HV banner, navigation, abort
htgui/screens.py       the eight Tk screens
tests/                 unittest suite (codec, simulator, connection, model, GUI, web)
```

## Run the GUI

Start the simulator in one terminal and the GUI in another:

```
python -m htproto.simulator --scenario pass --port 46000
python -m htweb --port 46000
```

That serves the operator GUI on <http://127.0.0.1:8770/> and opens a browser.
**The page is `Doc/HT_MK1_GUI_Proposal.html` — the approved design, markup and
CSS unchanged** — so the running instrument looks exactly like the mock-up. The
only edit to it is a small `window.HT_SEAM` export at the end of its script, so
`live.js` can swap the three simulated run functions for protocol-driven ones
and rebuild the net model from a real netlist. Everything that draws is the
design's own code.

`--allow-remote` binds all interfaces instead of loopback. Think before using
it: the page can arm and fire 500 V.

### What is live, and what is still presentation

The instrument's protocol is narrower than the design, so be clear about which
is which:

| Live from the instrument | Presentational only |
|---|---|
| link state, `!STATE`, `!HV`, `!SAFE`, `!FIXTURE` | connector/fixture map (`J1…J8`) — a GUI-side artifact; the instrument only knows pins 1..256 |
| continuity, resistance and insulation results and progress | net *names* — the protocol carries pin pairs, not names |
| faults, instrument log lines | HV card-stack detection, leakage voltage trace |
| netlist upload/download, cal, limits, abort, arm, fixture handover | scenario/seed pickers left from the mock |

### There is also a Tk frontend

`python -m htgui` runs the earlier Tk build. It is kept because its state model
(`htgui/model.py`) is where the safety rules are unit-tested without a display,
and because it needs no browser. The web frontend is the one that matches the
approved design.

For real hardware, point `TcpTransport` at a serial transport (115200 8N1 on the
USB VCP); nothing above the transport changes.

### How the safety rules are implemented

`htgui/model.py` is the only place they live, and it imports no Tk so they can
be tested without a display:

- **"Safe to handle" comes from `!SAFE` and nothing else.** Not from a run
  finishing, not from event ordering, not from silence. Everything else is
  `UNKNOWN`, which is never presented as safe.
- **Link loss forces `UNKNOWN`** and drops the arm — the GUI cannot know what
  the instrument is doing once it stops hearing from it.
- **Arming is dropped by any fixture change**, solicited or not, by `!SAFE`,
  by `!STATE idle`, and by any link trouble. The case this exists to stop is:
  arm on the HV fixture, claim a move back to the matrix, then energise.
- **Insulation controls are enabled only from `!FIXTURE hv`** as reported by
  the instrument — never from what the GUI asked for.
- **Abort is never disabled while the link is up**, and it never sits behind a
  confirmation dialog.

Commands are always sent from a worker thread: `execute()` blocks for up to the
2 s command timeout, and freezing the UI for 2 s would freeze the abort button
with it.

## Using the connection manager

```python
from htproto import ConnectionManager, commands

cm = ConnectionManager(on_event=print,                # every ! event and # log line
                       on_link_state=lambda s, d: print(s, d))
status = cm.connect("127.0.0.1", 46000)  # issues >STATUS before returning
print(cm.execute(commands.ping()))       # Pong()
cm.disconnect()
```

Behaviour per brief 3.5: commands time out after 2 s (`CommandTimeoutError`),
5 s without traffic or a closed port flips the state to `LINK_LOST`
("state unknown" — every command then raises until you `connect()` again),
and `connect()` always re-issues `>STATUS` before reporting CONNECTED.
Every session is logged to `sessions/session-<timestamp>.log` (both
directions, flushed per line). Callbacks fire from background threads.

## Run the tests

From this directory:

```
python -m unittest discover -s tests -v
```

## Run the simulator

From this directory:

```
python -m htproto.simulator --scenario pass --port 46000
```

Scenarios: `pass`, `opens_shorts`, `res_fail`, `insul_fail`, `disconnect`.
Options: `--nets N` (harness size, default 12), `--interval S` (delay between
streamed result events, default 0.02 s).

Hand-test it from a **second** terminal (leave the simulator window running):

```
python -m htproto.handtest --port 46000
```

Type commands (`PING`, `STATUS`, `CONT RUN verify`, ...) and watch the
replies and streamed events. The leading `>` is optional, as on the real
instrument. Empty line or Ctrl-C quits. Any raw TCP client works too
(PuTTY in "Raw" mode, `nc` if installed) — connect to `127.0.0.1`, port
`46000`.

The `disconnect` scenario drops the TCP connection part-way through a run
without sending `!DONE` — this is the hook for testing the GUI's
"link lost — state unknown" behaviour (brief 3.5.3).
