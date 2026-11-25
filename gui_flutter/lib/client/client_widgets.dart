/// Small building blocks in the client's style — the Flutter counterparts of
/// `ui/widgets/{card,modern_button,status_badge,verdict_label}.py` and the Qt
/// group boxes / combo boxes / line edits of the left panel.
library;

import 'package:flutter/material.dart';

import 'client_icons.dart';
import 'client_theme.dart';

/// `Card` / `QGroupBox`: a titled surface with the client's hairline border.
class GroupCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  const GroupCard({
    super.key,
    this.title,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 12),
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(children: [
              Expanded(
                child: Text(title!.toUpperCase(),
                    style: ctext(context,
                        size: 10,
                        weight: FontWeight.w700,
                        color: c.muted,
                        spacing: 1)),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}

enum CRole { primary, danger, secondary, ghost, neutral }

/// `ModernButton`.
class CButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final CRole role;
  final bool compact;
  final String? tooltip;
  final double? width;
  final IconKind? icon;

  /// Overrides the standard height (34, or 28 compact) and label size (13 / 12).
  final double? height;
  final double? fontSize;

  const CButton(
    this.label, {
    super.key,
    this.onPressed,
    this.role = CRole.neutral,
    this.compact = false,
    this.tooltip,
    this.width,
    this.icon,
    this.height,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final enabled = onPressed != null;
    final (bg, hover, fg, border) = switch (role) {
      CRole.primary => (
          c.green,
          c.greenHover,
          Colors.white,
          Colors.transparent
        ),
      CRole.danger => (c.red, c.redHover, Colors.white, Colors.transparent),
      CRole.secondary => (
          c.blue,
          c.blueHover,
          Colors.white,
          Colors.transparent
        ),
      CRole.ghost => (
          Colors.transparent,
          c.blue.withValues(alpha: 0.12),
          c.text,
          c.blue
        ),
      CRole.neutral => (
          c.border,
          c.dim.withValues(alpha: 0.5),
          c.text,
          Colors.transparent
        ),
    };
    final btn = _Hover(
      builder: (h) => Container(
        width: width,
        height: height ?? (compact ? 28 : 34),
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
        // No `alignment:` here — a Container with one expands to fill any
        // loose space (a Wrap, a Column), stretching the button full width.
        // The Row below centres within whatever width the parent gives.
        decoration: BoxDecoration(
          color: enabled ? (h ? hover : bg) : c.border.withValues(alpha: 0.55),
          border: Border.all(
              color: enabled ? border : Colors.transparent, width: 1.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                ClientIcon(icon!, color: enabled ? fg : c.dim, size: 13),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ctext(context,
                      size: fontSize ?? (compact ? 12 : 13),
                      weight: FontWeight.w700,
                      color: enabled ? fg : c.dim),
                ),
              ),
            ]),
      ),
      enabled: enabled,
      onTap: onPressed,
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Hover + click without Material's ink.
class _Hover extends StatefulWidget {
  final Widget Function(bool hovering) builder;
  final bool enabled;
  final VoidCallback? onTap;
  const _Hover({required this.builder, required this.enabled, this.onTap});

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          child: widget.builder(_h && widget.enabled),
        ),
      );
}

/// A clickable wrapper with hover feedback, for custom controls.
class ClickBox extends StatelessWidget {
  final Widget Function(bool hovering) builder;
  final VoidCallback? onTap;
  const ClickBox({super.key, required this.builder, this.onTap});

  @override
  Widget build(BuildContext context) =>
      _Hover(builder: builder, enabled: onTap != null, onTap: onTap);
}

/// `StatusBadge`: a rounded pill with text.
class Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final double size;
  const Pill(this.text,
      {super.key, required this.bg, this.fg = Colors.white, this.size = 11});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(text,
            style:
                ctext(context, size: size, weight: FontWeight.w700, color: fg)),
      );
}

/// A one-line text input (`QLineEdit`).
class CField extends StatefulWidget {
  final String value;
  final String hint;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final double? width;
  final TextAlign align;
  final bool mono;

  const CField({
    super.key,
    required this.value,
    this.hint = '',
    this.onChanged,
    this.enabled = true,
    this.width,
    this.align = TextAlign.start,
    this.mono = false,
  });

  @override
  State<CField> createState() => _CFieldState();
}

class _CFieldState extends State<CField> {
  late final TextEditingController _c =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(CField old) {
    super.didUpdateWidget(old);
    // Follow external changes (e.g. DUT ID auto-increment) without fighting
    // the caret while the operator is typing.
    if (widget.value != _c.text && widget.value != old.value) {
      _c.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    return SizedBox(
      width: widget.width,
      height: 32,
      child: TextField(
        controller: _c,
        enabled: widget.enabled,
        textAlign: widget.align,
        onChanged: widget.onChanged,
        cursorColor: c.blue,
        style: ctext(context,
            size: 13,
            color: widget.enabled ? c.text : c.dim,
            family: widget.mono ? kClientMono : null),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: c.input,
          hintText: widget.hint,
          hintStyle: ctext(context, size: 13, color: c.dim),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: c.inputBorder)),
          disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide:
                  BorderSide(color: c.inputBorder.withValues(alpha: .5))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: c.blue, width: 1.4)),
        ),
      ),
    );
  }
}

/// A combo box (`QComboBox`). [items] maps value → label.
class CDropdown<T> extends StatelessWidget {
  final T value;
  final Map<T, String> items;
  final ValueChanged<T>? onChanged;
  final double? width;
  final bool highlight;

  const CDropdown({
    super.key,
    required this.value,
    required this.items,
    this.onChanged,
    this.width,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final enabled = onChanged != null && items.isNotEmpty;
    return Container(
      width: width,
      height: 32,
      padding: const EdgeInsets.only(left: 10, right: 6),
      decoration: BoxDecoration(
        color: c.input,
        border: Border.all(
            color: highlight ? c.blue : c.inputBorder,
            width: highlight ? 1.4 : 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.containsKey(value) ? value : null,
          isExpanded: true,
          isDense: true,
          dropdownColor: c.card,
          borderRadius: BorderRadius.circular(6),
          icon: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ClientIcon(IconKind.arrowDown, color: c.muted, size: 12),
          ),
          style: ctext(context, size: 13, color: enabled ? c.text : c.dim),
          hint: Text('—', style: ctext(context, size: 13, color: c.dim)),
          onChanged: enabled ? (v) => v == null ? null : onChanged!(v) : null,
          items: [
            for (final e in items.entries)
              DropdownMenuItem<T>(
                value: e.key,
                child: Text(e.value,
                    overflow: TextOverflow.ellipsis,
                    style: ctext(context, size: 13)),
              ),
          ],
        ),
      ),
    );
  }
}

/// `QRadioButton`.
class CRadio extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const CRadio(this.label, {super.key, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    return ClickBox(
      onTap: onTap,
      builder: (_) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? c.blue : Colors.transparent,
            border: Border.all(color: selected ? c.blue : c.dim, width: 1.6),
          ),
          child: selected
              ? Center(
                  child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle)))
              : null,
        ),
        const SizedBox(width: 8),
        Text(label,
            style: ctext(context,
                size: 13, color: onTap == null ? c.dim : c.text)),
      ]),
    );
  }
}

/// `QCheckBox`.
class CCheck extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? accent;
  const CCheck(this.label,
      {super.key, required this.value, this.onChanged, this.accent});

  @override
  Widget build(BuildContext context) {
    final c = context.cc;
    final a = accent ?? c.blue;
    return ClickBox(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      builder: (_) =>
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(top: 1),
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: value ? a : Colors.transparent,
            border: Border.all(color: value ? a : c.dim, width: 1.6),
            borderRadius: BorderRadius.circular(4),
          ),
          child: value
              ? const Center(
                  child:
                      ClientIcon(IconKind.check, color: Colors.white, size: 13))
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: ctext(context, size: 13))),
      ]),
    );
  }
}

/// `Label:  [field]` row of the left panel.
class LabelRow extends StatelessWidget {
  final String label;
  final Widget child;
  final double labelWidth;
  const LabelRow(this.label, this.child, {super.key, this.labelWidth = 74});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(
            width: labelWidth,
            child: Text('$label:',
                style: ctext(context, size: 12.5, color: context.cc.muted)),
          ),
          Expanded(child: child),
        ]),
      );
}

/// A thin horizontal rule in the border colour (`_hline`).
class HLine extends StatelessWidget {
  const HLine({super.key});
  @override
  Widget build(BuildContext context) => Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: context.cc.border);
}
