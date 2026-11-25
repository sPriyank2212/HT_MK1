# -*- coding: utf-8 -*-
from common import *


def build(path):
    d = new_doc("HT_MK0_FLASH", "Flashing Procedure")
    d.standard_intro(
        purpose=[
            "This document describes how to program (flash) the HT_MK0 "
            f"firmware, version {FW_VERSION}, onto the NUCLEO-F303ZE board, "
            "and how to confirm that the firmware is running afterwards.",
            "The primary method uses STM32CubeProgrammer. A command-line "
            "method and a method from STM32CubeIDE are also given.",
        ],
        audience=[
            "Whoever programs the firmware: a technician preparing a new tester "
            "or an engineer updating an existing one. No programming "
            "knowledge is needed; the steps are the same for every board.",
        ],
        related=PACKAGE_DOCS)

    # ── 2 Overview ───────────────────────────────────────────────────────────────────
    d.h1("Overview", page_break=True)
    d.p("The firmware is stored in the flash memory of the STM32F303ZE "
        "microcontroller on the NUCLEO board. It is written over the USB "
        "cable, through the ST-Link programmer that is built into the board. "
        "No other programmer, jumper or adapter is needed, and the board is "
        "not modified.")
    d.figure(dia("flash_flow.png"), "The flashing procedure at a glance", 15.0)
    d.table(["Item", "Value"], [
        ["Target board", "NUCLEO-F303ZE (NUCLEO-144)"],
        ["Microcontroller", "STM32F303ZETx, 512 KB flash"],
        ["Flash start address", "0x08000000"],
        ["Firmware file", "`POC_HT.elf`"],
        ["Firmware version", FW_VERSION],
        ["Programming interface", "ST-Link, over SWD, through the USB connector CN1"],
        ["Time to program", "Normally under 10 seconds"],
    ], "Programming facts", weights=[34, 66])
    d.note("Flashing replaces the whole program. The board keeps no test "
           "data, so nothing needs to be saved first. The netlists, the "
           "connector configuration and the results live on the PC.")

    # ── 3 Before you begin ──────────────────────────────────────────────────────────────────
    d.h1("Before You Begin")
    d.h2("What You Need")
    d.table(["Item", "Notes"], [
        ["NUCLEO-F303ZE board", "The tester board to be programmed."],
        ["USB cable", "Data-capable; fits the ST-LINK USB connector (CN1) of the board."],
        ["PC", "Windows 10 or 11, with a free USB port."],
        ["STM32CubeProgrammer", "Free from STMicroelectronics. Installs the ST-Link driver."],
        ["Firmware file", "`POC_HT.elf`, copied to a folder on the PC."],
    ], "Items needed for flashing", weights=[30, 70])
    d.h2("Checklist")
    d.bullets([
        "The Harness Tester GUI is closed, or disconnected. It would hold the "
        "COM port that the programmer needs.",
        "No STM32CubeIDE debug session is running.",
        "No harness is connected. The pins are not used while flashing, but a "
        "clear board avoids accidents.",
        "The firmware file is the one you intend to load. Note its name and "
        "the version in the table above.",
    ])
    d.h2("The Connectors You Will Use")
    d.figure(dia("hardware.png"), "The USB connector CN1 and the LEDs of the board", 14.5)
    d.p("Programming uses only CN1, the USB connector at the ST-Link end of "
        "the board. The same cable later carries the test traffic.")

    # ── 4 STM32CubeProgrammer ─────────────────────────────────────────────────────────────────
    d.h1("Flashing with STM32CubeProgrammer")
    d.h2("Install the Programmer and Driver")
    d.steps([
        "Search for STM32CubeProgrammer on the STMicroelectronics website and "
        "download the Windows installer.",
        "Run the installer as administrator and accept the default folder.",
        "When asked about the ST-Link driver, choose Yes. The programmer "
        "cannot reach the board without it.",
        "Restart the PC if the installer asks.",
    ])
    d.h2("Connect the Board")
    d.steps([
        "Make sure the board is not yet plugged in.",
        "Plug the USB cable into CN1 on the board, and into the PC.",
        "Wait for Windows to finish detecting the board, up to ten seconds. "
        "LD1 (green) lights when the board has power.",
    ])
    d.h2("Connect the Programmer to the Board")
    d.steps([
        "Open STM32CubeProgrammer.",
        "At the top right, set the interface to ST-LINK. Leave the other "
        "settings at their defaults.",
        "Click Connect. After a few seconds the log reports the ST-Link serial "
        "number and identifies the device as an STM32F303.",
    ])
    d.p("If the connection fails, click the refresh button beside the port "
        "box and try again. If it still fails, see section 7.")
    d.h2("Load and Program the Firmware")
    d.steps([
        "In the left bar, open the Erasing & Programming page.",
        "Click Browse and select `POC_HT.elf`.",
        "Check that the start address shows 0x08000000.",
        "Tick Verify programming. Leave Skip flash erase before programming "
        "unticked.",
        "Click Start Programming. A progress bar shows the erase and the "
        "write.",
        "Wait until the log reports that the download is complete and, because "
        "verification was ticked, that it was verified successfully. If a "
        "verification error appears, repeat from step 1 of this section.",
    ])
    d.warning("Do not unplug the USB cable while the progress bar is moving. "
              "An interrupted write leaves the board without a working "
              "program; it can be recovered by flashing again.")
    d.h2("Finish")
    d.steps([
        "Click Disconnect in STM32CubeProgrammer.",
        "Unplug the USB cable and plug it in again. This is a full power-up.",
        "Check the LED pattern (section 5).",
    ])

    # ── 5 Verify ───────────────────────────────────────────────────────────────────────────────────
    d.h1("Checking That the Firmware Runs")
    d.h2("LED Check")
    d.p("After the cable is plugged in, LD1, LD2 and LD3 blink together three "
        "times, then only LD1 (green) stays on.")
    d.figure(dia("led_patterns.png"), "The LED pattern after power-up", 14.0)
    d.table(["What you see", "Meaning", "Action"], [
        ["Three blinks of all LEDs, then LD1 steady", "The firmware started normally.", "Continue to the GUI check."],
        ["No LED at all", "No power, or a charge-only cable.", "Try another cable or port."],
        ["LEDs blink but never settle on LD1", "The board keeps restarting.", "Flash again; check the firmware file."],
        ["Only LD1 on, no boot blinks", "The board was already running when connected.", "Unplug and plug in again to see the pattern."],
    ], "LED check results")
    d.h2("GUI Check")
    d.steps([
        f"Start `{EXE_NAME}`.",
        "Click Refresh, choose the port marked with an asterisk, and click "
        "Connect.",
        f"The status line must read CONNECTED followed by FW v{FW_VERSION}.",
        "Open the Info tab. The firmware version, the device state IDLE, the "
        "port and the baud rate are shown.",
        "In the Log tab, check that the connect line says TRACE=OFF.",
    ])
    d.figure(shot("panel_left_loaded.png"), "The status line after a successful flash", 5.5, max_h_cm=12)
    d.p("If the version shown is not the one you flashed, the wrong file was "
        "programmed or the verification was skipped. Flash again.")

    # ── 6 Alternatives ─────────────────────────────────────────────────────────────────────────────
    d.h1("Other Ways to Flash")
    d.h2("Command Line")
    d.p("STM32CubeProgrammer includes a command-line tool. It is convenient "
        "for flashing many boards. Open a command prompt in the folder that "
        "holds the firmware file and run:")
    d.code([
        "STM32_Programmer_CLI -c port=SWD",
        "  -w POC_HT.elf -v -rst",
    ])
    d.p("The options connect over SWD, write the file, verify the result, and "
        "restart the board. The tool prints Download verified successfully "
        "when it is done. Unplug and plug in the cable and check the LEDs as "
        "before.")
    d.h2("From STM32CubeIDE")
    d.p("Engineers who have the firmware source can build and flash from the "
        "development environment.")
    d.steps([
        "Open STM32CubeIDE and import the firmware project (the folder with "
        "POC_HT.ioc).",
        "Choose Project, Build Project with the Debug configuration.",
        "Connect the board and choose Run, Debug (or Run). The project's "
        "launch file selects the ST-Link.",
        "When finished, stop the session, close the debug view, and unplug "
        "and replug the USB cable before testing.",
    ])
    d.note("A debug session can leave the debug trace port enabled, which "
           "holds five Side-B pins HIGH. The firmware clears the trace "
           "port at start-up and before every scan, but always power-cycle the "
           "board after debugging. Do not build with the HT_KEEP_TRACE option "
           "for production boards; it is for trace sessions only.")

    # ── 7 Troubleshooting ──────────────────────────────────────────────────────────────────────────
    d.h1("Troubleshooting")
    d.table(["Problem", "Cause and remedy"], [
        ["The programmer shows no ST-Link",
         "Driver missing or cable charge-only. Reinstall the driver from the "
         "programmer installer; try another cable and port."],
        ["Connect fails or times out",
         "Another program holds the ST-Link (STM32CubeIDE debug, the GUI). "
         "Close it. Unplug and plug in the cable. Try the mode Under reset in "
         "the programmer."],
        ["Verification error",
         "Poor connection or a damaged file. Check the cable and copy the "
         "firmware file again, then flash again."],
        ["Programmer asks to update the ST-Link",
         "An optional update. It can be accepted or skipped; do not unplug "
         "the cable while it runs."],
        ["Board does not respond after flashing",
         "Unplug and plug in the cable. The COM port may have changed; click "
         "Refresh in the GUI."],
        ["COM port missing after flashing",
         "Wait ten seconds, then check Windows Device Manager. If it is "
         "still missing, power-cycle the board."],
        ["Pins look connected to everything",
         "A debug session left trace enabled. Close it, unplug and plug in "
         "the cable."],
    ], "Flashing troubleshooting", weights=[32, 68])

    # ── 8 Record ───────────────────────────────────────────────────────────────────────────────────────
    d.h1("Flash Record")
    d.p("Fill in one row for each board that is flashed and keep the record "
        "with the unit.")
    d.table(["Date", "Board serial", "Firmware file", "Version read", "OK", "Initials"],
            [["", "", "", "", "", ""], ["", "", "", "", "", ""], ["", "", "", "", "", ""]],
            "Flash record", weights=[15, 20, 20, 20, 10, 15])
    d.save(path)
    return d
