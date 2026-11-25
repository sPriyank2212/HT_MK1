"""Convert a netlist JSON to the flat Excel format used by the GUI loader."""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path


def convert(input_path: str, output_path: str) -> None:
    try:
        import openpyxl
    except ImportError as exc:
        raise ImportError("openpyxl is required: pip install openpyxl") from exc

    with open(input_path, encoding="utf-8") as f:
        netlist = json.load(f)

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Netlist"

    headers = [
        "Net", "Source", "Conn ID", "Src Pin Label", "Src Pin #",
        "Dst Pin #", "Dst Pin Label", "Conn ID B", "Destination",
        "Connector Detail", "Harness ID",
        "R_Min_mOhm", "R_Max_mOhm", "HV_Enabled", "HV_Voltage_V", "HV_Soak_ms", "HV_Min_IR_mOhm",
    ]

    header_fill = openpyxl.styles.PatternFill(
        start_color="1F4E79", end_color="1F4E79", fill_type="solid"
    )
    header_font = openpyxl.styles.Font(color="FFFFFF", bold=True)
    thin_border = openpyxl.styles.Border(
        left=openpyxl.styles.Side(style="thin"),
        right=openpyxl.styles.Side(style="thin"),
        top=openpyxl.styles.Side(style="thin"),
        bottom=openpyxl.styles.Side(style="thin"),
    )

    for col, header in enumerate(headers, 1):
        cell = ws.cell(row=1, column=col, value=header)
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = openpyxl.styles.Alignment(horizontal="center", vertical="center")
        cell.border = thin_border

    def _bool_str(v):
        return "TRUE" if v else "FALSE"

    rows = []
    for net in netlist.get("nets", []):
        pins = net.get("pins", [])
        if len(pins) < 2:
            continue
        src = pins[0]
        dst = pins[1]
        rows.append([
            net.get("name", ""),
            net.get("source", ""),
            net.get("connector_id", ""),
            src.get("name", ""),
            str(src.get("number", "")),
            str(dst.get("number", "")),
            dst.get("name", ""),
            net.get("connector_id_b", ""),
            net.get("destination", ""),
            net.get("connector_detail", ""),
            netlist.get("harness_id", ""),
            net.get("r_min_mohm", 0),
            net.get("r_max_mohm", 500),
            _bool_str(net.get("hv_enabled", False)),
            net.get("hv_voltage_v", 500),
            net.get("hv_soak_ms", 1000),
            net.get("hv_min_ir_mohm", 100),
        ])

    for r_idx, row in enumerate(rows, 2):
        for c_idx, value in enumerate(row, 1):
            cell = ws.cell(row=r_idx, column=c_idx, value=value)
            cell.border = thin_border
            cell.alignment = openpyxl.styles.Alignment(
                horizontal="center" if c_idx in (5, 6) else "left",
                vertical="center",
            )

    for col in ws.columns:
        max_length = 0
        column = col[0].column_letter
        for cell in col:
            try:
                if cell.value is not None:
                    max_length = max(max_length, len(str(cell.value)))
            except Exception:
                pass
        ws.column_dimensions[column].width = min(max_length + 2, 45)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    wb.save(output_path)
    print(f"Wrote {output_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert netlist JSON to Excel")
    parser.add_argument("input", help="Input netlist JSON")
    parser.add_argument("output", help="Output Excel file")
    args = parser.parse_args()
    try:
        convert(args.input, args.output)
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
