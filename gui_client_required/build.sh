#!/usr/bin/env bash
# ============================================================
#  build.sh  -  Build standalone HarnessTester binary (Linux/Raspberry Pi)
#  Run from the gui/ directory:  ./build.sh
#
#  PyInstaller does not cross-compile: this must run natively on the
#  target machine/architecture (e.g. directly on the Raspberry Pi) to
#  produce a binary that runs on that Pi.
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

EXE="dist/HarnessTester"
SPEC="HarnessTester.spec"

echo ""
echo "=== Harness Tester - Linux/Pi Build Script ==="

# --- 1. Pre-flight checks -----------------------------------
if [ ! -f "$SPEC" ]; then
    echo "ERROR: $SPEC not found. Run this script from the gui/ directory."
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 not found on PATH."
    exit 1
fi
echo "Python      : $(python3 --version)"

if ! python3 -c "import PyInstaller" >/dev/null 2>&1; then
    echo "ERROR: PyInstaller not installed. Run: pip install -r requirements.txt"
    exit 1
fi
echo "PyInstaller : $(python3 -c 'import PyInstaller; print(PyInstaller.__version__)')"

# --- 2. Remove old binary + clean build cache ----------------
echo ""
echo "[1/2] Removing old binary and build cache..."
rm -f "$EXE"
rm -rf build
echo "      Done."

# --- 3. Run PyInstaller ---------------------------------------
echo "[2/2] Running PyInstaller..."
echo ""
python3 -m PyInstaller "$SPEC" --clean
echo ""

# --- 4. Result -------------------------------------------------
if [ ! -f "$EXE" ]; then
    echo "BUILD FAILED - binary not found after build."
    exit 1
fi
chmod +x "$EXE"

SIZE_MB=$(du -m "$EXE" | cut -f1)
echo "=== BUILD SUCCEEDED ==="
echo "  File : $(realpath "$EXE")"
echo "  Size : ${SIZE_MB} MB"
echo ""
