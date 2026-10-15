/// Message types for the HT_MK1 protocol (brief sections 3.2-3.4).
///
/// Direct port of `htproto/messages.py`. The `type` string on each class is
/// the Python class name, because the live layer dispatches on exactly those
/// names — `server.py` used to put `type(obj).__name__` on the wire and
/// `live.js` switched on it. Keeping the names identical keeps that dispatch
/// table byte-for-byte the same.
library;

import 'codec.dart';

abstract class Message {
  const Message();

  /// Python class name, used by the live layer's dispatch.
  String get type;
}

// ---- Replies (instrument -> GUI, '<' prefix) ----

/// `<PONG`
class Pong extends Message {
  const Pong();
  @override
  String get type => 'Pong';
  @override
  bool operator ==(Object other) => other is Pong;
  @override
  int get hashCode => 'Pong'.hashCode;
  @override
  String toString() => 'Pong()';
}

/// `<ID HT_MK1 fw=<semver> proto=1`
class IdReply extends Message {
  final String fw;
  final int proto;
  const IdReply({required this.fw, required this.proto});
  @override
  String get type => 'IdReply';
  @override
  bool operator ==(Object other) =>
      other is IdReply && other.fw == fw && other.proto == proto;
  @override
  int get hashCode => Object.hash(fw, proto);
  @override
  String toString() => 'IdReply(fw: $fw, proto: $proto)';
}

/// `<STATUS state=<state> fixture=<fixture> hv_mv=<int>`
class StatusReply extends Message {
  final State state;
  final Fixture fixture;
  final int hvMv;
  const StatusReply({
    required this.state,
    required this.fixture,
    required this.hvMv,
  });
  @override
  String get type => 'StatusReply';
  @override
  bool operator ==(Object other) =>
      other is StatusReply &&
      other.state == state &&
      other.fixture == fixture &&
      other.hvMv == hvMv;
  @override
  int get hashCode => Object.hash(state, fixture, hvMv);
  @override
  String toString() =>
      'StatusReply(state: ${state.wire}, fixture: ${fixture.wire}, hv_mv: $hvMv)';
}

/// `<OK [detail...]`  e.g. `<OK started`, `<OK armed`, `<OK loaded=12`
class Ok extends Message {
  final String detail;
  const Ok({this.detail = ''});
  @override
  String get type => 'Ok';
  @override
  bool operator ==(Object other) => other is Ok && other.detail == detail;
  @override
  int get hashCode => detail.hashCode;
  @override
  String toString() => 'Ok(detail: $detail)';
}

/// `<ERR <code> <text>`
class ErrReply extends Message {
  final String code;
  final String text;
  const ErrReply({required this.code, required this.text});
  @override
  String get type => 'ErrReply';
  @override
  bool operator ==(Object other) =>
      other is ErrReply && other.code == code && other.text == text;
  @override
  int get hashCode => Object.hash(code, text);
  @override
  String toString() => 'ErrReply(code: $code, text: $text)';
}

/// `<NETLIST <n>`  (header of a NETLIST GET response)
class NetlistReply extends Message {
  final int count;
  const NetlistReply({required this.count});
  @override
  String get type => 'NetlistReply';
  @override
  bool operator ==(Object other) => other is NetlistReply && other.count == count;
  @override
  int get hashCode => count.hashCode;
  @override
  String toString() => 'NetlistReply(count: $count)';
}

/// `<NET <hi> <lo>`  (one line of a NETLIST GET response)
class NetEntry extends Message {
  final int hi;
  final int lo;
  const NetEntry({required this.hi, required this.lo});
  @override
  String get type => 'NetEntry';
  @override
  bool operator ==(Object other) =>
      other is NetEntry && other.hi == hi && other.lo == lo;
  @override
  int get hashCode => Object.hash(hi, lo);
  @override
  String toString() => 'NetEntry(hi: $hi, lo: $lo)';
}

/// `<CAL current_ua=<int> method=<string> rref_mohm=<int>
/// rref_tol_mohm=<int> gain_max=<int>`
///
/// Every field is read straight from `kelvin.h`'s real constants by
/// `proto.c`'s `CAL GET` handler - there is no separately-maintained copy to
/// drift out of sync. `method` is `ratiometric` once HW-04 (R131 on AIN8) is
/// wired; there is no single fixed PGA gain to report (every measurement
/// auto-ranges), so `gain_max` is the top of that range instead.
class CalReply extends Message {
  final int currentUa;
  final String method;
  final int rrefMohm;
  final int rrefTolMohm;
  final int gainMax;
  const CalReply({
    required this.currentUa,
    required this.method,
    required this.rrefMohm,
    required this.rrefTolMohm,
    required this.gainMax,
  });
  @override
  String get type => 'CalReply';
  @override
  bool operator ==(Object other) =>
      other is CalReply &&
      other.currentUa == currentUa &&
      other.method == method &&
      other.rrefMohm == rrefMohm &&
      other.rrefTolMohm == rrefTolMohm &&
      other.gainMax == gainMax;
  @override
  int get hashCode =>
      Object.hash(currentUa, method, rrefMohm, rrefTolMohm, gainMax);
  @override
  String toString() =>
      'CalReply(current_ua: $currentUa, method: $method, rref_mohm: $rrefMohm, '
      'rref_tol_mohm: $rrefTolMohm, gain_max: $gainMax)';
}

/// `<LIMITS r_max_mohm=<int> ins_min_mohm=<int>`
class LimitsReply extends Message {
  final int rMaxMohm;
  final int insMinMohm;
  const LimitsReply({required this.rMaxMohm, required this.insMinMohm});
  @override
  String get type => 'LimitsReply';
  @override
  bool operator ==(Object other) =>
      other is LimitsReply &&
      other.rMaxMohm == rMaxMohm &&
      other.insMinMohm == insMinMohm;
  @override
  int get hashCode => Object.hash(rMaxMohm, insMinMohm);
  @override
  String toString() =>
      'LimitsReply(r_max_mohm: $rMaxMohm, ins_min_mohm: $insMinMohm)';
}

// ---- Events (instrument -> GUI, '!' prefix) ----

/// `!PROGRESS <done> <total>`
class Progress extends Message {
  final int done;
  final int total;
  const Progress({required this.done, required this.total});
  @override
  String get type => 'Progress';
  @override
  bool operator ==(Object other) =>
      other is Progress && other.done == done && other.total == total;
  @override
  int get hashCode => Object.hash(done, total);
  @override
  String toString() => 'Progress(done: $done, total: $total)';
}

/// `!CONT <hi> <lo> <pass|open|short>`
class ContResult extends Message {
  final int hi;
  final int lo;
  final ContStatus status;
  const ContResult({required this.hi, required this.lo, required this.status});
  @override
  String get type => 'ContResult';
  @override
  bool operator ==(Object other) =>
      other is ContResult &&
      other.hi == hi &&
      other.lo == lo &&
      other.status == status;
  @override
  int get hashCode => Object.hash(hi, lo, status);
  @override
  String toString() => 'ContResult(hi: $hi, lo: $lo, status: ${status.wire})';
}

/// `!RES <hi> <lo> <milliohms> <pass|fail_high|fail_low>`
class ResResult extends Message {
  final int hi;
  final int lo;
  final int milliohms;
  final ResStatus status;
  const ResResult({
    required this.hi,
    required this.lo,
    required this.milliohms,
    required this.status,
  });
  @override
  String get type => 'ResResult';
  @override
  bool operator ==(Object other) =>
      other is ResResult &&
      other.hi == hi &&
      other.lo == lo &&
      other.milliohms == milliohms &&
      other.status == status;
  @override
  int get hashCode => Object.hash(hi, lo, milliohms, status);
  @override
  String toString() =>
      'ResResult(hi: $hi, lo: $lo, milliohms: $milliohms, status: ${status.wire})';
}

/// `!INSUL <net> <leak_mohm> <pass|fail>`
class InsulResult extends Message {
  final int net;
  final int leakMohm;
  final InsulStatus status;
  const InsulResult({
    required this.net,
    required this.leakMohm,
    required this.status,
  });
  @override
  String get type => 'InsulResult';
  @override
  bool operator ==(Object other) =>
      other is InsulResult &&
      other.net == net &&
      other.leakMohm == leakMohm &&
      other.status == status;
  @override
  int get hashCode => Object.hash(net, leakMohm, status);
  @override
  String toString() =>
      'InsulResult(net: $net, leak_mohm: $leakMohm, status: ${status.wire})';
}

/// `!FAULT <code> <text>`
class Fault extends Message {
  final String code;
  final String text;
  const Fault({required this.code, required this.text});
  @override
  String get type => 'Fault';
  @override
  bool operator ==(Object other) =>
      other is Fault && other.code == code && other.text == text;
  @override
  int get hashCode => Object.hash(code, text);
  @override
  String toString() => 'Fault(code: $code, text: $text)';
}

/// `!DONE <cont|res|insul> <passed> <failed>`
class Done extends Message {
  final TestKind kind;
  final int passed;
  final int failed;
  const Done({required this.kind, required this.passed, required this.failed});
  @override
  String get type => 'Done';
  @override
  bool operator ==(Object other) =>
      other is Done &&
      other.kind == kind &&
      other.passed == passed &&
      other.failed == failed;
  @override
  int get hashCode => Object.hash(kind, passed, failed);
  @override
  String toString() =>
      'Done(kind: ${kind.wire}, passed: $passed, failed: $failed)';
}

/// `!STATE <idle|running|fault|hv_armed>`
class StateEvent extends Message {
  final State state;
  const StateEvent({required this.state});
  @override
  String get type => 'StateEvent';
  @override
  bool operator ==(Object other) => other is StateEvent && other.state == state;
  @override
  int get hashCode => state.hashCode;
  @override
  String toString() => 'StateEvent(state: ${state.wire})';
}

/// `!FIXTURE <none|mtx|hv>`
class FixtureEvent extends Message {
  final Fixture fixture;
  const FixtureEvent({required this.fixture});
  @override
  String get type => 'FixtureEvent';
  @override
  bool operator ==(Object other) =>
      other is FixtureEvent && other.fixture == fixture;
  @override
  int get hashCode => fixture.hashCode;
  @override
  String toString() => 'FixtureEvent(fixture: ${fixture.wire})';
}

/// `!HV <millivolts>`
class HvEvent extends Message {
  final int millivolts;
  const HvEvent({required this.millivolts});
  @override
  String get type => 'HvEvent';
  @override
  bool operator ==(Object other) =>
      other is HvEvent && other.millivolts == millivolts;
  @override
  int get hashCode => millivolts.hashCode;
  @override
  String toString() => 'HvEvent(millivolts: $millivolts)';
}

/// `!MANUAL adc_mv=<int> adc_code=<int>`, in reply to `>MANUAL PATH` (GUI-06,
/// 2026-08-21) — the continuity ADC reading that command's own one-shot
/// connect/settle/read/release sequence took. There is no separate "hold the
/// path open, read it again later" state in this firmware, so this arrives
/// once per `MANUAL PATH`, not on demand.
class ManualEvent extends Message {
  final int adcMv;
  final int adcCode;
  const ManualEvent({required this.adcMv, required this.adcCode});
  @override
  String get type => 'ManualEvent';
  @override
  bool operator ==(Object other) =>
      other is ManualEvent &&
      other.adcMv == adcMv &&
      other.adcCode == adcCode;
  @override
  int get hashCode => Object.hash(adcMv, adcCode);
  @override
  String toString() => 'ManualEvent(adc_mv: $adcMv, adc_code: $adcCode)';
}

/// `!BUSLINE <name> <ok|fault>`, one per device `BUS SCAN` probed (GUI-06,
/// 2026-08-21). Terminated by `!DONE bus <ok_count> <fault_count>`.
class BusLineEvent extends Message {
  final String name;
  final bool ok;
  const BusLineEvent({required this.name, required this.ok});
  @override
  String get type => 'BusLineEvent';
  @override
  bool operator ==(Object other) =>
      other is BusLineEvent && other.name == name && other.ok == ok;
  @override
  int get hashCode => Object.hash(name, ok);
  @override
  String toString() => 'BusLineEvent(name: $name, ok: $ok)';
}

/// `!CAL_RESULT r_mohm=<int> ratiometric=<0|1> <pass|fail>`, in reply to
/// `>CAL RUN <hi> <lo>` (GUI-06, 2026-08-21) — a standalone
/// `Kelvin_MeasurePair` on the given pair, surfacing whether the HW-04
/// ratiometric reference (R131 via AIN8) actually worked for this reading —
/// the one field `!RES` doesn't carry.
class CalResultEvent extends Message {
  final int rMohm;
  final bool ratiometric;
  final bool pass;
  const CalResultEvent({
    required this.rMohm,
    required this.ratiometric,
    required this.pass,
  });
  @override
  String get type => 'CalResultEvent';
  @override
  bool operator ==(Object other) =>
      other is CalResultEvent &&
      other.rMohm == rMohm &&
      other.ratiometric == ratiometric &&
      other.pass == pass;
  @override
  int get hashCode => Object.hash(rMohm, ratiometric, pass);
  @override
  String toString() =>
      'CalResultEvent(r_mohm: $rMohm, ratiometric: $ratiometric, pass: $pass)';
}

/// `!TEMP <deci_celsius>`, in reply to `>TEMP READ` (FW-14, DS18B20 board
/// sensor). Only sent on a successful read - a missing/unpowered sensor or a
/// bad CRC produces no event at all, so callers must time out.
class TempEvent extends Message {
  final int deciCelsius;
  const TempEvent({required this.deciCelsius});
  @override
  String get type => 'TempEvent';
  @override
  bool operator ==(Object other) =>
      other is TempEvent && other.deciCelsius == deciCelsius;
  @override
  int get hashCode => deciCelsius.hashCode;
  @override
  String toString() => 'TempEvent(deci_celsius: $deciCelsius)';
}

/// `!SAFE`
class SafeEvent extends Message {
  const SafeEvent();
  @override
  String get type => 'SafeEvent';
  @override
  bool operator ==(Object other) => other is SafeEvent;
  @override
  int get hashCode => 'SafeEvent'.hashCode;
  @override
  String toString() => 'SafeEvent()';
}

// ---- Log lines (instrument -> GUI, '#' prefix): display, do not parse ----

/// `# <free text>`
class LogLine extends Message {
  final String text;
  const LogLine(this.text);
  @override
  String get type => 'LogLine';
  @override
  bool operator ==(Object other) => other is LogLine && other.text == text;
  @override
  int get hashCode => text.hashCode;
  @override
  String toString() => 'LogLine(text: $text)';
}
