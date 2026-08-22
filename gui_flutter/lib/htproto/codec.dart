/// Wire codec for the HT_MK1 protocol (brief section 3).
///
/// Direct port of `htproto/codec.py`. Line-based ASCII, one message per line
/// ending `\n`, fields space-separated.
///
/// - GUI -> instrument lines start with `>` (command)
/// - instrument -> GUI lines start with `<` (reply), `!` (event) or `#` (log)
///
/// The encoders in [commands] produce the exact bytes a command must occupy on
/// the wire, including the leading `>` and trailing `\n`. [parseLine] validates
/// instrument lines strictly: wrong prefix, wrong field count, wrong field
/// order or a non-integer where the contract says integer all raise
/// [ProtocolError]. Anything that fails to parse must be surfaced by the
/// caller, never silently dropped (brief section 6, failure handling).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'messages.dart' as m;

const int newlineByte = 0x0a;
const String cmdPrefix = '>';
const String replyPrefix = '<';
const String eventPrefix = '!';
const String logPrefix = '#';

/// A line violated the section 3 contract.
class ProtocolError implements Exception {
  final String message;
  const ProtocolError(this.message);
  @override
  String toString() => message;
}

enum State {
  idle('idle'),
  running('running'),
  fault('fault'),
  hvArmed('hv_armed');

  final String wire;
  const State(this.wire);

  static State? fromWire(String s) {
    for (final v in State.values) {
      if (v.wire == s) return v;
    }
    return null;
  }
}

enum Fixture {
  none('none'),
  mtx('mtx'),
  hv('hv');

  final String wire;
  const Fixture(this.wire);

  static Fixture? fromWire(String s) {
    for (final v in Fixture.values) {
      if (v.wire == s) return v;
    }
    return null;
  }
}

enum ContMode {
  verify('verify'),
  discover('discover');

  final String wire;
  const ContMode(this.wire);

  static ContMode? fromWire(String s) {
    for (final v in ContMode.values) {
      if (v.wire == s) return v;
    }
    return null;
  }
}

enum ContStatus {
  pass('pass'),
  open('open'),
  short('short');

  final String wire;
  const ContStatus(this.wire);

  static ContStatus? fromWire(String s) {
    for (final v in ContStatus.values) {
      if (v.wire == s) return v;
    }
    return null;
  }
}

enum ResStatus {
  pass('pass'),
  failHigh('fail_high'),
  failLow('fail_low');

  final String wire;
  const ResStatus(this.wire);

  static ResStatus? fromWire(String s) {
    for (final v in ResStatus.values) {
      if (v.wire == s) return v;
    }
    return null;
  }
}

enum InsulStatus {
  pass('pass'),
  fail('fail');

  final String wire;
  const InsulStatus(this.wire);

  static InsulStatus? fromWire(String s) {
    for (final v in InsulStatus.values) {
      if (v.wire == s) return v;
    }
    return null;
  }
}

enum TestKind {
  cont('cont'),
  res('res'),
  insul('insul'),
  /// `MANUAL SWEEP`'s `!DONE sweep <found> 0` (GUI-06, 2026-08-21) — a
  /// diagnostic action, not one of the three staged tests; `AppState`
  /// routes it to its own handler rather than the shared `_onDone`.
  sweep('sweep'),
  /// `BUS SCAN`'s `!DONE bus <ok_count> <fault_count>` (GUI-06,
  /// 2026-08-21) — same reasoning as `sweep`.
  bus('bus');

  final String wire;
  const TestKind(this.wire);

  static TestKind? fromWire(String s) {
    for (final v in TestKind.values) {
      if (v.wire == s) return v;
    }
    return null;
  }
}

/// Error codes defined by the contract (3.2). Unknown codes are still parsed
/// (the firmware may add some) but callers can check membership here.
const Set<String> errorCodes = {
  'EBUSY',
  'EFIXTURE',
  'ENOTARMED',
  'ERANGE',
  'EHW',
  'ESYNTAX',
};

final RegExp _uintRe = RegExp(r'^[0-9]+$');
final RegExp _intRe = RegExp(r'^-?[0-9]+$');
final RegExp _semverRe = RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$');

/// Python-style `repr()` for a string, so error text matches the Python build.
String _r(String s) => "'$s'";

int _parseUint(String token, String what) {
  if (!_uintRe.hasMatch(token)) {
    throw ProtocolError('$what: expected unsigned integer, got ${_r(token)}');
  }
  return int.parse(token);
}

// The firmware prints measurement values with %ld from int32_t, so a negative
// reading is a legal wire value for these fields (brief 8.4 finding 2). Pins,
// counts and progress stay unsigned.
int _parseInt(String token, String what) {
  if (!_intRe.hasMatch(token)) {
    throw ProtocolError('$what: expected integer, got ${_r(token)}');
  }
  return int.parse(token);
}

T _enumOf<T>(T? value, String token, String what) {
  if (value == null) {
    throw ProtocolError('$what: unexpected value ${_r(token)}');
  }
  return value;
}

String _kv(String token, String key, String what) {
  final prefix = '$key=';
  if (!token.startsWith(prefix)) {
    throw ProtocolError('$what: expected field $prefix<...>, got ${_r(token)}');
  }
  return token.substring(prefix.length);
}

int _kvUint(String token, String key, String what) =>
    _parseUint(_kv(token, key, what), what);

int _kvInt(String token, String key, String what) =>
    _parseInt(_kv(token, key, what), what);

// ---------------------------------------------------------------------------
// Command encoders (GUI -> instrument). Each returns the full wire line.
// ---------------------------------------------------------------------------

int _checkUint(int value, String what) {
  if (value < 0) {
    throw ProtocolError('$what: expected non-negative int, got $value');
  }
  return value;
}

/// Pins are 1-based, valid range 1..256 (brief 8.1 answer 1). Out of range is
/// ERR ERANGE on the wire; the codec refuses to send it at all.
int _checkPin(int value, String what) {
  _checkUint(value, what);
  if (value < 1 || value > 256) {
    throw ProtocolError('$what: pin out of range 1..256: $value');
  }
  return value;
}

/// Byte-exact encoders for every command in section 3.2.
///
/// Lower-case on purpose: this mirrors `class commands` in `htproto/codec.py`
/// so call sites read identically in both builds — `commands.contRun(...)`
/// against `commands.cont_run(...)`. That traceability is the point of the
/// port, and it is worth one lint suppression.
// ignore: camel_case_types
class commands {
  const commands._();

  static Uint8List _line(String body) =>
      Uint8List.fromList(ascii.encode('$cmdPrefix$body\n'));

  static Uint8List ping() => _line('PING');

  static Uint8List identify() => _line('ID');

  static Uint8List status() => _line('STATUS');

  static Uint8List safe() => _line('SAFE');

  static Uint8List abort() => _line('ABORT');

  /// Forces safe, then clears the fault latch. Accepted while faulted, which
  /// nothing else is. Deliberate operator action only.
  static Uint8List faultClear() => _line('FAULT CLEAR');

  static Uint8List netlistBegin(int n) =>
      _line('NETLIST BEGIN ${_checkUint(n, 'n')}');

  static Uint8List netlistAdd(int hi, int lo) =>
      _line('NETLIST ADD ${_checkPin(hi, 'hi')} ${_checkPin(lo, 'lo')}');

  static Uint8List netlistEnd() => _line('NETLIST END');

  static Uint8List netlistGet() => _line('NETLIST GET');

  static Uint8List contRun(ContMode mode) => _line('CONT RUN ${mode.wire}');

  static Uint8List resRun() => _line('RES RUN');

  static Uint8List insulArm() => _line('INSUL ARM');

  static Uint8List insulRun() => _line('INSUL RUN');

  static Uint8List hvSet(int millivolts) =>
      _line('HV SET ${_checkUint(millivolts, 'millivolts')}');

  static Uint8List fixture(Fixture f) => _line('FIXTURE ${f.wire}');

  static Uint8List manualPath(int hi, int lo) =>
      _line('MANUAL PATH ${_checkPin(hi, 'hi')} ${_checkPin(lo, 'lo')}');

  /// The firmware refuses this outright with ERR EHW (brief section 0).
  /// Encoded only so the refusal can be exercised; the GUI must not offer
  /// this control to the operator.
  static Uint8List manualRelay(int board, int n, bool on) => _line(
        'MANUAL RELAY ${_checkUint(board, 'board')} ${_checkUint(n, 'n')} ${on ? 1 : 0}',
      );

  static Uint8List manualOff() => _line('MANUAL OFF');

  /// GUI-06 (2026-08-21): one HS pin against all 256 LS — a bounded version
  /// of cross-continuity discovery. Whole-run gated on the firmware side
  /// (`ERR EBUSY` while another run is active), unlike `manualPath`/
  /// `manualOff`'s instant replies.
  static Uint8List manualSweep(int hi) =>
      _line('MANUAL SWEEP ${_checkPin(hi, 'hi')}');

  /// GUI-06 (2026-08-21): probes every I2C device the firmware has a
  /// confirmed schematic address for (Matrix Card + the ADS124S08) —
  /// deliberately not the HV cards, whose address straps are still
  /// unverified (`hv_card.c`, BU-03).
  static Uint8List busScan() => _line('BUS SCAN');

  static Uint8List calGet() => _line('CAL GET');

  /// GUI-06 (2026-08-21), unblocked by HW-04: a standalone
  /// `Kelvin_MeasurePair` on the given pair, surfacing whether the HW-04
  /// ratiometric reference actually worked for this reading.
  static Uint8List calRun(int hi, int lo) =>
      _line('CAL RUN ${_checkPin(hi, 'hi')} ${_checkPin(lo, 'lo')}');

  static Uint8List limitsGet() => _line('LIMITS GET');

  static Uint8List limitsSet(int rMaxMohm, int insMinMohm) => _line(
        'LIMITS SET r_max_mohm=${_checkUint(rMaxMohm, 'r_max_mohm')}'
        ' ins_min_mohm=${_checkUint(insMinMohm, 'ins_min_mohm')}',
      );

  /// FW-14: DS18B20 board-temperature read. Answered `<OK started`, then
  /// (only on success - a missing/unpowered sensor or a bad CRC replies with
  /// nothing at all, see `Core/Src/app/tasks.c` `CMD_TEMP_READ`) a `!TEMP`
  /// event some time later. Callers must time out rather than wait forever.
  static Uint8List tempRead() => _line('TEMP READ');
}

// ---------------------------------------------------------------------------
// Line framer: bytes in, lines out.
// ---------------------------------------------------------------------------

/// Feeds a byte stream, yields complete lines without the trailing `\n`.
///
/// A trailing `\r` is stripped defensively: the contract says `\n` only, and
/// real firmware honours that, but a stray CR from a terminal session must not
/// turn every line into a parse error.
class LineFramer {
  final List<int> _buf = <int>[];

  List<String> feed(List<int> data) {
    _buf.addAll(data);
    final lines = <String>[];
    while (true) {
      final idx = _buf.indexOf(newlineByte);
      if (idx < 0) break;
      var raw = _buf.sublist(0, idx);
      _buf.removeRange(0, idx + 1);
      if (raw.isNotEmpty && raw.last == 0x0d) {
        raw = raw.sublist(0, raw.length - 1);
      }
      for (final b in raw) {
        if (b > 0x7f) {
          throw FormatException('non-ascii byte in instrument line: $b');
        }
      }
      lines.add(ascii.decode(raw));
    }
    return lines;
  }

  List<int> get pending => List<int>.unmodifiable(_buf);
}

// ---------------------------------------------------------------------------
// Parsers (instrument -> GUI).
// ---------------------------------------------------------------------------

/// Parse one instrument line (no trailing newline) into a message.
///
/// Throws [ProtocolError] on anything that does not match section 3 exactly.
m.Message parseLine(String line) {
  if (line.isEmpty) throw const ProtocolError('empty line');
  final prefix = line[0];
  final body = line.substring(1);
  if (prefix == logPrefix) return m.LogLine(body);
  if (prefix != replyPrefix && prefix != eventPrefix) {
    throw ProtocolError('bad prefix ${_r(prefix)}: ${_r(line)}');
  }
  final tokens = body.split(' ');
  if (prefix == replyPrefix) return _parseReply(tokens, line);
  return _parseEvent(tokens, line);
}

m.Message _parseReply(List<String> tokens, String line) {
  final head = tokens[0];
  if (head == 'PONG' && tokens.length == 1) return const m.Pong();
  if (head == 'ID' && tokens.length == 4) {
    if (tokens[1] != 'HT_MK1') {
      throw ProtocolError('ID: expected HT_MK1, got ${_r(tokens[1])}');
    }
    final fw = _kv(tokens[2], 'fw', 'ID');
    if (!_semverRe.hasMatch(fw)) {
      throw ProtocolError('ID: bad semver ${_r(fw)}');
    }
    final proto = _kvUint(tokens[3], 'proto', 'ID');
    return m.IdReply(fw: fw, proto: proto);
  }
  if (head == 'STATUS' && tokens.length == 4) {
    final stateTok = _kv(tokens[1], 'state', 'STATUS');
    final fixtureTok = _kv(tokens[2], 'fixture', 'STATUS');
    return m.StatusReply(
      state: _enumOf(State.fromWire(stateTok), stateTok, 'STATUS'),
      fixture: _enumOf(Fixture.fromWire(fixtureTok), fixtureTok, 'STATUS'),
      hvMv: _kvInt(tokens[3], 'hv_mv', 'STATUS'),
    );
  }
  if (head == 'OK') {
    return m.Ok(detail: tokens.sublist(1).join(' '));
  }
  if (head == 'ERR' && tokens.length >= 2) {
    return m.ErrReply(code: tokens[1], text: tokens.sublist(2).join(' '));
  }
  if (head == 'NETLIST' && tokens.length == 2) {
    return m.NetlistReply(count: _parseUint(tokens[1], 'NETLIST'));
  }
  if (head == 'NET' && tokens.length == 3) {
    return m.NetEntry(
      hi: _parseUint(tokens[1], 'NET hi'),
      lo: _parseUint(tokens[2], 'NET lo'),
    );
  }
  if (head == 'CAL' && tokens.length == 6) {
    return m.CalReply(
      currentUa: _kvUint(tokens[1], 'current_ua', 'CAL'),
      method: _kv(tokens[2], 'method', 'CAL'),
      rrefMohm: _kvUint(tokens[3], 'rref_mohm', 'CAL'),
      rrefTolMohm: _kvUint(tokens[4], 'rref_tol_mohm', 'CAL'),
      gainMax: _kvUint(tokens[5], 'gain_max', 'CAL'),
    );
  }
  if (head == 'LIMITS' && tokens.length == 3) {
    return m.LimitsReply(
      rMaxMohm: _kvInt(tokens[1], 'r_max_mohm', 'LIMITS'),
      insMinMohm: _kvInt(tokens[2], 'ins_min_mohm', 'LIMITS'),
    );
  }
  throw ProtocolError('unrecognised reply: ${_r(line)}');
}

m.Message _parseEvent(List<String> tokens, String line) {
  final head = tokens[0];
  if (head == 'PROGRESS' && tokens.length == 3) {
    return m.Progress(
      done: _parseUint(tokens[1], 'PROGRESS done'),
      total: _parseUint(tokens[2], 'PROGRESS total'),
    );
  }
  if (head == 'CONT' && tokens.length == 4) {
    return m.ContResult(
      hi: _parseUint(tokens[1], 'CONT hi'),
      lo: _parseUint(tokens[2], 'CONT lo'),
      status: _enumOf(
          ContStatus.fromWire(tokens[3]), tokens[3], 'CONT status'),
    );
  }
  if (head == 'RES' && tokens.length == 5) {
    return m.ResResult(
      hi: _parseUint(tokens[1], 'RES hi'),
      lo: _parseUint(tokens[2], 'RES lo'),
      milliohms: _parseInt(tokens[3], 'RES milliohms'),
      status:
          _enumOf(ResStatus.fromWire(tokens[4]), tokens[4], 'RES status'),
    );
  }
  if (head == 'INSUL' && tokens.length == 4) {
    return m.InsulResult(
      net: _parseUint(tokens[1], 'INSUL net'),
      leakMohm: _parseInt(tokens[2], 'INSUL leak_mohm'),
      status:
          _enumOf(InsulStatus.fromWire(tokens[3]), tokens[3], 'INSUL status'),
    );
  }
  if (head == 'FAULT' && tokens.length >= 3) {
    return m.Fault(code: tokens[1], text: tokens.sublist(2).join(' '));
  }
  if (head == 'DONE' && tokens.length == 4) {
    return m.Done(
      kind: _enumOf(TestKind.fromWire(tokens[1]), tokens[1], 'DONE kind'),
      passed: _parseUint(tokens[2], 'DONE passed'),
      failed: _parseUint(tokens[3], 'DONE failed'),
    );
  }
  if (head == 'STATE' && tokens.length == 2) {
    return m.StateEvent(
      state: _enumOf(State.fromWire(tokens[1]), tokens[1], 'STATE'),
    );
  }
  if (head == 'FIXTURE' && tokens.length == 2) {
    return m.FixtureEvent(
      fixture: _enumOf(Fixture.fromWire(tokens[1]), tokens[1], 'FIXTURE'),
    );
  }
  if (head == 'HV' && tokens.length == 2) {
    return m.HvEvent(millivolts: _parseInt(tokens[1], 'HV'));
  }
  if (head == 'TEMP' && tokens.length == 2) {
    return m.TempEvent(deciCelsius: _parseInt(tokens[1], 'TEMP'));
  }
  if (head == 'MANUAL' && tokens.length == 3) {
    return m.ManualEvent(
      adcMv: _kvInt(tokens[1], 'adc_mv', 'MANUAL'),
      adcCode: _kvUint(tokens[2], 'adc_code', 'MANUAL'),
    );
  }
  if (head == 'CAL_RESULT' && tokens.length == 4) {
    if (tokens[3] != 'pass' && tokens[3] != 'fail') {
      throw ProtocolError(
          'CAL_RESULT: expected pass|fail, got ${_r(tokens[3])}');
    }
    return m.CalResultEvent(
      rMohm: _kvInt(tokens[1], 'r_mohm', 'CAL_RESULT'),
      ratiometric: _kvUint(tokens[2], 'ratiometric', 'CAL_RESULT') != 0,
      pass: tokens[3] == 'pass',
    );
  }
  if (head == 'BUSLINE' && tokens.length == 3) {
    if (tokens[2] != 'ok' && tokens[2] != 'fault') {
      throw ProtocolError('BUSLINE: expected ok|fault, got ${_r(tokens[2])}');
    }
    return m.BusLineEvent(name: tokens[1], ok: tokens[2] == 'ok');
  }
  if (head == 'SAFE' && tokens.length == 1) return const m.SafeEvent();
  throw ProtocolError('unrecognised event: ${_r(line)}');
}
