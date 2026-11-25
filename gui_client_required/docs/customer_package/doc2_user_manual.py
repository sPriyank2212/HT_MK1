# -*- coding: utf-8 -*-
from common import *


def build(path):
    d = new_doc("HT_MK0_UM", "User Manual")
    d.standard_intro(
        purpose=[
            "This manual explains how to set up and use the HT_MK0 Harness "
            "Tester: connecting the tester to a PC, connecting a harness, "
            "loading a netlist, running the three kinds of test, reading the "
            "results, saving reports and solving common problems.",
        ],
        audience=[
            "Operators who test harnesses with the HT_MK0 every day. The manual "
            "assumes basic use of Windows, a USB cable and a spreadsheet. "
            "Details of every screen are in the GUI Functional Description.",
        ],
        related=PACKAGE_DOCS)

    # ── 2 Safety ────────────────────────────────────────────────────────────────────
    d.h1("Safety and Precautions", page_break=True)
    d.p("The HT_MK0 is a low-voltage instrument, but its test pins are "
        "connected directly to the microcontroller. Read these precautions "
        "before connecting a harness.")
    d.warning("The test pins are 3.3 V logic. Never connect a powered harness, "
              "a battery, a power supply or any other voltage source to a "
              "test pin. Applying voltage to a pin can destroy the "
              "microcontroller.")
    d.bullets([
        "Connect and disconnect the harness while the USB cable is unplugged, "
        "or at least while no test is running.",
        "Discharge static electricity before touching the board or the "
        "connectors. Handle the board by its edges.",
        "Use only a data-capable USB cable. Some cables carry power only.",
        "Do not leave a debugger (STM32CubeIDE debug session, trace probe) "
        "attached during testing. A debug session can hold several test pins "
        "HIGH and make them look connected.",
        "Do not use the HT_MK0 for any test that needs a measured resistance "
        "or an insulation test. It checks continuity only.",
    ])

    # ── 3 Before you start ─────────────────────────────────────────────────────────────
    d.h1("Before You Start")
    d.h2("What You Need")
    d.table(["Item", "Notes"], [
        ["HT_MK0 tester", "The NUCLEO-F303ZE board with the firmware programmed, and the J1, J2 and J3 connectors."],
        ["USB cable", "Data-capable cable that fits the ST-LINK USB connector (CN1) of the board."],
        ["PC", "Windows 10 or 11, 64-bit, with a free USB port."],
        ["GUI program", f"`{EXE_NAME}`, a single file."],
        ["Netlist", "A .json, .xlsx or .csv file describing the harness. Not needed for Auto-Scan."],
        ["Harness", "The harness under test, with connectors that match J1, J2 and J3."],
    ], "Items needed", weights=[24, 76])
    d.h2("Installing the USB Driver")
    d.p("The board talks to the PC through its built-in ST-Link, which appears "
        "as a virtual COM port. Windows sometimes installs a basic driver that "
        "does not provide the COM port. The reliable way is to install "
        "STM32CubeProgrammer from STMicroelectronics and accept the ST-Link "
        "driver when asked.")
    d.steps([
        "Install STM32CubeProgrammer and accept the ST-Link driver.",
        "Plug the board into the PC.",
        "Open Windows Device Manager and expand Ports (COM & LPT).",
        "Check that STMicroelectronics STLink Virtual COM Port (COMn) is listed. "
        "Note the number n.",
    ])
    d.note("Windows can give the board a different COM number when it is "
           "plugged into a different USB port. The GUI marks the likely port "
           "with an asterisk (*).")
    d.h2("Starting the GUI")
    d.p(f"Copy `{EXE_NAME}` to a folder on the PC and double-click it. There "
        "is no installer. The program opens maximised, so the whole window is "
        "visible without resizing.")
    d.p("On first start the program creates a folder named `HarnessTesterData` "
        "next to itself. It keeps the profiles, the connector configuration, "
        "saved netlists and every test result there. If that folder cannot be "
        "written (for example, on a read-only disk), the program uses "
        "`%LOCALAPPDATA%\\HarnessTester` instead. Keep the program in a folder "
        "you can write to.")
    d.note("The first time the program is started on a PC, Windows may ask you "
           "to confirm that you want to run it. Choose More info and then Run "
           "anyway. Windows asks only once for each copy of the file.")
    d.h2("The Main Window")
    d.figure(shot("window_pass.png"), "The main window", 15.9)
    d.table(["Area", "What it is for"], [
        ["Menu bar", "File, View and Help menus."],
        ["Toolbar", "Test mode, START TEST, STOP / ABORT, progress, duration and the verdict."],
        ["Left panel", "Connection, Netlist / Test Mode and Test Profile."],
        ["Tabs", "Connector View, Results Table, Log, Info and Configuration."],
        ["Status bar", "Short messages, such as the name of the file just saved."],
    ], "Areas of the main window", weights=[24, 76])

    # ── 4 Connecting the tester ───────────────────────────────────────────────────────────
    d.h1("Connecting the Tester")
    d.h2("Cable and Power")
    d.steps([
        "Make sure the harness is not connected yet.",
        "Plug the USB cable into the connector marked CN1 (ST-LINK) on the "
        "board, the one next to the ST-Link section.",
        "Plug the other end into the PC.",
        "Watch the LEDs. Within about two seconds LD1, LD2 and LD3 blink "
        "together three times, and then LD1 (green) stays on. The tester is "
        "ready.",
    ])
    d.figure(dia("hardware.png"), "Connecting the system", 14.5)
    d.p("If no LED lights up, try another USB cable or port. If the LEDs blink "
        "but the COM port is missing in Windows, install the driver (section 3.2).")
    d.h2("Connecting in the GUI")
    d.steps([
        "In the Connection group of the left panel, click Refresh.",
        "Choose the COM port that is marked with an asterisk and named "
        "STMicroelectronics STLink Virtual COM Port.",
        "Leave Baud at 115200.",
        "Click Connect. After a moment the status line changes from Not "
        "connected to CONNECTED with the firmware version, and the Connect "
        "button greys out.",
    ])
    d.figure(shot("panel_left_loaded.png"), "The left panel when connected, with a netlist loaded", 6.0, max_h_cm=16)
    d.p("While connected, the GUI sends a short check message every two "
        "seconds. If three in a row are not answered, it reports a lost "
        "connection in the Log tab and tries to reconnect up to five times. "
        "If the cable is removed, plug it back in and click Connect.")

    # ── 5 Connecting the harness ───────────────────────────────────────────────────────────
    d.h1("Connecting the Harness")
    d.p("The tester has two sides. Side A drives and Side B senses. Each side "
        "has the same three connectors: J1 (DB15), J2 (DB15) and J3 (DB9). "
        "Plug one end of the harness into the Side-A connector or connectors "
        "and the other end into the Side-B connectors, as your netlist "
        "describes.")
    d.table(["Connector", "Type", "Pins", "Typical use"], [
        ["J1", "DB15", "1 to 15", "First group of wires"],
        ["J2", "DB15", "1 to 15", "Second group of wires"],
        ["J3", "DB9", "1 to 7", "Third group (seven pins in use)"],
    ], "Connectors on each side")
    d.note("A wire may start on one connector and end on another, for example "
           "J1 pin 5 to J2 pin 9. The connector view draws such wires across "
           "the diagram.")
    d.h2("Connector Configuration")
    d.p("The tester numbers its channels 1 to 37. The connector configuration "
        "says which connector pin each channel is. The default configuration "
        "is loaded automatically and is correct for the standard tester. You "
        "only need to open the Configuration tab if your connectors are wired "
        "differently; the GUI Functional Description explains the tab.")
    d.p("The far end of each connector can have its own name. If the harness "
        "connectors are called X1, X2 and X3, enter those names in the Dst "
        "Conn ID column of the Configuration tab. The Side-B connectors "
        "are then shown, and reported, as X1, X2 and X3, while the Side-A "
        "connectors stay J1, J2 and J3. Pin numbers do not change.")
    d.p("If the configuration has an error, or a netlist uses a channel the "
        "configuration does not list, START TEST stays disabled and the Log tab "
        "says why.")

    # ── 6 Netlist ─────────────────────────────────────────────────────────────────────────────
    d.h1("Preparing a Netlist")
    d.p("A netlist lists the wires the harness should have. Each row is one "
        "wire: where it starts, where it ends, and a name. Continuity and "
        "Cross Continuity tests compare the harness with the netlist. "
        "Auto-Scan does not need one.")
    d.h2("Spreadsheet or CSV Netlist")
    d.p("Create a sheet with one header row and one row per wire. Column "
        "names are not case-sensitive, and a space and an underscore are the "
        "same. The three columns marked required must be present.")
    d.table(["Column", "Required", "Meaning"], [
        ["Net", "Yes", "Name of the wire, for example W_PWR_24V."],
        ["Src Pin #", "Yes", "Channel number at the Side-A end (1 to 37)."],
        ["Dst Pin #", "Yes", "Channel number at the Side-B end (1 to 37)."],
        ["Src Pin Label", "No", "Signal name shown beside the Side-A pin."],
        ["Dst Pin Label", "No", "Signal name shown beside the Side-B pin."],
        ["Source", "No", "Label for the Side-A end, for example Side-A."],
        ["Destination", "No", "Label for the Side-B end, for example Side-B."],
        ["Part Number", "No", "Connector part number at the Side-A end."],
        ["Part Number B", "No", "Connector part number at the Side-B end."],
        ["Harness ID", "No", "Name of the harness; shown in the left panel."],
        ["Colour", "No", "Wire colour. Shown in the results and named on the wire in the Sections view."],
        ["AWG", "No", "Wire gauge."],
        ["Length", "No", "Wire length, as you want it written."],
        ["Harness No", "No", "Harness number of the wire."],
    ], "Netlist columns", center_cols=(1,))
    d.p("The connector columns (Conn ID and Conn ID B) are filled in "
        "automatically from the connector configuration, so you can leave "
        "them out. Example rows:")
    d.table(["Net", "Src Pin #", "Dst Pin #", "Src Pin Label"], [
        ["W_PWR_24V", "1", "1", "PWR_24V"],
        ["W_CAN_H", "3", "3", "CAN_H"],
        ["W_LINK_A", "5", "24", "LINK_A"],
    ], "Example netlist rows", center_cols=(1, 2))
    d.p("In the last row the wire starts on channel 5 (J1 pin 5) and ends on "
        "channel 24 (J2 pin 9).")
    d.h2("Loading the Netlist")
    d.steps([
        "Make sure Standard (file) is selected in the Netlist / Test Mode group.",
        "Click Browse, or choose File, Load Netlist (Ctrl+O).",
        "Select the file. The file name appears beside Browse, and the tree "
        "below lists every wire with its pins.",
        "Check the connector view: the wires of the netlist are drawn between "
        "the Side-A and Side-B connectors, all grey (untested).",
    ])
    d.p("If the file cannot be read, a Netlist Error window states the reason, "
        "for example a missing column. Fix the file and load it again.")
    d.figure(shot("diagram_pass.png"), "The connector view with a netlist loaded and all wires passing", 11.0, max_h_cm=19)

    # ── 7 Running tests ─────────────────────────────────────────────────────────────────────────
    d.h1("Running a Test")
    d.p("Before every test, check that LD1 is steady green, the status line "
        "says CONNECTED, the harness is plugged in on both sides, and START TEST "
        "is enabled.")
    d.h2("Continuity Test (Mode 1)")
    d.p("The Continuity test checks every wire in the netlist, one after "
        "another. Use it for routine pass or fail testing.")
    d.steps([
        "In the toolbar, set Mode to Continuity (one-to-one).",
        "Load the netlist (section 6.2).",
        "Enter your name in Operator and the harness serial number in DUT ID.",
        "Click START TEST, or press F5. LD1 goes out, LD2 lights blue (it "
        "blinks if the scan lasts longer than a second) and the progress bar "
        "shows the pairs done.",
        "When the run ends, read the verdict in the toolbar: PASS in green or "
        "FAIL in red. LD1 blinks twice for a pass; LD3 blinks twice for a fail.",
        "The results are saved to a CSV file automatically. After a FAIL the "
        "Results Table tab opens by itself.",
    ])
    d.h2("Cross Continuity Test (Mode 2)")
    d.p("Cross Continuity drives each Side-A pin and reads all 37 Side-B pins. "
        "It finds wires that are missing and also connections that should not "
        "exist, such as a short between two pins. It reports all 1369 pairs, "
        "so it takes a few seconds.")
    d.note("In this version Cross Continuity is reliable for harnesses whose wires join the same channel number on both sides, for example A3 to B3. For a wire between different channel numbers, such as J1 pin 5 to J2 pin 9, the firmware also expects the reverse connection, which does not exist, and reports it as NOT CONNECTED, so the verdict is FAIL. Use Continuity (Mode 1) for harnesses with such wires.")
    d.steps([
        "Set Mode to Cross Continuity (one-to-many).",
        "Load the netlist.",
        "Click START TEST.",
        "Read the verdict. FAIL means a listed wire is missing, or an unlisted "
        "connection exists.",
        "In the Results Table, use the Status filter to show only NOT "
        "CONNECTED rows, then look for rows that are tinted red: they are "
        "the problems.",
    ])
    d.note("In Cross Continuity the results table shows each pair as, for "
           "example, Side A of J1 pin 5 and Side B of J2 pin 9, and shows "
           "the pairs sorted by connector and pin.")
    d.h2("Auto-Scan")
    d.p("Auto-Scan finds out how an unknown harness is wired, with no netlist. "
        "It tests all 37 by 37 pin pairs and lists only the connections that "
        "exist.")
    d.steps([
        "In the Netlist / Test Mode group, select Auto-Scan.",
        "Click START TEST, or press the blue user button B1 on the board.",
        "Wait for the scan to finish. The Connector View tab opens and "
        "draws every connection that was found.",
        "To test more harnesses of the same kind against this one, click Use "
        "as Netlist. The result is saved as a netlist file and loaded, and "
        "Standard mode is selected again.",
    ])
    d.figure(shot("diagram_autoscan.png"), "Connections found by Auto-Scan", 10.0, max_h_cm=19)
    d.p("The toolbar shows PASS when an Auto-Scan completes. That only means "
        "the scan finished; nothing was compared. Check the connections "
        "against what you expected.")
    d.h2("Stopping a Test")
    d.p("Click STOP / ABORT or press F6. The GUI returns to idle at once and "
        "the results received so far stay on the screen. The tester, however, "
        "acts on the stop request only after the scan it is running has "
        "ended, which takes a few seconds at most. Wait for the green LD1 "
        "to become steady before you start the next test.")

    # ── 8 Reading results ───────────────────────────────────────────────────────────────────────────
    d.h1("Reading the Results")
    d.h2("Connector View")
    d.p("The connector view shows each wire as a line between its Side-A pin "
        "and its Side-B pin. Wires are drawn at right angles, and where one "
        "wire crosses another it hops over it. The colour of each pin and "
        "wire shows its state.")
    d.table(["Colour", "State", "Meaning"], [
        ["Grey", "Untested", "No result received yet, or the pin is not in the netlist."],
        ["Yellow", "In progress", "Being tested."],
        ["Green", "Connected", "The wire was found."],
        ["Red", "Not connected", "A wire the netlist lists was not found."],
    ], "Colours in the connector view", center_cols=(0,))
    d.figure(shot("diagram_fail.png"), "A failed test: red wires are missing", 11.0, max_h_cm=19)
    d.p("The Single view shows all six connectors in one diagram, with Side A "
        "on the left and Side B on the right. The Sections view shows one "
        "section per connector. Hold the mouse over a pin to see its "
        "connector, pin number and channel.")
    d.h2("Results Table")
    d.p("The Results Table tab lists one row per pair tested, with the "
        "connector, pin and signal name at both ends, and a status badge. "
        "Green rows are connected; red rows are not.")
    d.figure(shot("results_fail.png"), "The results table after a failed test", 15.5)
    d.p("Use the Status box to show only CONNECTED or NOT CONNECTED rows, "
        "type in the search box to find a pin name or net, and click a column "
        "heading to sort. The line under the table counts the totals. "
        "Right-click selected rows and choose Copy to Clipboard as CSV to "
        "paste them into a spreadsheet.")
    d.h2("The Log")
    d.p("The Log tab records everything that happens: connecting, loading a "
        "netlist, starting and ending a test, saving results, warnings and "
        "errors. Messages are timestamped; warnings are orange and errors red. "
        "Use Save Log to keep a copy when you report a problem.")
    d.figure(shot("log_fail.png"), "The Log tab after a failed test", 15.0, max_h_cm=9)

    # ── 9 Reports ───────────────────────────────────────────────────────────────────────────────────────
    d.h1("Reports and Saved Data")
    d.h2("Automatic CSV")
    d.p("When a Continuity or Cross Continuity test ends, the GUI saves the "
        "results as a CSV file in the results folder. Auto-Scan saves one "
        "too. The name is:")
    d.code(["report_YYYYMMDD_HHMMSS_<DUT ID>.csv"])
    d.p("The file opens in Excel. The first rows hold the DUT ID, operator, "
        "netlist, verdict and date and time. The table below them has the "
        "same columns as the Results Table.")
    d.h2("Saving a CSV Manually")
    d.p("Choose File, Save Results as CSV (Ctrl+S) to save the results on "
        "screen under a name and place you choose.")
    d.h2("PDF Report")
    d.p("Choose File, Export PDF Report (Ctrl+P). Pick a file name. The "
        "report has the company logo, the DUT ID, the verdict, the date and "
        "operator, the duration, a summary of totals, and the full results "
        "table. It is suitable for attaching to a production record.")
    d.figure(shot("report_pdf_page1.png"), "First page of a PDF report", 9.0, max_h_cm=19)
    d.h2("Where the Files Are")
    d.p("Choose File, Open Results Folder to open the folder that holds the "
        "CSV files in Windows Explorer. All data is in the HarnessTesterData "
        "folder described in section 3.3.")
    d.table(["What", "Where (inside HarnessTesterData)"], [
        ["Test results (CSV)", "`profiles\\results`"],
        ["Test profiles", "`profiles`"],
        ["Connector configuration", "`profiles\\connector_config.xlsx`"],
        ["Netlists saved from Auto-Scan", "`netlists`"],
        ["Window size and theme", "`profiles\\app_settings.json`"],
    ], "Folders used by the GUI", weights=[40, 60])

    # ── 10 Profiles ──────────────────────────────────────────────────────────────────────────────────────
    d.h1("Profiles and Settings")
    d.p("A profile remembers the operator name, the DUT ID, the netlist and "
        "the baud rate, so the next session starts as you left it.")
    d.bullets([
        "**Save** stores the current values in the selected profile.",
        "**New** asks for a name and creates a profile.",
        "**Delete** removes the selected profile. The Default profile cannot "
        "be deleted.",
        "**DUT ID** counts up by one after every completed test, so each "
        "result file has its own number. Type a new value at any time.",
        "**Harness ID** is a note field for the operator. In this version it is "
        "not saved in the profile or written to the reports; the harness name "
        "shown in purple above the netlist tree comes from the netlist file.",
        "**Theme** (View, Theme) switches between dark and light.",
    ])

    # ── 11 Troubleshooting ───────────────────────────────────────────────────────────────────────────────────
    d.h1("Troubleshooting")
    d.table(["Symptom", "Likely cause and action"], [
        ["No COM port in the list",
         "Cable is charge-only, or the driver is missing. Try another cable and "
         "port, install the ST-Link driver, then click Refresh."],
        ["Connect hangs or fails",
         "Another program (STM32CubeIDE, a terminal) holds the port, or the "
         "wrong port is chosen. Close the other program. Pick the port marked *."],
        ["Port opens but nothing answers",
         "The board is not responding. Unplug the USB cable, wait five seconds, "
         "plug it in again, wait for the LED boot pattern, then connect."],
        ["START TEST is disabled",
         "Not connected, a test is running, the connector configuration has an "
         "error, or the netlist uses a channel the configuration does not list. "
         "Read the Log tab."],
        ["Netlist Error window",
         "The file is missing a required column or has an invalid pin number. "
         "Fix the file as the message says."],
        ["Every wire shows NOT CONNECTED",
         "Harness not plugged in, the wrong connector, or the baud rate is not "
         "115200. Check the plug and the baud box."],
        ["Pins look connected to everything",
         "A Side-B input is stuck HIGH (the Log tab names it), often because a "
         "debug session left trace enabled. Close the debugger, power-cycle the "
         "board and test again."],
        ["Log says connection lost",
         "Cable moved or the board reset. Reconnect. If it repeats, replace the "
         "cable or use a different USB port."],
        ["Windows asks to confirm running the program",
         "Choose More info, then Run anyway. This is asked once per copy."],
        ["Results file not found",
         "Use File, Open Results Folder. If the program is on a read-only disk "
         "the folder is under %LOCALAPPDATA%\\HarnessTester."],
    ], "Troubleshooting guide", weights=[30, 70])
    d.note("Calibration (F7) is a placeholder in this version and does not "
           "affect any result. You do not need to run it.")

    # ── 12 Quick reference ────────────────────────────────────────────────────────────────────────────────────────
    d.h1("Quick Reference")
    d.table(["Key", "Action"], [
        ["F5", "Start test"],
        ["F6", "Stop or abort the test"],
        ["F7", "Calibrate (placeholder)"],
        ["Ctrl+O", "Load netlist"],
        ["Ctrl+S", "Save results as CSV"],
        ["Ctrl+P", "Export PDF report"],
        ["Ctrl+M", "Show the Connector View tab"],
        ["Ctrl+R", "Show the Results Table tab"],
        ["Ctrl+L", "Show the Log tab"],
    ], "Keyboard shortcuts", center_cols=(0,), weights=[25, 75])
    d.table(["Step", "Do this"], [
        ["1", "Plug in the USB cable; wait for the green LED."],
        ["2", "Start the GUI; choose the COM port; click Connect."],
        ["3", "Load the netlist; plug in the harness."],
        ["4", "Choose the mode; click START TEST."],
        ["5", "Read PASS or FAIL; check the Results Table after a FAIL."],
        ["6", "Find the CSV in the results folder; export the PDF if needed."],
    ], "Daily routine in six steps", center_cols=(0,), weights=[12, 88])
    d.save(path)
    return d
