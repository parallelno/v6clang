// RUN: clang -target i8080-unknown-v6clang -S -emit-llvm %s -o - | FileCheck %s
//
// Verify that inline assembly constraints are accepted for the V6CLANG target.
// Tests at IR level since the V6CLANG backend does not yet have an MC asm parser.

void test_simple_asm(void) {
// CHECK-LABEL: @test_simple_asm
// CHECK: call void asm sideeffect "NOP"
    asm volatile("NOP");
}

unsigned char test_acc_output(void) {
// CHECK-LABEL: @test_acc_output
// CHECK: call i8 asm sideeffect "IN 0x10", "=a"
    unsigned char val;
    asm volatile("IN 0x10" : "=a"(val));
    return val;
}

void test_acc_input(unsigned char val) {
// CHECK-LABEL: @test_acc_input
// CHECK: call void asm sideeffect "OUT 0x20", "a"
    asm volatile("OUT 0x20" : : "a"(val));
}
