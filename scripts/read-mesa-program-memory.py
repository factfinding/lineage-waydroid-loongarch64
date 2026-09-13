#!/usr/bin/env python3
"""Read bounded native Mesa CPU metadata; never attach, call GL, or write memory."""
from pathlib import Path
import os, struct, json, sys, time, subprocess
pid = int(sys.argv[1])
program = int(sys.argv[2])
expected = int(sys.argv[3])
layout = json.load(open(sys.argv[4]))
assert Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\x00')[0] == b'com.miHoYo.Yuanshen'
assert 'build_id' in layout, 'Require layout derived from matching Mesa build'
assert layout['build_id'] in subprocess.check_output(['readelf', '-n', f'/proc/{pid}/root/vendor/lib64/libgallium_dri.so'], text=True), 'Mesa build ID differs from layout'
fd = os.open(f'/proc/{pid}/mem', os.O_RDONLY)

def read(address, size):
    if not (4096 < address < 2 ** 48 and 0 < size <= 65536):
        raise ValueError((address, size))
    value = os.pread(fd, size, address)
    if len(value) != size:
        raise ValueError('short read')
    return value

def get(data, typ, field, fmt='Q'):
    return struct.unpack_from('<' + fmt, data, layout[typ + '.' + field])[0]

def name(address):
    return read(address, 256).split(b'\x00')[0].decode(errors='replace')
p = read(program, layout['gl_shader_program.sizeof'])
assert get(p, 'gl_shader_program', 'Name', 'I') == expected
pd = get(p, 'gl_shader_program', 'data')
data = read(pd, layout['gl_shader_program_data.sizeof'])
slots = get(data, 'gl_shader_program_data', 'UniformDataSlots')
defaults = get(data, 'gl_shader_program_data', 'UniformDataDefaults')
slot_count = get(data, 'gl_shader_program_data', 'NumUniformDataSlots', 'I')
count = get(data, 'gl_shader_program_data', 'NumUniformStorage', 'I')
assert 0 < count < 1024
uaddress = get(data, 'gl_shader_program_data', 'UniformStorage')
size = layout['gl_uniform_storage.sizeof']
result = {'pid': pid, 'program': expected, 'program_pointer': program, 'uniform_count': count, 'uniforms': [], 'stages': [], 'method': 'Read-only /proc/PID/mem; process not stopped; values can change during capture'}
for stage in range(8):
    linked = struct.unpack_from('<Q', p, layout['gl_shader_program._LinkedShaders'] + 8 * stage)[0]
    if not linked:
        continue
    linked_data = read(linked, layout['gl_linked_shader.sizeof'])
    gp = get(linked_data, 'gl_linked_shader', 'Program')
    gd = read(gp, layout['gl_program.sizeof'])
    result['stages'].append({'stage': stage, 'program_pointer': gp, 'sampler_units': list(gd[layout['gl_program.SamplerUnits']:layout['gl_program.SamplerUnits'] + 32])})
for index in range(count):
    u = read(uaddress + index * size, size)
    n = name(get(u, 'gl_uniform_storage', 'name'))
    record = {'index': index, 'name': n, 'is_bindless': bool(u[layout['gl_uniform_storage.is_bindless']])}
    for field in ['remap_location', 'array_elements', 'block_index', 'offset', 'array_stride', 'matrix_stride', 'top_level_array_stride']:
        record[field] = get(u, 'gl_uniform_storage', field, 'i')
    record['opaque_stages'] = [{'stage': s, 'index': u[layout['gl_uniform_storage.opaque'] + 2 * s], 'active': bool(u[layout['gl_uniform_storage.opaque'] + 2 * s + 1])} for s in range(8)]
    storage = get(u, 'gl_uniform_storage', 'storage')
    if slots <= storage < slots + slot_count * 4:
        record['default_word0'] = struct.unpack('<I', read(defaults + storage - slots, 4))[0]
    if storage:
        raw = read(storage, 16)
        record['storage_words'] = list(struct.unpack('<4I', raw))
        record['storage_floats'] = list(struct.unpack('<4f', raw))
    driver = get(u, 'gl_uniform_storage', 'driver_storage')
    number = get(u, 'gl_uniform_storage', 'num_driver_storage', 'I')
    record['drivers'] = []
    if 0 < number < 9:
        for s in range(number):
            ds = read(driver + s * layout['gl_uniform_driver_storage.sizeof'], layout['gl_uniform_driver_storage.sizeof'])
            ptr = get(ds, 'gl_uniform_driver_storage', 'data')
            raw = read(ptr, 16)
            record['drivers'].append({'stride': ds[0], 'words': list(struct.unpack('<4I', raw)), 'floats': list(struct.unpack('<4f', raw))})
    result['uniforms'].append(record)
result['identity_stable'] = read(program, layout['gl_shader_program.sizeof']) == p and read(pd, layout['gl_shader_program_data.sizeof']) == data
if len(sys.argv) > 5:
    context = int(sys.argv[5])
    result['texture_bindings'] = []
    for unit in list(range(14)) + list(range(167, 181)):
        address = context + layout['gl_context.Texture'] + layout['gl_texture_attrib.Unit'] + unit * layout['gl_texture_unit.sizeof']
        td = read(address, layout['gl_texture_unit.sizeof'])
        record = {'unit': unit}
        for t in ['TEXTURE_2D_INDEX', 'TEXTURE_3D_INDEX', 'TEXTURE_CUBE_INDEX']:
            obj = struct.unpack_from('<Q', td, layout['gl_texture_unit.CurrentTex'] + 8 * layout[t])[0]
            record[t] = struct.unpack('<I', read(obj + layout['gl_texture_object.Name'], 4))[0] if obj else None
        result['texture_bindings'].append(record)
os.close(fd)
print(json.dumps(result, indent=2))
