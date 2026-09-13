#!/usr/bin/env python3
"""Emit bridge probe JSON from matching LA64 proxy libraries.

Usage: prepare-gles-bridge-probes.py PROXY_SO [PROXY_SO ...] > bridge.json
Pass bridge.json as the final argument of capture-genshin-gles-inputs.py.
Offsets are ELF file offsets, guarded by the deployed library's build ID.
Libraries may be unstripped or contain a compressed .gnu_debugdata symbol table.
"""

import json
import lzma
from pathlib import Path
import struct
import subprocess
import sys
import tempfile


SIGNATURES = {
    'void (unsigned int, unsigned int)': None,
    'void (int, int)': None,
    'void (unsigned int, unsigned int, unsigned int)': None,
    'void (unsigned int, int, int)': None,
    'void (unsigned int, unsigned int, void*)': 2,
    'void (int, int, void*)': 2,
    'void (unsigned int, unsigned int, unsigned int, void*)': 3,
    'void (unsigned int, int, int, void*)': 3,
}


def prepare(path):
    data = path.read_bytes()
    if data[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', data, 18)[0] != 258:
        raise ValueError(f'Expected little-endian ELF64 LoongArch: {path}')
    phoff = struct.unpack_from('<Q', data, 32)[0]
    entsize, count = struct.unpack_from('<HH', data, 54)
    segments = [struct.unpack_from('<IIQQQQQQ', data, phoff + i * entsize)
                for i in range(count)]
    notes = subprocess.check_output(['readelf', '-n', str(path)], text=True)
    build_id = next(line.split('Build ID:', 1)[1].strip()
                    for line in notes.splitlines() if 'Build ID:' in line)
    symbols = subprocess.check_output(['readelf', '-Ws', '--wide', str(path)], text=True)
    if 'TrampolineFuncGenerator' not in symbols:
        shoff = struct.unpack_from('<Q', data, 40)[0]
        shsize, shcount, strindex = struct.unpack_from('<HHH', data, 58)
        sections = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shsize)
                    for i in range(shcount)]
        strings = sections[strindex]
        names = data[strings[4]:strings[4] + strings[5]]
        debug = next(s for s in sections
                     if names[s[0]:].split(b'\0')[0] == b'.gnu_debugdata')
        with tempfile.NamedTemporaryFile(suffix='.so') as temp:
            temp.write(lzma.decompress(data[debug[4]:debug[4] + debug[5]]))
            temp.flush()
            symbols = subprocess.check_output(['readelf', '-Ws', '--wide', temp.name],
                                               text=True)
    rows = [line.split() for line in symbols.splitlines()]
    rows = [row for row in rows if len(row) >= 8 and row[3] == 'FUNC'
            and row[6] != 'UND' and 'TrampolineFuncGenerator' in row[7]]
    demangled = subprocess.check_output(['c++filt'], text=True,
                                        input='\n'.join(row[7] for row in rows) + '\n')
    entries = {}
    for row, name in zip(rows, demangled.splitlines()):
        for signature, pointer_arg in SIGNATURES.items():
            if (f'TrampolineFuncGenerator<{signature}, ' not in name
                    or not name.endswith('>::Func(void const*, berberis::ThreadState*)')):
                continue
            addr = int(row[1], 16)
            seg = next(s for s in segments
                       if s[0] == 1 and s[3] <= addr < s[3] + s[5])
            offset = addr - seg[3] + seg[2]
            entries[offset] = dict(offset=offset, virtual_address=addr,
                                   symbol=row[7], signature=signature,
                                   pointer_arg=pointer_arg)
    if not entries:
        raise ValueError(f'No sampler-compatible trampolines in {path}')
    return dict(library='/system/lib64/' + path.name, build_id=build_id,
                entries=list(entries.values()))


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    print(json.dumps({'libraries': [prepare(Path(arg)) for arg in sys.argv[1:]]},
                     indent=2))
