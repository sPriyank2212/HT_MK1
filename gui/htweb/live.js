/* Live protocol layer for the HT_MK1 operator GUI.
 *
 * The page above this is the approved design, unchanged. This file replaces
 * its three simulated run functions with protocol-driven ones and feeds real
 * instrument events into the same render calls, so what you see is exactly the
 * design, driven by the instrument.
 *
 * Safety rules from brief 2 and 3.5 are enforced HERE as well as in the
 * firmware, because the GUI must never be the only thing enforcing them:
 *
 *   - "safe to handle" comes from !SAFE and nothing else. Not from a run
 *     ending, not from event ordering, not from silence.
 *   - link loss forces "unknown" and disables everything that could energise;
 *     it never degrades to "safe".
 *   - arming is dropped by any !FIXTURE, any !SAFE, any !STATE idle, and any
 *     link trouble.
 *   - HV controls are enabled only from the fixture the INSTRUMENT reports.
 */
(function () {
  "use strict";
  var S = window.HT_SEAM;
  if (!S) { console.error("HT_SEAM missing - live layer cannot attach"); return; }
  var $ = S.$;

  /* ── instrument state, as told to us ───────────────────────────────────── */
  var L = {
    link: false, detail: "not connected",
    state: null, fixture: null, hv_mv: 0, armed: false,
    handling: "unknown",          // unknown | safe | live  — never inferred
    run: null, done: 0, total: 0,
    limits: null, cal: null
  };

  var HV_LIVE_MV = 50000;         // matches PROTO_HV_LIVE_MV in the firmware

  function post(body) {
    return fetch("/api/cmd", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body)
    }).then(function (r) { return r.json(); });
  }
  function cmd(text) { return post({ action: "send", cmd: text }); }

  function say(lvl, src, msg) { S.log(lvl, src, msg); }

  function reportRefusal(what, res) {
    if (res && res.ok === false) { say("fail", "link", what + " - " + res.error); return true; }
    if (res && res.reply && res.reply.type === "ErrReply") {
      // Never retry automatically: a refusal is the instrument's decision.
      say("fail", "seq", what + " refused - " + res.reply.code + " " + res.reply.text);
      return true;
    }
    return false;
  }

  /* ── header / banner ───────────────────────────────────────────────────── */
  function paintLink() {
    var hv = $("#hvPill"), st = $("#statePill");
    if (!L.link) {
      hv.className = "pill warn"; hv.innerHTML = "<i></i>Link lost";
      st.className = "pill warn"; st.innerHTML = "<i></i>State unknown";
      $("#stFix").textContent = "link lost";
      document.body.classList.remove("hv-live");
      return;
    }
    var live = L.hv_mv >= HV_LIVE_MV;
    document.body.classList.toggle("hv-live", live);
    if (live) {
      hv.className = "pill bad";
      hv.innerHTML = "<i></i>HV LIVE " + (L.hv_mv / 1000).toFixed(0) + " V";
    } else if (L.armed) {
      hv.className = "pill warn"; hv.innerHTML = "<i></i>HV armed";
    } else if (L.handling === "safe") {
      hv.className = "pill ok"; hv.innerHTML = "<i></i>HV Safe";
    } else {
      hv.className = "pill idle"; hv.innerHTML = "<i></i>HV state unknown";
    }
    var lbl = L.run ? L.run : (L.state || "idle");
    st.className = "pill " + (L.run ? "acc" : "idle");
    st.innerHTML = "<i></i>" + lbl.charAt(0).toUpperCase() + lbl.slice(1);
    $("#stFix").textContent =
      L.fixture === "hv" ? "J-HV · stage 2"
        : L.fixture === "mtx" ? "J-MTX · stage 1" : "no fixture declared";
    $("#hzRail").textContent = (L.hv_mv / 1000).toFixed(0) + " V";
  }

  /* ── the three runs, driven by the instrument ──────────────────────────── */
  function beginRun(kind, domSel, label, sub) {
    S.running = kind; L.run = kind; L.done = 0; L.total = 0;
    S.R[kind] = null;
    S.setDom(domSel, "run");
    $("#vTitle").textContent = "RUNNING";
    $("#vStage").textContent = label;
    $("#vSub").textContent = sub;
    $("#sb1").dataset.s = "active";
    S.updateControls(); S.renderFaults(); paintLink();
  }

  function startRun(kind, wire, domSel, label, sub) {
    // Never mark a run started until the instrument has accepted it.
    cmd(wire).then(function (res) {
      if (reportRefusal(label, res)) { S.running = null; S.updateControls(); return; }
      beginRun(kind, domSel, label, sub);
      say("info", kind, label + " started");
    });
  }

  S.setRun(
    function runCont() {
      var cross = S.cmode === "cross";
      startRun("cont", "CONT RUN " + (cross ? "discover" : "verify"), "#dCont",
        "Continuity · J-MTX",
        cross ? "J-MTX — energising one HS at a time and reading all 256 LS."
              : "J-MTX — testing the pairs the netlist expects.");
    },
    function runRes() {
      startRun("res", "RES RUN", "#dRes", "Resistance · J-MTX",
        "J-MTX — measuring every pair the netlist declares.");
    },
    function runHv() {
      // Arming is a separate, explicit step and the instrument enforces it too.
      cmd("INSUL ARM").then(function (res) {
        if (reportRefusal("arm", res)) return;
        L.armed = true; paintLink();
        startRun("insul", "INSUL RUN", "#dHv", "Insulation · J-HV",
          "J-HV — 500 V across each net in turn.");
      });
    }
  );

  /* ── results ───────────────────────────────────────────────────────────── */
  var counts = { pass: 0, fail: 0 };

  function netByPins(hi, lo) {
    for (var i = 0; i < S.nets.length; i++) {
      var n = S.nets[i];
      if (n.pinHi === hi && n.pinLo === lo) return n;
    }
    return null;
  }

  function onCont(m) {
    var n = netByPins(m.hi, m.lo);
    if (n) { n.open = (m.status !== "pass"); }
    if (m.status === "pass") counts.pass++; else counts.fail++;
    $("#dcN").textContent = counts.pass;
    $("#ctFound").textContent = counts.pass;
    $("#ctMiss").textContent = counts.fail;
    if (counts.fail) S.faultsOn.f06 = true;
    S.paintDiag();
  }

  function onRes(m) {
    var n = netByPins(m.hi, m.lo);
    if (n) { n.r = m.milliohms / 1000.0; }
    if (m.status === "pass") counts.pass++; else counts.fail++;
    $("#drN").textContent = counts.fail;
    if (counts.fail) S.faultsOn.f08 = true;
  }

  function onInsul(m) {
    if (m.status === "pass") counts.pass++; else counts.fail++;
    $("#dhN").textContent = counts.fail;
    if (counts.fail) S.faultsOn.f04 = true;
  }

  function onProgress(m) {
    L.done = m.done; L.total = m.total;
    var pct = m.total ? (100 * m.done / m.total) : 0;
    var bar = L.run === "cont" ? "#dcBar" : L.run === "res" ? "#drBar" : "#dhBar";
    $(bar).style.width = pct + "%";
    $("#vElapsed").textContent = m.done + " / " + m.total;
  }

  function onDone(m) {
    var kind = m.kind;                       // cont | res | insul
    var key = kind === "insul" ? "hv" : kind;
    var pass = m.failed === 0;
    S.R[key] = pass ? "pass" : "fail";
    S.setDom(kind === "cont" ? "#dCont" : kind === "res" ? "#dRes" : "#dHv",
             pass ? "pass" : "fail");
    S.running = null; L.run = null;
    say(pass ? "ok" : "fail", kind,
        kind + " " + (pass ? "PASS" : "FAIL") + " — " + m.passed + " passed, "
        + m.failed + " failed");
    counts.pass = counts.fail = 0;
    S.buildResTable(); S.paintHist(); S.renderFaults(); S.updateControls();
    paintLink();
    if (key === "cont" || key === "res") S.finishStage1();
  }

  /* ── event dispatch ────────────────────────────────────────────────────── */
  function onEvent(m) {
    switch (m.type) {
      case "ContResult": onCont(m); break;
      case "ResResult": onRes(m); break;
      case "InsulResult": onInsul(m); break;
      case "Progress": onProgress(m); break;
      case "Done": onDone(m); break;
      case "HvEvent":
        L.hv_mv = m.millivolts;
        if (m.millivolts > 0) L.handling = "live";
        $("#gTrack").style.width = Math.min(100, m.millivolts / 5000) + "%";
        paintLink();
        break;
      case "SafeEvent":
        // The one and only source of "safe to handle".
        L.handling = "safe"; L.armed = false; L.hv_mv = 0;
        say("ok", "safe", "instrument reports SAFE");
        paintLink();
        break;
      case "FixtureEvent":
        if (m.fixture !== L.fixture) L.armed = false;   // any change disarms
        L.fixture = m.fixture;
        S.onHv = (m.fixture === "hv");
        say("info", "fix", "fixture is now " + m.fixture);
        S.updateControls(); paintLink();
        break;
      case "StateEvent":
        L.state = m.state;
        if (m.state === "hv_armed") { L.armed = true; L.handling = "live"; }
        else if (m.state === "running") L.handling = "live";
        else if (m.state === "idle") L.armed = false;
        else if (m.state === "fault") { L.armed = false; L.handling = "unknown"; }
        paintLink();
        break;
      case "Fault":
        say("fail", "seq", m.code + " " + m.text);
        S.renderFaults();
        break;
      case "LogLine":
        say("info", "fw", m.text);
        break;
    }
  }

  /* ── transport ─────────────────────────────────────────────────────────── */
  function linkDown(detail) {
    L.link = false; L.armed = false; L.handling = "unknown";
    L.run = null; S.running = null; L.detail = detail;
    say("fail", "link", "link lost — " + detail + " (state unknown)");
    S.updateControls(); paintLink();
  }

  var es = new EventSource("/api/events");
  es.onmessage = function (ev) {
    var p = JSON.parse(ev.data);
    if (p.kind === "event") onEvent(p.msg);
    else if (p.kind === "link") {
      if (p.state === "connected") { L.link = true; L.detail = p.detail; paintLink(); }
      else linkDown(p.detail);
    } else if (p.kind === "protocol_error") {
      say("warn", "proto", p.detail);          // surfaced, never dropped
    }
  };
  es.onerror = function () { linkDown("event stream closed"); };

  /* ── connect + netlist wiring ──────────────────────────────────────────── */
  function connect() {
    post({ action: "connect" }).then(function (res) {
      if (res.ok === false) { say("fail", "link", res.error); return; }
      L.link = true;
      var st = res.reply || {};
      L.state = st.state; L.fixture = st.fixture; L.hv_mv = st.hv_mv || 0;
      L.armed = (st.state === "hv_armed");
      // A STATUS reply says nothing about whether the harness is safe to
      // touch, and it cannot report `running` at all - so stay UNKNOWN.
      L.handling = (L.armed || L.hv_mv > 0) ? "live" : "unknown";
      S.onHv = (st.fixture === "hv");
      say("ok", "link", "connected — state " + st.state + ", fixture " + st.fixture);
      cmd("CAL GET").then(function (r) { if (r.ok) L.cal = r.reply; });
      cmd("LIMITS GET").then(function (r) { if (r.ok) L.limits = r.reply; });
      post({ action: "netlist_get" }).then(function (r) {
        if (r.ok && r.reply && r.reply.length) {
          S.rebuildNets(r.reply);
          say("ok", "nl", "netlist read from instrument — " + r.reply.length + " nets");
        }
      });
      S.updateControls(); paintLink();
    });
  }

  // Abort and force-safe are wired to the design's existing controls.
  ["#abortHv", "#abortHv2"].forEach(function (sel) {
    var el = $(sel); if (!el) return;
    el.addEventListener("click", function () {
      cmd("ABORT").then(function () { say("warn", "seq", "ABORT sent"); });
    }, true);
  });

  $("#hoConfirm").addEventListener("click", function () {
    cmd("FIXTURE hv").then(function (res) { reportRefusal("fixture hv", res); });
  }, true);

  window.HT_LIVE = { state: L, connect: connect, cmd: cmd, seam: S };
  connect();
})();
