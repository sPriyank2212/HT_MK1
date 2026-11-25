/// The client's **Netlist Editor** (`ui/netlist_editor.py`), for the two
/// netlists the MK1 instrument has: continuity + resistance (on the Matrix
/// connector) and HV insulation (on the HV connector).
///
/// Wires are edited in a table, checked as they are typed (the same limits the
/// loader and the firmware enforce), saved as an `.xlsx` in the client's column
/// format, and — with **Apply to test** — loaded straight into the app through
/// the same path as Browse…, so what the editor makes is exactly what a saved
/// file would load.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../htproto/netlist_formats.dart';
import 'client_controller.dart';
import 'client_theme.dart';
import 'client_widgets.dart';
import 'netlist_doc.dart';

/// Opens the editor. [blank] starts an empty netlist; otherwise the loaded one
/// of [kind] is edited (an empty document if none is loaded).
Future<void> openNetlistEditor(
  BuildContext context,
  ClientController ctl,
  NetlistKind kind, {
  bool blank = false,
}) {
  final s = ctl.s;
  final NetlistDoc doc;
  if (blank) {
    doc = NetlistDoc.blank(kind);
  } else if (kind == NetlistKind.mtx && s.nlMtx.loaded && s.mtxRows.isNotEmpty) {
    doc = NetlistDoc.fromParsed(kind, s.mtxRows,
        name: s.nlMtx.name ?? 'netlist.xlsx', harnessId: s.nlHarnessId);
  } else if (kind == NetlistKind.hv && s.nlHv.loaded && s.hvRows.isNotEmpty) {
    doc = NetlistDoc.fromParsed(kind, s.hvRows,
        name: s.nlHv.name ?? 'hv_netlist.xlsx');
  } else {
    doc = NetlistDoc.blank(kind);
  }
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0xB3000000),
    builder: (_) => ClientTheme(
      colors: ctl.dark ? ClientColors.darkTheme : ClientColors.lightTheme,
      child: _NetlistEditor(ctl, doc),
    ),
  );
}

class _NetlistEditor extends StatefulWidget {
  final ClientController ctl;
  final NetlistDoc doc;
  const _NetlistEditor(this.ctl, this.doc);

  @override
  State<_NetlistEditor> createState() => _NetlistEditorState();
}

class _NetlistEditorState extends State<_NetlistEditor> {
  NetRowDraft? _sel;
  String _fillCount = '8';
  String _fillFrom = '1';
  String? _status;
  bool _statusError = false;

  NetlistDoc get doc => widget.doc;
  bool get _hv => doc.kind == NetlistKind.hv;
  int get _stack => widget.ctl.s.stack;

  void _changed() => setState(() => _status = null);

  void _say(String text, {bool error = false}) => setState(() {
        _status = text;
        _statusError = error;
      });

  // ---- actions ------------------------------------------------------------

  void _add() {
    _sel = doc.addRow();
    _changed();
  }

  void _duplicate() {
    final s = _sel;
    if (s == null) return _say('Select a wire first (click its number).');
    _sel = doc.duplicate(s);
    _changed();
  }

  void _delete() {
    final s = _sel;
    if (s == null) return _say('Select a wire first (click its number).');
    final i = doc.rows.indexOf(s);
    doc.rows.remove(s);
    _sel = doc.rows.isEmpty ? null : doc.rows[i.clamp(0, doc.rows.length - 1)];
    _changed();
  }

  void _fill() {
    final n = int.tryParse(_fillCount.trim());
    final from = int.tryParse(_fillFrom.trim());
    if (n == null || from == null || n < 1 || n > 256 || from < 1) {
      return _say('Enter how many wires (1–256) and the first pin.', error: true);
    }
    doc.fillStraightThrough(n, from);
    _changed();
  }

  void _copyFromContinuity() {
    final src = widget.ctl.s.mtxRows;
    if (src.isEmpty) {
      return _say('No continuity netlist is loaded to copy from.', error: true);
    }
    doc.rows.clear();
    for (final p in src) {
      final r = NetRowDraft();
      r[NCol.net] = p.name ?? '';
      r[NCol.hsPin] = '${p.hi}';
      r[NCol.lsPin] = '${p.lo}';
      doc.rows.add(r);
    }
    _sel = null;
    _changed();
  }

  Future<void> _save() async {
    final issues = doc.validate(stack: _stack).where((i) => i.error).toList();
    if (issues.isNotEmpty) {
      return _say('Fix ${issues.length} error${issues.length == 1 ? '' : 's'} '
          'before saving.', error: true);
    }
    final name = doc.name.trim().isEmpty ? 'netlist.xlsx' : doc.name.trim();
    final path = await widget.ctl.s.pickSavePath(
      dialogTitle: 'Save netlist',
      fileName: kNetlistExtensions.contains(extensionOf(name))
          ? name
          : '$name.xlsx',
      allowedExtensions: kNetlistExtensions,
    );
    if (path == null) return;
    try {
      final target = withNetlistExtension(path);
      await File(target).writeAsBytes(doc.toBytes(extensionOf(target)));
      _say('Saved ${File(target).uri.pathSegments.last}');
    } on Object catch (e) {
      _say('Could not save: $e', error: true);
    }
  }

  Future<void> _apply() async {
    final ctl = widget.ctl;
    final s = ctl.s;
    final errors = doc.validate(stack: _stack).where((i) => i.error).toList();
    if (errors.isNotEmpty) {
      return _say('Fix ${errors.length} error${errors.length == 1 ? '' : 's'} '
          'before applying.', error: true);
    }
    final name = doc.name.trim().isEmpty ? 'netlist.xlsx' : doc.name.trim();
    final bytes = doc.toXlsx();
    final ok = _hv
        ? await s.loadHvNetlistBytes(name, bytes, continueToVerify: s.mdNlOpen)
        : await s.loadMtxNetlistBytes(name, bytes);
    if (!mounted) return;
    if (!ok) {
      return _say(
          _hv
              ? 'The netlist could not be loaded — see the Log.'
              : 'The tester did not accept the netlist — see the Log.',
          error: true);
    }
    if (!_hv) ctl.setAutoScan(false);
    ctl.showToast('${_hv ? 'HV' : 'Continuity / resistance'} netlist applied: $name',
        kind: 'success');
    if (mounted) Navigator.of(context).pop();
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final s = widget.ctl.s;
    final size = MediaQuery.sizeOf(context);
    final issues = doc.validate(stack: _stack);
    final errs = issues.where((i) => i.error).length;
    final warns = issues.length - errs;
    final badRows = {for (final i in issues.where((i) => i.error && i.row != null)) i.row!};
    final canApply = !widget.ctl.running && (_hv || s.link);
    final cols = doc.columns;
    final tableW = 76.0 +
        cols.fold<double>(0, (a, b) => a + b.width + 6) +
        (_hv ? 2 * 96.0 : 0);

    return Dialog(
      backgroundColor: c.card,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
          side: BorderSide(color: c.border),
          borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: (size.width - 48).clamp(640, 1240).toDouble(),
        height: (size.height - 48).clamp(480, 760).toDouble(),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                _hv
                    ? 'Netlist Editor — HV Insulation (J-HV)'
                    : 'Netlist Editor — Continuity / Resistance (J-MTX)',
                style: ctext(context, size: 16, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              _hv
                  ? 'One row per net: the HS pin is the HV card relay that injects, the LS pin is its return. '
                      'HS 1–64 is card 1, 65–128 card 2, and so on. This netlist is sent to the tester only for the insulation run.'
                  : 'One row per wire: Side-A pin to Side-B pin. Used by Continuity and Resistance.',
              style: ctext(context, size: 12, color: c.muted),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Text('File name:', style: ctext(context, size: 12.5, color: c.muted)),
              const SizedBox(width: 8),
              CField(
                  value: doc.name,
                  width: 260,
                  onChanged: (v) => doc.name = v),
              if (!_hv) ...[
                const SizedBox(width: 18),
                Text('Harness ID:',
                    style: ctext(context, size: 12.5, color: c.muted)),
                const SizedBox(width: 8),
                CField(
                    value: doc.harnessId,
                    width: 200,
                    hint: 'e.g. HRN-2026-001',
                    onChanged: (v) => doc.harnessId = v),
              ],
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              CButton('Add Wire', role: CRole.secondary, compact: true, onPressed: _add),
              CButton('Duplicate', role: CRole.ghost, compact: true, onPressed: _duplicate),
              CButton('Delete', role: CRole.ghost, compact: true, onPressed: _delete),
              const SizedBox(width: 10),
              Text('Add', style: ctext(context, size: 12.5, color: c.muted)),
              CField(
                  value: _fillCount,
                  width: 56,
                  align: TextAlign.center,
                  onChanged: (v) => _fillCount = v),
              Text('straight-through wires from pin',
                  style: ctext(context, size: 12.5, color: c.muted)),
              CField(
                  value: _fillFrom,
                  width: 56,
                  align: TextAlign.center,
                  onChanged: (v) => _fillFrom = v),
              CButton('Add', role: CRole.ghost, compact: true, onPressed: _fill),
              if (_hv) ...[
                const SizedBox(width: 10),
                CButton('Copy from continuity netlist',
                    role: CRole.ghost,
                    compact: true,
                    onPressed: s.mtxRows.isEmpty ? null : _copyFromContinuity),
              ],
            ]),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: c.input,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Scrollbar(
                  notificationPredicate: (n) => n.depth == 1,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableW,
                      child: Column(children: [
                        _header(context, cols),
                        Expanded(
                          child: doc.rows.isEmpty
                              ? Center(
                                  child: Text(
                                      'No wires yet — Add Wire, or add straight-through wires above.',
                                      style: ctext(context, size: 13, color: c.dim)))
                              : ListView.builder(
                                  itemCount: doc.rows.length,
                                  itemExtent: 40,
                                  itemBuilder: (_, i) =>
                                      _row(context, cols, i, badRows.contains(i + 1)),
                                ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _IssueBar(issues: issues, errors: errs, warnings: warns),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_status!,
                    style: ctext(context,
                        size: 12.5,
                        weight: FontWeight.w600,
                        color: _statusError ? c.red : c.green)),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Text('${doc.rows.length} wire${doc.rows.length == 1 ? '' : 's'}',
                  style: ctext(context, size: 12, color: c.muted)),
              if (!_hv && !s.link) ...[
                const SizedBox(width: 14),
                Text('Connect to the tester to apply this netlist.',
                    style: ctext(context, size: 12, color: c.amber)),
              ],
              const Spacer(),
              CButton('Save as .xlsx…', role: CRole.ghost, onPressed: _save),
              const SizedBox(width: 8),
              CButton('Apply to test',
                  role: CRole.primary,
                  tooltip: canApply ? null : 'Connect to the tester first',
                  onPressed: canApply ? _apply : null),
              const SizedBox(width: 8),
              CButton('Close',
                  role: CRole.neutral,
                  onPressed: () => Navigator.of(context).pop()),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, List<NCol> cols) {
    final c = context.cc;
    TextStyle st() =>
        ctext(context, size: 11.5, weight: FontWeight.w700, color: c.muted);
    Widget h(String t, double w) => SizedBox(
        width: w, child: Center(child: Text(t, style: st(), maxLines: 1)));
    return Container(
      height: 32,
      color: c.bg,
      child: Row(children: [
        h('#', 70),
        for (final col in cols) ...[
          const SizedBox(width: 6),
          h(_hv && col == NCol.hsPin ? 'HS Pin' : col.title, col.width),
          if (_hv && col == NCol.lsPin) ...[
            const SizedBox(width: 6),
            h('Card', 90),
            const SizedBox(width: 6),
            h('Relay', 90),
          ],
        ],
      ]),
    );
  }

  Widget _row(BuildContext context, List<NCol> cols, int i, bool bad) {
    final c = context.cc;
    final r = doc.rows[i];
    final sel = identical(r, _sel);
    final hs = r.hi;
    final loc = hs == null || hs < 1 ? null : NetlistDoc.hvLocation(hs);
    return Container(
      decoration: BoxDecoration(
        color: bad
            ? c.red.withValues(alpha: .12)
            : (sel ? c.blue.withValues(alpha: .16) : Colors.transparent),
        border: Border(bottom: BorderSide(color: c.border.withValues(alpha: .6))),
      ),
      child: Row(children: [
        ClickBox(
          onTap: () => setState(() => _sel = sel ? null : r),
          builder: (_) => SizedBox(
            width: 70,
            height: 40,
            child: Center(
              child: Text('${i + 1}',
                  style: ctext(context,
                      size: 12,
                      weight: sel ? FontWeight.w800 : FontWeight.w400,
                      color: sel ? c.blue : c.muted)),
            ),
          ),
        ),
        for (final col in cols) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: col.width,
            child: CField(
              key: ValueKey('${r.id}-${col.name}'),
              value: r[col],
              align: (col == NCol.srcPin ||
                      col == NCol.dstPin ||
                      col == NCol.hsPin ||
                      col == NCol.lsPin ||
                      col == NCol.awg)
                  ? TextAlign.center
                  : TextAlign.start,
              onChanged: (v) {
                r[col] = v;
                _changed();
              },
            ),
          ),
          if (_hv && col == NCol.lsPin) ...[
            const SizedBox(width: 6),
            SizedBox(
                width: 90,
                child: Center(
                    child: Text(loc == null ? '—' : 'H${loc.$1}',
                        style: ctext(context, size: 12.5, color: c.muted)))),
            const SizedBox(width: 6),
            SizedBox(
                width: 90,
                child: Center(
                    child: Text(
                        loc == null
                            ? '—'
                            : 'HS-${loc.$2.toString().padLeft(2, '0')}',
                        style: ctext(context, size: 12.5, color: c.muted)))),
          ],
        ],
      ]),
    );
  }
}

class _IssueBar extends StatelessWidget {
  final List<NetlistIssue> issues;
  final int errors, warnings;
  const _IssueBar(
      {required this.issues, required this.errors, required this.warnings});

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    if (issues.isEmpty) {
      return Text('Netlist is valid.',
          style: ctext(context, size: 12.5, weight: FontWeight.w600, color: c.green));
    }
    final shown = issues.take(3).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        [
          if (errors > 0) '$errors error${errors == 1 ? '' : 's'}',
          if (warnings > 0) '$warnings warning${warnings == 1 ? '' : 's'}',
        ].join(' · '),
        style: ctext(context,
            size: 12.5,
            weight: FontWeight.w700,
            color: errors > 0 ? c.red : c.amber),
      ),
      for (final i in shown)
        Text(i.toString(),
            style: ctext(context,
                size: 12, color: i.error ? c.red : c.amber)),
      if (issues.length > shown.length)
        Text('… and ${issues.length - shown.length} more',
            style: ctext(context, size: 12, color: c.muted)),
    ]);
  }
}
