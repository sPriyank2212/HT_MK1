"""Safety-rule tests for the GUI state model (brief §2 and §3.5).

No Tk here on purpose: these are the rules that must not be wrong, so they are
kept testable without a display.
"""

import unittest

from htproto import messages as m
from htproto.codec import Fixture, State, TestKind
from htgui.model import Handling, InstrumentModel


def connected() -> InstrumentModel:
    mod = InstrumentModel()
    mod.set_link(True, "test")
    return mod


class HandlingRules(unittest.TestCase):
    def test_starts_unknown(self):
        self.assertIs(InstrumentModel().handling, Handling.UNKNOWN)

    def test_safe_only_from_safe_event(self):
        mod = connected()
        mod.apply_event(m.StateEvent(state=State.RUNNING))
        self.assertIs(mod.handling, Handling.LIVE)
        # !DONE ends the run but says nothing about the hardware (§3.3).
        mod.apply_event(m.Done(kind=TestKind.CONT, passed=3, failed=0))
        self.assertIsNot(mod.handling, Handling.SAFE)
        mod.apply_event(m.SafeEvent())
        self.assertIs(mod.handling, Handling.SAFE)

    def test_run_end_without_safe_is_unknown_not_live(self):
        # Continuity/resistance never emit !SAFE, so after !DONE we have no
        # evidence either way. "Unknown" is the honest answer; claiming
        # "energised" asserts something we were never told.
        mod = connected()
        mod.note_run_started("cont")
        self.assertIs(mod.handling, Handling.LIVE)
        mod.apply_event(m.Done(kind=TestKind.CONT, passed=1, failed=0))
        self.assertIs(mod.handling, Handling.UNKNOWN)

    def test_insulation_done_keeps_safe(self):
        # Insulation sends !HV 0, !SAFE, !STATE idle, !DONE — the !SAFE must
        # survive the !DONE that follows it.
        mod = connected()
        mod.note_run_started("insul")
        mod.apply_event(m.HvEvent(millivolts=0))
        mod.apply_event(m.SafeEvent())
        mod.apply_event(m.StateEvent(state=State.IDLE))
        mod.apply_event(m.Done(kind=TestKind.INSUL, passed=4, failed=0))
        self.assertIs(mod.handling, Handling.SAFE)

    def test_done_while_rail_up_stays_live(self):
        mod = connected()
        mod.note_run_started("insul")
        mod.apply_event(m.HvEvent(millivolts=500_000))
        mod.apply_event(m.Done(kind=TestKind.INSUL, passed=0, failed=1))
        self.assertIs(mod.handling, Handling.LIVE)

    def test_link_loss_never_reports_safe(self):
        mod = connected()
        mod.apply_event(m.SafeEvent())
        self.assertIs(mod.handling, Handling.SAFE)
        mod.set_link(False, "cable pulled")
        self.assertIs(mod.handling, Handling.UNKNOWN)   # §2 rule 4

    def test_rail_up_is_live(self):
        mod = connected()
        mod.apply_event(m.SafeEvent())
        mod.apply_event(m.HvEvent(millivolts=500_000))
        self.assertIs(mod.handling, Handling.LIVE)
        self.assertTrue(mod.hv_live)

    def test_hv_live_threshold(self):
        mod = connected()
        mod.apply_event(m.HvEvent(millivolts=49_999))
        self.assertFalse(mod.hv_live)
        mod.apply_event(m.HvEvent(millivolts=50_000))
        self.assertTrue(mod.hv_live)     # at or above, per PROTO_HV_LIVE_MV


class ArmingRules(unittest.TestCase):
    def test_arm_needs_hv_fixture(self):
        mod = connected()
        mod.apply_event(m.FixtureEvent(fixture=Fixture.MTX))
        self.assertFalse(mod.insulation_allowed)
        mod.apply_event(m.FixtureEvent(fixture=Fixture.HV))
        self.assertTrue(mod.insulation_allowed)

    def test_fixture_change_drops_the_arm(self):
        mod = connected()
        mod.apply_event(m.FixtureEvent(fixture=Fixture.HV))
        mod.apply_event(m.StateEvent(state=State.HV_ARMED))
        self.assertTrue(mod.can_energise)
        # The attack this guards: arm on HV, claim a move back, then energise.
        mod.apply_event(m.FixtureEvent(fixture=Fixture.MTX))
        self.assertFalse(mod.armed)
        self.assertFalse(mod.can_energise)

    def test_safe_event_drops_the_arm(self):
        mod = connected()
        mod.apply_event(m.FixtureEvent(fixture=Fixture.HV))
        mod.apply_event(m.StateEvent(state=State.HV_ARMED))
        mod.apply_event(m.SafeEvent())
        self.assertFalse(mod.armed)

    def test_link_loss_drops_the_arm(self):
        mod = connected()
        mod.apply_event(m.FixtureEvent(fixture=Fixture.HV))
        mod.apply_event(m.StateEvent(state=State.HV_ARMED))
        mod.set_link(False, "gone")
        self.assertFalse(mod.armed)
        self.assertFalse(mod.can_energise)
        self.assertFalse(mod.insulation_allowed)

    def test_repeated_fixture_event_keeps_the_arm(self):
        # Re-declaring the SAME fixture is a no-op on the instrument (§3.2.1),
        # so it must not be treated as a change here either.
        mod = connected()
        mod.apply_event(m.FixtureEvent(fixture=Fixture.HV))
        mod.apply_event(m.StateEvent(state=State.HV_ARMED))
        mod.apply_event(m.FixtureEvent(fixture=Fixture.HV))
        self.assertTrue(mod.armed)


class StatusHandshake(unittest.TestCase):
    def test_status_never_asserts_safe(self):
        # STATUS cannot report `running` at all, so an idle STATUS must not be
        # read as "quiet and safe" (§3.2).
        mod = connected()
        mod.apply_status(m.StatusReply(state=State.IDLE, fixture=Fixture.MTX, hv_mv=0))
        self.assertIsNot(mod.handling, Handling.SAFE)

    def test_status_armed_is_live(self):
        mod = connected()
        mod.apply_status(m.StatusReply(state=State.HV_ARMED, fixture=Fixture.HV,
                                       hv_mv=0))
        self.assertTrue(mod.armed)
        self.assertIs(mod.handling, Handling.LIVE)


class RunBookkeeping(unittest.TestCase):
    def test_done_closes_the_run_and_records_history(self):
        mod = connected()
        mod.note_run_started("cont")
        self.assertTrue(mod.running)
        mod.apply_event(m.Progress(done=5, total=10))
        mod.apply_event(m.Done(kind=TestKind.CONT, passed=9, failed=1))
        self.assertFalse(mod.running)
        self.assertEqual(len(mod.history), 1)
        self.assertEqual(mod.history[0].failed, 1)
        self.assertAlmostEqual(mod.history[0].yield_pct, 90.0)

    def test_results_reset_per_run(self):
        mod = connected()
        mod.note_run_started("cont")
        mod.apply_event(m.ContResult(hi=1, lo=2, status=__import__(
            "htproto.codec", fromlist=["ContStatus"]).ContStatus.PASS))
        self.assertEqual(len(mod.cont), 1)
        mod.note_run_started("cont")
        self.assertEqual(len(mod.cont), 0)

    def test_link_loss_clears_run_in_flight(self):
        mod = connected()
        mod.note_run_started("insul")
        mod.set_link(False, "gone")
        self.assertFalse(mod.running)


if __name__ == "__main__":
    unittest.main()
