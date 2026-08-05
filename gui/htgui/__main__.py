"""Entry point: ``python -m htgui``."""

from __future__ import annotations

import argparse


def main() -> int:
    ap = argparse.ArgumentParser(description="HT_MK1 operator GUI")
    ap.add_argument("--host", default="127.0.0.1",
                    help="instrument or simulator host (default 127.0.0.1)")
    ap.add_argument("--port", type=int, default=46000,
                    help="TCP port (default 46000)")
    args = ap.parse_args()

    from .app import HtGuiApp
    app = HtGuiApp(host=args.host, port=args.port)
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
