// RUN: clang -target i8080-unknown-v6clang -fsyntax-only %s 2>&1 | FileCheck %s
//
// Verify that the V6CLANG target warns about expensive types that require
// software emulation on the 8-bit i8080 architecture.

// CHECK: warning: use of 'long long' is expensive on target 'i8080-unknown-v6clang'
// CHECK-SAME: [-Wv6clang-expensive-type]
long long expensive_ll(long long x) { return x; }

// CHECK: warning: use of 'float' is expensive on target 'i8080-unknown-v6clang'
// CHECK-SAME: [-Wv6clang-expensive-type]
float expensive_float(float x) { return x; }

// CHECK: warning: use of 'double' is expensive on target 'i8080-unknown-v6clang'
// CHECK-SAME: [-Wv6clang-expensive-type]
double expensive_double(double x) { return x; }

// Normal types should not warn.
// CHECK-NOT: warning:{{.*}}char
// CHECK-NOT: warning:{{.*}}'int'
// CHECK-NOT: warning:{{.*}}short
char ok_char(char x) { return x; }
short ok_short(short x) { return x; }
int ok_int(int x) { return x; }
