# Firmware Simulator — Setup Guide

The firmware simulator (`tools/firmware_sim.py`) lets you develop and test the GUI
without real hardware. It needs a virtual serial port pair so the simulator and the
GUI can talk to each other.

---

## Windows — com0com

1. Download and install **com0com** from:
   https://sourceforge.net/projects/com0com/

2. Open the com0com Setup utility (Start → com0com → Setup).

3. Click **Add Pair** — it creates two linked ports, e.g. `COM10` and `COM11`.

4. Start the simulator on one end:
   ```
   cd harness_tester
   python tools/firmware_sim.py --port COM10
   ```

5. In the GUI, connect to `COM11` at 921600 baud.

---

## Linux — socat

1. Install socat:
   ```
   sudo apt install socat
   ```

2. Create a linked virtual port pair:
   ```
   socat -d -d pty,raw,echo=0 pty,raw,echo=0
   ```
   socat will print two paths, e.g. `/dev/pts/2` and `/dev/pts/3`.

3. Start the simulator:
   ```
   python tools/firmware_sim.py --port /dev/pts/2
   ```

4. Connect the GUI to `/dev/pts/3`.

---

## Simulator Behaviour

| Command          | Simulator Response |
|---|---|
| CMD_PING         | RSP_ACK |
| CMD_GET_STATUS   | RSP_STATUS (v1.0.0, IDLE, cal=120 mΩ) |
| CMD_SET_NETLIST  | RSP_ACK |
| CMD_SET_PARAM    | RSP_ACK |
| CMD_CALIBRATE    | RSP_ACK (offset=120 mΩ) |
| CMD_START_CONT   | 100× RSP_RESULT_CONT + RSP_PROGRESS + RSP_SCAN_DONE |
| CMD_START_HV     | 10× RSP_RESULT_HV → RSP_FAULT (lid-open) after 50% |
| CMD_ABORT        | RSP_ACK |
