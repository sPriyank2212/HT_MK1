/// The app chrome: status header, hazard banner, navigation rail and log bar.
///
/// ```css
/// .app{height:100dvh;display:grid;grid-template-columns:80px minmax(0,1fr);
///   grid-template-rows:auto minmax(0,1fr) auto;
///   grid-template-areas:"status status" "rail stage" "log log"}
/// ```
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import 'app_state.dart';
import 'build_tag.dart';

/// `@media (max-width:860px)` — the rail goes horizontal and the page scrolls.
///
/// The other breakpoint, `@media (max-width:1080px)`, is `kMediumBreak` in
/// `parts.dart`, next to the view grids it collapses.
const double kNarrow = 860;

// ---------------------------------------------------------------------------
// status header
// ---------------------------------------------------------------------------

/// `.status{height:52px;gap:18px;padding:0 16px;background:var(--panel);
///          border-bottom:1px solid var(--line)}`
///
/// At the narrow breakpoint the page adds `.status{overflow-x:auto}` — the
/// bar scrolls horizontally instead of overflowing. A horizontal scroll view
/// has unbounded width, so the flex children (the slots and the spacer) are
/// swapped for their intrinsic-width equivalents, the same trick the rail
/// uses when it goes horizontal.
class StatusBar extends StatelessWidget {
  final AppState s;
  final VoidCallback onToggleTheme;

  const StatusBar({super.key, required this.s, required this.onToggleTheme});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width <= kNarrow;
    // DUT ID/Operator are the least safety-relevant thing in this bar - the
    // first to give way once the bar is tight, rather than fighting the
    // existing slots (or the conditional Clear Fault button, which can
    // appear at any time) for space. 1600 rather than kMediumBreak (1080):
    // measured this bar overflowing at the 1480px "default" test width with
    // Clear Fault showing, so kMediumBreak alone left no real margin.
    final showOperatorFields = width > 1600;

    final children = <Widget>[
      // .mark
      Container(
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: c.lineSoft)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text('HT', style: t.markBadge),
            ),
            const SizedBox(width: 9),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HT_MK1 Console', style: t.markName),
                // Real: fetched via >ID on connect (AppState._connect()).
                // Null until then, or if never connected this session.
                Text('fw ${s.fwVersion ?? "—"} · g474', style: t.markSub),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(width: 18),
      _Slot(
        label: 'MTX netlist',
        value: s.nlMtx.loaded ? s.nlMtx.name! : 'none',
        flex: !narrow,
      ),
      const SizedBox(width: 18),
      _Slot(
        label: 'HV netlist',
        value: s.nlHv.loaded ? s.nlHv.name! : 'none',
        hvTint: true,
        flex: !narrow,
      ),
      const SizedBox(width: 18),
      _Slot(label: 'Connected to', value: s.stFix, flex: !narrow),
      // Session-scoped, not persisted - carried into every test report
      // generated after being set (AppState.dutId/operatorName, report.dart).
      // Hidden below the medium breakpoint: the least safety-relevant thing
      // in this bar, so the first to give way when it's tight, rather than
      // fighting the slots above for space down to the 860px scroll point.
      if (showOperatorFields) ...[
        const SizedBox(width: 18),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Lbl('DUT ID'),
            const SizedBox(height: 3),
            TextInput(value: s.dutId, onChanged: s.setDutId, width: 90),
          ],
        ),
        const SizedBox(width: 18),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Lbl('Operator'),
            const SizedBox(height: 3),
            TextInput(value: s.operatorName, onChanged: s.setOperatorName, width: 110),
          ],
        ),
      ],
      const SizedBox(width: 18),
      if (!narrow) const FlexSpacer(),
      ThemeBtn(onTap: onToggleTheme),
      const SizedBox(width: 18),
      // Replaces the markup's static "Link COM7" pill.
      _PortSelector(s: s),
      const SizedBox(width: 18),
      Pill(s.hvPill.variant, s.hvPill.text),
      const SizedBox(width: 18),
      Pill(s.statePill.variant, s.statePill.text),
      // FAULT CLEAR is the only recovery from a latched fault (brief §3.2.1,
      // FW-10) — offered here as a deliberate operator action, never
      // triggered automatically.
      if (s.inFault) ...[
        const SizedBox(width: 8),
        Btn('Clear Fault', variant: BtnVariant.primary, onTap: s.clearFault),
      ],
    ];

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: narrow
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: children),
            )
          : Row(children: children),
    );
  }
}

/// `.slot{display:flex;flex-direction:column;gap:3px;min-width:0}`
class _Slot extends StatelessWidget {
  final String label;
  final String value;
  final bool hvTint;

  /// False inside the narrow horizontally-scrolling bar, where a flex child
  /// would see unbounded width.
  final bool flex;

  const _Slot({
    required this.label,
    required this.value,
    this.hvTint = false,
    this.flex = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Lbl(label),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: context.type.slotV(hvTint ? c.hv : c.ink),
        ),
      ],
    );
    return flex ? Flexible(child: column) : column;
  }
}

/// The serial-port cluster: dropdown, refresh button, connect/disconnect
/// button and the live link pill.
class _PortSelector extends StatelessWidget {
  final AppState s;
  const _PortSelector({required this.s});

  @override
  Widget build(BuildContext context) {
    // A connect in flight is neither state: saying "Connect" while one is
    // running invites the second click that kills the first attempt.
    final String label = s.connecting
        ? 'Connecting'
        : s.link
            ? 'Disconnect'
            : 'Connect';
    final VoidCallback? onTap = s.connecting
        ? null
        : s.link
            ? () => unawaited(s.disconnect())
            : s.selPort == null
                ? null
                : () => s.connectTo(s.selPort!);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Under --sim or --host the transport is a socket; there is no COM
        // port to pick and the picker would only mislead.
        if (s.serialLink) ...[
          _PortDropdown(s: s),
          const SizedBox(width: 6),
          _RefreshBtn(onTap: s.refreshPorts),
          const SizedBox(width: 6),
        ],
        Btn(label, onTap: onTap),
        const SizedBox(width: 6),
        Pill(
          s.link
              ? PillVariant.ok
              : s.connecting
                  ? PillVariant.acc
                  : PillVariant.warn,
          s.link
              ? 'Link ${s.host}'
              : s.connecting
                  ? 'Opening ${s.selPort ?? s.host}'
                  : 'No link',
        ),
      ],
    );
  }
}

/// The port dropdown: rows of `name — description` from [AppState.ports].
/// Picking a port selects it and closes the menu — Connect is what opens it.
/// While linked the dropdown is disabled and shows the port the link is on.
class _PortDropdown extends StatefulWidget {
  final AppState s;
  const _PortDropdown({required this.s});

  @override
  State<_PortDropdown> createState() => _PortDropdownState();
}

class _PortDropdownState extends State<_PortDropdown> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _menu;
  bool _hover = false;

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  void _close() {
    final menu = _menu;
    _menu = null;
    // Nulling first makes a second _close a no-op; `mounted` covers the case
    // where the Overlay itself was torn down before this widget's dispose.
    if (menu != null && menu.mounted) menu.remove();
  }

  void _toggle() {
    if (_menu != null) {
      _close();
      return;
    }
    final s = widget.s;
    if (!_enabled(s)) return;
    // Without a Navigator there was no Overlay at all and this threw on every
    // click. There is one now (see HtHome), but a dead dropdown beats a
    // crashed console if some future harness leaves it out.
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final entry = OverlayEntry(builder: (context) {
      // The menu is a sibling of the app in the overlay, so it does not get
      // rebuilt by the AnimatedBuilder around HtHome. It listens itself:
      // otherwise Refresh behind an open menu changed AppState.ports and the
      // menu carried on showing the ports that had gone away.
      return AnimatedBuilder(
        animation: s,
        builder: (context, _) {
          final c = context.colors;
          final t = context.type;
          if (!_enabled(s)) {
            // The link came up, or the last port vanished, while the menu was
            // open. Fold it away rather than leave a live-looking list over a
            // selector that is no longer taking input.
            WidgetsBinding.instance.addPostFrameCallback((_) => _close());
          }
          return Stack(
            children: [
              // tap-away dismiss
              Positioned.fill(
                child: GestureDetector(
                  onTap: _close,
                  behavior: HitTestBehavior.translucent,
                ),
              ),
              CompositedTransformFollower(
                link: _link,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 4),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 340),
                  decoration: BoxDecoration(
                    color: c.panel,
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(kRadius),
                    boxShadow: c.shadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final p in s.ports)
                        HoverRow(
                          pressed: p.name == s.selPort,
                          onTap: () {
                            _close();
                            // Choose only — Connect opens it.
                            s.choosePort(p.name);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Text(
                              '${p.name} — ${p.description}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: t.mono(size: 12, color: c.ink),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    });
    overlay.insert(entry);
    _menu = entry;
  }

  /// The selector takes input only when there is something to pick and no link
  /// (or connect) already using the port.
  static bool _enabled(AppState s) =>
      !s.link && !s.connecting && s.ports.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final s = widget.s;
    final enabled = _enabled(s);
    final label = s.link
        ? s.host
        : s.selPort ?? (s.ports.isEmpty ? 'No ports' : 'Select port');
    final fg = enabled ? c.ink : c.ink3;

    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: enabled ? _toggle : null,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            // Narrow enough that the status bar still fits between the
            // breakpoints; longer port names ellipsize.
            constraints: const BoxConstraints(maxWidth: 96),
            decoration: BoxDecoration(
              color: enabled ? null : c.sunk,
              border: Border.all(
                  color: _hover && enabled ? c.accent : c.line),
              borderRadius: BorderRadius.circular(kRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: t.mono(size: 12, color: fg),
                  ),
                ),
                const SizedBox(width: 6),
                Text('▾', style: t.mono(size: 10, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.themebtn` with the refresh glyph — re-enumerates the serial ports.
class _RefreshBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _RefreshBtn({required this.onTap});

  @override
  State<_RefreshBtn> createState() => _RefreshBtnState();
}

class _RefreshBtnState extends State<_RefreshBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final colour = _hover ? c.accent : c.ink3;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: _hover ? c.accent : c.line),
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: HtIcon(HtIcons.refresh,
              size: 15, color: colour, strokeWidth: 1.7),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// hazard banner
// ---------------------------------------------------------------------------

/// `.hazard` — shown instead of `.status` while `body.hv-live`.
class HazardBar extends StatefulWidget {
  final AppState s;
  const HazardBar({super.key, required this.s});

  @override
  State<HazardBar> createState() => _HazardBarState();
}

class _HazardBarState extends State<HazardBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat;

  @override
  void initState() {
    super.initState();
    // @keyframes beat{0%,100%{opacity:1}50%{opacity:.42}} 1.05s infinite
    _beat = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final s = widget.s;

    return SizedBox(
      height: 52,
      child: Striped(
        stripe: c.hvSoft,
        base: c.panel,
        band: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.hv, width: 2)),
          ),
          child: Row(
            children: [
              FadeTransition(
                opacity: Tween<double>(begin: 1.0, end: .42).animate(_beat),
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.hv,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text('⚡',
                      style: t.ui(size: 17, color: c.panel)),
                ),
              ),
              const SizedBox(width: 14),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Single line: the banner is a fixed 52px, and letting
                    // the headline wrap to two lines overflows it by 7px.
                    Text(
                      'HIGH VOLTAGE LIVE — J-HV ENERGIZED',
                      style: t.hazardH2,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Insulation test running. Relays are cold-switched; '
                      'the fixture stays live until discharge completes.',
                      style: t.hazardP,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const FlexSpacer(),
              const SizedBox(width: 14),
              _HazardSlot(label: 'Rail', value: s.hzRail), // REAL - live hvMv.
              const SizedBox(width: 14),
              _HazardSlot(label: 'Leakage', value: s.hzLeak), // REAL - paintLink().
              const SizedBox(width: 14),
              Btn('Abort & discharge',
                  variant: BtnVariant.ghostHv, onTap: s.abort),
            ],
          ),
        ),
      ),
    );
  }
}

class _HazardSlot extends StatelessWidget {
  final String label;
  final String value;
  const _HazardSlot({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Lbl(label),
          const SizedBox(height: 3),
          Text(value,
              style: context.type.mono(
                  size: 12.5, tabular: true, color: context.colors.ink)),
        ],
      );
}

// ---------------------------------------------------------------------------
// navigation rail
// ---------------------------------------------------------------------------

/// `.rail{width:80px;padding:10px 8px;gap:2px;background:var(--panel);
///        border-right:1px solid var(--line)}`
class Rail extends StatelessWidget {
  final AppState s;
  final bool horizontal;

  /// Whether this is a customer build — hides the Diag button. Defaults to
  /// the real compile-time flag ([kCustomerBuild]); overridable so a test
  /// can exercise both branches without needing two separate `dart-define`
  /// test runs.
  final bool customerBuild;

  const Rail({
    super.key,
    required this.s,
    this.horizontal = false,
    this.customerBuild = kCustomerBuild,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final buttons = <Widget>[
      _RailButton(
          s: s, view: 'run', label: 'Run', icon: HtIcons.run, badge: null),
      _RailButton(
          s: s,
          view: 'cont',
          label: 'Contin',
          icon: HtIcons.cont,
          badge: s.railBadge('cont')),
      _RailButton(
          s: s,
          view: 'res',
          label: 'Resist',
          icon: HtIcons.res,
          badge: s.railBadge('res')),
      _RailButton(
          s: s,
          view: 'hv',
          label: 'HV',
          icon: HtIcons.hv,
          badge: s.railBadge('hv')),
      _RailButton(
          s: s,
          view: 'program',
          label: 'Netlist',
          icon: HtIcons.netlist,
          badge: null),
      _RailButton(
          s: s,
          view: 'results',
          label: 'Results',
          icon: HtIcons.results,
          badge: null),
      // Customer builds ship with no Diagnostics section at all - not just
      // a hidden button, see kCustomerBuild.
      if (!customerBuild)
        _RailButton(
            s: s, view: 'diag', label: 'Diag', icon: HtIcons.diag, badge: null),
    ];

    if (horizontal) {
      // @media (max-width:860px){.rail{flex-direction:row;overflow-x:auto}
      //   .rail button{flex:none;min-width:70px}
      //   .rail hr,.rail .stg{display:none}
      //   .rail .rail-end{margin-top:0;margin-left:auto}}
      //
      // No Expanded here: the Row is inside a horizontal scroll view, so its
      // width is unbounded and a flex child would assert.
      return Container(
        decoration: BoxDecoration(
          color: c.panel,
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                // .rail-end sits after a wider gap instead of margin-left:auto
                if (i == buttons.length - 1) const SizedBox(width: 16),
                SizedBox(width: 70, child: buttons[i]),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      width: 80,
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(right: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buttons[0],
          _RailStage('Stage 1 · MTX'),
          buttons[1],
          const SizedBox(height: 2),
          buttons[2],
          _RailStage('Stage 2 · HV'),
          buttons[3],
          // .rail hr{margin:5px 6px 0}
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 6, top: 5),
            child: Container(height: 1, color: c.lineSoft),
          ),
          const SizedBox(height: 2),
          buttons[4],
          const SizedBox(height: 2),
          buttons[5],
          // .rail .rail-end{margin-top:auto}
          const Expanded(child: SizedBox()),
          // Diag (buttons[6]) doesn't exist in a customer build - the first
          // six are always present, this one is the only conditional entry.
          if (buttons.length > 6) buttons[6],
        ],
      ),
    );
  }
}

/// `.rail .stg{mono 8px .14em uppercase ink-3;padding:8px 0 3px;
///             text-align:center}`
class _RailStage extends StatelessWidget {
  final String text;
  const _RailStage(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 3),
        child: Text(text.toUpperCase(),
            style: context.type.railStg, textAlign: TextAlign.center),
      );
}

class _RailButton extends StatefulWidget {
  final AppState s;
  final String view;
  final String label;
  final HtIconData icon;
  final String? badge;

  const _RailButton({
    required this.s,
    required this.view,
    required this.label,
    required this.icon,
    required this.badge,
  });

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = widget.s.view == widget.view;

    // .rail button{color:var(--ink-3)}
    // .rail button:hover{background:var(--panel-2);color:var(--ink-2)}
    // .rail button[aria-selected="true"]{background:var(--accent-soft);
    //                                    color:var(--accent)}
    final fg = selected
        ? c.accent
        : _hover
            ? c.ink2
            : c.ink3;
    final bg = selected
        ? c.accentSoft
        : _hover
            ? c.panel2
            : const Color(0x00000000);

    final badgeColor = switch (widget.badge) {
      'st-pass' => c.pass,
      'st-fail' => c.fail,
      'st-lock' => c.warn,
      _ => null,
    };

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => widget.s.go(widget.view),
        behavior: HitTestBehavior.opaque,
        child: Container(
          // .rail button{padding:9px 2px 8px;border-radius:var(--r)}
          padding: const EdgeInsets.only(left: 2, right: 2, top: 9, bottom: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // .rail button svg{width:19px;height:19px;stroke-width:1.6}
                  HtIcon(widget.icon, size: 19, color: fg, strokeWidth: 1.6),
                  const SizedBox(height: 5),
                  Text(widget.label.toUpperCase(),
                      style: context.type.rail(fg)),
                ],
              ),
              if (badgeColor != null)
                // .rail button .badge{top:6px;right:9px;width:6px;height:6px}
                Positioned(
                  top: 6,
                  right: 9,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: badgeColor, shape: BoxShape.circle),
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
// log bar
// ---------------------------------------------------------------------------

/// `.logbar{background:var(--sunk);border-top:1px solid var(--line)}`
class LogBar extends StatefulWidget {
  final AppState s;
  const LogBar({super.key, required this.s});

  @override
  State<LogBar> createState() => _LogBarState();
}

class _LogBarState extends State<LogBar> {
  final ScrollController _scroll = ScrollController();
  bool _hoverToggle = false;
  String? _hoverTab;
  int _seenOps = 0;
  int _seenWire = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll(int count, int seen, void Function(int) setSeen) {
    // logBody.scrollTop=logBody.scrollHeight
    if (count == seen) return;
    setSeen(count);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Widget _tab(BuildContext context, AppState s, String view, String label) {
    final c = context.colors;
    final t = context.type;
    final active = s.logView == view;
    final hover = _hoverTab == view;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoverTab = view),
      onExit: (_) => setState(() => _hoverTab = null),
      child: GestureDetector(
        onTap: () => s.setLogView(view),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            label,
            style: t
                .logButton(active
                    ? c.accent
                    : hover
                        ? c.ink2
                        : c.ink3)
                .copyWith(fontWeight: active ? FontWeight.w700 : null),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final s = widget.s;
    if (s.logOpen) {
      if (s.logView == 'wire') {
        _autoScroll(s.wireLog.length, _seenWire, (n) => _seenWire = n);
      } else {
        _autoScroll(s.logs.length, _seenOps, (n) => _seenOps = n);
      }
    }

    Color levelColor(String lvl) => switch (lvl) {
          'ok' => c.pass,
          'warn' => c.warn,
          'fail' => c.fail,
          'hv' => c.hv,
          _ => c.ink3,
        };

    return Container(
      decoration: BoxDecoration(
        color: c.sunk,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // .logbar .head{height:30px;gap:10px;padding:0 14px}
          SizedBox(
            height: 30,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  // Every line here is exactly what the session file's
                  // [tx]/[rx] lines record — see ConnectionManager.onWire —
                  // so "Console" is the live, on-screen twin of that file.
                  _tab(context, s, 'ops', 'Log'),
                  Text(' / ', style: t.logButton(c.ink3)),
                  _tab(context, s, 'wire', 'Console'),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.logView == 'wire'
                          ? (s.wireLog.isEmpty
                              ? 'no wire traffic yet'
                              : '${s.wireLog.last.dir}: ${s.wireLog.last.text}')
                          : s.logLineText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: t.logLine,
                    ),
                  ),
                  const SizedBox(width: 10),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _hoverToggle = true),
                    onExit: (_) => setState(() => _hoverToggle = false),
                    child: GestureDetector(
                      onTap: s.toggleLog,
                      child: Text(
                        s.logOpen ? 'COLLAPSE' : 'EXPAND',
                        style: t.logButton(_hoverToggle ? c.accent : c.ink3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // .logbar .body{height:150px;overflow:auto;padding:2px 14px 10px}
          if (s.logOpen)
            SizedBox(
              height: 150,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.only(
                    left: 14, right: 14, top: 2, bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: s.logView == 'wire'
                      ? [
                          for (final e in s.wireLog)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '[${_stampTime(e.t)}]',
                                    style: t.logBody(c.ink3),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 24,
                                    child: Text(
                                      e.dir.toUpperCase(),
                                      style: t
                                          .logBody(e.dir == 'tx'
                                              ? c.accent
                                              : c.pass)
                                          .copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(e.text,
                                        style: t.logBody(c.ink2)),
                                  ),
                                ],
                              ),
                            ),
                        ]
                      : [
                          for (final e in s.logs)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // <time>
                                  Text(
                                      '[${e.t.toStringAsFixed(3).padLeft(8)}]',
                                      style: t.logBody(c.ink3)),
                                  const SizedBox(width: 10),
                                  // <b class="lv-*">, width:38px
                                  SizedBox(
                                    width: 38,
                                    child: Text(
                                      e.lvl.toUpperCase(),
                                      style: t
                                          .logBody(levelColor(e.lvl))
                                          .copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  // <span class="src">, width:34px
                                  SizedBox(
                                    width: 34,
                                    child: Text(e.src,
                                        style: t.logBody(c.ink3)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(e.message,
                                        style: t.logBody(c.ink2)),
                                  ),
                                ],
                              ),
                            ),
                        ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _stampTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
}
