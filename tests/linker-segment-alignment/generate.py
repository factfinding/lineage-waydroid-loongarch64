#!/usr/bin/env python3
"""Make minimal ELF64 data DSOs with advertised vs actual PT_LOAD alignment.

Usage: generate.py OUTPUT_DIR [ELF_MACHINE=258]
Each fixture exports probe_magic, expected 0x123456789abcdef0.
No application binaries or payload code are required.
"""
import struct
import sys
from pathlib import Path

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
machine = int(sys.argv[2]) if len(sys.argv) > 2 else 258  # LoongArch
for name, vaddr, alignment in (
    ('congruent-16k', 0x8000, 0x4000),
    ('declared-4k', 0xa000, 0x1000),
    ('overstated-16k', 0xa000, 0x4000),
):
    data = bytearray(0x4100)
    ident = b'\x7fELF\x02\x01\x01' + bytes(9)
    struct.pack_into('<16sHHIQQQIHHHHHH', data, 0, ident, 3, machine, 1,
                     0, 64, 0x800, 0, 64, 56, 4, 64, 5, 3)
    phdrs = (
        (6, 4, 64, 64, 64, 224, 224, 8),
        (1, 6, 0, 0, 0, 0x1000, 0x1000, 0x4000),
        (1, 6, 0x4000, vaddr, vaddr, 0x100, 0x100, alignment),
        (2, 6, 0x200, 0x200, 0x200, 7 * 16, 7 * 16, 8),
    )
    for i, values in enumerate(phdrs):
        struct.pack_into('<IIQQQQQQ', data, 64 + i * 56, *values)
    strings = b'\0probe_magic\0'
    data[0x400:0x400+len(strings)] = strings
    for i, pair in enumerate(((4, 0x500), (5, 0x400), (10, len(strings)),
                              (6, 0x600), (11, 24), (30, 8), (0, 0))):
        struct.pack_into('<QQ', data, 0x200 + i * 16, *pair)
    struct.pack_into('<IIIII', data, 0x500, 1, 2, 1, 0, 0)
    struct.pack_into('<IBBHQQ', data, 0x618, 1, 0x11, 0, 4, vaddr, 8)
    struct.pack_into('<Q', data, 0x4000, 0x123456789abcdef0)
    names = b'\0.dynamic\0.dynstr\0.shstrtab\0.data\0'
    data[0x700:0x700+len(names)] = names
    sections = (
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        (names.index(b'.dynamic'), 6, 3, 0x200, 0x200, 7*16, 2, 0, 8, 16),
        (names.index(b'.dynstr'), 3, 2, 0x400, 0x400, len(strings), 0, 0, 1, 0),
        (names.index(b'.shstrtab'), 3, 0, 0, 0x700, len(names), 0, 0, 1, 0),
        (names.index(b'.data'), 1, 3, vaddr, 0x4000, 0x100, 0, 0, 8, 0),
    )
    for i, section in enumerate(sections):
        struct.pack_into('<IIQQQQIIQQ', data, 0x800+i*64, *section)
    (out / (name + '.so')).write_bytes(data)
