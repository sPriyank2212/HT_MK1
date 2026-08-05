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
    ap.add_argument("--log-dir", default=None,
                    help="where to write session logs (default: a per-user "
                         "directory under LOCALAPPDATA)")
    ap.add_argument("--sim", action="store_true",
                    help="run the built-in simulator on --port and talk to it. "
                         "For demos and training with no instrument attached — "
                         "nothing it shows comes from real hardware.")
    args = ap.parse_args()

    sim = None
    if args.sim:
        from htproto.simulator import SimulatorServer, make_scenario
        sim = SimulatorServer(make_scenario("pass", 12), host="127.0.0.1",
                              port=args.port, interval=0.02).start()
        args.host, args.port = "127.0.0.1", sim.port
        print(f"SIMULATOR MODE on port {sim.port} — no real instrument. "
              "Nothing shown is a measurement.")

    http_host = "0.0.0.0" if args.allow_remote else "127.0.0.1"
    if args.allow_remote:
        print("WARNING: serving on all interfaces. This page can energise the "
              "harness at 500 V.")

    # The browser is opened from on_ready, i.e. after the socket is listening.
    # Opening it first is a race the browser usually wins, and it loses with
    # ERR_CONNECTION_REFUSED (Chromium shows that as error -102).
    def ready(port: int) -> None:
        if not args.no_browser:
            webbrowser.open(f"http://127.0.0.1:{port}/")

    from .server import serve
    try:
        serve(args.host, args.port, http_host, args.http_port, on_ready=ready,
              log_dir=args.log_dir)
    finally:
        if sim is not None:
            sim.stop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
