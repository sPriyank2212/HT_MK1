# ============================================================
#  build.ps1  -  Build standalone HarnessTester.exe
#  Run from any location:  .\gui\build.ps1  OR  cd gui; .\build.ps1
# ============================================================

Set-Location $PSScriptRoot

$EXE  = "dist\HarnessTester.exe"
$SPEC = "HarnessTester.spec"

# --- 1. Pre-flight checks -----------------------------------
Write-Host ""
Write-Host "=== Harness Tester - EXE Build Script ===" -ForegroundColor Cyan

if (-not (Test-Path $SPEC)) {
    Write-Host "ERROR: $SPEC not found. Run this script from the gui/ directory." -ForegroundColor Red
    exit 1
}

$pyver = python --version 2>&1
if (-not $?) {
    Write-Host "ERROR: Python not found on PATH." -ForegroundColor Red
    exit 1
}
Write-Host "Python      : $pyver" -ForegroundColor Gray

$piVer = python -c "import PyInstaller; print(PyInstaller.__version__)" 2>&1
if (-not $?) {
    Write-Host "ERROR: PyInstaller not installed. Run: pip install pyinstaller" -ForegroundColor Red
    exit 1
}
Write-Host "PyInstaller : $piVer" -ForegroundColor Gray

# --- 2. Remove old exe --------------------------------------
Write-Host ""
Write-Host "[1/3] Removing old exe..." -ForegroundColor Yellow
if (Test-Path $EXE) {
    Remove-Item -Force $EXE
    # Wait for OneDrive to finish syncing the deletion before PyInstaller writes the new file
    $waited = 0
    while ((Test-Path $EXE) -and $waited -lt 10) {
        Start-Sleep -Seconds 1
        $waited++
    }
    Start-Sleep -Seconds 3
    Write-Host "      Removed $EXE" -ForegroundColor Gray
} else {
    Write-Host "      No previous exe found - skipping." -ForegroundColor Gray
}

# --- 3. Clean build cache -----------------------------------
Write-Host "[2/3] Cleaning build cache..." -ForegroundColor Yellow
if (Test-Path "build") { Remove-Item -Recurse -Force "build" }
Write-Host "      Done." -ForegroundColor Gray

# --- 4. Run PyInstaller -------------------------------------
Write-Host "[3/3] Running PyInstaller..." -ForegroundColor Yellow
Write-Host ""
python -m PyInstaller $SPEC --clean
Write-Host ""

# --- 5. Result ----------------------------------------------
if ($LASTEXITCODE -ne 0) {
    Write-Host "BUILD FAILED  (exit code $LASTEXITCODE)" -ForegroundColor Red
    exit $LASTEXITCODE
}

if (-not (Test-Path $EXE)) {
    Write-Host "BUILD FAILED  - exe not found after build." -ForegroundColor Red
    exit 1
}

$sizeMB = [math]::Round((Get-Item $EXE).Length / 1MB, 1)
$built  = (Get-Item $EXE).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")

Write-Host "=== BUILD SUCCEEDED ===" -ForegroundColor Green
Write-Host "  File : $((Resolve-Path $EXE).Path)" -ForegroundColor Green
Write-Host "  Size : $sizeMB MB" -ForegroundColor Green
Write-Host "  Built: $built" -ForegroundColor Green
Write-Host ""
