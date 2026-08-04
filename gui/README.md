# HT_MK1 Operator GUI

GUI half of the HT_MK1 harness tester, built against the protocol contract in
`../Doc/GUI_development_brief.md` (section 3). Pure Python 3, standard library
only — no dependencies to install.

## Layout

```
htproto/codec.py      wire codec: byte-exact command encoders, strict line parser
htproto/messages.py   reply/event dataclasses
htproto/simulator.py  instrument simulator (TCP) with the five test scenarios
tests/                unittest suite (codec conformance + simulator round-trips)
```

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
