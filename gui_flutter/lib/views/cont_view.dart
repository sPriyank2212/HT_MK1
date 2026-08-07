/// `<section id="v-cont">` — continuity, including the harness wiring diagram.
library;

import 'package:flutter/widgets.dart';

import '../app/app_state.dart';
import '../app/parts.dart';
import '../design/model.dart';
import '../design/painters.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';

class ContView extends StatelessWidget {
  final AppState s;
  const ContView({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final pill = s.pillFor('cont');
    final canRun = s.can('cont').$1;
    final cross = s.cmode == 'cross';

    return Cols([
      ViewBar([
        const StageBadge('Stage 1'),
        Text('Continuity', style: context.type.viewbarH2),
        const Conn('J-MTX'),
        Pill(pill.variant, pill.text),
        const FlexSpacer(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250),
          child: Text(s.cvWhy, style: context.type.why),
        ),
        Btn('Run continuity',
            variant: BtnVariant.primary,
            big: true,
            disabled: !canRun,
            onTap: canRun ? () => s.runTest('cont') : null),
      ]),
      Netbar(s: s, dom: 'mtx', useKey: 'cont'),
      Netbar(s: s, dom: 'fix', useKey: 'cont'),
      _ModeSelect(s: s),
      Band([
        const BandItem('Connector', Conn('J-MTX')),
        BandItem('Switching',
            Text('CD4067 · 256 HS × 256 LS', style: context.type.bandV)),
        BandItem('Stimulus',
            Text('3.3 V via R26 10 kΩ', style: context.type.bandV)),
        BandItem(
            'Sense', Text('AD7476 U4 · SPI3', style: context.type.bandV)),
        BandItem('Threshold',
            Text('< 0.80 V connected', style: context.type.bandV)),
        BandItem('Scan scope',
            Text(s.scScope, style: context.type.bandV)),
      ]),
      HtPanel(
        child: cross
            ? Tally([
                TallyItem('Nets discovered', s.auNets, 'acc'),
                TallyItem('Nodes mapped', s.auNodes),
                TallyItem('Multi-drop', s.auMulti, 'acc'),
                TallyItem('HS columns swept', s.auCols),
              ])
            : Tally([
                TallyItem(
                    'Expected nets', s.nlMtx.loaded ? '${s.nlMtx.nets}' : '—'),
                TallyItem('Verified', s.ctFound, 'ok'),
                TallyItem('Missing · F06', s.ctMiss, 'bad'),
                TallyItem('Unexpected · F07', s.ctExtra, 'bad'),
              ]),
      ),
      _WiringPanel(s: s),
      _ThreeUp(s: s),
      if (cross) _DiscoveryPanel(s: s),
    ]);
  }
}

// ---------------------------------------------------------------------------
// mode selector
// ---------------------------------------------------------------------------

/// `.modesel`
class _ModeSelect extends StatelessWidget {
  final AppState s;
  const _ModeSelect({required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(kPanelRadius),
        boxShadow: c.shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, constraints) {
        // .modesel button{flex:1;min-width:250px}
        final stack = constraints.maxWidth < 500;
        final children = [
          _ModeButton(
            s: s,
            mode: 'net',
            title: 'Netlist',
            desc: 'Test the pairs the netlist expects, then check each net '
                'against every\nother. Reports missing wires (F06) and '
                'unexpected shorts (F07).',
            req: 'requires the MTX netlist',
            reqNeed: true,
            border: !stack,
          ),
          _ModeButton(
            s: s,
            mode: 'cross',
            title: 'Cross continuity',
            desc: 'One to many. Energise one HS, scan all 256 LS, record every '
                'hit.\nFinds splices and multi-drop nets, and writes a netlist '
                'as it goes.',
            req: 'no netlist needed — it produces one',
            reqNeed: false,
            border: false,
          ),
        ];
        return stack
            ? Column(children: children)
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final w in children) Expanded(child: w),
                  ],
                ),
              );
      }),
    );
  }
}

class _ModeButton extends StatefulWidget {
  final AppState s;
  final String mode;
  final String title;
  final String desc;
  final String req;
  final bool reqNeed;
  final bool border;

  const _ModeButton({
    required this.s,
    required this.mode,
    required this.title,
    required this.desc,
    required this.req,
    required this.reqNeed,
    required this.border,
  });

  @override
  State<_ModeButton> createState() => _ModeButtonState();
}

class _ModeButtonState extends State<_ModeButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final on = widget.s.cmode == widget.mode;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => widget.s.setMode(widget.mode),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: on
                ? c.accentSoft
                : _hover
                    ? c.panel2
                    : const Color(0x00000000),
            border: widget.border
                ? Border(right: BorderSide(color: c.lineSoft))
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // .modesel .mt::before — the radio dot
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: on ? c.accent : c.ink3, width: 2),
                    ),
                    child: on
                        ? Center(
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                  color: c.accent, shape: BoxShape.circle),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(widget.title,
                      style: t.modeTitle(on ? c.accent : c.ink)),
                ],
              ),
              const SizedBox(height: 5),
              Text(widget.desc, style: t.modeDesc),
              const SizedBox(height: 3),
              Text(widget.req.toUpperCase(),
                  style: t.modeReq(widget.reqNeed ? c.warn : c.pass)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// harness wiring diagram
// ---------------------------------------------------------------------------

class _WiringPanel extends StatefulWidget {
  final AppState s;
  const _WiringPanel({required this.s});

  @override
  State<_WiringPanel> createState() => _WiringPanelState();
}

class _WiringPanelState extends State<_WiringPanel> {
  Offset? _tipAt;
  Net? _tipNet;

  DiagState _state() => DiagState(
        nets: widget.s.nets,
        netAt: widget.s.netAt,
        tested: widget.s.tested,
        faultF06: widget.s.faultsOn['f06']!,
        hoverNet: widget.s.hoverNet,
        selNet: widget.s.selNet,
        filter: widget.s.filter,
        selConn: widget.s.selConn,
        scanX: widget.s.scanX,
        // const reduce=matchMedia("(prefers-reduced-motion: reduce)").matches
        reduceMotion: MediaQuery.of(context).disableAnimations,
      );

  Net? _pick(DiagState st, Offset model) {
    final pin = hitPin(st, model.dx, model.dy);
    return pin != null ? pin.net : hitNet(st, model.dx, model.dy);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.s;
    final st = _state();
    final visible = st.visible().length;

    return HtPanel(
      header: [
        const PanelTitle('Harness wiring'),
        const FlexSpacer(),
        Lbl(s.mxHint),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // .diagbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.lineSoft)),
            ),
            child: RowWrap.gapped(
              10,
              [
                const Lbl('Show'),
                Seg(
                  options: const ['All wires', 'Faults only', 'Selected connector'],
                  selected: switch (s.filter) {
                    'fault' => 1,
                    'conn' => 2,
                    _ => 0,
                  },
                  onSelect: (i) =>
                      s.setFilter(['all', 'fault', 'conn'][i]),
                ),
                const FlexSpacer(),
                Lbl('$visible of ${s.netc} nets shown'),
              ],
            ),
          ),
          // .diagwrap{position:relative;padding:14px}
          Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = w * kCanvasH / kCanvasW;

              Offset toModel(Offset local) => Offset(
                    local.dx * kCanvasW / w,
                    local.dy * kCanvasH / h,
                  );

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.precise, // cursor:crosshair
                    onHover: (e) {
                      final model = toModel(e.localPosition);
                      final n = _pick(st, model);
                      s.setHover(n);
                      setState(() {
                        _tipNet = n;
                        _tipAt = n == null ? null : e.localPosition;
                      });
                    },
                    onExit: (_) {
                      s.setHover(null);
                      setState(() {
                        _tipNet = null;
                        _tipAt = null;
                      });
                    },
                    child: GestureDetector(
                      onTapUp: (e) {
                        final model = toModel(e.localPosition);
                        s.select(_pick(st, model));
                      },
                      child: Container(
                        width: w,
                        height: h,
                        decoration: BoxDecoration(
                          color: c.sunk,
                          border: Border.all(color: c.line),
                          borderRadius: BorderRadius.circular(kRadius),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: CustomPaint(
                          painter: DiagramPainter(st, c),
                          size: Size(w, h),
                        ),
                      ),
                    ),
                  ),
                  if (_tipNet != null && _tipAt != null)
                    _Tip(
                      net: _tipNet!,
                      state: st.netState(_tipNet!),
                      at: _tipAt!,
                      maxLeft: w,
                    ),
                ],
              );
            }),
          ),
          Legend(
            [
              LegendItem(c.pass, 'pass', line: true),
              LegendItem(c.fail, 'open / fail', line: true),
              LegendItem(c.gridEmpty, 'not tested', line: true),
              LegendItem(c.accent, 'Y joint · branch splice', round: true),
              LegendItem(c.ink2, 'I joint · inline splice', line: true),
            ],
            trailing:
                'connector faces and pin maps come from the fixture file',
          ),
        ],
      ),
    );
  }
}

/// `.tip{position:absolute;pointer-events:none;max-width:280px}`
class _Tip extends StatelessWidget {
  final Net net;
  final String state;
  final Offset at;
  final double maxLeft;

  const _Tip({
    required this.net,
    required this.state,
    required this.at,
    required this.maxLeft,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    const tipW = 280.0;
    // tip.style.left = min(m.rx+14, cv.clientWidth-tw-8)
    final left = (at.dx + 14).clamp(0.0, (maxLeft - tipW - 8).clamp(0.0, maxLeft));

    final detail = StringBuffer()
      ..write('${refOf(net.src)} → ${net.dsts.map(refOf).join(" · ")}');
    if (net.joint == 'Y') {
      detail.write('\nY joint · 1:${net.dsts.length} branch');
    } else if (net.joint == 'I') {
      detail.write('\nI joint · inline splice');
    }
    detail.write('\n');
    detail.write(state == 'idle'
        ? 'not tested'
        : state == 'fail'
            ? 'OPEN · 3.281 V (F06)'
            : '${net.v.toStringAsFixed(3)} V · connected');

    return Positioned(
      left: left,
      top: at.dy + 16,
      child: IgnorePointer(
        child: Container(
          constraints: const BoxConstraints(maxWidth: tipW),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: c.panel,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(kRadius),
            boxShadow: c.shadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(net.name, style: t.tipName),
              const SizedBox(height: 3),
              Text(detail.toString(), style: t.tipDetail),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// inspector / connectors / switch path
// ---------------------------------------------------------------------------

/// `.three{grid-template-columns:repeat(auto-fit,minmax(260px,1fr))}`
class _ThreeUp extends StatelessWidget {
  final AppState s;
  const _ThreeUp({required this.s});

  @override
  Widget build(BuildContext context) {
    final cols = <Widget>[
      _Inspector(s: s),
      _ConnectorList(s: s),
      Cols([
        HtPanel(
          header: const [PanelTitle('Switch path')],
          child: PanelPad(_switchPath(context, s)),
        ),
        if (s.cmode == 'cross') _DiscoveredNetlist(s: s),
      ]),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final perRow = ((constraints.maxWidth + 14) / (260 + 14))
          .floor()
          .clamp(1, cols.length);
      if (perRow == 1) return Cols(cols);
      final rows = <List<Widget>>[];
      for (var i = 0; i < cols.length; i += perRow) {
        rows.add(cols.sublist(
            i, (i + perRow) > cols.length ? cols.length : i + perRow));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < rows[r].length; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(child: rows[r][i]),
                ],
              ],
            ),
          ],
        ],
      );
    });
  }

  Widget _switchPath(BuildContext context, AppState s) {
    final n = s.selNet;
    if (n == null) {
      return PathBox(const [
        PathSpan('Select a wire to resolve the hardware path.'),
      ]);
    }
    String bank(int i) => 'bank ${i ~/ 16} ch ${pad(i % 16, 2)}';
    return PathBox([
      const PathSpan('ADC_IN → '),
      const PathSpan('Opto U3', bold: true),
      const PathSpan(' (OPTO_CNTR=LOW) → HI_COM\n→ HI mux '),
      PathSpan(bank(n.hs), bold: true),
      const PathSpan(' — EN via U101 @0x20\n→ '),
      PathSpan(refOf(n.src), bold: true),
      const PathSpan(' → harness → '),
      PathSpan(n.dsts.map(refOf).join(' / '), bold: true),
      const PathSpan('\n→ LO mux '),
      PathSpan(bank(n.ls), bold: true),
      const PathSpan(' — EN via U102 @0x21\n→ LO_COM → R131 100 Ω → GND'),
    ]);
  }
}

/// `#insNet` etc — `function inspect(n)`
class _Inspector extends StatelessWidget {
  final AppState s;
  const _Inspector({required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final n = s.selNet;

    if (n == null) {
      return HtPanel(
        header: const [
          PanelTitle('Net inspector'),
          FlexSpacer(),
          Tag(TagVariant.mut, 'nothing selected'),
        ],
        child: PanelPad(Kv(const [
          KvRow('Net', KvText('—', big: true)),
          KvRow('From', KvText('—')),
          KvRow('To', KvText('—')),
          KvRow('Topology', KvText('—')),
          KvRow('Measured', KvText('—')),
        ])),
      );
    }

    final st = DiagState(
      nets: s.nets,
      netAt: s.netAt,
      tested: s.tested,
      faultF06: s.faultsOn['f06']!,
    ).netState(n);

    final (tagVariant, tagText) = switch (st) {
      'fail' => (TagVariant.bad, 'open'),
      'pass' => (TagVariant.ok, 'connected'),
      _ => (TagVariant.mut, 'not tested'),
    };

    final topology = n.joint == 'Y'
        ? Text('Y joint · 1:${n.dsts.length} branch splice',
            style: t.kvDd.copyWith(color: c.accent))
        : KvText(n.joint == 'I'
            ? 'I joint · inline butt splice'
            : '1:1 · point to point');

    final measured = st == 'idle'
        ? '—'
        : st == 'fail'
            ? '3.281 V  —  OPEN (F06)'
            : '${n.v.toStringAsFixed(3)} V  —  below 0.80 V  ·  ${n.wire}';

    return HtPanel(
      header: [
        const PanelTitle('Net inspector'),
        const FlexSpacer(),
        Tag(tagVariant, tagText),
      ],
      child: PanelPad(Kv([
        KvRow('Net', KvText(n.name, big: true)),
        KvRow('From', KvText('${refOf(n.src)}  ·  ${kConn[n.src.c]!.label}')),
        KvRow(
          'To',
          KvText(n.dsts
              .map((d) => '${refOf(d)}  ·  ${kConn[d.c]!.label}')
              .join('\n')),
        ),
        KvRow('Topology', topology),
        KvRow('Measured', KvText(measured)),
      ])),
    );
  }
}

/// `#connList` — `function renderConnList()`
class _ConnectorList extends StatelessWidget {
  final AppState s;
  const _ConnectorList({required this.s});

  @override
  Widget build(BuildContext context) {
    return HtPanel(
      header: [
        const PanelTitle('Fixture connectors'),
        const FlexSpacer(),
        Lbl('${kFix.connectors.length} connectors · $kFixPins pins'),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < kFix.connectors.length; i++)
            _connRow(context, kFix.connectors[i],
                last: i == kFix.connectors.length - 1),
        ],
      ),
    );
  }

  Widget _connRow(BuildContext context, ConnectorDef conn,
      {required bool last}) {
    final c = context.colors;
    final t = context.type;
    final count = s.nets
        .where((n) =>
            n.src.c == conn.id || n.dsts.any((d) => d.c == conn.id))
        .length;

    return HoverRow(
      onTap: () => s.toggleConn(conn.id),
      pressed: s.selConn == conn.id,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.lineSoft)),
        ),
        child: Row(
          children: [
            Text(conn.id, style: t.connId(c.accent)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(conn.label, style: t.connLabel),
                  const SizedBox(height: 1),
                  Text(
                    '${kTypeName[conn.type]} · ${conn.pins} way · board '
                    '${conn.side == "L" ? "HS" : "LS"} ${pad(conn.base, 3)}–'
                    '${pad(conn.base + conn.pins - 1, 3)}',
                    style: t.connMeta,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 11),
            Tag(TagVariant.mut, '$count nets'),
          ],
        ),
      ),
    );
  }
}

/// `.panel.only-cross` — "Discovered netlist"
class _DiscoveredNetlist extends StatelessWidget {
  final AppState s;
  const _DiscoveredNetlist({required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return HtPanel(
      header: const [PanelTitle('Discovered netlist')],
      child: PanelPad(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.crossNote,
                style: t.ui(size: 12, color: c.ink2, height: 1.55)),
            const SizedBox(height: 11),
            RowWrap([
              Btn('Save as MTX netlist',
                  variant: BtnVariant.primary,
                  disabled: !s.saveNlEnabled,
                  onTap: s.saveNlEnabled ? s.saveDiscoveredNetlist : null),
              Btn('Export CSV', onTap: () {}),
            ]),
          ],
        ),
      ),
    );
  }
}

/// `.panel.only-cross` — "Discovery — one to many"
class _DiscoveryPanel extends StatelessWidget {
  final AppState s;
  const _DiscoveryPanel({required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    // buildAutoTable(): multi-drop nets, then two I joints, then three plain.
    final rows = <Net>[
      ...s.nets.where((n) => n.dsts.length > 1),
      ...s.nets.where((n) => n.joint == 'I').take(2),
      ...s.nets.where((n) => n.joint == null).take(3),
    ].take(9).toList();

    return HtPanel(
      header: const [
        PanelTitle('Discovery — one to many'),
        FlexSpacer(),
        Lbl('every LS that answered each energised HS'),
      ],
      child: HtTable(
        minWidth: 700,
        columns: const [
          HtCol('Auto net'),
          HtCol('HS'),
          HtCol('LS answered'),
          HtCol('Fan-out', right: true),
          HtCol('Worst V', right: true),
          HtCol('Topology'),
        ],
        rows: [
          for (var i = 0; i < rows.length; i++)
            [
              Td('AUTO_${pad(i + 1, 3)}', numeric: true),
              Td(refOf(rows[i].src), numeric: true),
              // .fan
              RowWrap.gapped(
                4,
                [
                  for (final d in rows[i].dsts)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.accentSoft,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(refOf(d), style: t.fan(c.accent)),
                    ),
                ],
              ),
              Td('1:${rows[i].dsts.length}', numeric: true),
              Td('${rows[i].v.toStringAsFixed(3)} V', numeric: true),
              Tag(
                rows[i].dsts.length > 1
                    ? TagVariant.acc
                    : rows[i].joint == 'I'
                        ? TagVariant.warn
                        : TagVariant.mut,
                rows[i].dsts.length > 1
                    ? 'Y joint · branch'
                    : rows[i].joint == 'I'
                        ? 'I joint · inline'
                        : 'point to point',
              ),
            ],
        ],
      ),
    );
  }
}
