"""Where the app finds and keeps its files, from source or as a frozen exe.

Run from source, everything lives under gui/ exactly as before.  Frozen
(PyInstaller --onefile) the exe unpacks itself into a temporary folder that is
deleted on exit, so two kinds of files have to be told apart:

  bundle_dir()  read-only assets shipped inside the exe (themes, icons, the
                default connector config).  Fine to read from the temp folder.
  data_dir()    files the app writes and expects to find next time (profiles,
                settings, saved results, golden netlists).  These must NOT go
                in the temp folder or they vanish on exit, so when frozen they
                go in a HarnessTesterData folder next to the exe, or under
                %LOCALAPPDATA% if that folder is not writable.
"""

from __future__ import annotations

import os
import shutil
import sys

FROZEN = bool(getattr(sys, "frozen", False))
_GUI_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
_DATA_FOLDER = "HarnessTesterData"
_APPDATA_FOLDER = "HarnessTester"     # under %LOCALAPPDATA% if the exe's folder is read-only

_data_dir: str | None = None
_migrated = False          # legacy connector IDs renamed once per run


def bundle_dir() -> str:
    """Root of the read-only files shipped with the app."""
    return getattr(sys, "_MEIPASS", _GUI_DIR) if FROZEN else _GUI_DIR


def _writable(path: str) -> bool:
    try:
        os.makedirs(path, exist_ok=True)
        probe = os.path.join(path, ".write_test")
        with open(probe, "w", encoding="utf-8") as f:
            f.write("ok")
        os.remove(probe)
        return True
    except OSError:
        return False


def data_dir() -> str:
    """Root of the files the app writes and reads back on the next run."""
    global _data_dir
    if _data_dir is None:
        if not FROZEN:
            _data_dir = _GUI_DIR
        else:
            beside_exe = os.path.join(
                os.path.dirname(os.path.abspath(sys.executable)), _DATA_FOLDER)
            if _writable(beside_exe):
                _data_dir = beside_exe
            else:
                base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
                _data_dir = os.path.join(base, _APPDATA_FOLDER)
                os.makedirs(_data_dir, exist_ok=True)
    return _data_dir


def profiles_dir() -> str:
    return os.path.join(data_dir(), "profiles")


def results_dir() -> str:
    return os.path.join(profiles_dir(), "results")


def settings_path() -> str:
    return os.path.join(profiles_dir(), "app_settings.json")


def netlists_dir() -> str:
    """Where golden-sample netlists are saved by default."""
    return os.path.join(data_dir(), "netlists")


def default_connector_config() -> str:
    """The connector_config.xlsx the 'Default' button points at."""
    if FROZEN:
        return os.path.join(bundle_dir(), "netlists", "connector_config.xlsx")
    return os.path.normpath(
        os.path.join(_GUI_DIR, "..", "netlists", "connector_config.xlsx"))


def active_connector_config() -> str:
    """The connector config the Configuration tab edits and the app uses.

    A writable copy kept with the profiles; seeded from the built-in default
    the first time it is asked for, so edits never touch the shipped file.
    """
    global _migrated
    path = os.path.join(profiles_dir(), "connector_config.xlsx")
    if not os.path.exists(path):
        os.makedirs(profiles_dir(), exist_ok=True)
        default = default_connector_config()
        if os.path.exists(default):
            shutil.copy2(default, path)
            try:
                from core.pinmap import strip_mcu_columns
                strip_mcu_columns(path)     # the master sheet carries MCU pins; the user's copy does not
            except Exception:
                pass
    elif not _migrated:
        _migrated = True
        try:
            from core.pinmap import migrate_legacy_ids, strip_mcu_columns
            migrate_legacy_ids(path)
            strip_mcu_columns(path)         # a copy saved by an earlier build still has them
        except Exception:
            pass    # an unreadable file is reported when the config is loaded
    return path


def seed_data() -> None:
    """First run of a frozen exe: put the bundled default profiles in place.

    Existing files are never overwritten, so profiles the user has saved or
    edited survive an upgrade.  Nothing to do when run from source.
    """
    if not FROZEN:
        return
    bundled = os.path.join(bundle_dir(), "profiles")
    target = profiles_dir()
    os.makedirs(target, exist_ok=True)
    os.makedirs(results_dir(), exist_ok=True)
    if not os.path.isdir(bundled):
        return
    for name in os.listdir(bundled):
        # app_settings.json is per-machine window state, not a profile.
        if not name.endswith(".json") or name.startswith("app_"):
            continue
        dest = os.path.join(target, name)
        if not os.path.exists(dest):
            shutil.copy2(os.path.join(bundled, name), dest)
