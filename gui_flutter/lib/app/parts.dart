/// Composite pieces of the design that more than one view uses, plus the two
/// modals and the HV lock overlay.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/model.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import 'app_state.dart';

// ---------------------------------------------------------------------------
// netlist strips — two independent files
// ---------------------------------------------------------------------------

/// `.netbar` — `renderNetbars()`'s `mk()` for the MTX and HV files, and the
/// separate fixture-file strip.
class Netbar extends StatelessWidget {
  final AppState s;

  /// "mtx" | "hv" | "fix"
  final String dom;

  /// key into `USES`
  final String useKey;

  const Netbar({
    super.key,
    required this.s,
    required this.dom,
    required this.useKey,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    final bool loaded;
    final String kind;
    final String fname;
    final String meta;
    final String uses;
    if (dom == 'fix') {
      loaded = s.nlFix.loaded;
      kind = 'Fixture file · connectors';
      fname = loaded ? s.nlFix.name : 'No fixture file loaded';
      meta = loaded
          ? '${s.nlFix.conns} connectors · ${s.nlFix.pins} pins · rev ${kFix.rev}'
          : 'the wiring diagram cannot be drawn without it';
      uses = loaded
          ? 'connector faces, pin layout and pin → board mapping'
          : '';
    } else if (dom == 'mtx') {
      final f = s.nlMtx;
      loaded = f.loaded;
      kind = 'MTX netlist · J-MTX';
      fname = loaded ? f.name! : 'No MTX netlist loaded';
      meta = loaded
          ? '${f.nets} nets · ${f.pins} pins · loaded ${f.time}'
              '${f.origin == "cross" ? " · built by cross scan" : ""}'
          : 'required for ${kUses[useKey]}';
      uses = loaded
          ? kUses[useKey]!
          : 'cross continuity can run without one and build it for you';
    } else {
      final f = s.nlHv;
      loaded = f.loaded;
      kind = 'HV netlist · ${s.hvConnName()}';
      fname = loaded ? f.name! : 'No HV netlist loaded';
      meta = loaded
          ? '${f.nets} nets · ${f.cards}-card map · loaded ${f.time}'
          : 'required for ${kUses[useKey]}';
      uses = loaded
          ? kUses[useKey]!
          : 'asked for automatically when you start the HV test';
    }

    final isHv = dom == 'hv';
    final empty = !loaded;

    // .netbar[data-dom="hv"] .doc / .kind
    final docBg = empty
        ? c.warnSoft
        : isHv
            ? c.hvSoft
            : c.accentSoft;
    final docFg = empty
        ? c.warn
        : isHv
            ? c.hv
            : c.accent;
    final kindColor = isHv && !empty ? c.hv : c.accent;
    final nameColor = empty ? c.warn : c.ink;

    final showMismatch = isHv && loaded && !s.stackMatch();

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: RowWrap.gapped(
        13,
        [
          // .netbar .doc{width:32px;height:32px;border-radius:var(--r)}
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: docBg,
              borderRadius: BorderRadius.circular(kRadius),
            ),
            child: HtIcon(HtIcons.doc,
                size: 17, color: docFg, strokeWidth: 1.6),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(kind.toUpperCase(), style: t.netbarKind(kindColor)),
              const SizedBox(height: 2),
              Text(fname, style: t.netbarName(nameColor)),
              const SizedBox(height: 2),
              Text(meta, style: t.netbarMeta),
            ],
          ),
          if (showMismatch) const Pill(PillVariant.warn, 'stack mismatch'),
          if (uses.isNotEmpty)
            // .netbar .uses{border-left:1px solid var(--line-soft);
            //               padding-left:13px;max-width:240px}
            Container(
              constraints: const BoxConstraints(maxWidth: 240),
              padding: const EdgeInsets.only(left: 13),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: c.lineSoft)),
              ),
              child: Text(uses, style: t.netbarUses),
            ),
          const FlexSpacer(),
          if (loaded) ...[
            Btn('Change…', onTap: () {}),
            if (dom != 'fix')
              Btn('Unload', onTap: () => s.unloadNetlist(dom)),
          ] else
            Btn('Select…',
                variant: BtnVariant.primary,
                onTap: dom == 'hv' ? s.openNlPicker : () {}),
        ],
      ),
    );

    final decoration = BoxDecoration(
      color: empty ? null : c.panel,
      border: Border.all(color: empty ? c.warn : c.line),
      borderRadius: BorderRadius.circular(kPanelRadius),
      boxShadow: c.shadow,
    );

    return Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: empty
          ? Striped(
              stripe: c.warnSoft, base: c.panel, band: 14, child: content)
          : content,
    );
  }
}

// ---------------------------------------------------------------------------
// verdict + act button
// ---------------------------------------------------------------------------

/// `.verdict` and `.act`
class Verdict extends StatelessWidget {
  final AppState s;
  const Verdict({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    // body[data-phase] colours the 4px rule and the headline.
    final phaseColor = switch (s.phase) {
      'running' => c.accent,
      'hold' => c.warn,
      'armed' => c.hv,
      'pass' => c.pass,
      'fail' => c.fail,
      _ => c.idle,
    };
    final titleColor = switch (s.phase) {
      'running' => c.accent,
      'hold' => c.warn,
      'armed' => c.hv,
      'pass' => c.pass,
      'fail' => c.fail,
      _ => c.ink2,
    };

    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(kPanelRadius),
        boxShadow: c.shadow,
      ),
      clipBehavior: Clip.antiAlias,
      // `.verdict::before{position:absolute;inset:0 auto 0 0;width:4px}` — a
      // Stack with a stretched Positioned is the literal translation, and it
      // lets the text column decide the height.
      //
      // This was an IntrinsicHeight + stretched Container. Row's intrinsic
      // height with a flex child does not agree with its own layout pass, so
      // it resolved to the 122px act button and clipped the headline block by
      // 15px. The rule only ever needed to be painted over the box, not to be
      // a flex sibling that forces a common height.
      child: Stack(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.vTitle, style: t.verdictH1(titleColor)),
                      const SizedBox(height: 7),
                      // .verdict .sub{max-width:62ch}
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Text(s.vSub, style: t.verdictSub),
                      ),
                      const SizedBox(height: 14),
                      RowWrap.gapped(
                        22,
                        [
                          _Meta('Elapsed', s.vElapsed),
                          _Meta('Running', s.vStage),
                          _Meta('Faults', s.vFaults),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                _ActButton(s: s),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: ColoredBox(color: phaseColor),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final String label;
  final String value;
  const _Meta(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Lbl(label),
          const SizedBox(height: 4),
          Text(value, style: context.type.verdictMeta),
        ],
      );
}

/// `.act{width:122px;height:122px;border-radius:50%;border:2px solid}`
class _ActButton extends StatefulWidget {
  final AppState s;
  const _ActButton({required this.s});
  @override
  State<_ActButton> createState() => _ActButtonState();
}

class _ActButtonState extends State<_ActButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final spec = widget.s.actButton;

    Color border, fg, bg;
    if (spec.disabled) {
      border = c.line;
      fg = c.ink3;
      bg = c.sunk;
    } else {
      switch (spec.style) {
        case 'stop':
          border = c.fail;
          fg = _hover ? c.panel : c.fail;
          bg = _hover ? c.fail : c.failSoft;
          break;
        case 'hv':
          border = c.hv;
          fg = _hover ? c.panel : c.hv;
          bg = _hover ? c.hv : c.hvSoft;
          break;
        default:
          border = c.accent;
          fg = _hover ? c.accentInk : c.accent;
          bg = _hover ? c.accent : c.accentSoft;
      }
    }

    return MouseRegion(
      cursor: spec.disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: spec.disabled ? null : (_) => setState(() => _down = true),
        onTapUp: spec.disabled ? null : (_) => setState(() => _down = false),
        onTapCancel:
            spec.disabled ? null : () => setState(() => _down = false),
        onTap: spec.disabled ? null : widget.s.actButtonPressed,
        child: Opacity(
          // .act[disabled]{opacity:.4}
          opacity: spec.disabled ? .4 : 1,
          child: Transform.scale(
            // .act:active{transform:scale(.97)}
            scale: _down ? .97 : 1,
            child: Container(
              width: 122,
              height: 122,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: border, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(spec.label.toUpperCase(), style: t.act(fg)),
                  const SizedBox(height: 5),
                  Text(spec.hint.toUpperCase(), style: t.actSmall(fg)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// fixture sequence
// ---------------------------------------------------------------------------

/// `.flow`, `.stagebox`, `.gate`
class FixtureFlow extends StatelessWidget {
  final AppState s;
  const FixtureFlow({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    // @media (max-width:1080px){.flow{grid-template-columns:1fr}
    //                           .gate{flex-direction:row;padding:8px 0}}
    final narrow = MediaQuery.sizeOf(context).width <= kMediumBreak;

    final box1 = _StageBox(
      number: '1',
      state: s.sb1S,
      conn: const Conn('J-MTX'),
      pill: s.sb1Pill,
      tests: 'Matrix Card rev 6 · 256 HS + 256 LS · CD4067\n'
          'Continuity → Resistance · one shared netlist',
    );
    final gate = _Gate(armed: s.gateArmed, horizontal: narrow);
    final box2 = _StageBox(
      number: '2',
      state: s.sb2S,
      conn: const Conn('J-HV', hv: true),
      pill: s.sb2Pill,
      tests: 'HV Card rev 1 · ${s.stack}-card stack · MHV05\n'
          'Insulation at 500 V · its own netlist',
    );

    return HtPanel(
      header: [
        const PanelTitle('Fixture sequence'),
        const FlexSpacer(),
        const Lbl('one connector at a time · DUT is moved between stages'),
      ],
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: narrow
            ? Column(children: [box1, gate, box2])
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: box1),
                    SizedBox(width: 46, child: gate),
                    Expanded(child: box2),
                  ],
                ),
              ),
      ),
    );
  }
}

const double kMediumBreak = 1080;

class _StageBox extends StatelessWidget {
  final String number;
  final String state;
  final Widget conn;
  final PillState pill;
  final String tests;

  const _StageBox({
    required this.number,
    required this.state,
    required this.conn,
    required this.pill,
    required this.tests,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    final borderColor = switch (state) {
      'active' => c.accent,
      'pass' => c.pass,
      'fail' => c.fail,
      _ => c.line,
    };
    final noColor = switch (state) {
      'active' => c.accent,
      'pass' => c.pass,
      'fail' => c.fail,
      _ => c.ink3,
    };

    return Opacity(
      // .stagebox[data-s="lock"]{opacity:.5;border-style:dashed}
      opacity: state == 'lock' ? .5 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.panel,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(kRadius),
          boxShadow: state == 'active'
              // box-shadow:0 0 0 3px var(--accent-soft)
              ? [BoxShadow(color: c.accentSoft, spreadRadius: 3, blurRadius: 0)]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RowWrap.gapped(
              9,
              [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: noColor, width: 1.5),
                  ),
                  child: Text(number, style: t.stageNo(noColor)),
                ),
                conn,
                const FlexSpacer(),
                Pill(pill.variant, pill.text),
              ],
            ),
            const SizedBox(height: 9),
            Text(tests, style: t.stageTests),
          ],
        ),
      ),
    );
  }
}

/// `.gate` — the "operator moves DUT" arrow between the two stage boxes.
class _Gate extends StatelessWidget {
  final bool armed;
  final bool horizontal;
  const _Gate({required this.armed, required this.horizontal});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // .gate.armed{color:var(--warn)}
    final colour = armed ? c.warn : c.ink3;
    final children = <Widget>[
      HtIcon(HtIcons.transfer, size: 20, color: colour, strokeWidth: 1.6),
      const SizedBox(width: 5, height: 5),
      Text('OPERATOR\nMOVES DUT',
          style: context.type.gate(colour), textAlign: TextAlign.center),
    ];
    return Padding(
      padding: horizontal
          ? const EdgeInsets.symmetric(vertical: 8)
          : EdgeInsets.zero,
      child: horizontal
          ? Row(mainAxisAlignment: MainAxisAlignment.center, children: children)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center, children: children),
    );
  }
}

/// `.handover` — shown only while `body[data-phase="hold"]`.
class Handover extends StatelessWidget {
  final AppState s;
  const Handover({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.warn, width: 2),
        borderRadius: BorderRadius.circular(kPanelRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Striped(
        stripe: c.warnSoft,
        base: c.panel,
        band: 14,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: RowWrap.gapped(
            18,
            [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.warn, width: 2),
                ),
                child: HtIcon(HtIcons.transfer,
                    size: 22, color: c.warn, strokeWidth: 1.7),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Move the harness to the HV fixture',
                      style: t.handoverH2),
                  const SizedBox(height: 3),
                  Text(s.hoText, style: t.handoverP),
                ],
              ),
              const FlexSpacer(),
              _HandoverGo(onTap: s.confirmHandover),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.handover .go{background:var(--warn);color:var(--panel);
///                padding:11px 18px;font-size:12px}`
class _HandoverGo extends StatefulWidget {
  final VoidCallback onTap;
  const _HandoverGo({required this.onTap});
  @override
  State<_HandoverGo> createState() => _HandoverGoState();
}

class _HandoverGoState extends State<_HandoverGo> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Opacity(
          opacity: _hover ? .88 : 1,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: c.warn,
              border: Border.all(color: c.warn),
              borderRadius: BorderRadius.circular(kRadius),
            ),
            child: Text('HARNESS MOVED — UNLOCK HV',
                style: context.type.btnBig(c.panel)),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// domain card
// ---------------------------------------------------------------------------

/// `.domain`
class DomainCard extends StatelessWidget {
  final AppState s;
  final HtIconData icon;
  final String title;
  final String stage;

  /// "idle" | "run" | "pass" | "fail" | "lock"
  final String state;
  final String cond;
  final String stat;
  final String unit;
  final double bar;
  final String runKey;
  final String runLabel;
  final BtnVariant runVariant;
  final String goView;

  const DomainCard({
    super.key,
    required this.s,
    required this.icon,
    required this.title,
    required this.stage,
    required this.state,
    required this.cond,
    required this.stat,
    required this.unit,
    required this.bar,
    required this.runKey,
    required this.runLabel,
    required this.runVariant,
    required this.goView,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    final statColor = switch (state) {
      'pass' => c.pass,
      'fail' => c.fail,
      'run' => c.accent,
      _ => c.ink,
    };
    final barColor = switch (state) {
      'pass' => c.pass,
      'fail' => c.fail,
      _ => c.accent,
    };

    final (canRun, why) = s.can(runKey);

    return Opacity(
      // .domain[data-s="lock"]{opacity:.6}
      opacity: state == 'lock' ? .6 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: c.panel,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(kPanelRadius),
          boxShadow: c.shadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // .domain .dh
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.lineSoft)),
              ),
              child: Row(
                children: [
                  HtIcon(icon, size: 18, color: c.ink3, strokeWidth: 1.6),
                  const SizedBox(width: 9),
                  // Flexible: "HV insulation" plus the stage badge exceeds a
                  // 250px-minimum domain card, and the title should give way
                  // rather than overflow.
                  Flexible(
                    child: Text(
                      title,
                      style: t.domainH4,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const FlexSpacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: c.line),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(stage.toUpperCase(), style: t.domainStg),
                  ),
                ],
              ),
            ),
            // .domain .db
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(cond, style: t.domainCond),
                  const SizedBox(height: 9),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(stat, style: t.domainStat(statColor)),
                      const SizedBox(width: 8),
                      Flexible(
                          child: Text(unit, style: t.domainStatUnit)),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Bar(bar, color: barColor),
                ],
              ),
            ),
            // .domain .df
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.sunk,
                border: Border(top: BorderSide(color: c.lineSoft)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Btn(
                      runLabel,
                      variant: runVariant,
                      expand: true,
                      disabled: !canRun,
                      onTap: canRun ? () => s.runTest(runKey) : null,
                    ),
                  ),
                  const SizedBox(width: 9),
                  _OpenLink(onTap: () => s.go(goView)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.domain .open`
class _OpenLink extends StatefulWidget {
  final VoidCallback onTap;
  const _OpenLink({required this.onTap});
  @override
  State<_OpenLink> createState() => _OpenLinkState();
}

class _OpenLinkState extends State<_OpenLink> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Text('OPEN',
              style: context.type.domainOpen(_hover ? c.accent : c.ink3)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// view bar
// ---------------------------------------------------------------------------

/// `.viewbar`
class ViewBar extends StatelessWidget {
  final List<Widget> children;
  const ViewBar(this.children, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(kPanelRadius),
        boxShadow: c.shadow,
      ),
      child: RowWrap.gapped(12, children),
    );
  }
}

/// `.stgbadge`
class StageBadge extends StatelessWidget {
  final String text;
  final bool hv;
  const StageBadge(this.text, {super.key, this.hv = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: hv ? c.hvSoft : c.accentSoft,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text.toUpperCase(),
          style: context.type.stgBadge(hv ? c.hv : c.accent)),
    );
  }
}

// ---------------------------------------------------------------------------
// tally
// ---------------------------------------------------------------------------

class TallyItem {
  final String label;
  final String value;

  /// null | "ok" | "bad" | "acc"
  final String? tone;
  const TallyItem(this.label, this.value, [this.tone]);
}

/// `.tally{display:grid;grid-template-columns:repeat(4,1fr);gap:1px;
///         background:var(--line-soft)}`
class Tally extends StatelessWidget {
  final List<TallyItem> items;
  const Tally(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final narrow = MediaQuery.sizeOf(context).width <= kMediumBreak;
    final perRow = narrow ? 2 : 4;

    Color tone(String? s) => switch (s) {
          'ok' => c.pass,
          'bad' => c.fail,
          'acc' => c.accent,
          _ => c.ink,
        };

    final rows = <List<TallyItem>>[];
    for (var i = 0; i < items.length; i += perRow) {
      rows.add(items.sublist(
          i, (i + perRow) > items.length ? items.length : i + perRow));
    }

    return ColoredBox(
      color: c.lineSoft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) const SizedBox(height: 1),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows[r].length; i++) ...[
                    if (i > 0) const SizedBox(width: 1),
                    Expanded(
                      child: Container(
                        color: c.panel,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Lbl(rows[r][i].label),
                            const SizedBox(height: 6),
                            Text(rows[r][i].value,
                                style: t.tally(tone(rows[r][i].tone))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// legend
// ---------------------------------------------------------------------------

class LegendItem {
  final Color color;
  final String label;
  final bool line;
  final bool round;
  const LegendItem(this.color, this.label,
      {this.line = false, this.round = false});
}

/// `.legend{gap:14px;padding:11px 14px;border-top:1px solid var(--line-soft)}`
class Legend extends StatelessWidget {
  final List<LegendItem> items;
  final String? trailing;
  final bool topBorder;

  const Legend(this.items,
      {super.key, this.trailing, this.topBorder = true});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        border: topBorder
            ? Border(top: BorderSide(color: c.lineSoft))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: RowWrap.gapped(
              14,
              [
                for (final it in items)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // .legend i{width:9px;height:9px;border-radius:2px} with
                      // per-item overrides for the line and dot swatches.
                      // BoxDecoration rejects shape:circle together with a
                      // borderRadius, so only one of the two is ever set.
                      Container(
                        width: it.line ? 16 : 9,
                        height: it.line ? 3 : 9,
                        decoration: it.round
                            ? BoxDecoration(
                                color: it.color, shape: BoxShape.circle)
                            : BoxDecoration(
                                color: it.color,
                                borderRadius: BorderRadius.circular(2),
                              ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          it.label,
                          style: context.type.legend,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (trailing != null)
            Text(trailing!,
                style: context.type.legend.copyWith(color: c.ink3)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HV lock overlay
// ---------------------------------------------------------------------------

/// `.lockover` / `.lockcard` — shown while `body[data-stage2="lock"]`, with
/// the content behind it blurred and inert.
class LockOverlay extends StatelessWidget {
  final Widget child;
  final bool locked;
  final String text;

  const LockOverlay({
    super.key,
    required this.child,
    required this.locked,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    if (!locked) return child;

    return Stack(
      children: [
        // body[data-stage2="lock"] .lockwrap > .cols{filter:blur(2px);
        //   pointer-events:none;user-select:none}
        IgnorePointer(
          child: ImageFiltered(
            imageFilter: cssBlur(2),
            child: child,
          ),
        ),
        Positioned.fill(
          child: ColoredBox(
            // background:color-mix(in srgb,var(--bg) 88%,transparent)
            // ignore: deprecated_member_use
            color: c.bg.withOpacity(.88),
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(20),
                constraints: const BoxConstraints(maxWidth: 460),
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 24),
                decoration: BoxDecoration(
                  color: c.panel,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(kPanelRadius),
                  boxShadow: c.shadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HtIcon(HtIcons.lock,
                        size: 30, color: c.warn, strokeWidth: 1.6),
                    const SizedBox(height: 11),
                    Text('HV locked', style: t.lockH3),
                    const SizedBox(height: 11),
                    Text(text,
                        style: t.lockP, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// `filter:blur(2px)` — CSS blur radius is 2× the Gaussian sigma.
ImageFilter cssBlur(double cssPx) =>
    ImageFilter.blur(sigmaX: cssPx / 2, sigmaY: cssPx / 2);
