#!/usr/bin/env python3
"""Run as root on LA64; arm filtered probes before an authorized game restart.

Usage: script.py CONTAINER_INIT_PID BRIDGE_JSON --restart --seconds 180
Use --pid HOST_GAME_PID --seconds 2 to validate on an existing process instead.
Records CPU arguments only. No ptrace, application memory writes or GL calls.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import select
import signal
import struct
import subprocess
import time


def elf(path):
    data = path.read_bytes()
    assert data[:6] == b'\x7fELF\x02\x01'
    off = struct.unpack_from('<Q', data, 32)[0]
    size, count = struct.unpack_from('<HH', data, 54)
    segments = [struct.unpack_from('<IIQQQQQQ', data, off + i * size)
                for i in range(count)]
    notes = subprocess.check_output(['readelf', '-n', str(path)], text=True)
    build_id = next((line.split('Build ID:', 1)[1].strip()
                     for line in notes.splitlines() if 'Build ID:' in line),
                    'sha256:' + hashlib.sha256(data).hexdigest())
    symbols = {}
    for line in subprocess.check_output(['readelf', '-Ws', '--wide', str(path)],
                                        text=True).splitlines():
        row = line.split()
        if len(row) >= 8 and row[3] == 'FUNC' and row[6] != 'UND':
            addr = int(row[1], 16)
            seg = next(s for s in segments if s[0] == 1
                       and s[3] <= addr < s[3] + s[5])
            symbols[row[7].split('@')[0]] = (addr - seg[3] + seg[2], int(row[2]))
    return data, build_id, symbols, segments


def game_pids():
    result = []
    for path in Path('/proc').glob('[0-9]*/cmdline'):
        try:
            if path.read_bytes().split(b'\0')[0] == b'com.miHoYo.Yuanshen':
                result.append(int(path.parent.name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('container_pid', type=int)
parser.add_argument('bridge_json', type=Path)
mode = parser.add_mutually_exclusive_group(required=True)
mode.add_argument('--restart', action='store_true')
mode.add_argument('--pid', type=int)
parser.add_argument('--seconds', type=float, default=180)
parser.add_argument('--guest-context', action='store_true',
                    help='Record guest preserved registers and known shader-setup fields')
args = parser.parse_args()
assert 0 < args.seconds <= 300
if args.pid:
    assert args.pid in game_pids()

root = Path('/home/noctis') / time.strftime('genshin-sampler-init-%Y%m%d-%H%M%S')
root.mkdir()
group = 'gsinit_' + str(time.time_ns())
trace_events = Path('/sys/kernel/tracing/uprobe_events')
container_root = Path(f'/proc/{args.container_pid}/root')
registered = []
manifest = []
child = None
actions = []
fds = []


def terminate(signum, frame):
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, terminate)


def write_event(text):
    fd = os.open(trace_events, os.O_WRONLY)
    try:
        os.write(fd, (text + '\n').encode())
    finally:
        os.close(fd)


def register(event, relative, offset, fields, event_filter=None, kind='p', **metadata):
    path = container_root / relative.lstrip('/')
    write_event(f'{kind}:{group}/{event} {path}:0x{offset:x} {fields}')
    registered.append(event)
    manifest.append(dict(event=event, library=relative, offset=offset,
                         filter=event_filter, kind=kind, **metadata))


def snapshot():
    pids = game_pids()
    for pid in pids:
        try:
            (root / f'maps-{pid}.txt').write_text(Path(f'/proc/{pid}/maps').read_text())
        except (FileNotFoundError, ProcessLookupError):
            pass
    return pids


try:
    setters = ['glUniform1i', 'glUniform1iv', 'glProgramUniform1i', 'glProgramUniform1iv']
    lifecycle = ['glGetUniformLocation', 'glLinkProgram', 'glProgramBinary', 'glCreateProgram']
    fingerprints = {name: set() for name in setters}
    # Function instructions identify dispatch stubs across ASLR. Matching is a
    # traffic filter only; analysis must still resolve each recorded callee.
    for label, relative in [('s2', '/system/lib64/libGLESv2.so'),
                            ('s3', '/system/lib64/libGLESv3.so'),
                            ('mesa', '/vendor/lib64/egl/libGLESv2_mesa.so')]:
        data, build_id, symbols, _ = elf(container_root / relative.lstrip('/'))
        for name in setters + lifecycle:
            if name not in symbols:
                continue
            offset, size = symbols[name]
            fields = ('a0=%r4:u64 a1=%r5:u64 a2=%r6:u64 a3=%r7:u64'
                      ' caller=%r1:u64')
            if name in ['glUniform1iv', 'glProgramUniform1iv']:
                reg = 'r6' if name == 'glUniform1iv' else 'r7'
                fields += f' value0=+0(%{reg}):u32'
            if name == 'glGetUniformLocation':
                fields += ' name=+0(%r5):string'
            register(label + '_' + name, relative, offset, fields,
                     symbol=name, build_id=build_id)
            if name in ['glGetUniformLocation', 'glCreateProgram']:
                register(label + '_' + name + '_ret', relative, offset,
                         'result=$retval:u32', kind='r', symbol=name, build_id=build_id)
            if name in setters:
                words = struct.unpack_from('<' + 'I' * (size // 4), data, offset)
                # LDPtr.D contains the API's dispatch-table slot in these builds.
                candidates = [(i * 4, word) for i, word in enumerate(words)
                              if word & 0xff000000 == 0x26000000]
                if len(candidates) != 1:
                    raise RuntimeError(f'Unrecognized dispatch stub: {relative}:{name}')
                fingerprints[name].add(candidates[0])

    bridge = json.loads(args.bridge_json.read_text())
    for lib_index, lib in enumerate(bridge['libraries']):
        _, build_id, _, _ = elf(container_root / lib['library'].lstrip('/'))
        if build_id != lib['build_id']:
            raise RuntimeError(f'Proxy build ID mismatch: {lib["library"]}')
        for index, entry in enumerate(lib['entries']):
            signature = entry['signature']
            if entry['pointer_arg'] == 2:
                name = 'glUniform1iv'
            elif entry['pointer_arg'] == 3:
                name = 'glProgramUniform1iv'
            elif signature.count(',') == 1:
                name = 'glUniform1i'
            else:
                name = 'glProgramUniform1i'
            fields = ('callee=%r4:u64 state=%r5:u64 gx0=+0(%r5):u64'
                      ' gx1=+8(%r5):u64 gx2=+16(%r5):u64 gx3=+24(%r5):u64'
                      ' guest_lr=+240(%r5):u64')
            if args.guest_context:
                fields += (' gx19=+152(%r5):u64 gx20=+160(%r5):u64'
                           ' gx21=+168(%r5):u64 gx22=+176(%r5):u64'
                           ' gx23=+184(%r5):u64 gx29=+232(%r5):u64')
                if name == 'glUniform1i':
                    fields += ' setup_flag=+44(+152(%r5)):u32'
                elif name == 'glUniform1iv':
                    # Specific to the audited libyuanshen.so frame-update
                    # caller. Resolve guest_lr before interpreting this field.
                    fields += ' shader_object=+20296(+232(%r5)):u64'
            if entry['pointer_arg'] is not None:
                fields += f' guest_value0=+0(+{8 * entry["pointer_arg"]}(%r5)):u32'
            for offset in sorted({off for off, word in fingerprints[name]}):
                fields += f' code{offset}=+{offset}(%r4):u32'
            expression = ' || '.join(f'code{off} == {word}'
                                     for off, word in sorted(fingerprints[name]))
            register(f'bridge_{lib_index}_{index}', lib['library'], entry['offset'],
                     fields, expression, signature=signature, target=name, build_id=build_id)

    relative = '/vendor/lib64/libgallium_dri.so'
    _, build_id, _, segments = elf(container_root / relative.lstrip('/'))
    if build_id != '29895dc125573fdbf6329ae0ef9e5db5c5804715':
        raise RuntimeError('Mesa build ID mismatch: regenerate internal symbol/layout offsets')
    addr = 0xd064a0
    seg = next(s for s in segments if s[0] == 1 and s[3] <= addr < s[3] + s[5])
    register('driver_uniform', relative, addr - seg[3] + seg[2],
             'location=%r4:u32 count=%r5:u32 values=%r6:u64 context=%r7:u64'
             ' program_ptr=%r8:u64 program=+4(%r8):u32 kind=%r9:u32'
             ' components=%r10:u32 value0=+0(%r6):u32',
             'kind == 1 && components == 1', symbol='_mesa_uniform', build_id=build_id)
    old_pids = snapshot()
    (root / 'manifest.json').write_text(json.dumps(dict(
        group=group, old_pids=old_pids, duration=args.seconds, events=manifest,
        fingerprints={k: sorted(v) for k, v in fingerprints.items()}), indent=2) + '\n')
    ctl_read, ctl_write = os.pipe()
    ack_read, ack_write = os.pipe()
    fds = [ctl_read, ctl_write, ack_read, ack_write]
    command = ['perf', 'record', '--no-bpf-event', '-o', str(root / 'perf.data'),
               '-m', '1024', '-D', '-1', '--control', f'fd:{ctl_read},{ack_write}']
    for event in manifest:
        command += ['-e', group + ':' + event['event']]
        if event['filter']:
            command += ['--filter', event['filter']]
    command += ['-p', str(args.pid)] if args.pid else ['-a']
    command += ['--', 'sleep', str(args.seconds)]
    with (root / 'perf-record.txt').open('w') as output:
        child = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                                 pass_fds=(ctl_read, ack_write))
        os.write(ctl_write, b'enable\n')
        if not select.select([ack_read], [], [], 10)[0]:
            raise RuntimeError('No perf enable acknowledgement; game was not restarted')
        acknowledgement = os.read(ack_read, 64)
        (root / 'perf-ack.txt').write_text(repr(acknowledgement) + '\n')
        if acknowledgement.strip(b'\x00\n\r ') != b'ack':
            raise RuntimeError(f'Unexpected perf acknowledgement {acknowledgement!r}; game was not restarted')
        (root / 'armed-time.json').write_text(json.dumps(dict(
            monotonic=time.monotonic(), unix_time=time.time()), indent=2) + '\n')
        print('ARMED', str(root), flush=True)
        if args.restart:
            prefix = ['lxc-attach', '-P', '/var/lib/waydroid/lxc', '-n', 'waydroid', '--', '/system/bin/am']
            for action in [['force-stop', 'com.miHoYo.Yuanshen'],
                           ['start', '-n', 'com.miHoYo.Yuanshen/com.miHoYo.GetMobileInfo.MainActivity']]:
                before = time.monotonic()
                r = subprocess.run(prefix + action, capture_output=True, text=True, timeout=20)
                actions.append(dict(action=action, start=before, end=time.monotonic(),
                                    returncode=r.returncode, stdout=r.stdout, stderr=r.stderr))
                (root / 'actions.json').write_text(json.dumps(actions, indent=2) + '\n')
                if r.returncode:
                    raise RuntimeError(r.stderr)
            print('RESTARTED', flush=True)
        deadline = time.monotonic() + args.seconds + 20
        last_pids = None
        while child.poll() is None:
            pids = snapshot()
            if pids != last_pids:
                print('GAME_PIDS', pids, flush=True)
                last_pids = pids
            if time.monotonic() > deadline:
                raise TimeoutError('perf exceeded capture deadline')
            time.sleep(2)
        if child.returncode:
            raise RuntimeError((root / 'perf-record.txt').read_text())
finally:
    if child is not None and child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
    for fd in fds:
        os.close(fd)
    errors = []
    for event in reversed(registered):
        try:
            write_event(f'-:{group}/{event}')
        except OSError as error:
            errors.append(str(error))
    (root / 'cleanup.json').write_text(json.dumps(dict(
        registered=len(registered), errors=errors,
        remaining=[line for line in trace_events.read_text().splitlines()
                   if group + '/' in line]), indent=2) + '\n')
    print('CLEANUP', str(root), flush=True)

with (root / 'events.txt').open('w') as output, (root / 'perf-script-errors.txt').open('w') as errors:
    r = subprocess.run(['perf', 'script', '-i', str(root / 'perf.data'), '--ns',
                        '-F', 'comm,pid,tid,cpu,time,event,trace'], stdout=output, stderr=errors)
    if r.returncode:
        raise RuntimeError('perf script failed; see perf-script-errors.txt')
print('DONE', str(root), flush=True)
