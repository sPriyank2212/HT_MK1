"""End-to-end: the real Tk app driving the real simulator over a socket.

Skipped where Tk cannot open a display. The model rules are covered headlessly
in ``test_model.py``; this checks the wiring between shell, screens and the
connection manager, and that the HV controls really are gated by the
instrument's reported fixture rather than by what the GUI asked for.
"""

import time
import unittest

from htproto import commands
from htproto.codec import ContMode, Fixture
from htproto.simulator import SimulatorServer, make_scenario

try:
    import tkinter as tk
    _root = tk.Tk()
    _root.destroy()
    HAVE_TK = True
except Exception:                                   # noqa: BLE001
    HAVE_TK = False


@unittest.skipUnless(HAVE_TK, "no display for Tk")
class GuiSmoke(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = SimulatorServer(make_scenario("pass", 6), port=0,
                                     interval=0.0).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.stop()

    def setUp(self):
        from htgui.app import HtGuiApp
        self.app = HtGuiApp(host=self.server.host, port=self.server.port)
        self.addCleanup(self.app.destroy)

    def pump(self, seconds=0.5):
        end = time.time() + seconds
        while time.time() < end:
            self.app.update()
            time.sleep(0.005)

    def connect(self):
        self.app.toggle_link()
        self.pump(2.0)
        self.assertTrue(self.app.model.link_ok, "did not connect to simulator")

    def test_every_screen_renders(self):
        self.connect()
        for name in self.app.screens:
            self.app.show(name)
            self.pump(0.1)

    def test_hv_controls_gated_by_reported_fixture(self):
        self.connect()
        ins = self.app.screens["HV insulation"]
        self.app.show("HV insulation")

        self.app.send(commands.fixture(Fixture.MTX), "fixture")
        self.pump(0.8)
        self.assertEqual(str(ins.b_arm.cget("state")), "disabled")

        self.app.send(commands.fixture(Fixture.HV), "fixture")
        self.pump(0.8)
        self.assertEqual(str(ins.b_arm.cget("state")), "normal")

    def test_fixture_change_while_armed_disarms(self):
        self.connect()
        self.app.send(commands.fixture(Fixture.HV), "fixture")
        self.pump(0.8)
        self.app.send(commands.insul_arm(), "arm")
        self.pump(0.8)
        self.assertTrue(self.app.model.armed)

        # arm on HV, claim a move back to the matrix, then try to energise
        self.app.send(commands.fixture(Fixture.MTX), "fixture")
        self.pump(0.8)
        self.assertFalse(self.app.model.armed)
        self.assertFalse(self.app.model.can_energise)

    def test_verify_without_netlist_is_refused(self):
        self.connect()
        self.app.start_run(commands.cont_run(ContMode.VERIFY), "cont", "cont")
        self.pump(1.2)
        self.assertFalse(self.app.model.running)
        self.assertEqual(self.app.model.history, [])

    def test_run_streams_results_and_closes(self):
        self.connect()
        self.app.send(commands.fixture(Fixture.MTX), "fixture")
        self.pump(0.5)
        self.app.model.netlist[:] = [(i, i + 1) for i in range(1, 7)]
        self.app.screens["Netlist"].upload()
        self.pump(1.5)
        self.app.start_run(commands.cont_run(ContMode.VERIFY), "cont", "cont")
        self.pump(3.0)
        self.assertTrue(self.app.model.cont, "no !CONT results arrived")
        self.assertEqual(len(self.app.model.history), 1)
        self.assertFalse(self.app.model.running)

    def test_link_loss_shows_unknown_never_safe(self):
        self.connect()
        self.app.cm.disconnect()
        self.app.model.set_link(False, "test pulled the plug")
        self.pump(0.4)
        self.assertEqual(self.app.model.handling.value, "unknown")
        self.assertIn("UNKNOWN", self.app.banner.cget("text").upper())


if __name__ == "__main__":
    unittest.main()
