# Harness Tester Demo (no hardware)

`HarnessTesterDemo.exe` is the Harness Tester program with a simulated tester in
place of the STM32 board. Everything above the serial port is the real program:
connecting, calibration, netlist upload, Continuity, Cross Continuity,
Auto-Scan, Use as Netlist, the Results Table, Log, CSV and PDF reports, the
connector configuration and the netlist editor.

Run from source: `python demo_main.py`. Build: `python -m PyInstaller HarnessTesterDemo.spec --clean --noconfirm`.

## Using it

1. Press **Connect**. The only port is "DEMO - Virtual Harness Tester".
2. Load a connector config (Configuration tab) and a netlist as usual.
3. Run a test. By default the harness that is "plugged in" matches the loaded
   netlist, so the test passes.

## Demo menu

| Item | What it does |
|---|---|
| Harness follows the loaded netlist | On: loading a netlist plugs in a matching harness (no faults). |
| Plug in a harness from a netlist file | Plug in a different harness; the loaded netlist is then only what the tester expects. Auto-Scan finds this one. |
| Break wire(s) | Opens that many wires of the harness. Continuity / Cross Continuity report them NOT CONNECTED. |
| Add stray wire(s) (miswire) | Adds wires between channels that were not connected. Cross Continuity reports MISWIRE. A stray wire also joins the two nets it touches, as on the bench. |
| Remove all faults / Show what is plugged in | Reset, or list the wires and faults. |
| Scan speed | Fast (about the real tester), Normal, Slow. |

With no netlist loaded the virtual harness is 37 straight wires (A1-B1 ... A37-B37),
the same as the firmware's default map.

## What is simulated

`core/virtual_device.py` answers the same UART frames as `firmware/Core/Src/harness.c`
(PING, GET_STATUS, SET_NETLIST in chunks, SET_PARAM, CALIBRATE, START_CONT,
START_CROSS_CONT, AUTO_SCAN, ABORT; NACK when busy). A scan drives a Side-A
channel and reads the Side-B channels electrically joined to it. Results are
50.0 mohm for a closed wire and 50000 mohm for an open one, as the firmware reports.
Firmware version shown: 2.2.0. The HV and short-circuit scans are not part of
the GUI and are not simulated.

## Differences from the real tester

- A scan takes a visible 40 ms per step by default (the real tester takes about 5 ms).
- Cross Continuity expects exactly the pairs the netlist lists. The firmware
  (`is_expected` in harness.c) also treats the reversed pair, A9-B5 for a listed A5-B9,
  as expected.
- The demo keeps its own profiles and results (`HarnessTesterDemoData`),
  separate from the real program's.
