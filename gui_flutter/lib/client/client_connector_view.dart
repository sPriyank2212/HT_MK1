/// The **Connector View** tab (`ui/connector_view.py`): the harness drawn as a
/// Source connector on the left and a Destination connector on the right, one
/// row per wire — pin number and signal label at each end, the wire between
/// them with its `W<n>` tag and a status pill (`UNTESTED`, `IN PROGRESS`,
/// `PASS`, `FAIL`, or the measured value) — under a blue
/// **CONTINUITY / RESISTANCE** band, and an amber **HV INSULATION** band for
/// the MK1 insulation test.
///
/// Colours follow the client's legend: grey untested, amber in progress,
/// green pass, red fail, light-blue HV result.
library;

import 'package:flutter/material.dart';

import '../design/model.dart';
import 'client_controller.dart';
import 'client_model.dart';
import 'client_theme.dart';

enum _W { untested, running, pass, fail, miswire }

class _Wire {
  int index;
  final int hi, lo;
  final String labelA, labelB;
  final _W state;
  final String text;
  _Wire(this.index, this.hi, this.lo, this.labelA, this.labelB, this.state,
      this.text);
}

class _Group {
  final String left, right;
  final List<_Wire> wires = [];
  _Group(this.left, this.right);
}

class ConnectorViewTab extends StatelessWidget {
  final ClientController ctl;
  const ConnectorViewTab(this.ctl, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final s = ctl.s;
    final groups = _groups(ctl);
    final showHv = ctl.viewMode == ClientMode.insulation ||
        s.insulRowsLive.isNotEmpty ||
        s.R['hv'] != null;

    return Column(children: [
      Expanded(
        child: groups.isEmpty && !showHv
            ? Center(
                child: Text(
                  ctl.autoScan
                      ? 'Run an Auto-Scan to see the connections'
                      : 'Load a netlist to see the wiring diagram',
                  style: ctext(context, size: 13, color: c.dim),
                ),
              )
            : Scrollbar(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  children: [
                    if (groups.isNotEmpty) ...[
                      _Band(
                        '${ctl.viewMode == ClientMode.resistance ? 'RESISTANCE' : 'CONTINUITY / RESISTANCE'}'
                        '  —  Source Pins  ↔  Destination Pins',
                        c.bandBlue,
                      ),
                      for (final g in groups) _GroupView(g),
                    ],
                    if (showHv) ...[
                      const SizedBox(height: 10),
                      _Band(
                        'HV INSULATION  ${_hvVolts(ctl)}  —  Net  ↔  Insulation',
                        c.bandAmber,
                      ),
                      _HvRows(ctl),
                    ],
                  ],
                ),
              ),
      ),
      const _Legend(),
    ]);
  }

  static String _hvVolts(ClientController ctl) => '500 V DC';
}

// ---------------------------------------------------------------------------
// data
// ---------------------------------------------------------------------------

List<_Group> _groups(ClientController ctl) {
  final s = ctl.s;
  final out = <String, _Group>{};
  _Group grp(String l, String r) => out.putIfAbsent('$l|$r', () => _Group(l, r));

  final resByKey = {
    for (final r in s.resRowsLive) '${r.srcPin}:${r.dstPin}': r,
  };
  final found = {for (final (hi, lo) in s.discoveredPairs) '$hi:$lo'};
  final sweepDone = s.running == null && found.isNotEmpty;
  var idx = 0;

  _Wire wire(Net n, NetPair p) {
    idx++;
    final la = p.srcLabel ?? 'Pin ${p.hi}';
    final lb = p.dstLabel ?? 'Pin ${p.lo}';
    final key = p.key;
    if (ctl.viewMode == ClientMode.resistance && !ctl.autoScan) {
      final r = resByKey[key];
      if (r == null) return _Wire(idx, p.hi, p.lo, la, lb, _W.untested, 'UNTESTED');
      final ok = r.status == 'PASS';
      return _Wire(idx, p.hi, p.lo, la, lb, ok ? _W.pass : _W.fail,
          '${r.resistanceMohm.toStringAsFixed(1)} mΩ');
    }
    if (ctl.viewMode == ClientMode.cross || ctl.autoScan) {
      if (found.contains(key)) return _Wire(idx, p.hi, p.lo, la, lb, _W.pass, 'PASS');
      if (sweepDone) return _Wire(idx, p.hi, p.lo, la, lb, _W.fail, 'NOT CONNECTED');
      return _Wire(idx, p.hi, p.lo, la, lb, _W.untested, 'UNTESTED');
    }
    if (n.reportedPairs.contains(key)) {
      final bad = n.openPairs.contains(key);
      return _Wire(idx, p.hi, p.lo, la, lb, bad ? _W.fail : _W.pass,
          bad ? 'NOT CONNECTED' : 'PASS');
    }
    return _Wire(idx, p.hi, p.lo, la, lb, _W.untested, 'UNTESTED');
  }

  if (ctl.autoScan) {
    final g = grp('Side A', 'Side B');
    for (final (hi, lo) in s.discoveredPairs) {
      idx++;
      g.wires.add(_Wire(idx, hi, lo, 'Pin $hi', 'Pin $lo', _W.pass, 'PASS'));
    }
    return _numbered(out.values.where((g) => g.wires.isNotEmpty).toList());
  }

  for (final n in s.nets) {
    for (final p in n.pairs) {
      final g = grp(connName(p.src.c), connName(p.dst.c));
      g.wires.add(wire(n, p));
    }
  }

  // Cross Continuity: a connection found that the netlist does not list.
  if (ctl.viewMode == ClientMode.cross && sweepDone) {
    final listed = {
      for (final n in s.nets) for (final p in n.pairs) p.key,
    };
    for (final (hi, lo) in s.discoveredPairs) {
      if (listed.contains('$hi:$lo')) continue;
      idx++;
      grp('Unlisted', 'Unlisted')
          .wires
          .add(_Wire(idx, hi, lo, 'Pin $hi', 'Pin $lo', _W.miswire, 'MISWIRE'));
    }
  }
  return _numbered(out.values.toList());
}

/// W1, W2, … in the order the wires are drawn. The netlist's own order would
/// number one connector's rows 1, 2, 3, 18 whenever a later net lands back on
/// it.
List<_Group> _numbered(List<_Group> groups) {
  var i = 0;
  for (final g in groups) {
    for (final w in g.wires) {
      w.index = ++i;
    }
  }
  return groups;
}

Color _wc(ClientColors c, _W w) => switch (w) {
      _W.untested => c.untested,
      _W.running => c.running,
      _W.pass => c.pass,
      _W.fail => c.fail,
      _W.miswire => c.amber,
    };

// ---------------------------------------------------------------------------
// widgets
// ---------------------------------------------------------------------------

class _Band extends StatelessWidget {
  final String text;
  final Color bg;
  const _Band(this.text, this.bg);

  @override
  Widget build(BuildContext context) => Container(
        height: 26,
        margin: const EdgeInsets.only(bottom: 8),
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            style: ctext(context,
                size: 12,
                weight: FontWeight.w700,
                color: Colors.white,
                spacing: .6)),
      );
}

const double _rowH = 46;
const double _boxW = 240;

class _GroupView extends StatelessWidget {
  final _Group g;
  const _GroupView(this.g);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ConnBox(title: g.left, wires: g.wires, side: _Side.left),
        Expanded(
          child: Column(children: [
            const SizedBox(height: 26),
            for (final w in g.wires) _WireRow(w),
          ]),
        ),
        _ConnBox(title: g.right, wires: g.wires, side: _Side.right),
      ]),
    );
  }
}

enum _Side { left, right }

class _ConnBox extends StatelessWidget {
  final String title;
  final List<_Wire> wires;
  final _Side side;
  const _ConnBox({required this.title, required this.wires, required this.side});

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final left = side == _Side.left;
    return Container(
      width: _boxW,
      decoration: BoxDecoration(
        color: c.connBody,
        border: Border.all(color: c.connBorder, width: 1.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        Container(
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.connTitleBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
          ),
          child: Text(title.isEmpty ? '—' : title,
              style: ctext(context,
                  size: 11.5, weight: FontWeight.w700, color: c.connTitleFg)),
        ),
        for (final w in wires)
          SizedBox(
            height: _rowH,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment:
                    left ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: left
                    ? [
                        Flexible(
                          child: Text(w.labelA,
                              overflow: TextOverflow.ellipsis,
                              style: ctext(context, size: 11.5, color: c.muted)),
                        ),
                        const SizedBox(width: 6),
                        _PinDot('${w.hi}', _wc(c, w.state)),
                      ]
                    : [
                        _PinDot('${w.lo}', _wc(c, w.state)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(w.labelB,
                              overflow: TextOverflow.ellipsis,
                              style: ctext(context, size: 11.5, color: c.muted)),
                        ),
                      ],
              ),
            ),
          ),
        const SizedBox(height: 4),
      ]),
    );
  }
}

class _PinDot extends StatelessWidget {
  final String n;
  final Color color;
  const _PinDot(this.n, this.color);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: color, width: 1.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(n,
          style: ctext(context, size: 10.5, weight: FontWeight.w700)),
    );
  }
}

class _WireRow extends StatelessWidget {
  final _Wire w;
  const _WireRow(this.w);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final color = _wc(c, w.state);
    return SizedBox(
      height: _rowH,
      child: Stack(alignment: Alignment.center, children: [
        Positioned(
          top: 2,
          child: Text('› W${w.index}',
              style: ctext(context, size: 10, color: c.dim)
                  .copyWith(fontStyle: FontStyle.italic)),
        ),
        Container(height: 2, color: color.withValues(alpha: .85)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: c.card,
            border: Border.all(color: color, width: 1.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(w.text,
              style: ctext(context,
                  size: 10, weight: FontWeight.w700, color: color)),
        ),
      ]),
    );
  }
}

/// HV insulation: one row per net — name and card/HS pin on the left, the
/// measured insulation and its status on the right.
class _HvRows extends StatelessWidget {
  final ClientController ctl;
  const _HvRows(this.ctl);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final rows = ctl.s.insulRowsLive;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          ctl.s.running == 'insul'
              ? 'Insulation test running…'
              : 'Not run yet — choose HV Insulation and press START TEST',
          style: ctext(context, size: 12.5, color: c.dim),
        ),
      );
    }
    return Column(children: [
      for (final r in rows)
        Container(
          height: 38,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: c.connBody,
            border: Border.all(
                color: r.status == 'PASS' ? c.hvResult : c.fail, width: 1.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            SizedBox(
                width: 200,
                child: Text(r.net == '—' ? '(net)' : r.net,
                    overflow: TextOverflow.ellipsis,
                    style: ctext(context, size: 12.5, weight: FontWeight.w600))),
            Text('${r.hvCard} · ${r.hsPin}',
                style: ctext(context, size: 11.5, color: c.muted)),
            const Spacer(),
            Text('${r.insulationMohm.toStringAsFixed(1)} MΩ',
                style: ctext(context,
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: r.status == 'PASS' ? c.hvResult : c.fail)),
            const SizedBox(width: 12),
            Text(r.status,
                style: ctext(context,
                    size: 11.5,
                    weight: FontWeight.w700,
                    color: r.status == 'PASS' ? c.pass : c.fail)),
          ]),
        ),
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    Widget dot(String label, Color col) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: ctext(context, size: 10.5, color: c.muted)),
        ]);
    return Container(
      height: 30,
      alignment: Alignment.center,
      child: Wrap(spacing: 22, children: [
        dot('UNTESTED', c.untested),
        dot('IN PROGRESS', c.running),
        dot('PASS', c.pass),
        dot('FAIL', c.fail),
        dot('HV RESULT', c.hvResult),
      ]),
    );
  }
}
