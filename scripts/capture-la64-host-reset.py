#!/usr/bin/env python3
"""Save bounded, read-only host-reset diagnostics on the development computer.

Example:
    capture-la64-host-reset.py --duration 3600 --output logs/host-reset-UNIQUE

Reconnects after SSH disconnects and records the boot ID for each connection.
It does not launch applications or change device settings. SSH still requires
working host userspace and networking; this is not a panic-safe console.
"""

import argparse
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import selectors
import shlex
import signal
import subprocess
import time


# This program is passed directly to python3 over SSH, never installed remotely.
# All its children have a separate process group and a timeout as a second
# lifetime guard. Broken stdout and signals run the same child cleanup path.
REMOTE_PROGRAM = r'''
import glob
import json
import math
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time

config = json.loads(sys.argv[1])
deadline = time.monotonic() + config['duration']
boot_id = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
selector = selectors.DefaultSelector()
children = {}
buffers = {}
stopping = False
kernel_ready = False


def stop_signal(signum, frame):
    global stopping
    stopping = True


for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGALRM):
    signal.signal(signum, stop_signal)
signal.alarm(math.ceil(config['duration']) + 1)


def emit(channel, **data):
    print(json.dumps(dict(channel=channel, remote_unix=time.time(),
                          remote_monotonic=time.monotonic(), boot_id=boot_id,
                          **data), ensure_ascii=False), flush=True)


def read(path):
    try:
        return Path(path).read_text().strip()
    except (OSError, UnicodeError):
        return None


def start(name, command, channel, package_filter=False):
    global kernel_ready
    if name in children or stopping or time.monotonic() >= deadline:
        return
    command = ['timeout', '--signal=TERM', '--kill-after=2s',
               str(max(0.1, deadline - time.monotonic())) + 's'] + command
    child = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             start_new_session=True)
    children[name] = child
    if name == 'kernel':
        kernel_ready = False
    buffers[name] = b''
    selector.register(child.stdout, selectors.EVENT_READ,
                      (name, channel, package_filter))
    emit('events', event='stream_started', stream=name, pid=child.pid,
         command=command)


def stop(name):
    child = children.pop(name, None)
    if child is None:
        return
    try:
        selector.unregister(child.stdout)
    except KeyError:
        pass
    # Kill the whole private group even if the timeout leader exited first.
    try:
        os.killpg(child.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        child.wait(timeout=0.3)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    child.wait(timeout=1)
    child.stdout.close()
    buffers.pop(name, None)


def process_snapshot():
    result = []
    for entry in os.scandir('/proc'):
        if not entry.name.isdigit():
            continue
        try:
            with open(entry.path + '/cmdline', 'rb') as source:
                name = source.read(256).split(b'\0')[0].decode(errors='replace').strip()
            if not any(name == p or name.startswith(p + ':')
                       for p in config['packages']):
                continue
            fields = {}
            for line in Path(entry.path + '/status').read_text().splitlines():
                key, _, value = line.partition(':')
                if key in ('NSpid', 'VmRSS', 'VmSize', 'Threads', 'State'):
                    fields[key] = value.strip()
            result.append(dict(host_pid=int(entry.name), name=name, **fields))
        except (OSError, UnicodeError):
            pass
    return sorted(result, key=lambda row: row['host_pid'])


def sample():
    paths = set()
    for pattern in ('/sys/class/thermal/thermal_zone*/temp',
                    '/sys/class/thermal/thermal_zone*/type',
                    '/sys/class/hwmon/hwmon*/name',
                    '/sys/class/hwmon/hwmon*/temp*_input',
                    '/sys/class/hwmon/hwmon*/temp*_label',
                    '/sys/class/hwmon/hwmon*/in*_input',
                    '/sys/class/hwmon/hwmon*/curr*_input',
                    '/sys/class/hwmon/hwmon*/power*_average',
                    '/sys/class/hwmon/hwmon*/power*_input',
                    '/sys/class/hwmon/hwmon*/fan*_input',
                    '/sys/class/drm/card*/device/gpu_busy_percent',
                    '/sys/class/drm/card*/device/mem_info_vram_*',
                    '/sys/class/drm/card*/device/mem_info_gtt_*'):
        paths.update(glob.glob(pattern))
    sensors = {path: read(path) for path in sorted(paths)[:256]}
    proc = {name: read('/proc/' + name) for name in
            ('uptime', 'loadavg', 'meminfo', 'pressure/cpu', 'pressure/memory',
             'pressure/io')}
    proc['stat_cpu'] = [line for line in (read('/proc/stat') or '').splitlines()
                        if line.startswith('cpu')]
    kernel_settings = {path: read(path) for path in (
        '/proc/sys/kernel/panic', '/proc/sys/kernel/panic_on_oops',
        '/proc/sys/kernel/panic_on_warn', '/proc/sys/kernel/softlockup_panic',
        '/proc/sys/kernel/hardlockup_panic', '/proc/sys/vm/panic_on_oom')}
    processes = process_snapshot()
    emit('sensors', sensors=sensors, proc=proc, target_processes=processes,
         kernel_settings=kernel_settings)
    return processes


attach = ['lxc-attach', '-P', '/var/lib/waydroid/lxc', '-n', 'waydroid', '--']
last_targets = None
next_sample = 0
next_stream_check = 0
try:
    emit('events', event='connected', hostname=os.uname().nodename,
         kernel=os.uname().release, collector_pid=os.getpid(),
         duration_seconds=config['duration'])
    start('kernel', ['dmesg', '--follow', '--time-format', 'raw'], 'kernel')
    # Crash-buffer traffic is normally small; retain entire crash records.
    start('android_crash', attach + ['/system/bin/logcat', '-b', 'crash',
                                    '-v', 'threadtime', '-T', '20'], 'android')
    # Restrict other buffers to process lifecycle tags, then package-match.
    lifecycle = ['ActivityManager:I', 'ActivityTaskManager:I', 'am_proc_start:I',
                 'am_proc_died:I', 'am_crash:I', 'am_anr:I', '*:S']
    start('android_lifecycle', attach + ['/system/bin/logcat', '-b', 'main',
          '-b', 'system', '-b', 'events', '-v', 'threadtime', '-T', '100']
          + lifecycle, 'android', package_filter=True)
    while not stopping and time.monotonic() < deadline:
        now = time.monotonic()
        if now >= next_sample:
            targets = sample()
            identity = [(p['host_pid'], p.get('NSpid'), p['name']) for p in targets]
            if identity != last_targets:
                emit('events', event='target_processes', processes=targets)
                last_targets = identity
            desired = {}
            for target in targets:
                pids = target.get('NSpid', '').split()
                if len(pids) >= 2:
                    desired['target_' + str(target['host_pid'])] = pids[-1]
            for name in list(children):
                if name.startswith('target_') and name not in desired:
                    stop(name)
            for name, android_pid in desired.items():
                start(name, attach + ['/system/bin/logcat', '-b', 'main', '-b',
                      'system', '-b', 'crash', '-v', 'threadtime', '-T', '20',
                      '--pid=' + android_pid], 'android')
            next_sample = now + config['interval']
        if now >= next_stream_check:
            # LXC may be unavailable immediately after a host reboot. Retry
            # read-only log readers instead of starting the container.
            if 'kernel' not in children:
                start('kernel', ['dmesg', '--follow', '--time-format', 'raw'], 'kernel')
            if 'android_crash' not in children:
                start('android_crash', attach + ['/system/bin/logcat', '-b',
                      'crash', '-v', 'threadtime', '-T', '20'], 'android')
            if 'android_lifecycle' not in children:
                start('android_lifecycle', attach + ['/system/bin/logcat', '-b',
                      'main', '-b', 'system', '-b', 'events', '-v', 'threadtime',
                      '-T', '100'] + lifecycle, 'android', package_filter=True)
            next_stream_check = now + 5
        wait = max(0, min(0.2, deadline - time.monotonic(),
                          next_sample - time.monotonic()))
        for key, mask in selector.select(wait):
            name, channel, package_filter = key.data
            data = os.read(key.fileobj.fileno(), 65536)
            if not data:
                if buffers[name]:
                    emit(channel, stream=name,
                         text=buffers[name].decode(errors='replace'), partial=True)
                emit('events', event='stream_ended', stream=name,
                     returncode=children[name].poll())
                stop(name)
                continue
            buffers[name] += data
            lines = buffers[name].split(b'\n')
            buffers[name] = lines.pop()
            for line in lines:
                text = line.decode(errors='replace')
                if (not package_filter
                        or any(package in text for package in config['packages'])
                        or 'lxc-attach:' in text or 'logcat:' in text):
                    emit(channel, stream=name, text=text)
            if (name == 'kernel' and lines and not kernel_ready
                    and children[name].poll() is None):
                kernel_ready = True
                emit('events', event='armed', verified_streams=['kernel', 'sensors'],
                     note='Android readers are retried while LXC is unavailable')
            if len(buffers[name]) > 1048576:
                emit(channel, stream=name,
                     text=buffers[name].decode(errors='replace'), partial=True)
                buffers[name] = b''
except BrokenPipeError:
    pass
finally:
    for name in list(children):
        stop(name)
    selector.close()
    signal.alarm(0)
    try:
        emit('events', event='remote_stopped', children_remaining=list(children))
    except BrokenPipeError:
        # Avoid a second exception while Python flushes stdout at shutdown.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
'''


def utc(unix=None):
    return datetime.fromtimestamp(unix or time.time(), timezone.utc).isoformat()


def stop_child(child):
    if child is None:
        return
    try:
        os.killpg(child.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        child.wait(timeout=1)
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        child.wait(timeout=1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True,
                        help='New local directory; existing paths are rejected')
    parser.add_argument('--duration', type=float, default=3600,
                        help='Total seconds, including reconnects (default: 3600)')
    parser.add_argument('--interval', type=int, choices=(1, 2), default=1,
                        help='Sensor sampling interval in seconds')
    parser.add_argument('--host', default='la64-root', help='Authorized root SSH alias')
    parser.add_argument('--package', action='append',
                        help='Android package to follow; repeatable (default: Genshin)')
    args = parser.parse_args()
    if not math.isfinite(args.duration) or not 0 < args.duration <= 86400:
        parser.error('--duration must be greater than zero and at most 86400')
    if args.host.startswith('-'):
        parser.error('--host must not start with a dash')
    args.output.mkdir(parents=True, exist_ok=False)
    args.output = args.output.resolve()
    start_unix, start_mono = time.time(), time.monotonic()
    deadline = start_mono + args.duration
    state = dict(status='connecting', armed=False, started=utc(start_unix),
                 deadline=utc(start_unix + args.duration),
                 duration_seconds=args.duration, last_received=None,
                 connection=0, host=args.host, local_pid=os.getpid(),
                 packages=args.package or ['com.miHoYo.Yuanshen'],
                 interval_seconds=args.interval, active_ssh_pid=None)
    stopped = False
    child = None
    files = {}

    def request_stop(signum, frame):
        nonlocal stopped
        state['stop_signal'] = signum
        stopped = True

    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, request_stop)

    def save_state():
        temp = args.output / '.status.json.tmp'
        temp.write_text(json.dumps(state, indent=2) + '\n')
        temp.replace(args.output / 'status.json')

    def record(channel, data):
        if channel not in ('events', 'kernel', 'sensors', 'android', 'ssh_stderr'):
            channel = 'events'
        if channel not in files:
            files[channel] = (args.output / (channel + '.jsonl')).open('x')
        received = utc()
        files[channel].write(json.dumps(dict(local_received=received,
                              connection=state['connection'], **data),
                              ensure_ascii=False) + '\n')
        files[channel].flush()
        if 'remote_unix' in data or channel == 'ssh_stderr':
            state['last_received'] = received
        if channel in ('kernel', 'sensors', 'android'):
            state['last_' + channel] = received
        if data.get('event') == 'connected':
            state['boot_id'] = data['boot_id']
            state['remote_collector_pid'] = data['collector_pid']
        if data.get('event') == 'armed':
            state.update(armed=True, status='armed')
            print('ARMED ' + json.dumps(dict(output=str(args.output),
                   boot_id=state.get('boot_id'), deadline=state['deadline'])),
                  flush=True)
        if data.get('event') in ('stream_started', 'stream_ended'):
            state.setdefault('streams', {})[data['stream']] = data['event']
            if data['stream'] == 'kernel' and data['event'] == 'stream_ended':
                state.update(armed=False, status='degraded')

    save_state()
    print(str(args.output), flush=True)
    try:
        while not stopped and time.monotonic() < deadline:
            state.update(connection=state['connection'] + 1,
                         status='connecting', armed=False, streams={})
            config = dict(duration=max(0.1, deadline - time.monotonic()),
                          interval=args.interval, packages=state['packages'])
            command = ['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5',
                       '-o', 'ServerAliveInterval=2', '-o', 'ServerAliveCountMax=2',
                       args.host, shlex.join(['python3', '-u', '-c', REMOTE_PROGRAM,
                                             json.dumps(config)])]
            child = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     start_new_session=True)
            state['active_ssh_pid'] = child.pid
            save_state()
            selector = selectors.DefaultSelector()
            selector.register(child.stdout, selectors.EVENT_READ, 'stdout')
            selector.register(child.stderr, selectors.EVENT_READ, 'stderr')
            buffers = dict(stdout=b'', stderr=b'')
            last_status = 0
            try:
                while (not stopped and time.monotonic() < deadline
                       and selector.get_map()):
                    for key, mask in selector.select(min(0.2, max(
                            0, deadline - time.monotonic()))):
                        stream = key.data
                        data = os.read(key.fileobj.fileno(), 65536)
                        if not data:
                            selector.unregister(key.fileobj)
                            continue
                        buffers[stream] += data
                        lines = buffers[stream].split(b'\n')
                        buffers[stream] = lines.pop()
                        for raw in lines:
                            text = raw.decode(errors='replace')
                            if stream == 'stderr':
                                record('ssh_stderr', dict(text=text))
                                continue
                            try:
                                row = json.loads(text)
                                record(row.get('channel', 'events'), row)
                            except (ValueError, TypeError, AttributeError):
                                record('events', dict(event='invalid_remote_line',
                                                      text=text))
                    if time.monotonic() - last_status >= 1:
                        save_state()
                        last_status = time.monotonic()
                for stream, buffer in buffers.items():
                    if buffer:
                        record('events', dict(event='partial_line', stream=stream,
                                              text=buffer.decode(errors='replace')))
            finally:
                selector.close()
                stop_child(child)
                child.stdout.close()
                child.stderr.close()
            record('events', dict(event='ssh_ended', returncode=child.returncode))
            child = None
            state.update(armed=False, status='reconnecting', active_ssh_pid=None)
            save_state()
            retry_at = min(deadline, time.monotonic() + 2)
            while not stopped and time.monotonic() < retry_at:
                time.sleep(max(0, min(0.1, retry_at - time.monotonic())))
    except Exception as error:
        state['error'] = str(error)
        raise
    finally:
        stop_child(child)
        state.update(armed=False, status='stopped', stopped=utc(),
                     reason=('error' if 'error' in state else
                             'signal' if stopped else 'deadline'), active_ssh_pid=None)
        save_state()
        for output in files.values():
            output.close()
        print('STOPPED ' + str(args.output), flush=True)


if __name__ == '__main__':
    main()
