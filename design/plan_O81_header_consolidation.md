# Plan: V6CLANG Header Consolidation (O81)

One source of truth, one model, one search path.

## Problem Summary

The V6CLANG toolchain currently maintains **two** include directories:

| Directory | Headers |
|---|---|
| `clang/lib/Driver/ToolChains/V6CLANG/include/` | `string.h` (decls only), `stdlib.h` (abort/exit), `v6clang.h` |
| `compiler-rt/lib/builtins/v6clang/include/` | `string.h` (full V6CLANG_RT definitions), `stdlib.h` (min/max/abs/labs), `v6clang_arith.h`, `v6clang_rt_macros.h` |

Both are added as `-internal-isystem`, resource-dir first. This means:
- `#include <string.h>` resolves to the **declarations-only** copy → no
  definitions → `undefined symbol: memset` at link time.
- The compiler-rt `string.h` (full inline-asm bodies) is **silently shadowed**.
- `#include <stdlib.h>` resolves to the resource-dir copy → no `min`/`max`.
- The two `stdlib.h` files split related content across locations with no
  clear rule.
- `v6clang.h` lives only in the resource-dir but is documented as a runtime header.

The workaround (`-isystem compiler-rt\lib\builtins\v6clang\include` in build
scripts) flips precedence but is fragile and surprising.

## Design

### 1. Single header location: `compiler-rt/lib/builtins/v6clang/include/`

This is where the runtime lives (alongside `crt0.s`), and where `v6clang_arith.h`
and `v6clang_rt_macros.h` already live. `clang/lib/Driver/ToolChains/V6CLANG/include/`
is deleted entirely: its `string.h` is a dead declarations-only stub, and its
`stdlib.h` and `v6clang.h` are moved/merged into the compiler-rt directory.

### 2. One model: `V6CLANG_RT` header-only inline-asm (the `v6clang_arith.h` pattern)

Every runtime routine is a `naked noinline used annotate("v6clang-rt-helper")`
definition in a header. Properties:
- Definition present in every TU that `#include`s it → no link error possible.
- `used` keeps the symbol alive; `--gc-sections` strips it if no caller
  references it → no ROM bloat.
- Same call shape as a normal function (HL/DE/BC reg-pass CC) → call sites
  coalesce at link time.

### 3. Canonical header set

| Header | Provides |
|---|---|
| `<string.h>` | `memcpy`, `memset`, `memmove`, `strlen`, `strcmp`, `strcpy` — already correct in compiler-rt. Opt-in via `#include`. |
| `<stdlib.h>` | `EXIT_SUCCESS`/`EXIT_FAILURE`, `abort()`, `exit()` (standard C) + `abs`, `labs` (standard C) + `min`, `max` (embedded convenience). |
| `<v6clang.h>` | `__v6clang_in/out/di/ei/hlt/nop` wrappers around `__builtin_v6clang_*`. Moved from resource-dir. |
| `v6clang_arith.h` | Math libcalls (`__mulhi3`, etc.). Unchanged, auto-included by driver. |
| `v6clang_rt_macros.h` | `V6CLANG_RT` macro. Unchanged, internal. |

`min`/`max` stay in `<stdlib.h>` rather than a separate `<sys/param.h>` —
they are common on bare-metal/embedded targets and are placed where users
on this platform expect them.

### 4. Driver wiring — one path, one auto-include rule

In `clang/lib/Driver/ToolChains/V6Clang.cpp`:
- Delete `findV6ClangIncludeDir` and its `-internal-isystem` push entirely.
- Keep `findV6ClangRuntimeIncludeDir` as the **only** runtime include path.
- Keep the auto-`-include v6clang_arith.h` exactly as is.
- No auto-include of `<string.h>`. Users include it explicitly — standard
  practice. No `v6clang_freestanding.h` umbrella is needed.

### 5. Install / packaging

The build system copies `compiler-rt/lib/builtins/v6clang/include/*` to
`<resource-dir>/lib/v6clang/include/` at install time. `findV6ClangRuntimeIncludeDir`
already searches both locations → no driver change needed. The resource-dir
directory becomes a **pure install artifact**, never authored by hand.

## What this fixes

- One `string.h`, one `stdlib.h` — no shadowing, no duplication.
- Standard headers contain standard contents; `min`/`max` are in `<stdlib.h>`
  where embedded users expect them.
- `memset` link error without `-isystem` is gone: `#include <string.h>`
  resolves to the full inline-asm definition.
- The `-isystem compiler-rt\lib\builtins\v6clang\include` workaround in
  `build.bat` can be deleted.
- Same `V6CLANG_RT` model as `v6clang_arith.h` — one mental model for the whole
  runtime.

## Files affected

| Action | File |
|---|---|
| **Delete** | `clang/lib/Driver/ToolChains/V6CLANG/include/` (entire directory) |
| **Edit** | `clang/lib/Driver/ToolChains/V6Clang.cpp` — remove `findV6ClangIncludeDir` and its `-internal-isystem` push from `AddClangSystemIncludeArgs` |
| **Edit** | `compiler-rt/lib/builtins/v6clang/include/stdlib.h` — add `EXIT_SUCCESS`/`EXIT_FAILURE`, `abort()`, `exit()` (moved from resource-dir); `abs`/`labs`/`min`/`max` already present |
| **New** | `compiler-rt/lib/builtins/v6clang/include/v6clang.h` — moved verbatim from `clang/lib/Driver/ToolChains/V6CLANG/include/v6clang.h` |
| **Edit** | `temp/demo/build.bat` — remove `-isystem compiler-rt\lib\builtins\v6clang\include` |
| **Edit** | `docs/V6ClangUsage.md` — update header table and location notes |

## Steps

### Step 1 — Extend `compiler-rt/.../stdlib.h`

Edit `compiler-rt/lib/builtins/v6clang/include/stdlib.h`. Add from the
resource-dir copy:
- `EXIT_SUCCESS` / `EXIT_FAILURE` macros.
- `abort()` — `noreturn`, `static inline always_inline`, infinite `HLT` loop.
- `exit(int)` — `noreturn`, ignores status, infinite `HLT` loop.

The file already has `abs`/`labs`/`min`/`max` — leave them as-is.

### Step 2 — Move `v6clang.h`

Copy `clang/lib/Driver/ToolChains/V6CLANG/include/v6clang.h` verbatim to
`compiler-rt/lib/builtins/v6clang/include/v6clang.h`. No content changes.

### Step 3 — Edit `V6Clang.cpp`

In `AddClangSystemIncludeArgs`, remove the `findV6ClangIncludeDir` block and
its two `CC1Args.push_back` calls. Delete `findV6ClangIncludeDir` entirely.
`findV6ClangRuntimeIncludeDir` and its push remain unchanged.

### Step 4 — Delete `clang/lib/Driver/ToolChains/V6CLANG/include/`

Remove all three files (`string.h`, `stdlib.h`, `v6clang.h`) and the directory.

### Step 5 — Fix `build.bat`

Remove `-isystem compiler-rt\lib\builtins\v6clang\include` from
`temp/demo/build.bat`. Search for the same flag in other scripts and
remove it there too.

### Step 6 — Update `docs/V6ClangUsage.md`

- Update the header table: single-source note, add `<v6clang.h>` row, update
  `<stdlib.h>` row to list all contents.
- Remove any mention of `clang/lib/Driver/ToolChains/V6CLANG/include/`.

### Step 7 — Extend `scripts/validate_dist.ps1` (CI smoke test)

`validate_dist.ps1` is invoked by `release.yml` ("Smoke-test staged tree"
step) after `make_dist.ps1` stages the distribution. Currently it only
compiles a trivial `smoke.c` that uses no runtime headers. After O81, the
staged `lib/v6clang/include/` must contain `string.h`, `stdlib.h` (extended),
and `v6clang.h` — none of which are tested by the current smoke test.

**Why `make_dist.ps1` needs no changes**: it already copies
`compiler-rt/lib/builtins/v6clang/include/*` → `<stage>/lib/clang/<ver>/lib/v6clang/include/`
(the `$RtIncSrcDir` block, added in O80). It never referenced
`clang/lib/Driver/ToolChains/V6CLANG/include/`, so deleting that directory
does not affect the packaging script at all.

**Add two new tests to `validate_dist.ps1`**, after the existing smoke
compile and before the resource-dir path assertions:

**Test A — `<string.h>` from installed layout, no `-isystem`**

Compile a source that calls `memset` and `memcpy` using only the staged
`clang.exe` with no extra flags:

```c
// string_smoke.c
#include <stdint.h>
#include <string.h>
int main(void) {
    uint8_t buf[4];
    memset(buf, 0xAB, 4);
    __builtin_v6clang_out(0xED, buf[0]);
    __builtin_v6clang_hlt();
    return 0;
}
```

Compile: `clang --target=i8080-unknown-v6clang -O2 string_smoke.c -o string_smoke.rom`

Run in emulator and assert `TEST_OUT port=0xED value=0xAB` and `HALT`.

**Test B — `<stdlib.h>` from installed layout, no `-isystem`**

Compile a source that uses `min` and `abs`:

```c
// stdlib_smoke.c
#include <stdint.h>
#include <stdlib.h>
int main(void) {
    uint8_t x = (uint8_t)min(200, 100);  // expects 100 = 0x64
    __builtin_v6clang_out(0xED, x);
    __builtin_v6clang_hlt();
    return 0;
}
```

Compile: `clang --target=i8080-unknown-v6clang -O2 stdlib_smoke.c -o stdlib_smoke.rom`

Run in emulator and assert `TEST_OUT port=0xED value=0x64` and `HALT`.

**Also add a file-existence check** for the new headers in the staged tree
(alongside the existing `v6clang.ld` and `crt0.o` checks):

```powershell
$expectedStringH  = Join-Path $resDir 'lib\v6clang\include\string.h'
$expectedStdlibH  = Join-Path $resDir 'lib\v6clang\include\stdlib.h'
$expectedV6ClangH     = Join-Path $resDir 'lib\v6clang\include\v6clang.h'
foreach ($h in @($expectedStringH, $expectedStdlibH, $expectedV6ClangH)) {
    if (-not (Test-Path $h)) { throw "Header not in staged tree: $h" }
}
```

**Local pre-flight** (run before pushing the branch):

```powershell
# 1. Re-stage with current build
pwsh scripts/make_dist.ps1 -Version test-O81

# 2. Run validate_dist (includes the new header tests)
pwsh scripts/validate_dist.ps1 -Stage dist/v6clang-test-O81-windows-x64

# 3. Also confirm temp/demo builds clean without -isystem
# (edit build.bat to remove the flag first — Step 5 above)
temp\demo\build.bat
```

All three must exit 0 before merging.
