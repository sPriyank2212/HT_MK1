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
      Band([
        const BandItem('Connector', Conn('J-MTX')),
        BandItem(
          'Scope',
          Text(s.nlMtx.loaded ? '${s.nlMtx.nets} declared pairs' : 'no netlist',
              style: t.bandV),
        ),
        BandItem('Excitation',
            Text('1.84 mA · DAC8775 ch A', style: t.bandV)),
        BandItem(
            'Sense', Text('ADS124S08 U68 · SPI1', style: t.bandV)),
        BandItem('Gain', Text('PGA ×16 · 20 SPS', style: t.bandV)),
        BandItem('Offset cal',
            Text('0.412 Ω subtracted', style: t.bandV)),
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
        ]),
        side: Cols([
          HtPanel(
            header: const [PanelTitle('Measurement conditions')],
            child: PanelPad(Kv([
              KvRow(
                'Mode',
                KvInline([
                  Text('2-wire fallback ', style: t.kvDd),
                  const Tag(TagVariant.warn, 'HW-01'),
                ]),
              ),
              const KvRow('Set current', KvText('2.000 mA')),
              KvRow(
                'Measured',
                KvInline([
                  Text('1.840 mA ', style: t.kvDd),
                  const Tag(TagVariant.warn, '−8 %'),
                ]),
              ),
              const KvRow(
                  'Compliance', KvText('3.3 V rail · headroom 1.1 V')),
              const KvRow('Resolution', KvText('±0.9 mΩ at PGA ×16')),
              KvRow(
                'Limits from',
                KvText(s.nlMtx.loaded
                    ? 'MTX netlist · per net'
                    : '— none loaded'),
              ),
            ])),
          ),
          HtPanel(
            header: const [PanelTitle('Sense path')],
            child: PanelPad(PathBox(const [
              PathSpan('DAC8775 ch A → I_OUT → '),
              PathSpan('Opto U3', bold: true),
              PathSpan(' (OPTO_CNTR=HIGH)\n'
                  '→ HI_COM → HI mux → HS → harness → LS\n→ LO mux → LO_COM → '),
              PathSpan('R131 100 Ω 0.01 %', bold: true),
              PathSpan(' → GND\nsense: HI_SENSE − LO_SENSE → '),
              PathSpan('ADS124S08 AIN0/AIN1', bold: true),
              PathSpan('\nR = V / I − R_offset'),
            ])),
          ),
          HtPanel(
            header: const [PanelTitle('Actions')],
            child: PanelPad(RowWrap([
              Btn('Re-measure worst', onTap: () {}),
              Btn('Auto-range PGA', onTap: () {}),
              Btn('Compliance sweep', onTap: () {}),
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
        ]),
        side: Cols([
          _HvRailPanel(s: s),
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
                  KvRow(
                    'Interlock',
                    KvInline([
                      Text('closed ', style: t.kvDd),
                      const Tag(TagVariant.ok, 'safe'),
                    ]),
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
                  Btn('Relay self-test', onTap: () {}),
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

/// `#hvCards` — `buildCards()` and `setRelays()`
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

/// The static "Net results" table from the markup.
class _NetResults extends StatelessWidget {
  final AppState s;
  const _NetResults({required this.s});

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('GND_RET', 'H1', 'HS-03', '0.052', '3.2 MΩ', TagVariant.bad, 'Fail'),
      ('PWR_28V_A', 'H1', 'HS-01', '0.021', '11.4 MΩ', TagVariant.warn,
          'Marginal'),
      ('LAMP_RET', 'H2', 'HS-19', '0.014', '18.6 MΩ', TagVariant.ok, 'Pass'),
      ('ARINC_A_LO', 'H1', 'HS-15', '0.006', '46.2 MΩ', TagVariant.ok, 'Pass'),
      ('SENSE_RTD_1', 'H3', 'HS-11', '0.004', '72.1 MΩ', TagVariant.ok, 'Pass'),
      ('PWR_28V_B', 'H1', 'HS-02', '0.003', '98.4 MΩ', TagVariant.ok, 'Pass'),
    ];

    return HtPanel(
      header: const [
        PanelTitle('Net results'),
        FlexSpacer(),
        Lbl('worst 6'),
      ],
      child: HtTable(
        columns: const [
          HtCol('Net'),
          HtCol('Card'),
          HtCol('HS relay'),
          HtCol('Leak V', right: true),
          HtCol('Insulation', right: true),
          HtCol('Result'),
        ],
        rows: [
          for (final r in rows)
            [
              Td(r.$1),
              Td(r.$2, numeric: true),
              Td(r.$3, numeric: true),
              Td(r.$4, numeric: true),
              Td(r.$5, numeric: true),
              Tag(r.$6, r.$7),
            ],
        ],
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
            // .hvgauge
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
            // .meters
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
