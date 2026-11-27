/// The client-styled Harness Tester window: menu bar, control bar (Mode,
/// START TEST, STOP / ABORT, Duration, verdict), the left panel, the five tabs
/// (Connector View · Results Table · Log · Info · Configuration) and the
/// footer — the layout of the customer's own application, running the MK1
/// tests on the shared [AppState].
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show AppExitResponse;

import '../app/app_state.dart';
import '../htproto/paths.dart';
import 'client_connector_view.dart';
import 'client_icons.dart';
import 'client_controller.dart';
import 'client_dialogs.dart';
import 'client_left_panel.dart';
import 'client_model.dart';
import 'client_netlist_editor.dart';
import 'client_output.dart';
import 'netlist_doc.dart';
import 'client_results.dart';
import 'client_tabs.dart';
import 'client_theme.dart';
import 'client_widgets.dart';

/// Root widget of the client app.
class ClientApp extends StatefulWidget {
  final AppState state;

  /// Profiles and settings directory; null keeps everything in memory.
  final Directory? dataDir;
  const ClientApp({super.key, required this.state, this.dataDir});

  @override
  State<ClientApp> createState() => _ClientAppState();
}

class _ClientAppState extends State<ClientApp> {
  late final ClientController ctl =
      ClientController(widget.state, dataDir: widget.dataDir);
  ClientOutput? _output;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    ctl.showToast('Harness Tester ready');
    // Logs, results and netlists are copied into the GUI folder when the
    // window is closed, and again after every run. (Tests pass no dataDir.)
    if (widget.dataDir != null) {
      _output = ClientOutput(ctl);
      _output!.prepare();
      ctl.saveOutputs = () => _output?.save();
      ctl.netlistsDir = () => _output!.netlistsDir;
      _lifecycle = AppLifecycleListener(onExitRequested: () async {
        _output?.save();
        return AppExitResponse.exit;
      });
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        final colors = ctl.dark ? ClientColors.darkTheme : ClientColors.lightTheme;
        return MaterialApp(
          title: 'Integrated Harness Tester MKI',
          debugShowCheckedModeBanner: false,
          theme: clientThemeData(colors),
          home: ClientTheme(colors: colors, child: ClientHome(ctl)),
        );
      },
    );
  }
}

class ClientHome extends StatelessWidget {
  final ClientController ctl;
  ClientHome(this.ctl, {super.key});

  final DateTime _started = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): ctl.start,
        const SingleActivator(LogicalKeyboardKey.f6): ctl.stop,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            ctl.browseNetlist,
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): () =>
            openNetlistEditor(context, ctl, NetlistKind.mtx),
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () =>
            openNetlistEditor(context, ctl, NetlistKind.hv),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            ctl.exportCsv,
        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
            ctl.exportPdf,
        const SingleActivator(LogicalKeyboardKey.keyM, control: true): () =>
            ctl.showTab(ClientTab.connector),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            ctl.showTab(ClientTab.results),
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
            ctl.showTab(ClientTab.log),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: c.bg,
          body: Stack(children: [
            Column(children: [
              _MenuRow(ctl),
              _ControlBar(ctl),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ClientLeftPanel(ctl),
                  Container(width: 1, color: c.border),
                  Expanded(child: _Centre(ctl, _started)),
                ]),
              ),
              _Footer(ctl),
            ]),
            Positioned(
              right: 18,
              bottom: 52,
              child: _ToastView(ctl),
            ),
            Positioned.fill(child: ClientModals(ctl)),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// menu bar
// ---------------------------------------------------------------------------

class _MenuRow extends StatelessWidget {
  final ClientController ctl;
  const _MenuRow(this.ctl);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final style = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(c.card),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStatePropertyAll(BorderSide(color: c.border)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
    );
    final item = ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(c.text),
      textStyle: WidgetStatePropertyAll(ctext(context, size: 13)),
      overlayColor: WidgetStatePropertyAll(c.blue.withValues(alpha: .18)),
    );
    MenuItemButton mi(String label, VoidCallback? f, {String? hint}) =>
        MenuItemButton(
          onPressed: f,
          style: item,
          trailingIcon: hint == null
              ? null
              : Text(hint, style: ctext(context, size: 11.5, color: c.dim)),
          child: Text(label),
        );

    return Container(
      color: c.bg,
      height: 34,
      alignment: Alignment.centerLeft,
      child: Stack(children: [
        Center(
          child: Text('Integrated Harness Tester MKI',
              style: ctext(context,
                  size: 13.5, weight: FontWeight.w700, color: c.muted)),
        ),
        MenuBarTheme(
        data: MenuBarThemeData(
          style: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(0),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            side: const WidgetStatePropertyAll(BorderSide.none),
            shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(0))),
          ),
        ),
        child: MenuTheme(
          data: MenuThemeData(style: style),
          child: MenuBar(children: [
            SubmenuButton(
              style: item,
              menuChildren: [
                mi('Load Netlist…', ctl.running ? null : ctl.browseNetlist,
                    hint: 'Ctrl+O'),
                mi('Netlist Editor…',
                    ctl.running
                        ? null
                        : () => openNetlistEditor(
                            context, ctl, NetlistKind.mtx),
                    hint: 'Ctrl+E'),
                mi('HV Netlist Editor…',
                    ctl.running
                        ? null
                        : () => openNetlistEditor(
                            context, ctl, NetlistKind.hv),
                    hint: 'Ctrl+H'),
                const Divider(height: 1),
                mi('Save Results as CSV…', ctl.exportCsv, hint: 'Ctrl+S'),
                mi('Export PDF Report…', ctl.exportPdf, hint: 'Ctrl+P'),
                mi('Open Result Folder', ctl.openResultFolder),
                const Divider(height: 1),
                mi('Exit', () => SystemNavigator.pop(), hint: 'Alt+F4'),
              ],
              child: const Text('File'),
            ),
            SubmenuButton(
              style: item,
              menuChildren: [
                SubmenuButton(
                  style: item,
                  menuChildren: [
                    mi('Dark', () => ctl.setTheme(true)),
                    mi('Light', () => ctl.setTheme(false)),
                  ],
                  child: const Text('Theme'),
                ),
                const Divider(height: 1),
                for (final t in ClientTab.values)
                  mi('Show ${t.title}', () => ctl.showTab(t)),
              ],
              child: const Text('View'),
            ),
            SubmenuButton(
              style: item,
              menuChildren: [
                mi('Calibration…',
                    ctl.running ? null : () => showCalibration(context, ctl)),
                mi('Read Board Temperature',
                    (ctl.running || !ctl.s.link) ? null : ctl.s.readTemp),
              ],
              child: const Text('Tools'),
            ),
            SubmenuButton(
              style: item,
              menuChildren: [
                mi('About', () => showAbout(context, ctl.s)),
              ],
              child: const Text('Help'),
            ),
          ]),
        ),
      ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// control bar
// ---------------------------------------------------------------------------

class _ControlBar extends StatelessWidget {
  final ClientController ctl;
  const _ControlBar(this.ctl);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final s = ctl.s;
    final why = ctl.startBlocked;
    final running = ctl.running;
    final v = ctl.verdict;
    final (vbg, vfg) = switch (v) {
      'PASS' => (c.green, Colors.white),
      'FAIL' => (c.red, Colors.white),
      'FAULT' => (c.amber, const Color(0xFF1C1C1C)),
      'DONE' => (c.blue, Colors.white),
      _ => (c.neutral, Colors.white),
    };

    final pct = s.totalCount > 0 ? s.doneCount / s.totalCount : null;

    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(children: [
        Text('Mode:', style: ctext(context, size: 13, color: c.muted)),
        const SizedBox(width: 8),
        CDropdown<ClientMode>(
          width: 270,
          highlight: true,
          value: ctl.mode,
          items: {
            for (final m in ClientMode.values) m: m.label,
          },
          onChanged: running || ctl.autoScan
              ? null
              : (m) {
                  ctl.setMode(m);
                  if (m == ClientMode.multi) showMultiTestDialog(context, ctl);
                },
        ),
        if (ctl.mode == ClientMode.multi && !ctl.autoScan) ...[
          const SizedBox(width: 8),
          CButton('Tests…',
              role: CRole.ghost,
              compact: true,
              tooltip: 'Choose the tests the Multi-Test Run performs',
              onPressed:
                  running ? null : () => showMultiTestDialog(context, ctl)),
        ],
        const SizedBox(width: 14),
        Tooltip(
          message: why ?? 'Start test sequence (F5)',
          child: CButton('START TEST',
              role: CRole.primary,
              icon: IconKind.play,
              width: 216,
              height: 58,
              fontSize: 24,
              onPressed: why == null ? ctl.start : () => ctl.start()),
        ),
        const SizedBox(width: 8),
        CButton('STOP / ABORT',
            role: CRole.danger,
            icon: IconKind.stop,
            width: 150,
            tooltip: 'Stop or abort the current test (F6)',
            onPressed: running || ctl.multiActive ? ctl.stop : null),
        const SizedBox(width: 16),
        if (running)
          SizedBox(
            width: 190,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: c.border,
                  valueColor: AlwaysStoppedAnimation(c.blue),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                pct == null
                    ? 'Running…'
                    : '${(pct * 100).round()}%  (${s.doneCount}/${s.totalCount})',
                style: ctext(context, size: 11, color: c.muted),
              ),
            ]),
          ),
        const SizedBox(width: 12),
        Text('Duration: ${ctl.durationText}',
            style: ctext(context, size: 13, color: c.muted)),
        const SizedBox(width: 16),
        _VerdictBox(v, vbg, vfg),
        const Spacer(),
        if (s.hvLive) _HvIndicator(s),
      ]),
    );
  }
}

class _VerdictBox extends StatelessWidget {
  final String text;
  final Color bg, fg;
  const _VerdictBox(this.text, this.bg, this.fg);

  @override
  Widget build(BuildContext context) {
    final glow = text == 'PASS' || text == 'FAIL' || text == 'FAULT';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: text == 'DONE' ? 140 : 136,
      height: text == 'DONE' ? 34 : 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: glow
            ? [BoxShadow(color: bg.withValues(alpha: .5), blurRadius: 18)]
            : null,
      ),
      // A finished Multi-Test Run reads "Completed" at the START TEST label's
      // size (13 pt, bold), not the big verdict size.
      child: text == 'DONE'
          ? Text('Completed',
              style: ctext(context,
                  size: 13, weight: FontWeight.w700, color: fg))
          : Text(text,
              style: ctext(context,
                  size: text == '—' ? 30 : 24,
                  weight: FontWeight.w800,
                  color: fg)),
    );
  }
}

/// GUI-SB-002: the HV indicator flashes at 1 Hz while the rail is live.
class _HvIndicator extends StatefulWidget {
  final AppState s;
  const _HvIndicator(this.s);

  @override
  State<_HvIndicator> createState() => _HvIndicatorState();
}

class _HvIndicatorState extends State<_HvIndicator> {
  bool _on = true;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _on = !_on);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _on ? const Color(0xFFFFD60A) : c.amber.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const ClientIcon(IconKind.bolt, color: Color(0xFF1C1C1C), size: 15),
        const SizedBox(width: 6),
        Text('HV ACTIVE ${widget.s.hvMv ~/ 1000} V',
            style: ctext(context,
                size: 13,
                weight: FontWeight.w800,
                color: const Color(0xFF1C1C1C))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// centre: tabs
// ---------------------------------------------------------------------------

class _Centre extends StatelessWidget {
  final ClientController ctl;
  final DateTime started;
  const _Centre(this.ctl, this.started);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(children: [
        Row(children: [
          for (final t in ClientTab.values)
            ClickBox(
              onTap: () => ctl.showTab(t),
              builder: (hover) => Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: ctl.tab == t
                      ? c.card
                      : (hover ? c.card.withValues(alpha: .5) : Colors.transparent),
                  border: Border.all(
                      color: ctl.tab == t ? c.border : Colors.transparent),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Text(t.title,
                    style: ctext(context,
                        size: 13,
                        weight: ctl.tab == t ? FontWeight.w600 : FontWeight.w400,
                        color: ctl.tab == t ? c.text : c.muted)),
              ),
            ),
        ]),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: c.card.withValues(alpha: .35),
              border: Border.all(color: c.border),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(8),
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: switch (ctl.tab) {
              ClientTab.connector => ConnectorViewTab(ctl),
              ClientTab.results => ResultsTab(ctl),
              ClientTab.log => LogTab(ctl),
              ClientTab.info => InfoTab(ctl, started: started),
              ClientTab.config => ConfigTab(ctl),
            },
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// footer + toast
// ---------------------------------------------------------------------------

class _Footer extends StatelessWidget {
  final ClientController ctl;
  const _Footer(this.ctl);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final s = ctl.s;
    final sum = Summary.of(ctl.rows);
    final port = s.link
        ? '● ${s.serialLink ? (s.selPort ?? '') : s.host} @ ${s.port}'
        : '○ Not connected';
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(children: [
        Text(port,
            style: ctext(context,
                size: 12, color: s.link ? c.green : c.muted)),
        _Sep(),
        Text(s.fwVersion == null ? 'FW —' : 'FW v${s.fwVersion}',
            style: ctext(context, size: 12, color: c.muted)),
        _Sep(),
        // CL-112: the firmware reads the board sensor every 60 s while idle.
        Text(
            s.boardTempDeciC == null
                ? 'Board temp —'
                : 'Board temp ${(s.boardTempDeciC! / 10).toStringAsFixed(1)} °C',
            style: ctext(context, size: 12, color: c.muted)),
        _Sep(),
        Text('PASS: ${sum.pass}',
            style: ctext(context, size: 12, color: c.muted)),
        _Sep(),
        Text('FAIL: ${sum.fail + sum.open + sum.miswire}',
            style: ctext(context,
                size: 12,
                weight: FontWeight.w600,
                color: sum.fail + sum.open + sum.miswire > 0 ? c.red : c.muted)),
        const Spacer(),
        Text('Designed and developed by Infinity Integrations Private Limited',
            style: ctext(context, size: 12, color: c.muted)),
        const SizedBox(width: 10),
        Image.asset('assets/company_logo_symbol.png',
            height: 28, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
      ]),
    );
  }
}

class _Sep extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text('|', style: ctext(context, size: 12, color: context.cc.border)),
      );
}

class _ToastView extends StatelessWidget {
  final ClientController ctl;
  const _ToastView(this.ctl);

  @override
  Widget build(BuildContext context) {
    final t = ctl.toast;
    if (t == null) return const SizedBox.shrink();
    final c = context.cc;
    final (bg, fg) = switch (t.kind) {
      'success' => (c.green, Colors.white),
      'warning' => (c.amber, const Color(0xFF1C1C1C)),
      'error' => (c.red, Colors.white),
      _ => (c.blue, Colors.white),
    };
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 14)],
        ),
        child: Text(t.text,
            style: ctext(context, size: 13, weight: FontWeight.w600, color: fg)),
      ),
    );
  }
}

/// Where the client app keeps profiles and settings: next to the console's own
/// data, under `…/HT_MK1/client`.
Directory defaultClientDataDir() =>
    Directory('${defaultLogDir().parent.path}${Platform.pathSeparator}client');
