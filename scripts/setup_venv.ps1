<#
.SYNOPSIS
    Provision the project-local Python environment (.venv) used by V6CLANG builds.

.DESCRIPTION
    V6CLANG's build and release scripts must not depend on a machine-wide Python
    installation: system interpreters can be upgraded, relocated, or removed,
    which silently breaks Ninja discovery in CMake and leaves "python" pointing
    at a Windows Store stub. This script creates a self-contained environment
    under <repo>/.venv and installs the build/test tooling into it, so every
    script can rely on a pinned, reproducible interpreter.

    Layout produced:
      <repo>/.venv/Scripts/python.exe      # interpreter
      <repo>/.venv/Scripts/ninja.exe       # build executor (pip "ninja")
      <repo>/.venv/Scripts/pygmentize.exe  # Pygments console script

    Bootstrapping order:
      1. `uv` (preferred) — creates the venv and downloads a pinned managed
         CPython when the machine has no suitable interpreter on PATH.
      2. `python -m venv` — fallback when uv is unavailable.

    The script is idempotent and offline-friendly: when the environment already
    contains Ninja and the required modules it performs no work.

.PARAMETER PythonVersion
    Interpreter version for the uv-managed CPython (default: 3.12).

.PARAMETER Force
    Delete and recreate the environment from scratch, then reinstall packages.

.PARAMETER Quiet
    Suppress the informational banner (used when called from build.ps1).

.EXAMPLE
    pwsh scripts\setup_venv.ps1

.EXAMPLE
    pwsh scripts\setup_venv.ps1 -Force
#>
[CmdletBinding()]
param(
    [string]$PythonVersion = '3.12',
    [switch]$Force,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot    = Split-Path -Parent $PSScriptRoot
$venvDir     = Join-Path $repoRoot '.venv'
$venvScripts = Join-Path $venvDir 'Scripts'
$venvPython  = Join-Path $venvScripts 'python.exe'
$ninjaExe    = Join-Path $venvScripts 'ninja.exe'

# Packages installed into the environment. Keep this list minimal and justified:
#   ninja     - the build executor used by CMake's "-G Ninja" generator
#   pyyaml    - LLVM CMake feature detection and lit/test tooling
#   pygments  - lit/LLVM diagnostic reporting
$packages = @('ninja', 'pyyaml', 'pygments')

function Write-Info([string]$Message) {
    if (-not $Quiet) { Write-Host $Message }
}

$uv = Get-Command uv -ErrorAction SilentlyContinue

if ($Force -and (Test-Path $venvDir)) {
    Write-Info "Removing existing environment: $venvDir"
    Remove-Item -Recurse -Force $venvDir
}

if (-not (Test-Path $venvPython)) {
    if ($uv) {
        Write-Info "Creating .venv with uv (Python $PythonVersion)..."
        & $uv.Source venv $venvDir --python $PythonVersion
        if ($LASTEXITCODE -ne 0) { throw "uv venv failed (exit $LASTEXITCODE)" }
    }
    else {
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        $launcherCmd = Get-Command py -ErrorAction SilentlyContinue
        if ($pythonCmd) {
            Write-Info "Creating .venv with '$($pythonCmd.Source)'..."
            & $pythonCmd.Source -m venv $venvDir
        }
        elseif ($launcherCmd) {
            Write-Info "Creating .venv with the 'py' launcher..."
            & $launcherCmd.Source -3 -m venv $venvDir
        }
        else {
            throw ("Neither 'uv' nor 'python'/'py' is available to bootstrap .venv. " +
                   "Install uv (https://docs.astral.sh/uv/) or Python 3.8+ and re-run.")
        }
        if ($LASTEXITCODE -ne 0) { throw "python -m venv failed (exit $LASTEXITCODE)" }
    }
}

if (-not (Test-Path $venvPython)) {
    throw "Failed to create a Python interpreter at $venvPython"
}

# Decide whether packages must be (re)installed.
$needInstall = $Force -or (-not (Test-Path $ninjaExe))
if (-not $needInstall) {
    & $venvPython -c "import yaml, pygments" 2>$null
    if ($LASTEXITCODE -ne 0) { $needInstall = $true }
}

if ($needInstall) {
    Write-Info "Installing packages into .venv: $($packages -join ', ')"
    if ($uv) {
        & $uv.Source pip install --python $venvPython @packages
        if ($LASTEXITCODE -ne 0) { throw "uv pip install failed (exit $LASTEXITCODE)" }
    }
    else {
        & $venvPython -m pip install --upgrade pip
        if ($LASTEXITCODE -ne 0) { throw "pip self-upgrade failed (exit $LASTEXITCODE)" }
        & $venvPython -m pip install @packages
        if ($LASTEXITCODE -ne 0) { throw "pip install failed (exit $LASTEXITCODE)" }
    }
}

if (-not (Test-Path $ninjaExe)) {
    throw "Ninja was not installed into the environment: $ninjaExe"
}

Write-Info "Python environment ready: $venvDir"
$global:LASTEXITCODE = 0
