"""TestProfile — persistent test session configuration."""

from __future__ import annotations
import json
import os
from dataclasses import dataclass, asdict


@dataclass
class TestProfile:
    name: str = "Default"
    operator: str = ""
    dut_id_prefix: str = "HT"
    dut_id_counter: int = 1
    port: str = ""
    baud: int = 115200
    netlist_path: str = ""
    r_limit_mohm: float = 500.0
    cal_offset_mohm: int = 0

    @property
    def dut_id(self) -> str:
        return f"{self.dut_id_prefix}-{self.dut_id_counter:04d}"

    def next_dut_id(self) -> str:
        """Increment counter and return the new DUT ID."""
        self.dut_id_counter += 1
        return self.dut_id


def load_profile(path: str) -> TestProfile:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    p = TestProfile()
    for k, v in data.items():
        if hasattr(p, k):
            setattr(p, k, v)
    return p


def save_profile(profile: TestProfile, path: str) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(asdict(profile), f, indent=2)


def default_profile() -> TestProfile:
    return TestProfile()


def profiles_dir() -> str:
    from . import paths
    return paths.profiles_dir()


def list_profiles() -> list[str]:
    """Return profile names (without .json extension) found in profiles/."""
    d = profiles_dir()
    if not os.path.isdir(d):
        return []
    return [
        os.path.splitext(f)[0]
        for f in os.listdir(d)
        if f.endswith(".json") and not f.startswith("app_")
    ]
