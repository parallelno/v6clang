// Conditional Call Optimization — O15 feature test
//
// Tests that `if (c) foo();` with a parameterless callee lowers to a
// single conditional CALL (CNZ / CZ / CC / CNC / CP / CM) instead of
// `Jcc skip; CALL foo;`.
//
// Why parameterless callees:
// Argument setup (e.g. MVI A, N for poke(N)) is emitted inside the
// call basic block by ISel. The conditional-call fold is only legal
// when the call block contains exactly the CALL instruction (anything
// else couldn't be hoisted across the inverted condition without
// changing semantics on the skip path). So the canonical pattern that
// triggers the fold uses a void-arg callee.
//
// Each `cb_*` body has work AFTER the conditional call so the call
// itself is not at the function tail (otherwise it becomes a
// conditional tail JMP via O23, not the C-prefix opcodes we want).

#include <stdint.h>

extern void notify(void);
extern uint8_t observed;

// 1. Equality (x == 0) -> expect CNZ notify
__attribute__((noinline))
uint8_t cb_eq(uint8_t x) {
    if (x == 0) notify();
    return observed + 1;
}

// 2. Inequality (x != 0) -> expect CZ notify
__attribute__((noinline))
uint8_t cb_ne(uint8_t x) {
    if (x != 0) notify();
    return observed + 1;
}

// 3. Unsigned LT -> expect CC notify
__attribute__((noinline))
uint8_t cb_ult(uint16_t x) {
    if (x < 100u) notify();
    return observed + 1;
}

// 4. Unsigned GE -> expect CNC notify
__attribute__((noinline))
uint8_t cb_uge(uint16_t x) {
    if (x >= 100u) notify();
    return observed + 1;
}

// 5. Signed LT 0 -> expect CM notify
__attribute__((noinline))
uint8_t cb_slt(int16_t x) {
    if (x < 0) notify();
    return observed + 1;
}

// 6. Signed GE 0 -> expect CP notify
__attribute__((noinline))
uint8_t cb_sge(int16_t x) {
    if (x >= 0) notify();
    return observed + 1;
}

// Negative: return value consumed -> fold must NOT fire (CallBB has a
// result COPY in addition to the CALL).
extern uint8_t produce(void);

__attribute__((noinline))
uint8_t cb_value_used(uint8_t x) {
    uint8_t v = 7;
    if (x) v = produce();
    return v + observed;
}

uint8_t observed;

__attribute__((noinline))
void notify(void) { observed += 1; }

__attribute__((noinline))
uint8_t produce(void) { return observed + 5; }

int main(void) {
    cb_eq(0);
    cb_ne(1);
    cb_ult(50);
    cb_uge(200);
    cb_slt(-1);
    cb_sge(0);
    return cb_value_used(5) + observed;
}
