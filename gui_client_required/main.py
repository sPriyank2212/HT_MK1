"""Entry point — creates QApplication and shows the MainWindow."""

import sys
import os

# Ensure project root is on the path when run directly
sys.path.insert(0, os.path.dirname(__file__))

from PyQt6.QtWidgets import QApplication
from core import paths
from ui.main_window import MainWindow


def main() -> None:
    app = QApplication(sys.argv)
    app.setApplicationName("HarnessTester")
    app.setOrganizationName("HarnessTester")

    # Frozen exe: put the default profiles in the writable data folder.
    paths.seed_data()

    window = MainWindow()
    window.showMaximized()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
