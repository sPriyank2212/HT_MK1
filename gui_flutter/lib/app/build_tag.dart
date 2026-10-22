/// The customer/developer build split — a genuine compile-time constant, not
/// a runtime flag. Set with `--dart-define=CUSTOMER_BUILD=true`; defaults to
/// the developer (full) build when not passed, same as a plain `flutter run`.
///
/// This has to be `bool.fromEnvironment`, not a plain top-level `bool`,
/// because only a real compile-time constant lets the AOT/release compiler
/// prove a branch gated on it is unreachable and tree-shake it out — a
/// customer build genuinely has no path to the code behind [kCustomerBuild],
/// not just a hidden menu item a `--dart-define` away from being un-hidden.
///
/// `build_exe.cmd` builds the developer and customer variants as two
/// separate `flutter build windows` passes for exactly this reason — one
/// release build cannot serve both, the flag has to be baked in at compile
/// time.
library;

const bool kCustomerBuild =
    bool.fromEnvironment('CUSTOMER_BUILD', defaultValue: false);

/// What [kBuildStamp] is when no stamp was passed (a plain `flutter run`).
const String kUnstamped = 'unstamped';

/// When this GUI was built, as `YYYY-MM-DDTHH:MM:SS` from the build PC's own
/// clock. `build_exe.cmd` reads the PC's date/time once and passes it as
/// `--dart-define=BUILD_STAMP=...` to both the developer and customer builds,
/// so the two share one stamp. Dart has no `__DATE__`, so the build script is
/// what supplies it; a plain `flutter run` shows [kUnstamped].
const String kBuildStamp =
    String.fromEnvironment('BUILD_STAMP', defaultValue: kUnstamped);

/// `2026-10-22T18:30:12` -> `2026-10-22 18:30` for display. Anything that is
/// not a full stamp (e.g. [kUnstamped]) is returned unchanged.
String prettyStamp(String stamp) {
  final m = RegExp(r'^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}):\d{2}$')
      .firstMatch(stamp);
  return m == null ? stamp : '${m[1]} ${m[2]}';
}
