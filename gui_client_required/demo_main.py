"""Entry point of the demo: the Harness Tester program with a virtual tester.

Run from source:  python demo_main.py
Packaged as HarnessTesterDemo.exe by HarnessTesterDemo.spec.
"""

import os
import sys

# Ensure project root is on the path when run directly
sys.path.insert(0, os.path.dirname(__file__))

from PyQt6.QtWidgets import QApplication
from core import paths, port_manager

# The demo keeps its own profiles, settings and results, so it never touches
# the real program's.
paths._DATA_FOLDER = "HarnessTesterDemoData"
paths._APPDATA_FOLDER = "HarnessTesterDemo"

# The only "port" is the virtual tester.  Set before the UI modules import
# port_manager's names.
port_manager._SERIAL_AVAILABLE = True
port_manager.enumerate_ports = lambda: [
    port_manager.PortInfo("DEMO", "Virtual Harness Tester (no hardware)")]

from ui.demo_window import DemoMainWindow  # noqa: E402


def main() -> None:
    app = QApplication(sys.argv)
    app.setApplicationName("HarnessTesterDemo")
    app.setOrganizationName("HarnessTester")

    paths.seed_data()

    window = DemoMainWindow()
    window.showMaximized()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
