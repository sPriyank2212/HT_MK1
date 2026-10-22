/// The design's own data model — fixture, harness nets and the two netlists.
///
/// Ported from the `<script>` block of `gui/htweb/index.html`. The seeded
/// harness must come out identical to the browser's, so [Mulberry32] below is
/// a bit-exact port of the page's PRNG: same 32-bit wrap-around, same
/// `Math.imul`, same call order. Change the order of the `next()` calls in
/// [buildNets] and you get a different demo harness.
library;

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// PRNG — bit-exact port of the page's mulberry32
// ---------------------------------------------------------------------------

int _toInt32(int v) => (v & 0xFFFFFFFF).toSigned(32);

/// JavaScript `>>>` on a 32-bit value.
int _ushr32(int v, int n) => (v & 0xFFFFFFFF) >> n;

/// JavaScript `Math.imul`.
int _imul(int a, int b) => _toInt32(_toInt32(a) * _toInt32(b));

/// ```js
/// function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;
///   let t=Math.imul(a^a>>>15,1|a);
///   t=t+Math.imul(t^t>>>7,61|t)^t;
///   return((t^t>>>14)>>>0)/4294967296}}
/// ```
class Mulberry32 {
  int _a;
  Mulberry32(int seed) : _a = _toInt32(seed);

  double next() {
    _a = _toInt32(_a);
    _a = _toInt32(_a + 0x6D2B79F5);
    var t = _imul(_a ^ _ushr32(_a, 15), 1 | _a);
    t = _toInt32(_toInt32(t + _imul(t ^ _ushr32(t, 7), 61 | t)) ^ t);
    return ((t ^ _ushr32(t, 14)) & 0xFFFFFFFF) / 4294967296.0;
  }
}

// ---------------------------------------------------------------------------
// FIXTURE
// ---------------------------------------------------------------------------

/// The board exposes 256 test points, but the operator never sees those — the
/// harness lands on real D-sub / circular / rectangular connectors. This
/// description comes from the fixture file, which is a third artifact: it maps
/// connector + pin -> board pin, and is a property of the FIXTURE, not of the
/// harness or the HV stack.
const double kPitch = 13;

/// The kinds of connector a harness end can land on. [term] is a screw /
/// spring terminal block, [mod] a modular or network jack (RJ45, USB...).
enum ConnType { dsub, circ, rect, term, mod }

const Map<ConnType, String> kTypeName = {
  ConnType.dsub: 'D-sub',
  ConnType.circ: 'Circular',
  ConnType.rect: 'Rectangular',
  ConnType.term: 'Terminal block',
  ConnType.mod: 'Modular jack',
};

class ConnectorDef {
  /// Unique key inside the fixture (what `PinRef.c` and `kConn` use). Usually
  /// the same as [name]; differs only when the same designator sits on BOTH
  /// harness ends (a mated pair's `DB15-1` at each end), where the second
  /// gets a suffix so the two stay distinct.
  final String id;

  /// What the operator reads on the diagram and in tables.
  final String name;
  final String label;
  final ConnType type;
  final int pins;

  /// The mating part number straight from the netlist's `Part Number`/`Part
  /// Number B` column (`GuessedConnector.partNumber`, `netlist_file.dart`)
  /// — empty when the file had none. Deliberately separate from [label]:
  /// `label` falls back to `id` (or an operator-typed friendly name, e.g.
  /// the demo fixture's "Engine bay") when there is no real part number, so
  /// using it as if it were a part number would show the connector id or a
  /// made-up name as though it were a catalog number.
  final String partNumber;

  /// "L" (harness end A / Side-A, the HI pins) or "R" (end B / Side-B, the LO
  /// pins).
  final String side;
  final int base;

  /// Signal name printed against a pin (the netlist's `Src Pin Label` /
  /// `Dst Pin Label` column), by pin number within this connector.
  final Map<int, String> pinLabels = <int, String>{};

  // Filled in by layoutFixture().
  double x = 0, y = 0, w = 0, h = 0;
  List<Offset2> pts = <Offset2>[];

  ConnectorDef({
    required this.id,
    String? name,
    required this.label,
    required this.type,
    required this.pins,
    required this.side,
    required this.base,
    this.partNumber = '',
  }) : name = name ?? id;
}

/// A plain point, so the model stays independent of dart:ui.
class Offset2 {
  final double x, y;
  const Offset2(this.x, this.y);
}

class FixtureDef {
  final String name;
  final String rev;
  final List<ConnectorDef> connectors;
  double midL = 0;
  double midR = 0;

  FixtureDef({
    required this.name,
    required this.rev,
    required this.connectors,
  });
}

/// Builds a [FixtureDef] with one continuous `base` sequence across *every*
/// connector, covering the full flat pin space (`J1` gets pins `1..N1`, `J2`
/// gets `N1+1..N1+N2`, and so on) rather than two independent per-side
/// halves — this is what the wire protocol actually addresses (`NETLIST ADD
/// <hi> <lo>`, one flat `1..256` space; `matrix_card.h`'s HI/LO banks are
/// separate mux trees, not separate pin-numbering spaces) and what a real
/// `required_format` netlist's `Src Pin #`/`Dst Pin #` columns already do
/// (confirmed 2026-08-14, GUI-08/CL-41: `DB15-1`→1..15, `DB15-2`→16..30,
/// `DB9`→31..39, sequential by connector order).
///
/// `side` is assigned by list-half (first half `L`, second half `R`) purely
/// for wiring-diagram layout balance (which half of the canvas a connector
/// face is drawn on) — it carries no electrical or pin-numbering meaning,
/// unlike `base`. List-half rather than alternating: alternating can badly
/// unbalance the two sides' *pin* totals when connector sizes vary widely
/// (a real regression caught by test — an 8-connector 37/37/24/30/25/25/
/// 19/59-pin split alternated down to a 105/151 pin imbalance instead of
/// the intended 128/128), whereas list-half reproduces the original
/// hand-authored demo fixture's own L/R split exactly.
FixtureDef buildFixture({
  required String name,
  required String rev,
  required List<({String id, String label, ConnType type, int pins})> defs,
}) {
  final connectors = <ConnectorDef>[];
  var base = 0;
  final leftCount = (defs.length / 2).ceil();
  for (var i = 0; i < defs.length; i++) {
    final d = defs[i];
    connectors.add(ConnectorDef(
      id: d.id,
      label: d.label,
      type: d.type,
      pins: d.pins,
      side: i < leftCount ? 'L' : 'R',
      base: base,
    ));
    base += d.pins;
  }
  return FixtureDef(name: name, rev: rev, connectors: connectors);
}

/// The demo/placeholder 8-connector layout — the fixture in effect before
/// any real netlist has ever been loaded, and what [kFix] starts out as.
/// Factored out (not just inlined into the `kFix` initializer below) so
/// tests that call [setActiveFixture] can restore it afterward, since
/// `kFix` is process-global mutable state now, not a per-instance one.
FixtureDef buildDefaultFixture() => buildFixture(
      name: 'FX-880-C.fixture',
      rev: 'C',
      defs: [
        (id: 'J1', label: 'Engine bay', type: ConnType.dsub, pins: 37),
        (id: 'J2', label: 'Airframe', type: ConnType.dsub, pins: 37),
        (id: 'J3', label: 'Sensors', type: ConnType.circ, pins: 24),
        (id: 'J4', label: 'Power', type: ConnType.rect, pins: 30),
        (id: 'J5', label: 'Avionics A', type: ConnType.dsub, pins: 25),
        (id: 'J6', label: 'Avionics B', type: ConnType.dsub, pins: 25),
        (id: 'J7', label: 'Lighting', type: ConnType.circ, pins: 19),
        (id: 'J8', label: 'Main bundle', type: ConnType.rect, pins: 59),
      ],
    );

/// The active fixture. Mutable (not `const`/`final`) — [setActiveFixture]
/// swaps it (and the four derived bindings below) at runtime once a real
/// netlist's connector layout has been inferred and confirmed
/// (`AppState`).
FixtureDef kFix = buildDefaultFixture();

Map<String, ConnectorDef> kConn = {for (final c in kFix.connectors) c.id: c};
List<ConnectorDef> kConnsL =
    kFix.connectors.where((c) => c.side == 'L').toList();
List<ConnectorDef> kConnsR =
    kFix.connectors.where((c) => c.side == 'R').toList();
int kFixPins = kFix.connectors.fold<int>(0, (a, c) => a + c.pins);

/// Swaps the active fixture. Every consumer (`layoutFixture`/`connSize`/
/// `pinXY` below, `painters.dart`, `cont_view.dart`, `app_state.dart`)
/// reads `kFix`/`kConn`/`kConnsL`/`kConnsR`/`kFixPins` by name, so
/// reassigning these five bindings and relaying out is everything needed —
/// no parameter threading through the geometry/paint code.
void setActiveFixture(FixtureDef next) {
  kFix = next;
  kConn = {for (final c in kFix.connectors) c.id: c};
  kConnsL = kFix.connectors.where((c) => c.side == 'L').toList();
  kConnsR = kFix.connectors.where((c) => c.side == 'R').toList();
  kFixPins = kFix.connectors.fold<int>(0, (a, c) => a + c.pins);
  layoutFixture();
}

// ---------------------------------------------------------------------------
// NETS
// ---------------------------------------------------------------------------

const List<String> kNames = [
  'PWR_28V_A', 'PWR_28V_B', 'GND_RET', 'ARINC_A_HI', 'ARINC_A_LO', 'LAMP_CMD',
  'LAMP_RET', 'SENSE_RTD_1', 'SENSE_RTD_2', 'FUEL_LVL', 'OIL_PRESS',
  'FIRE_LOOP_A', 'FIRE_LOOP_B', 'STARTER_CMD', 'GEN_FIELD', 'BUS_TIE',
  'PITOT_HEAT', 'NAV_LT', 'BEACON', 'STROBE', 'INTERCOM_HI', 'INTERCOM_LO',
];

const List<String> kWireGauges = [
  '14 AWG',
  '18 AWG',
  '22 AWG',
  '24 AWG TSP',
  '26 AWG',
];

/// A connector + pin address, `{c:"J1", p:14}` in the page.
class PinRef {
  final String c;
  final int p;
  const PinRef(this.c, this.p);

  @override
  bool operator ==(Object other) =>
      other is PinRef && other.c == c && other.p == p;
  @override
  int get hashCode => Object.hash(c, p);
}

/// One (hi, lo) pair of a net, resolved onto the fixture's connectors.
class NetPair {
  final int hi;
  final int lo;
  final PinRef src;
  final PinRef dst;
  final String? srcLabel;
  final String? dstLabel;
  const NetPair({
    required this.hi,
    required this.lo,
    required this.src,
    required this.dst,
    this.srcLabel,
    this.dstLabel,
  });

  String get key => '$hi:$lo';
}

class Net {
  String name;
  PinRef src;
  List<PinRef> dsts;

  /// Further source pins when several wires converge on one destination (the
  /// mirror image of a Y branch), or several on each end (a multi-drop bus).
  /// Empty for the common one-source net.
  List<PinRef> srcExtra;

  /// The netlist rows this net is made of, one per (hi, lo) pair, so a result
  /// for a single pair can be attributed to the right branch. Empty for the
  /// built-in demo harness.
  List<NetPair> pairs;

  /// `hi:lo` keys of pairs that came back open on the last run.
  final Set<String> openPairs = <String>{};

  /// `hi:lo` keys of pairs the last run has reported on at all (pass or
  /// open) — what turns a wire from "not tested" grey to pass/fail colour.
  final Set<String> reportedPairs = <String>{};

  /// The netlist's free-text detail for this net (`crossed pin 5 -> 8`,
  /// `twisted pair`, ...), display only.
  String? detail;

  /// The x of this net's vertical run (or spine), set by [routeNets]. Null for
  /// a wire that needs none because both pins are on the same row.
  double? laneX;

  /// "Y" branch splice (one-to-many or many-to-one), "M" multi-drop node,
  /// "I" inline splice, or null for point to point.
  String? joint;

  int hs;
  int ls;
  double r;
  double v;
  double ins;
  double rmin;
  double rmax;
  String wire;
  bool open;
  int card;
  int relay;

  /// Set by [AppState._onInsul] from a real `!INSUL ... fail` result. No
  /// "marginal" tier exists here (unlike the resistance ranked table) -
  /// InsulStatus on the wire is pass/fail only, see htproto/codec.dart.
  bool insFail;

  /// Set by [rebuildNets] only: the instrument's own 1..256 pin numbers.
  int? pinHi;
  int? pinLo;

  Net({
    required this.name,
    required this.src,
    required this.dsts,
    this.srcExtra = const <PinRef>[],
    this.pairs = const <NetPair>[],
    this.detail,
    this.joint,
    required this.hs,
    required this.ls,
    required this.r,
    required this.v,
    required this.ins,
    this.rmin = 0.05,
    this.rmax = 2.00,
    required this.wire,
    this.open = false,
    this.card = 0,
    this.relay = 0,
    this.insFail = false,
    this.pinHi,
    this.pinLo,
  });
}

extension NetEnds on Net {
  /// Every source pin of this net (HI side).
  List<PinRef> get srcs => <PinRef>[src, ...srcExtra];

  /// Whether the wire to/from [leaf] failed on the last run. A net built from
  /// netlist rows answers per branch; the demo harness has only the net-level
  /// [open] flag.
  bool pinOpen(PinRef leaf) {
    if (pairs.isEmpty) return open;
    for (final p in pairs) {
      if ((p.src == leaf || p.dst == leaf) && openPairs.contains(p.key)) {
        return true;
      }
    }
    return false;
  }

  /// Whether the last run has reported on the wire to/from [leaf] yet.
  bool pinReported(PinRef leaf) {
    for (final p in pairs) {
      if ((p.src == leaf || p.dst == leaf) && reportedPairs.contains(p.key)) {
        return true;
      }
    }
    return false;
  }

  /// Forget the last run's results (a new run starts, or the screen resets).
  void clearResults() {
    openPairs.clear();
    reportedPairs.clear();
    if (pairs.isNotEmpty) open = false;
  }
}

/// The name shown for a connector key (`PinRef.c`) — the designator the
/// operator knows, without the disambiguating suffix a second-end connector
/// of the same name carries internally.
String connName(String key) => kConn[key]?.name ?? key;

/// `refOf` — `J1-14`
String refOf(PinRef nd) =>
    '${connName(nd.c)}-${nd.p.toString().padLeft(2, '0')}';

String pad(int v, int width) => v.toString().padLeft(width, '0');

/// Build the demo harness. Same call order as the page's IIFE, so the same
/// numbers come out.
List<Net> buildNets() {
  final nets = <Net>[];
  final rnd = Mulberry32(880);
  final freeL = <PinRef>[];
  final freeR = <PinRef>[];
  for (final c in kConnsL) {
    for (var p = 1; p <= c.pins; p++) {
      freeL.add(PinRef(c.id, p));
    }
  }
  for (final c in kConnsR) {
    for (var p = 1; p <= c.pins; p++) {
      freeR.add(PinRef(c.id, p));
    }
  }

  // const take=a=>a.splice((rnd()*a.length)|0,1)[0];
  PinRef? take(List<PinRef> a) {
    if (a.isEmpty) return null;
    final i = (rnd.next() * a.length).toInt();
    return a.removeAt(i);
  }

  const netc = 118;
  for (var k = 0; k < netc; k++) {
    final src = take(freeL);
    final dst = take(freeR);
    if (src == null || dst == null) break;
    nets.add(Net(
      name: k < kNames.length ? kNames[k] : 'NET_${pad(k + 1, 3)}',
      src: src,
      dsts: [dst],
      joint: null,
      hs: kConn[src.c]!.base + src.p - 1,
      ls: kConn[dst.c]!.base + dst.p - 1,
      // Order matters: r, v, ins, then wire.
      r: 0.05 + rnd.next() * 1.55,
      v: 0.09 + rnd.next() * 0.42,
      ins: 12 + rnd.next() * 180,
      rmin: 0.05,
      rmax: 2.00,
      wire: kWireGauges[(rnd.next() * 5).toInt()],
      open: false,
      card: 0,
      relay: 0,
    ));
  }

  // six Y joints — one source branching to two or three destinations
  const yJoints = [3, 11, 24, 47, 68, 93];
  for (var k = 0; k < yJoints.length; k++) {
    final i = yJoints[k];
    if (i >= nets.length) continue;
    final extra = k % 2 != 0 ? 2 : 1;
    for (var j = 0; j < extra; j++) {
      final d = take(freeR);
      if (d != null) nets[i].dsts.add(d);
    }
    nets[i].joint = 'Y';
    if (nets[i].dsts.length > 1 && !kNames.contains(nets[i].name)) {
      nets[i].name = 'SPLICE_${pad(i, 3)}';
    }
  }
  nets[11].name = 'SPLICE_28V';

  // four I joints — inline butt splices on a point-to-point run
  for (final i in [7, 19, 55, 102]) {
    if (i < nets.length && nets[i].dsts.length == 1) nets[i].joint = 'I';
  }

  // HV relay assignment is a direct function of the source pin's own flat
  // board position (`hs`, already 0-based) - not the net's position in this
  // list. VERIFY: mirrors the same 64-pins-per-card sequential-block pattern
  // the connector allocation above uses, not yet confirmed against real HV
  // harness wiring/schematics (see BU- bring-up items in PROJECT_LOG.md).
  for (var i = 0; i < nets.length; i++) {
    nets[i].card = nets[i].hs ~/ 64;
    nets[i].relay = nets[i].hs % 64;
  }

  // seeded faults
  nets[4].open = true; // ARINC_A_LO open
  nets[5].r = 4.812; // LAMP_CMD resistance high
  nets[2].ins = 3.2; // GND_RET insulation low
  const worst = [1.91, 1.87, 1.78, 1.72, 1.66];
  const worstIdx = [9, 14, 21, 33, 40];
  for (var k = 0; k < worstIdx.length; k++) {
    if (worstIdx[k] < nets.length) nets[worstIdx[k]].r = worst[k];
  }
  return nets;
}

/// `netAt` — "J1:14" -> net (any node)
Map<String, Net> buildNetAt(List<Net> nets) {
  final map = <String, Net>{};
  for (final n in nets) {
    for (final s in n.srcs) {
      map['${s.c}:${s.p}'] = n;
    }
    for (final d in n.dsts) {
      map['${d.c}:${d.p}'] = n;
    }
  }
  return map;
}

// ---------------------------------------------------------------------------
// TWO NETLISTS
// ---------------------------------------------------------------------------

/// MTX  · harness on the matrix side — HS/LS pin pairs and R limits. Shared by
///        continuity and resistance; both read the same file.
/// HV   · the same harness against the HV stack — card, HS relay and the LS
///        relays that form each net's return. Separate file because the map
///        changes with a 1..4 card stack.
///
/// The pair is cross-checked at run time: the HV file declares a card count,
/// and it must match the stack detected on I2C2.
class MtxNetlist {
  bool loaded;
  String? name;
  int nets;
  int pins;
  String? time;

  /// "file" or "cross"
  String origin;

  MtxNetlist({
    required this.loaded,
    this.name,
    required this.nets,
    required this.pins,
    this.time,
    this.origin = 'file',
  });
}

class HvNetlist {
  bool loaded;
  String? name;
  int nets;
  int cards;
  String? time;

  HvNetlist({
    required this.loaded,
    this.name,
    this.nets = 0,
    this.cards = 0,
    this.time,
  });
}

class FixNetlist {
  bool loaded;
  String name;
  int conns;
  int pins;
  String? time;

  FixNetlist({
    required this.loaded,
    required this.name,
    required this.conns,
    required this.pins,
    this.time,
  });
}

/// `USES` — what each netbar says the file is for.
const Map<String, String> kUses = {
  'run': 'continuity + resistance read this file',
  'cont': 'expected pairs and isolation checks',
  'res': 'pair list and per-net R limits',
  'progM': 'the J-MTX side of the harness',
  'hv': 'card + relay map and the LS return pattern',
  'progH': 'the J-HV side, sized to the fitted stack',
};

/// `clock()` — the page uses `toLocaleTimeString` with 2-digit h/m/s.
String clock() {
  final t = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

// ---------------------------------------------------------------------------
// CONNECTOR GEOMETRY
// ---------------------------------------------------------------------------

/// Every connector is one vertical column of pins — pin 1 at the top, one row
/// per pin at [kPitch] spacing — whatever its real shape. A real fixture can
/// put well over a hundred pins on a single connector, and a
/// physically-accurate footprint at that count would be wide enough to
/// overlap its neighbours; a single column scales to any pin count by getting
/// taller, never wider, and reads as a straight ladder: tracing a net across
/// the canvas is "find the wire", not "find the pin inside a D-shell".
///
/// What says what the connector IS — D-sub, circular, rectangular, terminal
/// block, modular jack — is its outline and the pictogram in its header
/// (painters.dart), and its type/pin-count line, not the pin arrangement.
///
/// The harness always has TWO ends: Side-A connectors in the left column (the
/// HI pins) and Side-B connectors in the right (the LO pins). A designator
/// used at both ends is drawn once in each column.
///
/// Dots sit on each connector's wire-facing edge; the pin number sits beside
/// the dot and the signal label (from the netlist) outboard of it.
const double kConnW = 176;

/// Header zone above each connector's pin column: pictogram on the left,
/// designator / part number / type-and-pin-count lines beside it.
const double kConnHeaderH = 46;

/// Space at the top of the canvas for the "SIDE A" / "SIDE B" column titles.
const double kColTitleH = 22;

({double w, double h}) connSize(ConnectorDef c) => (
      w: kConnW,
      // header + a small first-pin inset (7) + the pin column itself + a
      // 20px margin below the last pin to the shell's bottom edge.
      h: kConnHeaderH + 7 + (c.pins - 1) * kPitch + 20,
    );

double layoutConn(ConnectorDef c, double x, double y) {
  final s = connSize(c);
  c.x = x;
  c.y = y;
  c.w = s.w;
  c.h = s.h;
  c.pts = <Offset2>[];
  final top = y + kConnHeaderH;
  final dotX = c.side == 'L' ? x + s.w - 14 : x + 14;
  for (var i = 0; i < c.pins; i++) {
    c.pts.add(Offset2(dotX, top + 7 + i * kPitch));
  }
  return y + s.h + 18;
}

/// `const CW=1060, CH=440;` — width is fixed (the widget always scales it to
/// fill the panel), but height is not: [layoutFixture] grows it to fit
/// however tall the current fixture's pin columns actually are, with 440 as
/// a floor so the original 8-connector demo fixture keeps its original
/// canvas size.
const double kCanvasW = 1060;
double kCanvasH = 440;

void layoutFixture() {
  final lh = kConnsL.fold<double>(-18, (a, c) => a + connSize(c).h + 18);
  final rh = kConnsR.fold<double>(-18, (a, c) => a + connSize(c).h + 18);

  kCanvasH = math.max(440.0, math.max(lh, rh) + 28 + kColTitleH);

  // Both columns start at the top (under the titles), not centred: with
  // columns of different heights, centring floated the shorter one down the
  // middle of nowhere.
  var y = kColTitleH + 14.0;
  for (final c in kConnsL) {
    y = layoutConn(c, 16, y);
  }
  y = kColTitleH + 14.0;
  for (final c in kConnsR) {
    y = layoutConn(c, kCanvasW - 16 - kConnW, y);
  }
  kFix.midL = 16 + kConnW;
  kFix.midR = kCanvasW - 16 - kConnW;
  _reroute();
}

Offset2 pinXY(PinRef nd) {
  final c = kConn[nd.c]!;
  if (nd.p - 1 < 0 || nd.p - 1 >= c.pts.length) return const Offset2(0, 0);
  return c.pts[nd.p - 1];
}

// ---------------------------------------------------------------------------
// wire paths, joints and hit samples
// ---------------------------------------------------------------------------

/// Point on the cubic the page draws between two pins.
Offset2 bez(Offset2 p0, Offset2 p1, double t) {
  final dx = (p1.x - p0.x) * 0.45;
  final c0 = Offset2(p0.x + dx, p0.y);
  final c1 = Offset2(p1.x - dx, p1.y);
  final u = 1 - t;
  return Offset2(
    u * u * u * p0.x + 3 * u * u * t * c0.x + 3 * u * t * t * c1.x + t * t * t * p1.x,
    u * u * u * p0.y + 3 * u * u * t * c0.y + 3 * u * t * t * c1.y + t * t * t * p1.y,
  );
}

/// Wires are routed like a schematic, not drawn as curves: a wire leaves its
/// pin horizontally, runs vertically down its own lane in the channel between
/// the two connector columns, and enters the other pin horizontally. Wires
/// that overlap in height therefore read as clean parallel lines, each in its
/// own lane, instead of curves sagging across one another.
class NetSegments {
  /// Each wire as a polyline of two or more points.
  final List<List<Offset2>> segs;

  /// The pin each polyline ends on, or null for a shared trunk or spine —
  /// lets a Y branch be painted pass/fail on its own.
  final List<PinRef?> leaves;

  /// Where the joint marker sits (the spine tap, a multi-drop node, an inline
  /// splice), or null for a plain wire.
  final Offset2? joint;

  /// Where a branch leaves the spine part-way along it: small T-junction dots.
  final List<Offset2> junctions;

  /// 'Y' (one-to-many or many-to-one), 'M' (multi-drop), 'I' (inline splice)
  /// or null for a plain point-to-point wire.
  final String? kind;
  const NetSegments(this.segs, this.joint, this.kind,
      [this.leaves = const <PinRef?>[],
      this.junctions = const <Offset2>[]]);
}

/// The wire channel runs between the two columns of pin dots.
const double _kChannelPad = 24;

Offset2? _pinOrNull(PinRef p) {
  final c = kConn[p.c];
  if (c == null || p.p - 1 < 0 || p.p - 1 >= c.pts.length) return null;
  return c.pts[p.p - 1];
}

List<Net> _routed = <Net>[];

/// Assigns every net a vertical lane in the channel between the connector
/// columns. Call after a netlist is loaded; [layoutFixture] re-runs it
/// whenever the geometry changes.
///
/// Lane order is what keeps the picture tidy: wires that run down the page are
/// stacked so the topmost one takes the outermost lane (so its horizontal legs
/// never cut across a lower wire's vertical run), and likewise upward wires
/// with the lowest outermost. Wires that join several pins (Y, merge,
/// multi-drop) share one vertical spine and sit between the two groups.
void routeNets(List<Net> nets) {
  _routed = nets;
  _reroute();
}

void _reroute() {
  const xa = 16 + kConnW - 14; // Side A pin dots
  const xb = kCanvasW - 16 - kConnW + 14; // Side B pin dots

  final down = <({Net n, double key})>[];
  final up = <({Net n, double key})>[];
  final spine = <({Net n, double key})>[];

  for (final n in _routed) {
    n.laneX = null;
    final s = [for (final p in n.srcs) _pinOrNull(p)];
    final d = [for (final p in n.dsts) _pinOrNull(p)];
    if (s.contains(null) || d.contains(null)) continue;
    final sy = s.map((p) => p!.y).toList();
    final dy = d.map((p) => p!.y).toList();
    if (sy.length == 1 && dy.length == 1) {
      if ((sy[0] - dy[0]).abs() < 0.5) continue; // straight across
      (dy[0] > sy[0] ? down : up).add((n: n, key: sy[0]));
    } else {
      final all = [...sy, ...dy];
      spine.add((n: n, key: all.reduce((a, b) => a + b) / all.length));
    }
  }
  down.sort((a, b) => a.key.compareTo(b.key));
  up.sort((a, b) => b.key.compareTo(a.key));
  spine.sort((a, b) => a.key.compareTo(b.key));

  final groups = [down, spine, up].where((g) => g.isNotEmpty).length;
  final lanes = down.length + spine.length + up.length;
  if (lanes == 0) return;
  final gapSlots = (groups - 1) * 2;
  const c0 = xa + _kChannelPad;
  const c1 = xb - _kChannelPad;
  final pitch = ((c1 - c0) / (lanes + gapSlots + 1)).clamp(2.6, 7.0);
  final block = (lanes - 1 + gapSlots) * pitch;
  final start = (c0 + c1) / 2 - block / 2;

  var slot = 0;
  void place(List<({Net n, double key})> group, {required bool reversed}) {
    for (var i = 0; i < group.length; i++) {
      final at = reversed ? group.length - 1 - i : i;
      group[i].n.laneX = start + (slot + at) * pitch;
    }
    slot += group.length + 2;
  }

  if (down.isNotEmpty) place(down, reversed: true);
  if (spine.isNotEmpty) place(spine, reversed: false);
  if (up.isNotEmpty) place(up, reversed: true);
}

/// The middle of a polyline, by length — where a net-name plate sits.
Offset2 polyMid(List<Offset2> pts) {
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += (pts[i].x - pts[i - 1].x).abs() + (pts[i].y - pts[i - 1].y).abs();
  }
  var left = total / 2;
  for (var i = 1; i < pts.length; i++) {
    final seg = (pts[i].x - pts[i - 1].x).abs() + (pts[i].y - pts[i - 1].y).abs();
    if (seg >= left && seg > 0) {
      final t = left / seg;
      return Offset2(pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t,
          pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t);
    }
    left -= seg;
  }
  return pts.first;
}

/// The wires of one net.
///
///  * 1 source, 1 destination — one wire, straight across when both pins are
///    on the same row, otherwise out / down its lane / in. An inline splice
///    marks the first horizontal leg;
///  * 1 source, N destinations — a Y: the source runs to a vertical spine and
///    each destination branches off it;
///  * N sources, 1 destination — the same Y mirrored;
///  * N sources, M destinations — a multi-drop node: every pin branches off
///    one spine.
NetSegments netSegments(Net n) {
  final srcPins = n.srcs;
  final dstPins = n.dsts;
  final s = srcPins.map(pinXY).toList();
  final d = dstPins.map(pinXY).toList();
  final xa = s.first.x;
  final xb = d.first.x;
  final lane = n.laneX ?? (xa + xb) / 2;

  if (s.length == 1 && d.length == 1) {
    final straight = (s[0].y - d[0].y).abs() < 0.5;
    final List<Offset2> line = straight
        ? [s[0], d[0]]
        : [s[0], Offset2(lane, s[0].y), Offset2(lane, d[0].y), d[0]];
    final Offset2? mark = n.joint == 'I'
        ? (straight
            ? Offset2((xa + xb) / 2, s[0].y)
            : Offset2((xa + lane) / 2, s[0].y))
        : null;
    return NetSegments([line], mark, mark == null ? null : 'I', [dstPins[0]]);
  }

  final all = [...s, ...d];
  final ymin = all.map((p) => p.y).reduce(math.min);
  final ymax = all.map((p) => p.y).reduce(math.max);
  final segs = <List<Offset2>>[];
  final leaves = <PinRef?>[];
  final junctions = <Offset2>[];

  Offset2 tap(Offset2 p) => Offset2(lane, p.y);
  void branch(Offset2 pin, PinRef? leaf, {required bool fromSide}) {
    segs.add(fromSide ? [pin, tap(pin)] : [tap(pin), pin]);
    leaves.add(leaf);
    if (pin.y > ymin + 0.5 && pin.y < ymax - 0.5) junctions.add(tap(pin));
  }

  final String kind;
  final Offset2 joint;
  if (s.length == 1) {
    kind = 'Y';
    branch(s[0], null, fromSide: true);
    for (var i = 0; i < d.length; i++) {
      branch(d[i], dstPins[i], fromSide: false);
    }
    joint = tap(s[0]);
  } else if (d.length == 1) {
    kind = 'Y';
    for (var i = 0; i < s.length; i++) {
      branch(s[i], srcPins[i], fromSide: true);
    }
    branch(d[0], null, fromSide: false);
    joint = tap(d[0]);
  } else {
    kind = 'M';
    for (var i = 0; i < s.length; i++) {
      branch(s[i], srcPins[i], fromSide: true);
    }
    for (var i = 0; i < d.length; i++) {
      branch(d[i], dstPins[i], fromSide: false);
    }
    joint = Offset2(lane, (ymin + ymax) / 2);
  }
  // the spine itself, shared by every branch
  segs.add([Offset2(lane, ymin), Offset2(lane, ymax)]);
  leaves.add(null);
  return NetSegments(segs, joint, kind, leaves, junctions);
}
