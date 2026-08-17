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
