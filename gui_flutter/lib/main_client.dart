/// HT_MK1 — client-styled Harness Tester. Same instrument link, protocol,
/// simulator and safety gating as the engineering console (`main.dart`), but
/// the window is the customer's own Harness Tester layout and terminology,
/// and PDF/CSV reports are in the customer's format.
///
/// ```
/// flutter run -d windows -t lib/main_client.dart --dart-entrypoint-args --sim
/// ht_mk1_client.exe --serial COM7
/// ```
///
/// Every command-line option of `main.dart` works here (`--serial`, `--sim`,
/// `--scenario`, `--nets`, `--list-ports`, `--log-dir`, …).
library;

import 'client/client_app.dart';
import 'main.dart' show runConsole;

Future<void> main(List<String> args) => runConsole(
      args,
      (state) => ClientApp(state: state, dataDir: defaultClientDataDir()),
    );
