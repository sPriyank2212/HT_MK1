/// The **Log**, **Info** and **Configuration** tabs (`ui/log_panel.py`,
/// `ui/info_panel.py`, `ui/config_panel.py`).
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/build_tag.dart';
import '../design/model.dart';
import 'client_controller.dart';
import 'client_theme.dart';
import 'client_widgets.dart';

// ---------------------------------------------------------------------------
// Log
// ---------------------------------------------------------------------------

String _stampSeconds(double t) {
  final ms = (t * 1000).round();
  String two(int n) => n.toString().padLeft(2, '0');
  final h = ms ~/ 3600000;
  final m = (ms ~/ 60000) % 60;
  final sec = (ms ~/ 1000) % 60;
  return '${two(h)}:${two(m)}:${two(sec)}.${(ms % 1000).toString().padLeft(3, '0')}';
}

String _stampTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
}

final RegExp _fwSeverity = RegExp(r'^#?([EW])\[');

/// `INFO` / `WARN` / `ERROR`. Firmware lines (`src == 'fw'`) arrive from the
/// instrument at level info; their real severity is the `E[` / `W[` prefix the
/// firmware's logger writes, so use that.
String logLevelOf(LogEntry e) {
  if (e.src == 'fw') {
    final m = _fwSeverity.firstMatch(e.message);
    if (m != null) return m.group(1) == 'E' ? 'ERROR' : 'WARN';
  }
  return switch (e.lvl) { 'warn' => 'WARN', 'fail' => 'ERROR', _ => 'INFO' };
}

String _two(int n) => n.toString().padLeft(2, '0');

String _stampDate(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${_stampTime(t)}';

/// `[HH:MM:SS.mmm] [LEVEL] message` — one line of the Log tab, stamped with
/// the real local time the entry was made.
String logLine(LogEntry e) {
  final w = e.wall;
  final stamp = w == null ? _stampSeconds(e.t) : _stampTime(w);
  return '[$stamp] [${logLevelOf(e)}] ${e.message}';
}

/// The whole log as ONE text file: a header saying which app / firmware / port
/// produced it, the application log (with date, level and source on every
/// line), then the raw serial traffic. This is what an operator sends back
/// when something fails on the bench.
String buildLogFileText(AppState s, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final fw = s.fwVersion;
  final state = !s.link ? 'not connected' : (s.instState?.name.toUpperCase() ?? '—');
  final port = s.serialLink ? '${s.selPort ?? '—'} @ ${s.port} baud' : '${s.host}:${s.port}';
  final b = StringBuffer()
    ..writeln('HARNESS TESTER - LOG FILE')
    ..writeln('Generated  : ${_stampDate(at)}')
    ..writeln('App build  : $kBuildStamp')
    ..writeln('Firmware   : ${fw == null ? '—' : 'v$fw'}   build ${s.fwBuild ?? '—'}')
    ..writeln('Link       : ${s.link ? 'connected' : 'not connected'}   port $port')
    ..writeln('Device     : $state   fixture ${!s.link ? '—' : (s.onHv ? 'J-HV' : 'J-MTX')}')
    ..writeln()
    ..writeln('===== APPLICATION LOG (${s.logs.length} lines) =====');
  for (final e in s.logs) {
    final w = e.wall;
    final stamp = w == null ? _stampSeconds(e.t) : _stampDate(w);
    b.writeln('[$stamp] [${logLevelOf(e).padRight(5)}] ${e.src.padRight(5)} ${e.message}');
  }
  b
    ..writeln()
    ..writeln('===== SERIAL TRAFFIC TX/RX (${s.wireLog.length} lines, '
        'newest ${AppState.wireLogCap} kept) =====');
  for (final w in s.wireLog) {
    b.writeln('[${_stampDate(w.t)}] [${w.dir.toUpperCase()}] ${w.text}');
  }
  return b.toString().replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
}

class LogTab extends StatefulWidget {
  final ClientController ctl;
  const LogTab(this.ctl, {super.key});

  @override
  State<LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<LogTab> {
  bool _wire = false;
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = widget.ctl.s;
    final now = DateTime.now();
    final name = 'harness_tester_log_${now.year}${_two(now.month)}${_two(now.day)}'
        '_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}.txt';
    final path = await s.pickSavePath(
      dialogTitle: 'Save log',
      fileName: name,
      allowedExtensions: const ['txt'],
    );
    if (path == null) return;
    try {
      await File(path).writeAsString(buildLogFileText(s, now: now));
      widget.ctl.showToast('Log saved to $path', kind: 'success');
    } on Object catch (e) {
      widget.ctl.showToast('Could not save the log: $e', kind: 'error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final s = widget.ctl.s;
    final lines = <(String, Color)>[];
    if (_wire) {
      for (final w in s.wireLog) {
        final tx = w.dir == 'tx';
        lines.add((
          '[${_stampTime(w.t)}] [${tx ? 'TX' : 'RX'}] ${w.text}',
          tx ? c.blue : c.green,
        ));
      }
    } else {
      for (final e in s.logs) {
        lines.add((
          logLine(e),
          switch (logLevelOf(e)) { 'WARN' => c.amber, 'ERROR' => c.red, _ => c.text },
        ));
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          CButton('Save Log (.txt)…',
              role: CRole.primary, compact: true, onPressed: _save),
          const SizedBox(width: 18),
          SizedBox(
            width: 230,
            child: CCheck('Show serial traffic (TX / RX)',
                value: _wire, onChanged: (v) => setState(() => _wire = v)),
          ),
          const Spacer(),
          Text('${lines.length} lines',
              style: ctext(context, size: 11.5, color: c.dim)),
          // Kept well apart from Save Log and set off at the far end, so it is
          // not hit by mistake.
          const SizedBox(width: 48),
          CButton('Clear Log',
              role: CRole.ghost,
              compact: true,
              tooltip: 'Erase the log shown on this tab',
              onPressed: () {
                s.logs.clear();
                s.wireLog.clear();
                s.updateControls();
              }),
        ]),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: c.input,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Scrollbar(
              controller: _scroll,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(10),
                itemCount: lines.length,
                itemBuilder: (_, i) => Text(
                  lines[i].$1,
                  style: ctext(context,
                      size: 12, color: lines[i].$2, family: kClientMono),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Info
// ---------------------------------------------------------------------------

class InfoTab extends StatelessWidget {
  final ClientController ctl;
  final DateTime started;
  const InfoTab(this.ctl, {super.key, required this.started});

  @override
  Widget build(BuildContext context) {
    final s = ctl.s;
    String two(int n) => n.toString().padLeft(2, '0');
    final st = '${started.year}-${two(started.month)}-${two(started.day)} '
        '${two(started.hour)}:${two(started.minute)}';
    final fw = s.fwVersion;
    final state = !s.link
        ? '—'
        : (s.instState?.name.toUpperCase() ?? '—');
    return ListView(padding: const EdgeInsets.all(16), children: [
      _InfoCard('GUI / Application', [
        ('App version', kBuildStamp),
        ('Protocol version', '1.0'),
        ('Model', 'HT_MK1'),
        ('Started', st),
      ]),
      const SizedBox(height: 14),
      _InfoCard('Firmware / Device', [
        ('FW version', fw == null ? '—' : 'v$fw'),
        ('Firmware build', s.fwBuild ?? '—'),
        ('Device state', state),
        ('Fixture', !s.link ? '—' : (s.onHv ? 'J-HV' : 'J-MTX')),
        ('Port', s.serialLink ? (s.selPort ?? '—') : '${s.host}:${s.port}'),
        ('Baud', s.serialLink ? '${s.port}' : '—'),
      ]),
    ]);
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const _InfoCard(this.title, this.rows);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    return GroupCard(
      title: title,
      child: Column(children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(
                width: 170,
                child: Text('$k:',
                    textAlign: TextAlign.right,
                    style: ctext(context, size: 13, color: c.muted)),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: SelectableText(v, style: ctext(context, size: 13)),
              ),
            ]),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

class ConfigTab extends StatefulWidget {
  final ClientController ctl;
  const ConfigTab(this.ctl, {super.key});

  @override
  State<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<ConfigTab> {
  String? _r;
  String? _ins;

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final ctl = widget.ctl;
    final s = ctl.s;
    final lim = s.limits;
    final rText = _r ?? (lim == null ? '' : (lim.rMaxMohm / 1000).toStringAsFixed(1));
    final insText =
        _ins ?? (lim == null ? '' : (lim.insMinMohm / 1.0e9).toStringAsFixed(1));
    final conns = kFix.connectors;

    return ListView(padding: const EdgeInsets.all(16), children: [
      GroupCard(
        title: 'Test limits',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            lim == null
                ? 'Not connected — limits are read from the tester on connect.'
                : 'Read from the tester on connect. Apply writes both limits to it.',
            style: ctext(context, size: 12, color: c.muted),
          ),
          const SizedBox(height: 10),
          Row(children: [
            SizedBox(
                width: 190,
                child: Text('Resistance limit (Ω, max):',
                    style: ctext(context, size: 13, color: c.muted))),
            CField(
                value: rText,
                width: 110,
                align: TextAlign.right,
                onChanged: (v) => _r = v),
            const SizedBox(width: 6),
            Text('0 – 20 Ω', style: ctext(context, size: 11.5, color: c.dim)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(
                width: 190,
                child: Text('Insulation limit (MΩ, min):',
                    style: ctext(context, size: 13, color: c.muted))),
            CField(
                value: insText,
                width: 110,
                align: TextAlign.right,
                onChanged: (v) => _ins = v),
            const SizedBox(width: 6),
            Text('0.1 – 40 MΩ', style: ctext(context, size: 11.5, color: c.dim)),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: CButton('Apply',
                role: CRole.secondary,
                compact: true,
                onPressed: !s.link || ctl.running ? null : _apply),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      GroupCard(
        title: 'HV card stack',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'How many HV cards are fitted. The HV netlist must match — a 4-card netlist on a 3-card stack leaves 64 nets unreachable.',
            style: ctext(context, size: 12, color: c.muted),
          ),
          const SizedBox(height: 10),
          Row(children: [
            for (final n in [1, 2, 3, 4]) ...[
              CRadio('$n card${n > 1 ? 's' : ''}',
                  selected: s.stack == n,
                  onTap: ctl.running ? null : () => s.pickStack(n)),
              const SizedBox(width: 22),
            ],
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      GroupCard(
        title: 'Connector configuration',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Which connector each tester channel is wired to. This is read from the loaded netlist (its Conn ID and Part Number columns) and shown on the Connector View and in the reports.',
            style: ctext(context, size: 12, color: c.muted),
          ),
          const SizedBox(height: 10),
          Container(
            color: c.input,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              for (final h in ['Side', 'Conn ID', 'Part Number', 'Pins', 'First channel'])
                Expanded(
                    child: Text(h,
                        textAlign: TextAlign.center,
                        style: ctext(context,
                            size: 11.5, weight: FontWeight.w700, color: c.muted))),
            ]),
          ),
          if (!s.nlFix.loaded || conns.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('No connector layout yet — load a netlist with Conn ID and Part Number columns.',
                  style: ctext(context, size: 12.5, color: c.dim)),
            )
          else
            for (final k in conns)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.border))),
                child: Row(children: [
                  for (final v in [
                    k.side == 'L' ? 'Source' : 'Destination',
                    k.name,
                    k.partNumber,
                    '${k.pins}',
                    '${k.base + 1}',
                  ])
                    Expanded(
                        child: Text(v,
                            textAlign: TextAlign.center,
                            style: ctext(context, size: 12.5))),
                ]),
              ),
        ]),
      ),
    ]);
  }

  void _apply() {
    final ctl = widget.ctl;
    final s = ctl.s;
    final r = double.tryParse((_r ?? '').trim());
    final ins = double.tryParse((_ins ?? '').trim());
    final curR = s.limits == null ? null : s.limits!.rMaxMohm / 1000;
    final curIns = s.limits == null ? null : s.limits!.insMinMohm / 1.0e9;
    final rv = r ?? curR;
    final iv = ins ?? curIns;
    if (rv == null || iv == null || rv < 0 || rv > 20 || iv < 0.1 || iv > 40) {
      ctl.showToast('Resistance must be 0–20 Ω and insulation 0.1–40 MΩ',
          kind: 'warning');
      return;
    }
    s.setLimits((rv * 1000).round(), (iv * 1.0e9).round());
    ctl.showToast('Limits applied', kind: 'success');
  }
}
