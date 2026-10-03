<#
.SYNOPSIS
    Cut a V6C release: build, package, tag, and push to trigger the CI workflow.

.DESCRIPTION
    Automates the release procedure in docs/V6CRelease.md:
        0. Provision the project-local Python environment (.venv) via
           scripts/setup_venv.ps1. Ninja and Python are never taken from the
           system; the build consumes .venv exclusively.
        1. Verify the working tree is clean and in sync with origin/main.
        2. Full build + tests via scripts/build.ps1.
        3. Stage and package via scripts/make_dist.ps1.
        4. Smoke-test the staged tree via scripts/validate_dist.ps1.
        5. Create an annotated git tag.
        6. Push the tag to origin (triggers release.yml workflow).

.PARAMETER Version
    Tag name, e.g. "v2026.05.27". Defaults to today's UTC date as vYYYY.MM.DD.

.PARAMETER Highlights
    One or more bullet strings for the "Highlights" section of the tag message.
    If omitted, git opens your configured editor so you can write the message
    manually (same as `git tag -a`).

.PARAMETER SkipBuild
    Skip scripts/build.ps1. Use only when the build is already known-good.

.PARAMETER DryRun
    Stop before pushing the tag. Creates the tag locally for inspection.

.EXAMPLE
    # Interactive message (editor opens):
    pwsh scripts\publish.ps1

    # Fully scripted:
    pwsh scripts\publish.ps1 -Highlights "Fix sieve regression","Update docs"

    # Dry run to inspect the tag without pushing:
    pwsh scripts\publish.ps1 -Highlights "Fix X" -DryRun

    # Skip the build step (already known-good):
    pwsh scripts\publish.ps1 -SkipBuild -Highlights "Fix X"
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string[]]$Highlights,
    [switch]$SkipBuild,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# --- 1. Working tree must be clean ---
$status = git status --porcelain
if ($status) {
    throw "Working tree is not clean. Commit or stash changes before releasing.`n$status"
}

# --- 1b. Must be in sync with origin/main ---
git fetch origin main --quiet
$behind = git rev-list --count HEAD..origin/main
if ([int]$behind -gt 0) {
    throw "Local main is $behind commit(s) behind origin/main. Run: git pull --ff-only origin main"
}
Write-Host 'Working tree clean, in sync with origin/main.'

# --- 2a. Project-local Python environment (.venv) ---
# Guarantee the release uses the pinned local Python + Ninja, never a system
# interpreter. .venv/ is gitignored, so this does not affect the clean check.
Write-Host '--- Python environment (.venv) ---'
& (Join-Path $PSScriptRoot 'setup_venv.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Python environment setup failed (scripts/setup_venv.ps1).' }

# --- 2. Build + tests ---
if (-not $SkipBuild) {
    Write-Host '--- Build + tests ---'
    & (Join-Path $PSScriptRoot 'build.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Build/tests failed. Aborting release.' }
}

# --- 3. Version ---
if (-not $Version) {
    $Version = "v$((Get-Date).ToUniversalTime().ToString('yyyy.MM.dd'))"
}
Write-Host "Release version: $Version"

if (git tag -l $Version) {
    throw "Tag '$Version' already exists locally. Use a patch suffix, e.g. $Version-1"
}

# --- 4. Stage + package ---
Write-Host '--- Stage + package ---'
$DistVersion = $Version -replace '^v', ''
& (Join-Path $PSScriptRoot 'make_dist.ps1') -Version $DistVersion
if ($LASTEXITCODE -ne 0) { throw 'make_dist.ps1 failed' }

$Stage = Join-Path $repoRoot "dist\v6c-$DistVersion-windows-x64"

# --- 5. Smoke test ---
Write-Host '--- Smoke test staged tree ---'
& (Join-Path $PSScriptRoot 'validate_dist.ps1') -Stage $Stage
if ($LASTEXITCODE -ne 0) { throw 'validate_dist.ps1 failed' }

# --- 6. Create annotated tag ---
if ($Highlights) {
    $bullets = ($Highlights | ForEach-Object { "- $_" }) -join "`n"
    $msg = @"
$Version

Highlights:
$bullets
"@
    git tag -a $Version -m $msg
} else {
    # Open the configured git editor for the tag message
    git tag -a $Version
}
if ($LASTEXITCODE -ne 0) { throw 'git tag failed' }

Write-Host ''
git tag -n10 $Version

# --- 7. Push ---
if ($DryRun) {
    Write-Host ''
    Write-Host "DryRun: tag '$Version' created locally. To push manually:"
    Write-Host "  git push origin $Version"
} else {
    Write-Host ''
    Write-Host "Pushing tag '$Version' to origin (triggers release.yml)..."
    git push origin $Version
    if ($LASTEXITCODE -ne 0) { throw 'git push failed' }
    Write-Host "Done. Monitor the workflow at: https://github.com/parallelno/v6llvmc/actions"
}
