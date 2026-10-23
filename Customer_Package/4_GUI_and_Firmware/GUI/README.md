# GUI

| File | Use |
|---|---|
| `HT_MK1_GUI.exe` | The operator GUI, for the real instrument. |
| `HT_MK1_GUI_Demo.exe` | The same GUI with a built-in simulator and no instrument. For training and trying the software - **nothing it shows is a measurement.** |

## Running it

* Windows 10 or 11, 64-bit. Nothing to install - double-click. (It unpacks to a temporary folder on each
  launch, so the first window takes a second or two.)
* Real instrument: connect the instrument's serial port (the ST-LINK virtual COM port, 115200 8N1), open the
  **port selector** in the status bar, pick the port and press **Connect**.
* The window opens maximized. The footer shows the GUI build time and, once connected, the firmware.

## Demo mode

The Run screen has a **Demo harness** selector (Good / Faulty) that changes what the simulator reports.
Load one of the example netlists first (Continuity screen, **Select...**), or use **Auto Scan**.

## Notes

* This is the customer build: it has no Diagnostics screen.
* Operating instructions and safety: `../../0_Documents/2_User_Manual.pdf`. What every screen and button does: `../../0_Documents/3_GUI_Functional_Description.pdf`.
