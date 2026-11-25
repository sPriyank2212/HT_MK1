---
name: gui-flutter-only
description: "HT_MK1 ships the Flutter GUI (gui_flutter/) only — the Python GUI (gui/) is not used, decided by the user"
metadata: 
  node_type: memory
  type: project
  originSessionId: 2c736dc9-e329-4c81-a4ff-7af6c6cfd804
  modified: 2026-08-11T13:17:29.876Z
---

The user confirmed explicitly (2026-08-11): **the Python GUI (`gui/` — htweb browser UI + Tk
fallback) will not be used.** `gui_flutter/` (Dart/Flutter, native Windows exe, no Python at
runtime) is the only GUI going forward.

**Why:** `gui_flutter/` was built 2026-08-07 as a full rebuild of `gui/` — same design, same
protocol, same safety rules, ported file-for-file, verified against both the simulator and real
hardware (130 tests, `flutter analyze` clean). The user's earlier framing (2026-08-10) was
"Flutter is primary, Python kept for reference" — this later message is more definitive: Python
is not a fallback or reference implementation to maintain, it is simply not used.

**How to apply:**
- Do not propose work, fixes, or features for `gui/` (Python) unless the user explicitly asks
  about it. GUI-03 (three minor robustness items in `gui/`'s connection manager) stays logged
  in `PROJECT_LOG.md` as a historical record, not as something to act on.
- All GUI-related work — new features, protocol wiring, bug fixes — targets `gui_flutter/`.
- If asked to clean up or reduce scope in the repo, `gui/` is a reasonable candidate to raise
  for removal (ask first — deleting it is not pre-authorized by this memory alone).
- See [[schematics-are-source-of-truth]] and the project's own `README.md` "Work in progress"
  table, which already reflects this.
