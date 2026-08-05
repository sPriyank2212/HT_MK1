"""Entry point for the packaged executable.

PyInstaller needs a script rather than ``-m``, and the exe must behave like a
double-clicked application: no console arguments, browser opens by itself. Any
arguments still work for the bench (``HT_MK1_GUI.exe --sim``, ``--port``, ...).

Build with ``build_exe.cmd``.
"""

from __future__ import annotations

import sys


def main() -> int:
    from htweb.__main__ import main as gui_main
    try:
        return gui_main()
    except KeyboardInterrupt:
        return 0
    except Exception as exc:                     # noqa: BLE001
        # A packaged app has no console to print a traceback into once it is
        # launched from Explorer, so say something an operator can act on and
        # hold the window open.
        print(f"\nHT_MK1 GUI failed to start: {type(exc).__name__}: {exc}\n")
        import traceback
        traceback.print_exc()
        try:
            input("Press Enter to close...")
        except (EOFError, OSError):
            pass
        return 1


if __name__ == "__main__":
    sys.exit(main())
