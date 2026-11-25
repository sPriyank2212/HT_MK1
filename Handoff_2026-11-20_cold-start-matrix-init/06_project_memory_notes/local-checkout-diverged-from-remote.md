---
name: local-checkout-diverged-from-remote
description: History of the 2026-11-13 reconciliation of the main checkout with GitHub; Debug/ is untracked+ignored; backup folder location; decisions made (FW-11 configurable).
metadata:
  node_type: memory
  type: project
  originSessionId: 4bbb51a8-84f4-43ed-8aaa-ffaf4c225835
  modified: 2026-11-13T07:17:53.811Z
---

On 2026-11-13 the main checkout was stale (26 commits behind `origin/fw/doc-reconciliation-2026-07-14`, with
uncommitted work). It was reconciled: everything uncommitted was backed up to
`..\HT_MK1_local_backup_2026-11-13` (patch, tar of 113 files, full `Debug_full/` copy, old tip 480186d), the
useful content was merged/ported into commits on GitHub, then the checkout was `reset --hard` to origin.
It now equals `origin/fw/doc-reconciliation-2026-07-14` (0017d79 at the time).

**Why this matters later:** `Debug/` is untracked and git-ignored on the remote (commit 9aa288f); it stays on the
user's disk only (CubeIDE regenerates it). Never re-add it. Local-only untracked files (app_icon.ico,
company_logo.jpeg, Result/, gui_flutter/screenshots/, OBC_ICD docx, zz_shots_test.dart, .vscode/) are
intentionally not in git.

**Decisions made by the user:** FW-11 = make the insulation limit configurable (done, CL-81: 100 kOhm..40 MOhm,
ERR ERANGE/EBUSY, int64, verdict still one voltage comparison in insulation.c). Still open: HW-15 (firmware maps
HV card 1 to EN2/J2; the Overview docs say EN1/J1 shared with Matrix), I2C3 400 kHz (needs a scope), BU-16.

**How to apply:** future changes can be made directly in the main checkout again; if it drifts, use a
`git worktree add` off origin and push `HEAD:<branch>` as a fast-forward, never force. New log IDs continue
above CL-83, FW-20, HW-15, GUI-36, BU-16, DOC-07. See [[schematics-are-source-of-truth]] and
[[firmware-single-mcu-architecture]].
