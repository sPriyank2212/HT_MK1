"""Launch the GUI and capture a screenshot of the main window."""
import sys
import os
import time

sys.path.insert(0, os.path.dirname(__file__))

from PyQt6.QtWidgets import QApplication
from PyQt6.QtGui import QScreen
from ui.main_window import MainWindow

app = QApplication(sys.argv)
window = MainWindow()
window.show()

# Let the window render
app.processEvents()
time.sleep(0.5)
app.processEvents()

# Grab the window content
pixmap = window.grab()
output_path = os.path.join(os.path.dirname(__file__), "GUI_SS", "GUI_Modernized.png")
os.makedirs(os.path.dirname(output_path), exist_ok=True)
pixmap.save(output_path)
print(f"Screenshot saved to {output_path}")

window.close()
app.quit()
