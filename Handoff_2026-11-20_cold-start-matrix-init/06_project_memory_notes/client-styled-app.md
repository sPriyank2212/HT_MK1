---
name: client-styled-app
description: "gui_flutter has a second, client-styled app (main_client.dart + lib/client/) with the customer's layout and report format; decisions and what is not done"
metadata:
  node_type: memory
  type: project
  originSessionId: a7e8908f-1fcc-4d29-943a-55ffa417e05a
  modified: 2026-11-16T09:45:19.632Z
---

`gui_client_required/` is the customer's own **Python/PySide6 Harness Tester for the MK0** (UART, 37 wires, continuity / cross continuity / auto-scan only). The user asked for the **client's look, terminology and PDF/CSV format, with the MK1 features** (resistance, HV insulation).

Built 2026-11-16 as a **second app inside `gui_flutter`** (the user chose this over replacing the console): `lib/main_client.dart` + `lib/client/*`, sharing `AppState`, `htproto`, the simulator and the HV gating with the engineering console, which is untouched. Entry bootstrap is shared via `runConsole()` in `main.dart`. Reports go through the `ReportFormat` hook on `AppState` (`client/client_report.dart` = client format). Build: `build_client_exe.cmd`. See PROJECT_LOG CL-89 and the README section.

**Why:** the client's own app stays the reference for look and wording; Flutter-only is already decided ([[gui-flutter-only]]), so the Python code is not reused, only copied in style.

**How to apply:**
- The client's *current* report is `gui_client_required/core/report.py` (landscape, 16 columns); `gui_flutter/required_format/` PDFs are an older portrait sample. Match the code, not the sample.
- Cross Continuity in the client = firmware discovery sweep judged against the netlist on the PC (unlisted connection = MISWIRE).
- Netlist editor exists (CL-90): two netlists, continuity/resistance (J-MTX) and HV (J-HV, HS/LS pins, 64 relays per card). Not done: Golden Sample, Profile Manager, Serial Monitor window, pin-detail dialog, Calibrate; connector layout is shown, not edited. Nothing run on hardware.
- The instrument keeps ONE netlist and its insulation test reads it (HI = HS relay on card (hi-1)/64). The old console HV netlist was metadata only; the client app uploads the HV netlist before insulation and restores the continuity one after (`AppState.uploadHvNetlist`, off in the console). Console behaviour deliberately unchanged because the user is bench-testing BU-16.
- A race in `AppState._beginRun` (results arriving with `<OK` were wiped) was found and fixed here (`_prepareRun`); a zero-interval simulator exposes it.
- Test gotcha: a run started from a widget-test body lives in the fake-async zone; wait with a loop that both `runAsync`-delays and `pump()`s.
