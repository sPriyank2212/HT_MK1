/// Connection manager for the HT_MK1 GUI (brief 3.5, task 2).
///
/// Direct port of `htproto/connection.py`. Owns the transport and the session
/// log; delegates the wire format to `codec.dart`. Implements the rules in
/// section 3.5:
///
/// 1. Every command waits for its `<` reply; a 2 s timeout is surfaced
///    ([CommandTimeoutError]) and the link drops to LINK_LOST — after a lost
///    reply the reply ordering can no longer be trusted, so the safe
///    assumption is "unknown", never "still fine".
/// 2. HV indication from `!HV` events is the GUI's job; this layer delivers
///    every event verbatim via [onEvent].
/// 3. Port closed, or [linkTimeout] (5 s) with no traffic: state becomes
///    LINK_LOST ("link lost - state unknown") and every command raises.
/// 4. [connect] — including reconnect — issues `>STATUS` and only reports
///    CONNECTED after the reply arrives. Never assume idle.
/// 5. Every byte sent and received goes to a session log file.
///
/// Python used a reader thread plus a watchdog thread and locks to serialise
/// them. Dart's isolate is single-threaded with an event loop, so the same
/// ordering guarantees come for free: appending to [_pending] and writing the
/// command happen in one synchronous block, which is exactly what the Python
/// `_io_lock` was protecting. The observable behaviour is unchanged.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'codec.dart';
import 'messages.dart';

/// seconds, per 3.5.1
const Duration defaultCommandTimeout = Duration(seconds: 2);

/// seconds, per 3.5.3
const Duration defaultLinkTimeout = Duration(seconds: 5);

enum LinkState {
  disconnected('disconnected'),
  connected('connected'),

  /// "state unknown" — never presented as safe
  linkLost('link_lost');

  final String wire;
  const LinkState(this.wire);
}

/// Base for connection-manager failures.
class ConnectionFailure implements Exception {
  final String message;
  const ConnectionFailure(this.message);
  @override
  String toString() => message;
}

/// Command attempted while DISCONNECTED.
class NotConnectedError extends ConnectionFailure {
  const NotConnectedError(super.message);
}

/// Command attempted after the link dropped; reconnect required.
class LinkLostError extends ConnectionFailure {
  const LinkLostError(super.message);
}

/// No `<` reply within the command timeout (3.5.1).
class CommandTimeoutError extends ConnectionFailure implements TimeoutException {
  const CommandTimeoutError(super.message);
  @override
  Duration? get duration => null;
}

/// Anything with open/send/stream/close works. [TcpTransport] talks to the
/// simulator; a serial transport (115200 8N1 USB VCP) slots in for real
/// hardware without touching [ConnectionManager].
abstract class Transport {
  Future<void> open(String host, int port);
  void send(List<int> data);

  /// Bytes from the instrument. Closing the stream means the port closed.
  Stream<Uint8List> get incoming;
  Future<void> close();
}

/// TCP transport — the simulator's side of the wire.
class TcpTransport implements Transport {
  Socket? _sock;
  StreamController<Uint8List>? _ctl;

  @override
  Future<void> open(String host, int port) async {
    final sock = await Socket.connect(host, port,
        timeout: const Duration(seconds: 5));
    sock.setOption(SocketOption.tcpNoDelay, true);
    _sock = sock;
    final ctl = StreamController<Uint8List>();
    _ctl = ctl;
    sock.listen(
      ctl.add,
      onError: ctl.addError,
      onDone: ctl.close,
      cancelOnError: true,
    );
  }

  @override
  void send(List<int> data) {
    final sock = _sock;
    if (sock == null) throw const SocketException('transport not open');
    sock.add(data);
  }

  @override
  Stream<Uint8List> get incoming =>
      _ctl?.stream ?? const Stream<Uint8List>.empty();

  @override
  Future<void> close() async {
    final sock = _sock;
    _sock = null;
    if (sock != null) {
      try {
        await sock.close();
      } on SocketException {
        // already gone
      }
      sock.destroy();
    }
    final ctl = _ctl;
    _ctl = null;
    if (ctl != null && !ctl.isClosed) await ctl.close();
  }
}

/// Every line sent and received, timestamped, flushed immediately (3.5.5).
///
/// Field failures get diagnosed from this file, so nothing is buffered.
class SessionLogger {
  final Directory _dir;
  RandomAccessFile? _file;
  File? path;

  SessionLogger(this._dir);

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _three(int n) => n.toString().padLeft(3, '0');

  /// `datetime.now().isoformat(timespec="milliseconds")`
  static String _stampIso(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)}T'
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.'
      '${_three(t.millisecond)}';

  /// `%Y%m%d-%H%M%S`
  static String _stampFile(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}-'
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

  void open() {
    _dir.createSync(recursive: true);
    final stamp = _stampFile(DateTime.now());
    final f = File(
        '${_dir.path}${Platform.pathSeparator}session-$stamp.log');
    path = f;
    _file = f.openSync(mode: FileMode.append);
    meta('session log opened');
  }

  void _write(String tag, String text) {
    final file = _file;
    if (file == null) return;
    final stamp = _stampIso(DateTime.now());
    file.writeStringSync('$stamp [$tag] $text\n');
    file.flushSync();
  }

  void tx(String line) => _write('tx', line);
  void rx(String line) => _write('rx', line);
  void meta(String text) => _write('gui', text);

  void close() {
    final file = _file;
    _file = null;
    if (file != null) {
      try {
        file.closeSync();
      } on FileSystemException {
        // nothing useful to do at shutdown
      }
    }
  }
}

/// One in-flight command awaiting its reply.
///
/// Most commands expect exactly one reply line. `>NETLIST GET` expects a
/// `<NETLIST <n>` header followed by n `<NET` lines (3.2); the header sets
/// [expect] and the same entry keeps consuming replies until the sequence is
/// complete — so `<NET` lines can never be mistaken for replies to some other
/// command.
class _Pending {
  final Completer<List<Message>> completer = Completer<List<Message>>();
  final List<Message> lines = <Message>[];
  final bool isNetlist;
  Object? error;

  /// total lines; set by the NETLIST header
  int? expect;

  _Pending({this.isNetlist = false});

  bool get isDone => completer.isCompleted;
}

typedef EventCallback = void Function(Message msg);
typedef LinkStateCallback = void Function(LinkState state, String detail);
typedef ProtocolErrorCallback = void Function(String raw, Object error);

/// `direction` is `'tx'` or `'rx'`, matching [SessionLogger]'s tags — every
/// line that reaches the log file also reaches this, so a live console can
/// show the same wire traffic without reading the file back off disk.
typedef WireCallback = void Function(String direction, String text);

class ConnectionManager {
  final EventCallback _onEvent;
  final LinkStateCallback _onLinkState;
  final ProtocolErrorCallback _onProtocolError;
  final WireCallback _onWire;

  final Duration commandTimeout;
  final Duration linkTimeout;
  final Transport Function() _transportFactory;

  Transport? _transport;
  StreamSubscription<Uint8List>? _sub;
  LinkState _state = LinkState.disconnected;
  final Queue<_Pending> _pending = Queue<_Pending>();
  Timer? _watchdog;
  bool _stop = false;
  DateTime _lastRx = DateTime.now();

  late final SessionLogger logger;

  ConnectionManager({
    EventCallback? onEvent,
    LinkStateCallback? onLinkState,
    ProtocolErrorCallback? onProtocolError,
    WireCallback? onWire,
    this.commandTimeout = defaultCommandTimeout,
    this.linkTimeout = defaultLinkTimeout,
    Directory? logDir,
    Transport Function() transportFactory = TcpTransport.new,
  })  : _onEvent = onEvent ?? _noEvent,
        _onLinkState = onLinkState ?? _noLink,
        _onProtocolError = onProtocolError ?? _noProto,
        _onWire = onWire ?? _noWire,
        _transportFactory = transportFactory {
    logger = SessionLogger(logDir ?? Directory('sessions'));
  }

  static void _noEvent(Message _) {}
  static void _noLink(LinkState _, String __) {}
  static void _noProto(String _, Object __) {}
  static void _noWire(String _, String __) {}

  // -- lifecycle -------------------------------------------------------------

  LinkState get state => _state;

  /// Open the link and handshake with `>STATUS` (3.5.4).
  ///
  /// Returns the instrument's STATUS reply; controls may only be enabled from
  /// what it says. Throws on any failure — never assume idle.
  Future<StatusReply> connect({
    String host = '127.0.0.1',
    int port = 46000,
  }) async {
    await disconnect();
    _stop = false;
    final transport = _transportFactory();
    // Errors propagate; still DISCONNECTED.
    await transport.open(host, port);
    _transport = transport;
    logger.open();
    logger.meta('connected $host:$port');
    _lastRx = DateTime.now();
    _state = LinkState.connected;

    final framer = LineFramer();
    _sub = transport.incoming.listen(
      (data) {
        _lastRx = DateTime.now();
        List<String> lines;
        try {
          lines = framer.feed(data);
        } on FormatException catch (exc) {
          _onProtocolError('<non-ascii bytes>', exc);
          return;
        }
        for (final line in lines) {
          _handleIncoming(line);
        }
      },
      onError: (Object exc) {
        if (!_stop) _linkLost('port error: $exc');
      },
      onDone: () {
        if (!_stop) _linkLost('port closed by instrument');
      },
    );

    // 3.5.3: 5 s with no traffic -> link lost, state unknown.
    final tick = Duration(
      microseconds: (linkTimeout.inMicroseconds ~/ 4)
          .clamp(1, const Duration(milliseconds: 500).inMicroseconds),
    );
    _watchdog = Timer.periodic(tick, (t) {
      if (_stop) return;
      if (_state == LinkState.connected &&
          DateTime.now().difference(_lastRx) > linkTimeout) {
        t.cancel();
        _linkLost('no traffic for ${_secs(linkTimeout)}s');
      }
    });

    Message status;
    try {
      status = await execute(commands.status());
    } on ConnectionFailure {
      await disconnect();
      rethrow;
    }
    if (status is! StatusReply) {
      await disconnect();
      throw ConnectionFailure(
          'STATUS handshake got unexpected reply $status');
    }
    _onLinkState(_state, 'connected $host:$port');
    return status;
  }

  static String _secs(Duration d) => (d.inMilliseconds / 1000.0).toStringAsFixed(1);

  Future<void> disconnect() async {
    _stop = true;
    _watchdog?.cancel();
    _watchdog = null;
    final sub = _sub;
    _sub = null;
    if (sub != null) await sub.cancel();
    final transport = _transport;
    _transport = null;
    if (transport != null) {
      try {
        await transport.close();
      } on SocketException {
        // already gone
      }
    }
    _failAllPending(const NotConnectedError('disconnected'));
    final changed = _state != LinkState.disconnected;
    _state = LinkState.disconnected;
    if (changed) {
      logger.meta('disconnected');
      _onLinkState(LinkState.disconnected, 'disconnected');
    }
    logger.close();
  }

  // -- commands --------------------------------------------------------------

  /// Send one command, wait for its parsed reply. Throws on timeout.
  Future<Message> execute(Uint8List command) async {
    final lines = await _execute(command);
    return lines[0];
  }

  /// `>NETLIST GET`: header reply followed by n `<NET` lines (3.2).
  Future<List<NetEntry>> netlistGet() async {
    final lines = await _execute(commands.netlistGet(), isNetlist: true);
    final header = lines[0];
    final entries = lines.sublist(1);
    if (header is! NetlistReply || entries.length != header.count) {
      throw ConnectionFailure('malformed NETLIST GET sequence: $lines');
    }
    return entries.cast<NetEntry>();
  }

  Future<List<Message>> _execute(
    Uint8List command, {
    bool isNetlist = false,
  }) async {
    final entry = _Pending(isNetlist: isNetlist);
    _requireReady();
    // Append-then-send in one synchronous block: this is what the Python
    // _io_lock guaranteed, and it is what keeps replies matched to commands
    // in order.
    _pending.add(entry);
    try {
      _sendLine(command);
    } on Object catch (exc) {
      _pending.remove(entry);
      _linkLost('send failed: $exc');
      throw LinkLostError('send failed: $exc');
    }

    Timer? timer;
    timer = Timer(commandTimeout, () {
      if (entry.isDone) return;
      _pending.remove(entry);
      final text = _wireRepr(command);
      _linkLost(
          'command timeout after ${_secs(commandTimeout)}s: $text');
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(CommandTimeoutError(
            'no reply within ${_secs(commandTimeout)}s: $text'));
      }
    });

    try {
      return await entry.completer.future;
    } finally {
      timer.cancel();
    }
  }

  static String _wireRepr(Uint8List command) =>
      "b'${ascii.decode(command).replaceAll('\n', r'\n')}'";

  // -- receive path ----------------------------------------------------------

  void _sendLine(Uint8List command) {
    _transport!.send(command);
    final text = ascii.decode(command).replaceAll(RegExp(r'\n+$'), '');
    logger.tx(text);
    _onWire('tx', text);
  }

  void _handleIncoming(String line) {
    logger.rx(line);
    _onWire('rx', line);
    Message msg;
    try {
      msg = parseLine(line);
    } on ProtocolError catch (exc) {
      // Malformed line: surface it, keep the link, let timeouts decide.
      _onProtocolError(line, exc);
      return;
    }
    if (line.startsWith('<')) {
      _matchReply(msg, line);
    } else {
      // '!' event or '#' log line
      _onEvent(msg);
    }
  }

  void _matchReply(Message msg, String raw) {
    if (_pending.isEmpty) {
      _onProtocolError(
          raw, const ProtocolError('reply with no command in flight'));
      return;
    }
    final entry = _pending.first;
    entry.lines.add(msg);
    var finished = true;
    if (entry.isNetlist) {
      final first = entry.lines[0];
      if (first is! NetlistReply) {
        entry.error = ConnectionFailure(
            'NETLIST GET: expected <NETLIST header, got $first');
      } else if (msg is! NetlistReply && msg is! NetEntry) {
        entry.error =
            ProtocolError('NETLIST GET: expected <NET, got $msg');
      } else if (entry.lines.length < 1 + first.count) {
        finished = false; // more <NET lines to come
      }
    }
    if (finished) {
      _pending.removeFirst();
      _complete(entry);
    }
  }

  void _complete(_Pending entry) {
    if (entry.completer.isCompleted) return;
    final err = entry.error;
    if (err != null) {
      entry.completer.completeError(err);
    } else {
      entry.completer.complete(entry.lines);
    }
  }

  // -- failure handling ------------------------------------------------------

  void _requireReady() {
    switch (_state) {
      case LinkState.disconnected:
        throw const NotConnectedError('not connected');
      case LinkState.linkLost:
        throw const LinkLostError(
            'link lost - state unknown; reconnect required');
      case LinkState.connected:
        return;
    }
  }

  void _linkLost(String detail) {
    if (_state != LinkState.connected) return;
    _state = LinkState.linkLost;
    logger.meta('LINK LOST: $detail');
    _failAllPending(LinkLostError('link lost: $detail'));
    // The bytes can no longer be trusted; force a clean reconnect.
    final transport = _transport;
    _transport = null;
    if (transport != null) {
      unawaited(transport.close().catchError((_) {}));
    }
    _watchdog?.cancel();
    _watchdog = null;
    _onLinkState(LinkState.linkLost, detail);
  }

  void _failAllPending(Object exc) {
    final pending = List<_Pending>.from(_pending);
    _pending.clear();
    for (final entry in pending) {
      entry.error = exc;
      _complete(entry);
    }
  }
}
