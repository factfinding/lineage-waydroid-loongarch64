#!/usr/bin/env python3
"""Run on the LA64 host as root: script.py HOST_PID [SECONDS<=5] [BRIDGE_JSON].
Record only application GLES calls; never invoke GL or map GPU buffers.
Artifacts are created under /home/noctis/genshin-gl-live-TIMESTAMP.
Optional BRIDGE_JSON supplies build-ID-checked proxy trampoline file offsets.
Bridge events include guest x0-x3, x30 and the first vector argument element.
These generic trampolines also serve other APIs: classify by callee address.
"""
from pathlib import Path
import subprocess, json, struct, time, sys, os
pid = int(sys.argv[1])
duration = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0
assert 0 < duration <= 5
assert Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\x00')[0] == b'com.miHoYo.Yuanshen'
root = Path('/home/noctis') / ('genshin-gl-live-' + time.strftime('%Y%m%d-%H%M%S'))
root.mkdir()
(root / 'maps.txt').write_text(Path(f'/proc/{pid}/maps').read_text())
group = 'gwater_' + str(int(time.time()))
events = Path('/sys/kernel/tracing/uprobe_events')
libs = [('/system/lib64/libGLESv2.so', 's2'), ('/vendor/lib64/egl/libGLESv2_mesa.so', 'mesa')]
functions = ['glUseProgram', 'glUniform1i', 'glUniform1iv', 'glProgramUniform1i', 'glProgramUniform1iv', 'glGetUniformLocation', 'glLinkProgram', 'glProgramBinary', 'glActiveTexture', 'glBindTexture', 'glDrawElements', 'glDrawElementsInstanced', 'glDrawArrays', 'glDrawArraysInstanced', 'glBindBuffer', 'glBindBufferBase', 'glBindBufferRange', 'glBufferData', 'glBufferSubData', 'glUniform4fv', 'glUniformMatrix4fv', 'glMapBufferRange', 'glUnmapBuffer']
registered = []
manifest = []

def build_id(file):
    notes = subprocess.check_output(['readelf', '-n', str(file)], text=True)
    return next(line.split('Build ID:', 1)[1].strip()
                for line in notes.splitlines() if 'Build ID:' in line)

def write(s):
    fd = os.open(events, os.O_WRONLY)
    try:
        os.write(fd, (s + '\n').encode())
    finally:
        os.close(fd)
try:
    if len(sys.argv) > 3:
        bridge = json.loads(Path(sys.argv[3]).read_text())
        for lib_index, lib in enumerate(bridge['libraries']):
            file = Path(f'/proc/{pid}/root' + lib['library'])
            if build_id(file) != lib['build_id']:
                raise RuntimeError(f'Proxy build ID mismatch: {file}')
            for index, entry in enumerate(lib['entries']):
                event = f'bridge_{lib_index}_{index}'
                # ThreadState begins with CPUState::x[31] in the ARM64 ABI.
                spec = (f'p:{group}/{event} {file}:0x{entry["offset"]:x}'
                        ' callee=%r4:u64 state=%r5:u64'
                        ' gx0=+0(%r5):u64 gx1=+8(%r5):u64'
                        ' gx2=+16(%r5):u64 gx3=+24(%r5):u64'
                        ' guest_lr=+240(%r5):u64')
                if entry.get('pointer_arg') is not None:
                    pointer_offset = 8 * entry['pointer_arg']
                    spec += f' guest_value0=+0(+{pointer_offset}(%r5)):u32'
                write(spec)
                registered.append(event)
                manifest.append(dict(entry, event=event, library=lib['library'],
                                     build_id=lib['build_id'], kind='guest_entry'))
    for relative, label in libs:
        file = Path(f'/proc/{pid}/root' + relative)
        data = file.read_bytes()
        assert data[:4] == b'\x7fELF' and data[4:6] == b'\x02\x01'
        phoff = struct.unpack_from('<Q', data, 32)[0]
        entsize, count = struct.unpack_from('<HH', data, 54)
        segments = [struct.unpack_from('<IIQQQQQQ', data, phoff + i * entsize) for i in range(count)]
        symbols = subprocess.check_output(['readelf', '-Ws', str(file)], text=True)
        for line in symbols.splitlines():
            cols = line.split()
            if len(cols) < 8 or cols[3] != 'FUNC' or cols[6] == 'UND':
                continue
            name = cols[7].split('@')[0]
            if name not in functions:
                continue
            addr = int(cols[1], 16)
            seg = next((s for s in segments if s[0] == 1 and s[3] <= addr < s[3] + s[5]))
            off = addr - seg[3] + seg[2]
            event = label + '_' + name
            if event in registered:
                continue
            spec = f'p:{group}/{event} {file}:0x{off:x} a0=%r4:u64 a1=%r5:u64 a2=%r6:u64 a3=%r7:u64 a4=%r8:u64 caller=%r1:u64'
            if name == 'glUniform1iv':
                spec += ' value0=+0(%r6):u32'
            if name == 'glProgramUniform1iv':
                spec += ' value0=+0(%r7):u32'
            if name == 'glGetUniformLocation':
                spec += ' name=+0(%r5):string'
            if name in ['glBufferData', 'glUniform4fv']:
                pointer = 'r6'
            elif name in ['glBufferSubData', 'glUniformMatrix4fv']:
                pointer = 'r7'
            else:
                pointer = None
            if pointer:
                spec += ''.join((f' word{i}=+{4 * i}(%{pointer}):u32' for i in range(16)))
            write(spec)
            registered.append(event)
            manifest.append({'event': event, 'library': relative, 'symbol': name, 'offset': off, 'kind': 'entry'})
            if name in ['glGetError', 'glCheckFramebufferStatus']:
                event += '_ret'
                write(f'r:{group}/{event} {file}:0x{off:x} result=$retval:u64')
                registered.append(event)
                manifest.append({'event': event, 'library': relative, 'symbol': name, 'offset': off, 'kind': 'return'})
    (root / 'manifest.json').write_text(json.dumps({'pid': pid, 'duration_seconds': duration, 'group': group, 'events': manifest}, indent=2) + '\n')
    cmd = ['perf', 'record', '--no-bpf-event', '-o', str(root / 'perf.data'), '-m', '1024', '-e', group + ':*', '-p', str(pid), '--', 'sleep', str(duration)]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=duration + 20)
    (root / 'perf-record.txt').write_text(r.stdout + r.stderr)
    if r.returncode:
        raise RuntimeError(r.stderr)
finally:
    errors = []
    for event in reversed(registered):
        try:
            write(f'-:{group}/{event}')
        except OSError as e:
            errors.append(str(e))
    (root / 'cleanup.json').write_text(json.dumps({'registered': len(registered), 'errors': errors, 'remaining': [l for l in events.read_text().splitlines() if group + '/' in l]}, indent=2) + '\n')
    print(str(root), flush=True)
r = subprocess.run(['perf', 'script', '-i', str(root / 'perf.data'), '--ns'], capture_output=True, text=True)
(root / 'events.txt').write_text(r.stdout)
(root / 'perf-script-errors.txt').write_text(r.stderr)
print('returncode', r.returncode, 'lines', len(r.stdout.splitlines()))
