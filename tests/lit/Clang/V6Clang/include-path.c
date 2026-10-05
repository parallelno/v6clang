// RUN: clang -target i8080-unknown-v6clang -E %s -o - | FileCheck %s
// RUN: clang -target i8080-unknown-v6clang -O2 -S %s -o - | FileCheck %s --check-prefix=ASM
// RUN: clang -target i8080-unknown-v6clang -### -c %s 2>&1 | FileCheck %s --check-prefix=DRIVER
//
// DRIVER asserts the driver injects -internal-isystem pointing at the
// V6CLANG resource-dir include directory and emits -ffunction-sections by
// default. Honors -nostdinc / -fno-function-sections per Clang
// convention (covered by negative checks below).
//
// RUN: clang -target i8080-unknown-v6clang -nostdinc -### -c %s 2>&1 | FileCheck %s --check-prefix=NOSTDINC
// RUN: clang -target i8080-unknown-v6clang -fno-function-sections -### -c %s 2>&1 | FileCheck %s --check-prefix=NOFUNCSEC
//
// Phase 6: V6CLANG driver auto-injects <resource-dir>/lib/v6clang/include/ so
// `<string.h>`, `<stdlib.h>`, `<v6clang.h>` resolve without any -I flag.
// Also verify -ffunction-sections is on by default (per-function ELF
// sections so ld.lld --gc-sections can prune unreachable helpers).

#include <string.h>
#include <stdlib.h>
#include <v6clang.h>

// CHECK: void *memcpy(
// CHECK: void *memset(
// CHECK: void abort(
// CHECK: v6clang_out(

void test_use(char *p) {
    memset(p, 0, 4);
    v6clang_out(0xED, 0x42);
}

// ASM: .section{{.*}}.text.test_use

// DRIVER: -ffunction-sections
// DRIVER: -internal-isystem
// DRIVER-SAME: v6clang
// DRIVER-SAME: include

// NOSTDINC-NOT: ToolChains{{[/\\]+}}v6clang{{[/\\]+}}include"

// NOFUNCSEC-NOT: -ffunction-sections
