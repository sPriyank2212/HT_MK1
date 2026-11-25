# -*- coding: utf-8 -*-
from common import *


def build(path):
    d = new_doc("HT_MK0_OVW", "System Overview")
    d.standard_intro(
        purpose=[
            "This document describes what the HT_MK0 Harness Tester is, what it "
            "measures, how a test works, and how the tester decides between pass "
            "and fail. It is the first document to read; the other documents in "
            "the package go into operation, the screens, flashing, acceptance "
            "testing and the code.",
        ],
        audience=[
            "Everyone who works with the HT_MK0: operators, test engineers, "
            "acceptance testers and maintainers. No electronics or programming "
            "knowledge is needed to follow this document.",
        ],
        related=PACKAGE_DOCS)

    # ── 2 What it is ────────────────────────────────────────────────────────────
    d.h1("What the HT_MK0 Is", page_break=True)
    d.p("The HT_MK0 Harness Tester checks that the wires of a cable harness "
        "connect the pins they should and nothing else. It is the proof-of-concept "
        "build of the Harness Tester: a standard NUCLEO-F303ZE development board "
        "running the test firmware, controlled from a Windows program, the Harness "
        "Tester GUI. The board is used as delivered; nothing on it is modified.")
    d.p("The tester has 37 test channels. Each channel has one output pin on "
        "Side A and one input pin on Side B. The harness under test is "
        "connected between the two sides. The channels are brought out to "
        "three connectors on each side: J1 and J2 (DB15, 15 pins each) and "
        "J3 (DB9, 7 pins used).")
    d.figure(dia("system_block.png"), "System block diagram", 15.0)
    d.h2("Key Facts")
    d.table(["Item", "Value"], [
        ["Product", "HT_MK0 Harness Tester (proof of concept)"],
        ["Test hardware", "NUCLEO-F303ZE board, STM32F303ZE microcontroller, 72 MHz"],
        ["Test channels", "37 outputs (Side A) and 37 inputs (Side B)"],
        ["Connectors", "J1 (DB15), J2 (DB15) and J3 (DB9) on each side"],
        ["Signal level", "3.3 V logic; no external voltage may be applied"],
        ["PC link", "USB cable to the board; virtual COM port at 115200 baud, 8N1"],
        ["Power", "From the USB cable; no separate supply"],
        ["Firmware version", f"{FW_VERSION}"],
        ["GUI version", f"{GUI_VERSION} (Windows 10 or 11, 64-bit)"],
        ["Netlist files", "JSON, Excel (.xlsx) or CSV"],
        ["Reports", "CSV saved automatically after every test; PDF on request"],
    ], "Key facts of the HT_MK0", weights=[28, 72])

    # ── 3 How a test works ─────────────────────────────────────────────────────────
    d.h1("How a Test Works")
    d.h2("Continuity Principle")
    d.p("Every Side-B input has a pull-down resistor, so an input that is not "
        "connected to anything reads LOW. To test a wire, the firmware drives one "
        "Side-A pin HIGH and then reads the Side-B pins. If the wire is present "
        "and intact, the Side-B pin at its other end reads HIGH. If the wire is "
        "broken, that pin stays LOW.")
    d.figure(dia("principle.png"), "Continuity test principle", 14.0)
    d.p("The firmware repeats this for every pair it has to check, waiting 5 ms "
        "after each Side-A pin is driven so the level can settle, and sends one "
        "result to the PC for each pair. The GUI colours the wire in the "
        "connector view, adds a row to the results table, and decides the "
        "overall verdict when the run ends.")
    d.h2("Test Modes")
    d.p("The operator chooses what to run in the toolbar and in the Netlist / "
        "Test Mode group of the left panel. There are three ways to test.")
    d.table(["Mode", "What it does", "Netlist", "Result"], [
        ["Continuity", "Checks each wire listed in the netlist, one pair at a time.",
         "Recommended. Without one, the firmware scans its built-in straight map A1-B1 to A37-B37 (or the last netlist it received)",
         "PASS or FAIL"],
        ["Cross Continuity", "Drives each Side-A pin and reads all 37 Side-B pins, "
         "so unexpected connections are found as well as missing wires.",
         "Required", "PASS or FAIL"],
        ["Auto-Scan", "Finds every connection that exists, without a netlist. "
         "Can also be started with the button B1 on the board.",
         "Not needed", "List of connections found"],
    ], "The three test modes")
    d.note("In this version Cross Continuity is reliable for harnesses whose wires join the same channel number on both sides, for example A3 to B3. For a wire between different channel numbers, such as J1 pin 5 to J2 pin 9, the firmware also expects the reverse connection, which does not exist, and reports it as NOT CONNECTED, so the verdict is FAIL. Use Continuity (Mode 1) for harnesses with such wires.")
    d.h2("Channels and Connector Pins")
    d.p("The firmware knows only channel numbers, 1 to 37. A small Excel file, "
        "connector_config.xlsx, says which connector pin each channel is wired "
        "to. The GUI uses it to show results as, for example, J2 pin 5 instead "
        "of channel 20. The file is part of the package and can be edited in the "
        "Configuration tab of the GUI.")
    d.figure(dia("mapping.png"), "From a netlist pin to a connector pin", 14.0)
    d.h2("Test Duration")
    d.p("A Continuity run on a full 37-wire harness completes in well under a "
        "second. A Cross Continuity run reports all 37 by 37 pairs over the "
        "115200 baud link and typically takes a few seconds. The duration of "
        "each run is shown in the toolbar.")

    # ── 4 Pass and fail ─────────────────────────────────────────────────────────────
    d.h1("Pass and Fail Conditions")
    d.p("Each tested pair gets one of the results below. The results table and "
        "the reports show only two words, CONNECTED and NOT CONNECTED; the "
        "column on the right says what the firmware found.")
    d.table(["Result", "Shown as", "Meaning", "Counts as"], [
        ["Expected pair present", "CONNECTED", "The wire the netlist lists is present.", "Pass"],
        ["Expected pair missing", "NOT CONNECTED", "An open: the netlist lists a wire that is not there.", "Fail"],
        ["Unexpected pair present", "NOT CONNECTED", "A miswire or short: a connection the netlist does not list (Cross Continuity only).", "Fail"],
        ["No pair expected, none found", "NOT CONNECTED", "Normal for an unused pair (Cross Continuity only).", "Neither"],
    ], "Result of one tested pair")
    d.p("The verdict shown in the toolbar follows from these results.")
    d.table(["Mode", "PASS when", "FAIL when"], [
        ["Continuity", "Every wire in the netlist is present.", "One or more listed wires are missing."],
        ["Cross Continuity", "Every listed wire is present and no unlisted connection is found.",
         "A listed wire is missing, or an unlisted connection is found."],
        ["Auto-Scan", "The scan completes. It reports what it found and compares nothing, so the toolbar shows PASS.",
         "Not applicable. Stuck inputs, if any, are reported in the Log tab."],
    ], "Verdict rules")
    d.note("If any Side-B input already reads HIGH before a scan drives anything, "
           "the firmware reports a stuck input to the GUI. Such an input would "
           "look connected to every pin, so the results of that run cannot be "
           "trusted until the cause is fixed. See the User Manual, Troubleshooting.")

    # ── 5 Limits ─────────────────────────────────────────────────────────────────────
    d.h1("What the HT_MK0 Does Not Do")
    d.p("The HT_MK0 tests continuity only. It uses the digital inputs and "
        "outputs of the microcontroller, so it cannot measure analogue values.")
    d.bullets([
        "**Resistance.** There is no resistance measurement. A wire is either "
        "connected or not connected. The resistance values the firmware reports "
        "are fixed placeholders and are not shown as measurements.",
        "**Insulation resistance and high voltage.** There is no high-voltage "
        "hardware. The firmware has an insulation command for protocol "
        "compatibility, but it returns fixed values and the GUI does not offer it.",
        "**Calibration.** The calibration command is a placeholder; it does not "
        "change any result.",
        "**Voltage on the harness.** The pins are 3.3 V logic only. The harness "
        "under test must not carry any voltage.",
    ])
    d.warning("Never connect a harness that is powered, or any external voltage "
              "source, to the test pins. The pins are connected directly to the "
              "microcontroller and are not protected against overvoltage.")

    # ── 6 Indicators ────────────────────────────────────────────────────────────────────
    d.h1("Indicators and Controls on the Board")
    d.p("The three LEDs and the user button of the NUCLEO board give status "
        "without looking at the PC.")
    d.table(["LED", "Colour", "Meaning"], [
        ["LD1", "Green", "Steady: idle and ready. Two short blinks: the last test passed."],
        ["LD2", "Blue", "Slow blink: a scan or netlist upload is running. Fast blink: calibrating."],
        ["LD3", "Red", "Two short blinks: the last test failed."],
        ["All three", "-", "Three blinks together at power-on: the firmware has started."],
    ], "Board LEDs", center_cols=(0,))
    d.figure(dia("led_patterns.png"), "LED patterns", 14.0)
    d.p("The blue user button B1 starts an Auto-Scan without using the PC, "
        "provided the tester is idle. A press during a scan is ignored.")

    # ── 7 Pin support ────────────────────────────────────────────────────────────────────
    d.h1("Pin Support")
    d.p("The default connector configuration assigns the 37 channels to the "
        "three connectors as below. Every channel exists on both sides, so "
        "Side A and Side B each have a copy of J1, J2 and J3.")
    d.table(["Connector", "Type", "Channels", "Pins used", "Part numbers in the example netlists"], [
        ["J1", "DB15", "1 to 15", "15", "DB15-M-15P (Side A), DB15-F-15S (Side B)"],
        ["J2", "DB15", "16 to 30", "15", "DB15-M-15P (Side A), DB15-F-15S (Side B)"],
        ["J3", "DB9", "31 to 37", "7", "DB9-M-09P (Side A), DB9-F-09S (Side B)"],
    ], "Connector layout of the default configuration")
    d.p("A netlist may wire any Side-A pin to any Side-B pin, including pins on "
        "a different connector. A channel that the connector configuration does "
        "not list cannot be used: the GUI refuses to start such a test.")
    d.h2("Pins That Share a Function on the Board")
    d.p("A few microcontroller pins also have another job on the NUCLEO board "
        "(debug trace, USB, boot selection). They work as test pins, but a "
        "fault on one of them may come from the board rather than the harness. "
        "The GUI lists them in the Log tab when the configuration is loaded.")
    d.table(["Connector pin", "Side", "MCU pin", "Other use"], shared_pin_rows(),
            "Test pins that share a function", center_cols=(1,))
    d.note("A debugger left running with trace enabled can hold the five trace "
           "pins HIGH, which makes those channels read as connected to everything. "
           "The firmware releases the trace pins at power-on and before every "
           "scan; close any debug session and power-cycle the board if the "
           "Log tab reports that trace was active.")

    # ── 8 Supporting tools ─────────────────────────────────────────────────────────────────────
    d.h1("Supporting Tools and Files")
    d.p("The package contains the following items. The Harness Tester GUI is "
        "described screen by screen in the GUI Functional Description.")
    d.table(["Item", "Purpose"], [
        [f"`{EXE_NAME}`", "The Harness Tester GUI. A single program; no installation."],
        ["`POC_HT.elf`", "The firmware, programmed once onto the NUCLEO board."],
        ["`connector_config.xlsx`", "Maps channels to connector pins. Default for J1, J2, J3."],
        ["Example netlists", "Sample .json, .xlsx and .csv netlists to copy from."],
        ["ST-Link driver", "Installed with STM32CubeProgrammer; needed for the USB link."],
    ], "Items in the package", weights=[34, 66])
    d.figure(shot("window_pass.png"), "The Harness Tester GUI after a passing Continuity test", 15.5)

    # ── 9 Requirements ─────────────────────────────────────────────────────────────────────────────
    d.h1("System Requirements")
    d.table(["Item", "Requirement"], [
        ["Operating system", "Windows 10 or Windows 11, 64-bit"],
        ["USB", "One free USB port and a data-capable USB cable (not charge-only)"],
        ["Driver", "ST-Link virtual COM port driver (installed with STM32CubeProgrammer)"],
        ["Disk space", "About 100 MB for the program; test results are small CSV files"],
        ["Screen", "1280 by 800 or larger; the GUI opens maximised"],
        ["Excel", "Not required; netlists and the connector configuration are read directly"],
    ], "PC requirements", weights=[28, 72])
    d.save(path)
    return d
