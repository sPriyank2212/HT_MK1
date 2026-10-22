/// Auto scan — find out what the harness on J-MTX actually connects, with no
/// netlist and no test plan.
///
/// It is the firmware's cross-continuity discovery (`CONT RUN discover`)
/// presented as its own section: the operator plugs a harness in, presses run
/// and gets the list of connections it found. It is a survey, not a pass/fail
/// verdict, so it never counts towards the Mode 1 result that unlocks the
/// insulation test (see `AppState.runAutoScan`).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../app/app_state.dart';
import '../app/parts.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';

/// Rows drawn in the result table. A fully populated 256-pin harness can
/// report far more connections than a person will scroll; the CSV/netlist
/// save still carries all of them.
const int _kMaxRows = 300;

class AutoScanView extends StatelessWidget {
  final AppState s;
  const AutoScanView({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final (canRun, why) = s.canAutoScan;
    final scanning = s.running == 'cont';
    final found = s.discoveredPairs;

    final pill = scanning
        ? const PillState(PillVariant.acc, 'Scanning')
        : found.isNotEmpty
            ? const PillState(PillVariant.ok, 'Scanned')
            : const PillState(PillVariant.idle, 'Not run');

    return Cols([
      ViewBar([
        const StageBadge('Auto scan'),
        Text('Auto scan', style: t.viewbarH2),
        const Conn('J-MTX'),
        Pill(pill.variant, pill.text),
        const FlexSpacer(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250),
          child: Text(
            why.isNotEmpty ? why : 'finds every connection — no netlist needed',
            style: t.why,
          ),
        ),
        Btn('Run auto scan',
            variant: BtnVariant.primary,
            big: true,
            disabled: !canRun,
            onTap: canRun ? () => unawaited(s.runAutoScan()) : null),
      ]),
      HtPanel(
        child: PanelPad(
          Text(
            'Auto scan works without a harness plan. Plug the harness into '
            'J-MTX and run it: each pin is energised in turn and every other '
            'pin that answers is recorded, so you see the connections that '
            'really exist — including splices and multi-drop nets. Nothing '
            'is compared against a netlist and the result does not count '
            'towards the Mode 1 pass.',
            style: t.ui(size: 12.5, color: context.colors.ink2, height: 1.55),
          ),
        ),
      ),
      Tally([
        TallyItem('Connections found', s.auNets, 'acc'),
        TallyItem('Pins involved', s.auNodes),
        TallyItem('Multi-drop nets', s.auMulti, 'acc'),
        TallyItem('Columns swept', s.auCols),
      ]),
      _FoundPanel(s: s, pairs: found, scanning: scanning),
    ]);
  }
}

class _FoundPanel extends StatelessWidget {
  final AppState s;
  final List<(int, int)> pairs;
  final bool scanning;
  const _FoundPanel(
      {required this.s, required this.pairs, required this.scanning});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    // One row per source pin, with every pin that answered it.
    final byHi = <int, List<int>>{};
    for (final (hi, lo) in pairs) {
      (byHi[hi] ??= <int>[]).add(lo);
    }
    final hiPins = byHi.keys.toList()..sort();
    final shown = hiPins.take(_kMaxRows).toList();

    return HtPanel(
      header: [
        const PanelTitle('Connections found'),
        const FlexSpacer(),
        Btn('Save as MTX netlist',
            variant: BtnVariant.primary,
            disabled: !s.saveNlEnabled,
            onTap: s.saveNlEnabled
                ? () => unawaited(s.saveDiscoveredNetlist())
                : null),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pairs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 26),
              child: Text(
                scanning
                    ? 'Scanning — connections appear here as they are found.'
                    : 'Run auto scan to find the connections on J-MTX.',
                style: t.empty,
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            HtTable(
              minWidth: 560,
              columns: const [
                HtCol('Source pin'),
                HtCol('Connected to'),
                HtCol('Fan-out', right: true),
                HtCol('Topology'),
              ],
              rows: [
                for (final hi in shown)
                  [
                    Td('Pin $hi', numeric: true),
                    RowWrap.gapped(
                      4,
                      [
                        for (final lo in (byHi[hi]!..sort()))
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.accentSoft,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text('Pin $lo', style: t.fan(c.accent)),
                          ),
                      ],
                    ),
                    Td('1:${byHi[hi]!.length}', numeric: true),
                    Tag(
                      byHi[hi]!.length > 1 ? TagVariant.acc : TagVariant.mut,
                      byHi[hi]!.length > 1 ? 'multi-drop' : 'point to point',
                    ),
                  ],
              ],
            ),
            if (hiPins.length > shown.length)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${hiPins.length - shown.length} more source pins not shown '
                  '— save as a netlist to keep them all.',
                  style: t.empty,
                  textAlign: TextAlign.center,
                ),
              ),
            if (!scanning)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Text(s.crossNote, style: t.empty),
              ),
          ],
        ],
      ),
    );
  }
}
