/// The client's left panel: **Connection**, **Netlist / Test Mode**,
/// **Test Profile** (`ui/left_panel.py`), bound to [AppState].
library;

import 'package:flutter/material.dart';

import '../design/model.dart' show connName;
import 'client_controller.dart';
import 'client_dialogs.dart';
import 'client_netlist_editor.dart';
import 'netlist_doc.dart';
import 'client_theme.dart';
import 'client_widgets.dart';

class ClientLeftPanel extends StatelessWidget {
  final ClientController ctl;
  const ClientLeftPanel(this.ctl, {super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: Scrollbar(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          children: [
            _ConnectionCard(ctl),
            const SizedBox(height: 12),
            _NetlistCard(ctl),
            const SizedBox(height: 12),
            _HvNetlistCard(ctl),
            const SizedBox(height: 12),
            _ProfileCard(ctl),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connection
// ---------------------------------------------------------------------------

class _ConnectionCard extends StatefulWidget {
  final ClientController ctl;
  const _ConnectionCard(this.ctl);

  @override
  State<_ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends State<_ConnectionCard> {
  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final ctl = widget.ctl;
    final s = ctl.s;
    final linked = s.link;
    final ports = {
      for (final p in s.ports)
        p.name: p.description.isEmpty ? p.name : '${p.name} — ${p.description}',
    };
    const bauds = [9600, 115200, 921600];

    return GroupCard(
      title: 'Connection',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (s.serialLink) ...[
          Row(children: [
            SizedBox(
                width: 40,
                child: Text('Port:',
                    style: ctext(context, size: 12.5, color: c.muted))),
            Expanded(
              child: CDropdown<String>(
                value: s.selPort ?? '',
                items: ports,
                onChanged: linked || s.connecting ? null : s.choosePort,
              ),
            ),
            const SizedBox(width: 6),
            CButton('Refresh',
                role: CRole.ghost,
                compact: true,
                tooltip: 'Rescan available serial ports',
                onPressed: linked || s.connecting ? null : () => s.refreshPorts()),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(
                width: 40,
                child: Text('Baud:',
                    style: ctext(context, size: 12.5, color: c.muted))),
            Expanded(
              child: CDropdown<int>(
                value: bauds.contains(s.port) ? s.port : 115200,
                items: {for (final b in bauds) b: '$b'},
                onChanged: linked || s.connecting
                    ? null
                    : (v) {
                        s.port = v;
                        setState(() {});
                      },
              ),
            ),
          ]),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Link: ${s.host}:${s.port}',
                style: ctext(context, size: 12.5, color: c.muted)),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: CButton('● Connect',
                role: CRole.primary,
                onPressed: linked || s.connecting
                    ? null
                    : () {
                        if (s.serialLink && s.selPort != null) {
                          s.connectTo(s.selPort!);
                        } else {
                          s.connect();
                        }
                      }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CButton('○ Disconnect',
                role: CRole.ghost,
                onPressed: linked ? () => s.disconnect() : null),
          ),
        ]),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: s.connecting
              ? Pill('Connecting…', bg: c.amber, fg: const Color(0xFF1C1C1C))
              : linked
                  ? Pill(
                      'CONNECTED — FW v${s.fwVersion ?? '?'}',
                      bg: c.green,
                    )
                  : Pill('Not connected', bg: c.neutral),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Netlist / Test Mode
// ---------------------------------------------------------------------------

class _NetlistCard extends StatelessWidget {
  final ClientController ctl;
  const _NetlistCard(this.ctl);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final s = ctl.s;
    final busy = ctl.running;
    return GroupCard(
      title: 'Netlist / Test Mode',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: CRadio('Standard (file)',
                selected: !ctl.autoScan,
                onTap: busy ? null : () => ctl.setAutoScan(false)),
          ),
          Expanded(
            child: CRadio('Auto-Scan',
                selected: ctl.autoScan,
                onTap: busy ? null : () => ctl.setAutoScan(true)),
          ),
        ]),
        const HLine(),
        if (!ctl.autoScan) ...[
          if (s.nlHarnessId != null && s.nlHarnessId!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Harness ID: ${s.nlHarnessId}',
                  style: ctext(context,
                      size: 12, weight: FontWeight.w700, color: c.info)),
            ),
          Row(children: [
            CButton('Browse…',
                role: CRole.secondary,
                compact: true,
                tooltip: 'Load a netlist file (.xlsx, .xls or .csv)',
                onPressed: busy ? null : ctl.browseNetlist),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.nlMtx.loaded ? (s.nlMtx.name ?? '') : 'No netlist loaded',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ctext(context, size: 12.5),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _NetTree(ctl),
          const SizedBox(height: 8),
          Row(children: [
            CButton('Edit',
                role: CRole.ghost,
                compact: true,
                tooltip: 'Edit the loaded netlist',
                onPressed: busy
                    ? null
                    : () => openNetlistEditor(context, ctl, NetlistKind.mtx)),
            const SizedBox(width: 8),
            CButton('New',
                role: CRole.ghost,
                compact: true,
                tooltip: 'Create a continuity / resistance netlist',
                onPressed: busy
                    ? null
                    : () => openNetlistEditor(context, ctl, NetlistKind.mtx,
                        blank: true)),
            const SizedBox(width: 8),
            CButton('Clear',
                role: CRole.ghost,
                compact: true,
                tooltip: 'Unload the netlist',
                onPressed: busy
                    ? null
                    : () {
                        s.unloadNetlist('mtx');
                        ctl.showToast('Netlist cleared', kind: 'info');
                      }),
            const SizedBox(width: 8),
            CButton('Export',
                role: CRole.ghost,
                compact: true,
                tooltip: 'Export the loaded netlist as a CSV file',
                onPressed: busy || !s.nlMtx.loaded ? null : ctl.exportNetlist),
          ]),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(8),
            alignment: Alignment.center,
            child: Text(
              'Auto-Scan: probes every Side-A × Side-B pin pair,\n'
              'showing only the connections that are present.',
              textAlign: TextAlign.center,
              style: ctext(context, size: 12, color: c.info),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: CButton('Use as Netlist',
                  role: CRole.secondary,
                  tooltip:
                      'Load the connections found by the last Auto-Scan as the active netlist and switch to Standard mode',
                  onPressed: s.discoveredPairs.isEmpty || busy
                      ? null
                      : ctl.useAutoScanAsNetlist),
            ),
            const SizedBox(width: 8),
            CButton('Export',
                role: CRole.ghost,
                tooltip:
                    'Save the connections found by the last Auto-Scan as an .xlsx netlist in the Netlists folder',
                onPressed: s.discoveredPairs.isEmpty || busy
                    ? null
                    : () => ctl.exportAutoScanNetlist()),
          ]),
        ],
        const HLine(),
        Text('Connection Defaults',
            style: ctext(context, size: 11.5, color: c.dim)),
        const SizedBox(height: 6),
        LabelRow(
            'Connector',
            CField(
                value: ctl.connector,
                hint: 'e.g. X1',
                onChanged: (v) => ctl.setDefaults(connector: v))),
        LabelRow(
            'Source',
            CField(
                value: ctl.source,
                hint: 'e.g. Side A',
                onChanged: (v) => ctl.setDefaults(source: v))),
        LabelRow(
            'Destination',
            CField(
                value: ctl.destination,
                hint: 'e.g. Side B',
                onChanged: (v) => ctl.setDefaults(destination: v))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// HV Netlist (was on the Configuration tab)
// ---------------------------------------------------------------------------

/// The HV insulation netlist (HS pin = the HV card relay that injects, LS pin =
/// its return). Sent to the tester only for the insulation run.
class _HvNetlistCard extends StatelessWidget {
  final ClientController ctl;
  const _HvNetlistCard(this.ctl);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final s = ctl.s;
    final busy = ctl.running;
    return GroupCard(
      title: 'HV Netlist',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CButton('Browse…',
              role: CRole.secondary,
              compact: true,
              tooltip:
                  'Load the HV netlist (.xlsx, .xls or .csv with HS Pin and LS Pin columns)',
              onPressed: busy ? null : () => s.loadHvNetlistFromFile()),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.nlHv.loaded ? (s.nlHv.name ?? '') : 'No HV netlist loaded',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ctext(context, size: 12.5),
            ),
          ),
        ]),
        if (s.nlHv.loaded) ...[
          const SizedBox(height: 6),
          Text('${s.nlHv.nets} nets, ${s.nlHv.cards}-card map',
              style: ctext(context, size: 12, color: c.muted)),
        ],
        const SizedBox(height: 8),
        Row(children: [
          CButton('Edit',
              role: CRole.ghost,
              compact: true,
              tooltip: 'Edit the loaded HV netlist',
              onPressed: busy
                  ? null
                  : () => openNetlistEditor(context, ctl, NetlistKind.hv)),
          const SizedBox(width: 8),
          CButton('New',
              role: CRole.ghost,
              compact: true,
              tooltip: 'Create an HV insulation netlist',
              onPressed: busy
                  ? null
                  : () => openNetlistEditor(context, ctl, NetlistKind.hv,
                      blank: true)),
          const SizedBox(width: 8),
          CButton('Clear',
              role: CRole.ghost,
              compact: true,
              tooltip: 'Unload the HV netlist',
              onPressed: !s.nlHv.loaded || busy
                  ? null
                  : () {
                      s.unloadNetlist('hv');
                      ctl.showToast('HV netlist cleared', kind: 'info');
                    }),
          const SizedBox(width: 8),
          CButton('Export',
              role: CRole.ghost,
              compact: true,
              tooltip: 'Save the HV netlist as .xlsx, .xls or .csv',
              onPressed: !s.nlHv.loaded || busy
                  ? null
                  : () => ctl.exportNetlist(kind: NetlistKind.hv)),
        ]),
      ]),
    );
  }
}

/// `QTreeWidget` of nets and pins.
class _NetTree extends StatelessWidget {
  final ClientController ctl;
  const _NetTree(this.ctl);

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final nets = ctl.s.nets;
    return Container(
      height: 132,
      decoration: BoxDecoration(
        color: c.input,
        border: Border.all(color: c.inputBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: nets.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(10),
              child: Text('(No netlist loaded)',
                  style: ctext(context, size: 12.5, color: c.dim)),
            )
          : Scrollbar(
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  for (final n in nets) ...[
                    Text(
                      'NET: ${n.name}'
                      '${n.pairs.isNotEmpty ? '  [${connName(n.pairs.first.src.c)}]' : ''}'
                      '  (${n.pairs.isEmpty ? 2 : n.pairs.length * 2} pins)',
                      style: ctext(context, size: 12, weight: FontWeight.w600),
                    ),
                    for (final p in n.pairs) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Text(
                          'Pin ${p.hi}${p.srcLabel == null ? '' : '  ${p.srcLabel}'}',
                          style: ctext(context, size: 11.5, color: c.muted),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Text(
                          'Pin ${p.lo}${p.dstLabel == null ? '' : '  ${p.dstLabel}'}',
                          style: ctext(context, size: 11.5, color: c.muted),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Test Profile
// ---------------------------------------------------------------------------

class _ProfileCard extends StatelessWidget {
  final ClientController ctl;
  const _ProfileCard(this.ctl);

  @override
  Widget build(BuildContext context) {
    final s = ctl.s;
    return GroupCard(
      title: 'Test Profile',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LabelRow(
          'Profile',
          CDropdown<String>(
            value: ctl.profile,
            items: {
              for (final p in ctl.profiles)
                p: p == ctl.profile && ctl.profileDirty ? '$p *' : p,
            },
            onChanged: ctl.running ? null : ctl.selectProfile,
          ),
          labelWidth: 70,
        ),
        LabelRow(
            'Operator',
            CField(
                value: s.operatorName,
                hint: 'Operator name',
                onChanged: ctl.setOperator),
            labelWidth: 70),
        LabelRow(
            'Harness ID',
            CField(
                value: ctl.harnessId,
                hint: 'e.g. HRN-2024-001',
                onChanged: ctl.setHarnessId),
            labelWidth: 70),
        LabelRow(
            'DUT ID',
            CField(
                value: s.dutId,
                hint: 'HT-0001',
                onChanged: ctl.setDutId),
            labelWidth: 70),
        const SizedBox(height: 4),
        Row(children: [
          CButton('Save',
              role: CRole.ghost, compact: true, onPressed: ctl.saveProfile),
          const SizedBox(width: 8),
          CButton('New',
              role: CRole.ghost,
              compact: true,
              onPressed: () async {
                final name = await promptText(context,
                    title: 'New profile', label: 'Profile name');
                if (name == null) return;
                if (!ctl.newProfile(name)) {
                  ctl.showToast('That name is empty or already used',
                      kind: 'warning');
                }
              }),
          const SizedBox(width: 8),
          CButton('Delete',
              role: CRole.ghost,
              compact: true,
              onPressed: ctl.profile == 'Default' ? null : ctl.deleteProfile),
        ]),
      ]),
    );
  }
}
