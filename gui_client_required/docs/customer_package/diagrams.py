# -*- coding: utf-8 -*-
"""Draw the figures used in the customer-package documents (matplotlib).

Every figure is drawn 6.27 in wide (the 15.92 cm text width) so the lettering
is printed at the size it is drawn: 9 pt and up.
"""
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt                      # noqa: E402
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Rectangle  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "diagrams")
os.makedirs(OUT, exist_ok=True)

plt.rcParams["font.family"] = "Times New Roman"
W = 6.27
NAVY, BLUE, LBLUE = "#1F3864", "#1F4E79", "#DCE8F4"
GREY, LGREY = "#7F7F7F", "#F2F2F2"
GREEN, LGREEN = "#2E8B3E", "#D5EBD0"
RED, LRED = "#C0392B", "#F8D7D3"
AMBER, LAMBER = "#B7791F", "#FBE9C8"


def canvas(h):
    fig = plt.figure(figsize=(W, h), dpi=220)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, W)
    ax.set_ylim(0, h)
    ax.axis("off")
    return fig, ax


def box(ax, x, y, w, h, text, fc=LBLUE, ec=BLUE, fs=9.5, bold=False, tc="black", lw=1.2, r=0.06):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle=f"round,pad=0,rounding_size={r}",
                                fc=fc, ec=ec, lw=lw))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=fs,
            fontweight="bold" if bold else "normal", color=tc, linespacing=1.15)


def arrow(ax, p0, p1, text="", fs=8.5, both=False, color=NAVY, lw=1.3, off=(0, 0.07), ha="center"):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="<|-|>" if both else "-|>",
                                 mutation_scale=11, lw=lw, color=color, shrinkA=0, shrinkB=0))
    if text:
        ax.text((p0[0] + p1[0]) / 2 + off[0], (p0[1] + p1[1]) / 2 + off[1], text,
                ha=ha, va="bottom", fontsize=fs, color=color)


def save(fig, name):
    fig.savefig(os.path.join(OUT, name), dpi=220)
    plt.close(fig)
    print("drew", name)


# ── 1. System block diagram ────────────────────────────────────────────────────────────
def system_block():
    fig, ax = canvas(2.9)
    ax.text(W / 2, 2.72, "HT_MK0 system", ha="center", fontsize=10.5, fontweight="bold", color=NAVY)
    box(ax, 0.05, 1.05, 1.3, 1.35, "PC\nHarness Tester\nGUI\n(Windows)", fc=LBLUE)
    box(ax, 2.15, 1.05, 1.5, 1.35, "Nucleo-F303ZE\nST-Link + firmware\nSTM32F303ZE", fc=LGREEN, ec=GREEN)
    box(ax, 4.45, 1.05, 0.95, 1.35, "Harness\nunder test\n(DUT)", fc=LAMBER, ec=AMBER)
    box(ax, 5.55, 1.05, 0.65, 1.35, "J1\nJ2\nJ3", fc=LGREY, ec=GREY, fs=9)
    arrow(ax, (1.35, 1.72), (2.15, 1.72), "", both=True)
    ax.text(1.75, 1.84, "USB", ha="center", fontsize=8.6, color=NAVY)
    ax.text(1.75, 1.45, "115200 baud", ha="center", fontsize=8.0, color=NAVY)
    arrow(ax, (3.65, 2.12), (4.45, 2.12), "")
    ax.text(4.05, 2.2, "Side A", ha="center", fontsize=8.4, color=NAVY)
    arrow(ax, (4.45, 1.32), (3.65, 1.32), "")
    ax.text(4.05, 1.4, "Side B", ha="center", fontsize=8.4, color=NAVY)
    arrow(ax, (5.4, 1.72), (5.55, 1.72), "", both=True)
    ax.text(0.7, 0.72, "netlist, connector config,\nresults, reports", ha="center", fontsize=8.5, color=GREY)
    ax.text(2.9, 0.72, "drives Side A, reads Side B,\nreports every pair", ha="center", fontsize=8.5, color=GREY)
    ax.text(4.92, 0.72, "37 wires\nto be checked", ha="center", fontsize=8.5, color=GREY)
    ax.text(5.88, 0.72, "connectors", ha="center", fontsize=8.5, color=GREY)
    save(fig, "system_block.png")


# ── 2. Measurement principle ────────────────────────────────────────────────────────────
def principle():
    fig, ax = canvas(3.2)
    ax.text(W / 2, 3.0, "Continuity test principle", ha="center", fontsize=10.5, fontweight="bold", color=NAVY)
    xa, xb = 1.35, 3.85
    ax.text(xa - 0.2, 2.68, "Side A (outputs)", ha="right", fontsize=9.5, fontweight="bold")
    ax.text(xb + 0.2, 2.68, "Side B (inputs)", ha="left", fontsize=9.5, fontweight="bold")
    ys = [2.2, 1.7, 1.2, 0.7]
    labs = {1: "LOW: not wired", 2: "HIGH: wire present", 3: "LOW: wire missing", 4: "LOW: not wired"}
    for i, y in enumerate(ys, 1):
        hi = i == 2
        ax.add_patch(plt.Circle((xa, y), 0.09, fc=GREEN if hi else GREY, ec="black", lw=0.8))
        ax.text(xa - 0.2, y, f"A{i}  " + ("HIGH" if hi else "LOW"), ha="right", va="center", fontsize=9)
        ax.add_patch(plt.Circle((xb, y), 0.09, fc=GREEN if i == 2 else (RED if i == 3 else GREY),
                                ec="black", lw=0.8))
        ax.text(xb + 0.2, y, f"B{i}  reads {labs[i]}", ha="left", va="center", fontsize=9)
    ax.plot([xa, xb], [ys[1], ys[1]], color=GREEN, lw=2.2)
    ax.plot([xa, xb], [ys[0], ys[0]], color=GREY, lw=1.0, ls=":")
    ax.plot([xa, xb], [ys[3], ys[3]], color=GREY, lw=1.0, ls=":")
    ax.plot([xa, xb - 1.0], [ys[2], ys[2]], color=RED, lw=1.4)
    ax.text(xb - 0.5, ys[2] + 0.05, "break", ha="center", fontsize=8.5, color=RED)
    ax.text(W / 2, 0.22, "The firmware drives one Side-A pin at a time and reads every Side-B pin.",
            ha="center", fontsize=9, color=GREY)
    save(fig, "principle.png")


# ── 3. Hardware connection ───────────────────────────────────────────────────────────────
def hardware():
    fig, ax = canvas(3.5)
    ax.text(W / 2, 3.32, "Connecting the system", ha="center", fontsize=10.5, fontweight="bold", color=NAVY)
    box(ax, 0.1, 1.45, 1.1, 1.1, "PC\nUSB-A port", fc=LBLUE)
    ax.plot([1.2, 2.0], [2.0, 2.0], color=NAVY, lw=3)
    ax.text(1.6, 2.08, "USB cable", ha="center", fontsize=8.5)
    ax.add_patch(Rectangle((2.0, 0.5), 2.7, 2.5, fc=LGREEN, ec=GREEN, lw=1.5))
    ax.text(3.35, 2.82, "NUCLEO-F303ZE", ha="center", fontsize=9.5, fontweight="bold", color=GREEN)
    box(ax, 2.0, 1.78, 0.5, 0.45, "CN1\nUSB", fc="white", ec=NAVY, fs=8)
    for i, (c, n) in enumerate(((GREEN, "LD1"), ("#3B6FD6", "LD2"), (RED, "LD3"))):
        ax.add_patch(plt.Circle((3.0 + i * 0.5, 2.42), 0.1, fc=c, ec="black", lw=0.8))
        ax.text(3.0 + i * 0.5, 2.18, n, ha="center", fontsize=8)
    box(ax, 3.1, 1.1, 0.7, 0.45, "B1\nbutton", fc="#3B6FD6", ec=NAVY, fs=8, tc="white")
    box(ax, 2.2, 0.6, 2.3, 0.35, "Morpho headers: Side A / Side B", fc="white", ec=GREEN, fs=8)
    box(ax, 5.0, 2.0, 1.15, 0.75, "Side A\nJ1  J2  J3", fc=LAMBER, ec=AMBER, fs=8.5)
    box(ax, 5.0, 0.95, 1.15, 0.75, "Side B\nJ1  J2  J3", fc=LAMBER, ec=AMBER, fs=8.5)
    ax.plot([4.7, 5.0], [0.78, 1.3], color=NAVY, lw=1.4)
    ax.plot([4.7, 5.0], [0.78, 2.35], color=NAVY, lw=1.4)
    ax.text(5.58, 0.55, "harness under test\nplugs in here", ha="center", fontsize=8.5, color=GREY)
    save(fig, "hardware.png")


# ── 4. LED patterns ────────────────────────────────────────────────────────────────────────
def led_patterns():
    fig, ax = canvas(2.95)
    ax.text(W / 2, 2.78, "LED patterns", ha="center", fontsize=10.5, fontweight="bold", color=NAVY)
    rows = [
        ("Power-on", "all three blink together 3 times", [(0, .2, "A"), (.4, .6, "A"), (.8, 1.0, "A")]),
        ("Idle / ready", "LD1 green, steady", [(0, 1.2, "G")]),
        ("Scanning", "LD2 blue, slow blink (250 ms)", [(0, .25, "B"), (.5, .75, "B"), (1.0, 1.25, "B")]),
        ("Calibrating", "LD2 blue, fast blink (100 ms)", [(0, .1, "B"), (.2, .3, "B"), (.4, .5, "B"), (.6, .7, "B"), (.8, .9, "B")]),
        ("Test PASS", "LD1 green, 2 short blinks", [(0, .1, "G"), (.2, .3, "G")]),
        ("Test FAIL", "LD3 red, 2 short blinks", [(0, .1, "R"), (.2, .3, "R")]),
    ]
    col = {"G": GREEN, "B": "#3B6FD6", "R": RED, "A": "#555555"}
    y = 2.45
    for name, desc, bars in rows:
        ax.text(0.05, y, name, fontsize=9, fontweight="bold", va="center")
        ax.text(1.15, y, desc, fontsize=8.6, va="center")
        for a, b, c in bars:
            ax.add_patch(Rectangle((4.2 + a * 1.4, y - 0.1), (b - a) * 1.4, 0.2, fc=col[c], ec="none"))
        ax.plot([4.2, 4.2 + 1.2 * 1.4], [y - 0.14, y - 0.14], color="#CCCCCC", lw=0.6)
        y -= 0.4
    save(fig, "led_patterns.png")


# ── 5. Flashing flow ─────────────────────────────────────────────────────────────────────────
def flash_flow():
    fig, ax = canvas(3.0)
    ax.text(W / 2, 2.82, "Flashing procedure at a glance", ha="center", fontsize=10.5, fontweight="bold", color=NAVY)
    steps = ["Install\nST-Link driver\nand programmer", "Connect board\nto CN1", "Open the\n.elf file",
             "Erase and\nprogram", "Verify and\npower-cycle", "Check LED\nboot pattern"]
    bw, gap = 0.84, 0.17
    x = 0.12
    for i, s in enumerate(steps):
        box(ax, x, 1.2, bw, 1.2, s, fc=LBLUE if i < 5 else LGREEN, ec=BLUE if i < 5 else GREEN, fs=8.6)
        ax.text(x + bw / 2, 2.55, str(i + 1), ha="center", fontsize=9, fontweight="bold", color=NAVY)
        if i < len(steps) - 1:
            arrow(ax, (x + bw, 1.8), (x + bw + gap, 1.8))
        x += bw + gap
    ax.text(W / 2, 0.75, "If the connection fails: Refresh the port list, close any debug session,\n"
            "then unplug and replug the USB cable.", ha="center", fontsize=9, color=GREY)
    save(fig, "flash_flow.png")


# ── 6. Software architecture ──────────────────────────────────────────────────────────────────
def architecture():
    fig, ax = canvas(4.4)
    ax.text(W / 2, 4.22, "Software architecture", ha="center", fontsize=10.5, fontweight="bold", color=NAVY)
    # GUI
    ax.add_patch(Rectangle((0.08, 0.55), 3.55, 3.45, fc="#F7FAFD", ec=BLUE, lw=1.3))
    ax.text(1.85, 3.82, "PC: Harness Tester GUI (Python, PyQt6)", ha="center", fontsize=9.3, fontweight="bold", color=BLUE)
    box(ax, 0.25, 3.0, 3.2, 0.55, "ui: MainWindow, left panel, toolbar, tabs", fs=8.6)
    box(ax, 0.25, 2.25, 1.5, 0.55, "core.test_engine\nstate machine", fs=8.4)
    box(ax, 1.95, 2.25, 1.5, 0.55, "core.serial_comm\nworker thread", fs=8.4)
    box(ax, 0.25, 1.5, 1.5, 0.55, "core.netlist\ncore.pinmap", fs=8.4, fc=LGREY, ec=GREY)
    box(ax, 1.95, 1.5, 1.5, 0.55, "core.packet_codec\ncore.crc16", fs=8.4, fc=LGREY, ec=GREY)
    box(ax, 0.25, 0.7, 1.5, 0.55, "core.result_model\ncore.report", fs=8.4, fc=LGREY, ec=GREY)
    box(ax, 1.95, 0.7, 1.5, 0.55, "core.paths\ncore.profile", fs=8.4, fc=LGREY, ec=GREY)
    arrow(ax, (1.0, 3.0), (1.0, 2.8)); arrow(ax, (2.7, 3.0), (2.7, 2.8))
    arrow(ax, (1.75, 2.52), (1.95, 2.52), both=True)
    arrow(ax, (2.7, 2.25), (2.7, 2.05))
    # link
    arrow(ax, (3.63, 2.52), (4.2, 2.52), "UART\nvia USB", both=True, fs=8.2, off=(0, 0.06))
    # firmware
    ax.add_patch(Rectangle((4.2, 0.55), 1.99, 3.45, fc="#F4FAF2", ec=GREEN, lw=1.3))
    ax.text(5.2, 3.82, "Nucleo-F303ZE firmware (C)", ha="center", fontsize=9.3, fontweight="bold", color=GREEN)
    box(ax, 4.33, 3.0, 1.73, 0.55, "main.c\nclock, UART, GPIO", fs=8.4, fc=LGREEN, ec=GREEN)
    box(ax, 4.33, 2.25, 1.73, 0.55, "harness.c\npacket decoder,\ncommands", fs=8.2, fc=LGREEN, ec=GREEN)
    box(ax, 4.33, 1.5, 1.73, 0.55, "scan routines\ncontinuity, cross,\nauto-scan", fs=8.2, fc=LGREEN, ec=GREEN)
    box(ax, 4.33, 0.7, 1.73, 0.55, "37 + 37 GPIO pins\nLEDs, button", fs=8.4, fc=LGREY, ec=GREY)
    arrow(ax, (5.2, 3.0), (5.2, 2.8)); arrow(ax, (5.2, 2.25), (5.2, 2.05)); arrow(ax, (5.2, 1.5), (5.2, 1.25))
    ax.text(W / 2, 0.22, "Files on the PC side: netlist (.json, .xlsx, .csv) and connector_config.xlsx",
            ha="center", fontsize=8.8, color=GREY)
    save(fig, "architecture.png")


# ── 7. Packet frame ────────────────────────────────────────────────────────────────────────────
def packet_frame():
    fig, ax = canvas(2.1)
    ax.text(W / 2, 1.92, "Serial packet frame", ha="center", fontsize=10.5, fontweight="bold", color=NAVY)
    fields = [("SOF", "0xAA", 0.75, LBLUE), ("LEN", "n (0..255)", 1.05, LBLUE), ("CMD", "command or\nresponse", 1.1, LBLUE),
              ("PAYLOAD", "n bytes", 1.6, LAMBER), ("CRC_HI", "", 0.85, LGREEN), ("CRC_LO", "", 0.85, LGREEN)]
    x = 0.07
    for name, sub, w, c in fields:
        ax.add_patch(Rectangle((x, 0.85), w, 0.7, fc=c, ec=NAVY, lw=1.2))
        ax.text(x + w / 2, 1.3, name, ha="center", fontsize=9.5, fontweight="bold")
        ax.text(x + w / 2, 1.03, sub, ha="center", va="center", fontsize=8.3)
        x += w
    ax.annotate("", xy=(0.07 + 0.75 + 1.05, 0.62), xytext=(0.07 + 0.75 + 1.05 + 1.1 + 1.6 + 0.0, 0.62),
                arrowprops=dict(arrowstyle="<->", color=RED, lw=1.2))
    ax.text(0.07 + 0.75 + 1.05 + (1.1 + 1.6) / 2, 0.38, "CRC-16/CCITT-FALSE covers CMD and PAYLOAD",
            ha="center", fontsize=8.6, color=RED)
    save(fig, "packet_frame.png")


# ── 8. Firmware state machine ───────────────────────────────────────────────────────────────────
def state_machine():
    fig, ax = canvas(3.5)
    ax.text(W / 2, 3.32, "Firmware state machine", ha="center", fontsize=10.5, fontweight="bold", color=NAVY)
    box(ax, 0.2, 1.55, 1.1, 0.8, "IDLE\nLD1 steady", fc=LGREEN, ec=GREEN, fs=9, bold=True)
    box(ax, 2.35, 2.45, 1.3, 0.6, "UPLOADING\nLD2 slow blink", fc=LBLUE, fs=8.6)
    box(ax, 2.35, 0.65, 1.3, 0.6, "CALIBRATING\nLD2 fast blink", fc=LBLUE, fs=8.6)
    box(ax, 4.75, 1.55, 1.3, 0.8, "SCANNING\nLD2 slow blink", fc=LAMBER, ec=AMBER, fs=8.8, bold=True)
    box(ax, 4.75, 0.35, 1.3, 0.6, "COMPLETE\n2 blinks, then IDLE", fc=LGREEN, ec=GREEN, fs=8.2)
    arrow(ax, (0.75, 2.35), (2.35, 2.75), "", both=True)
    ax.text(0.95, 2.78, "SET_NETLIST", fontsize=8.2, color=NAVY)
    arrow(ax, (0.75, 1.55), (2.35, 0.95), "", both=True)
    ax.text(0.95, 0.9, "CALIBRATE", fontsize=8.2, color=NAVY)
    arrow(ax, (1.3, 1.95), (4.75, 1.95), "")
    ax.text(3.0, 2.03, "START_CONT, START_CROSS_CONT,", ha="center", fontsize=8.0, color=NAVY)
    ax.text(3.0, 1.74, "AUTO_SCAN or button B1", ha="center", fontsize=8.0, color=NAVY)
    arrow(ax, (5.4, 1.55), (5.4, 0.95), "")
    ax.text(5.5, 1.2, "scan finished", fontsize=8.2, color=NAVY)
    ax.plot([4.75, 0.75], [0.65, 0.65], color=GREY, lw=1.3)
    arrow(ax, (0.75, 0.65), (0.75, 1.55), "", color=GREY)
    ax.text(4.2, 0.52, "automatic return to IDLE", ha="right", fontsize=8.2, color=GREY)
    ax.text(3.0, 1.3, "ABORT from any state returns to IDLE", ha="center", fontsize=8.2, color=GREY)
    save(fig, "state_machine.png")


# ── 9. Mode 1 sequence ────────────────────────────────────────────────────────────────────────────
def sequence():
    fig, ax = canvas(4.3)
    ax.text(W / 2, 4.15, "Message sequence of a Continuity test", ha="center", fontsize=10.5, fontweight="bold", color=NAVY)
    xg, xf = 1.3, 4.9
    box(ax, xg - 0.7, 3.6, 1.4, 0.4, "GUI", fc=LBLUE, bold=True)
    box(ax, xf - 0.7, 3.6, 1.4, 0.4, "Firmware", fc=LGREEN, ec=GREEN, bold=True)
    ax.plot([xg, xg], [3.6, 0.1], color=GREY, lw=1, ls="--")
    ax.plot([xf, xf], [3.6, 0.1], color=GREY, lw=1, ls="--")
    seq = [("SET_PARAM", 1), ("ACK", -1), ("SET_NETLIST (one packet per chunk)", 1), ("ACK per chunk", -1),
           ("START_CONT or START_CROSS_CONT", 1), ("ACK", -1),
           ("RESULT_CONT for each pair, PROGRESS every 4", -1), ("SCAN_DONE", -1)]
    y = 3.35
    for text, d in seq:
        a, b = ((xg, xf) if d > 0 else (xf, xg))
        arrow(ax, (a, y), (b, y), text, fs=8.6, off=(0, 0.03))
        y -= 0.37
    ax.text(W / 2, 0.22, "PING every 2 s; three unanswered pings mark the link lost.",
            ha="center", fontsize=8.8, color=GREY)
    save(fig, "sequence.png")


# ── 10. Channel mapping ─────────────────────────────────────────────────────────────────────────────
def mapping():
    fig, ax = canvas(2.7)
    ax.text(W / 2, 2.52, "From a netlist pin to a connector pin", ha="center", fontsize=10.5, fontweight="bold", color=NAVY)
    box(ax, 0.1, 1.2, 1.35, 1.0, "Netlist\nSrc Pin # 20\nDst Pin # 20", fc=LAMBER, ec=AMBER, fs=8.8)
    box(ax, 2.0, 1.2, 1.5, 1.0, "Channel 20\n(the number the\nfirmware uses)", fc=LGREEN, ec=GREEN, fs=8.8)
    box(ax, 4.05, 1.2, 2.1, 1.0, "connector_config.xlsx\nchannel 20 = J2 pin 5", fc=LBLUE, fs=8.8)
    arrow(ax, (1.45, 1.7), (2.0, 1.7)); arrow(ax, (3.5, 1.7), (4.05, 1.7))
    ax.text(W / 2, 0.75, "On screen and in reports the pin is shown as  J2 pin 5.", ha="center", fontsize=9.2)
    ax.text(W / 2, 0.42, "The firmware only ever sees the channel number.", ha="center", fontsize=9, color=GREY)
    save(fig, "mapping.png")


# ── 11. Acceptance test flow ──────────────────────────────────────────────────────────────────────────
def test_flow():
    fig, ax = canvas(2.7)
    ax.text(W / 2, 2.52, "Acceptance test sequence", ha="center", fontsize=10.5, fontweight="bold", color=NAVY)
    names = ["TC-01\nPower-on and\nconnection", "TC-02\nConnector\nconfiguration", "TC-03\nContinuity\nPASS",
             "TC-04\nContinuity\nFAIL", "TC-05\nCross\ncontinuity", "TC-06\nAuto-Scan", "TC-07\nAbort and\nfaults", "TC-08\nResults\nexport"]
    for i, n in enumerate(names):
        row, col = divmod(i, 4)
        x = 0.3 + col * 1.5
        y = 1.45 - row * 0.95
        box(ax, x, y, 1.1, 0.75, n, fc=LBLUE if i < 7 else LGREEN, ec=BLUE if i < 7 else GREEN, fs=8.4)
        if col < 3:
            arrow(ax, (x + 1.1, y + 0.37), (x + 1.5, y + 0.37))
    ax.plot([0.3 + 3 * 1.5 + 0.55, 0.3 + 3 * 1.5 + 0.55], [1.45, 1.32], color=NAVY, lw=1.3)
    ax.plot([0.3 + 3 * 1.5 + 0.55, 0.85], [1.32, 1.32], color=NAVY, lw=1.3)
    arrow(ax, (0.85, 1.32), (0.85, 1.2), "")
    ax.text(W / 2, 0.15, "Run the cases in this order; each later case assumes the earlier ones passed.",
            ha="center", fontsize=8.8, color=GREY)
    save(fig, "test_flow.png")


# ── 12. Data flow (GUI side) ────────────────────────────────────────────────────────────────────────────
def data_flow():
    fig, ax = canvas(2.9)
    ax.text(W / 2, 2.72, "How a result reaches the screen", ha="center", fontsize=10.5, fontweight="bold", color=NAVY)
    items = [("Serial worker\nthread", LBLUE, BLUE), ("Qt signal\ncontResultReceived", LGREY, GREY),
             ("MainWindow\n_on_cont_result", LBLUE, BLUE), ("Result table\nand model", LGREEN, GREEN)]
    x = 0.1
    for t, f, e in items:
        box(ax, x, 1.5, 1.35, 0.85, t, fc=f, ec=e, fs=8.8)
        x += 1.55
    for i in range(3):
        arrow(ax, (0.1 + 1.35 + i * 1.55, 1.92), (0.1 + 1.55 * (i + 1), 1.92))
    box(ax, 3.2, 0.3, 1.35, 0.7, "Connector view\n(wire colour)", fc=LGREEN, ec=GREEN, fs=8.6)
    box(ax, 4.75, 0.3, 1.35, 0.7, "Counters and\nverdict", fc=LAMBER, ec=AMBER, fs=8.6)
    arrow(ax, (3.9, 1.5), (3.9, 1.0)); arrow(ax, (3.9, 1.5), (5.4, 1.0))
    save(fig, "data_flow.png")


if __name__ == "__main__":
    for f in (system_block, principle, hardware, led_patterns, flash_flow, architecture,
              packet_frame, state_machine, sequence, mapping, test_flow, data_flow):
        f()
