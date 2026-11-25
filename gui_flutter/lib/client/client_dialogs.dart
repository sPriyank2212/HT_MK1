/// The client's dialogs: the generic ones (name prompt, About, netlist
/// viewer) and the safety-critical ones driven by [AppState]'s modal flags —
/// the prerequisite / handover prompt, the HV netlist and MTX netlist
/// pickers, the **HV confirmation** and the **hardware fault** alert
/// (`GUI-DLG-HV-001..004`, `GUI-DLG-FAULT-001..004` of the client's GUI
/// requirements).
///
/// The HV and fault dialogs are non-dismissible by design: no Escape, no
/// click-outside. HV needs every box ticked; the fault dialog stays until the
/// operator acknowledges it.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/build_tag.dart';
import 'client_controller.dart';
import 'client_icons.dart';
import 'client_model.dart';
import 'client_netlist_editor.dart';
import 'netlist_doc.dart';
import 'client_theme.dart';
import 'client_widgets.dart';

// ---------------------------------------------------------------------------
// frame
// ---------------------------------------------------------------------------

/// A centred card over a scrim. [onDismiss] null = cannot be dismissed.
class DialogFrame extends StatelessWidget {
  final String title;
  final Color? accent;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final VoidCallback? onDismiss;
  final IconKind? icon;

  /// Always visible between the scrolling body and the buttons — for the
  /// controls that must never be scrolled out of view (the HV safety boxes).
  final Widget? pinned;

  const DialogFrame({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.accent,
    this.width = 560,
    this.onDismiss,
    this.icon,
    this.pinned,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final a = accent ?? c.border;
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDismiss,
          child: ColoredBox(color: const Color(0xB3000000)),
        ),
      ),
      Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: width,
              maxHeight: MediaQuery.sizeOf(context).height - 48),
          child: Container(
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: c.card,
              border: Border.all(color: a, width: accent == null ? 1 : 2),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Color(0x99000000), blurRadius: 30),
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.border)),
                ),
                child: Row(children: [
                  if (icon != null) ...[
                    ClientIcon(icon!, color: accent ?? c.text, size: 22),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(title,
                        style: ctext(context,
                            size: 16,
                            weight: FontWeight.w700,
                            color: accent ?? c.text)),
                  ),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: child,
                ),
              ),
              if (pinned != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: pinned!,
                ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 8,
                  children: actions,
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

Widget _p(BuildContext context, String text, {Color? color, double size = 13}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: ctext(context, size: size, color: color ?? context.cc.muted)
              .copyWith(height: 1.45)),
    );

/// One line of a pre-flight checklist (`Continuity passed on J-MTX … passed`).
class _CheckRow extends StatelessWidget {
  final ({String state, String title, String detail, String value}) row;
  const _CheckRow(this.row);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final fg = switch (row.state) {
      'ok' => c.green,
      'warn' => c.amber,
      _ => c.red,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: c.input,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration:
              BoxDecoration(color: fg.withValues(alpha: .18), shape: BoxShape.circle),
          child: switch (row.state) {
            'ok' => ClientIcon(IconKind.check, color: fg, size: 12),
            'warn' => Text('!',
                style: ctext(context,
                    size: 12, weight: FontWeight.w800, color: fg)),
            _ => ClientIcon(IconKind.cross, color: fg, size: 11),
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.title,
                style: ctext(context, size: 13, weight: FontWeight.w600)),
            // AppState words this for the console and prints "null" when no
            // netlist name exists (a skipped pre-test); not for an operator.
            Text(row.detail.replaceAll('null · ', ''),
                style: ctext(context, size: 11.5, color: c.muted)),
          ]),
        ),
        const SizedBox(width: 10),
        Text(row.value,
            style: ctext(context, size: 12, weight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// the AppState-driven overlay
// ---------------------------------------------------------------------------

/// Everything that can sit on top of the window, in priority order. A fault
/// outranks every other dialog.
class ClientModals extends StatelessWidget {
  final ClientController ctl;
  const ClientModals(this.ctl, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = ctl.s;
    if (s.mdFixtureOpen) {
      // The client app has no connector-shape editor: the guessed layout from
      // the netlist's Conn ID / Part Number columns is accepted as is, and the
      // Connector View draws from the netlist rows themselves.
      scheduleMicrotask(() {
        s.mdFixtureOpen = false;
      });
    }
    if (s.inFault) return _FaultDialog(ctl);
    if (s.mdVerifyOpen) return _HvConfirmDialog(s);
    if (s.mdPreOpen) return _PrerequisiteDialog(s);
    if (s.mdNlOpen) return _HvNetlistDialog(ctl);
    if (s.mdMtxOpen) return _MtxNetlistDialog(ctl);
    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// prerequisites / handover
// ---------------------------------------------------------------------------

class _PrerequisiteDialog extends StatelessWidget {
  final AppState s;
  const _PrerequisiteDialog(this.s);

  ({String state, String title, String detail, String value}) _row(
      String key, String title) {
    final r = s.R[key];
    return (
      state: r == 'pass' ? 'ok' : 'warn',
      title: title,
      detail: switch (r) {
        'pass' => 'completed on J-MTX',
        'fail' => 'failed on J-MTX',
        _ => 'not run yet',
      },
      value: switch (r) { 'pass' => 'passed', 'fail' => 'failed', _ => 'not run' },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final done = s.preTestsDone;
    return DialogFrame(
      title: done
          ? 'Move the harness to ${s.hvConnName()}'
          : 'Run continuity and resistance first?',
      icon: IconKind.warn,
      accent: c.amber,
      onDismiss: s.cancelModals,
      actions: [
        CButton('Cancel', role: CRole.ghost, onPressed: s.cancelModals),
        if (done)
          CButton('Harness moved — continue',
              role: CRole.primary,
              onPressed: () => unawaited(s.continueToInsulation(skipped: false)))
        else ...[
          CButton('Go to Continuity',
              role: CRole.secondary, onPressed: s.goToMode1),
          CButton('Continue anyway',
              role: CRole.danger,
              onPressed: () => unawaited(s.continueToInsulation(skipped: true))),
        ],
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _p(
            context,
            done
                ? 'Continuity and resistance passed on J-MTX. Unplug the harness from J-MTX and plug it into ${s.hvConnName()}, then continue to the insulation test.'
                : 'The insulation test normally follows a passed Continuity and Resistance check on J-MTX. Run those first, or continue anyway to run insulation without any pre-test.'),
        _CheckRow(_row('cont', 'Continuity passed on J-MTX')),
        _CheckRow(_row('res', 'Resistance passed on J-MTX')),
        if (!done)
          _p(
              context,
              'Continue anyway tells the instrument the harness is on ${s.hvConnName()} — make sure it is plugged in there. The skipped pre-tests are recorded in the log.',
              color: c.amber),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// netlist pickers
// ---------------------------------------------------------------------------

class _HvNetlistDialog extends StatelessWidget {
  final ClientController ctl;
  const _HvNetlistDialog(this.ctl);

  @override
  Widget build(BuildContext context) {
    final s = ctl.s;
    return DialogFrame(
      title: 'Select the HV netlist',
      onDismiss: s.cancelModals,
      actions: [
        CButton('Cancel', role: CRole.ghost, onPressed: s.cancelModals),
        CButton('Create…',
            role: CRole.ghost,
            onPressed: () =>
                openNetlistEditor(context, ctl, NetlistKind.hv, blank: true)),
        CButton('Browse…',
            role: CRole.secondary,
            onPressed: () => unawaited(s.browseHvNetlist())),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _p(context,
            'HV uses its own netlist because the relay map depends on how many HV cards are stacked. The instrument is set to a ${s.stack}-card stack. It is sent to the tester only for the insulation run; the continuity netlist is sent back before the next continuity or resistance test.'),
        _p(context,
            'Browse for an Excel (.xlsx) file with HS Pin and LS Pin columns, or Create one here. Without an HV netlist the test cannot build the return pattern — and a wrong pattern reads as a pass.'),
      ]),
    );
  }
}

class _MtxNetlistDialog extends StatelessWidget {
  final ClientController ctl;
  const _MtxNetlistDialog(this.ctl);

  @override
  Widget build(BuildContext context) {
    final s = ctl.s;
    return DialogFrame(
      title: 'Select the netlist',
      onDismiss: s.closeMtxNlExplainer,
      actions: [
        CButton('Cancel', role: CRole.ghost, onPressed: s.closeMtxNlExplainer),
        CButton('Create…',
            role: CRole.ghost,
            onPressed: () =>
                openNetlistEditor(context, ctl, NetlistKind.mtx, blank: true)),
        CButton('Browse…',
            role: CRole.secondary,
            onPressed: () => unawaited(s.browseMtxNetlist())),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _p(context,
            'Continuity and Resistance need a netlist. Load one from an Excel file, or switch to Auto-Scan to discover the harness and use that as the netlist.'),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// HV confirmation  (GUI-DLG-HV-001..004)
// ---------------------------------------------------------------------------

class _HvConfirmDialog extends StatefulWidget {
  final AppState s;
  const _HvConfirmDialog(this.s);

  @override
  State<_HvConfirmDialog> createState() => _HvConfirmDialogState();
}

class _HvConfirmDialogState extends State<_HvConfirmDialog> {
  bool _lid = false, _people = false, _isolated = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final s = widget.s;
    final all = _lid && _people && _isolated;
    final warn = c.amber;
    return DialogFrame(
      title: 'HIGH VOLTAGE TEST — SAFETY WARNING',
      icon: IconKind.warn,
      accent: warn,
      width: 600,
      // GUI-DLG-HV-001: cannot be closed by Escape or by clicking outside.
      onDismiss: null,
      pinned: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Before proceeding, confirm ALL of the following:',
            style: ctext(context, size: 13, weight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: warn.withValues(alpha: .10),
            border: Border.all(color: warn.withValues(alpha: .6)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            CCheck('Safety enclosure lid is fully closed and latched',
                value: _lid, accent: warn, onChanged: (v) => setState(() => _lid = v)),
            const SizedBox(height: 10),
            CCheck('No personnel are in contact with the DUT or connectors',
                value: _people,
                accent: warn,
                onChanged: (v) => setState(() => _people = v)),
            const SizedBox(height: 10),
            CCheck('DUT is fully isolated from external power supplies',
                value: _isolated,
                accent: warn,
                onChanged: (v) => setState(() => _isolated = v)),
          ]),
        ),
      ]),
      actions: [
        CButton('CANCEL', role: CRole.ghost, onPressed: s.cancelModals),
        CButton('CONFIRM AND START',
            role: CRole.danger, onPressed: all ? _go : null),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('This test will apply up to 500 V DC to the DUT.',
            style: ctext(context, size: 14, weight: FontWeight.w700, color: warn)),
        const SizedBox(height: 10),
        _p(context,
            'It drives 500 V through the harness on ${s.hvConnName()}. Check this is the same harness that passed on J-MTX.'),
        for (final row in s.verifyChecks) _CheckRow(row),
        const SizedBox(height: 12),
        Text('Requested test voltage: 500 V DC',
            style: ctext(context, size: 12.5, color: c.muted)),
      ]),
    );
  }

  void _go() {
    widget.s.setAck(true);
    widget.s.confirmEnergize();
  }
}

// ---------------------------------------------------------------------------
// hardware fault  (GUI-DLG-FAULT-001..004)
// ---------------------------------------------------------------------------

class _FaultDialog extends StatelessWidget {
  final ClientController ctl;
  const _FaultDialog(this.ctl);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final s = ctl.s;
    final t = s.lastFaultAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final time = t == null
        ? '—'
        : '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 110,
                child: Text('$k:', style: ctext(context, size: 13, color: c.muted))),
            Expanded(
                child: Text(v,
                    style: ctext(context, size: 13, weight: FontWeight.w600))),
          ]),
        );
    return DialogFrame(
      title: 'HARDWARE FAULT DETECTED',
      icon: IconKind.warn,
      accent: c.red,
      onDismiss: null,
      actions: [
        CButton('ACKNOWLEDGE AND ABORT',
            role: CRole.danger, onPressed: () => unawaited(s.clearFault())),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        kv('Fault Code', s.lastFaultCode ?? 'unknown'),
        kv('Description', s.lastFaultText ?? 'The instrument reported a fault.'),
        kv('Time', time),
        const SizedBox(height: 10),
        _p(context,
            'The test has been stopped and the high-voltage rail has been forced safe by the instrument.'),
        _p(context,
            'DO NOT touch the harness or open the enclosure until the HV rail reads 0 V.',
            color: c.red),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// generic dialogs
// ---------------------------------------------------------------------------

/// `QInputDialog.getText`.
Future<String?> promptText(BuildContext context,
    {required String title, required String label}) {
  return showDialog<String>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (ctx) => _PromptDialog(title: title, label: label),
  );
}

class _PromptDialog extends StatefulWidget {
  final String title, label;
  const _PromptDialog({required this.title, required this.label});

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  String _v = '';

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(
          side: BorderSide(color: c.border),
          borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 360,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title,
                style: ctext(context, size: 16, weight: FontWeight.w700)),
            const SizedBox(height: 14),
            Text(widget.label, style: ctext(context, size: 12.5, color: c.muted)),
            const SizedBox(height: 6),
            CField(value: '', onChanged: (v) => _v = v),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              CButton('Cancel',
                  role: CRole.ghost,
                  onPressed: () => Navigator.of(context).pop()),
              const SizedBox(width: 8),
              CButton('OK',
                  role: CRole.secondary,
                  onPressed: () => Navigator.of(context).pop(_v)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Help → About.
Future<void> showAbout(BuildContext context, AppState s) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (ctx) {
      final c = ctx.cc;
      return Dialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(
            side: BorderSide(color: c.border),
            borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: 380,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Integrated Harness Tester MKI',
                  style: ctext(ctx, size: 18, weight: FontWeight.w700)),
              const SizedBox(height: 10),
              for (final (k, v) in [
                ('Model', 'HT_MK1'),
                ('Product code', 'I2PL-IHT-MKI'),
                ('Application', kBuildStamp),
                ('Protocol', '1.0'),
                ('Firmware', s.fwVersion == null ? 'not connected' : 'v${s.fwVersion}'),
                ('Designed by', 'Infinity Integrations Private Limited'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    SizedBox(
                        width: 100,
                        child: Text('$k:',
                            style: ctext(ctx, size: 13, color: c.muted))),
                    Expanded(child: Text(v, style: ctext(ctx, size: 13))),
                  ]),
                ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: CButton('OK',
                    role: CRole.secondary,
                    onPressed: () => Navigator.of(ctx).pop()),
              ),
            ]),
          ),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Multi-Test Run: which tests to perform
// ---------------------------------------------------------------------------

/// The pop-up shown when Multi-Test Run is chosen (and from "Tests…"): tick
/// the tests the run performs, then **Confirm & Exit**. They run in the order
/// listed, and a failed test ends the run.
Future<void> showMultiTestDialog(BuildContext context, ClientController ctl) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0xB3000000),
    builder: (ctx) => _MultiTestDialog(ctl),
  );
}

class _MultiTestDialog extends StatefulWidget {
  final ClientController ctl;
  const _MultiTestDialog(this.ctl);

  @override
  State<_MultiTestDialog> createState() => _MultiTestDialogState();
}

class _MultiTestDialogState extends State<_MultiTestDialog> {
  late final Set<ClientMode> _sel = {...widget.ctl.multiSelection};

  static const _labels = {
    ClientMode.continuity: 'Continuity (one-to-one)',
    ClientMode.cross: 'Cross Continuity (one-to-many)',
    ClientMode.resistance: 'Resistance (4-wire Kelvin)',
    ClientMode.insulation: 'HV Insulation (IR) Test (500 V DC)',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    return ClientTheme(
      colors: widget.ctl.dark ? ClientColors.darkTheme : ClientColors.lightTheme,
      child: Builder(builder: (ctx) {
        final cc = ctx.cc;
        return Dialog(
          backgroundColor: cc.card,
          shape: RoundedRectangleBorder(
              side: BorderSide(color: cc.border),
              borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            width: 440,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Multi-Test Run',
                        style: ctext(ctx, size: 18, weight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                        'Select the tests to perform. They run in this order, '
                        'one after another; a failed test ends the run.',
                        style: ctext(ctx, size: 12.5, color: cc.muted)),
                    const SizedBox(height: 14),
                    for (final m in kMultiOrder)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: CCheck(_labels[m]!,
                            value: _sel.contains(m),
                            onChanged: (v) => setState(
                                () => v ? _sel.add(m) : _sel.remove(m))),
                      ),
                    if (_sel.isEmpty)
                      Text('Select at least one test.',
                          style: ctext(ctx, size: 12, color: c.amber)),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: CButton('Confirm & Exit',
                          role: CRole.secondary,
                          onPressed: _sel.isEmpty
                              ? null
                              : () {
                                  widget.ctl.setMultiSelection(_sel);
                                  Navigator.of(ctx).pop();
                                }),
                    ),
                  ]),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// calibration (CL-112)
// ---------------------------------------------------------------------------

/// Tools → Calibration…: the instrument's calibration constants (`CAL GET`,
/// read on connect) and a self-cal measurement (`CAL RUN <hs> <ls>`: one
/// 4-wire Kelvin reading of the chosen pair through the ADS124S08, reported
/// with whether the ratiometric R131 reference worked). Same commands as the
/// engineering console's Calibration panel.
Future<void> showCalibration(BuildContext context, ClientController ctl) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (ctx) => _CalibrationDialog(ctl),
  );
}

class _CalibrationDialog extends StatefulWidget {
  final ClientController ctl;
  const _CalibrationDialog(this.ctl);

  @override
  State<_CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<_CalibrationDialog> {
  String _hs = '1';
  String _ls = '1';

  int? _pin(String v) {
    final n = int.tryParse(v.trim());
    return (n != null && n >= 1 && n <= 256) ? n : null;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.ctl.s;
    return ListenableBuilder(
      listenable: s,
      builder: (ctx, _) {
        final c = ctx.cc;
        final cal = s.cal;
        final last = s.lastCalResult;
        final hs = _pin(_hs), ls = _pin(_ls);
        String? why;
        if (!s.link) {
          why = 'Connect to the instrument first.';
        } else if (widget.ctl.running) {
          why = 'A test is running.';
        } else if (hs == null || ls == null) {
          why = 'HS and LS pins must be 1..256.';
        }
        Widget kv(String k, String v) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                SizedBox(
                    width: 190,
                    child: Text('$k:',
                        style: ctext(ctx, size: 13, color: c.muted))),
                Expanded(child: Text(v, style: ctext(ctx, size: 13))),
              ]),
            );
        return Dialog(
          backgroundColor: c.card,
          shape: RoundedRectangleBorder(
              side: BorderSide(color: c.border),
              borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            width: 520,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Calibration',
                        style: ctext(ctx, size: 18, weight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    kv('Reference resistor (R131)',
                        cal == null
                            ? 'not connected'
                            : '${(cal.rrefMohm / 1000).toStringAsFixed(3)} Ω ± '
                                '${(cal.rrefTolMohm / 1000).toStringAsFixed(3)} Ω'),
                    kv('Excitation current',
                        cal == null
                            ? 'not connected'
                            : '${(cal.currentUa / 1000).toStringAsFixed(2)} mA'),
                    kv('Resistance method', cal == null ? 'not connected' : cal.method),
                    kv('PGA gain (auto, up to)',
                        cal == null ? 'not connected' : '×${cal.gainMax}'),
                    const SizedBox(height: 14),
                    Text(
                        'Self-cal: connect the calibration wire or reference '
                        'resistor from the HS pin to the LS pin, then press Run. '
                        'The instrument makes one 4-wire measurement of that pair.',
                        style: ctext(ctx, size: 12, color: c.muted)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Text('HS pin', style: ctext(ctx, size: 13)),
                      const SizedBox(width: 8),
                      CField(
                          value: _hs,
                          width: 70,
                          mono: true,
                          onChanged: (v) => setState(() => _hs = v)),
                      const SizedBox(width: 18),
                      Text('LS pin', style: ctext(ctx, size: 13)),
                      const SizedBox(width: 8),
                      CField(
                          value: _ls,
                          width: 70,
                          mono: true,
                          onChanged: (v) => setState(() => _ls = v)),
                      const Spacer(),
                      CButton(s.calRunning ? 'Running…' : 'Run Self-Cal',
                          role: CRole.primary,
                          tooltip: why,
                          onPressed: (why != null || s.calRunning)
                              ? null
                              : () => unawaited(s.calRun(hs!, ls!))),
                    ]),
                    if (why != null) ...[
                      const SizedBox(height: 6),
                      Text(why, style: ctext(ctx, size: 12, color: c.amber)),
                    ],
                    const SizedBox(height: 14),
                    kv(
                        'Last self-cal result',
                        last == null
                            ? '—'
                            : '${(last.rMohm / 1000).toStringAsFixed(3)} Ω '
                                '(${last.rMohm} mΩ) · '
                                '${last.ratiometric ? "ratiometric OK" : "ratiometric FAILED (current estimate used)"} · '
                                '${last.pass ? "PASS" : "FAIL"}'),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: CButton('Close',
                          role: CRole.secondary,
                          onPressed: () => Navigator.of(ctx).pop()),
                    ),
                  ]),
            ),
          ),
        );
      },
    );
  }
}
