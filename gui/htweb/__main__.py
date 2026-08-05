"""Entry point: ``python -m htweb``."""

from __future__ import annotations

import argparse
import webbrowser


def main() -> int:
    ap = argparse.ArgumentParser(description="HT_MK1 operator GUI (web frontend)")
    ap.add_argument("--host", default="127.0.0.1",
                    help="instrument / simulator host (default 127.0.0.1)")
    ap.add_argument("--port", type=int, default=46000,
                    help="instrument / simulator port (default 46000)")
    ap.add_argument("--http-port", type=int, default=8770,
                    help="port to serve the GUI on (default 8770)")
    ap.add_argument("--allow-remote", action="store_true",
                    help="bind 0.0.0.0 instead of loopback. This page can arm "
                         "and fire 500 V — only do this on a trusted network.")
    ap.add_argument("--no-browser", action="store_true",
                    help="do not open a browser window")
    args = ap.parse_args()

    http_host = "0.0.0.0" if args.allow_remote else "127.0.0.1"
    if args.allow_remote:
        print("WARNING: serving on all interfaces. This page can energise the "
              "harness at 500 V.")

    if not args.no_browser:
        webbrowser.open(f"http://127.0.0.1:{args.http_port}/")

    from .server import serve
    serve(args.host, args.port, http_host, args.http_port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
