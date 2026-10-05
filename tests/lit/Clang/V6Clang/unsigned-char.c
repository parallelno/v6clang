// RUN: clang -target i8080-unknown-v6clang -O1 -S -emit-llvm %s -o - | FileCheck %s
//
// Verify char is unsigned by default (design §2.3).

// char should be unsigned → comparing char to -1 should never be true.
int test_unsigned_char(char c) {
  if (c < 0)
    return 1;
  return 0;
}
// The comparison c < 0 on unsigned char is always false;
// with unsigned char, c < 0 is always false so the function returns 0.
// CHECK: define {{.*}} @test_unsigned_char
// CHECK: ret i16 0
