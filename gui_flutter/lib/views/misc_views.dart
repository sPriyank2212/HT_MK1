/// `<section id="v-program">`, `<section id="v-results">` and
/// `<section id="v-diag">`.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../app/app_state.dart';
import '../app/parts.dart';
import '../design/model.dart';
import '../design/painters.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';

// ===========================================================================
// NETLISTS
// ===========================================================================

class ProgramView extends StatelessWidget {
  final AppState s;
  const ProgramView({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return Cols([
      Netbar(s: s, dom: 'mtx', useKey: 'progM'),
      Netbar(s: s, dom: 'hv', useKey: 'progH'),
      HtPanel(
        header: const [PanelTitle('Why two files')],
        child: PanelPad(
          LayoutBuilder(builder: (context, box) {
            final stack = box.maxWidth < 580;
            final left = _why(
              context,
              const Conn('MTX netlist'),
              'Describes the harness on the matrix side: which HS pin connects '
              'to which LS pin, and the resistance window for each net. Fixed '
              'for a given harness drawing — continuity and resistance both '
              'read it.',
            );
            final right = _why(
              context,
              const Conn('HV netlist', hv: true),
              'Describes the same harness against the HV stack: which card and '
              'relay each net lands on, and which LS relays form its return. '
              'Changes with the stack size, so it is a separate file — a '
              '4-card map on a 3-card stack leaves the top 64 nets '
              'unreachable.',
            );
            return stack
                ? Cols.gapped(18, [left, right])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: left),
                      const SizedBox(width: 18),
                      Expanded(child: right),
                    ],
                  );
          }),
        ),
      ),
      HtPanel(
        header: const [
          PanelTitle('MTX nets'),
          FlexSpacer(),
          Lbl('continuity + resistance · showing 8'),
        ],
        child: HtTable(
          minWidth: 640,
          columns: const [
            HtCol('Net'),
            HtCol('Wire'),
            HtCol('HS'),
            HtCol('LS'),
            HtCol('R min', right: true),
            HtCol('R max', right: true),
            HtCol('Topology'),
          ],
          rows: [
            for (final r in _mtxRows)
              [
                Td(r.$1),
                Td(r.$2, numeric: true),
                Td(r.$3, numeric: true),
                Td(r.$4, numeric: true),
                Td(r.$5, numeric: true),
                Td(r.$6, numeric: true),
                Tag(r.$7, r.$8),
              ],
          ],
        ),
      ),
      HtPanel(
        header: [
          const PanelTitle('HV nets'),
          const FlexSpacer(),
          Lbl(s.nlHv.loaded
              ? '${s.nlHv.name} · ${s.nlHv.nets} nets · ${s.nlHv.cards}-card map'
              : 'no HV netlist loaded'),
        ],
        child: s.nlHv.loaded
            ? HtTable(
                minWidth: 640,
                columns: const [
                  HtCol('Net'),
                  HtCol('Card'),
                  HtCol('HS relay'),
                  HtCol('Return LS'),
                  HtCol('Insul min', right: true),
                  HtCol('Reachable'),
                ],
                rows: [
                  for (final r in _hvRows)
                    () {
                      final reach = r.$2 < s.stack;
                      return <Widget>[
                        Td(r.$1),
                        Td('H${r.$2 + 1}', numeric: true),
                        Td('HS-${pad(r.$3, 2)}', numeric: true),
                        Td('all except LS-${pad(r.$3, 2)}', numeric: true),
                        Td('10 MΩ', numeric: true),
                        Tag(reach ? TagVariant.ok : TagVariant.bad,
                            reach ? 'yes' : 'card not fitted'),
                      ];
                    }(),
                ],
              )
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Text('Load an HV netlist to see the relay map.',
                    style: t.td.copyWith(color: c.ink3),
                    textAlign: TextAlign.center),
              ),
      ),
    ]);
  }

  Widget _why(BuildContext context, Widget title, String body) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 7),
          Text(body,
              style: context.type
                  .ui(size: 12.5, color: context.colors.ink2, height: 1.55)),
        ],
      );

  static const List<(String, String, String, String, String, String, TagVariant, String)>
      _mtxRows = [
    ('PWR_28V_A', '14 AWG', 'J1-01 / 001', 'J3-14 / 142', '0.02', '0.35',
        TagVariant.mut, '1:1'),
    ('PWR_28V_B', '14 AWG', 'J1-02 / 002', 'J3-15 / 143', '0.02', '0.35',
        TagVariant.mut, '1:1'),
    ('GND_RET', '12 AWG', 'J1-03 / 003', 'J2-22 / 086', '0.01', '0.20',
        TagVariant.mut, '1:1'),
    ('ARINC_A_HI', '24 AWG TSP', 'J1-14 / 014', 'J2-07 / 071', '0.10', '3.00',
        TagVariant.mut, '1:1'),
    ('ARINC_A_LO', '24 AWG TSP', 'J1-15 / 015', 'J2-08 / 072', '0.10', '3.00',
        TagVariant.mut, '1:1'),
    ('LAMP_CMD', '22 AWG', 'J1-22 / 022', 'J3-05 / 133', '0.05', '2.00',
        TagVariant.mut, '1:1'),
    ('SPLICE_28V', '18 AWG', 'J1-31 / 031', 'J2-04 · J3-09 · J4-01', '0.05',
        '1.20', TagVariant.acc, '1:3 splice'),
    ('SENSE_RTD_1', '26 AWG', 'J2-11 / 075', 'J4-03 / 195', '0.20', '5.00',
        TagVariant.mut, '1:1'),
  ];

  static const List<(String, int, int)> _hvRows = [
    ('GND_RET', 0, 3),
    ('PWR_28V_A', 0, 1),
    ('PWR_28V_B', 0, 2),
    ('ARINC_A_HI', 0, 14),
    ('LAMP_RET', 1, 19),
    ('SENSE_RTD_1', 2, 11),
    ('AUX_SPARE', 3, 7),
  ];
}

// ===========================================================================
// RESULTS
// ===========================================================================

class ResultsView extends StatelessWidget {
  final AppState s;
  const ResultsView({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    return Cols([
      HtPanel(
        header: const [
          PanelTitle('First-pass yield · last 24 builds'),
          FlexSpacer(),
          Pill(PillVariant.acc, '78 %'),
        ],
        child: PanelPad(
          SizedBox(
            height: 54,
            child: CustomPaint(
              painter: SparkPainter(context.colors),
              size: Size.infinite,
            ),
          ),
        ),
      ),
      HtPanel(
        header: [
          const PanelTitle('Run history'),
          const FlexSpacer(),
          RowWrap([
            Btn('Export CSV', onTap: () {}),
            Btn('Print report', onTap: () {}),
          ]),
        ],
        child: HtTable(
          minWidth: 900,
          columns: const [
            HtCol('Run'),
            HtCol('Serial'),
            HtCol('MTX netlist'),
            HtCol('HV netlist'),
            HtCol('Continuity'),
            HtCol('Resistance'),
            HtCol('HV'),
            HtCol('Verdict'),
          ],
          rows: [
            for (final r in _history)
              [
                Td(r.$1, numeric: true),
                Td(r.$2, numeric: true),
                Td(r.$3, numeric: true),
                Td(r.$4, numeric: true),
                Tag(r.$5, r.$6),
                Tag(r.$7, r.$8),
                Tag(r.$9, r.$10),
                Tag(r.$11, r.$12),
              ],
          ],
        ),
      ),
      HtPanel(
        header: const [PanelTitle('Fault pareto · this shift')],
        child: HtTable(
          columns: const [
            HtCol('Code'),
            HtCol('Test'),
            HtCol('Fault'),
            HtCol('Most common location'),
            HtCol('Count', right: true),
            HtCol('Share', right: true),
          ],
          rows: [
            for (final r in _pareto)
              [
                Td(r.$1, numeric: true),
                Td(r.$2),
                Td(r.$3),
                Td(r.$4, numeric: true),
                Td(r.$5, numeric: true),
                Td(r.$6, numeric: true),
              ],
          ],
        ),
      ),
    ]);
  }

  static const _history = <(String, String, String, String, TagVariant, String,
      TagVariant, String, TagVariant, String, TagVariant, String)>[
    ('0418', '24-A0417', 'AV-880_RevC', 'AV-880_HV_3card', TagVariant.ok,
        'Pass', TagVariant.ok, 'Pass', TagVariant.bad, '1 low', TagVariant.bad,
        'Fail'),
    ('0417', '24-A0416', 'AV-880_RevC', 'AV-880_HV_3card', TagVariant.ok,
        'Pass', TagVariant.ok, 'Pass', TagVariant.ok, 'Pass', TagVariant.ok,
        'Pass'),
    ('0416', '24-A0415', '— built', '—', TagVariant.acc, '310 found',
        TagVariant.mut, 'Not run', TagVariant.mut, 'Not run', TagVariant.acc,
        'Netlist built'),
    ('0415', '24-A0414', 'AV-880_RevC', '—', TagVariant.bad, '1 open',
        TagVariant.mut, 'Not run', TagVariant.mut, 'Not run', TagVariant.bad,
        'Fail'),
    ('0414', '24-A0413', 'AV-880_RevC', 'AV-880_HV_3card', TagVariant.ok,
        'Pass', TagVariant.ok, 'Pass', TagVariant.ok, 'Pass', TagVariant.ok,
        'Pass'),
  ];

  static const _pareto = <(String, String, String, String, String, String)>[
    ('F06', 'Continuity', 'Open circuit', 'J2-07 backshell', '14', '46 %'),
    ('F08', 'Resistance', 'Resistance high', 'J3-05 crimp', '9', '30 %'),
    ('F04', 'HV', 'Below 10 MΩ', 'H1 HS-03', '4', '13 %'),
    ('F07', 'Continuity', 'Unexpected short', 'J4-03 splice', '3', '11 %'),
  ];
}

// ===========================================================================
// DIAGNOSTICS
// ===========================================================================

class DiagView extends StatefulWidget {
  final AppState s;
  const DiagView({super.key, required this.s});

  @override
  State<DiagView> createState() => _DiagViewState();
}

class _DiagViewState extends State<DiagView> {
  double _hsPin = 14;
  double _lsPin = 71;
  double _hvRelay = 3;
  double _hvSet = 0;
  int _optoMode = 0;
  int _hvCard = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final panels = <Widget>[
      _busMap(context, s),
      _cards(context, s),
      _manualSwitch(context, s),
      _manualRelay(context, s),
      _calibration(context, s),
    ];

    return Cols([
      // .diag-grid{grid-template-columns:repeat(auto-fit,minmax(330px,1fr))}
      LayoutBuilder(builder: (context, box) {
        final perRow =
            ((box.maxWidth + 14) / (330 + 14)).floor().clamp(1, panels.length);
        final rows = <List<Widget>>[];
        for (var i = 0; i < panels.length; i += perRow) {
          rows.add(panels.sublist(
              i, (i + perRow) > panels.length ? panels.length : i + perRow));
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
                  // pad the last row so a lone panel does not stretch
                  for (var i = rows[r].length; i < perRow; i++) ...[
                    const SizedBox(width: 14),
                    const Expanded(child: SizedBox()),
                  ],
                ],
              ),
            ],
          ],
        );
      }),
      // .panel{grid-column:1/-1}
      _limits(context),
    ]);
  }

  Widget _busMap(BuildContext context, AppState s) {
    final rows = <(String, PillVariant, String, String, String)>[
      (
        'I2C2',
        PillVariant.ok,
        'OK',
        'HV MCP23017 · ${s.stack}-card stack · iso ADuM1250',
        '100 kHz'
      ),
      (
        'I2C3',
        PillVariant.warn,
        'Slow',
        'Matrix MCP23017 ×5 · 0x20 0x21 0x23 0x24 0x25',
        '100 kHz'
      ),
      (
        'SPI1',
        PillVariant.bad,
        'Fault',
        'AD7476 U33 · ADS124S08 U68 — CS unrouted',
        '16 MHz'
      ),
      (
        'SPI2',
        PillVariant.ok,
        'OK',
        'DAC8775 · DAC8830 · HV AD7476 ×2 · isolated',
        '8 MHz'
      ),
      ('SPI3', PillVariant.ok, 'OK', 'Control AD7476 U4 · ADC_IN', '16 MHz'),
    ];
    final c = context.colors;
    final t = context.type;

    return HtPanel(
      header: [
        const PanelTitle('Bus map'),
        const FlexSpacer(),
        // No bus-enumeration command exists in firmware at all (checked
        // bsp/board.c directly) — see Doc/GUI_protocol_command_coverage.md §4.
        Btn('Rescan', disabled: true, onTap: null),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: c.lineSoft)),
              ),
              child: Row(
                children: [
                  SizedBox(
                      width: 60,
                      child: Text(rows[i].$1, style: t.busId(c.accent))),
                  const SizedBox(width: 11),
                  Pill(rows[i].$2, rows[i].$3),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(rows[i].$4,
                        style: t.busDevs,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 11),
                  Text(rows[i].$5, style: t.busHz),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// `#cardBody` — rebuilt by `setStack()`
  Widget _cards(BuildContext context, AppState s) {
    return HtPanel(
      header: const [PanelTitle('Cards'), FlexSpacer(), Lbl('by stage')],
      child: HtTable(
        minWidth: 0,
        columns: const [
          HtCol('Slot'),
          HtCol('Card'),
          HtCol('Stage'),
          HtCol('Status'),
          HtCol('Rail', right: true),
        ],
        rows: [
          [
            const Td('—', numeric: true),
            const Td('Control rev 4'),
            const Td('both', numeric: true),
            const Tag(TagVariant.ok, 'Ready'),
            const Td('3.301 V', numeric: true),
          ],
          [
            const Td('M1', numeric: true),
            const Td('Matrix rev 6'),
            const Td('1 · J-MTX', numeric: true),
            const Tag(TagVariant.warn, 'Degraded'),
            const Td('3.298 V', numeric: true),
          ],
          for (var i = 0; i < 4; i++)
            [
              Td('H${i + 1}', numeric: true),
              Td(i < s.stack ? 'HV rev 1' : '—'),
              Td('2 · J-HV${i + 1}', numeric: true),
              Tag(i < s.stack ? TagVariant.ok : TagVariant.mut,
                  i < s.stack ? 'Ready' : 'Empty'),
              Td(i < s.stack ? '${(4.98 + i * 0.004).toStringAsFixed(3)} V' : '—',
                  numeric: true),
            ],
        ],
      ),
    );
  }

  Widget _manualSwitch(BuildContext context, AppState s) {
    final t = context.type;
    String fmt(double v) {
      final i = v.round();
      return '${pad(i, 3)} · b${i ~/ 16} ch${pad(i % 16, 2)}';
    }

    return HtPanel(
      header: const [
        PanelTitle('Manual switch · J-MTX'),
        FlexSpacer(),
        Tag(TagVariant.warn, 'Engineer'),
      ],
      child: PanelPad(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CtlRow(
            label: 'HS pin',
            control: Row(children: [
              Expanded(
                child: HtSlider(
                  value: _hsPin,
                  min: 0,
                  max: 255,
                  onChanged: (v) => setState(() => _hsPin = v),
                ),
              ),
              const SizedBox(width: 11),
              SizedBox(
                  width: 118,
                  child: Text(fmt(_hsPin),
                      style: t.out(context.colors.ink))),
            ]),
          ),
          const SizedBox(height: 10),
          _CtlRow(
            label: 'LS pin',
            control: Row(children: [
              Expanded(
                child: HtSlider(
                  value: _lsPin,
                  min: 0,
                  max: 255,
                  onChanged: (v) => setState(() => _lsPin = v),
                ),
              ),
              const SizedBox(width: 11),
              SizedBox(
                  width: 118,
                  child: Text(fmt(_lsPin),
                      style: t.out(context.colors.ink))),
            ]),
          ),
          const SizedBox(height: 10),
          _CtlRow(
            label: 'Opto mode',
            control: Seg(
              options: const ['Continuity', 'Current src'],
              selected: _optoMode,
              onSelect: (i) => setState(() => _optoMode = i),
            ),
          ),
          const SizedBox(height: 14),
          RowWrap([
            // MANUAL PATH is 1-based wire pins (1..256); the sliders show a
            // 0-based bank/channel index, same convention as Net.hs/ls
            // elsewhere in this file.
            Btn(
              'Close path',
              variant: BtnVariant.primary,
              onTap: () =>
                  s.manualClosePath(_hsPin.round() + 1, _lsPin.round() + 1),
            ),
            // No protocol command exists for either — see
            // Doc/GUI_protocol_command_coverage.md §4.
            Btn('Read ADC', disabled: true, onTap: null),
            Btn('Sweep this HS', disabled: true, onTap: null),
          ]),
        ],
      )),
    );
  }

  Widget _manualRelay(BuildContext context, AppState s) {
    final c = context.colors;
    final t = context.type;
    return HtPanel(
      header: const [
        PanelTitle('Manual relay · J-HV'),
        FlexSpacer(),
        Tag(TagVariant.hot, 'HV · interlocked'),
      ],
      child: PanelPad(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CtlRow(
            label: 'Card',
            control: Seg(
              options: const ['H1', 'H2', 'H3', 'H4'],
              selected: _hvCard,
              enabled: [for (var i = 0; i < 4; i++) i < s.stack],
              fill: true,
              onSelect: (i) => setState(() => _hvCard = i),
            ),
          ),
          const SizedBox(height: 10),
          _CtlRow(
            label: 'HS relay',
            control: Row(children: [
              Expanded(
                child: HtSlider(
                  value: _hvRelay,
                  min: 0,
                  max: 63,
                  onChanged: (v) => setState(() => _hvRelay = v),
                ),
              ),
              const SizedBox(width: 11),
              SizedBox(
                width: 118,
                child: Text(
                  'HS-${pad(_hvRelay.round(), 2)} · 0x2${_hvRelay.round() ~/ 8}'
                  ' b${_hvRelay.round() % 8}',
                  style: t.out(c.ink),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          _CtlRow(
            label: 'Set voltage',
            control: Row(children: [
              Expanded(
                child: HtSlider(
                  value: _hvSet,
                  min: 0,
                  max: 500,
                  step: 10,
                  onChanged: (v) => setState(() => _hvSet = v),
                ),
              ),
              const SizedBox(width: 11),
              SizedBox(
                width: 118,
                child: Text(
                  '${_hvSet.round()} V',
                  // o.style.color = +r.value>10 ? var(--hv) : ""
                  style: t.out(_hvSet > 10 ? c.hv : c.ink),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          // MANUAL RELAY is refused by the firmware by design — driving one
          // HV relay by hand over a serial link while the rail may be live is
          // not something the instrument allows (brief §0, §8 Q3: "the
          // firmware refuses, a GUI confirm is not sufficient... do not offer
          // the control"). No Close HS only / Close LS pattern here.
          Text(
            'Manual relay closes are refused by the instrument by design — '
            'a live HV card will not accept single-relay control over the '
            'link. Discharge (MANUAL OFF) is the only manual action offered '
            'here.',
            style: t.mono(size: 11.5, color: c.ink3, height: 1.5),
          ),
          const SizedBox(height: 11),
          RowWrap([
            Btn('Discharge', variant: BtnVariant.ghostHv, onTap: s.manualOff),
          ]),
        ],
      )),
    );
  }

  Widget _calibration(BuildContext context, AppState s) {
    final t = context.type;
    final cal = s.cal;
    return HtPanel(
      header: [
        const PanelTitle('Calibration'),
        const FlexSpacer(),
        Pill(cal != null ? PillVariant.ok : PillVariant.idle,
            cal != null ? 'Read from instrument' : 'Not connected'),
      ],
      child: PanelPad(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Every row here is CAL GET's actual reply (fetched once on
          // connect, in AppState.connect()) — no field is invented. CAL GET
          // has exactly three fields; loopback offset, ADC offset and the HV
          // divider ratio the earlier mock-up showed are not part of the
          // protocol and are not displayed as if they were real.
          Kv([
            KvRow(
              'Reference resistor',
              KvText(cal != null
                  ? '${(cal.rrefMohm / 1000).toStringAsFixed(3)} Ω'
                  : '— not connected'),
            ),
            KvRow(
              'Excitation (set)',
              KvText(cal != null
                  ? '${(cal.currentUa / 1000).toStringAsFixed(2)} mA'
                  : '— not connected'),
            ),
            KvRow(
              'PGA gain',
              KvText(cal != null ? '×${cal.gain}' : '— not connected'),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            'Loopback offset, ADC offset and HV divider ratio are not '
            'reported by CAL GET in the current protocol — not shown rather '
            'than shown as invented numbers.',
            style: t.mono(size: 11, color: context.colors.ink3, height: 1.5),
          ),
          const SizedBox(height: 14),
          RowWrap([
            // No protocol command exists for any of these three — see
            // Doc/GUI_protocol_command_coverage.md §4 (self-cal, compliance
            // sweep) and §5 (certificate needs a PDF-export dependency).
            Btn('Run self-cal',
                variant: BtnVariant.primary, disabled: true, onTap: null),
            Btn('Compliance sweep', disabled: true, onTap: null),
            Btn('Cal certificate', disabled: true, onTap: null),
          ]),
        ],
      )),
    );
  }

  Widget _limits(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    const blockers = [
      (
        'HW-01',
        'Kelvin path offline — resistance only.',
        ' ADS124S08 control lines do not reach the card connector. Resistance '
            'falls back to the 2-wire AD7476 path; milliohm resolution '
            'unavailable. Continuity and HV are unaffected.'
      ),
      (
        'HW-02',
        'Sense array cannot switch — resistance only.',
        ' HI_SENSE_EN / LO_SENSE_EN nets do not match the expander outputs, so '
            '4-wire measurements report as 2-wire until the rename lands.'
      ),
      (
        'FW-04',
        'Cross continuity is bus-bound.',
        ' A full 256 × 256 sweep is roughly 70 s of I2C traffic at 100 kHz '
            'against 18 s at 400 kHz. Netlist mode needs only ~624 reads. Raise '
            'I2C3 to 400 kHz before cross mode is usable on the line.'
      ),
      (
        'BU-06',
        'Stack encoding lives in the cable.',
        ' ISO_HV_CARD_ENx is set per slot by the harness build, not the '
            'schematic. A miswired cable makes the console report a stack size '
            'the instrument does not actually have — verify against the I2C2 '
            'scan before trusting the HV netlist match.'
      ),
    ];

    return HtPanel(
      header: const [
        PanelTitle('Instrument limits'),
        FlexSpacer(),
        Tag(TagVariant.warn, '2 blocking · 2 pending'),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blockers.length; i++)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                border: i == blockers.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: c.lineSoft)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 46,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(blockers[i].$1, style: t.blockerId),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(
                        text: blockers[i].$2,
                        style: t.blockerText.copyWith(
                            color: c.ink, fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: blockers[i].$3, style: t.blockerText),
                    ])),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// `.ctl{grid-template-columns:auto minmax(0,1fr);gap:10px 14px}`
class _CtlRow extends StatelessWidget {
  final String label;
  final Widget control;
  const _CtlRow({required this.label, required this.control});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 90,
            child: Text(label.toUpperCase(), style: context.type.ctlLabel),
          ),
          const SizedBox(width: 14),
          Expanded(child: control),
        ],
      );
}

/// `input[type=range]{width:100%;accent-color:var(--accent)}`
class HtSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  const HtSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.step = 1,
    required this.onChanged,
  });

  @override
  State<HtSlider> createState() => _HtSliderState();
}

class _HtSliderState extends State<HtSlider> {
  void _update(double dx, double width) {
    final frac = (dx / width).clamp(0.0, 1.0);
    var v = widget.min + frac * (widget.max - widget.min);
    v = (v / widget.step).round() * widget.step;
    widget.onChanged(v.clamp(widget.min, widget.max));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final frac = ((widget.value - widget.min) / (widget.max - widget.min))
        .clamp(0.0, 1.0);

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      const thumb = 14.0;
      final travel = math.max(0.0, w - thumb);
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTapDown: (e) => _update(e.localPosition.dx, w),
          onHorizontalDragUpdate: (e) => _update(e.localPosition.dx, w),
          child: SizedBox(
            height: 20,
            width: w,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Track. The width is explicit: a non-positioned Stack child
                // gets loose constraints, so a Container with only a height
                // would collapse to zero width.
                SizedBox(
                  width: w,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.sunk,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: c.line, width: .5),
                    ),
                  ),
                ),
                // filled portion
                SizedBox(
                  width: w * frac,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Positioned(
                  left: frac * travel,
                  child: Container(
                    width: thumb,
                    height: thumb,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
