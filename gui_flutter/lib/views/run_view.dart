/// `<section id="v-run">` — the operator's home screen.
library;

import 'package:flutter/widgets.dart';

import '../app/app_state.dart';
import '../app/parts.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';

class RunView extends StatelessWidget {
  final AppState s;
  const RunView({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > kMediumBreak;

    final left = Cols([
      Verdict(s: s),
      Netbar(s: s, dom: 'mtx', useKey: 'run'),
      // body[data-phase="hold"] .handover{display:flex}
      if (s.phase == 'hold') Handover(s: s),
      FixtureFlow(s: s),
      _Domains(s: s),
    ]);

    final right = Cols([
      _FaultsPanel(s: s),
      _DemoPanel(s: s),
      _StackPanel(s: s),
    ]);

    if (!wide) {
      // @media (max-width:1080px){.run-grid{grid-template-columns:1fr}}
      return Cols([left, right]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // grid-template-columns:minmax(0,1.5fr) minmax(300px,.9fr)
        Expanded(flex: 15, child: left),
        const SizedBox(width: 14),
        Expanded(flex: 9, child: right),
      ],
    );
  }
}

/// `.domains{grid-template-columns:repeat(auto-fit,minmax(250px,1fr))}`
class _Domains extends StatelessWidget {
  final AppState s;
  const _Domains({required this.s});

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      DomainCard(
        s: s,
        icon: HtIcons.cont,
        title: 'Continuity',
        stage: 'S1 · MTX',
        state: s.dContS,
        cond: s.dcCond,
        stat: s.dcN,
        unit: s.dcU,
        bar: s.dcBar,
        runKey: 'cont',
        runLabel: 'Run continuity',
        runVariant: BtnVariant.primary,
        goView: 'cont',
      ),
      DomainCard(
        s: s,
        icon: HtIcons.res,
        title: 'Resistance',
        stage: 'S1 · MTX',
        state: s.dResS,
        // MOCK: literal string, never updates. Doesn't reflect the IDAC's
        // actual 2 mA excitation (FW-12) or the real PGA gain/offset that
        // Diagnostics' Calibration panel already reads from CAL GET.
        cond: '1.84 mA · 4-wire\n'
            'ADS124S08 U68 · SPI1 · PGA ×16\n'
            'OPTO_CNTR = HIGH',
        stat: s.drN,
        unit: 'out of limit',
        bar: s.drBar,
        runKey: 'res',
        runLabel: 'Run resistance',
        runVariant: BtnVariant.primary,
        goView: 'res',
      ),
      DomainCard(
        s: s,
        icon: HtIcons.hv,
        title: 'HV insulation',
        stage: 'S2 · HV',
        state: s.dHvS,
        cond: s.dhCond,
        stat: s.dhN,
        unit: 'below 10 MΩ',
        bar: s.dhBar,
        runKey: 'hv',
        runLabel: 'Run HV · 500 V',
        runVariant: BtnVariant.hv,
        goView: 'hv',
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      // auto-fit with a 250px minimum
      final perRow = ((constraints.maxWidth + 14) / (250 + 14))
          .floor()
          .clamp(1, cards.length);
      final rows = <List<Widget>>[];
      for (var i = 0; i < cards.length; i += perRow) {
        rows.add(cards.sublist(
            i, (i + perRow) > cards.length ? cards.length : i + perRow));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) const SizedBox(height: 14),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows[r].length; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    Expanded(child: rows[r][i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}

/// `<div class="panel">` with `#faultList`
class _FaultsPanel extends StatelessWidget {
  final AppState s;
  const _FaultsPanel({required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final list = s.faultList;
    final pill = s.faultCountPill;

    return HtPanel(
      header: [
        const PanelTitle('Faults'),
        const FlexSpacer(),
        Pill(pill.variant, pill.text),
      ],
      child: list.isEmpty
          // .empty{padding:26px 14px;text-align:center}
          ? Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 26),
              child: Text('No faults. Run a test to populate.',
                  style: t.empty, textAlign: TextAlign.center),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < list.length; i++)
                  HoverRow(
                    onTap: () => s.openFault(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        border: i == list.length - 1
                            ? null
                            : Border(
                                bottom: BorderSide(color: c.lineSoft)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // .fault .code{width:52px;text-align:center}
                          Container(
                            width: 52,
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: list[i].hot ? c.hvSoft : c.failSoft,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(list[i].code,
                                style: t.faultCode(
                                    list[i].hot ? c.hv : c.fail)),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(list[i].title, style: t.faultTitle),
                                const SizedBox(height: 2),
                                Text(list[i].detail, style: t.faultDetail),
                              ],
                            ),
                          ),
                          const SizedBox(width: 11),
                          Text(list[i].value,
                              style: t.faultVal(
                                  list[i].hot ? c.hv : c.fail)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The "Demo harness" panel — presentational only, per the README's split of
/// live vs. presentation.
class _DemoPanel extends StatelessWidget {
  final AppState s;
  const _DemoPanel({required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return HtPanel(
      header: [
        const PanelTitle('Demo harness'),
        const FlexSpacer(),
        const Tag(TagVariant.mut, 'mockup only'),
      ],
      child: PanelPad(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Seg(
              options: const ['Good stage 1', 'Faulty stage 1'],
              selected: s.scenario == 'good' ? 0 : 1,
              fill: true,
              onSelect: (i) {
                s.scenario = i == 0 ? 'good' : 'bad';
                s.resetAll();
              },
            ),
            const SizedBox(height: 10),
            Text(
              s.scenario == 'good'
                  ? 'Stage 1 passes, the handover appears, then the two HV '
                      'prompts gate the 500 V pass.'
                  : 'Continuity finds an open on ARINC_A_HI. The gate holds — '
                      'the harness is never moved and HV never runs.',
              style: t.ui(size: 12, color: c.ink3, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "HV stack" panel.
class _StackPanel extends StatelessWidget {
  final AppState s;
  const _StackPanel({required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return HtPanel(
      header: [
        const PanelTitle('HV stack'),
        const FlexSpacer(),
        Pill(PillVariant.acc, '${s.stack} card${s.stack > 1 ? "s" : ""}'),
      ],
      child: PanelPad(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // MOCK: "Detected on I2C2" is false - s.stack is a manual Seg
            // pick (pickStack, below), not read from the instrument. No
            // protocol field for a real detected card count exists.
            Text(
              'Detected on I2C2. The HV netlist must match the fitted stack — '
              'a 4-card netlist on a 3-card stack leaves 64 nets unreachable.',
              style: t.ui(size: 12, color: c.ink2, height: 1.5),
            ),
            const SizedBox(height: 10),
            Seg(
              options: const ['1', '2', '3', '4'],
              selected: s.stack - 1,
              fill: true,
              onSelect: (i) => s.pickStack(i + 1),
            ),
          ],
        ),
      ),
    );
  }
}
