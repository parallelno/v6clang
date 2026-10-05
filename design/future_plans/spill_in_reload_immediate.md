# V6CLANG Adaptation of the llvm-mos Spilling

## Problem

Spilling + reloading on V6CLANG takes significant CPU time.

## Current spilling implementation:

**Example 1**
tests\features\20\v6clang_xchg.asm, interleaved_add func.
```
interleaved_add:
  ...
	;--- V6CLANG_SPILL16 ---
	PUSH	HL
	LXI	HL, __v6clang_ss.interleaved_add+2
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
```

**Example 2**
tests\features\20\v6clang_xchg.asm, interleaved_add func.
```
interleaved_add:
  ...
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	__v6clang_ss.interleaved_add
	XCHG
	;--- V6CLANG_SPILL16 ---
```



### Soft stack path (frame pointer based):

Emits MOS::LDStk / MOS::STStk pseudos with frame index, lowered during frame index elimination.

---

## V6CLANG Current vs. llvm-mos Spilling: Side-by-Side

### Current V6CLANG Architecture (Two-Phase)

* Phase 1
RA calls storeRegToStackSlot → emits opaque pseudo (V6CLANG_SPILL8, V6CLANG_SPILL16, etc.) with Defs = [FLAGS] only. RA sees these as cheap, non-clobbering instructions.

* Phase 2
EliminateFrameIndex runs post-RA, expands pseudos into real instructions. This is where the complexity lives: 14+ different expansion paths depending on which register is being spilled, whether HL/DE is dead (O42 optimization), etc. The expansion silently clobbers HL (via PUSH HL/LXI HL/POP HL) or DE, but the RA never knew about it.

### llvm-mos Architecture (Single-Phase, Static Stack)
storeRegToStackSlot emits real instructions directly — STAbs/LDAbs with frame indices. When a non-GPR needs spilling, it creates a vreg for the routing copy, so the RA sees and allocates it. No post-RA pseudo expansion needed for static stack spills at all.

### The Fundamental Difference
llvm-mos can emit vregs in storeRegToStackSlot because MOS uses GlobalISel, where register allocation happens later in a different way, and their storeRegToStackSlot is called during RA when vregs are still valid. The RA sees the vreg, allocates a GPR for it, done.


V6CLANG uses SelectionDAG + RegAllocGreedy (standard LLVM pipeline). In this pipeline, storeRegToStackSlot is called by the RA during allocation. You can't create new vregs inside storeRegToStackSlot because:

The RA is in the middle of processing the live interval map
New vregs would need allocation, which the RA isn't set up to handle re-entrantly
After greedy RA, VirtRegMap doesn't expect new vregs to appear
So the MOS trick of "create a vreg for scratch, let RA handle it" doesn't directly port to V6CLANG's pipeline.


### Cons / Risks
1. Can't directly copy the MOS "vreg in storeRegToStackSlot" trick — V6CLANG's pipeline doesn't support it. Must use split pseudos instead.

2. Pseudo proliferation — goes from 4 pseudos (SPILL8/16, RELOAD8/16) to ~12. Each needs expansion logic, testing, TD definitions.

3. RA eviction cascade correctness — must verify that RegAllocGreedy actually handles Defs on spill instructions correctly and doesn't infinite-loop. LLVM's RA is designed for this (ARM/Thumb2 spills declare clobbers), but V6CLANG's extreme register scarcity (7 GPR8s) makes it an unusual stress test.

??????? Is Con 4 true? what about hldl/shld
4. H/L spilling is still ugly — no clean 2-instruction sequence exists. You need either DE as temp (clobbers DE) or route through A twice. The Defs declaration gets complex.

5. Non-static-stack functions — for functions that don't use V6ClangStaticStackAlloc, STA/SHLD aren't available (they need absolute addresses). Those functions still need SP-relative spilling via LXI HL + MOV M,r, which is back to clobbering HL.

6. Testing burden — every combination of register × liveness state needs verification under maximal pressure.

**Bottom Line**

The MOS approach validates the direction (honest clobbers, RA-aware spilling) but can't be copied mechanically because of the pipeline difference (GlobalISel vs SelectionDAG).


## Common code to store/restore the regs in I8080 ASM.

* A spilling.
STA ADDR - stores A into memory, no extra clobbers, 16cc
LDA ADDR - restores A from memory, no extra clobbers, 16cc

* HL spilling.
SHLD - stores HL into memory, no extra clobbers, 20cc
LHLD - restores HL from memory, no extra clobbers, 20cc

Other regs can be spilled in multiple ways. The best way depends on the spilling
reg and free regs.
Examples:

* DE spilling. HL is dead. 24cc
XCHG
SHLD ADDR

* DE spilling. HL is live. 28cc
XCHG
SHLD ADDR
XCHG

BC spilling, HL is dead. 36cc
MOV L, C
MOV H, B
SHLD ADDR

BC spilling. HL is live, A is dead. 48cc
MOV A, C
STA ADDR1
MOV A, B
STA ADDR1+1

BC spilling. HL is live, A is live. 64cc
PUSH H
MOV L, C
MOV H, B
SHLD ADDR
POP H

When we make spilling honest, the spilling logic should not worry about preserving
live reg. It should only contain the spilling logic and honestly defines what regs
it needs for a spill. RA must provide required regs for a spill. Another complexity
is the multiple paths to spill DE and BC regs. Each path needs their own set of
extra regs and the CPU sycles. To select the best path, RA needs take the Defs and the CPU cycles into account.
To solve that problem we can define multiiple specialized pseudos for each register
or a reg pair.

#### Example 1: DE spill.
We have two pseudos:
1. V6CLANG_SPILL16_DE1, Defs=[], 28cc
XCHG
SHLD ADDR
XCHG
2. V6CLANG_SPILL16_DE2, Defs=[HL], 24cc
XCHG
SHLD ADDR

When HL is dead, RA can use V6CLANG_SPILL16_DE2 because it uses less CC.
When HL is live, RA has no choice but using V6CLANG_SPILL16_DE1.


#### Example 2: BC Spill.
We have three pseudos:
1. V6CLANG_SPILL16_BC1, Defs=[HL], 36cc
MOV L, C
MOV H, B
SHLD ADDR

2. V6CLANG_SPILL16_BC2, Defs=[A], 48cc
MOV A, C
STA ADDR1
MOV A, B
STA ADDR1+1

When A and HL live, RA uses the cjeapest V6CLANG_SPILL16_BC1
When A live, but HL dead, RA uses V6CLANG_SPILL16_BC2
When A and HL dead, RA uses the cheapest V6CLANG_SPILL16_BC2 and apply eviction
mechanism to find the required reg pair for a spill.


### Notes

#### PUSH & POP for Spilling
LIFO: I can't be used directly for spilling because RA stores/restores regs in non
LIFO order.
PUSH Rp - stores the reg pair into stack, no extra clobbers, 16cc
POP  Rp - restores the reg pair from stack, no extra clobbers, 12cc

#### What is RegAllocGreedy (RA)
The RA's entire job is mapping vregs → physical registers. It maintains:

- Live intervals for every vreg (where it's live in the program)
- Interference with physical registers — if an instruction has Defs = [HL], the RA records that physical register $HL is clobbered at that point. Any vreg assigned to $HL whose live range crosses that point interferes with it and must be evicted or split.
- Register classes — each vreg has a set of allowed physical registers it can be assigned to
- RegUnit interference matrix — tracks exactly which physical register units are occupied at every program point

#### How Defs Interact With RA
When you write Defs = [HL] on a pseudo instruction:

The RA sees: "at this program point, physical register $HL is written." If some vreg %v5 is currently assigned to $HL and is live across this instruction, the RA must either:

- Evict %v5 from $HL and reassign it elsewhere
- Split %v5's live range around this point
- Spill %v5 before and reload after

This is standard RA machinery — it handles physical register clobbers from CALL instructions, inline asm, and any instruction with implicit defs the exact same way.

#### Eviction
Eviction removes a vreg entirely from its assigned physical register and reassigns it. The evicted vreg goes back onto the allocation worklist and must find a new home — either a different physical register, or it gets spilled to memory (store before, reload after every use).

```
Before:  %v5 in $HL across the whole function
After:   %v5 kicked out of $HL, re-queued, likely spilled everywhere
```

#### Splitting
Splitting cuts a vreg's live range into pieces so that only the conflicting piece moves. The vreg keeps its register everywhere except around the interference point.

Example — %v5 is in $HL for a long range, but a V6CLANG_SPILL8_REG at instruction 50 clobbers HL:

Before eviction:
  %v5 [$HL]: ████████████████████████  (inst 10-90)
  Clobber at inst 50:       ╳

```
After SPLIT:
  %v5a [$HL]: ███████████             (inst 10-49)
  %v5b [$HL]:              ███████████ (inst 51-90)

  At inst 49: STORE %v5a → stack      (spill just once)
  At inst 51: LOAD  %v5b ← stack      (reload just once)

After EVICT:
  %v5 → entire range goes back to worklist
  → likely gets $DE (if free) or spilled EVERYWHERE it's used
```

#### Eviction vs Splitting
Eviction	Splitting
Granularity	Whole live range	Surgical — only around conflict
Copies generated	Potentially many (every use/def needs reload)	Just 1 store + 1 reload at the split point
When it wins	Short live range, few uses	Long live range with a single conflict point
Implementation	Simple — re-queue vreg	Complex — creates new vregs, inserts copies

**In Practice**
RegAllocGreedy tries splitting first (via trySplit()) before falling back to eviction. This is one of its main advantages over the simpler RegAllocBasic. For V6CLANG with only 7 GPR8 registers, splitting is especially valuable — it lets the RA keep a vreg in HL for 90% of its lifetime and only briefly save/restore it around one conflicting instruction, rather than giving up HL entirely.

#### LLVM-MOS under register pressure

***Eviction Decision***
When the RA calls tryEvict() for an unallocated vreg V_new:

- Iterate over every physical register P
- For each P, collect all vregs currently assigned to P that interfere with V_new
- Check canEvictInterference(): V_new can evict V_old only if V_new.weight > V_old.weight (with some cascade-related tiebreakers)
- Among all candidate physical registers where eviction is legal, pick the one with the lowest total eviction cost (sum of evictee weights)

So "cheapest" = the physical register whose current occupant(s) have the lowest spill weight.

**In the MOS Cascade Scenario**
When the RA spills an Imag8 and creates vreg V2 (GPRRegClass), V2 has a tiny live interval (just the COPY + STAbs, ~2 instructions). Its spill weight is moderate-to-high because it's short-lived (small denominator). The RA looks at A, X, Y and evicts whichever current occupant has the lowest spill weight — typically the one with the longest remaining live range or fewest remaining uses.

#### MOS Cascade Under Full GPR Pressure
* Step 1: RA decides to spill vreg V1 (Imag8RegClass). Calls storeRegToStackSlot.
* Step 2: loadStoreByteStaticStackSlot sees V1 is not a GPR → creates a new vreg V2 in GPRRegClass:
```
Register Tmp = Builder.getMRI()->createVirtualRegister(&MOS::GPRRegClass);
// emits: COPY V2, V1   (Imag8 → GPR)
//        STAbs V2, [frame_idx]  (GPR → memory)
```

* Step 3: V2 goes back into the RA's allocation worklist. The RA tries to assign it to A, X, or Y. All three are live → RA evicts the cheapest one, say V3 which was in $Y.

* Step 4: V3 (GPRRegClass) needs spilling. storeRegToStackSlot is called for V3. This time, it's a GPR → takes the direct path:
```
// GPR detected → emit directly, no vreg needed:
Builder.buildInstr(MOS::STAbs).add(MO).addFrameIndex(...);
// Just:  STAbs $Y, [frame_idx2]
```
* Step 5: Done. No new vreg created. Cascade terminates.

**Why This Works**
The cascade always terminates because there are two tiers:
Tier	Register class	Spill path	Creates new vreg?
Leaf	GPR (A/X/Y)	STAbs directly	No
Non-leaf	Imag8	COPY to GPR vreg + STAbs	Yes → RA allocates it

A leaf spill never creates new vregs, so the recursion depth is exactly 1. The RA's eviction of a GPR always leads to a leaf spill.

#### What MOS Has That V6CLANG Doesn't
MOS explicitly enables this with:
```
Builder.getMF().getProperties().reset(MachineFunctionProperties::Property::NoVRegs);
```
This tells LLVM "yes, there are still vregs after this point, don't assert." MOS also has MOSPostRAScavenging as a safety net for any vregs that survive past the main RA. V6CLANG doesn't have either of these — adding them would be part of the adaptation work.

####  Reg Liveness info
Pseudo can request live interval detail (exact def/use slots).

**What Is and Isn't Available**
| Question | Answer |
| "Is HL live at instruction X inside a loop?" | Yes — LivePhysRegs gives correct answer because loop liveness is in the successor LiveIn sets |
| "Is HL live-in on the loop back-edge?" | Yes — MBB.LiveIns includes anything that crosses the back-edge |
| Cross-block queries | Not directly — LivePhysRegs only walks within one block at a time |
| Live interval detail (exact def/use slots) | Only if you also run LiveIntervals analysis, which post-RA peepholes can request |

#### Can You Use Languages Other Than C?
Yes. Any language whose frontend can emit LLVM IR works. The backend doesn't care what language produced the IR.

*Languages that work today with V6CLANG (via Clang):*
C, C++, Objective-C
Rust (uses LLVM backend natively)
Swift (uses LLVM)
Zig (uses LLVM)
D (ldc compiler)
Ada (GNAT via LLVM)

### Exmples of a bad code generated by the V6CLANG pseudos expansions:
;--- V6CLANG_LEA_FI ---
	LXI	DE, __v6clang_ss.main+4
	MOV	H, D
	MOV	L, E
Why no just:
    LXI	HL, __v6clang_ss.main+4


    LXI	HL, 0x140a
;--- V6CLANG_STORE16_P ---
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
Why not just:
    XCHG
    MOV M, E
    INX H
    MOV M, D
    DCX H
    XCHG

;--- V6CLANG_RELOAD16 ---
	PUSH	HL
	LXI	HL, __v6clang_ss.main+15
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL

Why not just:
    PUSH	HL
    LHLD __v6clang_ss.main+15
    MOV	C, L
    MOV	B, H
    POP HL


Or even better, let RA deside when HL requires preservation. If HL is dead,
we don't need PUSH/POP at all.



### Solutions

#### Solution 1
Honest-Defs split pseudos — The biggest win comes from V6CLANG_SPILL8_A (STA, zero clobber) and V6CLANG_SPILL16_HL, V6CLANG_SPILL16_DE (SHLD, zero clobber) being cascade terminators that guarantee no infinite eviction loops.

#### Solution 2
Regs and vres like LLVM-MOS has

#### Solution 3
Same as the current approach, but smarter spilling pseudos.

### Questions:

- What is ISel?
- What is GlobalISel?
- WHat is MIR?
- What os MBB walk?
- Explain GlobalISel vs SelectionDAG difference.
- fully honest spilling with all regs occupied can trigger cascade spillage to
free required reg. The worst case: spilling BC causing spilling HL. Result two
spilling and restoring instead of PUSH/POP in BC spilling (current implementation).
How often is it? Will that make new fully honest spilling less performant that
the original approach?
- llvm-mos spilling uses vregs. they
- what is V6CLANG_LEA_FI for?
- What is the full diagram of the llvm-mos design?
- What is the full diagram of the current spilling design?
- In `What MOS Has That V6CLANG Doesn't` you said: `tells LLVM "yes, there are still vregs after this point, don't assert."` and `MOS also has MOSPostRAScavenging as a safety net for any vregs that survive past the main RA`.
All your explanation of LLVM-MOS spilling before this line implied that there
is no need for such extra staff. Everything is honest to RA. Spilling has one pass.
Explain what is true and what is not in your here.
- does v6clang use mem2reg, inlining, loop unroll, GVN, LICM, ... opts?


---

## Research: Spill Into the Reload's Immediate Operand

### The Idea

Under **static stack allocation**, code lives at link-time-known addresses in
RAM (the Vector 06c runs code from RAM). The classical spill/reload pair

```
spill:   SHLD __v6clang_ss.f+N        ; HL -> data slot        20cc
...
reload:  LHLD __v6clang_ss.f+N        ; slot -> HL             20cc
```

can be collapsed by making the **reload instruction itself be the data slot**.
The spill patches the immediate operand of the reload (self-modifying code):

```
spill:   SHLD reload_site+1        ; HL -> imm16 of LXI    20cc
...
reload_site:
         LXI  HL, 0x0000           ; imm16 was patched     10cc
```

Invariants:
* `reload_site+1` is the absolute address of the first byte of the `imm16`
  field of `LXI HL, imm16` (opcode `0x21`, then lo, hi).
* After the spill, the LXI's immediate bytes equal the value written.
* The reload executes the patched LXI and materialises the value in HL.

The same construction works for any `imm16`/`imm8`-carrying instruction whose
immediate position is known:

| Reg  | Reload instruction | Opcode byte | imm addr  | Cost |
|------|--------------------|-------------|-----------|------|
| HL   | `LXI  HL, nn`      | `0x21`      | site+1    | 10cc |
| DE   | `LXI  DE, nn`      | `0x11`      | site+1    | 10cc |
| BC   | `LXI  BC, nn`      | `0x01`      | site+1    | 10cc |
| A    | `MVI  A,  n`       | `0x3E`      | site+1    | 7cc  |
| B    | `MVI  B,  n`       | `0x06`      | site+1    | 7cc  |
| C    | `MVI  C,  n`       | `0x0E`      | site+1    | 7cc  |
| D    | `MVI  D,  n`       | `0x16`      | site+1    | 7cc  |
| E    | `MVI  E,  n`       | `0x1E`      | site+1    | 7cc  |
| H    | `MVI  H,  n`       | `0x26`      | site+1    | 7cc  |
| L    | `MVI  L,  n`       | `0x2E`      | site+1    | 7cc  |

### Cycle/Size Comparison vs Current Spilling

Baseline assumes static stack (SHLD/LHLD/STA/LDA are available). "Current"
figures taken from the data slot path; size counts only the reload section.

#### Reloads (pure win — reload side only)

| Target | Current reload (best case)                         | Cost  | Bytes | Patched reload             | Cost  | Bytes | Delta/reload |
|--------|-----------------------------------------------------|-------|-------|-----------------------------|-------|-------|--------------|
| HL     | `LHLD addr`                                         | 20cc  | 3     | `LXI HL,imm`                | 10cc  | 3     | -10cc, 0B   |
| DE     | `LHLD addr; XCHG`                                   | 24cc  | 4     | `LXI DE,imm`                | 10cc  | 3     | -14cc, -1B  |
| BC     | `LHLD addr; MOV C,L; MOV B,H`                       | 30cc  | 5     | `LXI BC,imm`                | 10cc  | 3     | -20cc, -2B  |
| A      | `LDA addr`                                          | 13cc  | 3     | `MVI A,imm`                 | 7cc   | 2     | -6cc, -1B   |
| B..L   | `LDA addr; MOV r,A` (or routed via HL reload)       | 18cc+ | 4+    | `MVI r,imm`                 | 7cc   | 2     | -11cc, -2B  |

For non-accumulator 8-bit regs and non-HL 16-bit pairs the win is large —
precisely the cases where the current backend routes through HL/A and burns
cycles.

#### Spill side

Each spill does *exactly* the same absolute-address store it does today, just
targeting a code address instead of a BSS address:

| Reg | Spill instruction | Cost |
|-----|-------------------|------|
| HL  | `SHLD site+1`     | 20cc |
| DE  | `XCHG; SHLD site+1; XCHG` (or drop second XCHG if HL dead) | 24–28cc |
| BC  | (same options as today: through HL, through A, or push/pop) | 36–48cc |
| A   | `STA site+1`      | 16cc |
| B..L| (same options as today: through A) | 19–32cc |

=> **spill cost is unchanged** (except for the target address).
The optimization is a pure **reload-side** improvement, but it pays for itself
as soon as any spill has ≥1 reload, which is the overwhelming common case.

#### Memory footprint

* Current: each spill slot takes 1B (i8) or 2B (i16) in `__v6clang_ss.f` BSS
  **plus** the reload-site instruction (LHLD = 3B, LDA = 3B, +routing).
* Patched: the reload-site instruction *is* the slot. BSS usage drops by
  1B/2B per spill slot. Reload-site size either stays the same (HL) or
  shrinks (all other cases).

### Prerequisites

1. **Static stack eligibility** (already enforced by `V6ClangStaticStackAlloc`):
   no recursion, not reachable from ISRs, no taken address, has frame
   objects. The reload-site must be written only by this function's spill.
2. **Code is in RAM**. V6CLANG runs from RAM; OK.
3. **Spill dominates reload** on every path. Already an invariant of spill
   insertion (RA only inserts a reload where the slot is defined on every
   reaching path). Multiple spills joining into a single reload (Φ-style)
   still work — every spill writes the same physical bytes.
4. **Reload-site addressability at link time.** The spill's operand must be
   `reload_site+offset`. That means either:
   * an assembler-level local symbol emitted next to the reload, referenced
     from the spill — the V6CLANG object writer already supports `R_V6CLANG_16`
     relocations (see M10), so this is straightforward, OR
   * an `MCSymbol` materialised in the MCStreamer and referenced as the
     spill's operand.
5. **No shared reload site.** Each reload instruction must be a unique slot
   — so if the same vreg is reloaded at two sites, they are *two* patched
   sites and the spill must write *both* (double the spill cost on the
   second side). RA only emits one reload per use in the common case, so
   this is rare; a cost model should treat N reloads as N spill-writes.

### Pitfalls and Non-Issues

* **Interrupts.** An ISR cannot trample the reload-site because the static
  stack pass already forbids running this optimization for any function
  reachable from an ISR. Good.
* **Instruction prefetch.** The 8080 has no instruction prefetch beyond the
  fetched byte currently being decoded. Patching bytes that have not yet
  been fetched is safe. The 20cc SHLD completes and commits to memory
  before the next fetch cycle.
* **Debugger breakpoints.** A software breakpoint at the reload site
  overwrites the `LXI` opcode with `RST`. Patching the imm bytes does not
  disturb the opcode. Low risk.
* **Disassembler / symbolic debugging.** The reload site looks like a
  mutable literal. DWARF/line info still points at the LXI. Cosmetic only.
* **ROM targets.** Not applicable — Vector 06c runs RAM. Would need a
  guard if cross-targeting a ROM-only variant.
* **Relocations after link.** `site+1` is a fully resolved absolute address
  once the linker places the function. Nothing special at runtime.
* **Function entry before first spill.** The first execution of the reload
  site before a spill runs would read the initial (linker-placed) bytes.
  Safe only if reload is **unreachable** before the spill — same property
  RA already guarantees for a reload from an uninitialised slot (it never
  emits one). So this is not a new constraint.
* **Multiple spills on diverging paths (no join).** Each path must dominate
  the reload it reaches; RA ensures this. If two paths spill the *same*
  vreg and both reach the same reload, the reload reads whichever spill
  executed last — which is also the semantics of the classical slot.
* **Function called twice from the same activation chain.** Forbidden by
  `norecurse`; already enforced.
* **Tail-merged spill, two reload sites.** Each site has its own imm slot;
  spill must write both. Either duplicate the spill or keep a classical
  slot — the cost model picks.

### How It Maps Onto the Current Pipeline

The optimization is an **expansion-time rewrite**, not a new RA feature.
The RA continues to create `V6CLANG_SPILL*` / `V6CLANG_RELOAD*` pseudos exactly as
today. The change happens in `eliminateFrameIndex` /
`expandPostRAPseudo` in `V6ClangRegisterInfo.cpp`, keyed on:

1. Function is in the static-stack set (already a queryable attribute).
2. The spill/reload pair share the same frame index and there is **exactly
   one reload** for this spill (or the cost model decides multi-reload is
   still a win).
3. The reload site's register is a whole register pair (LXI) or a single
   8-bit reg (MVI) — i.e. the reload instruction itself admits an
   immediate operand of the right width.

Rewrite:
* Allocate a private `MCSymbol` at the reload site (an `.Ltmp` label).
* Replace the reload pseudo with `LXI r16, 0` or `MVI r8, 0`
  whose immediate carries the target flag `MO_PATCHED_IMM`.
* Replace the spill pseudo with `SHLD Sym+1` or `STA Sym+1`
  (same spill sequence shape as today, just different address operand).
* Emit the `.Ltmp` label immediately before the reload instruction in
  the asm/object stream so `Sym+1` resolves to the imm byte.

No change to RA, no change to pseudo set, no new register class, no new
verifier property. This is the cheapest-to-implement entry of all the
spilling improvements discussed above.

### Interactions With Other Features / Opts

* **O39 Static Stack Alloc** — this optimization *requires* static stack
  eligibility. Functions that fail the static stack criteria fall back to
  the classical slot path.
* **LoadImmCombine / AccumulatorPlanning** — both passes assume the
  immediate of an `MVI`/`LXI` is a known constant derivable from the
  instruction itself. A patched imm is *not* known at compile time. The
  reload's `LXI/MVI` must be marked with `MO_PATCHED_IMM` (or similar) so
  these passes treat it as an opaque load, not as a constant-producing
  instruction. This is the single invasive change outside the expansion
  logic.
* **V6ClangLoadStoreOpt / INX HL merging** — does not run on the reload site
  (no consecutive LXI+MOV pattern).
* **V6ClangRedundantFlagElim / ZeroTestOpt** — `LXI` and `MVI` do not touch
  flags, so no interaction.
* **Linker / relocations** — no change. The spill's `SHLD Sym+1` uses the
  existing `R_V6CLANG_16` relocation.

### Cost Model (Sketch)

A spill/reload pair for register `R` costs (in cycles):

```
cost_classical(R, N_reloads) = spill_cost(R) + N_reloads * reload_cost_slot(R)
cost_patched  (R, N_reloads) = N_reloads * spill_cost(R) + N_reloads * reload_cost_imm(R)
```

Patched wins when:
```
N_reloads * (spill_cost(R) + reload_cost_imm(R))
  <  spill_cost(R) + N_reloads * reload_cost_slot(R)
```
For `N_reloads = 1` (the common case) it always wins: `reload_cost_imm`
is strictly less than `reload_cost_slot` for every register, and the
spill cost is identical.

For `N_reloads >= 2`, the spill is paid per reload site and the break-even
depends on the register. For HL (`spill=20, reload_imm=10, reload_slot=20`)
patched is never worse: `2*(20+10)=60` vs `20+2*20=60`, tied at
`N_reloads=2`. For A (`spill=16, reload_imm=7, reload_slot=13`) patched
wins up through `N_reloads=2` (`2*(16+7)=46` vs `16+2*13=42` — classical
wins at N=2!). So the cost model needs to actually check.

### Open Questions

* Can `SHLD` on I8080 write to a code-address that is about to be fetched
  without violating any pipeline assumption? On the real KR580VM80A there
  is no prefetch queue; the instruction fetched immediately after SHLD
  reads the bus freshly. **Expected safe**, but must be verified on real
  HW + emulator.
* Does the static stack alloc pass already guarantee "function runs to
  completion without concurrent re-entry"? Yes — that's exactly what the
  criteria enforce. So patched code bytes can't be observed mid-patch by
  another activation.
* Is there a case where the reload site is emitted inside a data region
  (e.g. jump-table)? No — reloads are always in the `.text` stream for
  this function.
* What about `V6CLANG_LEA_FI` (address-of spill slot)? Not applicable —
  a patched reload has no addressable slot. If `&spillslot` is needed,
  the function falls back to the classical slot. RA does not emit
  `V6CLANG_LEA_FI` against spill slots today, only against user allocas, so
  this is moot.
* How does this interact with **two-operand spills** (16-bit pair spilled
  via two 8-bit stores through A)? Each byte goes to its own imm field
  (`site+1` for lo, `site+2` for hi — both bytes of the same `LXI`).
  Still one reload instruction. Still a win.

### Recommended Scope of a Minimal Prototype

1. Limit to `HL`, `A` first — the two "clean" cases (SHLD and STA, no
   routing through other regs on the spill side, no cost-model risk at
   `N_reloads=2`).
2. Add `MO_PATCHED_IMM` target operand flag + AsmPrinter handling so
   `LoadImmCombine` skips these instructions.
3. Gate behind `-mv6clang-spill-patched-reload` for A/B testing.
4. Measure against `tests/features/20/` and the golden suite; check
   codesize and cycle counts for the 3–5 functions with the highest spill
   traffic.
5. Extend to `DE`, `BC`, individual `B..L` once cost model is validated.

### Summary

The optimization trades classical BSS spill slots for self-modifying
imm-field slots. Under the conditions static stack already guarantees,
it is safe, requires **no** RA changes, and saves **10–20 cc per reload**
(and 1–2 B per reload site). The single invasive change in the rest of
the compiler is teaching constant-tracking passes to treat patched
`LXI`/`MVI` immediates as opaque.
