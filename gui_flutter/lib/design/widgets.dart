/// The design's components, one widget per CSS class.
///
/// Each widget carries the selector it implements in its doc comment, so a
/// change to the stylesheet has an obvious home here.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'icons.dart';
import 'tokens.dart';

// ---------------------------------------------------------------------------
// layout helpers
// ---------------------------------------------------------------------------

/// `.cols{display:grid;gap:14px}`
class Cols extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  final CrossAxisAlignment crossAxisAlignment;

  const Cols(
    this.children, {
    super.key,
    this.gap = 14,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  /// Same thing with the gap first. Dart requires positional arguments before
  /// named ones, so a named `gap:` ahead of the children list will not parse;
  /// this constructor reads the way the stylesheet does, gap then content.
  const Cols.gapped(
    this.gap,
    this.children, {
    super.key,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  @override
  Widget build(BuildContext context) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) out.add(SizedBox(height: gap));
      out.add(children[i]);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: out,
    );
  }
}

/// `.row{display:flex;gap:9px;flex-wrap:wrap;align-items:center}`
///
/// A CSS flex row can hold both wrapping content and a `flex:1` spacer.
/// Flutter's `Wrap` has no flex, and an `Expanded` inside one throws. So when
/// the children contain a [FlexSpacer] this splits at it: everything before goes
/// in a wrapping group that takes the free space, everything after is pinned
/// to the trailing edge — which is what `.spacer` achieves in the page.
class RowWrap extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  final double runGap;
  final WrapAlignment alignment;
  final WrapCrossAlignment crossAxisAlignment;

  const RowWrap(
    this.children, {
    super.key,
    this.gap = 9,
    double? runGap,
    this.alignment = WrapAlignment.start,
    this.crossAxisAlignment = WrapCrossAlignment.center,
  }) : runGap = runGap ?? gap;

  /// Same thing with the gap first. Dart requires positional arguments before
  /// named ones, so a named `gap:` ahead of the children list will not parse;
  /// this constructor reads the way the stylesheet does, gap then content.
  const RowWrap.gapped(
    this.gap,
    this.children, {
    super.key,
    double? runGap,
    this.alignment = WrapAlignment.start,
    this.crossAxisAlignment = WrapCrossAlignment.center,
  }) : runGap = runGap ?? gap;

  Wrap _wrap(List<Widget> items, WrapAlignment align) => Wrap(
        spacing: gap,
        runSpacing: runGap,
        alignment: align,
        crossAxisAlignment: crossAxisAlignment,
        children: items,
      );

  @override
  Widget build(BuildContext context) {
    final at = children.indexWhere((w) => w is FlexSpacer);
    if (at < 0) return _wrap(children, alignment);

    final before = children.sublist(0, at);
    final after = children.sublist(at + 1);
    return Row(
      crossAxisAlignment: switch (crossAxisAlignment) {
        WrapCrossAlignment.start => CrossAxisAlignment.start,
        WrapCrossAlignment.end => CrossAxisAlignment.end,
        WrapCrossAlignment.center => CrossAxisAlignment.center,
      },
      children: [
        Expanded(child: _wrap(before, alignment)),
        if (after.isNotEmpty) SizedBox(width: gap),
        if (after.isNotEmpty)
          Flexible(
            fit: FlexFit.loose,
            child: _wrap(after, WrapAlignment.end),
          ),
      ],
    );
  }
}

/// `.spacer{flex:1}`
///
/// Inside a [Row] this is a real flex child. Inside a [RowWrap] it is only a
/// marker — see that class, which splits its children at this widget.
class FlexSpacer extends StatelessWidget {
  const FlexSpacer({super.key});
  @override
  Widget build(BuildContext context) => const Expanded(child: SizedBox());
}

/// `repeating-linear-gradient(135deg, <color> 0 <band>px, transparent
/// <band>px <2×band>px)` over a solid base.
///
/// CSS measures the band along the gradient axis; at 135° that axis is
/// `(x + y) / √2`, so the stripes run bottom-left to top-right.
class StripePainter extends CustomPainter {
  final Color stripe;
  final Color base;
  final double band;

  const StripePainter({
    required this.stripe,
    required this.base,
    required this.band,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // Stripes are perpendicular to the 135° axis: draw thick diagonal lines.
    final paint = Paint()
      ..color = stripe
      ..style = PaintingStyle.stroke
      ..strokeWidth = band;

    final diag = size.width + size.height;
    // Line k covers axis range [k*2*band, k*2*band + band]; its centre sits at
    // axis = k*2*band + band/2, and axis = (x+y)/√2.
    final period = 2 * band;
    for (var axis = -diag; axis < diag * 2; axis += period) {
      final c = (axis + band / 2) * math.sqrt2;
      // x + y = c  ->  from (c, 0) to (0, c)
      canvas.drawLine(Offset(c, 0), Offset(0, c), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(StripePainter old) =>
      old.stripe != stripe || old.base != base || old.band != band;
}

/// A box whose background is a hazard stripe pattern.
class Striped extends StatelessWidget {
  final Color stripe;
  final Color base;
  final double band;
  final Widget child;

  const Striped({
    super.key,
    required this.stripe,
    required this.base,
    required this.band,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: StripePainter(stripe: stripe, base: base, band: band),
        child: child,
      );
}

// ---------------------------------------------------------------------------
// text
// ---------------------------------------------------------------------------

/// `.lbl{font-family:var(--mono);font-size:10px;font-weight:600;
///       letter-spacing:.13em;text-transform:uppercase;color:var(--ink-3)}`
class Lbl extends StatelessWidget {
  final String text;
  final Color? color;
  const Lbl(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    // One line, always. `.lbl` is a single-line caption in the design; letting
    // it wrap made the 52px status bar overflow by 80px at narrow widths as
    // "MTX NETLIST" broke across lines.
    return Text(
      text.toUpperCase(),
      style: color == null ? t.lbl : t.lbl.copyWith(color: color),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The content of a `.kv` `<dd>` that mixes text and a `.tag`.
///
/// In the page that is inline flow, so it wraps to a second line when the
/// column is narrow. A `Row` cannot do that and overflows instead; `Wrap` is
/// the faithful translation.
class KvInline extends StatelessWidget {
  final List<Widget> children;
  const KvInline(this.children, {super.key});

  @override
  Widget build(BuildContext context) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 3,
        children: children,
      );
}

// ---------------------------------------------------------------------------
// pill
// ---------------------------------------------------------------------------

enum PillVariant { ok, bad, warn, hot, acc, idle }

/// `.pill` and its modifiers.
class Pill extends StatelessWidget {
  final PillVariant variant;
  final String text;

  const Pill(this.variant, this.text, {super.key});

  static Color fg(HtColors c, PillVariant v) => switch (v) {
        PillVariant.ok => c.pass,
        PillVariant.bad => c.fail,
        PillVariant.warn => c.warn,
        PillVariant.hot => c.hv,
        PillVariant.acc => c.accent,
        PillVariant.idle => c.ink3,
      };

  static Color border(HtColors c, PillVariant v) =>
      v == PillVariant.idle ? c.line : fg(c, v);

  static Color background(HtColors c, PillVariant v) => switch (v) {
        PillVariant.ok => c.passSoft,
        PillVariant.bad => c.failSoft,
        PillVariant.warn => c.warnSoft,
        PillVariant.hot => c.hvSoft,
        PillVariant.acc => c.accentSoft,
        // .pill.idle sets colour only; background stays transparent.
        PillVariant.idle => const Color(0x00000000),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final colour = fg(c, variant);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: background(c, variant),
        border: Border.all(color: border(c, variant)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // .pill i{width:6px;height:6px;border-radius:50%;
          //          background:currentColor}
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text.toUpperCase(),
              style: context.type.pill(colour),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// button
// ---------------------------------------------------------------------------

enum BtnVariant { normal, primary, hv, ghostHv }

/// `.btn` and its modifiers, including `:hover` and `[disabled]`.
class Btn extends StatefulWidget {
  final String label;
  final BtnVariant variant;
  final bool big;
  final bool disabled;
  final VoidCallback? onTap;

  /// `.domain .df .btn{flex:1;justify-content:center}`
  final bool expand;

  const Btn(
    this.label, {
    super.key,
    this.variant = BtnVariant.normal,
    this.big = false,
    this.disabled = false,
    this.onTap,
    this.expand = false,
  });

  @override
  State<Btn> createState() => _BtnState();
}

class _BtnState extends State<Btn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final disabled = widget.disabled || widget.onTap == null;

    Color bg;
    Color border;
    Color fg;
    double opacity = 1;

    if (disabled) {
      // .btn[disabled]{opacity:.4;background:var(--sunk);
      //                border-color:var(--line);color:var(--ink-3)}
      bg = c.sunk;
      border = c.line;
      fg = c.ink3;
      opacity = .4;
    } else {
      switch (widget.variant) {
        case BtnVariant.normal:
          bg = c.panel;
          // .btn:hover{border-color:var(--accent);color:var(--accent)}
          border = _hover ? c.accent : c.line;
          fg = _hover ? c.accent : c.ink2;
          break;
        case BtnVariant.primary:
          bg = c.accent;
          border = c.accent;
          fg = c.accentInk;
          if (_hover) opacity = .88; // .btn.primary:hover{opacity:.88}
          break;
        case BtnVariant.hv:
          bg = c.hv;
          border = c.hv;
          fg = c.panel;
          if (_hover) opacity = .88;
          break;
        case BtnVariant.ghostHv:
          // .btn.ghost-hv{border-color:var(--hv);color:var(--hv);
          //               background:transparent}
          bg = _hover ? c.hvSoft : const Color(0x00000000);
          border = c.hv;
          fg = c.hv;
          break;
      }
    }

    final child = Container(
      // .btn{padding:7px 13px}  .btn.big{padding:10px 20px;font-size:12px}
      padding: widget.big
          ? const EdgeInsets.symmetric(horizontal: 20, vertical: 10)
          : const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment:
            widget.expand ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          // Flexible so a label wider than the button shrinks instead of
          // overflowing. At the design's intended widths nothing truncates;
          // this only bites in the narrow domain-card footers, where the CSS
          // would overflow too (a flex item's min-width defaults to auto).
          Flexible(
            child: Text(
              widget.label.toUpperCase(),
              style: widget.big ? t.btnBig(fg) : t.btn(fg),
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    return MouseRegion(
      cursor: disabled
          // .btn[disabled]{cursor:not-allowed}
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: disabled ? null : widget.onTap,
        child: Opacity(opacity: opacity, child: child),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// segmented control
// ---------------------------------------------------------------------------

/// `.seg{display:inline-flex;border:1px solid var(--line);
///       border-radius:var(--r);overflow:hidden}`
class Seg extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int>? onSelect;
  final List<bool>? enabled;
  final bool fill;

  const Seg({
    super.key,
    required this.options,
    required this.selected,
    this.onSelect,
    this.enabled,
    this.fill = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    final buttons = <Widget>[];
    for (var i = 0; i < options.length; i++) {
      final on = i == selected;
      final ok = enabled == null || enabled![i];
      final btn = GestureDetector(
        onTap: ok && onSelect != null ? () => onSelect!(i) : null,
        child: MouseRegion(
          cursor: ok ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: Container(
            // .seg button{padding:5px 12px}
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            alignment: Alignment.center,
            // .seg button[aria-pressed="true"]{background:var(--accent);
            //                                  color:var(--accent-ink)}
            color: on ? c.accent : const Color(0x00000000),
            child: Opacity(
              opacity: ok ? 1 : .4,
              child: Text(
                options[i].toUpperCase(),
                style: t.seg(on ? c.accentInk : c.ink3),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
      // Loose Flexible when not filling: the three-option filter segment is
      // wider than the diagnostics bar at narrow widths, and the buttons
      // should give way rather than overflow.
      buttons.add(fill
          ? Expanded(child: btn)
          : Flexible(fit: FlexFit.loose, child: btn));
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: buttons,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// panel
// ---------------------------------------------------------------------------

/// `.panel{background:var(--panel);border:1px solid var(--line);
///         border-radius:8px;box-shadow:var(--shadow)}`
class HtPanel extends StatelessWidget {
  /// `.panel > header` — omitted when null.
  final List<Widget>? header;

  /// Body, unpadded. Wrap in [PanelPad] for `.panel > .pad`.
  final Widget? child;

  const HtPanel({super.key, this.header, this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
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
          if (header != null)
            Container(
              // .panel > header{padding:11px 14px;gap:10px;
              //                 border-bottom:1px solid var(--line-soft)}
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.lineSoft)),
              ),
              child: Row(children: _headerRow(header!, 10)),
            ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

/// `.panel > header h3`
class PanelTitle extends StatelessWidget {
  final String text;
  const PanelTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: context.type.panelH3);
}

/// `.panel > .pad{padding:14px}`
class PanelPad extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const PanelPad(this.child,
      {super.key, this.padding = const EdgeInsets.all(14)});
  @override
  Widget build(BuildContext context) => Padding(padding: padding, child: child);
}

/// `.panel > header{display:flex;gap:10px}` — every non-flex child is made
/// loosely flexible so a long trailing `.lbl` shortens instead of overflowing
/// the panel, which is what `overflow:hidden` does for the page.
List<Widget> _headerRow(List<Widget> items, double gap) {
  final out = <Widget>[];
  for (var i = 0; i < items.length; i++) {
    if (i > 0) out.add(SizedBox(width: gap));
    final w = items[i];
    out.add(w is FlexSpacer ? w : Flexible(fit: FlexFit.loose, child: w));
  }
  return out;
}

// ---------------------------------------------------------------------------
// tag
// ---------------------------------------------------------------------------

enum TagVariant { ok, bad, warn, mut, hot, acc }

/// `.tag{mono 10px 600 .06em uppercase;border-radius:3px;padding:2px 7px}`
class Tag extends StatelessWidget {
  final TagVariant variant;
  final String text;
  const Tag(this.variant, this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (fg, bg) = switch (variant) {
      TagVariant.ok => (c.pass, c.passSoft),
      TagVariant.bad => (c.fail, c.failSoft),
      TagVariant.warn => (c.warn, c.warnSoft),
      TagVariant.mut => (c.ink3, c.panel2),
      TagVariant.hot => (c.hv, c.hvSoft),
      TagVariant.acc => (c.accent, c.accentSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text.toUpperCase(), style: context.type.tag(fg)),
    );
  }
}

// ---------------------------------------------------------------------------
// connector chip
// ---------------------------------------------------------------------------

/// `.conn{mono 13px 650 accent}` with the drawn connector glyph in `::before`.
class Conn extends StatelessWidget {
  final String text;
  final bool hv;
  final double fontSize;

  const Conn(this.text, {super.key, this.hv = false, this.fontSize = 13});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final colour = hv ? c.hv : c.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // .conn::before{width:12px;height:12px;border:2px solid currentColor;
        //   border-radius:2px;
        //   background:linear-gradient(...) center/100% 2px no-repeat}
        SizedBox(
          width: 12,
          height: 12,
          child: CustomPaint(painter: _ConnGlyphPainter(colour)),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: context.type.conn(colour).copyWith(fontSize: fontSize),
        ),
      ],
    );
  }
}

class _ConnGlyphPainter extends CustomPainter {
  final Color color;
  const _ConnGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
        const Radius.circular(2),
      ),
      stroke,
    );
    // the 2px centre bar
    canvas.drawRect(
      Rect.fromLTWH(0, size.height / 2 - 1, size.width, 2),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ConnGlyphPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// key / value list
// ---------------------------------------------------------------------------

class KvRow {
  final String term;
  final Widget definition;
  const KvRow(this.term, this.definition);
}

/// `.kv{display:grid;grid-template-columns:auto minmax(0,1fr);
///      gap:7px 14px;align-items:baseline}`
class Kv extends StatelessWidget {
  final List<KvRow> rows;
  const Kv(this.rows, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        for (var i = 0; i < rows.length; i++)
          TableRow(
            children: [
              Padding(
                padding: EdgeInsets.only(
                    top: i == 0 ? 0 : 7, right: 14),
                child: Text(rows[i].term.toUpperCase(), style: t.kvDt),
              ),
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 7),
                child: rows[i].definition,
              ),
            ],
          ),
      ],
    );
  }
}

/// `.kv dd` default text.
class KvText extends StatelessWidget {
  final String text;
  final bool big;
  const KvText(this.text, {super.key, this.big = false});
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: big ? context.type.kvDdBig : context.type.kvDd,
      );
}

// ---------------------------------------------------------------------------
// band
// ---------------------------------------------------------------------------

class BandItem {
  final String label;
  final Widget value;
  const BandItem(this.label, this.value);
}

/// `.band{display:flex;flex-wrap:wrap;background:var(--sunk);
///        border:1px solid var(--line);border-radius:8px;overflow:hidden}`
/// `.band > div{padding:10px 16px;gap:5px;flex:1;min-width:150px;
///              border-right:1px solid var(--line-soft)}`
class Band extends StatelessWidget {
  final List<BandItem> items;
  const Band(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, constraints) {
      // flex:1 with min-width:150px — work out how many fit per row.
      final perRow = math.max(
          1, math.min(items.length, (constraints.maxWidth / 150).floor()));
      final rows = <List<BandItem>>[];
      for (var i = 0; i < items.length; i += perRow) {
        rows.add(items.sublist(i, math.min(i + perRow, items.length)));
      }
      return Container(
        decoration: BoxDecoration(
          color: c.sunk,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(kPanelRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in rows)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < row.length; i++)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            border: i == row.length - 1
                                ? null
                                : Border(
                                    right: BorderSide(color: c.lineSoft)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Lbl(row[i].label),
                              const SizedBox(height: 5),
                              row[i].value,
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// progress bar
// ---------------------------------------------------------------------------

/// `.bar{height:5px;background:var(--sunk);border-radius:3px;overflow:hidden}`
/// `.bar i{height:100%;background:var(--accent);border-radius:3px}`
class Bar extends StatelessWidget {
  /// 0..1
  final double value;
  final Color? color;

  const Bar(this.value, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 5,
        color: c.sunk,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color ?? c.accent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// hardware path box
// ---------------------------------------------------------------------------

/// `.path{background:var(--sunk);border-radius:var(--r);padding:11px 12px;
///        mono 11px;line-height:1.75;color:var(--ink-2)}`
/// `.path b{color:var(--accent)}` — `.path.hvp b{color:var(--hv)}`
class PathBox extends StatelessWidget {
  /// Alternating plain / bold runs, as the markup's `<b>` spans.
  final List<PathSpan> spans;
  final bool hv;

  const PathBox(this.spans, {super.key, this.hv = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final boldColor = hv ? c.hv : c.accent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: c.sunk,
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            for (final s in spans)
              TextSpan(
                text: s.text,
                style: s.bold
                    ? t.path.copyWith(
                        color: boldColor, fontWeight: FontWeight.w600)
                    : t.path,
              ),
          ],
        ),
        style: t.path,
      ),
    );
  }
}

class PathSpan {
  final String text;
  final bool bold;
  const PathSpan(this.text, {this.bold = false});
}

// ---------------------------------------------------------------------------
// table
// ---------------------------------------------------------------------------

class HtCol {
  final String label;

  /// `th.r,td.r{text-align:right}`
  final bool right;
  final double? width;

  const HtCol(this.label, {this.right = false, this.width});
}

/// `table{border-collapse:collapse;width:100%;min-width:560px}` inside
/// `.tw{overflow-x:auto}`.
class HtTable extends StatelessWidget {
  final List<HtCol> columns;
  final List<List<Widget>> rows;
  final double minWidth;

  const HtTable({
    super.key,
    required this.columns,
    required this.rows,
    this.minWidth = 560,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    Widget table(double width) => SizedBox(
          width: width,
          child: Table(
            columnWidths: {
              for (var i = 0; i < columns.length; i++)
                if (columns[i].width != null)
                  i: FixedColumnWidth(columns[i].width!)
                else
                  i: const IntrinsicColumnWidth(flex: 1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.line)),
                ),
                children: [
                  for (final col in columns)
                    Padding(
                      // th{padding:9px 14px}
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      child: Text(
                        col.label.toUpperCase(),
                        style: t.th,
                        textAlign:
                            col.right ? TextAlign.right : TextAlign.left,
                      ),
                    ),
                ],
              ),
              for (var r = 0; r < rows.length; r++)
                TableRow(
                  decoration: BoxDecoration(
                    border: r == rows.length - 1
                        // tbody tr:last-child td{border-bottom:none}
                        ? null
                        : Border(bottom: BorderSide(color: c.lineSoft)),
                  ),
                  children: [
                    for (var i = 0; i < columns.length; i++)
                      Padding(
                        // td{padding:9px 14px}
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        child: Align(
                          alignment: columns[i].right
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: i < rows[r].length
                              ? rows[r][i]
                              : const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );

    return LayoutBuilder(builder: (context, constraints) {
      final width = math.max(minWidth, constraints.maxWidth);
      if (width <= constraints.maxWidth) return table(width);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: table(width),
      );
    });
  }
}

/// `td` plain text.
class Td extends StatelessWidget {
  final String text;
  final bool numeric;
  final Color? color;
  const Td(this.text, {super.key, this.numeric = false, this.color});
  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final style = numeric ? t.tdNum : t.td;
    return Text(text, style: color == null ? style : style.copyWith(color: color));
  }
}

// ---------------------------------------------------------------------------
// icon button (theme toggle)
// ---------------------------------------------------------------------------

/// `.themebtn{width:28px;height:28px;border-radius:var(--r);
///            border:1px solid var(--line);color:var(--ink-3)}`
class ThemeBtn extends StatefulWidget {
  final VoidCallback onTap;
  const ThemeBtn({super.key, required this.onTap});
  @override
  State<ThemeBtn> createState() => _ThemeBtnState();
}

class _ThemeBtnState extends State<ThemeBtn> {
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
          // .themebtn svg{width:15px;height:15px;stroke-width:1.7}
          child: HtIcon(HtIcons.theme,
              size: 15, color: colour, strokeWidth: 1.7),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// generic hover-highlight row
// ---------------------------------------------------------------------------

/// Rows that use `:hover{background:var(--panel-2)}` — `.fault`, `.connrow`,
/// `.filerow`, `tbody tr`.
class HoverRow extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? pressedColor;
  final bool pressed;

  /// Resting background. Rows inside a `.filelist` sit on `--panel`; rows
  /// inside a panel body inherit it and pass nothing.
  final Color? base;

  const HoverRow({
    super.key,
    required this.child,
    this.onTap,
    this.pressedColor,
    this.pressed = false,
    this.base,
  });

  @override
  State<HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = widget.pressed
        ? (widget.pressedColor ?? c.accentSoft)
        : _hover
            ? c.panel2
            : (widget.base ?? const Color(0x00000000));
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: ColoredBox(color: bg, child: widget.child),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// text input
// ---------------------------------------------------------------------------

/// A single-line free-text field — `EditableText` directly, styled to match
/// the rest of the design system, since this project deliberately carries no
/// Material dependency (`pubspec.yaml`: `uses-material-design: false`) and
/// `TextField` is Material-only. First real free-text input in the app
/// (everything else is a `Btn`/`Seg`/`HtSlider`), for the DUT ID/Operator
/// fields the `required_format` test reports need (`AppState.dutId`/
/// `operatorName`) — nothing upstream (netlist, calibration, limits) is
/// ever operator-typed text, only picked/measured.
class TextInput extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final double width;

  const TextInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 110,
  });

  @override
  State<TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<TextInput> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChange);

  void _onFocusChange() => setState(() {});

  @override
  void didUpdateWidget(covariant TextInput old) {
    super.didUpdateWidget(old);
    // External changes (e.g. AppState reset) win, unless the operator is
    // actively typing - never stomp on a value mid-edit.
    if (!_focus.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        onTap: () => _focus.requestFocus(),
        child: Container(
          width: widget.width,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: c.sunk,
            border: Border.all(color: _focus.hasFocus ? c.accent : c.line),
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: EditableText(
            controller: _controller,
            focusNode: _focus,
            style: t.mono(size: 12, color: c.ink),
            cursorColor: c.accent,
            backgroundCursorColor: c.sunk,
            maxLines: 1,
            onChanged: widget.onChanged,
          ),
        ),
      ),
    );
  }
}
