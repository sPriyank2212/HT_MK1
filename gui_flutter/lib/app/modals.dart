/// The two modals that gate every HV start.
///
///   1. select the HV netlist — only when one is not already loaded
///   2. verify this is the harness that passed on J-MTX — always
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/model.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import 'app_state.dart';

/// `.modal{position:fixed;inset:0;z-index:60;padding:22px;
///         background:var(--scrim)}`
class ModalScrim extends StatelessWidget {
  final Widget child;
  final VoidCallback onDismiss;

  const ModalScrim({super.key, required this.child, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(
      children: [
        // .modal click on the backdrop closes it
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            child: ColoredBox(color: c.scrim),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              // .mbox{width:100%;max-width:580px;max-height:92dvh}
              constraints: BoxConstraints(
                maxWidth: 580,
                maxHeight: MediaQuery.sizeOf(context).height * .92,
              ),
              // Swallow taps inside the box so they do not dismiss it.
              child: GestureDetector(onTap: () {}, child: child),
            ),
          ),
        ),
      ],
    );
  }
}

/// `.mbox`
class MBox extends StatelessWidget {
  final HtIconData icon;
  final bool hot;
  final String title;
  final Widget subtitle;
  final List<Widget> body;
  final List<Widget> footer;

  const MBox({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.footer,
    this.hot = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(10),
        boxShadow: c.modalShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // .mbox > header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.lineSoft)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // .mbox .mi{width:38px;height:38px;border-radius:8px}
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: hot ? c.hvSoft : c.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: HtIcon(icon,
                      size: 20,
                      color: hot ? c.hv : c.accent,
                      strokeWidth: 1.7),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.modalH2),
                      const SizedBox(height: 3),
                      subtitle,
                    ],
                  ),
                ),
              ],
            ),
          ),
          // .mbox .mbody
          Flexible(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              child: Cols(body),
            ),
          ),
          // .mbox > footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            decoration: BoxDecoration(
              color: c.sunk,
              border: Border(top: BorderSide(color: c.lineSoft)),
            ),
            child: RowWrap.gapped(
              10,
              footer,
              alignment: WrapAlignment.end,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MODAL 1 · HV netlist required
// ---------------------------------------------------------------------------

class HvNetlistModal extends StatelessWidget {
  final AppState s;
  const HvNetlistModal({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final files = hvFilesFor(s.netc);

    return ModalScrim(
      onDismiss: s.cancelModals,
      child: MBox(
        icon: HtIcons.doc,
        title: 'Select the HV netlist',
        subtitle: Text.rich(
          TextSpan(
            style: t.modalP,
            children: [
              const TextSpan(
                  text: 'HV uses its own netlist because the relay map depends '
                      'on how many HV cards are stacked. The instrument reports a '),
              TextSpan(
                  text: '${s.stack}-card',
                  style: t.modalP.copyWith(fontWeight: FontWeight.w600)),
              const TextSpan(text: ' stack on I2C2.'),
            ],
          ),
        ),
        body: [
          // .filelist
          Container(
            decoration: BoxDecoration(
              color: c.lineSoft,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(kRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < files.length; i++) ...[
                  if (i > 0) const SizedBox(height: 1),
                  _FileRow(file: files[i], stack: s.stack, s: s),
                ],
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Btn('Browse the file system…',
                onTap: () => unawaited(s.browseHvNetlist())),
          ),
          Text(
            'Reads the same Excel (.xlsx) netlist format as the MTX side — a '
            'header row with HI/HS and LO/LS pin columns, plus an optional '
            'CARDS column declaring the stack size (defaults to the fitted '
            'stack if left out). Only the row count and CARDS matter here — '
            'the HV card/relay map itself still comes from the fitted stack, '
            'not from the file.',
            style: t.mono(size: 11.5, color: c.ink3, height: 1.55),
          ),
          Text(
            'The HV netlist maps each net to a card and HS relay, and declares '
            'which LS relays form its return. Without it the test cannot build '
            'the return pattern — and a wrong pattern reads as a pass.',
            style: t.mono(size: 11.5, color: c.ink3, height: 1.55),
          ),
        ],
        footer: [Btn('Cancel', onTap: s.cancelModals)],
      ),
    );
  }
}

/// `.filerow`
class _FileRow extends StatelessWidget {
  final HvFile file;
  final int stack;
  final AppState s;
  const _FileRow({required this.file, required this.stack, required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final ok = file.cards == stack;

    return HoverRow(
      onTap: () => s.pickHvFile(file),
      base: c.panel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.hvSoft,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: HtIcon(HtIcons.doc,
                    size: 14, color: c.hv, strokeWidth: 1.7),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(file.name, style: t.fileName),
                    const SizedBox(height: 2),
                    Text(file.note, style: t.fileDetail),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            Tag(ok ? TagVariant.ok : TagVariant.warn,
                ok ? 'matches stack' : '${file.cards}-card ≠ $stack'),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MODAL · select the MTX netlist
// ---------------------------------------------------------------------------

/// The MTX netbar's Select…/Change…. Two ways to give the instrument an MTX
/// netlist: browse a real Excel file ([AppState.browseMtxNetlist]), or build
/// one from the harness itself with cross-continuity + "Save as MTX
/// netlist" (`confirmGoToBuildMtxNetlist` routes there). Used to jump
/// straight to cross mode with only a log-panel line (collapsed by default)
/// explaining why — from the operator's side that read as "I clicked
/// Select… and nothing happened." This says so up front instead.
class MtxNetlistModal extends StatelessWidget {
  final AppState s;
  const MtxNetlistModal({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return ModalScrim(
      onDismiss: s.closeMtxNlExplainer,
      child: MBox(
        icon: HtIcons.doc,
        hot: false,
        title: 'Select the MTX netlist',
        subtitle: Text(
          'Load it from a netlist file, or build one from the harness '
          'itself with cross continuity.',
          style: t.modalP,
        ),
        body: [
          Align(
            alignment: Alignment.centerLeft,
            child: Btn('Browse for a netlist file (.xlsx)…',
                variant: BtnVariant.primary,
                onTap: () => unawaited(s.browseMtxNetlist())),
          ),
          Text(
            'Expects a header row with a HI/HS pin column and a LO/LS pin '
            'column (a NET name column is optional) — pins are the '
            "instrument's own 1..256 numbering, the same pairs NETLIST ADD "
            'takes on the wire. Uploaded immediately on pick — CONT RUN '
            'verify and RES RUN both need this before either will run.',
            style: t.mono(size: 11.5, color: c.ink3, height: 1.55),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 2),
            color: c.lineSoft,
          ),
          Text(
            'No file yet? Run cross continuity to scan every HS pin against '
            'every LS pin, then Save as MTX netlist once it finds something.',
            style: t.mono(size: 11.5, color: c.ink3, height: 1.55),
          ),
        ],
        footer: [
          Btn('Cancel', onTap: s.closeMtxNlExplainer),
          Btn('Take me there', onTap: s.confirmGoToBuildMtxNetlist),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MODAL 2 · pre-HV verification
// ---------------------------------------------------------------------------

class VerifyModal extends StatelessWidget {
  final AppState s;
  const VerifyModal({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final t = context.type;

    return ModalScrim(
      onDismiss: s.cancelModals,
      child: MBox(
        icon: HtIcons.warning,
        title: 'Confirm before energizing to 500 V',
        subtitle: Text(
          'The HV test drives 500 V through the harness on J-HV. Check that '
          'this is the same harness that passed on J-MTX before continuing.',
          style: t.modalP,
        ),
        body: [
          Cols.gapped(
            8,
            [for (final row in s.verifyChecks) _Check(row: row)],
          ),
          _AckBox(s: s),
        ],
        footer: [
          Btn('Cancel', onTap: s.cancelModals),
          Btn(
            'Energize 500 V',
            variant: BtnVariant.hv,
            big: true,
            disabled: !s.ackChecked,
            onTap: s.ackChecked ? s.confirmEnergize : null,
          ),
        ],
      ),
    );
  }
}

/// `.check`
class _Check extends StatelessWidget {
  final ({String state, String title, String detail, String value}) row;
  const _Check({required this.row});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final (fg, bg, glyph) = switch (row.state) {
      'ok' => (c.pass, c.passSoft, '✓'),
      'warn' => (c.warn, c.warnSoft, '!'),
      _ => (c.fail, c.failSoft, '✕'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: c.sunk,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Text(glyph, style: t.checkIcon(fg)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.title, style: t.checkTitle),
                const SizedBox(height: 2),
                Text(row.detail, style: t.checkDetail),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(row.value, style: t.checkValue(fg)),
        ],
      ),
    );
  }
}

/// `.ack{border:2px solid var(--hv);background:var(--hv-soft);cursor:pointer}`
class _AckBox extends StatelessWidget {
  final AppState s;
  const _AckBox({required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => s.setAck(!s.ackChecked),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.hvSoft,
            border: Border.all(color: c.hv, width: 2),
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // .ack input{width:19px;height:19px;accent-color:var(--hv)}
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Container(
                  width: 19,
                  height: 19,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: s.ackChecked ? c.hv : c.panel,
                    border: Border.all(color: c.hv, width: 2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: s.ackChecked
                      ? Text('✓',
                          style: t.mono(
                              size: 12,
                              weight: FontWeight.w700,
                              color: c.panel))
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: t.ackText,
                    children: [
                      TextSpan(
                          text: 'I confirm',
                          style: t.ackText
                              .copyWith(fontWeight: FontWeight.w600)),
                      const TextSpan(
                          text: ' that the harness now on J-HV is the same unit '
                              'that passed continuity and resistance on J-MTX, '
                              'that its serial matches, and that the fixture is '
                              'clear of hands and tools.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MODAL · confirm a netlist-guessed connector layout (GUI-11)
// ---------------------------------------------------------------------------

/// Shown right after [AppState.browseMtxNetlist] applies a connector layout
/// guessed from the netlist file's `Conn ID`/`Part Number` columns
/// (`GuessedConnector`, `htproto/netlist_file.dart`) — lets the operator fix
/// a wrong shape guess, or give a connector a friendlier name, before
/// relying on it for the wiring diagram and the connection-results tables.
/// Pin count/id/order are not editable here — they come from the netlist
/// itself, not from operator guesswork (a short count usually means the
/// connector's trailing pins were never wired in this particular netlist,
/// not that the guess picked the wrong number).
class FixtureGuessModal extends StatefulWidget {
  final AppState s;
  const FixtureGuessModal({super.key, required this.s});

  @override
  State<FixtureGuessModal> createState() => _FixtureGuessModalState();
}

class _FixtureGuessModalState extends State<FixtureGuessModal> {
  // kFix.connectors is exactly the applied guess at the moment this modal
  // opens (AppState.browseMtxNetlist applies it before showing this) —
  // edits stay local until Apply.
  late final List<ConnType> _types = [
    for (final c in kFix.connectors) c.type,
  ];
  late final List<String> _labels = [
    for (final c in kFix.connectors) c.label,
  ];

  static const _shapeOptions = ['D-sub', 'Circular', 'Rect'];
  static const _shapeValues = [ConnType.dsub, ConnType.circ, ConnType.rect];

  void _confirm() {
    final edited = <ConnectorDef>[];
    for (var i = 0; i < kFix.connectors.length; i++) {
      final c = kFix.connectors[i];
      final label = _labels[i].trim();
      edited.add(ConnectorDef(
        id: c.id,
        label: label.isEmpty ? c.id : label,
        type: _types[i],
        pins: c.pins,
        side: c.side,
        base: c.base,
      ));
    }
    widget.s.confirmFixtureGuess(edited);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final connectors = kFix.connectors;

    return ModalScrim(
      onDismiss: widget.s.cancelFixtureGuess,
      child: MBox(
        icon: HtIcons.doc,
        hot: false,
        title: 'Confirm the connector layout',
        subtitle: Text(
          'Guessed from the netlist file\'s Conn ID / Part Number columns. '
          'Pin counts come from the file itself — fix the shape or name '
          'before relying on it in the wiring diagram and result tables.',
          style: t.modalP,
        ),
        body: [
          for (var i = 0; i < connectors.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 62,
                    child: Text('${connectors[i].id} · ${connectors[i].pins}p',
                        style: t.mono(size: 12, color: c.ink)),
                  ),
                  const SizedBox(width: 8),
                  Seg(
                    options: _shapeOptions,
                    selected: _shapeValues.indexOf(_types[i]),
                    onSelect: (v) =>
                        setState(() => _types[i] = _shapeValues[v]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextInput(
                      value: _labels[i],
                      onChanged: (v) => _labels[i] = v,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'A connector with fewer pins than expected usually means its '
            'trailing pins were never wired in this file, not a wrong guess '
            '— that is expected, not an error to fix here.',
            style: t.mono(size: 11.5, color: c.ink3, height: 1.55),
          ),
        ],
        footer: [
          Btn('Cancel', onTap: widget.s.cancelFixtureGuess),
          Btn('Apply', variant: BtnVariant.primary, onTap: _confirm),
        ],
      ),
    );
  }
}
