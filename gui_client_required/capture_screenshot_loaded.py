"""Launch the GUI, load the example netlist, and capture screenshots."""
import sys
import os
import time

sys.path.insert(0, os.path.dirname(__file__))

from PyQt6.QtWidgets import QApplication
from ui.main_window import MainWindow

app = QApplication(sys.argv)
window = MainWindow()
window.show()
app.processEvents()
time.sleep(0.3)

# Load example netlist if available
example = os.path.join(os.path.dirname(__file__), "..", "netlists", "example_harness_v1.json")
if os.path.exists(example):
    window._on_netlist_browsed(example)
    app.processEvents()
    time.sleep(0.3)

# Capture connector view
pixmap = window.grab()
output_path = os.path.join(os.path.dirname(__file__), "GUI_SS", "GUI_Modernized_Connector.png")
pixmap.save(output_path)
print(f"Connector screenshot saved to {output_path}")

# Switch to Results tab
window._tabs.setCurrentIndex(1)
app.processEvents()
time.sleep(0.3)
pixmap = window.grab()
output_path = os.path.join(os.path.dirname(__file__), "GUI_SS", "GUI_Modernized_Results.png")
pixmap.save(output_path)
print(f"Results screenshot saved to {output_path}")

window.close()
app.quit()
