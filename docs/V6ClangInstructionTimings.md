# V6CLANG Instruction Timings

Instruction cycle costs for the Intel 8080 / KR580VM80A on the Vector 06c (3 MHz clock).
Cross-referenced with TableGen `SchedWriteRes` names from `V6ClangSchedule.td`.

## Scheduling Model

| Property | Value |
|----------|-------|
| MicroOpBufferSize | 0 (strictly in-order) |
| IssueWidth | 1 (single-issue) |
| LoadLatency | 2 (cost units) |
| CompleteModel | 0 (allow unscheduled instructions) |

## SchedWrite Resources

| SchedWrite | Cycles | Latency (cost units) | Description |
|------------|--------|----------------------|-------------|
| WriteALU4 | 4 | 1 | ALU reg-reg, rotate, misc single-byte |
| WriteALU8 | 8 | 2 | ALU mem/imm, INR/DCR reg, SPHL, PCHL, HLT |
| WriteMOV8 | 8 | 2 | MOV r,r; MOV r,M; MOV M,r; MVI r,d8; LDAX; STAX |
| WriteINX8 | 8 | 2 | INX, DCX (16-bit inc/dec) |
| WriteDAD12 | 12 | 3 | DAD, INR M, DCR M, POP, IN, OUT |
| WriteMOV16 | 12 | 3 | MVI M,d8 |
| WriteLXI12 | 12 | 3 | LXI rp,d16 |
| WritePUSH16 | 16 | 4 | PUSH, LDA, STA, RST |
| WriteBR12 | 12 | 3 | JMP, conditional branch |
| WriteRET12 | 12 | 3 | RET (unconditional) |
| WriteCondRET | 8/16 | 4 | Rcc (not-taken/taken) |
| WriteLHLD20 | 20 | 5 | LHLD, SHLD |
| WriteCALL24 | 24 | 6 | CALL, XTHL |

## Instruction Timing Table

### Data Transfer

| Mnemonic | Bytes | Cycles | SchedWrite | Notes |
|----------|-------|--------|------------|-------|
| MOV r,r | 1 | 8 | WriteMOV8 | Register to register (Vector-06c: same cost as MOV r,M) |
| MOV r,M | 1 | 8 | WriteMOV8 | Memory (HL) to register |
| MOV M,r | 1 | 8 | WriteMOV8 | Register to memory (HL) |
| MVI r,d8 | 2 | 8 | WriteMOV8 | Immediate to register |
| MVI M,d8 | 2 | 12 | WriteMOV16 | Immediate to memory (HL) |
| LDA a16 | 3 | 16 | WritePUSH16 | Load A from direct address |
| STA a16 | 3 | 16 | WritePUSH16 | Store A to direct address |
| LDAX rp | 1 | 8 | WriteMOV8 | Load A from (rp) |
| STAX rp | 1 | 8 | WriteMOV8 | Store A to (rp) |
| LHLD a16 | 3 | 20 | WriteLHLD20 | Load HL from direct address |
| SHLD a16 | 3 | 20 | WriteLHLD20 | Store HL to direct address |
| LXI rp,d16 | 3 | 12 | WriteLXI12 | Load immediate 16-bit |
| XCHG | 1 | 4 | WriteALU4 | Exchange DE ↔ HL |

### Stack Operations

| Mnemonic | Bytes | Cycles | SchedWrite | Notes |
|----------|-------|--------|------------|-------|
| PUSH rp | 1 | 16 | WritePUSH16 | Push register pair |
| POP rp | 1 | 12 | WriteDAD12 | Pop register pair |
| SPHL | 1 | 8 | WriteALU8 | SP ← HL |
| XTHL | 1 | 24 | WriteCALL24 | Exchange (SP) ↔ HL |

### ALU — 8-bit Register

| Mnemonic | Bytes | Cycles | SchedWrite | Notes |
|----------|-------|--------|------------|-------|
| ADD r | 1 | 4 | WriteALU4 | A ← A + r |
| ADC r | 1 | 4 | WriteALU4 | A ← A + r + CY |
| SUB r | 1 | 4 | WriteALU4 | A ← A − r |
| SBB r | 1 | 4 | WriteALU4 | A ← A − r − CY |
| ANA r | 1 | 4 | WriteALU4 | A ← A & r |
| XRA r | 1 | 4 | WriteALU4 | A ← A ^ r |
| ORA r | 1 | 4 | WriteALU4 | A ← A | r |
| CMP r | 1 | 4 | WriteALU4 | Compare A − r (flags only) |

### ALU — 8-bit Memory (HL)

| Mnemonic | Bytes | Cycles | SchedWrite | Notes |
|----------|-------|--------|------------|-------|
| ADD M | 1 | 8 | WriteALU8 | A ← A + (HL) |
| ADC M | 1 | 8 | WriteALU8 | A ← A + (HL) + CY |
| SUB M | 1 | 8 | WriteALU8 | A ← A − (HL) |
| SBB M | 1 | 8 | WriteALU8 | A ← A − (HL) − CY |
| ANA M | 1 | 8 | WriteALU8 | A ← A & (HL) |
| XRA M | 1 | 8 | WriteALU8 | A ← A ^ (HL) |
| ORA M | 1 | 8 | WriteALU8 | A ← A | (HL) |
| CMP M | 1 | 8 | WriteALU8 | Compare A − (HL) (flags only) |

### ALU — 8-bit Immediate

| Mnemonic | Bytes | Cycles | SchedWrite | Notes |
|----------|-------|--------|------------|-------|
| ADI d8 | 2 | 8 | WriteALU8 | A ← A + d8 |
| ACI d8 | 2 | 8 | WriteALU8 | A ← A + d8 + CY |
| SUI d8 | 2 | 8 | WriteALU8 | A ← A − d8 |
| SBI d8 | 2 | 8 | WriteALU8 | A ← A − d8 − CY |
| ANI d8 | 2 | 8 | WriteALU8 | A ← A & d8 |
| XRI d8 | 2 | 8 | WriteALU8 | A ← A ^ d8 |
| ORI d8 | 2 | 8 | WriteALU8 | A ← A | d8 |
| CPI d8 | 2 | 8 | WriteALU8 | Compare A − d8 (flags only) |

### ALU — 16-bit

| Mnemonic | Bytes | Cycles | SchedWrite | Notes |
|----------|-------|--------|------------|-------|
| DAD rp | 1 | 12 | WriteDAD12 | HL ← HL + rp |
| INX rp | 1 | 8 | WriteINX8 | rp ← rp + 1 (no flags) |
| DCX rp | 1 | 8 | WriteINX8 | rp ← rp − 1 (no flags) |

### Increment / Decrement

| Mnemonic | Bytes | Cycles | SchedWrite | Notes |
|----------|-------|--------|------------|-------|
| INR r | 1 | 8 | WriteALU8 | r ← r + 1 |
| DCR r | 1 | 8 | WriteALU8 | r ← r − 1 |
| INR M | 1 | 12 | WriteDAD12 | (HL) ← (HL) + 1 |
| DCR M | 1 | 12 | WriteDAD12 | (HL) ← (HL) − 1 |

### Rotate

| Mnemonic | Bytes | Cycles | SchedWrite | Notes |
|----------|-------|--------|------------|-------|
| RLC | 1 | 4 | WriteALU4 | Rotate A left |
| RRC | 1 | 4 | WriteALU4 | Rotate A right |
| RAL | 1 | 4 | WriteALU4 | Rotate A left through carry |
| RAR | 1 | 4 | WriteALU4 | Rotate A right through carry |

### Branch

| Mnemonic | Bytes | Cycles | SchedWrite | Notes |
|----------|-------|--------|------------|-------|
| JMP a16 | 3 | 12 | WriteBR12 | Unconditional jump |
| JNZ a16 | 3 | 12 | WriteBR12 | Jump if not zero |
| JZ a16 | 3 | 12 | WriteBR12 | Jump if zero |
| JNC a16 | 3 | 12 | WriteBR12 | Jump if no carry |
| JC a16 | 3 | 12 | WriteBR12 | Jump if carry |
| JPO a16 | 3 | 12 | WriteBR12 | Jump if parity odd |
| JPE a16 | 3 | 12 | WriteBR12 | Jump if parity even |
| JP a16 | 3 | 12 | WriteBR12 | Jump if positive |
| JM a16 | 3 | 12 | WriteBR12 | Jump if minus |
| PCHL | 1 | 8 | WriteALU8 | PC ← HL |

### Call / Return

| Mnemonic | Bytes | Cycles | SchedWrite | Notes |
|----------|-------|--------|------------|-------|
| CALL a16 | 3 | 24 | WriteCALL24 | Unconditional call |
| CNZ a16 | 3 | 16/24 | WriteCALL24 | Call if not zero |
| CZ a16 | 3 | 16/24 | WriteCALL24 | Call if zero |
| CNC a16 | 3 | 16/24 | WriteCALL24 | Call if no carry |
| CC a16 | 3 | 16/24 | WriteCALL24 | Call if carry |
| CPO a16 | 3 | 16/24 | WriteCALL24 | Call if parity odd |
| CPE a16 | 3 | 16/24 | WriteCALL24 | Call if parity even |
| CP a16 | 3 | 16/24 | WriteCALL24 | Call if positive |
| CM a16 | 3 | 16/24 | WriteCALL24 | Call if minus |
| RET | 1 | 12 | WriteRET12 | Unconditional return |
| RNZ | 1 | 8/16 | WriteCondRET | Return if not zero |
| RZ | 1 | 8/16 | WriteCondRET | Return if zero |
| RNC | 1 | 8/16 | WriteCondRET | Return if no carry |
| RC | 1 | 8/16 | WriteCondRET | Return if carry |
| RPO | 1 | 8/16 | WriteCondRET | Return if parity odd |
| RPE | 1 | 8/16 | WriteCondRET | Return if parity even |
| RP | 1 | 8/16 | WriteCondRET | Return if positive |
| RM | 1 | 8/16 | WriteCondRET | Return if minus |

### RST (Restart)

| Mnemonic | Bytes | Cycles | SchedWrite | Notes |
|----------|-------|--------|------------|-------|
| RST n | 1 | 16 | WritePUSH16 | Call to 8×n |

### Miscellaneous

| Mnemonic | Bytes | Cycles | SchedWrite | Notes |
|----------|-------|--------|------------|-------|
| NOP | 1 | 4 | WriteALU4 | No operation |
| HLT | 1 | 8 | WriteALU8 | Halt processor |
| CMA | 1 | 4 | WriteALU4 | Complement A |
| STC | 1 | 4 | WriteALU4 | Set carry |
| CMC | 1 | 4 | WriteALU4 | Complement carry |
| DAA | 1 | 4 | WriteALU4 | Decimal adjust A |
| EI | 1 | 4 | WriteALU4 | Enable interrupts |
| DI | 1 | 4 | WriteALU4 | Disable interrupts |

### I/O

| Mnemonic | Bytes | Cycles | SchedWrite | Notes |
|----------|-------|--------|------------|-------|
| IN p8 | 2 | 12 | WriteDAD12 | A ← port |
| OUT p8 | 2 | 12 | WriteDAD12 | port ← A |

## Notes

- Conditional calls and returns have variable cycle counts:
  - **Not taken**: lower cycle count (condition not met, no call/return executed)
  - **Taken**: higher cycle count (includes stack push/pop and PC load)
- Conditional branches (Jcc) have a fixed cycle count of 12 regardless of whether the branch is taken.
- The scheduling model uses `CompleteModel = 0` to allow instructions without explicit scheduling info.
- Latency values in `WriteRes` are in abstract cost units (cycles ÷ 4), not raw clock cycles.
