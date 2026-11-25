"""Apply a connector-configuration Excel to a netlist JSON.

Connector config columns (case-insensitive):
    Connector ID    - short ID written to connector_id / connector_id_b
    Connector Name  - human-readable name (stored in connector_detail)
    Start Pin       - first logical pin number in this connector
    End Pin         - last logical pin number in this connector

Usage:
    python -m tools.apply_connector_config \
        ../netlists/connector_config.xlsx \
        ../netlists/poc_harness_v2.json \
        ../netlists/poc_harness_v2_db15_db9.json
"""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path


def _normalise_header(h: str) -> str:
    return h.strip().lower().replace(" ", "_").replace("-", "_")


def load_connector_config(path: str) -> list[dict]:
    """Return list of {connector_id, connector_name, start_pin, end_pin}."""
    try:
        import openpyxl
    except ImportError as exc:
        raise ImportError("openpyxl is required: pip install openpyxl") from exc

    wb = openpyxl.load_workbook(path, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    if not rows:
        raise ValueError("Connector config Excel is empty")

    headers = [_normalise_header(str(c)) if c is not None else "" for c in rows[0]]
    col = {h: i for i, h in enumerate(headers)}

    required = {"connector_id", "start_pin", "end_pin"}
    missing = required - set(col.keys())
    if missing:
        raise ValueError(f"Connector config missing columns: {missing}")

    def _int_cell(row, name):
        idx = col.get(name)
        if idx is None or idx >= len(row):
            return None
        v = row[idx]
        if v is None or v == "":
            return None
        try:
            return int(float(str(v)))
        except (ValueError, TypeError):
            return None

    configs = []
    for row in rows[1:]:
        cid = str(row[col["connector_id"]]) if col["connector_id"] < len(row) and row[col["connector_id"]] is not None else ""
        if not cid:
            continue
        cname = str(row[col.get("connector_name", -1)]) if "connector_name" in col and col["connector_name"] < len(row) and row[col["connector_name"]] is not None else ""
        start = _int_cell(row, "start_pin")
        end = _int_cell(row, "end_pin")
        if start is None or end is None:
            raise ValueError(f"Connector '{cid}' missing Start Pin or End Pin")
        configs.append({
            "connector_id": cid,
            "connector_name": cname,
            "start_pin": start,
            "end_pin": end,
        })
    return configs


def connector_for_pin(configs: list[dict], pin: int) -> dict | None:
    for cfg in configs:
        if cfg["start_pin"] <= pin <= cfg["end_pin"]:
            return cfg
    return None


def apply_config(config_path: str, netlist_path: str, output_path: str) -> None:
    configs = load_connector_config(config_path)
    if not configs:
        raise ValueError("Connector config contains no entries")

    with open(netlist_path, encoding="utf-8") as f:
        netlist = json.load(f)

    for net in netlist.get("nets", []):
        pins = net.get("pins", [])
        if not pins:
            continue
        # Use the first pin number to determine the source connector
        src_pin = pins[0].get("number")
        src_cfg = connector_for_pin(configs, src_pin)
        if src_cfg:
            net["connector_id"] = src_cfg["connector_id"]
            detail = src_cfg["connector_name"] or src_cfg["connector_id"]
            net["connector_detail"] = detail

        # Use the second pin number to determine the destination connector
        if len(pins) >= 2:
            dst_pin = pins[1].get("number")
            dst_cfg = connector_for_pin(configs, dst_pin)
            if dst_cfg:
                net["connector_id_b"] = dst_cfg["connector_id"]
                # If destination connector differs, include both in detail
                if dst_cfg["connector_id"] != src_cfg.get("connector_id") if src_cfg else True:
                    src_detail = src_cfg["connector_name"] or src_cfg["connector_id"] if src_cfg else ""
                    dst_detail = dst_cfg["connector_name"] or dst_cfg["connector_id"]
                    if src_detail and dst_detail:
                        net["connector_detail"] = f"{src_detail} -> {dst_detail}"

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(netlist, f, indent=2)
    print(f"Wrote {output_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply connector config to a netlist JSON")
    parser.add_argument("config", help="Connector config Excel (.xlsx)")
    parser.add_argument("input", help="Input netlist JSON")
    parser.add_argument("output", help="Output netlist JSON")
    args = parser.parse_args()

    try:
        apply_config(args.config, args.input, args.output)
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
