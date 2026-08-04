"""Interactive terminal client for the HT_MK1 protocol (bring-up aid).

Connects to the simulator (or later the real instrument via a TCP bridge),
prints every incoming line, and sends whatever you type as a command. The
leading '>' is optional, exactly as on the instrument (brief appendix B).

Run (from gui/):
    python -m htproto.handtest --port 46000
"""

from __future__ import annotations

import argparse
import socket
import sys
import threading
import time


def main() -> None:
    ap = argparse.ArgumentParser(description="HT_MK1 hand-test terminal")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=46000)
    args = ap.parse_args()

    try:
        sock = socket.create_connection((args.host, args.port), timeout=5)
    except OSError as exc:
        print(f"cannot connect to {args.host}:{args.port}: {exc}")
        print("is the simulator running?  python -m htproto.simulator --scenario pass")
        sys.exit(1)
    sock.settimeout(None)
    print(f"connected to {args.host}:{args.port} - type commands (PING, STATUS, "
          f"CONT RUN verify, ...), empty line or Ctrl-C to quit")

    def reader() -> None:
        buf = b""
        try:
            while True:
                data = sock.recv(4096)
                if not data:
                    print("\n[connection closed by instrument]")
                    return
                buf += data
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    print(line.decode("ascii", errors="replace").rstrip("\r"))
        except OSError:
            print("\n[connection lost]")

    threading.Thread(target=reader, daemon=True).start()
    try:
        while True:
            line = input()
            if not line.strip():
                break
            if not line.startswith(">"):
                line = ">" + line
            try:
                sock.sendall(line.encode("ascii") + b"\n")
            except OSError:
                print("[send failed: connection closed]")
                break
    except (KeyboardInterrupt, EOFError):
        pass
    finally:
        time.sleep(0.3)  # let the reader thread print in-flight replies
        sock.close()


if __name__ == "__main__":
    main()
