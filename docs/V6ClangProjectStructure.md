# V6CLANG Project Structure

```
v6clang/
├── llvm-project/                 # Full LLVM monorepo (gitignored, build source)
├── llvm/                         # Git-tracked mirror of V6CLANG changes
│   ├── lib/Target/V6CLANG/           # Full mirror of V6CLANG backend
│   ├── include/llvm/TargetParser/ # Modified upstream: Triple.h
│   └── lib/TargetParser/         # Modified upstream: Triple.cpp
├── llvm-build/                   # Build output directory (gitignored)
├── .venv/                        # Project-local Python env: Python + Ninja (gitignored)
├── scripts/
│   ├── setup_venv.ps1            # Provision .venv with Ninja + test tooling
│   ├── sync_llvm_mirror.ps1      # llvm-project/ → mirrors (run after builds)
│   └── populate_llvm_project.ps1  # mirrors → llvm-project/ (new contributor setup)
├── clang/lib/Basic/Targets/      # Clang frontend integration
├── compiler-rt/lib/builtins/v6clang/ # Runtime library
├── lld/V6CLANG/                      # Linker
├── tests/
│   ├── golden/                   # Emulator trust baseline (15 programs)
│   ├── lit/                      # LLVM FileCheck tests (mirror of llvm-project/ sources)
│   ├── unit/                     # Standalone C unit tests
│   ├── integration/              # End-to-end C→binary→emulator tests
│   ├── runtime/                  # Runtime library standalone tests
│   └── benchmarks/               # Performance measurements
├── docs/                         # Documentation
├── tools/
│   └── v6emul/                   # Vector 06c emulator
└── design/                       # Design & implementation plan
```

## Key Directories

| Directory | Git-tracked | Description |
|-----------|-------------|-------------|
| `llvm-project/` | No | Full LLVM monorepo, pinned to `llvmorg-18.1.0`. Build reads from here. |
| `llvm/` | Yes | Mirror of all V6CLANG-related changes. Authoritative source for recovery. |
| `llvm-build/` | No | CMake/Ninja build output. |
| `.venv/` | No | Project-local Python environment (Python + Ninja) provisioned by `scripts/setup_venv.ps1`. |
| `design/` | Yes | [design.md](../design/design.md) (architecture spec) and [plan.md](../design/plan.md) (milestones). |
| `tests/` | Yes | All test suites. See [golden tests README](../tests/golden/README.md). |
| `tools/` | Yes | No reference tools are bundled. Configure external tools through `V6ASM`, `V6EMUL`, `C8080`, and optional `Z88DK`. |
