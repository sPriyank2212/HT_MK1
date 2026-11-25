/// The client's look: the palette and type of the customer's own Harness
/// Tester (`gui_client_required/ui/widgets/*.py`, `ui/test_control_bar.py`,
/// `ui/connector_view.py`, `resources/{dark,light}_theme.qss`), as tokens.
///
/// Dark is the client's default ("Modernized" skin); light is their
/// `light_theme.qss` palette. Widgets read colours from
/// `ClientColors.of(context)` — never a literal — so View → Theme flips the
/// whole window.
library;

import 'package:flutter/material.dart';

class ClientColors {
  final bool dark;

  /// window background, left-panel/card surface, hairline border, input fill
  final Color bg, card, border, input, inputBorder;
  final Color text, muted, dim;

  /// accents — green = primary action / PASS, blue = secondary / selected
  final Color green, greenHover, blue, blueHover, red, redHover, amber, info;
  final Color neutral;

  /// the status colours used by the connector view's legend and the table
  final Color untested, running, pass, fail, hvResult;

  /// connector view: body, border, title bar, net chip
  final Color connBody, connBorder, connTitleBg, connTitleFg, bandBlue, bandAmber;

  const ClientColors._({
    required this.dark,
    required this.bg,
    required this.card,
    required this.border,
    required this.input,
    required this.inputBorder,
    required this.text,
    required this.muted,
    required this.dim,
    required this.green,
    required this.greenHover,
    required this.blue,
    required this.blueHover,
    required this.red,
    required this.redHover,
    required this.amber,
    required this.info,
    required this.neutral,
    required this.untested,
    required this.running,
    required this.pass,
    required this.fail,
    required this.hvResult,
    required this.connBody,
    required this.connBorder,
    required this.connTitleBg,
    required this.connTitleFg,
    required this.bandBlue,
    required this.bandAmber,
  });

  // `ModernButton`/`StatusBadge`/`Card`/`VerdictLabel` hex values.
  static const ClientColors darkTheme = ClientColors._(
    dark: true,
    bg: Color(0xFF0B0C15),
    card: Color(0xFF141621),
    border: Color(0xFF2A2E42),
    input: Color(0xFF0F111C),
    inputBorder: Color(0xFF2A2E42),
    text: Color(0xFFF1F5F9),
    muted: Color(0xFF94A3B8),
    dim: Color(0xFF64748B),
    green: Color(0xFF22C55E),
    greenHover: Color(0xFF16A34A),
    blue: Color(0xFF3B82F6),
    blueHover: Color(0xFF2563EB),
    red: Color(0xFFEF4444),
    redHover: Color(0xFFDC2626),
    amber: Color(0xFFF59E0B),
    info: Color(0xFF38BDF8),
    neutral: Color(0xFF475569),
    untested: Color(0xFF64748B),
    running: Color(0xFFF59E0B),
    pass: Color(0xFF22C55E),
    fail: Color(0xFFEF4444),
    hvResult: Color(0xFF38BDF8),
    connBody: Color(0xFF0F111E),
    connBorder: Color(0xFF3B82F6),
    connTitleBg: Color(0xFF141621),
    connTitleFg: Color(0xFF38BDF8),
    bandBlue: Color(0xFF1F3864),
    bandAmber: Color(0xFF5A3A00),
  );

  static const ClientColors lightTheme = ClientColors._(
    dark: false,
    bg: Color(0xFFF5F5F5),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFCCCCCC),
    input: Color(0xFFFFFFFF),
    inputBorder: Color(0xFFCCCCCC),
    text: Color(0xFF1C1C1C),
    muted: Color(0xFF475569),
    dim: Color(0xFF64748B),
    green: Color(0xFF28A745),
    greenHover: Color(0xFF1E7E34),
    blue: Color(0xFF2563EB),
    blueHover: Color(0xFF1D4ED8),
    red: Color(0xFFDC3545),
    redHover: Color(0xFFB02A37),
    amber: Color(0xFFD97706),
    info: Color(0xFF0284C7),
    neutral: Color(0xFF94A3B8),
    untested: Color(0xFF94A3B8),
    running: Color(0xFFD97706),
    pass: Color(0xFF28A745),
    fail: Color(0xFFDC3545),
    hvResult: Color(0xFF0284C7),
    connBody: Color(0xFFF8FAFC),
    connBorder: Color(0xFF2563EB),
    connTitleBg: Color(0xFFE2E8F0),
    connTitleFg: Color(0xFF0369A1),
    bandBlue: Color(0xFF1F3864),
    bandAmber: Color(0xFF92600A),
  );

  static ClientColors of(BuildContext context) {
    final t = context.dependOnInheritedWidgetOfExactType<ClientTheme>();
    return t?.colors ?? darkTheme;
  }
}

class ClientTheme extends InheritedWidget {
  final ClientColors colors;
  const ClientTheme({super.key, required this.colors, required super.child});

  @override
  bool updateShouldNotify(ClientTheme old) => old.colors != colors;
}

extension ClientThemeContext on BuildContext {
  ClientColors get cc => ClientColors.of(this);
}

/// Segoe UI is the client's face (Qt's default on Windows), Consolas its log.
const String kClientFont = 'Segoe UI';
const String kClientMono = 'Consolas';

TextStyle ctext(BuildContext context,
        {double size = 13,
        FontWeight weight = FontWeight.w400,
        Color? color,
        double? spacing,
        String? family}) =>
    TextStyle(
      fontFamily: family ?? kClientFont,
      fontFamilyFallback: const ['Segoe UI Variable Text', 'Arial'],
      fontSize: size,
      fontWeight: weight,
      color: color ?? context.cc.text,
      letterSpacing: spacing,
      decoration: TextDecoration.none,
    );

/// A Material [ThemeData] carrying the same palette, for the widgets (text
/// fields, menus, tooltips, scrollbars) that read it.
ThemeData clientThemeData(ClientColors c) => ThemeData(
      useMaterial3: false,
      brightness: c.dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.card,
      cardColor: c.card,
      dividerColor: c.border,
      fontFamily: kClientFont,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.blue,
        selectionColor: c.blue.withValues(alpha: 0.35),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: TextStyle(
            fontFamily: kClientFont, fontSize: 12, color: c.text),
        waitDuration: const Duration(milliseconds: 500),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(c.border),
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(4),
      ),
      colorScheme: ColorScheme(
        brightness: c.dark ? Brightness.dark : Brightness.light,
        primary: c.blue,
        onPrimary: Colors.white,
        secondary: c.green,
        onSecondary: Colors.white,
        error: c.red,
        onError: Colors.white,
        surface: c.card,
        onSurface: c.text,
      ),
    );
