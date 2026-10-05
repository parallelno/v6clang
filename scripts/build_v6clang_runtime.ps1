<#
.SYNOPSIS
    Assemble the V6CLANG runtime objects (crt0.o) using a freshly-built clang.

.DESCRIPTION
    The V6CLANG runtime currently consists of one object file: crt0.o, assembled
    from compiler-rt/lib/builtins/v6clang/crt0.s. It is NOT produced by the LLVM
    CMake/ninja build because compiler-rt is not configured for the i8080
    target. Instead, after every successful ninja build of clang we run this
    script to assemble crt0.s -> crt0.o using the just-built clang, and we
    place the .o next to its .s source.

    The clang driver (clang/lib/Driver/ToolChains/V6Clang.cpp) searches for
    crt0.o in two locations:
      1. <ResourceDir>/lib/v6clang/crt0.o            (installed/release tree)
      2. <bin>/../../compiler-rt/lib/builtins/v6clang/crt0.o  (dev tree)

    This script produces (2). For release builds, scripts/make_dist.ps1
    copies the .o from (2) into the staged install tree.

    If the .o is already up to date relative to the .s, assembly is skipped.

.PARAMETER BuildDir
    Path to the LLVM build directory containing bin/clang.exe.
    Defaults to "llvm-build" at the repo root.

.PARAMETER Force
    Reassemble even if the output is newer than the source.
#>
[CmdletBinding()]
param(
    [string]$BuildDir = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
if (-not $BuildDir) {
    $BuildDir = Join-Path $repoRoot 'llvm-build'
}

$ClangExe = Join-Path $BuildDir 'bin\clang.exe'
if (-not (Test-Path $ClangExe)) {
    throw "clang.exe not found at $ClangExe. Build clang first (ninja -C $BuildDir clang)."
}

$RtSrcDir = Join-Path $repoRoot 'compiler-rt\lib\builtins\v6clang'
$Sources = @('crt0.s')

foreach ($s in $Sources) {
    $sPath = Join-Path $RtSrcDir $s
    if (-not (Test-Path $sPath)) {
        throw "Missing runtime source: $sPath"
    }
    $oPath = [System.IO.Path]::ChangeExtension($sPath, '.o')

    $needsBuild = $Force -or (-not (Test-Path $oPath)) -or `
                  ((Get-Item $sPath).LastWriteTime -gt (Get-Item $oPath).LastWriteTime) -or `
                  ((Get-Item $ClangExe).LastWriteTime -gt (Get-Item $oPath).LastWriteTime)

    if (-not $needsBuild) {
        Write-Host "[v6clang-runtime] up to date: $oPath"
        continue
    }

    Write-Host "[v6clang-runtime] assembling $s -> $(Split-Path $oPath -Leaf)"
    & $ClangExe --target=i8080-unknown-v6clang -c $sPath -o $oPath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to assemble $sPath (clang exit $LASTEXITCODE)"
    }
}

Write-Host "[v6clang-runtime] done."
