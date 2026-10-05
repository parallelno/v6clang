// RUN: clang -target i8080-unknown-v6clang -O0 -S -mllvm -mv6clang-annotate-pseudos %s -o - | FileCheck %s

#include <stdint.h>

extern void sink(uint8_t);

__attribute__((noinline))
uint16_t sum3_correct(const uint8_t *p) {
  return (uint16_t)p[0] + (uint16_t)p[1] + (uint16_t)p[2];
}

__attribute__((noinline))
uint16_t sum3_proposed(const uint8_t *p) {
  uint8_t acc = p[0];
  acc += p[1];
  acc += p[2];
  return (uint16_t)acc;
}

void main(void) {
  static const uint8_t overflow[3] = {200, 200, 200};
  static const uint8_t no_overflow[3] = {50, 60, 70};

  uint16_t correct = sum3_correct(overflow);
  uint16_t proposed = sum3_proposed(overflow);
  uint16_t correct2 = sum3_correct(no_overflow);
  uint16_t proposed2 = sum3_proposed(no_overflow);

  uint8_t disagree = (correct != proposed) ? 1 : 0;
  uint8_t agree = (correct2 == proposed2) ? 0 : 1;

  sink(disagree | agree);
}

// Regression: the select for `(correct != proposed) ? 1 : 0` can spill the
// false value between CMP16 and the inverted JZ. `MVI A,0 -> XRA A` must not
// fire there, because XRA A overwrites Z and makes the JZ unconditional.
// CHECK-LABEL: main:
// CHECK:       ;--- V6CLANG_CMP16 ---
// CHECK:       SBB{{[ 	]+}}D
// CHECK-NOT:   XRA{{[ 	]+}}A
// CHECK:       JZ