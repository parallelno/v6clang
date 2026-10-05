# V6CLANG Adaptation of the llvm-mos Spilling

## Problem

Spilling on V6CLANG takes significant CPU time. Some spilling operations use hardcoded
PUSH & POP even when HL is dead and avaliable.


## Original MOS spilling:

### Static stack path (equivalent to V6CLANG's V6ClangStaticStackAlloc):

* For GPR (A, X, Y) → emits real MOS::STAbs / MOS::LDAbs directly. No pseudo, no hidden clobbers. These are absolute-address store/load instructions — zero extra registers needed.
* For non-GPR (imaginary registers, bit flags) → creates a virtual register (createVirtualRegister(&MOS::GPRRegClass)), emits a COPY to/from it, then stores/loads the vreg via STAbs/LDAbs. The RA sees the vreg and allocates a GPR for it — fully honest, no hidden clobbers.
* For 16-bit Imag16 → splits into lo/hi bytes, stores each separately via the same loadStoreByteStaticStackSlot mechanism.

The critical insight: On the static stack path, llvm-mos doesn't use pseudos at all for spills. It emits real instructions directly in storeRegToStackSlot/loadRegFromStackSlot. When a temporary register is needed (non-GPR spill), it creates a vreg, not a hidden clobber — so the RA is fully aware.

This is the most radical validation of the "honest Defs" approach you've been discussing. llvm-mos goes even further than honest pseudos — it bypasses pseudos entirely for static stack spills, putting real instructions with real vreg dependencies directly into RA's view.

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