#!/usr/bin/env python3
"""DEPRECATED: v6clang_link.py — replaced by ld.lld.

The Vector-06c LLVM toolchain now uses native LLVM `ld.lld` plus
`llvm-objcopy` (driven automatically by clang). To produce a flat ROM:

    clang -target i8080-unknown-v6clang -O2 input.c -o output.rom

To override the linker script, defsyms, or link multiple objects manually:

    ld.lld -m elf32v6clang \
           -T clang/lib/Driver/ToolChains/V6Clang/v6clang.ld \
           foo.o bar.o -o out.elf
    llvm-objcopy -O binary out.elf out.rom

Pass `--legacy` to fall through to the original Python implementation
(`scripts/v6clang_link_legacy.py`). This is a temporary escape hatch and will
be removed once all callers migrate.

See design/plan_O_LLD_native_linker.md for migration details.
"""

import os
import runpy
import sys

DEPRECATION_MESSAGE = (
    "scripts/v6clang_link.py is deprecated; use ld.lld via the clang driver.\n"
    "Run with --legacy to use the legacy Python implementation, or see\n"
    "design/plan_O_LLD_native_linker.md for the new flow."
)


def main():
    if "--legacy" in sys.argv:
        sys.argv = [a for a in sys.argv if a != "--legacy"]
        legacy = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "v6clang_link_legacy.py")
        runpy.run_path(legacy, run_name="__main__")
        return 0
    sys.stderr.write(DEPRECATION_MESSAGE + "\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
#!/usr/bin/env python3
"""V6CLANG Linker — Link multiple V6CLANG ELF .o files into a flat binary.

Reads ELF32 little-endian relocatable objects (.o), resolves symbols,
lays out sections (.text, .rodata, .data, .bss), applies relocations,
and produces a contiguous flat binary for the Vector 06c.

Usage:
    python v6clang_link.py file1.o [file2.o ...] -o output.bin [--base 0x0100] [--map output.map]
"""

import struct
import sys
import argparse
import os

# ELF constants
SHT_NULL = 0
SHT_PROGBITS = 1
SHT_SYMTAB = 2
SHT_STRTAB = 3
SHT_RELA = 4
SHT_NOBITS = 8

SHF_ALLOC = 0x2
SHF_WRITE = 0x1
SHF_EXECINSTR = 0x4

STB_LOCAL = 0
STB_GLOBAL = 1
STB_WEAK = 2

SHN_UNDEF = 0
SHN_ABS = 0xFFF1
SHN_COMMON = 0xFFF2

# V6CLANG relocation types (must match V6ClangFixupKinds.h)
R_V6CLANG_NONE = 0
R_V6CLANG_8 = 1
R_V6CLANG_16 = 2
R_V6CLANG_LO8 = 3
R_V6CLANG_HI8 = 4


class ELFSection:
    """Parsed ELF section."""
    __slots__ = ('name', 'type', 'flags', 'addr', 'offset', 'size',
                 'link', 'info', 'index', 'data', 'obj_index', '_name_idx')


class ELFSymbol:
    """Parsed ELF symbol."""
    __slots__ = ('name', 'value', 'size', 'bind', 'type', 'shndx', 'obj_index')


class ELFRelocation:
    """Parsed ELF RELA relocation."""
    __slots__ = ('offset', 'sym_index', 'rtype', 'addend', 'target_section_idx')


class InputObject:
    """Represents one input .o file."""
    __slots__ = ('path', 'sections', 'symbols', 'relocations', 'data')


def read_elf32(path):
    """Parse an ELF32 LE relocatable object file."""
    with open(path, 'rb') as f:
        data = f.read()

    if len(data) < 52:
        raise ValueError(f"{path}: File too small for ELF header")
    if data[:4] != b'\x7fELF':
        raise ValueError(f"{path}: Not an ELF file")
    if data[4] != 1:
        raise ValueError(f"{path}: Not 32-bit ELF")
    if data[5] != 1:
        raise ValueError(f"{path}: Not little-endian ELF")

    e_type = struct.unpack_from('<H', data, 16)[0]
    if e_type != 1:  # ET_REL
        raise ValueError(f"{path}: Not a relocatable object (e_type={e_type})")

    shoff = struct.unpack_from('<I', data, 32)[0]
    shentsize = struct.unpack_from('<H', data, 46)[0]
    shnum = struct.unpack_from('<H', data, 48)[0]
    shstrndx = struct.unpack_from('<H', data, 50)[0]

    # Parse section headers
    sections = []
    for i in range(shnum):
        base = shoff + i * shentsize
        sec = ELFSection()
        sec.name = ''
        sec.type = struct.unpack_from('<I', data, base + 4)[0]
        sec.flags = struct.unpack_from('<I', data, base + 8)[0]
        sec.addr = struct.unpack_from('<I', data, base + 12)[0]
        sec.offset = struct.unpack_from('<I', data, base + 16)[0]
        sec.size = struct.unpack_from('<I', data, base + 20)[0]
        sec.link = struct.unpack_from('<I', data, base + 24)[0]
        sec.info = struct.unpack_from('<I', data, base + 28)[0]
        sec.index = i
        sec.obj_index = -1
        # Read name_idx for later name resolution
        sec._name_idx = struct.unpack_from('<I', data, base)[0]
        if sec.type == SHT_PROGBITS:
            sec.data = data[sec.offset:sec.offset + sec.size]
        elif sec.type == SHT_NOBITS:
            sec.data = bytes(sec.size)
        else:
            sec.data = data[sec.offset:sec.offset + sec.size]
        sections.append(sec)

    # Resolve section names
    if shstrndx < len(sections):
        strtab_data = sections[shstrndx].data
        for sec in sections:
            end = strtab_data.index(b'\x00', sec._name_idx)
            sec.name = strtab_data[sec._name_idx:end].decode('ascii')

    # Parse symbol table
    symbols = []
    symtab_sec = None
    for sec in sections:
        if sec.type == SHT_SYMTAB:
            symtab_sec = sec
            break

    if symtab_sec:
        sym_strtab = sections[symtab_sec.link]
        sym_strtab_data = sym_strtab.data
        entry_size = 16
        num_syms = symtab_sec.size // entry_size

        for i in range(num_syms):
            base = symtab_sec.offset + i * entry_size
            sym = ELFSymbol()
            st_name = struct.unpack_from('<I', data, base)[0]
            sym.value = struct.unpack_from('<I', data, base + 4)[0]
            sym.size = struct.unpack_from('<I', data, base + 8)[0]
            st_info = data[base + 12]
            sym.bind = st_info >> 4
            sym.type = st_info & 0xF
            sym.shndx = struct.unpack_from('<H', data, base + 14)[0]
            sym.obj_index = -1

            name_end = sym_strtab_data.index(b'\x00', st_name)
            sym.name = sym_strtab_data[st_name:name_end].decode('ascii')
            symbols.append(sym)

    # Parse relocations
    relocations = []
    for sec in sections:
        if sec.type != SHT_RELA:
            continue
        target_idx = sec.info  # Section that relocations apply to
        num_rela = sec.size // 12
        for j in range(num_rela):
            roff = sec.offset + j * 12
            rel = ELFRelocation()
            rel.offset = struct.unpack_from('<I', data, roff)[0]
            r_info = struct.unpack_from('<I', data, roff + 4)[0]
            rel.addend = struct.unpack_from('<i', data, roff + 8)[0]
            rel.sym_index = r_info >> 8
            rel.rtype = r_info & 0xFF
            rel.target_section_idx = target_idx
            relocations.append(rel)

    obj = InputObject()
    obj.path = path
    obj.sections = sections
    obj.symbols = symbols
    obj.relocations = relocations
    obj.data = data
    return obj


# Section ordering by category
SECTION_ORDER = {
    '.text': 0,
    '.rodata': 1,
    '.data': 2,
    '.bss': 3,
}


def section_sort_key(name):
    """Return sort key for section ordering."""
    for prefix, order in SECTION_ORDER.items():
        if name == prefix or name.startswith(prefix + '.'):
            return (order, name)
    # Unknown sections go after .text but before .rodata
    return (0, 'z_' + name)


def is_alloc_section(sec):
    """Check if a section should be allocated in the output."""
    if sec.type not in (SHT_PROGBITS, SHT_NOBITS):
        return False
    if sec.size == 0:
        return False
    # Must have ALLOC flag, or be a known named section
    if sec.flags & SHF_ALLOC:
        return True
    if sec.name in ('.text', '.rodata', '.data', '.bss'):
        return True
    if sec.name.startswith('.text.') or sec.name.startswith('.rodata.'):
        return True
    if sec.name.startswith('.data.') or sec.name.startswith('.bss.'):
        return True
    return False


def link(input_paths, output_path, base_addr=0x0100, map_path=None):
    """Link multiple ELF .o files into a flat binary."""
    if not input_paths:
        print("Error: No input files", file=sys.stderr)
        return 1

    # Parse all input objects
    objects = []
    for i, path in enumerate(input_paths):
        try:
            obj = read_elf32(path)
            obj_idx = i
            for sec in obj.sections:
                sec.obj_index = obj_idx
            for sym in obj.symbols:
                sym.obj_index = obj_idx
            objects.append(obj)
        except Exception as e:
            print(f"Error reading {path}: {e}", file=sys.stderr)
            return 1

    # Collect all allocatable sections and assign them to output
    # Each output_section: (name, obj_index, sec_index, data, size, type)
    alloc_sections = []
    for obj_idx, obj in enumerate(objects):
        for sec in obj.sections:
            if is_alloc_section(sec):
                alloc_sections.append({
                    'name': sec.name,
                    'obj_index': obj_idx,
                    'sec_index': sec.index,
                    'data': bytearray(sec.data),
                    'size': sec.size,
                    'type': sec.type,
                    'vaddr': 0,  # filled during layout
                })

    # Sort by section order
    alloc_sections.sort(key=lambda s: section_sort_key(s['name']))

    # Layout: assign virtual addresses
    current_addr = base_addr
    for asec in alloc_sections:
        asec['vaddr'] = current_addr
        current_addr += asec['size']

    total_size = current_addr - base_addr

    # Validate size
    if current_addr > 0x10000:
        print(f"Error: Output exceeds 64KB address space "
              f"(end address: 0x{current_addr:04X})", file=sys.stderr)
        return 1

    # Build section vaddr lookup: (obj_index, sec_index) → vaddr
    sec_vaddr = {}
    for asec in alloc_sections:
        key = (asec['obj_index'], asec['sec_index'])
        sec_vaddr[key] = asec['vaddr']

    # Build global symbol table
    # Phase 1: collect all global/weak definitions
    global_defs = {}  # name → (value, obj_index, sec_index)
    errors = []

    for obj_idx, obj in enumerate(objects):
        for sym in obj.symbols:
            if sym.bind == STB_LOCAL:
                continue
            if sym.shndx == SHN_UNDEF or sym.shndx == 0:
                continue  # undefined reference, handle in phase 2
            if sym.shndx == SHN_ABS:
                resolved = sym.value
            elif (obj_idx, sym.shndx) in sec_vaddr:
                resolved = sec_vaddr[(obj_idx, sym.shndx)] + sym.value
            else:
                # Symbol in a non-allocated section — skip
                continue

            if sym.name in global_defs:
                prev = global_defs[sym.name]
                if sym.bind == STB_WEAK:
                    continue  # existing def wins
                if prev[3] == STB_WEAK:
                    global_defs[sym.name] = (resolved, obj_idx, sym.shndx, sym.bind)
                    continue
                errors.append(f"Error: Multiple definition of '{sym.name}' "
                              f"(in {objects[prev[1]].path} and {objects[obj_idx].path})")
            else:
                global_defs[sym.name] = (resolved, obj_idx, sym.shndx, sym.bind)

    # Phase 2: check for undefined symbols
    undefined = set()
    for obj_idx, obj in enumerate(objects):
        for sym in obj.symbols:
            if sym.bind != STB_LOCAL and sym.shndx == 0 and sym.name:
                if sym.name not in global_defs:
                    undefined.add(sym.name)

    for undef in sorted(undefined):
        errors.append(f"Error: Undefined symbol '{undef}'")

    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        return 1

    # Build output buffer
    output = bytearray(total_size)
    for asec in alloc_sections:
        file_offset = asec['vaddr'] - base_addr
        output[file_offset:file_offset + asec['size']] = asec['data']

    # Apply relocations
    for obj_idx, obj in enumerate(objects):
        for rel in obj.relocations:
            target_key = (obj_idx, rel.target_section_idx)
            if target_key not in sec_vaddr:
                continue  # Relocation targets a non-allocated section

            target_vaddr = sec_vaddr[target_key]
            patch_file_offset = (target_vaddr - base_addr) + rel.offset

            # Resolve symbol
            sym = obj.symbols[rel.sym_index]
            if sym.bind == STB_LOCAL or (sym.shndx != 0 and sym.shndx != SHN_UNDEF):
                # Local symbol or locally-defined symbol
                if sym.shndx == SHN_ABS:
                    sym_value = sym.value
                elif (obj_idx, sym.shndx) in sec_vaddr:
                    sym_value = sec_vaddr[(obj_idx, sym.shndx)] + sym.value
                else:
                    print(f"Warning: Relocation references symbol '{sym.name}' "
                          f"in non-allocated section (obj={obj.path})",
                          file=sys.stderr)
                    continue
            else:
                # Global/external symbol
                if sym.name in global_defs:
                    sym_value = global_defs[sym.name][0]
                else:
                    # Should have been caught in undefined check
                    print(f"Warning: Unresolved symbol '{sym.name}'",
                          file=sys.stderr)
                    continue

            value = sym_value + rel.addend

            # Apply fixup
            if rel.rtype == R_V6CLANG_8:
                if patch_file_offset < total_size:
                    output[patch_file_offset] = value & 0xFF
            elif rel.rtype == R_V6CLANG_16:
                if patch_file_offset + 1 < total_size:
                    output[patch_file_offset] = value & 0xFF
                    output[patch_file_offset + 1] = (value >> 8) & 0xFF
            elif rel.rtype == R_V6CLANG_LO8:
                if patch_file_offset < total_size:
                    output[patch_file_offset] = value & 0xFF
            elif rel.rtype == R_V6CLANG_HI8:
                if patch_file_offset < total_size:
                    output[patch_file_offset] = (value >> 8) & 0xFF
            elif rel.rtype == R_V6CLANG_NONE:
                pass
            else:
                print(f"Warning: Unknown relocation type {rel.rtype} "
                      f"in {obj.path}", file=sys.stderr)

    # Write output binary
    with open(output_path, 'wb') as f:
        f.write(output)

    print(f"Linked: {len(objects)} object(s), {total_size} bytes, "
          f"base: 0x{base_addr:04X} -> {output_path}")

    # Write memory map if requested
    if map_path:
        write_map(map_path, alloc_sections, global_defs, objects, base_addr,
                  total_size)

    return 0


def write_map(map_path, alloc_sections, global_defs, objects, base_addr,
              total_size):
    """Write a memory map file."""
    with open(map_path, 'w') as f:
        f.write(f"V6CLANG Linker Map\n")
        f.write(f"==============\n\n")
        f.write(f"Base address: 0x{base_addr:04X}\n")
        f.write(f"Total size:   {total_size} bytes\n")
        f.write(f"End address:  0x{base_addr + total_size:04X}\n\n")

        f.write(f"Sections:\n")
        f.write(f"{'Address':>8s}  {'Size':>6s}  {'Type':>8s}  {'Source':<30s}  Name\n")
        f.write(f"{'-'*8:>8s}  {'-'*6:>6s}  {'-'*8:>8s}  {'-'*30:<30s}  {'-'*20}\n")
        for asec in alloc_sections:
            stype = 'PROGBITS' if asec['type'] == SHT_PROGBITS else 'NOBITS'
            source = os.path.basename(objects[asec['obj_index']].path)
            f.write(f"0x{asec['vaddr']:04X}    {asec['size']:6d}  {stype:>8s}  "
                    f"{source:<30s}  {asec['name']}\n")

        f.write(f"\nSymbols:\n")
        f.write(f"{'Address':>8s}  {'Bind':>6s}  Name\n")
        f.write(f"{'-'*8:>8s}  {'-'*6:>6s}  {'-'*30}\n")
        for name in sorted(global_defs.keys()):
            val, obj_idx, sec_idx, bind = global_defs[name]
            bind_str = 'GLOBAL' if bind == STB_GLOBAL else 'WEAK'
            f.write(f"0x{val:04X}    {bind_str:>6s}  {name}\n")

    print(f"Map: {map_path}")


def main():
    parser = argparse.ArgumentParser(
        description='V6CLANG Linker — Link ELF .o files into flat binary')
    parser.add_argument('inputs', nargs='+', help='Input ELF .o files')
    parser.add_argument('-o', '--output', required=True,
                        help='Output flat binary file')
    parser.add_argument('--base', type=lambda x: int(x, 0), default=0x0100,
                        help='Base/start address (default: 0x0100)')
    parser.add_argument('--map', default=None,
                        help='Output memory map file')
    args = parser.parse_args()

    sys.exit(link(args.inputs, args.output, args.base, args.map))


if __name__ == '__main__':
    main()
