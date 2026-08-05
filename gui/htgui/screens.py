"""The eight screens (brief §2, tasks 3-10).

Each is a Frame with a ``refresh()`` the shell calls whenever the model
changes. Screens never talk to the transport directly — they call
``app.send()`` / ``app.start_run()``, which keep the 2 s wait off the UI thread.

The recurring safety pattern: a control that can energise the harness is
enabled from ``model.insulation_allowed`` / ``model.can_energise``, both of
which are false the moment the link is not healthy. Nothing is enabled from
what the GUI *believes* it did.
"""

from __future__ import annotations

import time
import tkinter as tk
from tkinter import filedialog, ttk

from htproto import commands
from htproto.codec import ContMode, Fixture

from .app import confirm
from .model import Handling

PAD = dict(padx=12, pady=8)


class Screen(tk.Frame):
    def __init__(self, parent, app):
        super().__init__(parent, bg="#fafafa")
        self.app = app
        self.model = app.model
        self.build()

    def build(self) -> None: ...
    def refresh(self) -> None: ...

    def h1(self, text):
        tk.Label(self, text=text, bg="#fafafa", font=("Segoe UI", 17, "bold"),
                 anchor="w").pack(fill=tk.X, **PAD)

    def tree(self, cols, widths, height=18):
        frame = tk.Frame(self, bg="#fafafa")
        frame.pack(fill=tk.BOTH, expand=True, **PAD)
        tv = ttk.Treeview(frame, columns=cols, show="headings", height=height)
        for c, w in zip(cols, widths):
            tv.heading(c, text=c)
            tv.column(c, width=w, anchor="w")
        sb = ttk.Scrollbar(frame, orient="vertical", command=tv.yview)
        tv.configure(yscrollcommand=sb.set)
        tv.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        sb.pack(side=tk.RIGHT, fill=tk.Y)
        tv.tag_configure("pass", background="#e8f5e9")
        tv.tag_configure("fail", background="#ffebee")
        return tv


# --------------------------------------------------------------------------- #
# Task 3 + 8 — run / fixture sequence
# --------------------------------------------------------------------------- #

class RunScreen(Screen):
    """Guides load → continuity → resistance → MOVE → insulation → report.

    The handover is the point of this screen. The operator physically moves the
    harness, and insulation stays locked until the *instrument* reports
    ``!FIXTURE hv`` — not until the GUI asked for it (§2 rule 5).
    """

    STEPS = [
        ("1. Load harness on the MATRIX fixture", Fixture.MTX),
        ("2. Continuity", None),
        ("3. Resistance", None),
        ("4. MOVE harness to the HV fixture", Fixture.HV),
        ("5. Insulation", None),
        ("6. Report", None),
    ]

    def build(self):
        self.h1("Run sequence")
        self.step_lbls = []
        box = tk.Frame(self, bg="#fafafa")
        box.pack(fill=tk.X, **PAD)
        for text, _ in self.STEPS:
            l = tk.Label(box, text=text, bg="#fafafa", anchor="w",
                         font=("Segoe UI", 12), padx=8, pady=5)
            l.pack(fill=tk.X)
            self.step_lbls.append(l)

        bar = tk.Frame(self, bg="#fafafa")
        bar.pack(fill=tk.X, **PAD)
        self.b_mtx = tk.Button(bar, text="Confirm: harness on MATRIX", width=26,
                               command=lambda: self.app.send(
                                   commands.fixture(Fixture.MTX), "fixture mtx"))
        self.b_mtx.pack(side=tk.LEFT, padx=4)
        self.b_hv = tk.Button(bar, text="Confirm: harness moved to HV", width=26,
                              command=self.confirm_hv)
        self.b_hv.pack(side=tk.LEFT, padx=4)

        bar2 = tk.Frame(self, bg="#fafafa")
        bar2.pack(fill=tk.X, **PAD)
        self.b_cont = tk.Button(bar2, text="Run continuity (verify)", width=22,
                                command=lambda: self.app.start_run(
                                    commands.cont_run(ContMode.VERIFY), "cont",
                                    "continuity verify"))
        self.b_cont.pack(side=tk.LEFT, padx=4)
        self.b_res = tk.Button(bar2, text="Run resistance", width=18,
                               command=lambda: self.app.start_run(
                                   commands.res_run(), "res", "resistance"))
        self.b_res.pack(side=tk.LEFT, padx=4)
        self.b_ins = tk.Button(bar2, text="Go to insulation →", width=18,
                               command=lambda: self.app.show("HV insulation"))
        self.b_ins.pack(side=tk.LEFT, padx=4)

        self.summary = tk.Label(self, text="", bg="#fafafa", justify=tk.LEFT,
                                anchor="w", font=("Consolas", 11))
        self.summary.pack(fill=tk.BOTH, expand=True, **PAD)

    def confirm_hv(self):
        if confirm(self, "Move harness",
                   "Confirm the harness has been physically moved to the HV "
                   "fixture.\n\nThe instrument will refuse to arm otherwise, and "
                   "500 V is applied at this fixture."):
            self.app.send(commands.fixture(Fixture.HV), "fixture hv")

    def refresh(self):
        m = self.model
        for i, (_, want) in enumerate(self.STEPS):
            done = False
            if want is Fixture.MTX:
                done = m.fixture is Fixture.MTX
            elif want is Fixture.HV:
                done = m.fixture is Fixture.HV
            elif i == 1:
                done = any(h.kind == "cont" for h in m.history)
            elif i == 2:
                done = any(h.kind == "res" for h in m.history)
            elif i == 4:
                done = any(h.kind == "insul" for h in m.history)
            elif i == 5:
                done = len(m.history) >= 3
            self.step_lbls[i].configure(
                bg="#e8f5e9" if done else "#fafafa",
                fg="#1b5e20" if done else "black")

        live = m.link_ok and not m.running
        for b in (self.b_mtx, self.b_hv, self.b_cont, self.b_res):
            b.configure(state=tk.NORMAL if live else tk.DISABLED)
        self.b_ins.configure(state=tk.NORMAL if m.insulation_allowed else tk.DISABLED)

        lines = [f"{h.kind:<6} {h.passed:>4} passed  {h.failed:>4} failed  "
                 f"({h.yield_pct:.1f}% yield)" for h in m.history[-8:]]
        self.summary.configure(text="\n".join(lines) or "No runs yet.")


# --------------------------------------------------------------------------- #
# Task 5 — continuity
# --------------------------------------------------------------------------- #

class ContinuityScreen(Screen):
    def build(self):
        self.h1("Continuity")
        bar = tk.Frame(self, bg="#fafafa")
        bar.pack(fill=tk.X, **PAD)
        self.b_verify = tk.Button(bar, text="Verify against netlist", width=22,
                                  command=lambda: self.app.start_run(
                                      commands.cont_run(ContMode.VERIFY), "cont",
                                      "continuity verify"))
        self.b_verify.pack(side=tk.LEFT, padx=4)
        self.b_disc = tk.Button(bar, text="Discover harness", width=18,
                                command=self.discover)
        self.b_disc.pack(side=tk.LEFT, padx=4)
        self.lbl = tk.Label(bar, text="", bg="#fafafa", font=("Segoe UI", 11))
        self.lbl.pack(side=tk.LEFT, padx=14)

        self.canvas = tk.Canvas(self, bg="white", height=150,
                                highlightthickness=1, highlightbackground="#cfd8dc")
        self.canvas.pack(fill=tk.X, **PAD)
        self.tv = self.tree(("hi", "lo", "result"), (90, 90, 220), height=13)

    def discover(self):
        if confirm(self, "Discover",
                   "A discovery scan tests all 256x256 combinations and takes "
                   "tens of seconds.\n\nContinue?"):
            self.app.start_run(commands.cont_run(ContMode.DISCOVER), "cont",
                               "continuity discover")

    def refresh(self):
        m = self.model
        ok = m.link_ok and not m.running
        self.b_verify.configure(state=tk.NORMAL if ok else tk.DISABLED)
        self.b_disc.configure(state=tk.NORMAL if ok else tk.DISABLED)
        rows = m.cont
        npass = sum(1 for r in rows if r.status.value == "pass")
        self.lbl.configure(text=f"{len(rows)} nets   {npass} pass   "
                                f"{len(rows)-npass} not pass")

        self.tv.delete(*self.tv.get_children())
        for r in rows[-400:]:
            tag = "pass" if r.status.value == "pass" else "fail"
            self.tv.insert("", tk.END, values=(r.hi, r.lo, r.status.value), tags=(tag,))

        # Wiring view: one tick per net, green pass / red otherwise.
        c = self.canvas
        c.delete("all")
        w = max(c.winfo_width(), 400)
        show = rows[-160:]
        if not show:
            c.create_text(12, 12, anchor="nw", fill="#90a4ae",
                          text="wiring view — results appear here as they stream in")
            return
        step = max(w / max(len(show), 1), 4)
        for i, r in enumerate(show):
            x = 10 + i * step
            good = r.status.value == "pass"
            c.create_line(x, 20, x, 130, width=3,
                          fill="#2e7d32" if good else "#c62828")


# --------------------------------------------------------------------------- #
# Task 6 — resistance
# --------------------------------------------------------------------------- #

class ResistanceScreen(Screen):
    def build(self):
        self.h1("Resistance")
        bar = tk.Frame(self, bg="#fafafa")
        bar.pack(fill=tk.X, **PAD)
        self.b_run = tk.Button(bar, text="Run resistance", width=18,
                               command=lambda: self.app.start_run(
                                   commands.res_run(), "res", "resistance"))
        self.b_run.pack(side=tk.LEFT, padx=4)
        self.lbl_cond = tk.Label(bar, text="", bg="#fafafa", font=("Consolas", 10))
        self.lbl_cond.pack(side=tk.LEFT, padx=14)

        self.note = tk.Label(self, bg="#fff8e1", anchor="w", justify=tk.LEFT,
                             font=("Segoe UI", 10), padx=10, pady=6,
                             text="Note: the instrument reports fail_high on every "
                                  "net until the 4-wire rewrite (FW-02) lands. The "
                                  "event format is final; the measurement is not.")
        self.note.pack(fill=tk.X, **PAD)

        # Ranked by margin to limit — the useful ordering when triaging.
        self.tv = self.tree(("hi", "lo", "milliohms", "result", "margin to limit"),
                            (80, 80, 120, 110, 140), height=16)

    def refresh(self):
        m = self.model
        self.b_run.configure(
            state=tk.NORMAL if (m.link_ok and not m.running) else tk.DISABLED)
        cal, lim = m.cal, m.limits
        self.lbl_cond.configure(text=(
            f"I={getattr(cal,'current_ua','?')} uA  gain={getattr(cal,'gain','?')}  "
            f"Rref={getattr(cal,'rref_mohm','?')} mohm   "
            f"limit={getattr(lim,'r_max_mohm','?')} mohm"))

        limit = getattr(lim, "r_max_mohm", None)
        rows = sorted(m.res, key=lambda r: (limit - r.milliohms) if limit else r.milliohms)
        self.tv.delete(*self.tv.get_children())
        for r in rows[:400]:
            margin = f"{limit - r.milliohms:+d}" if limit is not None else "?"
            tag = "pass" if r.status.value == "pass" else "fail"
            self.tv.insert("", tk.END, tags=(tag,),
                           values=(r.hi, r.lo, r.milliohms, r.status.value, margin))


# --------------------------------------------------------------------------- #
# Task 7 — HV insulation
# --------------------------------------------------------------------------- #

class InsulationScreen(Screen):
    """Arming is a deliberate, explicit action and nothing else (§2 rule 1)."""

    def build(self):
        self.h1("HV insulation — 500 V")
        self.warn = tk.Label(self, bg="#ffebee", fg="#b71c1c", anchor="w",
                             font=("Segoe UI", 11, "bold"), padx=10, pady=7)
        self.warn.pack(fill=tk.X, **PAD)

        bar = tk.Frame(self, bg="#fafafa")
        bar.pack(fill=tk.X, **PAD)
        self.b_arm = tk.Button(bar, text="ARM HV", width=14, bg="#ffcdd2",
                               font=("Segoe UI", 11, "bold"), command=self.arm)
        self.b_arm.pack(side=tk.LEFT, padx=4)
        self.b_run = tk.Button(bar, text="Run insulation", width=16,
                               command=self.run_insul)
        self.b_run.pack(side=tk.LEFT, padx=4)
        self.b_hv0 = tk.Button(bar, text="Rail to 0 V", width=12,
                               command=lambda: self.app.send(
                                   commands.hv_set(0), "hv set 0"))
        self.b_hv0.pack(side=tk.LEFT, padx=4)
        self.lbl_rail = tk.Label(bar, text="", bg="#fafafa",
                                 font=("Consolas", 12, "bold"))
        self.lbl_rail.pack(side=tk.LEFT, padx=16)

        self.tv = self.tree(("net", "leakage (mohm)", "result"), (90, 180, 120), height=16)

    def arm(self):
        if not self.model.insulation_allowed:
            return
        if confirm(self, "Arm HV",
                   "This arms the 500 V insulation test.\n\n"
                   "Confirm the harness is on the HV fixture and nobody is "
                   "touching it.\n\nArm now?"):
            self.app.send(commands.insul_arm(), "arm")

    def run_insul(self):
        if confirm(self, "Run insulation",
                   "500 V will be applied to the harness.\n\nStart the run?"):
            self.app.start_run(commands.insul_run(), "insul", "insulation")

    def refresh(self):
        m = self.model
        if not m.link_ok:
            self.warn.configure(text="LINK LOST — state unknown. HV controls disabled.")
        elif m.fixture is not Fixture.HV:
            self.warn.configure(
                text=f"Harness is on '{m.fixture.value if m.fixture else '?'}' — "
                     "insulation is locked until the instrument reports the HV fixture.")
        elif not m.armed:
            self.warn.configure(text="On the HV fixture. Not armed.")
        else:
            self.warn.configure(text="ARMED — 500 V may be applied at any moment.")

        allowed = m.insulation_allowed and not m.running
        self.b_arm.configure(state=tk.NORMAL if (allowed and not m.armed) else tk.DISABLED)
        self.b_run.configure(state=tk.NORMAL if (m.can_energise and not m.running)
                             else tk.DISABLED)
        self.b_hv0.configure(state=tk.NORMAL if m.link_ok else tk.DISABLED)
        self.lbl_rail.configure(
            text=f"rail {m.hv_mv/1000.0:.1f} V",
            fg="#c62828" if m.hv_live else "#37474f")

        self.tv.delete(*self.tv.get_children())
        for r in m.insul[-400:]:
            tag = "pass" if r.status.value == "pass" else "fail"
            self.tv.insert("", tk.END, values=(r.net, r.leak_mohm, r.status.value),
                           tags=(tag,))


# --------------------------------------------------------------------------- #
# Task 4 — netlist manager
# --------------------------------------------------------------------------- #

class NetlistScreen(Screen):
    def build(self):
        self.h1("Netlist")
        bar = tk.Frame(self, bg="#fafafa")
        bar.pack(fill=tk.X, **PAD)
        for text, cmd in (("Load file…", self.load),
                          ("Save file…", self.save),
                          ("Upload to instrument", self.upload),
                          ("Download from instrument", self.download),
                          ("Clear", self.clear)):
            tk.Button(bar, text=text, command=cmd, width=20).pack(side=tk.LEFT, padx=3)

        add = tk.Frame(self, bg="#fafafa")
        add.pack(fill=tk.X, **PAD)
        tk.Label(add, text="hi", bg="#fafafa").pack(side=tk.LEFT)
        self.e_hi = tk.Entry(add, width=6); self.e_hi.pack(side=tk.LEFT, padx=4)
        tk.Label(add, text="lo", bg="#fafafa").pack(side=tk.LEFT)
        self.e_lo = tk.Entry(add, width=6); self.e_lo.pack(side=tk.LEFT, padx=4)
        tk.Button(add, text="Add", command=self.add_row).pack(side=tk.LEFT, padx=4)
        tk.Button(add, text="Remove selected", command=self.del_row).pack(side=tk.LEFT, padx=4)
        self.lbl = tk.Label(add, text="", bg="#fafafa")
        self.lbl.pack(side=tk.LEFT, padx=14)

        self.tv = self.tree(("#", "hi", "lo"), (60, 100, 100), height=17)

    def add_row(self):
        try:
            hi, lo = int(self.e_hi.get()), int(self.e_lo.get())
        except ValueError:
            return
        # Pins are 1-based 1..256 (§3.2.1); refuse locally rather than earn ERANGE.
        if not (1 <= hi <= 256 and 1 <= lo <= 256):
            self.app._toasts.put("pins must be 1..256")
            return
        self.model.netlist.append((hi, lo))
        self.app._dirty.set()

    def del_row(self):
        for iid in self.tv.selection():
            idx = int(self.tv.item(iid, "values")[0]) - 1
            if 0 <= idx < len(self.model.netlist):
                self.model.netlist.pop(idx)
        self.app._dirty.set()

    def clear(self):
        self.model.netlist.clear()
        self.app._dirty.set()

    def load(self):
        path = filedialog.askopenfilename(
            title="Load netlist", filetypes=[("Netlist", "*.csv *.txt"), ("All", "*.*")])
        if not path:
            return
        rows = []
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.replace(",", " ").split()
                if len(parts) >= 2:
                    try:
                        rows.append((int(parts[0]), int(parts[1])))
                    except ValueError:
                        pass
        self.model.netlist[:] = rows
        self.app._dirty.set()

    def save(self):
        path = filedialog.asksaveasfilename(
            title="Save netlist", defaultextension=".csv")
        if not path:
            return
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("# hi,lo\n")
            for hi, lo in self.model.netlist:
                fh.write(f"{hi},{lo}\n")

    def upload(self):
        rows = list(self.model.netlist)

        def run():
            self.app.cm.execute(commands.netlist_begin(len(rows)))
            for hi, lo in rows:
                self.app.cm.execute(commands.netlist_add(hi, lo))
            return f"uploaded: {self.app.cm.execute(commands.netlist_end())}"
        self.app._async(run)

    def download(self):
        def run():
            entries = self.app.cm.netlist_get()
            self.model.netlist[:] = [(e.hi, e.lo) for e in entries]
            return f"downloaded {len(entries)} entries"
        self.app._async(run)

    def refresh(self):
        self.lbl.configure(text=f"{len(self.model.netlist)} entries")
        self.tv.delete(*self.tv.get_children())
        for i, (hi, lo) in enumerate(self.model.netlist, 1):
            self.tv.insert("", tk.END, values=(i, hi, lo))


# --------------------------------------------------------------------------- #
# Task 9 — faults + history
# --------------------------------------------------------------------------- #

class FaultsScreen(Screen):
    def build(self):
        self.h1("Faults")
        bar = tk.Frame(self, bg="#fafafa")
        bar.pack(fill=tk.X, **PAD)
        # Deliberate operator action only — never automatic (§3.2.1).
        self.b_clear = tk.Button(bar, text="Clear fault latch", width=18,
                                 command=self.clear_fault)
        self.b_clear.pack(side=tk.LEFT, padx=4)
        tk.Button(bar, text="Clear list", width=14,
                  command=self.model.clear_results).pack(side=tk.LEFT, padx=4)
        self.tv = self.tree(("time", "code", "detail"), (110, 80, 460), height=10)

        tk.Label(self, text="Instrument log", bg="#fafafa", anchor="w",
                 font=("Segoe UI", 12, "bold")).pack(fill=tk.X, padx=12)
        self.txt = tk.Text(self, height=12, font=("Consolas", 9), bg="white")
        self.txt.pack(fill=tk.BOTH, expand=True, **PAD)

    def clear_fault(self):
        if confirm(self, "Clear fault",
                   "This forces the instrument safe and then clears the fault "
                   "latch.\n\nOnly do this once the cause is understood.\n\nClear?"):
            self.app.send(commands.fault_clear(), "clear fault")

    def refresh(self):
        self.b_clear.configure(state=tk.NORMAL if self.model.link_ok else tk.DISABLED)
        self.tv.delete(*self.tv.get_children())
        for ts, f in self.model.faults[-200:]:
            self.tv.insert("", tk.END, tags=("fail",),
                           values=(time.strftime("%H:%M:%S", time.localtime(ts)),
                                   f.code, f.text))
        self.txt.delete("1.0", tk.END)
        self.txt.insert(tk.END, "\n".join(self.model.logs[-200:]))
        self.txt.see(tk.END)


class HistoryScreen(Screen):
    def build(self):
        self.h1("History")
        self.lbl = tk.Label(self, text="", bg="#fafafa", anchor="w",
                            font=("Consolas", 11), justify=tk.LEFT)
        self.lbl.pack(fill=tk.X, **PAD)
        self.tv = self.tree(("when", "test", "passed", "failed", "yield"),
                            (150, 90, 90, 90, 90), height=12)
        tk.Label(self, text="Fault pareto", bg="#fafafa", anchor="w",
                 font=("Segoe UI", 12, "bold")).pack(fill=tk.X, padx=12)
        self.pareto = tk.Text(self, height=9, font=("Consolas", 10), bg="white")
        self.pareto.pack(fill=tk.BOTH, expand=True, **PAD)

    def refresh(self):
        m = self.model
        first_pass = sum(1 for h in m.history if h.failed == 0)
        self.lbl.configure(text=(
            f"{len(m.history)} runs    first-pass yield "
            f"{100.0*first_pass/len(m.history):.1f}%" if m.history else "No runs yet."))
        self.tv.delete(*self.tv.get_children())
        for h in reversed(m.history[-200:]):
            self.tv.insert("", tk.END, tags=("pass" if h.failed == 0 else "fail",),
                           values=(time.strftime("%H:%M:%S", time.localtime(h.finished)),
                                   h.kind, h.passed, h.failed, f"{h.yield_pct:.1f}%"))
        counts: dict[str, int] = {}
        for _, f in m.faults:
            counts[f.code] = counts.get(f.code, 0) + 1
        self.pareto.delete("1.0", tk.END)
        for code, n in sorted(counts.items(), key=lambda kv: -kv[1]):
            self.pareto.insert(tk.END, f"{code:<6} {'#' * min(n, 60)} {n}\n")


# --------------------------------------------------------------------------- #
# Task 10 — diagnostics
# --------------------------------------------------------------------------- #

class DiagnosticsScreen(Screen):
    def build(self):
        self.h1("Diagnostics")
        bar = tk.Frame(self, bg="#fafafa")
        bar.pack(fill=tk.X, **PAD)
        tk.Button(bar, text="Ping", width=10,
                  command=lambda: self.app.send(commands.ping(), "ping")).pack(side=tk.LEFT, padx=3)
        tk.Button(bar, text="Identify", width=10,
                  command=lambda: self.app.send(commands.identify(), "id")).pack(side=tk.LEFT, padx=3)
        tk.Button(bar, text="Status", width=10,
                  command=self.status).pack(side=tk.LEFT, padx=3)
        tk.Button(bar, text="Read cal + limits", width=16,
                  command=self.read_cfg).pack(side=tk.LEFT, padx=3)

        path = tk.Frame(self, bg="#fafafa")
        path.pack(fill=tk.X, **PAD)
        tk.Label(path, text="Manual path   hi", bg="#fafafa").pack(side=tk.LEFT)
        self.e_hi = tk.Entry(path, width=6); self.e_hi.pack(side=tk.LEFT, padx=4)
        tk.Label(path, text="lo", bg="#fafafa").pack(side=tk.LEFT)
        self.e_lo = tk.Entry(path, width=6); self.e_lo.pack(side=tk.LEFT, padx=4)
        tk.Button(path, text="Close path", command=self.manual_path).pack(side=tk.LEFT, padx=4)
        tk.Button(path, text="Open all", command=lambda: self.app.send(
            commands.manual_off(), "manual off")).pack(side=tk.LEFT, padx=4)
        tk.Label(path, bg="#fafafa", fg="#757575",
                 text="  (manual relay control is refused by the instrument by design)"
                 ).pack(side=tk.LEFT)

        lim = tk.Frame(self, bg="#fafafa")
        lim.pack(fill=tk.X, **PAD)
        tk.Label(lim, text="r_max_mohm", bg="#fafafa").pack(side=tk.LEFT)
        self.e_r = tk.Entry(lim, width=10); self.e_r.pack(side=tk.LEFT, padx=4)
        tk.Label(lim, text="ins_min_mohm", bg="#fafafa").pack(side=tk.LEFT)
        self.e_i = tk.Entry(lim, width=14); self.e_i.pack(side=tk.LEFT, padx=4)
        tk.Button(lim, text="Set limits", command=self.set_limits).pack(side=tk.LEFT, padx=4)

        self.info = tk.Label(self, text="", bg="#fafafa", anchor="nw",
                             justify=tk.LEFT, font=("Consolas", 11))
        self.info.pack(fill=tk.BOTH, expand=True, **PAD)

    def status(self):
        def run():
            st = self.app.cm.execute(commands.status())
            self.model.apply_status(st)
            return str(st)
        self.app._async(run)

    def read_cfg(self):
        def run():
            self.model.cal = self.app.cm.execute(commands.cal_get())
            self.model.limits = self.app.cm.execute(commands.limits_get())
            return "cal + limits read"
        self.app._async(run)

    def manual_path(self):
        try:
            hi, lo = int(self.e_hi.get()), int(self.e_lo.get())
        except ValueError:
            return
        self.app.send(commands.manual_path(hi, lo), "manual path")

    def set_limits(self):
        try:
            r, i = int(self.e_r.get()), int(self.e_i.get())
        except ValueError:
            return
        self.app.send(commands.limits_set(r, i), "limits set")

    def refresh(self):
        m = self.model
        self.info.configure(text="\n".join([
            f"link          {'up' if m.link_ok else 'DOWN'}  ({m.link_detail})",
            f"session log   {self.app.cm.logger.path}",
            f"state         {m.state.value if m.state else '?'}",
            f"fixture       {m.fixture.value if m.fixture else '?'}",
            f"rail          {m.hv_mv} mV",
            f"handling      {m.handling.value}",
            f"cal           {m.cal}",
            f"limits        {m.limits}",
            f"netlist       {len(m.netlist)} entries",
        ]))
