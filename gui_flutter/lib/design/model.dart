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

enum ConnType { dsub, circ, rect }

const Map<ConnType, String> kTypeName = {
  ConnType.dsub: 'D-sub',
  ConnType.circ: 'Circular 38999',
  ConnType.rect: 'Amphenol rect',
};

class ConnectorDef {
  final String id;
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

  /// "L" or "R"
  final String side;
  final int base;

  // Filled in by layoutFixture().
  double x = 0, y = 0, w = 0, h = 0;
  List<Offset2> pts = <Offset2>[];

  ConnectorDef({
    required this.id,
    required this.label,
    required this.type,
    required this.pins,
    required this.side,
    required this.base,
    this.partNumber = '',
  });
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

class Net {
  String name;
  PinRef src;
  List<PinRef> dsts;

  /// "Y" branch splice, "I" inline splice, or null for point to point.
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

/// `refOf` — `J1-14`
String refOf(PinRef nd) => '${nd.c}-${nd.p.toString().padLeft(2, '0')}';

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
    map['${n.src.c}:${n.src.p}'] = n;
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

/// Every connector is one vertical column of pins — pin 1 at the top, last
/// pin at the bottom, one row per pin at [kPitch] spacing — not laid out to
/// its real physical footprint (a staggered D-shell, concentric rings, a
/// grid). A real fixture can put well over a hundred pins on a single
/// connector (`required_format/netlist_full_256x256.xlsx`'s 128-pin
/// blocks), and a physically-accurate footprint at that pin count is wide
/// enough to overlap its neighbours on screen — a two-row D-sub shell alone
/// comes out ~860px wide at 128 pins, most of the whole canvas. A single
/// column scales to any pin count by getting taller, never wider, and it
/// reads as a straight ladder: Side-A's pin N sits at the same kind of
/// position Side-B's pin N would, so tracing a net across the canvas is
/// "find the wire," not "find the pin inside a D-shell or a ring." Dots sit
/// on each connector's canvas-facing edge (right edge for a left-column
/// connector, left edge for a right-column one) so wires start/end right at
/// the shell and the outward edge is free for painters.dart's pin-number
/// labels. `kTypeName`/`ConnType` still say what the connector actually is
/// in the meta text — this only changed how pins are drawn, not what a
/// connector is.
const double kConnW = 92;

/// Header zone above each connector's pin column — the id/label line plus
/// the type/pin-count meta line below it (painters.dart's
/// `_paintConnectors`, which reads this same constant for the shell's
/// top edge).
const double kConnHeaderH = 32;

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

  kCanvasH = math.max(440.0, math.max(lh, rh) + 28);

  var y = math.max(14.0, (kCanvasH - lh) / 2);
  for (final c in kConnsL) {
    y = layoutConn(c, 16, y);
  }
  y = math.max(14.0, (kCanvasH - rh) / 2);
  for (final c in kConnsR) {
    y = layoutConn(c, kCanvasW - 16 - kConnW, y);
  }
  kFix.midL = 16 + kConnW;
  kFix.midR = kCanvasW - 16 - kConnW;
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

class NetSegments {
  final List<List<Offset2>> segs;
  final Offset2? joint;
  final String? kind;
  const NetSegments(this.segs, this.joint, this.kind);
}

NetSegments netSegments(Net n) {
  final s = pinXY(n.src);
  final ds = n.dsts.map(pinXY).toList();
  if (n.joint == 'Y' && ds.length > 1) {
    final j = Offset2(
      (s.x + ds.fold<double>(0, (a, d) => a + d.x) / ds.length) / 2,
      (s.y + ds.fold<double>(0, (a, d) => a + d.y) / ds.length) / 2,
    );
    return NetSegments(
      [
        [s, j],
        ...ds.map((d) => [j, d]),
      ],
      j,
      'Y',
    );
  }
  return NetSegments(
    ds.map((d) => [s, d]).toList(),
    n.joint == 'I' ? bez(s, ds[0], 0.5) : null,
    n.joint,
  );
}
