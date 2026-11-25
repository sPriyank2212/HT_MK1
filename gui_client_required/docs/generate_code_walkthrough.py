#!/usr/bin/env python3
"""
generate_code_walkthrough.py
Generates: Code_Walkthrough_CWR-HT-001.docx — Code Walkthrough, Harness Tester MK0

Built on the shared doc_template.py so this document shares fonts, colors,
tables, and page layout with the User Manual, Flashing/Deployment Procedure,
and Functional Test Procedure. Content below is sourced directly from the
firmware (firmware/Core/Src/harness.c, main.c, stm32f3xx_it.c) and GUI
(gui/core/*.py, gui/ui/main_window.py, gui/main.py) as they exist on
branch release_V2.0 — every function name, call, table value, and code
snippet is taken from that source, not paraphrased from the older
docs/Code_Walkthrough_CWR-HT-001.md.

Run from anywhere; output drops into the same folder as this script.
"""
import os
from doc_template import *

SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
OUTPUT_PATH = os.path.join(SCRIPT_DIR, "Code_Walkthrough_CWR-HT-001.docx")
LOGO_PATH   = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "resources", "company_logo.jpeg"))

COMPANY = "Priyank Soni"
CLIENT  = "Infinity Integrations Private Limited (I2PL)"
DATE    = "2026-08-27"

doc, sec = new_document()

build_cover_page(
    doc, sec,
    title="Code Walkthrough",
    subtitle="Harness Tester MK0 — Firmware and PC GUI",
    doc_id="CWR-HT-001",
    version="1.0",
    date=DATE,
    system="Harness Tester MK0 (STM32F303ZE Nucleo POC), firmware v2.2.0 / GUI v2.0.0",
    company=COMPANY,
    client=CLIENT,
    logo_path=LOGO_PATH,
)

build_revision_history_and_toc(doc, rows=[
    ["1.0", DATE,
     "Initial release under the shared documentation template. Rebuilt from "
     "current release_V2.0 source (firmware v2.2.0, GUI v2.0.0), covering "
     "cross-continuity scanning, auto-scan, stuck-pin detection, and TPIU "
     "trace-pad reclaim not present in the prior CWR-HT-001 Rev B.",
     "Priyank Soni"],
])

# ===========================================================================
# 1. Introduction
# ===========================================================================
doc.add_heading("1. Introduction", level=1)

doc.add_heading("1.1 Purpose", level=2)
doc.add_paragraph(
    "This document walks through the firmware and PC GUI source code for the Harness "
    "Tester MK0. It is written for engineers at Infinity Integrations Private Limited "
    "(I2PL) who will maintain, extend, or debug this system after technology transfer. "
    "It shows the real file layout, the call hierarchy from startup through the main "
    "test operations, the wire protocol between the two halves of the system, and the "
    "reasoning behind decisions that are not obvious from the code alone."
)

doc.add_heading("1.2 Scope", level=2)
add_table(doc, ["In Scope", "Out of Scope"], [
    ["firmware/Core/Src/harness.c and harness.h", "STM32CubeMX-generated HAL driver internals"],
    ["firmware/Core/Src/main.c and stm32f3xx_it.c", "PCB layout — MK0 uses an unmodified Nucleo board"],
    ["All files under gui/core/ and gui/ui/", "Production packaging and installer build"],
    ["UART protocol framing, CRC, command/response set", "External netlist-authoring tools (Excel/CSV format only)"],
    ["GUI state machine, serial worker, result model, PDF/CSV export", "The Integrated Harness Tester MK-I (256-pin/Kelvin/HV) design — "
     "not present in this codebase; see Known Limitations §7"],
])

doc.add_heading("1.3 Reference Documents", level=2)
add_table(doc, ["Document ID", "Title", "Relationship"], [
    ["UM-HT-MK0-v1.0", "User Manual, Harness Tester MK0", "Operator procedures this document's design decisions support"],
    ["FFP-HT-MK0-v1.0", "Flashing/Deployment Procedure, Harness Tester MK0", "Build and flash steps for the firmware described here"],
    ["FTP-HT-MK0-v1.0", "Functional Test Procedure, Harness Tester MK0", "Acceptance tests exercising the flows mapped in §4.4 and §3.4"],
    ["I2PL-PRJ-AV-IHT/01 (SOW)", "Statement of Work, Integrated Harness Tester MK-I", "Confirms MK0 is a zero-hardware-modification POC on an "
     "unmodified Nucleo-F303ZE, validating protocol and workflow ahead of the MK-I production design"],
])

# ===========================================================================
# 2. System Overview
# ===========================================================================
doc.add_heading("2. System Overview", level=1)
doc.add_paragraph(
    "The Harness Tester MK0 checks whether a wire harness is wired correctly. A harness "
    "under test is jumpered onto two sets of GPIO pins on an unmodified Nucleo-F303ZE "
    "development board — Side A (37 outputs) and Side B (37 inputs). The board's firmware "
    "drives Side-A pins and reads Side-B pins to discover which wires connect where. A "
    "Windows PC application (the “Harness Tester GUI”) loads a netlist describing the "
    "expected wiring, drives the test sequence over USB, and shows live results."
)
add_code_block(doc,
    "PC (Windows)                              Nucleo-F303ZE\n"
    "+----------------------+   UART/USB    +---------------------------+\n"
    "|  Harness Tester GUI  |<------------->|  harness.c firmware       |\n"
    "|  (PyQt6, gui/)       |  115200 baud  |  (firmware/Core/Src/)     |\n"
    "|  - MainWindow        |  8N1, binary  |  - packet decoder + CRC16 |\n"
    "|  - TestEngine        |  framing      |  - state machine          |\n"
    "|  - SerialWorker      |               |  - 37x37 GPIO scan        |\n"
    "+----------------------+               +------------+--------------+\n"
    "                                                     | 37 + 37 GPIO pins\n"
    "                                        Side-A outputs -- DUT -- Side-B inputs",
    caption="Figure 2.1 — System context. The USB link is the Nucleo's on-board ST-Link V2 "
            "virtual COM port; no external USB-UART adapter or power supply is needed."
)
doc.add_paragraph(
    "This is a zero-hardware-modification proof of concept, per the governing Statement "
    "of Work: the Nucleo board is used exactly as it ships. There is no custom PCB, no "
    "analog measurement front-end, and no high-voltage module in this codebase — resistance "
    "and insulation-resistance values reported by this system are fixed simulated constants, "
    "not measurements (see §7)."
)

# ===========================================================================
# 3. Firmware Architecture
# ===========================================================================
doc.add_heading("3. Firmware Architecture", level=1)

doc.add_heading("3.1 File Layout", level=2)
add_table(doc, ["File", "Contents"], [
    ["firmware/Core/Inc/harness.h", "Protocol constants (SOF, commands, responses, fault codes), the "
     "HT_State_t enum, HARNESS_PINS, and the four public API functions"],
    ["firmware/Core/Src/harness.c", "Everything else: ring buffer, CRC-16, packet decoder/encoder, GPIO "
     "pin tables, LED patterns, netlist JSON parser, and all five scan routines"],
    ["firmware/Core/Src/main.c", "CubeMX-generated entry point and peripheral init, plus the three "
     "USER CODE callbacks that hand control to harness.c"],
    ["firmware/Core/Src/stm32f3xx_it.c", "CPU exception handlers and the two peripheral IRQ handlers "
     "(USART3, EXTI15_10) that route into the HAL"],
    ["firmware/Core/Src/stm32f3xx_hal_msp.c, system_stm32f3xx.c, syscalls.c, sysmem.c",
     "CubeMX/HAL boilerplate — not modified for the harness feature set"],
])

doc.add_heading("3.2 Startup Call Hierarchy", level=2)
add_table(doc, ["Function", "Calls", "Purpose"], [
    ["main()", "HAL_Init, SystemClock_Config, MX_GPIO_Init, MX_RTC_Init, "
     "MX_USART3_UART_Init, HAL_NVIC_SetPriority x2, HAL_NVIC_EnableIRQ x2, HT_Init, "
     "HAL_UART_Receive_IT, HT_Process (in while(1))", "Entry point — CubeMX-generated init, then hands off to the harness module"],
    ["HT_Init(&huart3)", "harness_gpio_init, iwdg_init, nl_default", "Configures Side-A/B GPIO, starts the boot LED sequence, seeds the default 1:1 pin map"],
    ["harness_gpio_init()", "release_trace_pins, __HAL_RCC_GPIOE_CLK_ENABLE, HAL_GPIO_Init (per port)", "Reclaims the TPIU trace pads, then configures all 37 Side-A pins as push-pull outputs and all 37 Side-B pins as pulled-down inputs"],
    ["release_trace_pins()", "(direct DBGMCU->CR register access)", "Clears DBGMCU_CR_TRACE_IOEN so the debug block releases PE2-PE6 and PB3 back to GPIO — see §6"],
])
doc.add_paragraph(
    "main() then enters an unconditional while(1) loop that calls HT_Process() every "
    "iteration. There is no RTOS — the firmware is a plain superloop. Two interrupts feed "
    "it asynchronously: USART3 (byte reception) and EXTI15_10 (the user button, PC13)."
)
add_code_block(doc,
    "void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)\n"
    "{\n"
    "    if (huart->Instance == USART3) {\n"
    "        HT_UART_RxByte(uart3_rx_byte);\n"
    "        HAL_UART_Receive_IT(&huart3, &uart3_rx_byte, 1);\n"
    "    }\n"
    "}",
    caption="Listing 3.1 — firmware/Core/Src/main.c:308-314. Each received byte is handed "
            "to the harness module and the single-byte interrupt is immediately re-armed; "
            "there is no DMA or multi-byte buffering on the receive side."
)

doc.add_heading("3.3 Function Reference — harness.c", level=2)
add_table(doc, ["Function", "Calls", "Purpose"], [
    ["crc16()", "—", "CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF, no reflection) over a byte buffer"],
    ["send_packet()", "crc16, HAL_UART_Transmit", "Frames [SOF][LEN][CMD][PAYLOAD][CRC_HI][CRC_LO] and transmits it"],
    ["send_ack/send_nack/send_status/send_result_cont/send_result_short/\nsend_result_hv/send_progress/send_scan_done/send_fault()",
     "send_packet", "Typed response builders — one per RSP_* message defined in harness.h"],
    ["decoder_feed()", "crc16, dispatch_command", "6-state byte-at-a-time packet decoder (DEC_SOF...DEC_CRC_LO); silently discards CRC failures"],
    ["dispatch_command()", "handle_set_netlist, handle_set_param, handle_calibrate, run_continuity_scan, "
     "run_cross_continuity_scan, run_short_scan, run_hv_scan, run_auto_scan, send_ack/send_nack", "Command switch — the only caller of every run_*_scan() function"],
    ["nl_parse_json()", "—", "Hand-written scanner for the compact {\"nets\":[{\"pins\":[{\"n\":N}]}]} format; builds every "
     "i<j pin-index pair per net into nl_pairs[]"],
    ["harness_gpio_init()", "release_trace_pins, HAL_GPIO_Init", "One-time GPIO direction/pull configuration for all 74 pins"],
    ["led_update()", "HAL_GetTick, HAL_GPIO_WritePin (via LED_*_ON/OFF macros)", "Called every HT_Process() cycle — drives LD1/LD2/LD3 per current state"],
    ["baseline_check()", "all_side_a_low, HAL_Delay, read_side_b, send_fault", "Drives all Side-A pins low, then flags any Side-B pin still reading HIGH as stuck"],
    ["run_continuity_scan()", "release_trace_pins, baseline_check, write_side_a, read_side_b, "
     "send_result_cont, send_progress, send_scan_done", "Tests every pair in nl_pairs[] (netlist-defined or default 1:1)"],
    ["run_short_scan()", "release_trace_pins, baseline_check, write_side_a, read_side_b, is_expected, "
     "send_result_short, send_progress, send_scan_done", "For each Side-A pin, reads all 37 Side-B pins and reports any unexpected HIGH as a short"],
    ["run_cross_continuity_scan()", "release_trace_pins, baseline_check, write_side_a, read_side_b, is_expected, "
     "send_result_cont, send_progress, send_scan_done", "Full 37x37 sweep reporting PASS/OPEN/MISWIRE/NOT_CONNECTED for every pair"],
    ["run_hv_scan()", "release_trace_pins, baseline_check, send_result_hv, send_progress, send_scan_done", "Reports fixed simulated IR/HV values for every netlist pair — no real HV hardware exists on MK0"],
    ["run_auto_scan()", "release_trace_pins, baseline_check, write_side_a, read_side_b, send_result_cont, "
     "send_progress, send_scan_done", "Full 37x37 discovery with no netlist; skips pins already flagged stuck by baseline_check"],
    ["HT_Process()", "rb_pop, decoder_feed, led_update, iwdg_refresh (no-op)", "Main-loop body — drains the RX ring buffer, services the button request, updates LEDs"],
])

doc.add_heading("3.4 Runtime Call Hierarchy — Key Operations", level=2)

doc.add_paragraph("a) Byte reception through command dispatch:")
add_code_block(doc,
    "USART3_IRQHandler()                          [stm32f3xx_it.c]\n"
    "  -> HAL_UART_IRQHandler()                    [HAL, not shown]\n"
    "    -> HAL_UART_RxCpltCallback()              [main.c]\n"
    "      -> HT_UART_RxByte()                     [harness.c]\n"
    "        -> rb_push()                          [harness.c — ring buffer, ISR context]\n"
    "\n"
    "HT_Process()                                  [harness.c — main-loop context]\n"
    "  -> rb_pop()  (repeat until buffer empty)\n"
    "  -> decoder_feed(byte)\n"
    "    -> dispatch_command(cmd, payload, len)     [on valid CRC]\n"
    "      -> handle_set_netlist() / handle_set_param() / handle_calibrate()\n"
    "         / run_continuity_scan() / run_cross_continuity_scan()\n"
    "         / run_short_scan() / run_hv_scan() / run_auto_scan()",
    caption="Call tree 3.1 — verified against harness.c:135-183 (decoder_feed) and 1186-1284 "
            "(dispatch_command)."
)

doc.add_paragraph("b) CMD_START_CONT — the primary continuity scan:")
add_code_block(doc,
    "dispatch_command(CMD_START_CONT)              [harness.c:1213]\n"
    "  -> send_ack(NULL, 0)\n"
    "  -> run_continuity_scan()                    [harness.c:809]\n"
    "     -> release_trace_pins()                  reclaim TPIU pads stolen since boot\n"
    "     -> baseline_check()                      name any Side-B pin already stuck HIGH\n"
    "        -> all_side_a_low()\n"
    "        -> read_side_b() x37\n"
    "        -> send_fault(FAULT_STUCK_PINS, ...)   [only if any pin found stuck]\n"
    "     -> nl_default()                          [only if no netlist was uploaded]\n"
    "     -> for each pair in nl_pairs[]:\n"
    "          write_side_a(pin_a, HIGH)\n"
    "          read_side_b(pin_b)\n"
    "          write_side_a(pin_a, LOW)\n"
    "          send_result_cont(pin_a, pin_b, res_raw, fail)\n"
    "          send_progress(i+1, total)            [every 4th pair, and the last]\n"
    "     -> all_side_a_low()\n"
    "     -> send_scan_done(total, passed, failed)",
    caption="Call tree 3.2 — verified against harness.c:809-878."
)

doc.add_paragraph("c) CMD_AUTO_SCAN — no-netlist discovery, triggered by GUI or the on-board button:")
add_code_block(doc,
    "HT_ButtonPressed()                            [harness.c — EXTI15_10 ISR context]\n"
    "  -> sets g_btn_req = 1  (only while STATE_IDLE or STATE_COMPLETE)\n"
    "\n"
    "HT_Process()                                  [main-loop context]\n"
    "  -> if g_btn_req: run_auto_scan()             [harness.c:1070]\n"
    "     -> release_trace_pins(), baseline_check()\n"
    "     -> for each Side-A pin a in 0..36:\n"
    "          write_side_a(a, HIGH)\n"
    "          for each Side-B pin b in 0..36:\n"
    "            if g_stuck[b]: skip                skip pins already known stuck\n"
    "            if read_side_b(b): send_result_cont(a+1, b+1, 500, PASS)\n"
    "          write_side_a(a, LOW)\n"
    "     -> send_scan_done(found, found, g_stuck_count)",
    caption="Call tree 3.3 — verified against harness.c:1070-1114 and 1317-1321 (HT_ButtonPressed)."
)

# ===========================================================================
# 4. PC GUI Architecture
# ===========================================================================
doc.add_heading("4. PC GUI Architecture", level=1)

doc.add_heading("4.1 File Layout", level=2)
add_table(doc, ["File", "Contents"], [
    ["gui/main.py", "Entry point — creates the QApplication and MainWindow"],
    ["gui/core/data_types.py", "Cmd/Rsp enums, TestState/Verdict/TestType/ResultStatus enums, "
     "TestResult/ContResult/ScanSummary/FirmwareStatus/TestModes dataclasses"],
    ["gui/core/crc16.py", "CRC-16/CCITT-FALSE — the Python mirror of harness.c's crc16()"],
    ["gui/core/packet_codec.py", "encode_packet() and the PacketDecoder state machine — the Python mirror of decoder_feed()"],
    ["gui/core/serial_comm.py", "SerialWorker(QThread) — owns the serial port, TX queue, heartbeat, and typed Qt signals"],
    ["gui/core/test_engine.py", "TestEngine(QObject) — orchestrates upload/scan/verdict on the main thread"],
    ["gui/core/port_manager.py", "PortInfo/enumerate_ports()/PortScanner — COM port discovery and ranking"],
    ["gui/core/netlist.py", "Netlist/Net/NetPin dataclasses; JSON/Excel/CSV load and save; connector-config mapping"],
    ["gui/core/result_model.py", "ResultModel(QAbstractTableModel) backing the Results Table view"],
    ["gui/core/report.py", "ReportWorker(QObject) — background-thread PDF generation via reportlab"],
    ["gui/core/profile.py", "TestProfile dataclass — persisted operator/port/DUT-numbering settings"],
    ["gui/ui/main_window.py", "MainWindow(QMainWindow) — wires every panel and core object together (1129 lines)"],
    ["gui/ui/left_panel.py, test_control_bar.py, connector_view.py, matrix_view.py, "
     "results_table.py, log_panel.py, info_panel.py, netlist_editor.py, golden_sample.py",
     "Individual UI panels and dialogs — connection controls, wiring diagram, results grid, "
     "log console, firmware info, netlist editor, and the auto-scan-to-netlist wizard"],
    ["gui/ui/widgets/", "Small reusable widgets (Card, ModernButton, StatusBadge, GaugeProgress, "
     "VerdictLabel, IconButton, Toast) used across the panels above"],
])

doc.add_heading("4.2 Startup Call Hierarchy", level=2)
add_code_block(doc,
    "main()                                        [gui/main.py]\n"
    "  -> QApplication(sys.argv)\n"
    "  -> MainWindow()                              [gui/ui/main_window.py:44]\n"
    "     -> _setup_window()                        title, min size, taskbar icon\n"
    "     -> _build_menu_bar()                      File / View / Help menus\n"
    "     -> _build_central_widget()                LeftPanel, TestControlBar, ConnectorView,\n"
    "                                                ResultsTable, LogPanel, InfoPanel\n"
    "     -> _build_status_bar()                    company attribution + logo\n"
    "     -> _setup_shortcuts()                     F5/F6/F7\n"
    "     -> _wire_left_panel()                     connect LeftPanel/TestControlBar signals\n"
    "     -> _restore_geometry()                     -> _apply_theme() from saved settings\n"
    "  -> window.show()\n"
    "  -> app.exec()",
    caption="Call tree 4.1 — verified against gui/main.py:13-21 and MainWindow.__init__ "
            "(main_window.py:44-99)."
)

doc.add_heading("4.3 Function Reference — Core Objects", level=2)
add_table(doc, ["Class.Method", "Calls", "Purpose"], [
    ["TestEngine.start_test()", "_send_params, _begin_upload, _start_scanning", "Entry point for a netlist-driven continuity/cross-continuity run"],
    ["TestEngine.start_auto_test()", "_send_params, worker.send_packet(AUTO_SCAN)", "Entry point for a no-netlist discovery run"],
    ["TestEngine._begin_upload()", "netlist.load_netlist, netlist.netlist_to_bytes, _begin_upload_bytes", "Loads and serialises the netlist file"],
    ["TestEngine._begin_upload_bytes()", "worker.send_packet(SET_NETLIST) per chunk, _upload_timer.start", "Splits the netlist into <=250-byte chunks with a (seq,total) header"],
    ["TestEngine._on_scan_complete()", "_finalise", "Reacts to the worker's scanComplete signal; distinguishes auto vs. netlist-driven runs"],
    ["SerialWorker.run()", "serial.Serial, send_packet(GET_STATUS), decoder.feed, send_packet(PING)", "The QThread body — owns the actual pyserial port"],
    ["SerialWorker._on_packet()", "statusReceived/contResultReceived/scanComplete/progressUpdate/"
     "ackReceived/nackReceived/faultReceived.emit", "Decodes one complete frame into the matching typed Qt signal"],
    ["MainWindow._on_connect_requested()", "SerialWorker(), TestEngine(), (signal wiring), worker.start", "Creates and starts the worker/engine pair for one connection"],
    ["MainWindow._on_start_requested()", "engine.start_test / engine.start_auto_test", "Reads GUI state (mode, netlist) and kicks off TestEngine"],
    ["MainWindow._on_cont_result()", "_lookup_net_info, _display_pins, results_table.append_result, "
     "matrix_view.update_pin, engine.count_result", "Turns one ContResult signal into a TestResult row and a matrix-cell update"],
    ["MainWindow._on_verdict_ready()", "_expand_cross_continuity_not_connected, _auto_save_results, "
     "left_panel.increment_dut_id", "End-of-scan bookkeeping: completes the matrix, saves CSV, advances the DUT ID"],
    ["MainWindow._auto_save_results() / _write_results_csv()", "—", "Writes a timestamped CSV to gui/profiles/results/ after every scan"],
    ["MainWindow._on_export_pdf()", "report.run_pdf_worker", "Starts a background QThread that calls report.generate_pdf()"],
])

doc.add_heading("4.4 Runtime Call Hierarchy — Key Operations", level=2)

doc.add_paragraph("a) Connecting to the instrument:")
add_code_block(doc,
    "LeftPanel  (connectRequested signal)\n"
    "  -> MainWindow._on_connect_requested(port, baud)   [main_window.py:260]\n"
    "     -> SerialWorker(port, baud)                    constructed, not yet started\n"
    "     -> TestEngine(worker)                          wires worker.ackReceived / .nackReceived /\n"
    "                                                     .scanComplete / .connectionLost\n"
    "     -> (MainWindow wires 7 more worker signals + 4 engine signals)\n"
    "     -> worker.start()                               -> SerialWorker.run()  [new QThread]\n"
    "          -> serial.Serial(port, baud, timeout=0.1)\n"
    "          -> send_packet(Cmd.GET_STATUS)              first request after open\n"
    "          -> loop: TX queue drain, RX read+decode, 2s heartbeat (PING),\n"
    "                    disconnect after 3 missed ACKs",
    caption="Call tree 4.2 — verified against main_window.py:260-289 and serial_comm.py:68-131."
)

doc.add_paragraph(
    "b) Starting a netlist-driven test — the equivalent of the old documentation's "
    "“Primary Test Runner impact map”, re-traced against the current TestEngine:"
)
add_code_block(doc,
    "TestControlBar (startRequested)  or  F5 shortcut\n"
    "  -> MainWindow._on_start_requested()                [main_window.py:510]\n"
    "     -> engine.start_test(netlist_path, modes)        [test_engine.py:65]\n"
    "        -> _send_params()                             CMD_SET_PARAM (r_limit, ir_limit)\n"
    "        -> _begin_upload(path)\n"
    "           -> netlist.load_netlist(path), netlist.netlist_to_bytes(...)\n"
    "           -> _begin_upload_bytes(data)\n"
    "              -> CMD_SET_NETLIST per chunk (<=250 B, seq/total header)\n"
    "              -> _upload_timer.start(...)              fires once firmware should be done reassembling\n"
    "        -> [timer fires] _start_scanning()\n"
    "           -> CMD_START_CROSS_CONT  or  CMD_START_CONT (per modes.cross_continuity)\n"
    "\n"
    "        ... firmware streams RSP_RESULT_CONT / RSP_PROGRESS / RSP_SCAN_DONE ...\n"
    "\n"
    "SerialWorker._on_packet(RSP_RESULT_CONT)\n"
    "  -> contResultReceived.emit(ContResult)\n"
    "     -> MainWindow._on_cont_result()                  [main_window.py:657]\n"
    "        -> _lookup_net_info(), _display_pins()\n"
    "        -> results_table.append_result(TestResult)\n"
    "        -> matrix_view.update_pin(pin_a, pin_b, PASS/FAIL)\n"
    "        -> engine.count_result(status)\n"
    "\n"
    "SerialWorker._on_packet(RSP_SCAN_DONE)\n"
    "  -> scanComplete.emit(ScanSummary)\n"
    "     -> TestEngine._on_scan_complete() -> _finalise()\n"
    "        -> verdictReady.emit(Verdict.PASS/FAIL)\n"
    "           -> MainWindow._on_verdict_ready()          [main_window.py:707]\n"
    "              -> _expand_cross_continuity_not_connected()  [cross-continuity only]\n"
    "              -> _auto_save_results()                 writes CSV to profiles/results/\n"
    "              -> left_panel.increment_dut_id()",
    caption="Call tree 4.3 — verified against test_engine.py:65-169, serial_comm.py:137-183, "
            "and main_window.py:510-569, 657-738."
)

# ===========================================================================
# 5. Communication Protocol
# ===========================================================================
doc.add_heading("5. Communication Protocol", level=1)
doc.add_paragraph(
    "USART3 on the Nucleo board, bridged to a virtual COM port by the on-board ST-Link, "
    "at 115200 baud / 8N1 (firmware/Core/Src/main.c:226; matched on the GUI side by "
    "gui/core/profile.py's default baud=115200). Every frame — in both directions — uses "
    "the same layout, and the same CRC routine runs independently in harness.c (crc16()) "
    "and gui/core/crc16.py (crc16_ccitt_false()); the two must never diverge."
)
add_table(doc, ["Field", "Size", "Notes"], [
    ["SOF", "1 B", "Always 0x AA"],
    ["LEN", "1 B", "Payload length, 0-255"],
    ["CMD", "1 B", "Command (PC->MCU) or response (MCU->PC) ID"],
    ["PAYLOAD", "LEN B", "Command/response-specific data, big-endian multi-byte fields"],
    ["CRC_HI, CRC_LO", "2 B", "CRC-16/CCITT-FALSE over CMD+PAYLOAD only (not SOF, not LEN)"],
])

doc.add_heading("5.1 Commands (PC -> MCU)", level=2)
add_table(doc, ["Value", "Name", "Sent by current GUI?"], [
    ["0x01", "CMD_PING", "Yes — SerialWorker heartbeat, every 2 s"],
    ["0x02", "CMD_GET_STATUS", "Yes — once on connect, and on demand (Info panel Refresh)"],
    ["0x03", "CMD_SET_NETLIST", "Yes — chunked netlist upload"],
    ["0x04", "CMD_SET_PARAM", "Yes — r_limit/ir_limit, sent before every test"],
    ["0x05", "CMD_START_CONT", "Yes — continuity mode"],
    ["0x06", "CMD_START_SHORT", "No — see Known Limitations §7"],
    ["0x07", "CMD_START_HV", "No — see Known Limitations §7"],
    ["0x08", "CMD_ABORT", "Yes — Stop button / F6"],
    ["0x09", "CMD_CALIBRATE", "Yes — F7 / Calibrate action"],
    ["0x0A", "CMD_GET_RESULT", "No — firmware implements it (returns current STATUS) but the GUI never sends it; results arrive as streamed RESULT_CONT during a scan instead"],
    ["0x0B", "CMD_AUTO_SCAN", "Yes — Auto-Scan mode, and the on-board user button"],
    ["0x0C", "CMD_START_CROSS_CONT", "Yes — cross-continuity mode"],
])

doc.add_heading("5.2 Responses (MCU -> PC)", level=2)
add_table(doc, ["Value", "Name", "Payload", "Parsed by current GUI?"], [
    ["0x81", "RSP_ACK", "0 or 2 B (calibration offset)", "Yes"],
    ["0x82", "RSP_NACK", "0 B", "Yes"],
    ["0x83", "RSP_STATUS", "state(1) flags(1) major(1) minor(1) patch(1) cal_hi(1) cal_lo(1) pad(1)", "Yes"],
    ["0x84", "RSP_RESULT_CONT", "pin_a(1) pin_b(1) res_raw(4, mOhm x10) status(1)", "Yes"],
    ["0x85", "RSP_RESULT_SHORT", "pin_a(1) pin_b(1) is_short(1)", "No — no case in SerialWorker._on_packet(); see §7"],
    ["0x86", "RSP_RESULT_HV", "pin_a(1) pin_b(1) ir_raw(4) hv_raw(2) fail(1)", "No — no case in SerialWorker._on_packet(); see §7"],
    ["0x87", "RSP_SCAN_DONE", "total(2) passed(2) failed(2)", "Yes"],
    ["0x88", "RSP_PROGRESS", "done(2) total(2)", "Yes"],
    ["0x89", "RSP_FAULT", "code(1) data(4)", "Yes — only code 0x01 (FAULT_STUCK_PINS) is ever sent by firmware"],
])

doc.add_heading("5.3 RESULT_CONT status byte", level=2)
add_table(doc, ["Value", "Firmware meaning", "GUI ResultStatus"], [
    ["0", "PASS", "PASS"],
    ["1", "OPEN (expected connection missing)", "OPEN — SerialWorker also treats any status-0 result whose resistance is >=10 kOhm as OPEN (a legacy sentinel from before status byte 1 existed)"],
    ["2", "MISWIRE (unexpected connection present)", "MISWIRE"],
    ["3", "NOT_CONNECTED (cross-continuity: none expected, none found)", "NOT_CONNECTED"],
])

# ===========================================================================
# 6. Key Design Decisions
# ===========================================================================
doc.add_heading("6. Key Design Decisions", level=1)

doc.add_heading("6.1 Binary framed protocol, not text", level=2)
doc.add_paragraph(
    "The protocol is a compact binary frame with a CRC, not a line-oriented text protocol. "
    "This keeps a 37x37 scan's worth of results (up to 1369 RESULT_CONT packets) small and "
    "fast at 115200 baud, and the CRC catches the line noise a jumper-wire harness setup "
    "is prone to. The cost is that the same UART also carries free-form ASCII debug text "
    "from harness.c's dbg()/dbg_num() helpers (e.g. the per-pin scan trace in "
    "run_continuity_scan(), harness.c:849-858). This works only because no debug string "
    "ever contains the byte 0xAA — the decoder simply skips any byte that is not a valid "
    "SOF while in its wait-for-SOF state, so debug text passes through unnoticed until the "
    "next real frame. A future debug string that happens to include 0xAA would not corrupt "
    "framing (the decoder would just misinterpret it as a spurious SOF and resync on the "
    "following bytes), but it is a fragile assumption worth knowing about before adding new "
    "debug output."
)

doc.add_heading("6.2 Chunked netlist upload", level=2)
doc.add_paragraph(
    "MAX_PAYLOAD_LEN is 255 bytes (harness.h), so a netlist's JSON — up to 4096 bytes "
    "(MAX_NL_BYTES) — cannot fit in one packet. The GUI splits it into <=250-byte chunks, "
    "each carrying a (seq, total) header; the firmware's nl_buf reassembles them in "
    "handle_set_netlist() and only calls nl_parse_json() once nl_chunks_got reaches "
    "nl_total_chunks. TestEngine._begin_upload_bytes() sizes its post-upload timer as "
    "max(200, 50*total) ms — a fixed guess at reassembly time rather than a firmware "
    "acknowledgement of “parse complete,” since CMD_SET_NETLIST replies with a plain ACK "
    "per chunk, not a final one."
)

doc.add_heading("6.3 Trace-pad reclaim on every scan, not just at boot", level=2)
doc.add_paragraph(
    "release_trace_pins() runs once in HT_Init(), and again at the top of every one of the "
    "five run_*_scan() functions. DBGMCU_CR.TRACE_IOEN survives a warm reset — only a "
    "power-on reset clears it — so a debugger attached with tracing enabled after the "
    "board last powered up can silently steal PE2-PE6 and PB3 back from the harness at any "
    "time. Reclaiming them before every scan, not only at startup, is what makes the STATUS "
    "flags byte (and the GUI's warning in _on_status_received()) a reliable signal rather "
    "than a one-time boot check."
)

doc.add_heading("6.4 Baseline stuck-pin check before every scan", level=2)
doc.add_paragraph(
    "baseline_check() drives every Side-A pin LOW and asserts that every Side-B pin reads "
    "LOW too. A pin that does not — shorted to a rail, floating with its pull-down "
    "defeated, or still owned by another peripheral — would otherwise read HIGH no matter "
    "which Side-A pin is driven, silently fabricating a PASS connection to all 37 A pins "
    "while the rest of the scan reports a clean run. Running this check first turns that "
    "silent wrong answer into an explicit RSP_FAULT(FAULT_STUCK_PINS), which MainWindow "
    "surfaces as a persistent status-bar message (main_window.py:826-843) rather than a "
    "log line that could be missed."
)

doc.add_heading("6.5 Port ranking instead of first-available", level=2)
doc.add_paragraph(
    "port_manager.PortInfo.rank scores known USB-serial bridge descriptions (ST-Link, "
    "CH340, CP210, FTDI) ahead of everything else, and explicitly demotes Bluetooth/BthModem "
    "ports. Plain OS enumeration order would put legacy ports like COM1 first; COM1 opens "
    "successfully and simply never answers, so the connection would only fail eight seconds "
    "later on a missed-heartbeat timeout. Ranking lets the GUI default to the right port "
    "immediately in the common case of one instrument attached."
)

doc.add_heading("6.6 Reconnect only a port that has proven itself", level=2)
doc.add_paragraph(
    "MainWindow._on_connection_lost() only auto-retries a port name that has returned a "
    "valid RSP_STATUS at least once this session (_validated_port). A port that never "
    "answered even once — a stale COM1, a Bluetooth RFCOMM node — will not start answering "
    "on retry, so five 8-second reconnect attempts against it would just look like a hung "
    "application. A port that worked and then dropped mid-session is exactly the case "
    "reconnection exists for, and still gets its retries."
)

# ===========================================================================
# 7. Known Limitations
# ===========================================================================
doc.add_heading("7. Known Limitations", level=1)
add_warning_box(doc,
    "This section lists what is intentionally out of scope for the MK0 proof of concept, "
    "what is implemented in one half of the system but not reachable from the other, and "
    "one latent code defect. None of these are hidden — they are stated here so the next "
    "engineer does not have to rediscover them.",
    label="IMPORTANT"
)

doc.add_heading("7.1 Short-circuit and HV insulation testing are unreachable from the GUI", level=2)
doc.add_paragraph(
    "run_short_scan() and run_hv_scan() are fully implemented in harness.c and reachable "
    "via CMD_START_SHORT (0x06) and CMD_START_HV (0x07). But gui/core/data_types.py's Cmd "
    "enum defines neither value, TestModes has no field to request either mode, and "
    "TestEngine never constructs either command. Even if a command were added, "
    "SerialWorker._on_packet() (serial_comm.py:137-183) has no case for RSP_RESULT_SHORT "
    "(0x85) or RSP_RESULT_HV (0x86) — those packets would arrive, pass CRC, and be silently "
    "dropped by the decoder's if/elif chain. Wiring these up is a GUI-side change only; the "
    "firmware side needs no modification for continuity/cross-continuity/auto-scan use."
)

doc.add_heading("7.2 HV insulation results are simulated, not measured", level=2)
doc.add_paragraph(
    "run_hv_scan() reports a fixed IR of 10 000 MOhm and 500.0 V for every pair "
    "(harness.c:1039-1041) regardless of the actual harness. This is expected for MK0: the "
    "Nucleo board has no HV generation or leakage-current measurement hardware. This is a "
    "protocol/workflow placeholder for the MK-I production design, not a bug."
)

doc.add_heading("7.3 Continuity resistance values are simulated constants", level=2)
doc.add_paragraph(
    "run_continuity_scan() reports 50 mOhm for a connected pair and 50 000 mOhm for an open "
    "one (harness.c:862-864) — a fixed placeholder, not a measurement. MK0 has no "
    "current-source/InAmp/ADC front end; only the digital PASS/OPEN verdict is real."
)

doc.add_heading("7.4 IWDG is compiled out", level=2)
doc.add_paragraph(
    "iwdg_init() and iwdg_refresh() are both empty function bodies (harness.c:636-637). "
    "The inline comment explains why: on this board, polling the IWDG status register "
    "hangs because LSI oscillator sync takes longer than expected, and starting the "
    "watchdog without a confirmed register update causes spurious resets every ~0.41 s with "
    "the default prescaler/reload. There is no watchdog protection in this build — a "
    "firmware hang requires a physical power-cycle to recover from."
)

doc.add_heading("7.5 FAULT_HV_INTERLOCK collides with FAULT_STUCK_PINS", level=2)
doc.add_paragraph(
    "harness.h defines FAULT_STUCK_PINS as 0x01 (used by baseline_check(), the only fault "
    "code the firmware ever actually sends) and, separately, FAULT_HV_INTERLOCK also as "
    "0x01 alongside FAULT_WATCHDOG (0x07) — neither of the latter two is referenced "
    "anywhere in harness.c today. There is no runtime ambiguity yet because only "
    "FAULT_STUCK_PINS is ever transmitted, but the numeric collision must be resolved "
    "(renumber one of them) before HV-interlock or watchdog fault reporting is implemented, "
    "or MainWindow._on_fault_received() will misattribute one fault as the other."
)

doc.add_heading("7.6 TPIU trace-port pins can still be stolen mid-scan", level=2)
doc.add_paragraph(
    "release_trace_pins() runs at the start of every scan (§6.3), but a debugger that "
    "attaches with tracing enabled after a scan has already started can still re-set "
    "DBGMCU_CR.TRACE_IOEN for the remainder of that scan. The five affected Side-B pins "
    "(B20/B22/B23/B24/B31 = PE2-PE6) and Side-A pin 18 (PB3) would then read stuck HIGH "
    "for whatever's left of that run, indistinguishable from a real connection until the "
    "next scan's baseline_check(). In practice this only matters if a debug session is "
    "opened during production testing, which the User Manual instructs against."
)

# ===========================================================================
# 8. System Reference
# ===========================================================================
doc.add_heading("8. System Reference", level=1)

doc.add_heading("8.1 Side-A / Side-B Pin Map", level=2)
doc.add_paragraph(
    "37 pins per side, connected to the harness under test via the Nucleo's Morpho "
    "headers (CN8/CN9/CN10/CN11). Side A pins are push-pull outputs, initialised LOW; "
    "Side B pins are inputs with an internal pull-down. Source: firmware/Core/Src/harness.c:349-389."
)
add_table(doc, ["Pin #", "Side A (output)", "Side B (input)", "Notes"], [
    ["1",  "PC9",  "PC10", ""],
    ["2",  "PC8",  "PC11", ""],
    ["3",  "PB8",  "PC12", ""],
    ["4",  "PC6",  "PD2",  ""],
    ["5",  "PA5",  "PF6",  ""],
    ["6",  "PA12", "PF7",  "A6=PA12 is also USB_DP"],
    ["7",  "PA6",  "PA15", "B7=PA15 is also JTDI"],
    ["8",  "PA11", "PA0",  "A8=PA11 is also USB_DM"],
    ["9",  "PA7",  "PA1",  ""],
    ["10", "PB12", "PC1",  ""],
    ["11", "PB6",  "PC2",  ""],
    ["12", "PB11", "PC0",  ""],
    ["13", "PA9",  "PC3",  ""],
    ["14", "PB2",  "PD3",  "A14=PB2 is also BOOT1"],
    ["15", "PB10", "PD4",  ""],
    ["16", "PB15", "PG2",  ""],
    ["17", "PB13", "PD5",  ""],
    ["18", "PB3",  "PG3",  "A18=PB3 is SYS_JTDO-TRACESWO — released by release_trace_pins()"],
    ["19", "PA10", "PD6",  ""],
    ["20", "PC4",  "PE2",  "B20=PE2 is TPIU TRACECLK — see §6.3/7.6"],
    ["21", "PA2",  "PD7",  ""],
    ["22", "PF5",  "PE4",  "B22=PE4 is TPIU TRACED1 — see §6.3/7.6"],
    ["23", "PA3",  "PE3",  "B23=PE3 is TPIU TRACED0 — see §6.3/7.6"],
    ["24", "PF4",  "PE5",  "B24=PE5 is TPIU TRACED2 — see §6.3/7.6"],
    ["25", "PE7",  "PF2",  ""],
    ["26", "PD11", "PF8",  ""],
    ["27", "PD14", "PF9",  ""],
    ["28", "PE10", "PD1",  ""],
    ["29", "PD15", "PG1",  ""],
    ["30", "PE12", "PD0",  ""],
    ["31", "PF14", "PE6",  "B31=PE6 is TPIU TRACED3 — see §6.3/7.6"],
    ["32", "PE14", "PG15", ""],
    ["33", "PE9",  "PG9",  ""],
    ["34", "PE15", "PG10", ""],
    ["35", "PE13", "PG12", ""],
    ["36", "PE11", "PG13", ""],
    ["37", "PG6",  "PG11", "A37=PG6 is also USB_PowerSwitchOn"],
])

doc.add_heading("8.2 Reserved Pins (not part of the 37+37 harness map)", level=2)
add_table(doc, ["Pin", "Function", "Notes"], [
    ["PB0", "LD1 (green LED)", "—"],
    ["PB7", "LD2 (blue LED)", "—"],
    ["PB14", "LD3 (red LED)", "—"],
    ["PC13", "USER button B1", "EXTI15_10, active-low, rising edge triggers auto-scan"],
    ["PD8 / PD9", "USART3 TX / RX", "115200 baud, 8N1, bridged to USB by the on-board ST-Link"],
    ["PA13 / PA14", "SWDIO / SWCLK", "Programming/debug interface — always reserved"],
])

doc.add_heading("8.3 Peripheral Configuration", level=2)
add_table(doc, ["Peripheral", "Setting"], [
    ["USART3", "115200 baud, 8 data bits, no parity, 1 stop bit, no flow control (main.c:226-238)"],
    ["USART3 NVIC priority", "1 (main.c:100)"],
    ["EXTI15_10 NVIC priority", "2 (main.c:104) — lower priority than USART3, so a button press cannot delay byte reception"],
    ["RTC", "Initialised via MX_RTC_Init() (LSI clock source) but not read or written anywhere in harness.c — CubeMX-generated, unused by the harness feature set"],
    ["IWDG", "Disabled — see §7.4"],
])

doc.add_heading("8.4 LED Patterns", level=2)
add_table(doc, ["State", "Pattern"], [
    ["Boot", "All three LEDs blink together, 3x (200 ms per phase)"],
    ["Idle / Ready", "LD1 (green) solid"],
    ["Scanning / HV testing / Uploading", "LD2 (blue) slow blink, 250 ms"],
    ["Calibrating", "LD2 (blue) fast blink, 100 ms"],
    ["Fault", "LD3 (red) fast blink, 100 ms"],
    ["Complete", "Two fast blinks — green if last scan passed, red if it failed — then returns to Idle"],
])

doc.add_heading("8.5 Version Identifiers", level=2)
add_table(doc, ["Component", "Value", "Source"], [
    ["Firmware version", "2.2.0", "firmware/Core/Inc/harness.h — FW_MAJOR/MINOR/PATCH"],
    ["GUI application version", "2.0.0", "gui/version.py — APP_VERSION"],
    ["Protocol version", "1.0", "gui/version.py — PROTOCOL_VERSION"],
])

# ===========================================================================
# 9. Glossary
# ===========================================================================
doc.add_heading("9. Glossary", level=1)
add_table(doc, ["Term", "Definition"], [
    ["DUT", "Device Under Test — the wire harness being tested"],
    ["Netlist", "A file (JSON/Excel/CSV) describing the expected wiring: which Side-A pins should connect to which Side-B pins"],
    ["Continuity", "A test verifying that an expected connection is present"],
    ["Cross-continuity", "A full N x N sweep reporting PASS/OPEN/MISWIRE/NOT_CONNECTED for every pin pair, not just netlist pairs"],
    ["Auto-Scan", "A no-netlist discovery scan (CMD_AUTO_SCAN) that reports every connection it finds"],
    ["MISWIRE", "An unexpected connection present where the netlist expects none"],
    ["OPEN", "An expected connection that is missing"],
    ["SOF", "Start of Frame — the fixed 0xAA byte marking the start of every protocol packet"],
    ["CRC", "Cyclic Redundancy Check — CRC-16/CCITT-FALSE, covers CMD+PAYLOAD in every frame"],
    ["IWDG", "Independent Watchdog — disabled in this build (§7.4)"],
    ["TPIU", "Trace Port Interface Unit — the Cortex-M4 debug hardware block that can claim PE2-PE6 and PB3 for trace output"],
    ["DBGMCU_CR.TRACE_IOEN", "The register bit that, when set by a debugger, hands the TPIU pins to the trace block instead of GPIO"],
    ["EXTI", "External Interrupt — the STM32 peripheral servicing the user button on PC13"],
    ["HAL", "STM32 Hardware Abstraction Layer — the CubeMX-generated driver layer under harness.c"],
    ["VCP", "Virtual COM Port — the USB-serial bridge the on-board ST-Link exposes to Windows"],
    ["ST-Link", "The programming/debug + VCP bridge built into the Nucleo board"],
    ["Morpho header", "The Nucleo board's extended GPIO header set, used here to jumper the harness under test"],
])

build_footer(doc, sec, company=COMPANY, client=CLIENT)
save(doc, OUTPUT_PATH)
