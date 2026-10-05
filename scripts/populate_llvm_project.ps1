# populate_llvm_project.ps1
# Populates llvm-project/ (gitignored build source) from the git-tracked mirrors.
# Run this ONCE after cloning the repo and setting up llvm-project/:
#
#   git clone --depth 1 --branch llvmorg-18.1.0 https://github.com/llvm/llvm-project.git llvm-project
#   powershell -ExecutionPolicy Bypass -File scripts\populate_llvm_project.ps1
#
# This is the reverse of sync_llvm_mirror.ps1, which copies FROM llvm-project/ TO mirrors.

$root = Split-Path $PSScriptRoot -Parent
if (-not $root) { $root = Split-Path (Get-Location) -Parent }

# Verify llvm-project/ exists
if (-not (Test-Path "$root\llvm-project\llvm")) {
    Write-Error "llvm-project/ not found. Clone it first:`n  git clone --depth 1 --branch llvmorg-18.1.0 https://github.com/llvm/llvm-project.git llvm-project"
    exit 1
}

Write-Host "Populating llvm-project/ from git-tracked mirrors..."

# ── V6CLANG backend target directory ──
# Full directory mirror (all files are V6CLANG-specific)
robocopy "$root\llvm\lib\Target\V6Clang" "$root\llvm-project\llvm\lib\Target\V6Clang" /MIR /NFL /NDL /NJH /NJS
Write-Host "  [OK] llvm/lib/Target/V6Clang/"

# ── Lit tests ──
# CodeGen tests (source of truth for lit tests)
robocopy "$root\tests\lit\CodeGen\V6Clang" "$root\llvm-project\llvm\test\CodeGen\V6Clang" /MIR /XD Output /NFL /NDL /NJH /NJS
Write-Host "  [OK] llvm/test/CodeGen/V6Clang/"

# MC encoding tests
robocopy "$root\tests\lit\MC\V6Clang" "$root\llvm-project\llvm\test\MC\V6Clang" /MIR /XD Output /NFL /NDL /NJH /NJS
Write-Host "  [OK] llvm/test/MC/V6Clang/"

# Linker tests (lld + V6CLANG)
robocopy "$root\tests\lit\Linker\V6Clang" "$root\llvm-project\llvm\test\Linker\V6Clang" /MIR /XD Output /NFL /NDL /NJH /NJS
Write-Host "  [OK] llvm/test/Linker/V6Clang/"

# Clang integration tests
robocopy "$root\tests\lit\Clang\V6Clang" "$root\llvm-project\clang\test\CodeGen\V6Clang" /MIR /XD Output /NFL /NDL /NJH /NJS
Write-Host "  [OK] clang/test/CodeGen/V6Clang/"

# ── Modified upstream LLVM files ──
# M1: i8080 architecture registration in Triple
xcopy /Y /I "$root\llvm\include\llvm\TargetParser\Triple.h" "$root\llvm-project\llvm\include\llvm\TargetParser\" > $null
xcopy /Y /I "$root\llvm\lib\TargetParser\Triple.cpp" "$root\llvm-project\llvm\lib\TargetParser\" > $null
Write-Host "  [OK] Triple.h, Triple.cpp"

# EM_V6Clang machine ID in BinaryFormat/ELF.h
xcopy /Y /I "$root\llvm\include\llvm\BinaryFormat\ELF.h" "$root\llvm-project\llvm\include\llvm\BinaryFormat\" > $null
Write-Host "  [OK] BinaryFormat/ELF.h (EM_V6Clang)"

# V6CLANG ELF format/architecture recognition used by llvm-readobj/dwarfdump.
xcopy /Y /I "$root\llvm\include\llvm\Object\ELFObjectFile.h" "$root\llvm-project\llvm\include\llvm\Object\" > $null
Write-Host "  [OK] Object/ELFObjectFile.h (EM_V6Clang recognition)"

# V6CLANG relocation type names printed by llvm-readelf/llvm-readobj
# (getELFRelocationTypeName: R_V6CLANG_8/16/LO8/HI8/32)
xcopy /Y /I "$root\llvm\lib\Object\ELF.cpp" "$root\llvm-project\llvm\lib\Object\" > $null
Write-Host "  [OK] lib/Object/ELF.cpp (V6CLANG relocation names)"

# M9: Clang frontend integration
# TargetInfo (Basic/Targets)
xcopy /Y /I "$root\clang\lib\Basic\Targets\I8080.h" "$root\llvm-project\clang\lib\Basic\Targets\" > $null
xcopy /Y /I "$root\clang\lib\Basic\Targets\I8080.cpp" "$root\llvm-project\clang\lib\Basic\Targets\" > $null
xcopy /Y /I "$root\clang\lib\Basic\Targets.cpp" "$root\llvm-project\clang\lib\Basic\" > $null
xcopy /Y /I "$root\clang\lib\Basic\CMakeLists.txt" "$root\llvm-project\clang\lib\Basic\" > $null
# TargetCodeGenInfo (CodeGen/Targets)
if (-not (Test-Path "$root\llvm-project\clang\lib\CodeGen\Targets")) { New-Item -ItemType Directory -Path "$root\llvm-project\clang\lib\CodeGen\Targets" -Force > $null }
xcopy /Y /I "$root\clang\lib\CodeGen\Targets\V6Clang.cpp" "$root\llvm-project\clang\lib\CodeGen\Targets\" > $null
xcopy /Y /I "$root\clang\lib\CodeGen\TargetInfo.h" "$root\llvm-project\clang\lib\CodeGen\" > $null
xcopy /Y /I "$root\clang\lib\CodeGen\CodeGenModule.cpp" "$root\llvm-project\clang\lib\CodeGen\" > $null
xcopy /Y /I "$root\clang\lib\CodeGen\CGCall.cpp" "$root\llvm-project\clang\lib\CodeGen\" > $null
xcopy /Y /I "$root\clang\lib\CodeGen\CMakeLists.txt" "$root\llvm-project\clang\lib\CodeGen\" > $null
# Driver ToolChain
if (-not (Test-Path "$root\llvm-project\clang\lib\Driver\ToolChains")) { New-Item -ItemType Directory -Path "$root\llvm-project\clang\lib\Driver\ToolChains" -Force > $null }
xcopy /Y /I "$root\clang\lib\Driver\ToolChains\V6Clang.h" "$root\llvm-project\clang\lib\Driver\ToolChains\" > $null
xcopy /Y /I "$root\clang\lib\Driver\ToolChains\V6Clang.cpp" "$root\llvm-project\clang\lib\Driver\ToolChains\" > $null
xcopy /Y /I "$root\clang\lib\Driver\Driver.cpp" "$root\llvm-project\clang\lib\Driver\" > $null
xcopy /Y /I "$root\clang\lib\Driver\CMakeLists.txt" "$root\llvm-project\clang\lib\Driver\" > $null
# O70: V6CLANG driver options (-fno-v6clang-auto-include)
xcopy /Y /I "$root\clang\include\clang\Driver\Options.td" "$root\llvm-project\clang\include\clang\Driver\" > $null
# V6CLANG: clang attribute v6clang_rt_helper (lowers to LLVM string fn attr "v6clang-rt-helper").
xcopy /Y /I "$root\clang\include\clang\Basic\Attr.td" "$root\llvm-project\clang\include\clang\Basic\" > $null
# Clang.cpp (unsigned char default)
xcopy /Y /I "$root\clang\lib\Driver\ToolChains\Clang.cpp" "$root\llvm-project\clang\lib\Driver\ToolChains\" > $null
# CommonArgs.cpp (frame pointer default)
xcopy /Y /I "$root\clang\lib\Driver\ToolChains\CommonArgs.cpp" "$root\llvm-project\clang\lib\Driver\ToolChains\" > $null
Write-Host "  [OK] Clang frontend (Targets, CodeGen, Driver)"

# M9 step 5: Diagnostics
xcopy /Y /I "$root\clang\include\clang\Basic\DiagnosticSemaKinds.td" "$root\llvm-project\clang\include\clang\Basic\" > $null
xcopy /Y /I "$root\clang\lib\Sema\Sema.cpp" "$root\llvm-project\clang\lib\Sema\" > $null
Write-Host "  [OK] Diagnostics"

# M9 step 6: Builtin intrinsics
xcopy /Y /I "$root\clang\include\clang\Basic\BuiltinsV6Clang.def" "$root\llvm-project\clang\include\clang\Basic\" > $null
xcopy /Y /I "$root\clang\include\clang\Basic\TargetBuiltins.h" "$root\llvm-project\clang\include\clang\Basic\" > $null
xcopy /Y /I "$root\llvm\include\llvm\IR\IntrinsicsV6Clang.td" "$root\llvm-project\llvm\include\llvm\IR\" > $null
xcopy /Y /I "$root\llvm\include\llvm\IR\Intrinsics.td" "$root\llvm-project\llvm\include\llvm\IR\" > $null
xcopy /Y /I "$root\llvm\include\llvm\IR\CMakeLists.txt" "$root\llvm-project\llvm\include\llvm\IR\" > $null
# xcopy preserves mirror timestamps. Touch the root definition so an existing
# build tree regenerates IntrinsicImpl.inc after reverse population.
(Get-Item "$root\llvm-project\llvm\include\llvm\IR\Intrinsics.td").LastWriteTime = Get-Date
# Function.cpp (IntrinsicsV6Clang.h include)
xcopy /Y /I "$root\llvm\lib\IR\Function.cpp" "$root\llvm-project\llvm\lib\IR\" > $null
Write-Host "  [OK] Intrinsics (IntrinsicsV6Clang.td, BuiltinsV6Clang.def, Function.cpp)"

# Loop-rotation opt-out hook in MachineBlockPlacement (gated by
# TargetSubtargetInfo::enableLoopRotationInBlockPlacement, overridden in V6CLANG).
xcopy /Y /I "$root\llvm\include\llvm\CodeGen\TargetSubtargetInfo.h" "$root\llvm-project\llvm\include\llvm\CodeGen\" > $null
xcopy /Y /I "$root\llvm\lib\CodeGen\MachineBlockPlacement.cpp" "$root\llvm-project\llvm\lib\CodeGen\" > $null
Write-Host "  [OK] TargetSubtargetInfo.h, MachineBlockPlacement.cpp (enableLoopRotationInBlockPlacement)"

# Debug metadata: relocatable global addresses in local DBG_VALUE locations.
if (-not (Test-Path "$root\llvm-project\llvm\lib\CodeGen\AsmPrinter")) { New-Item -ItemType Directory -Path "$root\llvm-project\llvm\lib\CodeGen\AsmPrinter" -Force > $null }
xcopy /Y /I "$root\llvm\lib\CodeGen\AsmPrinter\DebugLocEntry.h" "$root\llvm-project\llvm\lib\CodeGen\AsmPrinter\" > $null
xcopy /Y /I "$root\llvm\lib\CodeGen\AsmPrinter\DwarfDebug.cpp" "$root\llvm-project\llvm\lib\CodeGen\AsmPrinter\" > $null
xcopy /Y /I "$root\llvm\lib\CodeGen\AsmPrinter\DwarfCompileUnit.cpp" "$root\llvm-project\llvm\lib\CodeGen\AsmPrinter\" > $null
xcopy /Y /I "$root\llvm\lib\CodeGen\AsmPrinter\DwarfExpression.h" "$root\llvm-project\llvm\lib\CodeGen\AsmPrinter\" > $null
xcopy /Y /I "$root\llvm\lib\CodeGen\AsmPrinter\DwarfExpression.cpp" "$root\llvm-project\llvm\lib\CodeGen\AsmPrinter\" > $null
Write-Host "  [OK] AsmPrinter relocatable local debug addresses"

# O-LLD: V6CLANG default linker script (data resource for the driver)
if (-not (Test-Path "$root\llvm-project\clang\lib\Driver\ToolChains\V6Clang")) { New-Item -ItemType Directory -Path "$root\llvm-project\clang\lib\Driver\ToolChains\V6Clang" -Force > $null }
xcopy /Y /I "$root\clang\lib\Driver\ToolChains\V6Clang\v6clang.ld" "$root\llvm-project\clang\lib\Driver\ToolChains\V6Clang\" > $null
Write-Host "  [OK] V6CLANG linker script (v6clang.ld)"

# O-LLD: ld.lld native linker integration (V6CLANG arch backend)
if (-not (Test-Path "$root\llvm-project\lld\ELF\Arch")) { New-Item -ItemType Directory -Path "$root\llvm-project\lld\ELF\Arch" -Force > $null }
xcopy /Y /I "$root\lld\ELF\Arch\V6Clang.cpp" "$root\llvm-project\lld\ELF\Arch\" > $null
xcopy /Y /I "$root\lld\ELF\Target.cpp" "$root\llvm-project\lld\ELF\" > $null
xcopy /Y /I "$root\lld\ELF\Target.h" "$root\llvm-project\lld\ELF\" > $null
xcopy /Y /I "$root\lld\ELF\Driver.cpp" "$root\llvm-project\lld\ELF\" > $null
xcopy /Y /I "$root\lld\ELF\Config.h" "$root\llvm-project\lld\ELF\" > $null
xcopy /Y /I "$root\lld\ELF\MapFile.cpp" "$root\llvm-project\lld\ELF\" > $null
xcopy /Y /I "$root\lld\ELF\Options.td" "$root\llvm-project\lld\ELF\" > $null
xcopy /Y /I "$root\lld\ELF\CMakeLists.txt" "$root\llvm-project\lld\ELF\" > $null
xcopy /Y /I "$root\lld\ELF\LinkerScript.cpp" "$root\llvm-project\lld\ELF\" > $null
xcopy /Y /I "$root\lld\ELF\InputSection.cpp" "$root\llvm-project\lld\ELF\" > $null
xcopy /Y /I "$root\lld\ELF\V6ClangPackedSections.cpp" "$root\llvm-project\lld\ELF\" > $null
xcopy /Y /I "$root\lld\ELF\V6ClangPackedSections.h" "$root\llvm-project\lld\ELF\" > $null
Write-Host "  [OK] lld/ELF V6CLANG backend and packed-section layout"

# V6CLANG packed-section unit tests
if (-not (Test-Path "$root\llvm-project\lld\unittests\AsLibELF")) { New-Item -ItemType Directory -Path "$root\llvm-project\lld\unittests\AsLibELF" -Force > $null }
xcopy /Y /I "$root\lld\unittests\AsLibELF\CMakeLists.txt" "$root\llvm-project\lld\unittests\AsLibELF\" > $null
xcopy /Y /I "$root\lld\unittests\AsLibELF\V6ClangPackedSectionsTest.cpp" "$root\llvm-project\lld\unittests\AsLibELF\" > $null
Write-Host "  [OK] lld V6CLANG packed-section unit tests"

# V6CLANG resource-dir headers (string.h, stdlib.h, v6clang.h)
$resourceInclude = "$root\clang\lib\Driver\ToolChains\V6Clang\include"
if (Test-Path $resourceInclude) {
    robocopy $resourceInclude "$root\llvm-project\clang\lib\Driver\ToolChains\V6Clang\include" /MIR /NFL /NDL /NJH /NJS > $null
    if ($LASTEXITCODE -gt 7) { throw "Failed to populate V6CLANG resource headers (robocopy exit $LASTEXITCODE)" }
    Write-Host "  [OK] V6CLANG resource-dir headers (string.h, stdlib.h, v6clang.h)"
} else {
    Write-Host "  [SKIP] Optional V6CLANG resource-dir headers are not present"
}

Write-Host ""
Write-Host "Populate complete. llvm-project/ is ready to build."
Write-Host "Next: cmake + ninja (see docs/V6ClangBuildGuide.md)"
$global:LASTEXITCODE = 0
