/// HT_MK1 operator console — Flutter Windows desktop app.
///
/// ```
/// ht_mk1_gui.exe --serial COM7       talk to the instrument over the VCP
/// ht_mk1_gui.exe --serial auto       find the ST-LINK VCP automatically
/// ht_mk1_gui.exe --list-ports        which COM ports exist
/// ht_mk1_gui.exe --sim               demo mode: built-in simulator
/// ht_mk1_gui.exe --host 10.0.0.4 --port 46000
/// ht_mk1_gui.exe --log-dir D:\logs
/// ```
///
/// `--serial` is the real link: the firmware carries the protocol on LPUART1
/// (PA2/PA3), which on a NUCLEO-G474RE is the ST-LINK Virtual COM Port at
/// 115200 8N1.
///
/// `--sim` runs the simulator inside the same process and says so on the
/// console — useful for training and for showing the GUI without an
/// instrument. Nothing it displays is a measurement.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app/app_state.dart';
import 'app/modals.dart';
import 'app/shell.dart';
import 'design/tokens.dart';
import 'htproto/connection.dart';
import 'htproto/paths.dart';
import 'htproto/serial_transport.dart';
import 'htproto/simulator.dart';
import 'views/cont_view.dart';
import 'views/misc_views.dart';
import 'views/res_hv_views.dart';
import 'views/run_view.dart';

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

  /// COM port name, or "auto" to find the ST-LINK VCP. null = use TCP.
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

const String _usage = '''
HT_MK1 operator console

  Talking to real hardware (LPUART1 -> ST-LINK VCP, 115200 8N1):
  --serial <port>    COM port, e.g. --serial COM7, or "auto" to pick the
                     ST-LINK VCP when exactly one is attached
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
// theme persistence — the page used localStorage("ht-theme")
// ---------------------------------------------------------------------------

File _themeFile() {
  final dir = defaultLogDir().parent; // %LOCALAPPDATA%\HT_MK1
  return File('${dir.path}${Platform.pathSeparator}theme');
}

String? loadStoredTheme() {
  try {
    final f = _themeFile();
    if (!f.existsSync()) return null;
    final v = f.readAsStringSync().trim();
    return (v == 'dark' || v == 'light') ? v : null;
  } on FileSystemException {
    return null;
  }
}

void storeTheme(String value) {
  try {
    final f = _themeFile();
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(value);
  } on FileSystemException {
    // A read-only profile must not take the app down over a theme preference.
  }
}

// ---------------------------------------------------------------------------
// entry point
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
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
  var port = o.port;
  // No --serial and no explicit TCP target: the link is serial, and the
  // operator picks the port from the status-bar selector.
  Transport Function() transportFactory =
      o.tcp ? TcpTransport.new : SerialTransport.new;

  if (o.serial != null) {
    var name = o.serial!;
    if (name == 'auto') {
      final guess = guessStLinkPort();
      if (guess == null) {
        // Do NOT exit. This is the double-click path: an operator console that
        // vanishes because the board is unplugged looks broken. Carry the
        // unresolved name through instead — SerialTransport.open turns it into
        // a readable failure, the window comes up, and the log says why.
        stderr.writeln('no single ST-LINK VCP found; '
            'run --list-ports and name one explicitly.');
      } else {
        name = guess;
        stdout.writeln('--serial auto picked $name');
      }
    }
    // SerialTransport reads the port name and baud out of these two, so the
    // session log's "connected COM7:115200" line says something true.
    host = name;
    port = o.baud;
    transportFactory = SerialTransport.new;
    stdout.writeln('instrument on $name at ${o.baud} 8N1');
  } else if (o.sim) {
    final sim = await SimulatorServer.start(
      makeScenario(o.scenario, nets: o.nets),
      host: '127.0.0.1',
      port: o.port,
      interval: Duration(microseconds: (o.interval * 1e6).round()),
    );
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

  late final AppState state;
  final cm = ConnectionManager(
    onEvent: (m) => state.onEvent(m),
    onLinkState: (s, d) => state.onLinkState(s, d),
    onProtocolError: (raw, e) => state.onProtocolError(raw, e),
    logDir: logDir,
    transportFactory: transportFactory,
  );
  state = AppState(
    cm: cm,
    host: host,
    port: port,
    // The one other place the native serial library is touched: the
    // status-bar selector's port list.
    listPorts: () => [
      for (final p in availableSerialPorts())
        PortEntry(p.name, p.description),
    ],
  );
  state.refreshPorts();
  // --serial preselects its port; the selector shows it even when the
  // enumeration does not (e.g. an unresolved "auto").
  if (o.serial != null) state.selPort = host;

  runApp(HtApp(state: state, storedTheme: loadStoredTheme()));

  // live.js calls connect() as soon as the page is built. Without --serial
  // (or --sim, or an explicit TCP target) the app starts disconnected and
  // the operator connects from the port selector instead.
  if (o.serial != null || o.sim || o.tcp) unawaited(state.connect());
}

// ---------------------------------------------------------------------------
// root
// ---------------------------------------------------------------------------

class HtApp extends StatefulWidget {
  final AppState state;
  final String? storedTheme;

  const HtApp({super.key, required this.state, this.storedTheme});

  @override
  State<HtApp> createState() => _HtAppState();
}

class _HtAppState extends State<HtApp> with WidgetsBindingObserver {
  String? _theme; // null = follow the system

  @override
  void initState() {
    super.initState();
    _theme = widget.storedTheme;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  void _toggleTheme() {
    // The page's toggle: whatever it looks like now, switch to the other.
    final dark = _theme == 'dark' ||
        (_theme == null &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    final next = dark ? 'light' : 'dark';
    setState(() => _theme = next);
    storeTheme(next);
  }

  @override
  Widget build(BuildContext context) {
    final systemDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    final isDark = _theme == null ? systemDark : _theme == 'dark';

    return HtTheme(
      isDark: isDark,
      child: Builder(builder: (context) {
        final c = context.colors;
        return WidgetsApp(
          title: 'HT_MK1 Console — Harness Test System',
          color: c.bg,
          // No Navigator: the app is a single screen with its own modals.
          // WidgetsApp does not supply a Directionality or a default text
          // style the way MaterialApp does, and this build deliberately has no
          // Material dependency, so both are established here.
          //   body{font-family:var(--ui);font-size:14px;line-height:1.45}
          builder: (context, _) => Directionality(
            textDirection: TextDirection.ltr,
            child: DefaultTextStyle(
              style: context.type.body,
              child: HtHome(
                state: widget.state,
                onToggleTheme: _toggleTheme,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// `<div class="app">`
class HtHome extends StatefulWidget {
  final AppState state;
  final VoidCallback onToggleTheme;

  const HtHome({
    super.key,
    required this.state,
    required this.onToggleTheme,
  });

  @override
  State<HtHome> createState() => _HtHomeState();
}

class _HtHomeState extends State<HtHome> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// `addEventListener("keydown", ...)`
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final s = widget.state;
    if (event.logicalKey == LogicalKeyboardKey.f5) {
      if (s.running == null) {
        s.actButtonPressed();
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      s.escape();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _view(AppState s) => switch (s.view) {
        'cont' => ContView(s: s),
        'res' => ResView(s: s),
        'hv' => HvView(s: s),
        'program' => ProgramView(s: s),
        'results' => ResultsView(s: s),
        'diag' => DiagView(s: s),
        _ => RunView(s: s),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: AnimatedBuilder(
        animation: widget.state,
        builder: (context, _) {
          final s = widget.state;
          final narrow = MediaQuery.sizeOf(context).width <= kNarrow;

          // body.hv-live swaps the status bar for the hazard banner.
          final header =
              s.hvLive ? HazardBar(s: s) : StatusBar(s: s, onToggleTheme: widget.onToggleTheme);

          final stage = SingleChildScrollView(
            // .stage{overflow:auto;padding:18px}  12px under 860
            padding: EdgeInsets.all(narrow ? 12 : 18),
            child: AnimatedSwitcher(
              // .view{animation:rise .22s ease-out}
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .012),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey<String>(s.view),
                child: _view(s),
              ),
            ),
          );

          final Widget body = narrow
              ? Column(
                  children: [
                    header,
                    Rail(s: s, horizontal: true),
                    Expanded(child: stage),
                    LogBar(s: s),
                  ],
                )
              : Column(
                  children: [
                    header,
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Rail(s: s),
                          Expanded(child: stage),
                        ],
                      ),
                    ),
                    LogBar(s: s),
                  ],
                );

          return ColoredBox(
            color: c.bg,
            child: Stack(
              children: [
                Positioned.fill(child: body),
                if (s.mdNlOpen) HvNetlistModal(s: s),
                if (s.mdVerifyOpen) VerifyModal(s: s),
              ],
            ),
          );
        },
      ),
    );
  }
}
