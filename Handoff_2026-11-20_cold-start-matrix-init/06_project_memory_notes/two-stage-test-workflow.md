---
name: two-stage-test-workflow
description: DUT is physically moved between the Matrix and HV connectors; insulation is gated on continuity+resistance passing
metadata: 
  node_type: memory
  type: project
  originSessionId: 2c9e7c07-b2d4-4935-b52a-8bd6a9a43a3c
  modified: 2026-07-28T07:01:59.683Z
---

The harness under test connects to **one connector at a time**, not both. Stage 1 is the Matrix
card connector (continuity, then resistance). Only if both pass does the operator detach the
harness and re-connect it to the HV card connector for stage 2 (500 V insulation). If stage 1
fails the harness is never moved and insulation is never attempted.

Stated by the user 2026-07-28 while reviewing the GUI proposal. Not derivable from the
schematics or `fw_status.txt`, both of which describe the three tests without saying the DUT
physically relocates between them.

**Why:** it makes the sequencer a gated two-stage state machine with an operator handover in
the middle, not one continuous pass. Any host protocol or GUI has to model the handover as a
blocking step and keep the HV path locked until it is acknowledged.

**How to apply:** treat continuity + resistance as one bundle on the Matrix connector and
insulation as a separate gated bundle on the HV connector. Do not design flows, reports, or
progress indicators that assume all three run back to back.

Continuity also has two operator-selected modes: **netlist** (verify the expected pairs, report
missing/unexpected) and **auto** (one-to-many discovery sweep that finds splices and multi-drop
nets and writes the netlist as it goes). Auto mode is the expensive one — a full 256x256 sweep
is bus-bound, see [[firmware-single-mcu-architecture]] on the I2C 100 vs 400 kHz decision.

Related: [[matrix-card-kelvin-resistance-rework]], [[schematics-are-source-of-truth]].
