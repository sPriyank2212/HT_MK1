/// Serial transport — the real instrument's side of the wire.
///
/// The firmware carries the protocol on LPUART1 (PA2/PA3), which on a
/// NUCLEO-G474RE lands on the ST-LINK Virtual COM Port, 115200 8N1. See
/// `Log_HwInit_LPUART1()` in `Core/Src/app/log.c`.
///
/// Nothing above [Transport] changes: [ConnectionManager] still owns the
/// timeouts, the link watchdog and the session log, and the codec still frames
/// lines the same way. The firmware terminates with CRLF and `LineFramer`
/// strips the trailing `\r`, so no special handling is needed here.
///
/// This file is imported only by `main.dart`. Keeping it out of
/// `connection.dart` means the test suite never pulls in the native library.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'connection.dart';

/// Default line settings, matching the firmware.
const int defaultBaud = 115200;

class SerialOpenError implements Exception {
  final String message;
  const SerialOpenError(this.message);
  @override
  String toString() => message;
}

/// One serial port, presented as a [Transport].
///
/// [open] takes the port name and baud rate through [ConnectionManager]'s
/// `host` and `port` arguments — that keeps a single source of truth for what
/// the link is, and makes the session log's "connected COM7:115200" line say
/// something true.
class SerialTransport implements Transport {
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamController<Uint8List>? _ctl;

  /// Guards against a second close landing while the first is still in its
  /// settle delay — link loss and an explicit disconnect can both fire.
  bool _closing = false;

  @override
  Future<void> open(String portName, int baud) async {
    // `--serial auto` reaches here unresolved when no ST-LINK was found. Say
    // so in the operator's own terms rather than failing on a port literally
    // named "auto".
    if (portName == 'auto') {
      throw const SerialOpenError(
          'no ST-LINK Virtual COM Port found — is the board plugged in?');
    }

    final port = SerialPort(portName);

    bool opened;
    try {
      opened = port.openReadWrite();
    } on SerialPortError catch (e) {
      port.dispose();
      throw SerialOpenError('cannot open $portName: $e');
    }
    if (!opened) {
      final err = SerialPort.lastError;
      port.dispose();
      throw SerialOpenError(
          'cannot open $portName${err == null ? '' : ': $err'}. '
          'Is another program holding it — a terminal, or the STM32CubeIDE '
          'console?');
    }

    try {
      final cfg = SerialPortConfig()
        ..baudRate = baud
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none
        ..setFlowControl(SerialPortFlowControl.none)
        // ST-LINK's VCP does not gate transmission on these, but several
        // USB-serial bridges stay mute until the host asserts them, and
        // neither line is wired to NRST on a Nucleo, so raising both is safe
        // and avoids a silent port.
        ..dtr = SerialPortDtr.on
        ..rts = SerialPortRts.on;
      port.config = cfg;
      cfg.dispose();
    } on SerialPortError catch (e) {
      port.close();
      port.dispose();
      throw SerialOpenError('cannot configure $portName: $e');
    }

    // Discard whatever the driver buffered before we got here. The instrument
    // heartbeats whether or not anyone is listening, so opening the port
    // delivers a burst of stale events — and the buffer starts mid-message,
    // so the first line arrives with its '!' already gone and fails to parse.
    // A TCP connect gets a clean stream by construction; this is the serial
    // equivalent. Anything buffered before we connected predates the session
    // and has nothing to tell us.
    try {
      port.flush(SerialPortBuffer.input);
    } on SerialPortError {
      // Not fatal: a stale line is surfaced as a protocol error, not dropped.
    }

    _port = port;
    final ctl = StreamController<Uint8List>();
    _ctl = ctl;

    final reader = SerialPortReader(port);
    _reader = reader;
    reader.stream.listen(
      ctl.add,
      onError: ctl.addError,
      // The port vanishing — cable pulled, board reset — closes the stream,
      // which ConnectionManager reads as link loss. That is the correct
      // reading: state unknown, never "safe".
      onDone: () {
        if (!ctl.isClosed) ctl.close();
      },
      cancelOnError: true,
    );
  }

  @override
  void send(List<int> data) {
    final port = _port;
    if (port == null) throw const SerialOpenError('transport not open');
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    // A bounded write: a wedged port must surface as link loss rather than
    // blocking the UI isolate forever.
    final written = port.write(bytes, timeout: 1000);
    if (written != bytes.length) {
      throw SerialOpenError(
          'short write on ${port.name}: $written of ${bytes.length} bytes');
    }
  }

  @override
  Stream<Uint8List> get incoming =>
      _ctl?.stream ?? const Stream<Uint8List>.empty();

  @override
  Future<void> close() async {
    // Order matters here, and the absence of dispose() is deliberate.
    //
    // SerialPortReader.close() asks its background isolate to stop but does
    // not wait for it. Closing and then freeing the port underneath that
    // isolate hands an already-released handle back to the CRT, which aborts:
    // exception 0x80000003 in ucrtbased.dll, about fifteen seconds after a
    // link-loss triggered close. That was a crash dialog on a 500 V console,
    // so the trade is not close.
    //
    // Closing the handle is enough — the reader's next read fails and the
    // isolate winds up on its own. The sp_port struct is left to leak: a few
    // hundred bytes per connect, on a link the operator opens by hand a
    // handful of times a shift.
    if (_closing) return;
    _closing = true;

    final reader = _reader;
    _reader = null;
    reader?.close();

    final ctl = _ctl;
    _ctl = null;
    if (ctl != null && !ctl.isClosed) await ctl.close();

    // Give the reader isolate a moment to observe the shutdown before the
    // handle goes away under it.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final port = _port;
    _port = null;
    if (port != null) {
      try {
        if (port.isOpen) port.close();
      } on SerialPortError {
        // already gone
      }
    }
    _closing = false;
  }
}

/// One row per port for `--list-ports`.
class PortInfo {
  final String name;
  final String description;
  const PortInfo(this.name, this.description);
}

/// Enumerate the serial ports this machine can see.
List<PortInfo> availableSerialPorts() {
  final out = <PortInfo>[];
  for (final name in SerialPort.availablePorts) {
    var description = '';
    SerialPort? p;
    try {
      p = SerialPort(name);
      final bits = <String>[
        if ((p.description ?? '').isNotEmpty) p.description!,
        if ((p.manufacturer ?? '').isNotEmpty) p.manufacturer!,
      ];
      description = bits.join(' · ');
    } on SerialPortError {
      description = '(details unavailable)';
    } finally {
      p?.dispose();
    }
    out.add(PortInfo(name, description));
  }
  return out;
}

/// The ST-LINK VCP, if exactly one is present. Used by `--serial auto`.
String? guessStLinkPort() {
  final matches = availableSerialPorts()
      .where((p) =>
          p.description.toLowerCase().contains('stlink') ||
          p.description.toLowerCase().contains('st-link') ||
          p.description.toLowerCase().contains('stmicroelectronics'))
      .toList();
  return matches.length == 1 ? matches.first.name : null;
}
