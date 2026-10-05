# O59. Frequency-Weighted Spill Slot Allocation

# Resolution
Not aplicable because we have better solution O61 and more flexible calling
convention.

*Inspired by llvm-mos `MOSZeroPageAlloc`.*
*Detailed analysis: [llvm_mos_analysis.md](llvm_mos_analysis.md) §S7.*

## Problem

When O10 (static stack allocation) assigns global memory slots to function
stack frames, the allocation is currently based on simple offset packing.
There is no consideration of which slots are **most frequently accessed** or
which functions' slots can **safely overlap**.

The llvm-mos approach uses block frequency analysis and call graph topology
to make optimal allocation decisions, placing the hottest spill slots in the
most efficient positions.

## How llvm-mos Does It

`MOSZeroPageAlloc` (~200 lines) performs whole-program analysis:

1. **Collect candidates**: CSR saves, stack frame objects, globals
2. **Score by frequency**: Use `MachineBlockFrequencyInfo` to weight each
   candidate by how often it's accessed (hot loop = high score)
3. **Build entry graphs**: For each program entry point (main, interrupts),
   build the reachable call subgraph
4. **Allocate greedily**: Assign the highest-scoring candidates first to
   zero-page slots, respecting call graph constraints (functions active
   simultaneously cannot share slots)
5. **Handle SCCs**: Functions in the same SCC (mutual recursion) must have
   disjoint allocations

## V6CLANG Adaptation

The i8080 has no zero page, but the same algorithm applies to **global
static stack slot allocation** (O10's bss region):

- **Hot slot placement**: Slots accessed in hot loops should get the lowest
  addresses (fastest to load via LDA/STA at addresses 0x0000-0x00FF, which
  are the same byte count but some assemblers can optimize)
- **Overlap analysis**: Functions that never coexist on the call stack can
  share the same global memory slot, reducing total bss usage
- **Frequency-weighted sizing**: When bss space is limited, prioritize the
  highest-frequency spill slots for static allocation; leave cold slots on
  the hardware stack

### Integration with O10

O10 currently uses SCC-based offset assignment for the static stack. This
optimization enhances that with:

```cpp
struct SlotCandidate {
  unsigned FunctionIdx;
  int FrameIdx;
  uint64_t Frequency;       // From MachineBlockFrequencyInfo
  unsigned Size;             // Slot size in bytes
};

// Sort by frequency descending, allocate greedily
std::sort(Candidates.begin(), Candidates.end(),
          [](const auto &A, const auto &B) {
            return A.Frequency > B.Frequency;
          });

for (auto &C : Candidates) {
  // Find lowest available offset not conflicting with
  // simultaneously-active functions
  unsigned Offset = findNonConflictingOffset(C);
  assignSlot(C, Offset);
}
```

## Before → After

```
; Before (naive O10 allocation):
; func_a slot 0: accessed 2x (cold)     → offset 0x8000
; func_a slot 1: accessed 500x (hot loop) → offset 0x8002
; func_b slot 0: accessed 200x (warm)    → offset 0x8004

; After (frequency-weighted):
; func_a slot 1: accessed 500x (hot loop) → offset 0x8000 (first/best)
; func_b slot 0: accessed 200x (warm)    → offset 0x8002
; func_a slot 0: accessed 2x (cold)       → offset 0x8004 (or left on stack)
```

## Benefit

- **Savings per instance**: Indirect — better placement of hot slots reduces
  total static memory usage and may enable keeping hot data contiguous
- **Frequency**: Applies to every function with static stack slots
- **Memory savings**: Overlap analysis can reduce total bss usage by 30-50%
  in programs with many leaf functions

## Complexity

High. ~200 lines. Requires `MachineBlockFrequencyInfo`, call graph analysis,
and conflict-free allocation algorithm. The analysis infrastructure is the
main complexity — the allocation itself is a greedy bin-packing variant.

## Risk

Medium. Must correctly identify function overlap constraints from the call
graph. Incorrect overlap analysis can cause data corruption (two active
functions sharing a slot). The llvm-mos implementation is well-tested and
can serve as a reference.

## Dependencies

O10 (done) — enhances the existing static stack allocation with smarter
slot placement. Should be implemented after O10 is mature and tested.
