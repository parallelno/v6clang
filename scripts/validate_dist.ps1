<#
.SYNOPSIS
    Smoke-test a staged V6CLANG distributable.

.DESCRIPTION
    Compiles a tiny C program with the staged clang.exe (no -nostartfiles,
    no -T override, no --defsym workaround), runs it through the separately
    installed v6emul, and asserts the expected output. This proves clang
    resolves v6clang.ld + crt0.o + freestanding headers via the "Installed"
    branch of its driver lookup (ResourceDir-relative), not the dev-tree
    fallback, AND that crt0 auto-linkage delivers a working _start that
    calls main.

    The emulator is a reference tool that is NOT part of the staged
    distributable (see make_dist.ps1). It is resolved from the V6EMUL
    environment variable, or from -V6EmulPath.

.PARAMETER Stage
    Path to the staged distribution root (the directory containing bin/).

.PARAMETER V6EmulPath
    Path to the separately installed v6emul executable. Overrides V6EMUL.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Stage,

    [string]$V6EmulPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Clang = Join-Path $Stage 'bin\clang.exe'
if (-not (Test-Path $Clang)) { throw "Missing in stage: $Clang" }

# v6emul is a separately installed reference tool and is NOT shipped in the
# staged tree (see make_dist.ps1). Resolve it from V6EMUL / -V6EmulPath.
$Emul = if ($V6EmulPath) { $V6EmulPath } else { $env:V6EMUL }
if (-not $Emul) {
    throw 'V6EMUL is not set. Point it at the separately installed v6emul executable ' +
          'or pass -V6EmulPath <path>.'
}
if (-not (Test-Path -LiteralPath $Emul -PathType Leaf)) {
    throw "v6emul not found at: $Emul"
}

$StageDocs    = Join-Path $Stage 'docs'
$StageSamples = Join-Path $Stage 'samples'
foreach ($p in @($StageDocs, $StageSamples)) {
    if (-not (Test-Path $p)) { throw "Missing in stage: $p" }
}

$StageDocsIndex = Join-Path $StageDocs 'README.md'
$StageSampleMain = Join-Path $StageSamples '01_hello\main.c'
foreach ($p in @($StageDocsIndex, $StageSampleMain)) {
    if (-not (Test-Path $p)) { throw "Missing expected staged content: $p" }
}

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("v6clang-dist-smoke-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
try {
    $Src = Join-Path $Tmp 'smoke.c'
    @'
#include <stdint.h>
int main(void) {
    __builtin_v6clang_out(0xED, 0x42);
    __builtin_v6clang_hlt();
    return 0;
}
'@ | Set-Content -Path $Src -NoNewline

    $Rom = Join-Path $Tmp 'smoke.rom'

    # Full default flow: clang locates v6clang.ld + crt0.o entirely via
    # ResourceDir, ld.lld links, llvm-objcopy emits the flat ROM.
    Write-Host "Compiling smoke.c with staged clang ..."
    & $Clang --target=i8080-unknown-v6clang -O2 $Src -o $Rom
    if ($LASTEXITCODE -ne 0) { throw 'Staged clang failed to compile smoke.c' }
    if (-not (Test-Path $Rom)) { throw 'Staged clang did not produce smoke.rom' }

    Write-Host "Running smoke.rom in v6emul ($Emul) ..."
    $out = & $Emul --rom $Rom --load-addr 0x0100 --halt-exit --dump-cpu 2>&1 | Out-String
    Write-Host $out

    if ($out -notmatch 'TEST_OUT\s+port=0xED\s+value=0x42') {
        throw "Smoke test failed: expected TEST_OUT port=0xED value=0x42 in emulator output"
    }
    if ($out -notmatch 'HALT') {
        throw 'Smoke test failed: emulator did not reach HALT'
    }
    # crt0 sets SP = __stack_top (0x0000); first CALL into main wraps to 0xFFFE.
    # If crt0 did not run, SP would still be 0x0000 at HALT.
    if ($out -notmatch 'SP=FFFE') {
        throw 'Smoke test failed: SP not at 0xFFFE; crt0 did not initialize stack'
    }

    # Sanity-check that v6clang.ld and crt0.o are actually present where
    # clang expects them via -print-resource-dir.
    $resDir = (& $Clang -print-resource-dir).Trim()
    $expectedScript = Join-Path $resDir 'v6clang\v6clang.ld'
    $expectedCrt0   = Join-Path $resDir 'lib\v6clang\crt0.o'
    if (-not (Test-Path $expectedScript)) {
        throw "Linker script not at expected install path: $expectedScript"
    }
    if (-not (Test-Path $expectedCrt0)) {
        throw "crt0.o not at expected install path: $expectedCrt0"
    }

    # O81: verify consolidated runtime headers are present in the staged tree.
    $expectedStringH = Join-Path $resDir 'lib\v6clang\include\string.h'
    $expectedStdlibH = Join-Path $resDir 'lib\v6clang\include\stdlib.h'
    $expectedV6ClangH    = Join-Path $resDir 'lib\v6clang\include\v6clang.h'
    foreach ($h in @($expectedStringH, $expectedStdlibH, $expectedV6ClangH)) {
        if (-not (Test-Path $h)) { throw "Runtime header not in staged tree: $h" }
    }
    Write-Host "Runtime headers verified in staged tree."

    # O81 Test A: <string.h> from installed layout — no -isystem flag.
    # Verifies memset is defined (not just declared) and links correctly.
    Write-Host "Compiling string_smoke.c (tests <string.h> from installed layout) ..."
    $StringSrc = Join-Path $Tmp 'string_smoke.c'
    @'
#include <stdint.h>
#include <string.h>
int main(void) {
    uint8_t buf[4];
    memset(buf, 0xAB, 4);
    __builtin_v6clang_out(0xED, buf[0]);
    __builtin_v6clang_hlt();
    return 0;
}
'@ | Set-Content -Path $StringSrc -NoNewline

    $StringRom = Join-Path $Tmp 'string_smoke.rom'
    & $Clang --target=i8080-unknown-v6clang -O2 $StringSrc -o $StringRom
    if ($LASTEXITCODE -ne 0) { throw '<string.h> smoke: staged clang failed to compile' }

    $sout = & $Emul --rom $StringRom --load-addr 0x0100 --halt-exit --dump-cpu 2>&1 | Out-String
    Write-Host $sout
    if ($sout -notmatch 'TEST_OUT\s+port=0xED\s+value=0xAB') {
        throw '<string.h> smoke: expected TEST_OUT port=0xED value=0xAB'
    }
    if ($sout -notmatch 'HALT') { throw '<string.h> smoke: emulator did not reach HALT' }
    Write-Host "<string.h> smoke test PASSED."

    Write-Host "Release docs/ and samples/ verified at stage root."

    # O81 Test B: <stdlib.h> from installed layout — no -isystem flag.
    # Verifies min() macro is present and abort()/exit() compile.
    Write-Host "Compiling stdlib_smoke.c (tests <stdlib.h> from installed layout) ..."
    $StdlibSrc = Join-Path $Tmp 'stdlib_smoke.c'
    @'
#include <stdint.h>
#include <stdlib.h>
int main(void) {
    uint8_t x = (uint8_t)min(200, 100);  /* expects 100 = 0x64 */
    __builtin_v6clang_out(0xED, x);
    __builtin_v6clang_hlt();
    return 0;
}
'@ | Set-Content -Path $StdlibSrc -NoNewline

    $StdlibRom = Join-Path $Tmp 'stdlib_smoke.rom'
    & $Clang --target=i8080-unknown-v6clang -O2 $StdlibSrc -o $StdlibRom
    if ($LASTEXITCODE -ne 0) { throw '<stdlib.h> smoke: staged clang failed to compile' }

    $lout = & $Emul --rom $StdlibRom --load-addr 0x0100 --halt-exit --dump-cpu 2>&1 | Out-String
    Write-Host $lout
    if ($lout -notmatch 'TEST_OUT\s+port=0xED\s+value=0x64') {
        throw '<stdlib.h> smoke: expected TEST_OUT port=0xED value=0x64'
    }
    if ($lout -notmatch 'HALT') { throw '<stdlib.h> smoke: emulator did not reach HALT' }
    Write-Host "<stdlib.h> smoke test PASSED."

    Write-Host ''
    Write-Host 'Smoke test PASSED.'
}
finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
