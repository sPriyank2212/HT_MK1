"""Create the connector configuration Excel for J1/J2 (DB15) + J3 (DB9) layout."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import openpyxl
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side

out_path = Path(__file__).parent.parent.parent / "netlists" / "connector_config.xlsx"

wb = openpyxl.Workbook()
ws = wb.active
ws.title = "Connector Config"

headers = ["Connector ID", "Connector Name", "Start Pin", "End Pin"]
rows = [
    ["J1", "J1 (DB15)", 1, 15],
    ["J2", "J2 (DB15)", 16, 30],
    ["J3", "J3 (DB9)", 31, 37],
]

header_fill = PatternFill(start_color="1F4E79", end_color="1F4E79", fill_type="solid")
header_font = Font(color="FFFFFF", bold=True)
thin_border = Border(
    left=Side(style="thin"), right=Side(style="thin"),
    top=Side(style="thin"), bottom=Side(style="thin"),
)

for col, header in enumerate(headers, 1):
    cell = ws.cell(row=1, column=col, value=header)
    cell.fill = header_fill
    cell.font = header_font
    cell.alignment = Alignment(horizontal="center", vertical="center")
    cell.border = thin_border

for r_idx, row in enumerate(rows, 2):
    for c_idx, value in enumerate(row, 1):
        cell = ws.cell(row=r_idx, column=c_idx, value=value)
        cell.border = thin_border
        cell.alignment = Alignment(horizontal="center" if c_idx in (3, 4) else "left", vertical="center")

for col in ws.columns:
    max_length = 0
    column = col[0].column_letter
    for cell in col:
        try:
            if cell.value:
                max_length = max(max_length, len(str(cell.value)))
        except Exception:
            pass
    ws.column_dimensions[column].width = max_length + 2

wb.save(out_path)
print(f"Connector config created: {out_path}")
