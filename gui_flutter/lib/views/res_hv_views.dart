/// `<section id="v-res">` and `<section id="v-hv">`.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../app/app_state.dart';
import '../app/parts.dart';
import '../design/model.dart';
import '../design/painters.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';

/// `.two{grid-template-columns:minmax(0,1fr) 320px;gap:14px}` collapsing to a
/// single column under 1080px.
class TwoUp extends StatelessWidget {
  final Widget main;
  final Widget side;
  const TwoUp({super.key, required this.main, required this.side});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width <= kMediumBreak) {
      return Cols([main, side]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: main),
        const SizedBox(width: 14),
        SizedBox(width: 320, child: side),
      ],
    );
  }
}

// ===========================================================================
// RESISTANCE
// ===========================================================================

class ResView extends StatelessWidget {
  final AppState s;
  const ResView({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final pill = s.pillFor('res');
    final canRun = s.can('res').$1;

    return Cols([
      ViewBar([
        const StageBadge('Stage 1'),
        Text('Resistance', style: t.viewbarH2),
        const Conn('J-MTX'),
        Pill(pill.variant, pill.text),
        const FlexSpacer(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250),
          child: Text(s.rvWhy, style: t.why),
        ),
        Btn('Run resistance',
            variant: BtnVariant.primary,
            big: true,
            disabled: !canRun,
            onTap: canRun ? () => s.runTest('res') : null),
      ]),
      Netbar(s: s, dom: 'mtx', useKey: 'res'),
      // "Connector" and "Scope" (nlMtx) are real. "Excitation" and "Sense"
      // are genuinely fixed hardware facts (FW-12: the ADS124S08's own
      // IDAC1, fixed at 2 mA, routed to AIN9 = HI_COM). "Gain" no longer
      // claims a single fixed PGA setting — FW-02 auto-ranges it per
      // measurement (highest gain first, stepping down on saturation), so
      // no one number is "the" gain; 20 SPS is the real fixed data rate
      // (`board.c`'s `ADS124S08_DR_20`). "Offset cal" no longer invents a
      // subtracted value — the per-measurement system-offset subtraction
      // (CL-23) isn't reported back over the wire (`ResResult` carries only
      // the final milliohms), so there is nothing real to show as a number.
      Band([
        const BandItem('Connector', Conn('J-MTX')),
        BandItem(
          'Scope',
          Text(s.nlMtx.loaded ? '${s.nlMtx.nets} declared pairs' : 'no netlist',
              style: t.bandV),
        ),
        BandItem('Excitation',
            Text('2 mA · ADS124S08 IDAC1 → AIN9', style: t.bandV)),
        BandItem(
            'Sense', Text('ADS124S08 U68 · SPI1', style: t.bandV)),
        BandItem('Gain', Text('auto-ranged PGA · 20 SPS', style: t.bandV)),
        BandItem('Offset cal',
            Text('per measurement · not reported', style: t.bandV)),
      ]),
      TwoUp(
        main: Cols([
          HtPanel(
            header: const [
              PanelTitle('Resistance distribution'),
              FlexSpacer(),
              Lbl('limit window 0.05 – 2.00 Ω'),
            ],
            child: PanelPad(
              SizedBox(
                height: 150,
                child: CustomPaint(
                  painter: HistPainter(
                      s.nets, s.faultsOn['f06']!, context.colors),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
          _RankedTable(s: s),
          _ResConnectionResults(s: s),
        ]),
        side: Cols([
          // "Mode"/"Set current"/"Compliance" are real fixed hardware facts
          // (FW-12/DOC-04: HW-01's 2-wire AD7476 fallback is gone, the
          // IDAC's own datasheet compliance ceiling is AVDD − 0.6 V = 2.7 V).
          // "Measured" (a live per-measurement excitation current readback)
          // and a specific "Resolution" figure both dropped rather than
          // invented — no wire field reports either, and resolution varies
          // with the auto-ranged PGA gain (see the Excitation band above),
          // so no single number is honest. "Limits from" is real.
          HtPanel(
            header: const [PanelTitle('Measurement conditions')],
            child: PanelPad(Kv([
              const KvRow('Mode', KvText('4-wire Kelvin · ADS124S08 IDAC1')),
              const KvRow('Set current', KvText('2.000 mA')),
              const KvRow(
                  'Compliance', KvText('2.7 V ceiling (AVDD − 0.6 V) · 45 % margin at 2 mA')),
              KvRow(
                'Limits from',
                KvText(s.nlMtx.loaded
                    ? 'MTX netlist · per net'
                    : '— none loaded'),
              ),
            ])),
          ),
          // Static topology diagram, not live data - accurate to the
          // current schematic (FW-12: IDAC1 → AIN9 → HI_COM, DAC8775/Opto U3
          // gone). No protocol field reports a sense path to draw live even
          // in principle, so this documents the fixed wiring rather than
          // standing in for a real reading.
          HtPanel(
            header: const [PanelTitle('Sense path')],
            child: PanelPad(PathBox(const [
              // FW-12: excitation is the ADS124S08's own IDAC1, routed
              // directly to AIN9 (= HI_COM) - the DAC8775/Opto U3 path is
              // gone from the schematic.
              PathSpan('ADS124S08 IDAC1 → AIN9 → '),
              PathSpan('HI_COM', bold: true),
              PathSpan(' → HI mux → HS → harness → LS\n→ LO mux → LO_COM → '),
              PathSpan('R131 100 Ω 0.01 %', bold: true),
              PathSpan(' → GND\nsense: HI_SENSE − LO_SENSE → '),
              PathSpan('ADS124S08 AIN0/AIN1', bold: true),
              PathSpan('\nR = V / I − R_offset'),
            ])),
          ),
          HtPanel(
            header: const [PanelTitle('Actions')],
            child: PanelPad(RowWrap([
              // Re-runs the same RES RUN the header button does — there is
              // no protocol primitive to measure only the worst nets, so a
              // full re-run is the honest version of "re-measure worst".
              Btn('Re-measure worst',
                  disabled: !canRun,
                  onTap: canRun ? () => s.runTest('res') : null),
              // MOCK/OFF: deliberately kept off the operator surface - a
              // bench-characterization step, not a run-time command. See
              // Doc/GUI_protocol_proposed_commands.md, "Compliance sweep".
              Btn('Compliance sweep', disabled: true, onTap: null),
            ])),
          ),
        ]),
      ),
    ]);
  }
}

/// `#resBody` — `function buildResTable()`
class _RankedTable extends StatelessWidget {
  final AppState s;
  const _RankedTable({required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final ranked = s.nets
        .where((n) => !(n.open && s.faultsOn['f06']!))
        .map((n) => (n: n, m: n.rmax - n.r))
        .toList()
      ..sort((a, b) => a.m.compareTo(b.m));
    final rows = ranked.take(8).toList();

    const maxR = 5.2;
    double pct(double v) => math.min(100, v / maxR * 100);

    return HtPanel(
      header: const [
        PanelTitle('Ranked by margin to limit'),
        FlexSpacer(),
        Lbl('worst 8'),
      ],
      child: HtTable(
        columns: const [
          HtCol('Net'),
          HtCol('From'),
          HtCol('To'),
          HtCol('Measured', right: true),
          HtCol('Window'),
          HtCol('Margin', right: true),
          HtCol('Result'),
        ],
        rows: [
          for (final row in rows)
            () {
              final n = row.n;
              final m = row.m;
              final bad = n.r > n.rmax || n.r < n.rmin;
              return <Widget>[
                Td(n.name),
                Td(refOf(n.src), numeric: true),
                Td(refOf(n.dsts[0]), numeric: true),
                Td('${n.r.toStringAsFixed(3)} Ω',
                    numeric: true, color: bad ? c.fail : null),
                _MBar(
                  winLeft: pct(n.rmin),
                  winWidth: pct(n.rmax) - pct(n.rmin),
                  point: pct(n.r),
                  bad: bad,
                ),
                Td('${m >= 0 ? "+" : ""}${m.toStringAsFixed(3)}',
                    numeric: true, color: bad ? c.fail : null),
                Tag(
                  bad
                      ? TagVariant.bad
                      : (m < 0.2 ? TagVariant.warn : TagVariant.ok),
                  bad ? 'F08 high' : (m < 0.2 ? 'Marginal' : 'Pass'),
                ),
              ];
            }(),
        ],
      ),
    );
  }
}

/// "All connections in one table" for resistance (GUI-11) — `_RankedTable`
/// above only ever shows the worst 8 nets by margin; this shows every real
/// `!RES` result the current run has produced, connector-qualified.
class _ResConnectionResults extends StatelessWidget {
  final AppState s;
  const _ResConnectionResults({required this.s});

  @override
  Widget build(BuildContext context) {
    return HtPanel(
      header: const [
        PanelTitle('Connection results'),
        FlexSpacer(),
        Lbl('every pin under test'),
      ],
      child: ConnectionResultsTable(
        columns: const [
          'Test #', 'Src Conn', 'Src Pin', 'Dst Conn', 'Dst Pin',
          'R (mΩ)', 'Status', //
        ],
        rows: [
          for (final r in s.resRowsLive)
            ConnectionResultRow(
              cells: [
                '${r.testNum}',
                r.srcConnId,
                r.srcPinLabel,
                r.dstConnId,
                r.dstPinLabel,
                r.resistanceMohm.toStringAsFixed(1),
              ],
              bad: r.status != 'PASS',
              statusLabel: switch (r.status) {
                'PASS' => 'Pass',
                'FAIL_HIGH' => 'F08 high',
                'FAIL_LOW' => 'F08 low',
                _ => r.status,
              },
            ),
        ],
        emptyMessage:
            'No results yet — run resistance to populate this table.',
      ),
    );
  }
}

/// `.mbar{height:20px;background:var(--sunk);border-radius:3px;
///        min-width:110px;overflow:hidden}`
class _MBar extends StatelessWidget {
  final double winLeft;
  final double winWidth;
  final double point;
  final bool bad;

  const _MBar({
    required this.winLeft,
    required this.winWidth,
    required this.point,
    required this.bad,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 110,
      height: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          return Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: c.sunk)),
              // .mbar .win
              Positioned(
                left: w * winLeft / 100,
                width: w * winWidth / 100,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.passSoft,
                    border: Border(
                      left: BorderSide(color: c.pass),
                      right: BorderSide(color: c.pass),
                    ),
                  ),
                ),
              ),
              // .mbar .pt
              Positioned(
                left: w * point / 100,
                top: 3,
                bottom: 3,
                width: bad ? 4 : 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: bad ? c.fail : c.ink2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ===========================================================================
// HV INSULATION
// ===========================================================================

class HvView extends StatelessWidget {
  final AppState s;
  const HvView({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final pill = s.pillFor('hv');
    final canRun = s.can('hv').$1;

    final body = Cols([
      ViewBar([
        const StageBadge('Stage 2', hv: true),
        Text('HV insulation', style: t.viewbarH2),
        Conn(s.hvConnName(), hv: true),
        Pill(pill.variant, pill.text),
        const FlexSpacer(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250),
          child: Text('energizes the fixture to 500 V — keep clear',
              style: t.why),
        ),
        Btn('Run HV · 500 V',
            variant: BtnVariant.hv,
            big: true,
            disabled: !canRun,
            onTap: canRun ? () => s.runTest('hv') : null),
      ]),
      Netbar(s: s, dom: 'hv', useKey: 'hv'),
      Band([
        BandItem('Connector', Conn(s.hvConnName(), hv: true)),
        BandItem(
          'Stack',
          Text(
            '${s.stack} card${s.stack > 1 ? "s" : ""} · ${s.stack * 64} HS + '
            '${s.stack * 64} LS',
            style: t.bandV,
          ),
        ),
        // "Stack" is operator-picked, not detected (see s.stack's own note
        // in app_state.dart). Stimulus/Sense/Return are fixed hardware
        // facts, accurate to the current schematic. "trip 0.045 V" is the
        // real fixed threshold `mLeakBad` uses below. "≥ 10 MΩ" stays fixed
        // text rather than reading `s.limits.insMinMohm` for real: FW-11
        // (PROJECT_LOG.md) found the firmware's own `LIMITS SET
        // ins_min_mohm` value is off by 1000x from what "10 MΩ" actually
        // means and has no effect on the pass/fail verdict either way — a
        // live number here would be either wrong or would silently imply
        // this is what the verdict is gated on, which it isn't. Needs FW-11
        // resolved first, not a GUI-side unit guess.
        BandItem(
          'Stimulus',
          Text('500 V DC · R3002 1 MΩ',
              style: t.bandV.copyWith(color: c.hv)),
        ),
        BandItem(
            'Sense', Text('AD7476 U302 · SPI2-iso', style: t.bandV)),
        BandItem('Return',
            Text('all LS closed except own', style: t.bandV)),
        BandItem('Limit',
            Text('≥ 10 MΩ · trip 0.045 V', style: t.bandV)),
      ]),
      TwoUp(
        main: Cols([
          _RelayPanel(s: s),
          _NetResults(s: s),
          _InsulConnectionResults(s: s),
        ]),
        side: Cols([
          _HvRailPanel(s: s),
          // Static topology diagram, not live data - accurate to the
          // schematic (DAC8830/CA05P-5/R3002/R3004 unaffected by FW-12,
          // unlike the Resistance view's now-corrected stale DAC8775
          // references).
          HtPanel(
            header: const [PanelTitle('Leakage loop')],
            child: PanelPad(PathBox(
              const [
                PathSpan('DAC8830 → CA05P-5 → '),
                PathSpan('+500 V', bold: true),
                PathSpan('\n→ R3002 1 MΩ → INS_VIN → '),
                PathSpan('HS reed[n]', bold: true),
                PathSpan(
                    '\n→ net under test → [insulation] → adjacent conductor\n→ '),
                PathSpan('its LS reed', bold: true),
                PathSpan(' → HV_RET → R3004 1 kΩ → GND\nclose every LS '),
                PathSpan('except', bold: true),
                PathSpan(' net n’s own return'),
              ],
              hv: true,
            )),
          ),
          HtPanel(
            header: const [PanelTitle('Safety')],
            child: PanelPad(Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Kv([
                  // No protocol field reports interlock state at all -
                  // honestly unverified rather than an unconditional "safe",
                  // same rule verifyChecks row 5 (app_state.dart) follows:
                  // the GUI must never show a safe state it hasn't been told
                  // is real.
                  const KvRow(
                    'Interlock',
                    KvText('not reported by the instrument · unverified'),
                  ),
                  const KvRow('Switching',
                      KvText('cold · discharge before every relay change')),
                  const KvRow('Discharge',
                      KvText('passive · 10.05 MΩ · 200 ms wait')),
                  KvRow(
                    'Return map',
                    KvText(s.nlHv.loaded
                        ? 'HV netlist · per net'
                        : '— none loaded'),
                  ),
                ]),
                const SizedBox(height: 12),
                RowWrap([
                  Btn('Emergency discharge',
                      variant: BtnVariant.ghostHv, onTap: s.abort),
                  // No protocol command exists for a relay self-test yet —
                  // see Doc/GUI_protocol_command_coverage.md §4.
                  Btn('Relay self-test', disabled: true, onTap: null),
                ]),
              ],
            )),
          ),
        ]),
      ),
    ]);

    return LockOverlay(
      locked: s.stage2 == 'lock',
      text: 'HV runs on J-HV, a different connector with its own netlist. Pass '
          'continuity and resistance on J-MTX, then move the harness to the HV '
          'fixture to unlock this test.',
      child: body,
    );
  }
}

/// `#hvCards` — `buildCards()` and `setRelays()`. `AppState._onInsul` calls
/// `setRelays(n, !pass)` for every real `!INSUL` result (GUI-09/CL-40), so
/// this grid reflects an actual run in progress, not only the fault-card
/// click path.
class _RelayPanel extends StatelessWidget {
  final AppState s;
  const _RelayPanel({required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return HtPanel(
      header: [
        const PanelTitle('Relay state'),
        const FlexSpacer(),
        Lbl(s.hvNetLbl),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // .cards{gap:1px;background:var(--line-soft)}
          ColoredBox(
            color: c.lineSoft,
            child: Column(
              children: [
                for (var ci = 0; ci < 4; ci++) ...[
                  if (ci > 0) const SizedBox(height: 1),
                  _CardRow(s: s, index: ci, fitted: ci < s.stack),
                ],
              ],
            ),
          ),
          Legend(
            [
              LegendItem(c.hv, 'energized HS'),
              LegendItem(c.accent, 'LS closed (return)'),
              LegendItem(c.gridEmpty, 'open'),
              LegendItem(c.fail, 'leakage path found'),
            ],
            trailing: 'return pattern comes from the HV netlist',
          ),
        ],
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  final AppState s;
  final int index;
  final bool fitted;
  const _CardRow(
      {required this.s, required this.index, required this.fitted});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Opacity(
      // .card-row.absent{opacity:.5}
      opacity: fitted ? 1 : .5,
      child: Container(
        color: c.panel,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RowWrap.gapped(
              10,
              [
                Text('H${index + 1}', style: t.cardName),
                Conn('J-HV${index + 1}', hv: true, fontSize: 11),
                const Lbl('64 HS + 64 LS'),
                const FlexSpacer(),
                Pill(fitted ? PillVariant.ok : PillVariant.idle,
                    fitted ? 'Ready' : 'Not fitted'),
              ],
            ),
            const SizedBox(height: 9),
            _RelayRow(s: s, label: 'HS', card: index, low: false),
            const SizedBox(height: 7),
            _RelayRow(s: s, label: 'LS', card: index, low: true),
          ],
        ),
      ),
    );
  }
}

/// `.relay-row` + `.relays{grid-template-columns:repeat(64,1fr);gap:2px}`
class _RelayRow extends StatelessWidget {
  final AppState s;
  final String label;
  final int card;
  final bool low;

  const _RelayRow({
    required this.s,
    required this.label,
    required this.card,
    required this.low,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
            width: 34,
            child: Text(label, style: context.type.relayLabel)),
        const SizedBox(width: 10),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            const n = 64;
            const gap = 2.0;
            final cell = math.max(1.0, (box.maxWidth - gap * (n - 1)) / n);
            return SizedBox(
              height: cell,
              child: Row(
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    _cell(c, cell,
                        s.relayCell(low: low, card: card, index: i)),
                  ],
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _cell(HtColors c, double size, String kind) {
    // .relays i{background:var(--grid-empty)} + .closed/.src/.leak/.absent
    switch (kind) {
      case 'absent':
        return SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      case 'closed':
        return _solid(size, c.accent);
      case 'src':
        return SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.hv,
              borderRadius: BorderRadius.circular(1),
              // box-shadow:0 0 0 1px var(--hv)
              boxShadow: [
                BoxShadow(color: c.hv, spreadRadius: 1, blurRadius: 0),
              ],
            ),
          ),
        );
      case 'leak':
        return _solid(size, c.fail);
      default:
        return _solid(size, c.gridEmpty);
    }
  }

  Widget _solid(double size, Color color) => SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      );
}

/// The "Net results" table — ranked from real `!INSUL` results as they
/// stream in (see AppState._onInsul), same live-ranking pattern as
/// _RankedTable above. Worst (lowest insulation resistance) first. Resolves
/// to real data once a real netlist is loaded (pinHi is null on the demo
/// harness, so _onInsul has nothing to match against until then).
class _NetResults extends StatelessWidget {
  final AppState s;
  const _NetResults({required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ranked = [...s.nets]..sort((a, b) => a.ins.compareTo(b.ins));
    final rows = ranked.take(6).toList();

    return HtPanel(
      header: const [
        PanelTitle('Net results'),
        FlexSpacer(),
        Lbl('worst 6'),
      ],
      child: HtTable(
        columns: const [
          HtCol('Net'),
          HtCol('Conn'),
          HtCol('Card'),
          HtCol('HS relay'),
          HtCol('Insulation', right: true),
          HtCol('Result'),
        ],
        rows: [
          for (final n in rows)
            [
              Td(n.name),
              // GUI-11: real connector once a real netlist is loaded (the
              // demo/placeholder harness has one too, just not tied to any
              // actual instrument data).
              Td(n.src.c),
              Td('H${n.card + 1}', numeric: true),
              Td('HS-${pad(n.relay, 2)}', numeric: true),
              Td('${n.ins.toStringAsFixed(1)} MΩ',
                  numeric: true, color: n.insFail ? c.fail : null),
              Tag(n.insFail ? TagVariant.bad : TagVariant.ok,
                  n.insFail ? 'Fail' : 'Pass'),
            ],
        ],
      ),
    );
  }
}

/// "All connections in one table" for insulation (GUI-11) — `_NetResults`
/// above only ever shows the worst 6 nets by insulation resistance; this
/// shows every real `!INSUL` result the current run has produced.
class _InsulConnectionResults extends StatelessWidget {
  final AppState s;
  const _InsulConnectionResults({required this.s});

  @override
  Widget build(BuildContext context) {
    return HtPanel(
      header: const [
        PanelTitle('Connection results'),
        FlexSpacer(),
        Lbl('every net under test'),
      ],
      child: ConnectionResultsTable(
        columns: const [
          'Test #', 'Net', 'HV Card', 'HS Pin', 'Insulation (MΩ)', //
        ],
        rows: [
          for (final r in s.insulRowsLive)
            ConnectionResultRow(
              cells: [
                '${r.testNum}',
                r.net,
                r.hvCard,
                r.hsPin,
                r.insulationMohm.toStringAsFixed(1),
              ],
              bad: r.status != 'PASS',
              statusLabel: r.status == 'PASS' ? 'Pass' : 'Fail',
            ),
        ],
        emptyMessage:
            'No results yet — run insulation to populate this table.',
      ),
    );
  }
}

/// `#gRail`, `#gTrack`, `.meters`
class _HvRailPanel extends StatelessWidget {
  final AppState s;
  const _HvRailPanel({required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return HtPanel(
      header: [
        const PanelTitle('HV rail'),
        const FlexSpacer(),
        Pill(s.hvStatePill.variant, s.hvStatePill.text),
      ],
      child: PanelPad(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // .hvgauge - both s.gRail and the track bar below (s.gTrack) are
            // real, driven from the live HvEvent.millivolts in paintLink().
            Row(
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${s.gRail}',
                        style: t.hvGauge(s.gRail > 10 ? c.hv : c.ink3),
                      ),
                      TextSpan(
                        text: ' V',
                        style: t.mono(size: 14, color: c.ink3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // .hvtrack
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          height: 8,
                          color: c.sunk,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: s.gTrack.clamp(0.0, 1.0),
                            child: ColoredBox(color: c.hv),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Lbl('target 500 V · ramp 10 %/step'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // .meters - both s.mLeak and s.mSense are real, computed in
            // paintLink() from live hvMv and the last-tested net's !INSUL
            // result via the R3002/R3004 sense divider.
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: c.lineSoft),
                borderRadius: BorderRadius.circular(kRadius),
              ),
              clipBehavior: Clip.antiAlias,
              child: ColoredBox(
                color: c.lineSoft,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _Meter(
                          label: 'Leakage',
                          value: s.mLeak,
                          unit: 'V',
                          range: 'trip ≥ 0.045 V',
                          bad: s.mLeakBad,
                        ),
                      ),
                      const SizedBox(width: 1),
                      Expanded(
                        child: _Meter(
                          label: 'HV_Sense',
                          value: s.mSense,
                          unit: 'V',
                          range: 'ratio 0.00049',
                          bad: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String range;
  final bool bad;

  const _Meter({
    required this.label,
    required this.value,
    required this.unit,
    required this.range,
    required this.bad,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Container(
      color: c.panel,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Lbl(label),
          const SizedBox(height: 6),
          Text.rich(TextSpan(children: [
            TextSpan(text: value, style: t.meter(bad ? c.fail : c.ink)),
            TextSpan(text: unit, style: t.meterUnit),
          ])),
          const SizedBox(height: 6),
          Text(range, style: t.meterRange),
        ],
      ),
    );
  }
}
