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

final FixtureDef kFix = FixtureDef(
  name: 'FX-880-C.fixture',
  rev: 'C',
  connectors: [
    ConnectorDef(id: 'J1', label: 'Engine bay', type: ConnType.dsub, pins: 37, side: 'L', base: 0),
    ConnectorDef(id: 'J2', label: 'Airframe', type: ConnType.dsub, pins: 37, side: 'L', base: 37),
    ConnectorDef(id: 'J3', label: 'Sensors', type: ConnType.circ, pins: 24, side: 'L', base: 74),
    ConnectorDef(id: 'J4', label: 'Power', type: ConnType.rect, pins: 30, side: 'L', base: 98),
    ConnectorDef(id: 'J5', label: 'Avionics A', type: ConnType.dsub, pins: 25, side: 'R', base: 0),
    ConnectorDef(id: 'J6', label: 'Avionics B', type: ConnType.dsub, pins: 25, side: 'R', base: 25),
    ConnectorDef(id: 'J7', label: 'Lighting', type: ConnType.circ, pins: 19, side: 'R', base: 50),
    ConnectorDef(id: 'J8', label: 'Main bundle', type: ConnType.rect, pins: 59, side: 'R', base: 69),
  ],
);

final Map<String, ConnectorDef> kConn = {
  for (final c in kFix.connectors) c.id: c
};
final List<ConnectorDef> kConnsL =
    kFix.connectors.where((c) => c.side == 'L').toList();
final List<ConnectorDef> kConnsR =
    kFix.connectors.where((c) => c.side == 'R').toList();
final int kFixPins =
    kFix.connectors.fold<int>(0, (a, c) => a + c.pins);

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

  // HV relay assignment follows the source connector order
  for (var i = 0; i < nets.length; i++) {
    nets[i].card = i ~/ 64;
    nets[i].relay = i % 64;
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

class HvFile {
  final String name;
  final int cards;
  final int nets;
  final String note;
  const HvFile(this.name, this.cards, this.nets, this.note);
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

/// Each connector type gets a real face: D-subs are two staggered rows in a D
/// shell, circulars are concentric rings filled from the outside in,
/// rectangulars are a grid. Pin coordinates are cached so wires can be drawn
/// straight onto them.
class _Rings {
  final double r;
  final List<({double r, int c})> caps;
  const _Rings(this.r, this.caps);
}

_Rings _circRings(int n) {
  for (var rr = kPitch; rr < 400; rr += kPitch * 0.5) {
    final caps = <({double r, int c})>[];
    var tot = 1;
    for (var r = rr; r >= kPitch * 0.9; r -= kPitch * 0.95) {
      final c = (2 * math.pi * r / kPitch).floor();
      caps.add((r: r, c: c));
      tot += c;
    }
    if (tot >= n) return _Rings(rr, caps);
  }
  return const _Rings(kPitch, []);
}

({double w, double h}) connSize(ConnectorDef c) {
  if (c.type == ConnType.dsub) {
    final n1 = (c.pins / 2).ceil();
    return (w: n1 * kPitch + 30, h: 2 * kPitch + 34);
  }
  if (c.type == ConnType.circ) {
    final rings = _circRings(c.pins);
    return (w: 2 * rings.r + 34, h: 2 * rings.r + 40);
  }
  final cols = math.sqrt(c.pins * 1.7).ceil();
  final rows = (c.pins / cols).ceil();
  return (w: cols * kPitch + 26, h: rows * kPitch + 34);
}

double layoutConn(ConnectorDef c, double x, double y) {
  final s = connSize(c);
  c.x = x;
  c.y = y;
  c.w = s.w;
  c.h = s.h;
  c.pts = <Offset2>[];
  final top = y + 20;
  if (c.type == ConnType.dsub) {
    final n1 = (c.pins / 2).ceil();
    final n2 = c.pins - n1;
    for (var i = 0; i < n1; i++) {
      c.pts.add(Offset2(x + 18 + i * kPitch, top + 7));
    }
    for (var i = 0; i < n2; i++) {
      c.pts.add(Offset2(x + 18 + kPitch / 2 + i * kPitch, top + 7 + kPitch));
    }
  } else if (c.type == ConnType.circ) {
    final caps = _circRings(c.pins).caps;
    final cx = x + s.w / 2;
    final cy = top + (s.h - 20) / 2;
    var rem = c.pins;
    for (final ring in caps) {
      if (rem <= 0) break;
      final take = math.min(rem, ring.c);
      for (var i = 0; i < take; i++) {
        final a = -math.pi / 2 + (i / take) * math.pi * 2;
        c.pts.add(Offset2(
            cx + math.cos(a) * ring.r, cy + math.sin(a) * ring.r));
      }
      rem -= take;
    }
    if (rem > 0) c.pts.add(Offset2(cx, cy));
  } else {
    final cols = math.sqrt(c.pins * 1.7).ceil();
    for (var i = 0; i < c.pins; i++) {
      c.pts.add(Offset2(
          x + 16 + (i % cols) * kPitch, top + 7 + (i ~/ cols) * kPitch));
    }
  }
  return y + s.h + 18;
}

/// `const CW=1060, CH=440;`
const double kCanvasW = 1060;
const double kCanvasH = 440;

void layoutFixture() {
  final lw = kConnsL.map((c) => connSize(c).w).reduce(math.max);
  final rw = kConnsR.map((c) => connSize(c).w).reduce(math.max);
  final lh =
      kConnsL.fold<double>(-18, (a, c) => a + connSize(c).h + 18);
  final rh =
      kConnsR.fold<double>(-18, (a, c) => a + connSize(c).h + 18);

  var y = math.max(14.0, (kCanvasH - lh) / 2);
  for (final c in kConnsL) {
    y = layoutConn(c, 16, y);
  }
  y = math.max(14.0, (kCanvasH - rh) / 2);
  for (final c in kConnsR) {
    y = layoutConn(c, kCanvasW - 16 - rw, y);
  }
  kFix.midL = 16 + lw;
  kFix.midR = kCanvasW - 16 - rw;
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
