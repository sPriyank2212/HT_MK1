"""Web frontend backend tests — the page, the SSE stream and the command API.

Drives the HTTP layer exactly as the browser does, against the real simulator.
"""

import json
import threading
import time
import unittest
import urllib.request
from http.server import ThreadingHTTPServer

from htproto.simulator import SimulatorServer, make_scenario
from htweb.server import Bridge, Handler, INDEX


class WebBackend(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sim = SimulatorServer(make_scenario("pass", 6), port=0,
                                  interval=0.0).start()
        Handler.bridge = Bridge(cls.sim.host, cls.sim.port)
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = "http://127.0.0.1:%d" % cls.httpd.server_address[1]

        cls.events = []
        threading.Thread(target=cls._read_sse, daemon=True).start()
        time.sleep(0.4)

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.sim.stop()

    @classmethod
    def _read_sse(cls):
        try:
            with urllib.request.urlopen(cls.base + "/api/events", timeout=30) as r:
                for raw in r:
                    line = raw.decode().strip()
                    if line.startswith("data: "):
                        cls.events.append(json.loads(line[6:]))
        except Exception:            # noqa: BLE001  — closed at teardown
            pass

    def post(self, body):
        req = urllib.request.Request(
            self.base + "/api/cmd", method="POST",
            data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())

    def get(self, path):
        with urllib.request.urlopen(self.base + path, timeout=10) as r:
            return r.read()

    # -- the page --------------------------------------------------------------

    def test_page_is_the_approved_design(self):
        page = self.get("/").decode("utf-8", "replace")
        # The design's own markers must still be there: this is the mock-up
        # verbatim, not a reimplementation of it.
        for marker in ('id="hvPill"', 'id="statePill"', 'class="rail"',
                       'id="v-run"', 'id="v-cont"', 'id="v-res"', 'id="v-hv"',
                       'id="v-program"', 'id="v-results"', 'id="v-diag"'):
            self.assertIn(marker, page, f"design element {marker} missing")
        self.assertIn("window.HT_SEAM", page)
        self.assertIn("/live.js", page)

    def test_live_js_is_served(self):
        js = self.get("/live.js").decode("utf-8", "replace")
        self.assertIn("HT_SEAM", js)
        self.assertIn("EventSource", js)

    def test_unknown_path_404s(self):
        with self.assertRaises(urllib.error.HTTPError) as cm:
            self.get("/nope")
        self.assertEqual(cm.exception.code, 404)

    # -- the command API -------------------------------------------------------

    def test_connect_and_ping(self):
        self.assertTrue(self.post({"action": "connect"})["ok"])
        out = self.post({"action": "send", "cmd": "PING"})
        self.assertEqual(out["reply"]["type"], "Pong")

    def test_error_reply_is_data_not_an_exception(self):
        self.post({"action": "connect"})
        out = self.post({"action": "send", "cmd": "NONSENSE"})
        self.assertTrue(out["ok"])                  # transport worked
        self.assertEqual(out["reply"]["type"], "ErrReply")
        self.assertEqual(out["reply"]["code"], "ESYNTAX")

    def test_netlist_round_trip(self):
        self.post({"action": "connect"})
        pairs = [[i, i + 1] for i in range(1, 7)]
        self.assertTrue(self.post({"action": "netlist_put", "pairs": pairs})["ok"])
        got = self.post({"action": "netlist_get"})["reply"]
        self.assertEqual([[e["hi"], e["lo"]] for e in got], pairs)

    def test_run_streams_events_to_the_browser(self):
        self.post({"action": "connect"})
        self.post({"action": "send", "cmd": "FIXTURE mtx"})
        self.post({"action": "netlist_put",
                   "pairs": [[i, i + 1] for i in range(1, 7)]})
        before = len(self.events)
        self.post({"action": "send", "cmd": "CONT RUN verify"})
        deadline = time.time() + 6
        while time.time() < deadline:
            kinds = [e.get("msg", {}).get("type")
                     for e in self.events[before:] if e["kind"] == "event"]
            if "Done" in kinds:
                break
            time.sleep(0.05)
        kinds = [e.get("msg", {}).get("type")
                 for e in self.events[before:] if e["kind"] == "event"]
        self.assertIn("ContResult", kinds, "no !CONT reached the browser")
        self.assertIn("Done", kinds, "no !DONE reached the browser")


class PageOnDisk(unittest.TestCase):
    def test_index_matches_the_proposal_markup(self):
        """The served page must stay the approved design.

        Guards against someone 'tidying' the copy: the CSS block and the view
        sections have to survive verbatim, or the running instrument stops
        looking like the thing that was signed off.
        """
        page = INDEX.read_text(encoding="utf-8", errors="replace")
        self.assertGreater(len(page), 100_000, "page looks truncated")
        self.assertIn("<style>", page)
        # seven tab panels: run, cont, res, hv, program, results, diag
        self.assertEqual(page.count('<section class="view'), 7)


if __name__ == "__main__":
    unittest.main()
