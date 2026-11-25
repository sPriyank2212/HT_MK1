/// Integrated Harness Tester MKI — Flutter Windows desktop app.
///
/// ```
/// ht_mk1_gui.exe --serial COM7       talk to the instrument over the VCP
/// ht_mk1_gui.exe --serial auto       find the instrument's USB-UART automatically
/// ht_mk1_gui.exe --list-ports        which COM ports exist
/// ht_mk1_gui.exe --sim               demo mode: built-in simulator
/// ht_mk1_gui.exe --host 10.0.0.4 --port 46000
/// ht_mk1_gui.exe --log-dir D:\logs
/// ```
///
/// `--serial` is the real link: the firmware carries the protocol on USART2
/// (PA2/PA3) - the MCP2221A USB-UART on the Control Card, or on a NUCLEO-G474RE the ST-LINK Virtual COM Port - at
/// 115200 8N1.
///
/// `--sim` runs the simulator inside the same process and says so on the
/// console — useful for training and for showing the GUI without an
/// instrument. Nothing it displays is a measurement.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app/app_state.dart';
import 'app/run_history.dart';
import 'client/client_app.dart';
import 'htproto/connection.dart';
import 'htproto/netlist_picker_io.dart' as netlist_picker;
import 'htproto/paths.dart';
import 'htproto/serial_transport.dart';
import 'htproto/simulator.dart';

// ---------------------------------------------------------------------------
// command line
// ---------------------------------------------------------------------------

class Options {
  String host = '127.0.0.1';
  int port = 46000;
  String? logDir;
  bool sim = false;
  String scenario = 'pass';
  int nets = 12;
  double interval = 0.02;

  /// COM port name, or "auto" to find the instrument's USB-UART. null = use TCP.
  String? serial;
  int baud = defaultBaud;
  bool listPorts = false;

  /// set when --host or --port is passed: the link is TCP, not serial
  bool tcp = false;
}

Options parseArgs(List<String> args) {
  final o = Options();
  for (var i = 0; i < args.length; i++) {
    String next() {
      if (i + 1 >= args.length) {
        throw FormatException('${args[i]} needs a value');
      }
      return args[++i];
    }

    switch (args[i]) {
      case '--host':
        o.host = next();
        o.tcp = true;
      case '--port':
        o.port = int.parse(next());
        o.tcp = true;
      case '--serial':
        o.serial = next();
      case '--baud':
        o.baud = int.parse(next());
      case '--list-ports':
        o.listPorts = true;
      case '--log-dir':
        o.logDir = next();
      case '--sim':
        o.sim = true;
      case '--scenario':
        o.scenario = next();
      case '--nets':
        o.nets = int.parse(next());
      case '--interval':
        o.interval = double.parse(next());
      case '--help':
      case '-h':
        stdout.writeln(_usage);
        exit(0);
      default:
        stderr.writeln('unrecognised argument: ${args[i]}');
        stderr.writeln(_usage);
        exit(2);
    }
  }
  if (o.serial != null && o.sim) {
    stderr.writeln('--serial and --sim are mutually exclusive: one talks to '
        'the instrument, the other replaces it.');
    exit(2);
  }
  return o;
}

/// What [AppState.port] must hold for the link the options describe.
///
/// `AppState` carries one "port" number that means different things on the two
/// transports: a TCP port for [TcpTransport], a baud rate for
/// [SerialTransport]. Only `--serial` used to set it to the baud rate, so the
/// plain double-click launch — serial transport, port picked from the status
/// bar — reached `SerialTransport.open` carrying the *TCP* default, and opened
/// the COM port at 46000 baud against firmware talking at 115200. The link came
/// up, the STATUS handshake timed out two seconds later, and Connect looked
/// broken.
int linkPortFor(Options o) => (o.tcp || o.sim) ? o.port : o.baud;

const String _usage = '''
HT_MK1 operator console

  Talking to real hardware (USART2 -> MCP2221A USB-UART, 115200 8N1):
  --serial <port>    COM port, e.g. --serial COM7, or "auto" to pick the
                     instrument's USB-UART when exactly one is attached
  --baud <n>         line rate (default $defaultBaud)
  --list-ports       list the serial ports this machine can see, then exit

  Talking to a simulator or a TCP bridge:
  --sim              run the built-in simulator and talk to it. For demos and
                     training with no instrument attached - nothing it shows
                     comes from real hardware.
  --scenario <name>  simulator scenario: pass | opens_shorts | res_fail |
                     insul_fail | disconnect   (default pass)
  --nets <n>         simulated harness size (default 12)
  --interval <s>     delay between streamed result events (default 0.02)
  --host <addr>      instrument host (default 127.0.0.1)
  --port <n>         instrument port (default 46000)

  --log-dir <path>   where to write session logs
                     (default: a per-user directory under LOCALAPPDATA)
''';

// ---------------------------------------------------------------------------
// entry point
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) => runConsole(
      args,
      (state) => ClientApp(state: state, dataDir: defaultClientDataDir()),
    );

/// The shared bootstrap: parse the command line, bring up the serial / TCP /
/// simulator link, build [AppState], then hand it to [buildApp] for the UI.
///
Future<void> runConsole(
  List<String> args,
  Widget Function(AppState state) buildApp,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  final o = parseArgs(args);

  if (o.listPorts) {
    final ports = availableSerialPorts();
    if (ports.isEmpty) {
      stdout.writeln('no serial ports found');
    } else {
      for (final p in ports) {
        stdout.writeln('  ${p.name.padRight(8)}  ${p.description}');
      }
    }
    exit(0);
  }

  var host = o.host;
  var port = linkPortFor(o);
  SimulatorServer? demoSim;
  // No --serial and no explicit TCP target: the link is serial, and the
  // operator picks the port from the status-bar selector.
  final bool serialLink = !o.tcp && !o.sim;
  Transport Function() transportFactory =
      o.tcp ? TcpTransport.new : SerialTransport.new;

  if (o.serial != null) {
    var name = o.serial!;
    if (name == 'auto') {
      final guess = guessInstrumentPort();
      if (guess == null) {
        // Do NOT exit. This is the double-click path: an operator console that
        // vanishes because the board is unplugged looks broken. Carry the
        // unresolved name through instead — SerialTransport.open turns it into
        // a readable failure, the window comes up, and the log says why.
        stderr.writeln('no single instrument serial port found; '
            'run --list-ports and name one explicitly.');
      } else {
        name = guess;
        stdout.writeln('--serial auto picked $name');
      }
    }
    // SerialTransport reads the port name and baud out of these two, so the
    // session log's "connected COM7:115200" line says something true. `port`
    // already holds the baud rate — see linkPortFor.
    host = name;
    transportFactory = SerialTransport.new;
    stdout.writeln('instrument on $name at ${o.baud} 8N1');
  } else if (o.sim) {
    // port: 0, not o.port (defaults to 46000 - the exact same default a real
    // --host/--port TCP bridge target uses) - an OS-assigned free port
    // instead of the conventional one means the demo's bundled simulator can
    // never collide with, or be mistaken for, a real server that happens to
    // already be listening locally. The double-click demo build must not be
    // able to end up talking to anything but its own simulator.
    final sim = await SimulatorServer.start(
      makeScenario(o.scenario, nets: o.nets),
      host: '127.0.0.1',
      port: 0,
      interval: Duration(microseconds: (o.interval * 1e6).round()),
    );
    demoSim = sim;
    host = '127.0.0.1';
    port = sim.port;
    transportFactory = TcpTransport.new;
    stdout.writeln('SIMULATOR MODE on port ${sim.port} — no real instrument. '
        'Nothing shown is a measurement.');
  } else if (o.tcp) {
    stdout.writeln('instrument at $host:$port');
  } else {
    stdout.writeln('no port selected — pick one in the status bar');
  }

  final logDir = o.logDir != null ? Directory(o.logDir!) : defaultLogDir();
  stdout.writeln('session logs in ${logDir.path}');
  final historyDir = defaultHistoryDir();
  stdout.writeln('run history in ${historyDir.path}');
  final reportsDir = defaultReportsDir();
  stdout.writeln('test reports in ${reportsDir.path}');

  late final AppState state;
  final cm = ConnectionManager(
    onEvent: (m) => state.onEvent(m),
    onLinkState: (s, d) => state.onLinkState(s, d),
    onProtocolError: (raw, e) => state.onProtocolError(raw, e),
    onWire: (dir, text) => state.onWire(dir, text),
    logDir: logDir,
    transportFactory: transportFactory,
  );
  state = AppState(
    cm: cm,
    host: host,
    port: port,
    // --sim and --host aim at a socket; a COM-port picker aimed at one would
    // hand `Socket.connect` a port name. The selector hides itself instead.
    serialLink: serialLink,
    // The one other place the native serial library is touched: the
    // status-bar selector's port list.
    listPorts: () => [
      for (final p in availableSerialPorts())
        PortEntry(p.name, p.description),
    ],
    // The only place file_picker's platform channel is touched — see
    // netlist_picker_io.dart's own comment for why this is injected rather
    // than imported directly by AppState.
    pickNetlistFile: netlist_picker.pickNetlistFile,
    // GUI-05: run history lives on the GUI host, not the instrument.
    history: RunHistoryStore(historyDir),
    reportsDir: reportsDir,
    pickSavePath: netlist_picker.pickSavePath,
    // Only under --sim: lets the Run screen's demo selector change what the
    // simulated instrument reports. With real hardware there is no such
    // thing, and the selector is not shown.
    demoScenario: demoSim == null
        ? null
        : (faulty) => demoSim!.setScenario(
              makeScenario(faulty ? 'opens_shorts' : 'pass', nets: o.nets)),
  );
  state.refreshPorts();
  // --serial preselects its port; the selector shows it even when the
  // enumeration does not (e.g. an unresolved "auto").
  if (o.serial != null) state.selPort = host;

  runApp(buildApp(state));

  // live.js calls connect() as soon as the page is built. Without --serial
  // (or --sim, or an explicit TCP target) the app starts disconnected and
  // the operator connects from the port selector instead.
  if (o.serial != null || o.sim || o.tcp) unawaited(state.connect());
}
