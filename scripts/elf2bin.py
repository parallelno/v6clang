#!/usr/bin/env python3
"""DEPRECATED: elf2bin.py — replaced by `llvm-objcopy -O binary`.

The Vector-06c LLVM toolchain now uses native `llvm-objcopy` to convert
ELF to flat binary. The clang driver runs this automatically when the
output extension is anything other than `.elf` or `.o`:

    clang -target i8080-unknown-v6clang -O2 input.c -o output.rom

For manual conversion:

    llvm-objcopy -O binary input.elf output.rom

Pass `--legacy` to fall through to the original Python implementation
(`scripts/elf2bin_legacy.py`). This is a temporary escape hatch and will
be removed once all callers migrate.

See design/plan_O_LLD_native_linker.md for migration details.
"""

import os
import runpy
import sys

DEPRECATION_MESSAGE = (
    "scripts/elf2bin.py is deprecated; use 'llvm-objcopy -O binary' instead.\n"
    "Run with --legacy to use the legacy Python implementation, or see\n"
    "design/plan_O_LLD_native_linker.md for the new flow."
)


def main():
    if "--legacy" in sys.argv:
        sys.argv = [a for a in sys.argv if a != "--legacy"]
        legacy = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "elf2bin_legacy.py")
        runpy.run_path(legacy, run_name="__main__")
        return 0
    sys.stderr.write(DEPRECATION_MESSAGE + "\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
#!/usr/bin/env python3
"""Convert a V6CLANG ELF object (.o) to a flat binary (.bin).

Reads ELF32 little-endian, extracts PROGBITS sections (.text, .rodata, .data),
applies RELA relocations, and writes contiguous flat binary starting at a
configurable base address.

Usage:
    python elf2bin.py input.o -o output.bin [--base 0x0100]
"""

import struct
import sys
import argparse

# ELF constants
SHT_PROGBITS = 1
SHT_NOBITS = 8   # .bss
SHT_RELA = 4
SHT_STRTAB = 3
SHT_SYMTAB = 2

def read_elf32(data):
    """Parse a 32-bit little-endian ELF file."""
    # Verify ELF magic
    if data[:4] != b'\x7fELF':
        raise ValueError("Not an ELF file")
    if data[4] != 1:
        raise ValueError("Not 32-bit ELF")
    if data[5] != 1:
        raise ValueError("Not little-endian ELF")

    # Parse ELF header
    shoff = struct.unpack_from('<I', data, 32)[0]
    shentsize = struct.unpack_from('<H', data, 46)[0]
    shnum = struct.unpack_from('<H', data, 48)[0]
    shstrndx = struct.unpack_from('<H', data, 50)[0]

    # Parse section headers
    sections = []
    for i in range(shnum):
        base = shoff + i * shentsize
        sh = {
            'name_idx': struct.unpack_from('<I', data, base)[0],
            'type': struct.unpack_from('<I', data, base + 4)[0],
            'flags': struct.unpack_from('<I', data, base + 8)[0],
            'addr': struct.unpack_from('<I', data, base + 12)[0],
            'offset': struct.unpack_from('<I', data, base + 16)[0],
            'size': struct.unpack_from('<I', data, base + 20)[0],
            'link': struct.unpack_from('<I', data, base + 24)[0],
            'info': struct.unpack_from('<I', data, base + 28)[0],
            'index': i,
        }
        sections.append(sh)

    # Read string table
    strtab = sections[shstrndx]
    strtab_data = data[strtab['offset']:strtab['offset'] + strtab['size']]

    # Set section names
    for sh in sections:
        end = strtab_data.index(b'\x00', sh['name_idx'])
        sh['name'] = strtab_data[sh['name_idx']:end].decode('ascii')

    return sections, data


def parse_symtab(sections, data):
    """Parse the symbol table."""
    symbols = []
    symtab = None
    strtab = None

    for sh in sections:
        if sh['type'] == SHT_SYMTAB:
            symtab = sh
            strtab = sections[sh['link']]
            break

    if not symtab:
        return symbols

    strtab_data = data[strtab['offset']:strtab['offset'] + strtab['size']]
    entry_size = 16  # ELF32 Sym entry size
    num_syms = symtab['size'] // entry_size

    for i in range(num_syms):
        base = symtab['offset'] + i * entry_size
        st_name = struct.unpack_from('<I', data, base)[0]
        st_value = struct.unpack_from('<I', data, base + 4)[0]
        st_size = struct.unpack_from('<I', data, base + 8)[0]
        st_info = data[base + 12]
        st_other = data[base + 13]
        st_shndx = struct.unpack_from('<H', data, base + 14)[0]

        name_end = strtab_data.index(b'\x00', st_name)
        name = strtab_data[st_name:name_end].decode('ascii')

        symbols.append({
            'name': name,
            'value': st_value,
            'size': st_size,
            'info': st_info,
            'shndx': st_shndx,
        })

    return symbols


def elf_to_bin(input_path, output_path, base_addr=0):
    """Convert ELF .o to flat binary with relocations applied."""
    try:
        with open(input_path, 'rb') as f:
            data = f.read()
    except FileNotFoundError:
        print(f"error: input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)
    except OSError as e:
        print(f"error: cannot read {input_path}: {e}", file=sys.stderr)
        sys.exit(1)

    sections, data = read_elf32(data)
    symbols = parse_symtab(sections, data)

    # Collect PROGBITS and NOBITS sections in order
    output_sections = []
    for sh in sections:
        if sh['type'] == SHT_PROGBITS and sh['size'] > 0:
            output_sections.append(sh)
        elif sh['type'] == SHT_NOBITS and sh['size'] > 0:
            output_sections.append(sh)

    if not output_sections:
        print("Warning: No PROGBITS sections found", file=sys.stderr)
        with open(output_path, 'wb') as f:
            pass
        return

    # Layout sections contiguously from base_addr
    current_addr = base_addr
    for sh in output_sections:
        sh['vaddr'] = current_addr
        current_addr += sh['size']

    # Build a section index → vaddr map
    section_vaddr = {}
    for sh in output_sections:
        section_vaddr[sh['index']] = sh['vaddr']

    # Build output buffer
    total_size = current_addr - base_addr
    output = bytearray(total_size)

    # Copy section data
    for sh in output_sections:
        file_offset = sh['vaddr'] - base_addr
        if sh['type'] == SHT_PROGBITS:
            section_data = data[sh['offset']:sh['offset'] + sh['size']]
            output[file_offset:file_offset + sh['size']] = section_data
        # NOBITS (.bss) is already zero-filled

    # Apply relocations
    for sh in sections:
        if sh['type'] != SHT_RELA:
            continue
        # Find the target section
        target_sh = sections[sh['info']]
        if target_sh['index'] not in section_vaddr:
            continue

        target_base = section_vaddr[target_sh['index']] - base_addr
        num_rela = sh['size'] // 12
        for j in range(num_rela):
            roff = sh['offset'] + j * 12
            r_offset = struct.unpack_from('<I', data, roff)[0]
            r_info = struct.unpack_from('<I', data, roff + 4)[0]
            r_addend = struct.unpack_from('<i', data, roff + 8)[0]
            r_sym = r_info >> 8
            r_type = r_info & 0xFF

            # Resolve symbol value
            sym = symbols[r_sym]
            sym_value = sym['value']
            if sym['shndx'] in section_vaddr:
                sym_value += section_vaddr[sym['shndx']]

            value = sym_value + r_addend

            # Apply fixup at target_base + r_offset
            patch_offset = target_base + r_offset
            # For V6CLANG, all fixups are absolute (not PC-relative).
            # Determine size from the space available (heuristic: check context)
            # RELA type 0 with 2-byte fixup is typical for V6CLANG 16-bit addresses
            if patch_offset + 1 < total_size:
                # 16-bit little-endian
                output[patch_offset] = value & 0xFF
                output[patch_offset + 1] = (value >> 8) & 0xFF

    with open(output_path, 'wb') as f:
        f.write(output)

    print(f"Binary: {total_size} bytes, base: 0x{base_addr:04X}, "
          f"written to {output_path}")


def bin_to_intel_hex(data, base_addr=0, bytes_per_line=16):
    """Convert binary data to Intel HEX format string."""
    lines = []
    offset = 0
    while offset < len(data):
        count = min(bytes_per_line, len(data) - offset)
        addr = base_addr + offset
        record = [count, (addr >> 8) & 0xFF, addr & 0xFF, 0x00]
        record.extend(data[offset:offset + count])
        cs = (~sum(record) + 1) & 0xFF
        hex_data = ''.join(f'{b:02X}' for b in record)
        lines.append(f':{hex_data}{cs:02X}')
        offset += count
    lines.append(':00000001FF')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description='Convert V6CLANG ELF to flat binary')
    parser.add_argument('input', help='Input ELF .o file')
    parser.add_argument('-o', '--output', required=True, help='Output .bin file')
    parser.add_argument('--base', type=lambda x: int(x, 0), default=0,
                        help='Base address (default: 0)')
    parser.add_argument('--hex', action='store_true',
                        help='Also produce Intel HEX output (.hex)')
    args = parser.parse_args()

    elf_to_bin(args.input, args.output, args.base)

    if args.hex:
        hex_path = args.output.rsplit('.', 1)[0] + '.hex'
        with open(args.output, 'rb') as f:
            bin_data = f.read()
        hex_str = bin_to_intel_hex(bin_data, args.base)
        with open(hex_path, 'w') as f:
            f.write(hex_str)
        print(f"Intel HEX: {len(bin_data)} bytes at 0x{args.base:04X}, "
              f"written to {hex_path}")


if __name__ == '__main__':
    main()
