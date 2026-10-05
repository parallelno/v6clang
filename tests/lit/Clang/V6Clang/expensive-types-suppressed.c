// RUN: clang -target i8080-unknown-v6clang -fsyntax-only -Wno-v6clang-expensive-type %s 2>&1 | FileCheck %s --allow-empty
//
// Verify that -Wno-v6clang-expensive-type suppresses the warning.

// CHECK-NOT: warning:
long long no_warning(long long x) { return x; }
float no_warning_f(float x) { return x; }
