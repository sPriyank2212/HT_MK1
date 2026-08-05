"""Application shell: header, navigation, and the controls that must always be
reachable (brief §2, tasks 3-10).

Threading contract. ``ConnectionManager`` fires callbacks from its reader and
watchdog threads, and ``execute()`` blocks for up to the 2 s command timeout.
Neither may touch Tk. So:

- background callbacks only mutate ``InstrumentModel`` and set a dirty flag;
- a 100 ms ``after`` tick on the Tk thread redraws from the model;
- every command is sent from a worker thread, with the outcome delivered back
  through the same dirty-flag mechanism.

That is why nothing here calls ``execute()`` inline: a 2 s freeze of the UI
would take the abort button with it, and §2 rule 3 says abort is reachable at
all times.
"""

from __future__ import annotations

import queue
import threading
import tkinter as tk
from tkinter import messagebox, ttk

from htproto import (
    CommandTimeoutError,
    ConnectionManager,
    ErrReply,
    LinkState,
    NotConnectedError,
    LinkLostError,
    commands,
)

from .model import Handling, InstrumentModel

# Colours chosen for contrast rather than decoration; the HV banner has to read
# across a workshop.
COL_LIVE = "#c62828"
COL_SAFE = "#2e7d32"
COL_UNKNOWN = "#ef6c00"
COL_BG = "#fafafa"
COL_HEAD = "#263238"


class HtGuiApp(tk.Tk):
    def __init__(self, host: str = "127.0.0.1", port: int = 46000) -> None:
        super().__init__()
        self.title("HT_MK1 — Harness Tester")
        self.geometry("1180x760")
        self.configure(bg=COL_BG)

        self.host, self.port = host, port
        self.model = InstrumentModel()
        self._dirty = threading.Event()
        self._toasts: queue.Queue[str] = queue.Queue()
        self._after_id: str | None = None

        from htproto.paths import default_log_dir
        self.cm = ConnectionManager(
            on_event=self._on_event,
            on_link_state=self._on_link_state,
            on_protocol_error=self._on_protocol_error,
            # Absolute, per-user: a relative "sessions/" fails to open when the
            # app is launched from a directory the operator cannot write to,
            # and that failure takes the whole connect down with it.
            log_dir=default_log_dir(),
        )
        self.model.subscribe(self._dirty.set)

        self._build_header()
        self._build_body()
        self._tick()

    # -- construction ----------------------------------------------------------

    def _build_header(self) -> None:
        head = tk.Frame(self, bg=COL_HEAD, height=92)
        head.pack(side=tk.TOP, fill=tk.X)
        head.pack_propagate(False)

        # HV / handling banner — visible on every screen, always (§2 rule 2).
        self.banner = tk.Label(head, text="", bg=COL_UNKNOWN, fg="white",
                               font=("Segoe UI", 20, "bold"), width=26)
        self.banner.pack(side=tk.LEFT, fill=tk.Y, padx=(10, 14), pady=10)

        info = tk.Frame(head, bg=COL_HEAD)
        info.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, pady=10)
        self.lbl_status = tk.Label(info, text="", bg=COL_HEAD, fg="white",
                                   font=("Consolas", 11), anchor="w")
        self.lbl_status.pack(fill=tk.X)
        self.lbl_toast = tk.Label(info, text="", bg=COL_HEAD, fg="#ffd54f",
                                  font=("Segoe UI", 10), anchor="w")
        self.lbl_toast.pack(fill=tk.X)
        self.progress = ttk.Progressbar(info, mode="determinate", maximum=100)
        self.progress.pack(fill=tk.X, pady=(6, 0))

        btns = tk.Frame(head, bg=COL_HEAD)
        btns.pack(side=tk.RIGHT, padx=10, pady=10)
        # §2 rule 3: abort is reachable at all times during any HV operation.
        # It is never disabled while the link is up.
        self.btn_abort = tk.Button(btns, text="ABORT", bg=COL_LIVE, fg="white",
                                   font=("Segoe UI", 15, "bold"), width=10,
                                   command=self.do_abort)
        self.btn_abort.pack(side=tk.RIGHT, padx=4)
        self.btn_safe = tk.Button(btns, text="ALL SAFE", width=10,
                                  font=("Segoe UI", 11), command=self.do_safe)
        self.btn_safe.pack(side=tk.RIGHT, padx=4)
        self.btn_conn = tk.Button(btns, text="Connect", width=10,
                                  font=("Segoe UI", 11), command=self.toggle_link)
        self.btn_conn.pack(side=tk.RIGHT, padx=4)

    def _build_body(self) -> None:
        body = tk.Frame(self, bg=COL_BG)
        body.pack(fill=tk.BOTH, expand=True)

        nav = tk.Frame(body, bg="#eceff1", width=190)
        nav.pack(side=tk.LEFT, fill=tk.Y)
        nav.pack_propagate(False)

        self.content = tk.Frame(body, bg=COL_BG)
        self.content.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        from . import screens
        self.screens = {
            "Run sequence": screens.RunScreen(self.content, self),
            "Continuity": screens.ContinuityScreen(self.content, self),
            "Resistance": screens.ResistanceScreen(self.content, self),
            "HV insulation": screens.InsulationScreen(self.content, self),
            "Netlist": screens.NetlistScreen(self.content, self),
            "Faults": screens.FaultsScreen(self.content, self),
            "History": screens.HistoryScreen(self.content, self),
            "Diagnostics": screens.DiagnosticsScreen(self.content, self),
        }
        self._navbtns = {}
        for name in self.screens:
            b = tk.Button(nav, text=name, anchor="w", relief=tk.FLAT,
                          bg="#eceff1", font=("Segoe UI", 11), padx=14, pady=9,
                          command=lambda n=name: self.show(n))
            b.pack(fill=tk.X)
            self._navbtns[name] = b
        self.current = None
        self.show("Run sequence")

    def show(self, name: str) -> None:
        for n, s in self.screens.items():
            s.pack_forget()
            self._navbtns[n].configure(bg="#eceff1", fg="black")
        self.screens[name].pack(fill=tk.BOTH, expand=True)
        self._navbtns[name].configure(bg="#cfd8dc", fg="black")
        self.current = name
        self._dirty.set()

    # -- link ------------------------------------------------------------------

    def toggle_link(self) -> None:
        if self.model.link_ok:
            self.cm.disconnect()
            self.model.set_link(False, "disconnected by operator")
        else:
            self._async(self._do_connect)

    def _do_connect(self):
        status = self.cm.connect(self.host, self.port)
        self.model.apply_status(status)
        self.model.set_link(True, f"{self.host}:{self.port}")
        # §3.5 rule 4 handled by connect(); pull the static config too.
        for cmd, attr in ((commands.cal_get(), "cal"),
                          (commands.limits_get(), "limits")):
            try:
                setattr(self.model, attr, self.cm.execute(cmd))
            except Exception:      # non-fatal: the screens show "unknown"
                pass
        return "connected"

    # -- background callbacks (NOT the Tk thread) ------------------------------

    def _on_event(self, msg) -> None:
        self.model.apply_event(msg)

    def _on_link_state(self, state, detail) -> None:
        if state is LinkState.CONNECTED:
            self.model.set_link(True, detail)
        else:
            self.model.set_link(False, detail)
            self._toasts.put(f"link: {detail}")

    def _on_protocol_error(self, raw, exc) -> None:
        # Surfaced, never silently dropped (§6 failure handling).
        self._toasts.put(f"protocol error: {exc}")

    # -- command plumbing ------------------------------------------------------

    def _async(self, fn, *a, **kw) -> None:
        def run():
            try:
                out = fn(*a, **kw)
                if out:
                    self._toasts.put(str(out))
            except (CommandTimeoutError, LinkLostError, NotConnectedError) as exc:
                self._toasts.put(f"{type(exc).__name__}: {exc}")
            except Exception as exc:                      # noqa: BLE001
                self._toasts.put(f"error: {exc}")
            finally:
                self._dirty.set()
        threading.Thread(target=run, daemon=True).start()

    def send(self, cmd: bytes, label: str = "") -> None:
        """Fire a command and report its reply. Never blocks the UI thread."""
        def run():
            reply = self.cm.execute(cmd)
            if isinstance(reply, ErrReply):
                # §3.5 rule 6: surface the refusal, never retry automatically.
                return f"{label or 'command'} refused: {reply.code} {reply.text}"
            return f"{label}: {reply}" if label else str(reply)
        self._async(run)

    def start_run(self, cmd: bytes, kind: str, label: str) -> None:
        """Run commands are special: only mark the run started if the
        instrument actually accepted it (§3.5 rule 1 — never assume)."""
        def run():
            reply = self.cm.execute(cmd)
            if isinstance(reply, ErrReply):
                return f"{label} refused: {reply.code} {reply.text}"
            self.model.note_run_started(kind)
            return f"{label} started"
        self._async(run)

    def do_abort(self) -> None:
        # No confirmation: an abort must never be one dialog away (§2 rule 3).
        self._async(lambda: self.cm.execute(commands.abort()) and "abort sent")

    def do_safe(self) -> None:
        self.send(commands.safe(), "force safe")

    # -- redraw ----------------------------------------------------------------

    def _tick(self) -> None:
        try:
            while True:
                self.lbl_toast.configure(text=self._toasts.get_nowait())
        except queue.Empty:
            pass
        if self._dirty.is_set():
            self._dirty.clear()
            self._refresh()
        self._after_id = self.after(100, self._tick)

    def _refresh(self) -> None:
        m = self.model
        handling = m.handling
        if not m.link_ok:
            self.banner.configure(text="LINK LOST\nSTATE UNKNOWN", bg=COL_UNKNOWN)
        elif m.hv_live:
            self.banner.configure(text=f"HV LIVE\n{m.hv_mv/1000.0:.0f} V", bg=COL_LIVE)
        elif handling is Handling.SAFE:
            self.banner.configure(text="SAFE\nto handle", bg=COL_SAFE)
        elif handling is Handling.LIVE:
            self.banner.configure(text="ENERGISED\ndo not handle", bg=COL_LIVE)
        else:
            self.banner.configure(text="STATE\nUNKNOWN", bg=COL_UNKNOWN)

        self.lbl_status.configure(text=m.status_text())
        self.btn_conn.configure(text="Disconnect" if m.link_ok else "Connect")
        self.btn_abort.configure(state=tk.NORMAL if m.link_ok else tk.DISABLED)
        self.btn_safe.configure(state=tk.NORMAL if m.link_ok else tk.DISABLED)

        if m.progress_total:
            self.progress.configure(value=100.0 * m.progress_done / m.progress_total)
        else:
            self.progress.configure(value=0)

        if self.current:
            self.screens[self.current].refresh()

    def destroy(self) -> None:       # noqa: D102
        # Cancel the redraw tick first, or it fires against a dead widget and
        # Tcl complains on every shutdown.
        if self._after_id is not None:
            try:
                self.after_cancel(self._after_id)
            except tk.TclError:
                pass
            self._after_id = None
        try:
            self.cm.disconnect()
        finally:
            super().destroy()


def confirm(parent, title: str, text: str) -> bool:
    return messagebox.askyesno(title, text, parent=parent, icon="warning")
