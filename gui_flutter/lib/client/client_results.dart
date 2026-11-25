/// The **Results Table** tab (`ui/results_table.py`): a Filters card (Status,
/// search, Clear), the table with a coloured status badge, and the Summary
/// chips `Total / PASS / FAIL / OPEN / MISWIRE`.
library;

import 'package:flutter/material.dart';

import 'client_controller.dart';
import 'client_model.dart';
import 'client_theme.dart';
import 'client_widgets.dart';

Color statusColor(ClientColors c, RowStatus s) => switch (s) {
      RowStatus.connected || RowStatus.pass => c.green,
      RowStatus.miswire => c.amber,
      _ => c.red,
    };

class ResultsTab extends StatefulWidget {
  final ClientController ctl;
  const ResultsTab(this.ctl, {super.key});

  @override
  State<ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends State<ResultsTab> {
  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      // GUI-RT-008: auto-scroll while scanning, unless the operator scrolled up.
      _follow = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final ctl = widget.ctl;
    final all = ctl.rows;
    final rows = ctl.filteredRows;
    final cols = columnsFor(ctl.viewMode, autoScan: ctl.autoScan);
    final sum = Summary.of(all);

    if (ctl.running && _follow && rows.length != _lastCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
    _lastCount = rows.length;

    final statusOptions = <String, String>{
      'All': 'All',
      for (final s in _statusesFor(ctl)) s: s,
    };

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        GroupCard(
          title: 'Filters',
          child: Row(children: [
            Text('Status:', style: ctext(context, size: 12.5, color: c.muted)),
            const SizedBox(width: 8),
            CDropdown<String>(
              width: 170,
              value: ctl.statusFilter,
              items: statusOptions,
              onChanged: (v) => ctl.setFilter(status: v),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CField(
                value: ctl.search,
                hint: 'Search pin name or net…',
                onChanged: (v) => ctl.setFilter(query: v),
              ),
            ),
            const SizedBox(width: 12),
            CButton('Clear',
                role: CRole.ghost,
                compact: true,
                onPressed: ctl.clearFilters),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: c.card,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              _HeaderRow(cols),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(
                          all.isEmpty
                              ? 'No results yet — run a test'
                              : 'No rows match the filters',
                          style: ctext(context, size: 13, color: c.dim),
                        ),
                      )
                    : Scrollbar(
                        controller: _scroll,
                        child: ListView.builder(
                          controller: _scroll,
                          itemCount: rows.length,
                          itemExtent: 34,
                          itemBuilder: (_, i) => _DataRow(rows[i], cols, i),
                        ),
                      ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        GroupCard(
          title: 'Summary',
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            Pill('Total: ${sum.total}', bg: c.neutral),
            Pill('PASS: ${sum.pass}', bg: c.green),
            Pill('FAIL: ${sum.fail}', bg: c.red),
            Pill('OPEN: ${sum.open}', bg: c.red),
            Pill('MISWIRE: ${sum.miswire}',
                bg: c.amber, fg: const Color(0xFF1C1C1C)),
          ]),
        ),
      ]),
    );
  }

  List<String> _statusesFor(ClientController ctl) {
    if (ctl.autoScan) return const ['CONNECTED'];
    return switch (ctl.viewMode) {
      ClientMode.continuity => const ['CONNECTED', 'NOT CONNECTED'],
      ClientMode.cross => const ['CONNECTED', 'NOT CONNECTED', 'MISWIRE'],
      ClientMode.resistance => const ['PASS', 'FAIL HIGH', 'FAIL LOW'],
      ClientMode.insulation => const ['PASS', 'FAIL'],
      // Never returned: viewMode is always a concrete test.
      ClientMode.multi => const ['CONNECTED', 'NOT CONNECTED'],
    };
  }
}

/// Relative widths of the columns.
double _flex(Col c) => switch (c) {
      Col.test => 0.7,
      Col.pinA || Col.pinB => 0.9,
      Col.status => 1.5,
      Col.source || Col.destination => 1.3,
      Col.net => 2.0,
      Col.value || Col.limit || Col.limitIns || Col.insulation => 1.2,
      _ => 1.1,
    };

class _HeaderRow extends StatelessWidget {
  final List<Col> cols;
  const _HeaderRow(this.cols);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    return Container(
      height: 40,
      color: c.input,
      child: Row(children: [
        for (final col in cols)
          Expanded(
            flex: (_flex(col) * 10).round(),
            child: Center(
              child: Text(col.title,
                  style: ctext(context,
                      size: 12, weight: FontWeight.w700, color: c.muted)),
            ),
          ),
      ]),
    );
  }
}

class _DataRow extends StatelessWidget {
  final CRow row;
  final List<Col> cols;
  final int index;
  const _DataRow(this.row, this.cols, this.index);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    return Container(
      decoration: BoxDecoration(
        color: index.isOdd ? c.input.withValues(alpha: .5) : Colors.transparent,
        border: Border(bottom: BorderSide(color: c.border.withValues(alpha: .5))),
      ),
      child: Row(children: [
        for (final col in cols)
          Expanded(
            flex: (_flex(col) * 10).round(),
            child: Center(
              child: col == Col.status
                  ? _Badge(row.status)
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        cell(row, col),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ctext(context, size: 12.5),
                      ),
                    ),
            ),
          ),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  final RowStatus status;
  const _Badge(this.status);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final bg = statusColor(c, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(
        status.label,
        style: ctext(context,
            size: 11,
            weight: FontWeight.w700,
            color: status == RowStatus.miswire
                ? const Color(0xFF1C1C1C)
                : Colors.white),
      ),
    );
  }
}
