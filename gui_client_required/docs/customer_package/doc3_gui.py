# -*- coding: utf-8 -*-
from common import *


def build(path):
    d = new_doc("HT_MK0_GUI", "GUI Functional Description")
    d.standard_intro(
        purpose=[
            "This document describes the Harness Tester GUI, version "
            f"{GUI_VERSION}, in full: every menu, button, field, tab, dialog "
            "and message, what each one does and when it is available. It "
            "also defines the file formats the GUI reads and writes: the "
            "netlist and the connector configuration.",
        ],
        audience=[
            "Operators and test engineers who need to know exactly how a "
            "screen behaves, and engineers who prepare netlists and connector "
            "configurations. For step-by-step instructions, use the User "
            "Manual.",
        ],
        related=PACKAGE_DOCS)

    # ── 2 Overview ───────────────────────────────────────────────────────────────────────
    d.h1("Application Overview", page_break=True)
    d.p("The GUI is a single-window Windows program. It connects to the "
        "tester over a serial port, uploads a netlist, starts a test, and "
        "shows each result as it arrives. It keeps no connection to any "
        "network; everything is stored in files beside the program.")
    d.h2("Window Layout")
    d.figure(shot("window_pass.png"), "The main window", 15.9)
    d.table(["Area", "Contents", "Section"], [
        ["Menu bar", "File, View, Help", "3"],
        ["Test control bar", "Mode, START TEST, STOP / ABORT, progress, duration, verdict", "4"],
        ["Left panel", "Connection, Netlist / Test Mode, Test Profile", "5"],
        ["Tab area", "Connector View, Results Table, Log, Info, Configuration", "6 to 10"],
        ["Status bar", "Temporary messages, company name and logo", "12"],
    ], "Areas of the main window", center_cols=(2,), weights=[24, 60, 16])
    d.h2("Start-up Behaviour")
    d.bullets([
        "The window opens maximised on every start.",
        "The theme (dark or light) chosen last time is restored. The default is dark.",
        "The window title reads Harness Tester followed by the version; once a "
        "test is started it also shows the profile and the DUT ID.",
        "The connector configuration is read and checked. The result is "
        "written to the Log tab.",
        "No connection is made until Connect is clicked.",
    ])
    d.h2("Test States")
    d.p("The GUI follows the state of the tester. The toolbar and the left "
        "panel enable or disable their controls according to the state.")
    d.table(["State", "When", "START TEST", "STOP / ABORT"], [
        ["Not connected", "Before Connect or after a lost connection", "Disabled", "Disabled"],
        ["Idle", "Connected, nothing running", "Enabled*", "Disabled"],
        ["Uploading", "The netlist is being sent to the tester", "Disabled", "Enabled"],
        ["Scanning", "A test or Auto-Scan is running", "Disabled", "Enabled"],
        ["Calibrating", "After F7 (placeholder)", "Disabled", "Enabled"],
        ["Complete", "A run has just ended; the verdict is shown", "Enabled*", "Disabled"],
    ], "States seen by the GUI", weights=[18, 44, 19, 19])
    d.p("*START TEST is also disabled while the connector configuration has "
        "an error, or while the loaded netlist uses a channel that the "
        "configuration does not list.")

    # ── 3 Menu bar ────────────────────────────────────────────────────────────────────────
    d.h1("Menu Bar")
    d.h2("File Menu")
    d.figure(shot("menu_file.png"), "The File menu", 7.5, max_h_cm=9)
    d.table(["Item", "Shortcut", "Action"], [
        ["Load Netlist...", "Ctrl+O", "Opens a file chooser for .json, .xlsx or .csv netlists. Same as Browse in the left panel."],
        ["Save Results as CSV...", "Ctrl+S", "Saves the rows now in the Results Table to a CSV file you name. Shows No Results if the table is empty."],
        ["Export PDF Report...", "Ctrl+P", "Builds a PDF report of the results on screen. Shows No Results if the table is empty. The file is written in the background; the Log tab confirms it."],
        ["Save Netlist As...", "-", "Saves the loaded netlist as a JSON file, for example to convert a spreadsheet netlist. Shows No Netlist if none is loaded."],
        ["Open Results Folder...", "-", "Opens the folder with the automatically saved CSV files in Windows Explorer."],
        ["Exit", "Alt+F4", "Aborts a running test, closes the port, saves the window position and closes the program."],
    ], "File menu items", weights=[26, 14, 60])
    d.h2("View Menu")
    d.figure(shot("menu_view.png"), "The View menu", 7.5, max_h_cm=9)
    d.table(["Item", "Shortcut", "Action"], [
        ["Theme, Dark", "-", "Applies the dark colour scheme and remembers it."],
        ["Theme, Light", "-", "Applies the light colour scheme and remembers it."],
        ["Show Log", "Ctrl+L", "Brings the Log tab to the front."],
        ["Show Matrix", "Ctrl+M", "Brings the Connector View tab to the front."],
        ["Show Results", "Ctrl+R", "Brings the Results Table tab to the front."],
    ], "View menu items", weights=[26, 14, 60])
    d.h2("Help Menu")
    d.figure(shot("dlg_about.png"), "The About window", 7.5, max_h_cm=9)
    d.p("About shows the program name, the GUI version, the serial protocol "
        "version (1.0), and the Qt and Python versions the program was built "
        "with. Quote these when you report a problem.")

    # ── 4 Test control bar ────────────────────────────────────────────────────────────────────
    d.h1("Test Control Bar")
    d.p("The bar under the menu holds everything needed to start, stop and "
        "judge a test.")
    d.figure(shot("toolbar_ready.png"), "The test control bar, connected and ready", 15.0)
    d.table(["Control", "Behaviour"], [
        ["Mode box", "Chooses the test: Continuity (one-to-one) or Cross Continuity (one-to-many). The hover text explains each. While Auto-Scan is selected in the left panel, Cross Continuity is greyed out and Continuity is selected."],
        ["START TEST", "Starts a test (F5). Green when enabled. Enabled only when connected, idle, and neither the connector configuration nor the netlist has an error."],
        ["STOP / ABORT", "Sends the abort command (F6). Red; enabled only while a test runs. The GUI returns to idle at once; the tester acts on the command only after the scan it is running has ended."],
        ["Progress bar", "Appears while a test runs. Shows the percentage and the pairs done out of the total, for example 62% (23/37)."],
        ["Duration", "Elapsed time of the current or last run, in microseconds, milliseconds or seconds as suits its length."],
        ["Verdict", "Shows PASS (green), FAIL (red) or a dash (grey) before a result. INCONCLUSIVE (orange) is defined but not produced in this version."],
    ], "Controls of the test control bar", weights=[20, 80])
    d.note("In this version Cross Continuity is reliable for harnesses whose wires join the same channel number on both sides, for example A3 to B3. For a wire between different channel numbers, such as J1 pin 5 to J2 pin 9, the firmware also expects the reverse connection, which does not exist, and reports it as NOT CONNECTED, so the verdict is FAIL. Use Continuity (Mode 1) for harnesses with such wires.")
    d.figure(shot("toolbar_running.png"), "The bar while a test runs", 15.0)
    d.figure(shot("toolbar_fail.png"), "The bar after a failed test", 15.0)
    d.h2("What Happens When START TEST Is Clicked")
    d.table(["Step", "Standard mode (Continuity or Cross Continuity)", "Auto-Scan mode"], [
        ["1", "The connector configuration is re-read and checked.", "Same."],
        ["2", "The window title shows the profile and DUT ID.", "Same."],
        ["3", "Counters, results table and connector view are cleared.", "Same; the diagram is cleared too."],
        ["4", "The test parameters are sent to the tester.", "Same."],
        ["5", "The netlist is uploaded in packets of up to 250 bytes, if one is loaded.", "No upload."],
        ["6", "The scan command for the chosen mode is sent.", "The Auto-Scan command is sent."],
        ["7", "Results arrive one by one; the verdict is set at the end.", "Only connections found are listed; PASS is shown at the end."],
    ], "Sequence started by START TEST", center_cols=(0,), weights=[8, 48, 44])
    d.p("With no netlist loaded, the Log tab and status bar state that the "
        "tester will scan 37 straight pairs, A1 to B1 through A37 to B37. If "
        "a netlist was uploaded earlier in the same power-on session, the "
        "tester may still hold it; load the netlist you want before testing.")

    # ── 5 Left panel ─────────────────────────────────────────────────────────────────────────
    d.h1("Left Panel")
    d.p("The left panel has three groups, from top to bottom. It scrolls "
        "if the window is short.")
    d.figure(shot("panel_left_loaded.png"), "The left panel with a netlist loaded", 6.2, max_h_cm=15)
    d.h2("Connection Group")
    d.figure(shot("grp_connection.png"), "The Connection group, connected", 8.5, max_h_cm=7)
    d.table(["Control", "Behaviour"], [
        ["Port", "Lists the serial ports found. Ports that look like the tester (ST-Link, CH340, CP210, FTDI, virtual COM) come first and are marked with an asterisk. Bluetooth ports are listed last. Shows No ports found if there are none."],
        ["Refresh", "Scans the ports again. The scan runs in the background, so the window does not freeze; the port box is disabled while it runs. Your selection is kept if the port is still there."],
        ["Baud", "9600, 115200 or 921600. The tester firmware uses 115200; leave it there."],
        ["Connect", "Opens the port and asks the tester for its status. Disabled once connected."],
        ["Disconnect", "Closes the port and stops any auto-reconnect. Enabled only while connected."],
        ["Status line", "Not connected (grey), or CONNECTED followed by the firmware version (green, bold)."],
    ], "Controls of the Connection group", weights=[20, 80])
    d.p("When the status reply arrives, the Log tab records the firmware "
        "version, the calibration offset and whether the debug trace port was "
        "active. A port that opens but never answers is not retried; the GUI "
        "rescans the ports and asks you to pick another. A port that worked and "
        "then dropped out is retried up to five times, waiting 1, 3, 5, 5 and "
        "5 seconds.")
    d.h2("Netlist / Test Mode Group")
    d.figure(shot("grp_netlist.png"), "The Netlist / Test Mode group in Standard mode", 8.5, max_h_cm=10)
    d.table(["Control", "Behaviour"], [
        ["Standard (file)", "Selects netlist testing. Shows Browse and the netlist tree."],
        ["Auto-Scan", "Selects discovery. Hides Browse and the tree, shows an explanation and the Use as Netlist button, and disables Cross Continuity in the Mode box."],
        ["Harness ID line", "Appears in purple when the netlist file names the harness."],
        ["Browse...", "Opens the file chooser (.json, .xlsx, .csv). The file is read; the tree is filled; the connector view is drawn. A file that cannot be read shows the name with a parse error warning, and a Netlist Error window gives the reason."],
        ["Netlist tree", "One entry per wire: NET: name, the connector in brackets, source and destination, and the pin count. Below it, an optional Type line and one line per pin with its number and label."],
        ["Use as Netlist", "Auto-Scan only; enabled once a scan has found connections. Saves them as an Excel (.xlsx) netlist in the netlists folder and loads it, then returns to Standard mode. The file has the Colour, AWG, Length and Harness No columns empty, ready to be filled in."],
        ["Connection Defaults", "Connector, Source and Destination text. Used in results rows that have no value of their own: in Auto-Scan, or when a netlist leaves the field empty."],
    ], "Controls of the Netlist / Test Mode group", weights=[22, 78])
    d.figure(shot("grp_netlist_auto.png"), "The same group in Auto-Scan mode", 8.5, max_h_cm=8)
    d.h2("Test Profile Group")
    d.figure(shot("grp_test.png"), "The Test Profile group", 8.5, max_h_cm=8)
    d.table(["Control", "Behaviour"], [
        ["Profile", "Lists Default and every saved profile. Choosing one loads its operator, DUT ID and baud rate, and its netlist if the file still exists."],
        ["Operator", "Free text; appears in the CSV and PDF."],
        ["Harness ID", "Free text note. Not saved in the profile and not written to reports in this version."],
        ["DUT ID", "Identifier of the unit being tested; starts at HT-0001. Its trailing number goes up by one after every completed test. If it has no number, -2 is added."],
        ["Save", "Saves operator, DUT ID, netlist path and baud rate into the selected profile. The button shows Saved for a moment."],
        ["New", "Asks for a name, creates the profile and saves it. Default and app_settings are reserved names."],
        ["Delete", "Asks for confirmation, then removes the profile file. Default cannot be deleted."],
    ], "Controls of the Test Profile group", weights=[20, 80])

    # ── 6 Connector view ───────────────────────────────────────────────────────────────────────
    d.h1("Connector View Tab")
    d.p("The first tab draws the harness. A bar at the top switches between "
        "two views; the legend is always at the bottom.")
    d.h2("Single View")
    d.p("Single view shows every connector on both sides in one diagram. Side "
        "A is on the left, Side B on the right. Each pin is a circle with its "
        "connector pin number, and its signal name beside it. Pins in the "
        "netlist are coloured; unused pins are grey.")
    d.figure(shot("diagram_pass.png"), "Single view, all wires connected", 11.0, max_h_cm=19)
    d.table(["Element", "Meaning"], [
        ["Connector body", "One per connector and side, titled for example J1 Side-A, with the part number under the title."],
        ["Pin circle", "Grey untested, yellow in progress, green connected, red not connected. The number is the pin on that connector."],
        ["Wire", "Joins a Side-A pin to its Side-B pin. Dashed while untested, solid once a result is in. Coloured like its pins."],
        ["Right-angle routing", "A wire leaves Side A, runs along its own lane in the gap between the sides, and enters Side B. Wires that stay on the same row run straight across."],
        ["Hop", "Where two wires cross, one shows a small arch over the other, so crossings are never mistaken for connections."],
        ["Tooltip", "Hold the pointer over a pin to see connector, pin number and channel, for example J2 Side-A - pin 3 (channel 18)."],
    ], "Elements of the Single view", weights=[24, 76])
    d.p("A connector appears on both sides with all of its pins, whether or "
        "not the netlist uses them. A wire to a pin on a different connector "
        "is routed through the middle of the diagram. Lanes are ordered so "
        "that wires which step the same way run side by side without lying on "
        "top of each other.")
    d.h2("Sections View")
    d.p("Sections view lists one section per connector, with each wire drawn "
        "as a straight line between the two bodies and its net name above it. "
        "A wire that joins two different connectors gets its own purple "
        "INTERCONNECT section, for example J1 to J2.")
    d.figure(shot("view_sections_full.png"), "Sections view", 11.0, max_h_cm=19)
    d.figure(shot("legend.png"), "The legend at the foot of the tab", 10.0, max_h_cm=3)
    d.p("**Legend.** The legend names the four pin states: UNTESTED, IN PROGRESS, "
        "CONNECTED and NOT CONNECTED. The Connector View tab is cleared at "
        "the start of every test.")
    d.h2("Results in the Connector View")
    d.figure(shot("diagram_fail.png"), "Single view after a test with two missing wires", 11.0, max_h_cm=19)
    d.p("A pin takes the strongest state of the results that involve it, so "
        "a pin with one failed wire stays red even if another wire on it "
        "passed.")

    # ── 7 Results table ───────────────────────────────────────────────────────────────────────────
    d.h1("Results Table Tab")
    d.p("The second tab lists every tested pair as it arrives.")
    d.figure(shot("results_pass.png"), "The Results Table after a passing test", 15.9)
    d.h2("Columns")
    d.table(["Column", "Content"], [
        ["Test #", "Order in which the result was received."],
        ["Source", "Label of the Side-A end from the netlist, for example Side-A."],
        ["Part Number", "Connector part number at the Side-A end."],
        ["Conn ID", "Connector at the Side-A end, for example J1."],
        ["Src Pin Label", "Signal name at the Side-A end."],
        ["Src Pin #", "Pin number on that connector."],
        ["Status", "A badge: CONNECTED (green) or NOT CONNECTED (red)."],
        ["Dst Pin #", "Pin number at the Side-B end."],
        ["Dst Pin Label", "Signal name at the Side-B end."],
        ["Conn ID", "Connector at the Side-B end."],
        ["Part Number", "Connector part number at the Side-B end."],
        ["Destination", "Label of the Side-B end, for example Side-B."],
        ["Colour", "Wire colour from the netlist. Empty when the netlist has no Colour column."],
        ["AWG", "Wire gauge from the netlist."],
        ["Length", "Wire length from the netlist, as written there."],
        ["Harness No", "Harness number from the netlist."],
    ], "Columns of the Results Table", weights=[24, 76])
    d.p("The last four columns are copied from the netlist and are also in the "
        "CSV file and the PDF report. They are empty in an Auto-Scan.")
    d.p("Rows are tinted: green for connected, red for a missing or "
        "unexpected connection. The shades differ between the dark and light "
        "themes.")
    d.h2("Filter Bar and Footer")
    d.table(["Control", "Behaviour"], [
        ["Status box", "Shows All, CONNECTED or NOT CONNECTED rows."],
        ["Search box", "Shows only rows whose Src Pin Label or Dst Pin Label contains the text."],
        ["Clear Filters", "Resets the status box and the search box."],
        ["Summary line", "Total, CONNECTED and NOT CONNECTED counts of all rows received."],
        ["Column heading", "Click to sort; click again to reverse. The default order is by source connector."],
        ["Right-click menu", "Copy to Clipboard as CSV copies the selected rows with the visible columns. Export Selected as PDF and Show Pin Detail are listed but are not active in this version."],
    ], "Filter bar, footer and menu", weights=[24, 76])
    d.p("The table scrolls to the newest row while a test runs. Scroll up "
        "to stop it following; scroll to the bottom to resume.")
    d.h2("Cross Continuity Layout")
    d.p("A Cross Continuity run reports all 1369 pairs. The table then shows "
        "only four columns: Test #, Source, Status and Destination. Source and "
        "Destination read in full, for example Side A of J1 pin 5 and Side B "
        "of J2 pin 9. After the run the rows are sorted by connector and pin, "
        "Test # is renumbered 1 to N, and any pair the tester did not report "
        "is added as NOT CONNECTED so the matrix is complete. The figure shows a "
        "run on a harness of straight wires.")
    d.figure(shot("results_cross.png"), "The end of a Cross Continuity table", 15.9)
    d.p("In the figure, the grey and red rows are pairs that should not be "
        "connected and are not (NOT CONNECTED, no tint), or are connected "
        "when they should not be (NOT CONNECTED, red tint). The green rows at "
        "the bottom are the wires the netlist lists.")
    d.h2("Auto-Scan Layout")
    d.figure(shot("results_autoscan.png"), "Results of an Auto-Scan", 15.9)
    d.p("An Auto-Scan lists only the connections found, all as CONNECTED, "
        "with the connector fields taken from the connector configuration and "
        "the Connection Defaults.")

    # ── 8 Log ────────────────────────────────────────────────────────────────────────────────────────
    d.h1("Log Tab")
    d.p("The Log tab is a running record of the session. Each line has the "
        "time, a level and a message.")
    d.code(["[11:30:02.418] [INFO] Connected - FW v2.2.0, ..."])
    d.table(["Level", "Colour", "Use"], [
        ["INFO", "Normal", "Normal events: connecting, loading a netlist, test start and end."],
        ["WARN", "Orange", "Something needs attention but the test can continue."],
        ["ERROR", "Red", "A failure: a port that does not answer, an invalid configuration, a stuck input."],
        ["TX", "Blue", "A packet sent to the tester, in hexadecimal."],
        ["RX", "Green", "Bytes received from the tester, in hexadecimal."],
    ], "Log levels", center_cols=(0,), weights=[16, 18, 66])
    d.figure(shot("log_pass.png"), "The Log tab", 15.0, max_h_cm=9)
    d.table(["Control", "Behaviour"], [
        ["Clear Log", "Empties the log on screen."],
        ["Save Log...", "Saves the log as a text file."],
        ["Max lines", "Number of lines kept, 100 to 100000, default 10000. Older lines are dropped."],
    ], "Controls of the Log tab", weights=[24, 76])
    d.h2("Common Log Messages")
    d.table(["Message", "Meaning"], [
        ["Connected - FW v2.2.0, cal offset ..., TRACE=OFF", "The tester answered. TRACE=ON would mean the debug trace port was active."],
        ["Debug trace port was active ...", "Several test pins may read HIGH. Close the debugger and power-cycle the board."],
        ["Connector config ...: 37 channels", "The connector configuration is valid."],
        ["Connector config ... is invalid", "Start is blocked until the listed errors are fixed."],
        ["Netlist loaded: name - n net(s)", "The netlist was read successfully."],
        ["Netlist uses channel(s) ... not listed", "The configuration lacks channels the netlist needs. Start is blocked."],
        ["Stuck input(s) before the scan: ...", "These Side-B pins read HIGH with nothing driven. Results are not reliable."],
        ["Firmware rejected command 0x..", "The tester was busy or did not accept the command."],
        ["Serial connection lost", "The tester stopped answering; the GUI retries."],
        ["Test complete - PASS or FAIL", "End of a run, with the pass and fail counts."],
        ["Results saved - file name", "The automatic CSV was written."],
        ["Auto-Scan complete - n connections discovered", "End of Auto-Scan, with the pairs found."],
    ], "Common Log messages", weights=[44, 56])

    # ── 9 Info ───────────────────────────────────────────────────────────────────────────────────────────
    d.h1("Info Tab")
    d.figure(shot("info_connected.png"), "The Info tab while connected", 12.0, max_h_cm=9)
    d.table(["Group", "Field", "Content"], [
        ["GUI / Application", "App version", "Version of the program."],
        ["", "Protocol version", "Version of the serial protocol, 1.0."],
        ["", "Build date", "Date and time the program was built. Fixed when the program is built; it does not change when the program is started."],
        ["", "Build", "The Python version the program was built with."],
        ["", "Started", "Date and time the program started."],
        ["Firmware / Device", "FW version", "Version reported by the tester."],
        ["", "Device state", "IDLE, UPLOADING, CALIBRATING, SCANNING or COMPLETE."],
        ["", "Port and Baud", "The serial port and speed in use."],
        ["", "Last refreshed", "Time of the last status reply."],
    ], "Fields of the Info tab", weights=[26, 26, 48])
    d.p("Refresh Firmware Info asks the tester for its status and updates "
        "the Firmware / Device fields. They show a dash when not connected.")

    # ── 10 Configuration ─────────────────────────────────────────────────────────────────────────────────
    d.h1("Configuration Tab")
    d.p("The Configuration tab is where the connector configuration is "
        "viewed and edited. It is the table that tells the GUI which "
        "connector pin each tester channel is. Netlists use channel "
        "numbers; this table turns a channel into J2 pin 5 on screen and in "
        "reports.")
    d.figure(shot("config_tab.png"), "The Configuration tab", 15.5, max_h_cm=14)
    d.table(["Column", "Required", "Meaning"], [
        ["Channel", "Yes", "Tester channel number, 1 to 37. Unique."],
        ["Src Conn ID", "Yes", "Short name of the connector, for example J1. A file that heads this column Connector ID is read as well."],
        ["Dst Conn ID", "No", "Name of the same connector at the Side-B (destination) end, for example X1. Blank means the same as Src Conn ID. Only the name changes; the channel and the pin number stay. A file that heads this column Dest Connector ID is read as well."],
        ["Connector Name", "No", "Free text shown in the netlist tree, for example J1 (DB15)."],
        ["Src Pin", "Yes", "Pin number on that connector. A connector and pin pair may appear only once. A file that heads this column Conn Pin is read as well."],
        ["Dest Pin", "No", "Pin number on the Side-B connector. Fill it in when Side B has connectors of its own, for example one DB37 on Side A facing two DB15 and a DB9 on Side B. Side A and Side B are then independent: a pin that has no pigtail leaves both of its fields blank (Src Conn ID + Src Pin for Side A, Dst Conn ID + Dest Pin for Side B)."],
    ], "Columns of the connector configuration", center_cols=(1,), weights=[22, 14, 64])
    d.table(["Control", "Behaviour"], [
        ["Add Row", "Adds a row at the end with the next free channel number."],
        ["Remove Row(s)", "Removes the selected rows."],
        ["Import xlsx...", "Replaces the table with a connector configuration file. Both the per-channel format and the older Start Pin / End Pin range format are read."],
        ["Export xlsx...", "Saves the table to a file, with a Notes sheet that explains the columns."],
        ["Reset to Default", "After confirmation, replaces the table with the built-in configuration (J1, J2, J3)."],
        ["Status line", "Green: the number of channels and pins per connector, and where the file is saved. Red: the errors that block Start."],
    ], "Controls of the Configuration tab", weights=[24, 76])
    d.p("Edits are saved automatically about a second after the last change. "
        "The GUI then checks the table, and re-reads the loaded netlist "
        "against it. These rules are checked, and a violation blocks START "
        "TEST:")
    d.bullets([
        "a channel number or a connector pin listed twice;",
        "a missing Channel, Src Conn ID or Src Pin, or a non-number;",
        "a connector given two different Dst Conn IDs, or two "
        "connectors given the same one (not checked when a Dest Pin is "
        "used);",
        "with Dest Pins, a Side-B connector pin listed twice, a Side-A or "
        "Side-B pin with only one of its two fields filled, or a channel "
        "with no pigtail on either side.",
    ])
    d.p("When Dest Pin is used, Side B is not a copy of Side A: each channel "
        "ends on its own Side-B connector (Dst Conn ID) and Dest Pin. "
        "A netlist is then written in connector pins, not channel numbers: "
        "Conn ID and Src Pin # name the Side-A end, Conn ID B and Dst Pin # "
        "name the Side-B end, for example J1 pin 20 to X2 pin 6. The GUI "
        "looks each end up in this table; connector names must match it "
        "exactly. A wire end the table does not list, or that has no "
        "pigtail, is reported in the Log tab and blocks START TEST. The "
        "Connector View then draws the Side-B connectors as separate "
        "blocks, each with its own pin numbers.")
    d.p("A Dst Conn ID is shown wherever the Side-B end of a connector "
        "appears: the block titles and hover text of the Connector View, the "
        "Conn ID column of the Side-B end in the Results Table, and the CSV "
        "and PDF reports. A wire that leaves J1 and ends on J2 is then listed "
        "as ending on X2.")

    # ── 11 Dialogs ───────────────────────────────────────────────────────────────────────────────────────────
    d.h1("Dialogs and Messages")
    d.figure(shot("dlg_netlist_error.png"), "The Netlist Error window", 9.5, max_h_cm=6)
    d.table(["Window", "Text", "When"], [
        ["Netlist Error", "Could not load netlist: the reason. Please fix the file and try again.", "The netlist cannot be read or fails validation."],
        ["No Test Mode Selected", "Please select Continuity or Cross Continuity before starting.", "Safety check; not reachable with the standard mode box."],
        ["No Results", "No test results to save yet. / ... to export yet.", "Save CSV or Export PDF with an empty table."],
        ["No Netlist", "No netlist is loaded.", "Save Netlist As with no netlist."],
        ["Save Error", "Could not save the file or the netlist, with the reason.", "The disk or folder is not writable."],
        ["PDF Export Error", "Could not export PDF: the reason.", "The PDF could not be written, for example the file is open."],
        ["Calibration Complete", "Calibration offset: n mohm. The offset has been applied.", "After F7. Informational; a placeholder in this version."],
        ["New Profile", "Profile name:", "New in the Test Profile group."],
        ["Invalid Name", "The name is a reserved name.", "New with Default or app_settings."],
        ["Cannot Delete", "The Default profile cannot be deleted.", "Delete with Default selected."],
        ["Delete Profile", "Delete profile? This cannot be undone.", "Delete; answer Yes or No."],
        ["Import Failed / Export Failed", "Could not read or write the file, with the reason.", "Import or Export in the Configuration tab."],
        ["Reset Configuration", "Replace the whole table with the built-in connector configuration?", "Reset to Default; answer Yes or No."],
    ], "Dialogs and their messages", weights=[22, 44, 34])

    # ── 12 Status bar ───────────────────────────────────────────────────────────────────────────────────────────
    d.h1("Status Bar")
    d.p("The status bar shows short messages on the left, and on the right "
        "the company name and logo. Messages disappear after a few seconds "
        "unless they describe a condition that continues.")
    d.table(["Message", "Meaning"], [
        ["Default scan: 37 straight pairs (no netlist)", "START TEST with no netlist loaded."],
        ["Results saved: file name", "The automatic CSV was written."],
        ["Auto-Scan complete - n connection(s) found", "End of an Auto-Scan."],
        ["Auto-Scan result is now the netlist", "Use as Netlist completed."],
        ["Connection lost - reconnecting in Ns", "The GUI is retrying; the attempt number is shown."],
        ["Connection lost - ports rescanned", "Retries ran out; reconnect by hand."],
        ["Port did not respond - check the port selection", "The port opened but the tester did not answer."],
        ["Stuck input(s): ... - results unreliable", "Shown until cleared; see Log tab."],
        ["Not connected - cannot calibrate", "F7 pressed while not connected."],
    ], "Status bar messages", weights=[48, 52])

    # ── 13 Netlist format ───────────────────────────────────────────────────────────────────────────────────────────
    d.h1("Netlist File Format")
    d.p("A netlist can be a spreadsheet (.xlsx), a CSV file or a JSON file. "
        "All three describe the same thing: wires, each between a Side-A pin "
        "and a Side-B pin. Pin numbers are channel numbers, 1 to 37, unless the "
        "connector configuration uses Dest Pin; the pin numbers are then "
        "connector pins, read together with Conn ID and Conn ID B.")
    d.h2("Spreadsheet and CSV Format")
    d.p("One header row, then one row per wire. Column names are matched "
        "without regard to case; a space and an underscore are equivalent. "
        "Other names are accepted for some columns, shown below.")
    d.table(["Column", "Also accepted", "Required"], [
        ["Net", "Net Name, Network", "Yes"],
        ["Src Pin #", "Src Pin No, Src Pin Number", "Yes"],
        ["Dst Pin #", "Dst Pin No, Dst Pin Number", "Yes"],
        ["Src Pin Label", "Src Pin Name", "No"],
        ["Dst Pin Label", "Dst Pin Name", "No"],
        ["Source", "Src", "No"],
        ["Destination", "Dest", "No"],
        ["Conn ID", "Connector ID, Src Conn ID", "No"],
        ["Conn ID B", "Connector ID B, Dst Conn ID", "No"],
        ["Part Number", "Part No, Conn Part Number", "No"],
        ["Part Number B", "Part No B", "No"],
        ["Connector Detail", "Conn Detail", "No"],
        ["Harness ID", "Harness Num", "No"],
        ["Colour", "Color, Wire Colour", "No"],
        ["AWG", "Wire Gauge, Gauge", "No"],
        ["Length", "Wire Length", "No"],
        ["Harness No", "Harness Number, Harness #", "No"],
    ], "Netlist columns and accepted names", center_cols=(2,), weights=[26, 56, 18])
    d.p("Colour, AWG, Length and Harness No describe the wire. They are free "
        "text, kept as written. They are shown in the Results Table, the CSV "
        "file and the PDF report, and the Sections view of the Connector View "
        "names the colour on the wire's header. Harness No is per wire; "
        "Harness ID names the whole netlist.")
    d.bullets([
        "A row with no Net name is skipped, and a warning is shown in the Log "
        "tab. A row with a pin number that is not a number is skipped the same way.",
        "A wire that shares a Side-A pin with another row is a split: both "
        "rows are tested.",
        "Conn ID, Conn ID B and the connector detail are replaced by the "
        "values from the connector configuration whenever one is loaded.",
        "Columns for resistance and insulation limits are read but not used "
        "by the HT_MK0.",
    ])
    d.h2("JSON Format")
    d.p("The JSON file lists nets. A net can have more than two pins; every "
        "pair of pins in it is then tested, in list order.")
    d.code([
        '{ "harness_id": "HRN-001",',
        '  "nets": [ {',
        '    "name": "W_PWR_24V",',
        '    "connector_id": "J1",',
        '    "source": "Side-A", "destination": "Side-B",',
        '    "pins": [ { "number": 1, "name": "PWR_24V" },',
        '              { "number": 1, "name": "PWR_24V" } ]',
        '  } ] }',
    ])
    d.h2("Validation")
    d.table(["Check", "Result if it fails"], [
        ["The file has at least one net", "Netlist Error: Netlist contains no nets"],
        ["Every net has a name", "Netlist Error: name is empty"],
        ["Every net has at least two pins", "Netlist Error: must have at least 2 pins"],
        ["Pin numbers are 1 to 256", "Netlist Error: pin number out of range"],
        ["Every channel is listed in the connector configuration", "Log ERROR and Start blocked"],
    ], "Netlist validation", weights=[50, 50])

    # ── 14 Connector config format ────────────────────────────────────────────────────────────────────────────────────
    d.h1("Connector Configuration File")
    d.p("The connector configuration is an Excel file named "
        "connector_config.xlsx. The first sheet holds the table described in "
        "the Configuration Tab section. A second sheet, Notes, explains the "
        "columns and can be changed freely; the GUI reads only the first sheet.")
    d.p("The program keeps a working copy under profiles in its data folder, "
        "seeded from the default the first time. Edits are made to the copy, "
        "so the delivered default is never altered. A copy made by an earlier "
        "version with the names DB15-1, DB15-2 and DB9 is renamed to J1, J2 "
        "and J3 automatically.")
    d.table(["Channel", "Connector", "Pin"], [r[:3] for r in pin_rows()],
            "Default connector configuration", center_cols=(0, 1, 2))

    # ── 15 Files ──────────────────────────────────────────────────────────────────────────────────────────────────────────
    d.h1("Files and Folders")
    d.table(["File", "Written when", "Content"], [
        ["report_<time>_<DUT>.csv", "A test ends", "Results with a header block of DUT ID, operator, netlist, verdict and time."],
        ["report_<time>_<DUT>.pdf", "Export PDF Report", "Logo, verdict, metadata, summary and results table, on a landscape page."],
        ["autoscan_<time>.xlsx", "Use as Netlist", "The connections found by an Auto-Scan, as a netlist."],
        ["<profile>.json", "Profile Save or New", "Operator, DUT ID, netlist path and baud rate."],
        ["app_settings.json", "The window closes or the theme changes", "Theme and last window position."],
        ["connector_config.xlsx", "The Configuration tab is edited", "The working connector configuration."],
    ], "Files written by the GUI", weights=[34, 24, 42])
    d.save(path)
    return d
