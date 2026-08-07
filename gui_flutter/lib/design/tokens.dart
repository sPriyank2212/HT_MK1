/// Design tokens — the `:root` custom properties of the approved design,
/// transcribed value for value.
///
/// The CSS lives in `gui/htweb/index.html`. Nothing here is invented: every
/// colour, size, weight and letter-spacing below is the same number the
/// stylesheet uses. Where CSS says `letter-spacing:.13em` at `font-size:10px`
/// this file says `letterSpacing: 1.3`, because Flutter counts logical pixels
/// and CSS `em` is relative to the font size — 0.13 × 10 = 1.3.
library;

import 'package:flutter/widgets.dart';

/// `--r:6px`
const double kRadius = 6;

/// `.panel{border-radius:8px}`
const double kPanelRadius = 8;

/// `--ui:'Segoe UI Variable Text','Segoe UI',system-ui,-apple-system,
///       'Helvetica Neue',sans-serif`
const String kUiFont = 'Segoe UI Variable Text';
const List<String> kUiFallback = <String>[
  'Segoe UI',
  'Helvetica Neue',
  'Arial',
];

/// `--mono:'Cascadia Mono',Consolas,'SF Mono',ui-monospace,'Roboto Mono',
///          monospace`
const String kMonoFont = 'Cascadia Mono';
const List<String> kMonoFallback = <String>[
  'Consolas',
  'SF Mono',
  'Roboto Mono',
  'Courier New',
];

/// `font-variant-numeric:tabular-nums`
const List<FontFeature> kTabular = <FontFeature>[FontFeature.tabularFigures()];

/// CSS `box-shadow` blur is twice the Gaussian sigma; Flutter's `blurRadius`
/// is converted with `sigma = blurRadius * 0.57735 + 0.5`. Scaling by 0.866
/// makes a Flutter shadow land on the same sigma as the CSS one, so the
/// panels have the same softness they do in the browser.
double _cssBlur(double cssPx) => cssPx * 0.866;

class HtColors {
  final Color bg;
  final Color panel;
  final Color panel2;
  final Color sunk;
  final Color line;
  final Color lineSoft;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color accent;
  final Color accentInk;
  final Color accentSoft;
  final Color pass;
  final Color fail;
  final Color warn;
  final Color hv;
  final Color idle;
  final Color passSoft;
  final Color failSoft;
  final Color hvSoft;
  final Color warnSoft;
  final Color gridEmpty;
  final Color scrim;
  final List<BoxShadow> shadow;

  /// `.mbox{box-shadow:0 24px 70px -22px rgba(0,0,0,.55)}`
  final List<BoxShadow> modalShadow;

  const HtColors({
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.sunk,
    required this.line,
    required this.lineSoft,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.pass,
    required this.fail,
    required this.warn,
    required this.hv,
    required this.idle,
    required this.passSoft,
    required this.failSoft,
    required this.hvSoft,
    required this.warnSoft,
    required this.gridEmpty,
    required this.scrim,
    required this.shadow,
    required this.modalShadow,
  });

  /// `:root` / `:root[data-theme="light"]`
  static final HtColors light = HtColors(
    bg: const Color(0xFFEFF4F5),
    panel: const Color(0xFFFFFFFF),
    panel2: const Color(0xFFE4EDEF),
    sunk: const Color(0xFFDCE7EA),
    line: const Color(0xFFC8D8DC),
    lineSoft: const Color(0xFFDFE9EB),
    ink: const Color(0xFF0C1A1E),
    ink2: const Color(0xFF3F565D),
    ink3: const Color(0xFF6C858C),
    accent: const Color(0xFF0B8296),
    accentInk: const Color(0xFFFFFFFF),
    accentSoft: const Color.fromRGBO(11, 130, 150, .11),
    pass: const Color(0xFF2A8452),
    fail: const Color(0xFFC0362D),
    warn: const Color(0xFF9A6B00),
    hv: const Color(0xFFC04A06),
    idle: const Color(0xFF93A8AE),
    passSoft: const Color.fromRGBO(42, 132, 82, .12),
    failSoft: const Color.fromRGBO(192, 54, 45, .11),
    hvSoft: const Color.fromRGBO(192, 74, 6, .12),
    warnSoft: const Color.fromRGBO(154, 107, 0, .12),
    gridEmpty: const Color(0xFFD3E0E3),
    scrim: const Color.fromRGBO(12, 26, 30, .45),
    // --shadow:0 1px 2px rgba(12,26,30,.07),0 8px 24px -14px rgba(12,26,30,.28)
    shadow: <BoxShadow>[
      BoxShadow(
        offset: const Offset(0, 1),
        blurRadius: _cssBlur(2),
        color: const Color.fromRGBO(12, 26, 30, .07),
      ),
      BoxShadow(
        offset: const Offset(0, 8),
        blurRadius: _cssBlur(24),
        spreadRadius: -14,
        color: const Color.fromRGBO(12, 26, 30, .28),
      ),
    ],
    modalShadow: <BoxShadow>[
      BoxShadow(
        offset: const Offset(0, 24),
        blurRadius: _cssBlur(70),
        spreadRadius: -22,
        color: const Color.fromRGBO(0, 0, 0, .55),
      ),
    ],
  );

  /// `@media (prefers-color-scheme:dark)` / `:root[data-theme="dark"]`
  static final HtColors dark = HtColors(
    bg: const Color(0xFF0B1114),
    panel: const Color(0xFF121B1F),
    panel2: const Color(0xFF18242A),
    sunk: const Color(0xFF0E171A),
    line: const Color(0xFF23343A),
    lineSoft: const Color(0xFF1B282D),
    ink: const Color(0xFFDEEAED),
    ink2: const Color(0xFF9AB0B7),
    ink3: const Color(0xFF6E878F),
    accent: const Color(0xFF2FB6C4),
    accentInk: const Color(0xFF04191C),
    accentSoft: const Color.fromRGBO(47, 182, 196, .14),
    pass: const Color(0xFF4FAF6D),
    fail: const Color(0xFFE8574C),
    warn: const Color(0xFFE0A32E),
    hv: const Color(0xFFFF8A3D),
    idle: const Color(0xFF57707A),
    passSoft: const Color.fromRGBO(79, 175, 109, .15),
    failSoft: const Color.fromRGBO(232, 87, 76, .14),
    hvSoft: const Color.fromRGBO(255, 138, 61, .15),
    warnSoft: const Color.fromRGBO(224, 163, 46, .14),
    gridEmpty: const Color(0xFF1B282D),
    scrim: const Color.fromRGBO(0, 0, 0, .62),
    // --shadow:0 1px 2px rgba(0,0,0,.4),0 10px 28px -16px rgba(0,0,0,.8)
    shadow: <BoxShadow>[
      BoxShadow(
        offset: const Offset(0, 1),
        blurRadius: _cssBlur(2),
        color: const Color.fromRGBO(0, 0, 0, .4),
      ),
      BoxShadow(
        offset: const Offset(0, 10),
        blurRadius: _cssBlur(28),
        spreadRadius: -16,
        color: const Color.fromRGBO(0, 0, 0, .8),
      ),
    ],
    modalShadow: <BoxShadow>[
      BoxShadow(
        offset: const Offset(0, 24),
        blurRadius: _cssBlur(70),
        spreadRadius: -22,
        color: const Color.fromRGBO(0, 0, 0, .55),
      ),
    ],
  );
}

/// Text styles, one per CSS rule that sets type.
class HtType {
  final HtColors c;
  const HtType(this.c);

  TextStyle ui({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) =>
      TextStyle(
        fontFamily: kUiFont,
        fontFamilyFallback: kUiFallback,
        fontSize: size,
        fontWeight: weight,
        color: color ?? c.ink,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration ?? TextDecoration.none,
      );

  TextStyle mono({
    double size = 12,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
    bool tabular = false,
    TextDecoration? decoration,
  }) =>
      TextStyle(
        fontFamily: kMonoFont,
        fontFamilyFallback: kMonoFallback,
        fontSize: size,
        fontWeight: weight,
        color: color ?? c.ink,
        letterSpacing: letterSpacing,
        height: height,
        fontFeatures: tabular ? kTabular : null,
        decoration: decoration ?? TextDecoration.none,
      );

  /// `body{font-size:14px;line-height:1.45}`
  TextStyle get body => ui(size: 14, height: 1.45);

  /// `.lbl{mono 10px 600 .13em uppercase ink-3 line-height:1}`
  TextStyle get lbl => mono(
        size: 10,
        weight: FontWeight.w600,
        letterSpacing: 1.3,
        color: c.ink3,
        height: 1,
      );

  /// `.num,.mono{tabular-nums}`
  TextStyle get num => mono(tabular: true);

  /// `.pill{mono 11px 600 .05em uppercase}`
  TextStyle pill(Color color) => mono(
        size: 11,
        weight: FontWeight.w600,
        letterSpacing: .55,
        color: color,
        height: 1.45,
      );

  /// `.btn{mono 11px 600 .06em uppercase}`
  TextStyle btn(Color color) => mono(
        size: 11,
        weight: FontWeight.w600,
        letterSpacing: .66,
        color: color,
      );

  /// `.btn.big{font-size:12px}`
  TextStyle btnBig(Color color) => mono(
        size: 12,
        weight: FontWeight.w600,
        letterSpacing: .72,
        color: color,
      );

  /// `.seg button{mono 11px 600 .05em uppercase}`
  TextStyle seg(Color color) => mono(
        size: 11,
        weight: FontWeight.w600,
        letterSpacing: .55,
        color: color,
      );

  /// `.tag{mono 10px 600 .06em uppercase}`
  TextStyle tag(Color color) => mono(
        size: 10,
        weight: FontWeight.w600,
        letterSpacing: .6,
        color: color,
      );

  /// `.panel > header h3{12px 650 .05em uppercase ink-2}`
  TextStyle get panelH3 => ui(
        size: 12,
        weight: FontWeight.w600,
        letterSpacing: .6,
        color: c.ink2,
      );

  /// `.kv dt{mono 10px 600 .1em uppercase ink-3}`
  TextStyle get kvDt => mono(
        size: 10,
        weight: FontWeight.w600,
        letterSpacing: 1.0,
        color: c.ink3,
      );

  /// `.kv dd{mono tabular 12.5px}`
  TextStyle get kvDd => mono(size: 12.5, tabular: true, color: c.ink);

  /// `.kv dd.big{font-size:16px}`
  TextStyle get kvDdBig => mono(size: 16, tabular: true, color: c.ink);

  /// `th{mono 9.5px 600 .12em uppercase ink-3}`
  TextStyle get th => mono(
        size: 9.5,
        weight: FontWeight.w600,
        letterSpacing: 1.14,
        color: c.ink3,
      );

  /// `td{12.5px}`
  TextStyle get td => ui(size: 12.5, color: c.ink);

  /// `td.n{mono tabular}`
  TextStyle get tdNum => mono(size: 12.5, tabular: true, color: c.ink);

  /// `.viewbar h2{18px 650 -.01em}`
  TextStyle get viewbarH2 =>
      ui(size: 18, weight: FontWeight.w600, letterSpacing: -.18);

  /// `.stgbadge{mono 10px 700 .12em uppercase}`
  TextStyle stgBadge(Color color) => mono(
        size: 10,
        weight: FontWeight.w700,
        letterSpacing: 1.2,
        color: color,
      );

  /// `.viewbar .why{mono 10.5px ink-3 line-height:1.4}`
  TextStyle get why =>
      mono(size: 10.5, color: c.ink3, height: 1.4);

  /// `.verdict h1{mono 42px 700 -.02em line-height:1}`
  TextStyle verdictH1(Color color) => mono(
        size: 42,
        weight: FontWeight.w700,
        letterSpacing: -.84,
        color: color,
        height: 1,
      );

  /// `.verdict .sub{13px ink-2}`
  TextStyle get verdictSub => ui(size: 13, color: c.ink2, height: 1.45);

  /// `.verdict .meta .v{mono tabular 15px}`
  TextStyle get verdictMeta => mono(size: 15, tabular: true, color: c.ink);

  /// `.act{mono 13px 700 .08em uppercase}`
  TextStyle act(Color color) => mono(
        size: 13,
        weight: FontWeight.w700,
        letterSpacing: 1.04,
        color: color,
      );

  /// `.act small{9px 600 .06em opacity .75}`
  TextStyle actSmall(Color color) => mono(
        size: 9,
        weight: FontWeight.w600,
        letterSpacing: .54,
        // ignore: deprecated_member_use
        color: color.withOpacity(.75),
      );

  /// `.conn{mono 13px 650 accent}`
  TextStyle conn(Color color) =>
      mono(size: 13, weight: FontWeight.w600, color: color);

  /// `.band .v{mono tabular 13px ink}`
  TextStyle get bandV => mono(size: 13, tabular: true, color: c.ink);

  /// `.path{mono 11px line-height:1.75 ink-2}`
  TextStyle get path => mono(size: 11, color: c.ink2, height: 1.75);

  /// `.netbar .kind{mono 9px 700 .12em uppercase}`
  TextStyle netbarKind(Color color) => mono(
        size: 9,
        weight: FontWeight.w700,
        letterSpacing: 1.08,
        color: color,
      );

  /// `.netbar .fname{mono 13px 650}`
  TextStyle netbarName(Color color) =>
      mono(size: 13, weight: FontWeight.w600, color: color);

  /// `.netbar .fmeta{mono 10.5px ink-3}`
  TextStyle get netbarMeta => mono(size: 10.5, color: c.ink3);

  /// `.netbar .uses{mono 10.5px ink-3 line-height:1.45}`
  TextStyle get netbarUses => mono(size: 10.5, color: c.ink3, height: 1.45);

  /// `.stagebox .tests{mono 11px ink-3 line-height:1.6}`
  TextStyle get stageTests => mono(size: 11, color: c.ink3, height: 1.6);

  /// `.stagebox .no{mono 10px 700}`
  TextStyle stageNo(Color color) =>
      mono(size: 10, weight: FontWeight.w700, color: color);

  /// `.gate span{mono 8px .1em uppercase line-height:1.3}`
  TextStyle gate(Color color) => mono(
        size: 8,
        letterSpacing: .8,
        color: color,
        height: 1.3,
      );

  /// `.domain .dh h4{13.5px 650}`
  TextStyle get domainH4 => ui(size: 13.5, weight: FontWeight.w600);

  /// `.domain .cond{mono 11px ink-3 line-height:1.6}`
  TextStyle get domainCond => mono(size: 11, color: c.ink3, height: 1.6);

  /// `.domain .stat b{mono tabular 25px 700 -.02em line-height:1}`
  TextStyle domainStat(Color color) => mono(
        size: 25,
        weight: FontWeight.w700,
        letterSpacing: -.5,
        color: color,
        tabular: true,
        height: 1,
      );

  /// `.domain .stat span{mono 11px ink-3}`
  TextStyle get domainStatUnit => mono(size: 11, color: c.ink3);

  /// `.domain .stg{mono 9px .1em uppercase ink-3}`
  TextStyle get domainStg =>
      mono(size: 9, letterSpacing: .9, color: c.ink3);

  /// `.domain .open{mono 10px .08em uppercase ink-3}`
  TextStyle domainOpen(Color color) =>
      mono(size: 10, letterSpacing: .8, color: color);

  /// `.fault .code{mono 11px 700}`
  TextStyle faultCode(Color color) =>
      mono(size: 11, weight: FontWeight.w700, color: color);

  /// `.fault .ttl{12.5px 600}`
  TextStyle get faultTitle => ui(size: 12.5, weight: FontWeight.w600);

  /// `.fault .det{mono 11px ink-3}`
  TextStyle get faultDetail => mono(size: 11, color: c.ink3);

  /// `.fault .val{mono tabular 12.5px}`
  TextStyle faultVal(Color color) =>
      mono(size: 12.5, tabular: true, color: color);

  /// `.empty{12.5px ink-3}`
  TextStyle get empty => ui(size: 12.5, color: c.ink3);

  /// `.tally b{mono tabular 20px 700 line-height:1}`
  TextStyle tally(Color color) => mono(
        size: 20,
        weight: FontWeight.w700,
        tabular: true,
        color: color,
        height: 1,
      );

  /// `.modesel .mt{13.5px 650}`
  TextStyle modeTitle(Color color) =>
      ui(size: 13.5, weight: FontWeight.w600, color: color);

  /// `.modesel .md{mono 11px ink-3 line-height:1.55}`
  TextStyle get modeDesc => mono(size: 11, color: c.ink3, height: 1.55);

  /// `.modesel .req{mono 10px .06em uppercase 600}`
  TextStyle modeReq(Color color) => mono(
        size: 10,
        weight: FontWeight.w600,
        letterSpacing: .6,
        color: color,
      );

  /// `.connrow .cid{mono 12px 650 accent}`
  TextStyle connId(Color color) =>
      mono(size: 12, weight: FontWeight.w600, color: color);

  /// `.connrow .cl{12.5px}`
  TextStyle get connLabel => ui(size: 12.5);

  /// `.connrow .cm{mono 10.5px ink-3}`
  TextStyle get connMeta => mono(size: 10.5, color: c.ink3);

  /// `.legend span{mono 10.5px ink-2}`
  TextStyle get legend => mono(size: 10.5, color: c.ink2);

  /// `.tip .tn{mono 12px 650}`
  TextStyle get tipName => mono(size: 12, weight: FontWeight.w600);

  /// `.tip .td{mono 10.5px ink-3 line-height:1.5}`
  TextStyle get tipDetail => mono(size: 10.5, color: c.ink3, height: 1.5);

  /// `.card-row .ch b{mono 12px 650}`
  TextStyle get cardName => mono(size: 12, weight: FontWeight.w600);

  /// `.relay-row .rl{mono 9.5px 600 .1em ink-3}`
  TextStyle get relayLabel => mono(
        size: 9.5,
        weight: FontWeight.w600,
        letterSpacing: .95,
        color: c.ink3,
      );

  /// `.hvgauge .big{mono tabular 34px 700 -.02em line-height:1}`
  TextStyle hvGauge(Color color) => mono(
        size: 34,
        weight: FontWeight.w700,
        letterSpacing: -.68,
        tabular: true,
        color: color,
        height: 1,
      );

  /// `.meter .v{mono tabular 21px -.02em line-height:1}`
  TextStyle meter(Color color) => mono(
        size: 21,
        tabular: true,
        letterSpacing: -.42,
        color: color,
        height: 1,
      );

  /// `.meter .v u{11px ink-3}`
  TextStyle get meterUnit => mono(size: 11, color: c.ink3);

  /// `.meter .rng{mono 10px ink-3}`
  TextStyle get meterRange => mono(size: 10, color: c.ink3);

  /// `.bus .id{mono 12px 650 accent}`
  TextStyle busId(Color color) =>
      mono(size: 12, weight: FontWeight.w600, color: color);

  /// `.bus .devs{mono 11px ink-3}`
  TextStyle get busDevs => mono(size: 11, color: c.ink3);

  /// `.bus .hz{mono tabular 11px ink-2}`
  TextStyle get busHz => mono(size: 11, tabular: true, color: c.ink2);

  /// `.ctl label{mono 10px 600 .1em uppercase ink-3}`
  TextStyle get ctlLabel => mono(
        size: 10,
        weight: FontWeight.w600,
        letterSpacing: 1.0,
        color: c.ink3,
      );

  /// `.out{mono tabular 13px}`
  TextStyle out(Color color) => mono(size: 13, tabular: true, color: color);

  /// `.blocker .id{mono 10.5px 700 warn}`
  TextStyle get blockerId =>
      mono(size: 10.5, weight: FontWeight.w700, color: c.warn);

  /// `.blocker p{12px ink-2 line-height:1.5}`
  TextStyle get blockerText => ui(size: 12, color: c.ink2, height: 1.5);

  /// `.mark span{13px 650 .02em}`
  TextStyle get markName =>
      ui(size: 13, weight: FontWeight.w600, letterSpacing: .26);

  /// `.mark em{mono 10px ink-3 .06em}`
  TextStyle get markSub =>
      mono(size: 10, color: c.ink3, letterSpacing: .6);

  /// `.mark b{mono 11px 700 accent-ink}`
  TextStyle get markBadge =>
      mono(size: 11, weight: FontWeight.w700, color: c.accentInk);

  /// `.slot .v{mono 12.5px}`
  TextStyle slotV(Color color) => mono(size: 12.5, color: color);

  /// `.hazard h2{14px 700 .1em uppercase hv}`
  TextStyle get hazardH2 => ui(
        size: 14,
        weight: FontWeight.w700,
        letterSpacing: 1.4,
        color: c.hv,
      );

  /// `.hazard p{11.5px ink-2}`
  TextStyle get hazardP => ui(size: 11.5, color: c.ink2);

  /// `.rail button span{mono 9px 600 .06em uppercase}`
  TextStyle rail(Color color) => mono(
        size: 9,
        weight: FontWeight.w600,
        letterSpacing: .54,
        color: color,
      );

  /// `.rail .stg{mono 8px .14em uppercase ink-3}`
  TextStyle get railStg =>
      mono(size: 8, letterSpacing: 1.12, color: c.ink3);

  /// `.logbar .head .line{mono 11.5px ink-2}`
  TextStyle get logLine => mono(size: 11.5, color: c.ink2);

  /// `.logbar .head button{mono 10px .1em uppercase ink-3}`
  TextStyle logButton(Color color) =>
      mono(size: 10, letterSpacing: 1.0, color: color);

  /// `.logbar .body{mono 11.5px line-height:1.65}`
  TextStyle logBody(Color color) =>
      mono(size: 11.5, color: color, height: 1.65);

  /// `.mbox h2{17px 650 -.01em}`
  TextStyle get modalH2 =>
      ui(size: 17, weight: FontWeight.w600, letterSpacing: -.17);

  /// `.mbox header p{12.5px ink-2 line-height:1.5}`
  TextStyle get modalP => ui(size: 12.5, color: c.ink2, height: 1.5);

  /// `.check .ct{12.5px 600}`
  TextStyle get checkTitle => ui(size: 12.5, weight: FontWeight.w600);

  /// `.check .cd{mono 11px ink-3}`
  TextStyle get checkDetail => mono(size: 11, color: c.ink3);

  /// `.check .cv{mono 11px 600}`
  TextStyle checkValue(Color color) =>
      mono(size: 11, weight: FontWeight.w600, color: color);

  /// `.check .ci{mono 11px 700}`
  TextStyle checkIcon(Color color) =>
      mono(size: 11, weight: FontWeight.w700, color: color);

  /// `.ack span{12.5px line-height:1.55}`
  TextStyle get ackText => ui(size: 12.5, height: 1.55);

  /// `.filerow .fn{mono 12.5px 600}`
  TextStyle get fileName => mono(size: 12.5, weight: FontWeight.w600);

  /// `.filerow .fd{mono 10.5px ink-3}`
  TextStyle get fileDetail => mono(size: 10.5, color: c.ink3);

  /// `.lockcard h3{15px 650}`
  TextStyle get lockH3 => ui(size: 15, weight: FontWeight.w600);

  /// `.lockcard p{12.5px ink-2 line-height:1.6}`
  TextStyle get lockP => ui(size: 12.5, color: c.ink2, height: 1.6);

  /// `.handover h2{16px 700}`
  TextStyle get handoverH2 => ui(size: 16, weight: FontWeight.w700);

  /// `.handover p{mono 12.5px ink-2}`
  TextStyle get handoverP => mono(size: 12.5, color: c.ink2);

  /// `.fan i{mono 10.5px}`
  TextStyle fan(Color color) => mono(size: 10.5, color: color);
}

/// Carries the active palette down the tree. `HtTheme.of(context)`.
class HtTheme extends InheritedWidget {
  final HtColors colors;
  final HtType type;
  final bool isDark;

  HtTheme({
    super.key,
    required this.isDark,
    required super.child,
  })  : colors = isDark ? HtColors.dark : HtColors.light,
        type = HtType(isDark ? HtColors.dark : HtColors.light);

  static HtTheme of(BuildContext context) {
    final t = context.dependOnInheritedWidgetOfExactType<HtTheme>();
    assert(t != null, 'HtTheme.of() called with no HtTheme above');
    return t!;
  }

  @override
  bool updateShouldNotify(HtTheme old) => old.isDark != isDark;
}

/// Shorthand: `final c = ctx.colors;`
extension HtThemeContext on BuildContext {
  HtColors get colors => HtTheme.of(this).colors;
  HtType get type => HtTheme.of(this).type;
  bool get isDark => HtTheme.of(this).isDark;
}
