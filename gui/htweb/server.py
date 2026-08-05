"""Local web backend for the operator GUI.

The frontend is ``index.html`` — the markup and CSS of
``Doc/HT_MK1_GUI_Proposal.html`` verbatim, so the running instrument looks
exactly like the approved design. This module is the bridge between that page
and the instrument, and it is deliberately thin: all protocol knowledge stays
in ``htproto``.

Three endpoints, all standard library, no dependencies:

===================  ==========================================================
``GET  /``           the page
``GET  /api/events`` Server-Sent Events: one JSON object per instrument event,
                     plus link-state changes. SSE rather than a WebSocket
                     because it is one-way, reconnects on its own, and needs
                     nothing outside the standard library.
``POST /api/cmd``    ``{"cmd": "PING"}`` → ``{"ok": true, "reply": ...}``.
                     Runs on the request thread, so the 2 s command timeout
                     bounds it. The page never blocks its UI on this.
===================  ==========================================================

Safety note: this server binds **127.0.0.1 by default and refuses anything
else unless --allow-remote is passed**. The page can arm and fire 500 V; it has
no business being reachable from the network.
"""

from __future__ import annotations

import json
import queue
import threading
from dataclasses import asdict, is_dataclass
from enum import Enum
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from htproto import ConnectionManager, LinkState, ProtocolError, commands
from htproto.codec import parse_line

HERE = Path(__file__).resolve().parent
INDEX = HERE / "index.html"


def _jsonable(obj):
    """Turn a protocol message into something JSON can carry."""
    if obj is None or isinstance(obj, (str, int, float, bool)):
        return obj
    if isinstance(obj, Enum):
        return obj.value
    if is_dataclass(obj):
        out = {k: _jsonable(v) for k, v in asdict(obj).items()}
        out["type"] = type(obj).__name__
        return out
    return str(obj)


class Bridge:
    """Owns the ConnectionManager and fans events out to browser clients."""

    def __init__(self, host: str, port: int) -> None:
        self.host, self.port = host, port
        self._clients: list[queue.Queue] = []
        self._lock = threading.Lock()
        self.cm = ConnectionManager(
            on_event=self._on_event,
            on_link_state=self._on_link_state,
            on_protocol_error=self._on_proto_err,
        )

    # -- fan-out ---------------------------------------------------------------

    def subscribe(self) -> queue.Queue:
        q: queue.Queue = queue.Queue(maxsize=2000)
        with self._lock:
            self._clients.append(q)
        return q

    def unsubscribe(self, q: queue.Queue) -> None:
        with self._lock:
            if q in self._clients:
                self._clients.remove(q)

    def _push(self, payload: dict) -> None:
        with self._lock:
            clients = list(self._clients)
        for q in clients:
            try:
                q.put_nowait(payload)
            except queue.Full:
                pass       # a wedged browser tab must not stall the instrument

    def _on_event(self, msg) -> None:
        self._push({"kind": "event", "msg": _jsonable(msg)})

    def _on_link_state(self, state: LinkState, detail: str) -> None:
        self._push({"kind": "link", "state": state.value, "detail": detail})

    def _on_proto_err(self, raw: str, exc: Exception) -> None:
        self._push({"kind": "protocol_error", "raw": raw, "detail": str(exc)})

    # -- commands --------------------------------------------------------------

    def connect(self) -> dict:
        status = self.cm.connect(self.host, self.port)
        self._push({"kind": "link", "state": "connected",
                    "detail": f"{self.host}:{self.port}"})
        return {"ok": True, "reply": _jsonable(status)}

    def disconnect(self) -> dict:
        self.cm.disconnect()
        return {"ok": True}

    def send(self, line: str) -> dict:
        """Send one command line. The page passes protocol text, not bytes."""
        wire = (line if line.startswith(">") else ">" + line) + "\n"
        reply = self.cm.execute(wire.encode("ascii"))
        return {"ok": True, "reply": _jsonable(reply)}

    def netlist_get(self) -> dict:
        entries = self.cm.netlist_get()
        return {"ok": True, "reply": [{"hi": e.hi, "lo": e.lo} for e in entries]}

    def netlist_put(self, pairs) -> dict:
        self.cm.execute(commands.netlist_begin(len(pairs)))
        for hi, lo in pairs:
            self.cm.execute(commands.netlist_add(int(hi), int(lo)))
        reply = self.cm.execute(commands.netlist_end())
        return {"ok": True, "reply": _jsonable(reply)}


class Handler(BaseHTTPRequestHandler):
    bridge: Bridge = None            # set by serve()
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):      # quieter than the default
        pass

    # -- helpers ---------------------------------------------------------------

    def _send(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, payload: dict, code: int = 200) -> None:
        self._send(code, json.dumps(payload).encode("utf-8"), "application/json")

    # -- routes ----------------------------------------------------------------

    def do_GET(self):                                    # noqa: N802
        if self.path in ("/", "/index.html"):
            try:
                self._send(200, INDEX.read_bytes(), "text/html; charset=utf-8")
            except OSError as exc:
                self._send(500, str(exc).encode(), "text/plain")
            return
        if self.path == "/live.js":
            try:
                self._send(200, (HERE / "live.js").read_bytes(),
                           "application/javascript; charset=utf-8")
            except OSError as exc:
                self._send(500, str(exc).encode(), "text/plain")
            return
        if self.path == "/api/events":
            self._events()
            return
        self._send(404, b"not found", "text/plain")

    def _events(self) -> None:
        q = self.bridge.subscribe()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        try:
            while True:
                try:
                    payload = q.get(timeout=10.0)
                except queue.Empty:
                    # Keep-alive comment: without traffic some proxies and the
                    # browser itself will drop an idle SSE stream.
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
                    continue
                self.wfile.write(b"data: " + json.dumps(payload).encode() + b"\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            self.bridge.unsubscribe(q)

    def do_POST(self):                                   # noqa: N802
        if self.path != "/api/cmd":
            self._send(404, b"not found", "text/plain")
            return
        try:
            n = int(self.headers.get("Content-Length", "0"))
            req = json.loads(self.rfile.read(n) or b"{}")
        except (ValueError, json.JSONDecodeError) as exc:
            self._json({"ok": False, "error": f"bad request: {exc}"}, 400)
            return

        action = req.get("action", "send")
        try:
            if action == "connect":
                out = self.bridge.connect()
            elif action == "disconnect":
                out = self.bridge.disconnect()
            elif action == "netlist_get":
                out = self.bridge.netlist_get()
            elif action == "netlist_put":
                out = self.bridge.netlist_put(req.get("pairs", []))
            else:
                out = self.bridge.send(req.get("cmd", ""))
        except ProtocolError as exc:
            out = {"ok": False, "error": f"protocol error: {exc}"}
        except Exception as exc:                          # noqa: BLE001
            # Timeouts and link loss land here; the page shows them and stops.
            out = {"ok": False, "error": f"{type(exc).__name__}: {exc}"}
        self._json(out)


def serve(instrument_host: str, instrument_port: int,
          http_host: str, http_port: int) -> None:
    Handler.bridge = Bridge(instrument_host, instrument_port)
    httpd = ThreadingHTTPServer((http_host, http_port), Handler)
    print(f"HT_MK1 GUI on http://{http_host}:{http_port}/")
    print(f"instrument at {instrument_host}:{instrument_port}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        Handler.bridge.cm.disconnect()
        httpd.server_close()
