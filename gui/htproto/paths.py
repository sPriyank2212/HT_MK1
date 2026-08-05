"""Where the GUI writes things.

A packaged executable is launched from wherever the operator happens to be —
Explorer, a Start-menu shortcut, C:\\Windows — and the current directory is
almost never writable. Defaulting the session log to a relative ``sessions/``
worked from a checkout and failed with ``PermissionError: [WinError 5]`` on the
first real double-click, taking the whole connection down with it, because the
log is opened as part of connecting (brief §3.5 rule 5).

So: pick a per-user location that is always writable, and fall back to the
system temp directory rather than failing to connect. Session logs are how
field failures get diagnosed; losing the link because we could not open one is
the wrong trade.
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

APP = "HT_MK1"


def default_log_dir() -> Path:
    """A writable directory for session logs, created if needed."""
    candidates = []

    local = os.environ.get("LOCALAPPDATA")
    if local:
        candidates.append(Path(local) / APP / "sessions")          # Windows
    xdg = os.environ.get("XDG_DATA_HOME")
    if xdg:
        candidates.append(Path(xdg) / APP / "sessions")
    home = Path.home()
    candidates.append(home / ".local" / "share" / APP / "sessions")
    candidates.append(Path(tempfile.gettempdir()) / APP / "sessions")

    for path in candidates:
        try:
            path.mkdir(parents=True, exist_ok=True)
            probe = path / ".writable"
            probe.write_text("", encoding="ascii")
            probe.unlink()
            return path
        except OSError:
            continue

    # Nothing worked; hand back temp and let the caller surface the failure.
    return Path(tempfile.gettempdir())
