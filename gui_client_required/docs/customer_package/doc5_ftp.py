# -*- coding: utf-8 -*-
from common import *


def _reference_wires():
    from core.netlist import load_netlist
    from core.netlist import channel_table
    cfg = channel_table(os.path.join(REPO, "netlists", "connector_config.xlsx"))
    nl = load_netlist(os.path.join(REPO, "netlists", "example_cross_connector_test.xlsx"))
    rows = []
    for n in nl.nets:
        a, b = n.pins[0].number, n.pins[1].number
        ca, cb = cfg[a], cfg[b]
        rows.append([n.name, f"{ca['connector_id']} pin {ca['conn_pin']}", f"{cb['connector_id']} pin {cb['conn_pin']}"])
    assert len(rows) == 15
    return rows


def record(d, caption, rows):
    d.table(["Check", "Expected", "Actual", "Pass / Fail"],
            [[c, e, "", ""] for c, e in rows], caption, weights=[26, 42, 20, 12])


def build(path):
    d = new_doc("HT_MK0_FTP", "Functional Test Procedure")
    d.standard_intro(
        purpose=[
            "This procedure verifies that a built HT_MK0 Harness Tester works "
            "as described in the other documents of the package. Each test "
            "case lists the steps to carry out, the result to expect and a "
            "table in which the tester records what was seen.",
        ],
        audience=[
            "Acceptance testers: the people who accept a tester at the end of "
            "build, or after a repair or a software update. Basic use of the "
            "GUI is assumed; the User Manual explains each screen.",
        ],
        related=PACKAGE_DOCS)
    d.h2("Scope")
    d.p("The procedure covers the functions of the HT_MK0: connection, the "
        "connector configuration, Continuity, Cross Continuity and Auto-Scan "
        "testing, stopping and recovering, and the export of results. It does "
        "not cover resistance or insulation measurement, which the HT_MK0 does "
        "not perform.")
    d.h2("Acceptance Criteria")
    d.p("The tester is accepted when every check in test cases TC-01 to TC-08 "
        "is marked Pass, or each deviation is recorded and accepted in the "
        "sign-off section. A check that is not marked is treated as a fail.")
    d.figure(dia("test_flow.png"), "Sequence of the test cases", 14.0)

    # ── 2 Equipment ───────────────────────────────────────────────────────────────────────────────────────
    d.h1("Test Environment and Equipment", page_break=True)
    d.table(["Item", "Details"], [
        ["Tester under test", f"HT_MK0 board with firmware {FW_VERSION} (see the Flashing Procedure)."],
        ["PC", "Windows 10 or 11, 64-bit, ST-Link driver installed."],
        ["GUI", f"`{EXE_NAME}`, run from a folder that can be written to."],
        ["USB cable", "Data-capable, fits CN1 of the board."],
        ["Netlists", "`example_cross_connector_test.xlsx` (15 wires) and `example_straight_only.xlsx` (13 wires), supplied in the package."],
        ["Connector configuration", "The default `connector_config.xlsx` (J1, J2, J3)."],
        ["Reference harness", "A harness with the 15 wires listed below, plugged between Side A and Side B."],
        ["Spare jumper", "One extra wire with connectors, for TC-05."],
        ["Spreadsheet program", "To open the CSV files in TC-08."],
    ], "Equipment", weights=[28, 72])
    d.h2("Reference Harness")
    d.p("The reference harness is a known-good set of 15 wires. It is wired "
        "exactly as the netlist `example_cross_connector_test.xlsx` lists, so "
        "that a correct test passes. A wire may start on one connector and end "
        "on another.")
    d.table(["Net", "Side A end", "Side B end"], _reference_wires(),
            "Wires of the reference harness", weights=[44, 28, 28])
    d.h2("Preconditions")
    d.bullets([
        "The firmware has been flashed and the board shows the three-blink "
        "pattern, then LD1 steady, when the cable is plugged in.",
        "For a clean record, delete the HarnessTesterData folder next to the "
        "program before TC-01, so the default settings are used and the "
        "result files of this run are the only ones present.",
        "Fill in the test run details below before starting.",
    ])
    d.table(["Detail", "Value"], [
        ["Date", ""], ["Tester name", ""], ["Board serial or ID", ""],
        ["Firmware version read", ""], ["GUI file name", ""],
        ["Windows version", ""], ["COM port used", ""],
    ], "Test run details", key_col=False, weights=[40, 60])

    # ── 3 Test cases ─────────────────────────────────────────────────────────────────────────────────────────────
    d.h1("Test Cases", page_break=True)
    d.p("Carry out the test cases in order. Record each result in the table "
        "that follows the steps, writing what was seen in the Actual column "
        "and Pass or Fail in the last column.")

    # TC-01
    d.h2("TC-01: Power-On and Connection")
    d.p("**Objective:** confirm that the tester starts, the PC finds it, and "
        "the GUI connects.")
    d.p("**Preconditions:** no harness connected; GUI not running.")
    d.steps([
        "Plug the USB cable into CN1 of the board and into the PC. Watch the LEDs.",
        "Start the GUI. It must open maximised.",
        "Click Refresh. Select the port marked with an asterisk.",
        "Check that Baud is 115200. Click Connect.",
        "Read the status line and the Log tab.",
        "Open the Info tab. Click Refresh Firmware Info.",
        "Click Disconnect, then Connect again.",
    ])
    record(d, "Result record, TC-01", [
        ("LED pattern", "LD1, LD2, LD3 blink together 3 times, then LD1 steady"),
        ("GUI window", "Opens maximised"),
        ("Port list", "A STLink Virtual COM Port is listed and marked *"),
        ("Status line", f"CONNECTED followed by FW v{FW_VERSION}"),
        ("Log line", f"Connected, FW v{FW_VERSION}, cal offset 120, TRACE=OFF"),
        ("Info tab", f"FW version v{FW_VERSION}; state IDLE; port; baud 115200"),
        ("Reconnect", "Disconnect shows Not connected; Connect works again"),
    ])

    # TC-02
    d.h2("TC-02: Connector Configuration and Netlist")
    d.p("**Objective:** confirm that the default connector configuration is "
        "valid, that a netlist loads, and that faulty input is refused.")
    d.p("**Preconditions:** TC-01 passed; GUI connected.")
    d.steps([
        "Open the Configuration tab and read the status line under the table.",
        "Open the Log tab and read the lines written at start-up.",
        "Click Browse in the left panel and load `example_cross_connector_test.xlsx`.",
        "Read the Log tab, the netlist tree and the Connector View tab.",
        "In the Configuration tab, change Src Pin of channel 2 to 1. Read the "
        "status line and look at START TEST.",
        "Click Reset to Default and confirm with Yes. Read the status line again.",
        "Make a copy of the netlist and rename the header Src Pin # to Source "
        "Pin. Try to load the copy.",
    ])
    record(d, "Result record, TC-02", [
        ("Configuration", "Green line: 37 channels, J1 15 pins, J2 15 pins, J3 7 pins"),
        ("Netlist load", "Log: Netlist loaded, 15 net(s); tree lists 15 nets"),
        ("Connector View", "15 grey wires between J1, J2 and J3"),
        ("Duplicate pin", "Red status: J1 pin 1 already on row 2; START TEST disabled"),
        ("Reset to Default", "Green status returns; START TEST enabled again"),
        ("Bad netlist", "Netlist Error window names the missing column"),
    ])

    # TC-03
    d.h2("TC-03: Continuity Test, Passing Harness")
    d.p("**Objective:** confirm that a correct harness gives PASS.")
    d.p("**Preconditions:** TC-02 passed; netlist loaded; reference harness "
        "connected; Mode set to Continuity (one-to-one).")
    d.steps([
        "Enter your name in Operator. Note the DUT ID.",
        "Click START TEST. Watch LD1, LD2 and the progress bar.",
        "When the run ends, read the verdict, the Duration and the log.",
        "Open the Results Table tab and the Connector View tab.",
        "Look at the DUT ID again.",
        "Choose File, Open Results Folder and look for the new CSV file.",
    ])
    record(d, "Result record, TC-03", [
        ("Run", "Progress bar runs to 100%; START TEST disabled meanwhile; LD1 out and LD2 blue during the run"),
        ("Verdict", "PASS in green"),
        ("Duration", "Shown in the toolbar; record the value"),
        ("Results Table", "15 rows, all CONNECTED; summary Total 15, NOT CONNECTED 0"),
        ("Connector View", "All wires green"),
        ("LEDs", "LD1 blinks twice, then steady"),
        ("DUT ID", "Increased by one, for example HT-0001 to HT-0002"),
        ("CSV file", "report_<time>_HT-0001.csv present; Verdict line says PASS"),
    ])

    # TC-04
    d.h2("TC-04: Continuity Test, Missing Wire")
    d.p("**Objective:** confirm that a missing wire gives FAIL and is shown.")
    d.p("**Preconditions:** TC-03 passed.")
    d.steps([
        "Unplug the reference harness, remove the wire W_CAN_H (J1 pin 3 on "
        "both sides) and plug the harness in again.",
        "Click START TEST.",
        "Read the verdict and the Log tab.",
        "Look at the tab that is now in front, at the Connector View and at the LEDs.",
        "Refit the wire W_CAN_H and plug the harness in again.",
    ])
    record(d, "Result record, TC-04", [
        ("Verdict", "FAIL in red"),
        ("Log", "Test complete, FAIL (PASS: 14, FAIL: 1)"),
        ("Results Table", "Opens by itself; one red row, NOT CONNECTED, CAN_H, J1 pin 3"),
        ("Connector View", "The CAN_H wire and its pins are red; all others green"),
        ("LEDs", "LD3 blinks twice, then LD1 steady"),
        ("CSV file", "A new file with Verdict FAIL"),
    ])

    # TC-05
    d.h2("TC-05: Cross Continuity Test")
    d.p("**Objective:** confirm that Cross Continuity passes a correct harness "
        "and finds a connection that should not exist.")
    d.p("**Preconditions:** TC-04 finished and the wire refitted. Cross "
        "Continuity needs a harness of straight wires (the same channel "
        "number on both sides), so this test case uses the 13 straight wires "
        "of the reference harness.")
    d.steps([
        "Unplug the reference harness, remove the two wires that join "
        "different connectors (W_LINK_J1_TO_J2 and W_LINK_J1_TO_J3) and plug "
        "the harness in again.",
        "Load `example_straight_only.xlsx` with Browse.",
        "Set Mode to Cross Continuity (one-to-many).",
        "Click START TEST. Note the Duration when it ends.",
        "Read the verdict and the summary line of the Results Table.",
        "Fit the spare jumper from Side A J1 pin 4 to Side B J1 pin 5.",
        "Click START TEST again and read the verdict and the Log tab.",
        "In the Results Table, set Status to NOT CONNECTED and look for the "
        "red-tinted row.",
        "Remove the spare jumper. Refit the two wires W_LINK_J1_TO_J2 and "
        "W_LINK_J1_TO_J3.",
    ])
    record(d, "Result record, TC-05", [
        ("Correct harness", "PASS"),
        ("Summary line", "Total 1369, CONNECTED 13, NOT CONNECTED 1356"),
        ("Duration", "A few seconds; record the value"),
        ("With extra wire", "FAIL; Log: PASS: 13, FAIL: 1"),
        ("Unexpected pair", "Red row: Side A of J1 pin 4 to Side B of J1 pin 5"),
        ("Table order", "Rows sorted by connector and pin; Test # runs 1 to 1369"),
    ])

    # TC-06
    d.h2("TC-06: Auto-Scan")
    d.p("**Objective:** confirm that Auto-Scan finds the connections of a "
        "harness, that the result can become a netlist, and that the board "
        "button starts a scan.")
    d.p("**Preconditions:** TC-05 finished; extra wire removed; all 15 wires of the reference harness refitted.")
    d.steps([
        "Select Auto-Scan in the Netlist / Test Mode group.",
        "Click START TEST. When it ends, read the Log, the status bar and the "
        "Connector View.",
        "Click Use as Netlist. Read the Log tab and the mode selection.",
        "Set Mode to Continuity and click START TEST.",
        "Click Disconnect. Press the blue button B1 on the board and watch the LEDs.",
        "Click Connect to reconnect.",
    ])
    record(d, "Result record, TC-06", [
        ("Connections found", "Log: Auto-Scan complete, 15 connections discovered"),
        ("Connector View", "Opens by itself; 15 green wires"),
        ("Use as Netlist", "Log names a file autoscan_<time>.xlsx; Standard mode selected"),
        ("Continuity on result", "PASS, 15 rows CONNECTED"),
        ("Button B1", "LD1 goes out briefly, blinks twice, then steady"),
    ])

    # TC-07
    d.h2("TC-07: Stop and Connection Loss")
    d.p("**Objective:** confirm that the GUI recovers from a stop request and "
        "from a cable pull.")
    d.p("**Preconditions:** TC-06 finished; GUI connected; Standard mode.")
    d.steps([
        "Set Mode to Cross Continuity and click START TEST. At once click STOP / ABORT. "
        "The scan itself still runs to its end; only the GUI stops waiting.",
        "Wait ten seconds, until LD1 is steady. Click START TEST again and let it finish.",
        "With the GUI idle, unplug the USB cable. Read the Log tab and the status bar.",
        "Plug the cable in again within ten seconds. Watch the Log tab.",
        "If the GUI did not reconnect by itself, click Refresh, choose the "
        "port and click Connect.",
        "Click START TEST once more and let the run finish.",
    ])
    record(d, "Result record, TC-07", [
        ("Stop", "START TEST available again; no error window"),
        ("Next run", "Completes normally with a verdict"),
        ("Cable pulled", "Log: Serial connection lost; status bar counts reconnect attempts"),
        ("Cable replugged", "Connected again automatically, or after Refresh and Connect"),
        ("After reconnecting", "CONNECTED with the firmware version; a test runs to a verdict"),
    ])

    # TC-08
    d.h2("TC-08: Results Export")
    d.p("**Objective:** confirm that results can be saved and exported in "
        "every supported way.")
    d.p("**Preconditions:** at least one test has been run.")
    d.steps([
        "Choose File, Save Results as CSV and save a file on the desktop. "
        "Open it in the spreadsheet program.",
        "Choose File, Export PDF Report, save a file and open it.",
        "Choose File, Save Netlist As and save a JSON file.",
        "On the Log tab, click Save Log and save the file.",
        "Choose File, Open Results Folder. Count the CSV files.",
    ])
    record(d, "Result record, TC-08", [
        ("CSV content", "Header lines for DUT, operator, netlist, verdict, time; then the results table"),
        ("PDF report", "Logo, DUT ID, verdict, metadata, summary, and results table"),
        ("Netlist JSON", "File saved; contains the 15 nets"),
        ("Log file", "Text file with the session log"),
        ("Results folder", "One CSV per completed test, named report_<time>_<DUT>.csv"),
    ])

    # ── 4 Summary ────────────────────────────────────────────────────────────────────────────────────────────
    d.h1("Test Completion Summary")
    d.table(["Test case", "Title", "Result", "Tested by", "Date"], [
        ["TC-01", "Power-On and Connection", "", "", ""],
        ["TC-02", "Connector Configuration and Netlist", "", "", ""],
        ["TC-03", "Continuity, Passing Harness", "", "", ""],
        ["TC-04", "Continuity, Missing Wire", "", "", ""],
        ["TC-05", "Cross Continuity", "", "", ""],
        ["TC-06", "Auto-Scan", "", "", ""],
        ["TC-07", "Stop and Connection Loss", "", "", ""],
        ["TC-08", "Results Export", "", "", ""],
    ], "Test completion summary", weights=[13, 38, 13, 20, 16])

    d.h1("Deviations and Overall Verdict")
    d.p("Record every check that did not pass and what was decided.")
    d.table(["No.", "Test case", "Description", "Decision"],
            [["1", "", "", ""], ["2", "", "", ""], ["3", "", "", ""]],
            "Deviations", weights=[10, 18, 44, 28])
    d.p("**Overall verdict:** all checks passed / accepted with the deviations "
        "above / not accepted (delete as appropriate).")

    d.h1("Sign-off")
    d.table(["Role", "Name", "Signature", "Date"],
            [["Tester", "", "", ""], ["Reviewer", "", "", ""], ["Customer representative", "", "", ""]],
            "Sign-off record", weights=[34, 26, 24, 16])
    d.save(path)
    return d
