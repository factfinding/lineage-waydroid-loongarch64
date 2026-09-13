#!/usr/bin/env python3
"""Install one probe APK and collect an automatic scene matrix via the documented SSH aliases."""
import argparse
import hashlib
import json
import pathlib
import shlex
import subprocess
import time
import zipfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--apk', required=True, type=pathlib.Path)
p.add_argument('--api', choices=['gles3', 'vulkan'], required=True)
p.add_argument('--suite', choices=['terrain', 'water'], default='terrain')
p.add_argument('--out', required=True, type=pathlib.Path)
p.add_argument('--timeout', type=int, default=600)
args = p.parse_args()
if args.suite == 'water' and args.api != 'gles3':
    p.error('The water diagnostic plugin requires GLES3')
args.out.mkdir(parents=True, exist_ok=False)
with zipfile.ZipFile(args.apk) as apk:
    libraries = [n for n in apk.namelist() if n.startswith('lib/') and n.endswith('.so')]
    if not libraries or any(n.split('/')[1] != 'arm64-v8a' for n in libraries):
        raise SystemExit('Expected ARM64-only APK')
    if 'lib/arm64-v8a/libil2cpp.so' not in libraries:
        raise SystemExit('Expected IL2CPP build')
pkg = 'org.la64.' + args.suite + 'probe.' + args.api
sha = hashlib.sha256(args.apk.read_bytes()).hexdigest()
remote = '/home/noctis/' + args.suite + '-probe-' + args.api + '-' + sha[:12] + '.apk'
android_apk = '/data/local/tmp/' + args.suite + '-probe-' + args.api + '.apk'
lxc = ['lxc-attach', '-P', '/var/lib/waydroid/lxc', '-n', 'waydroid', '--']
def ssh(command, check=True):
    return subprocess.run(['ssh', 'la64-root', command], check=check, capture_output=True)
def android(command, check=True):
    return ssh(shlex.join(lxc + command), check)
subprocess.run(['scp', str(args.apk), 'la64-root:' + remote], check=True)
actual = ssh(shlex.join(['sha256sum', remote])).stdout.decode().split()[0]
if actual != sha:
    raise SystemExit('Transferred APK hash mismatch')
ssh(shlex.join(lxc + ['/system/bin/sh', '-c', 'cat > ' + shlex.quote(android_apk)]) + ' < ' + shlex.quote(remote))
install = android(['/system/bin/pm', 'install', '-r', '-t', android_apk])
(args.out / 'install.txt').write_bytes(install.stdout + install.stderr)
if b'Success' not in install.stdout:
    raise SystemExit('Package manager did not report Success')
android(['/system/bin/am', 'force-stop', pkg])
wrapper_key = 'wrap.' + pkg
previous_wrapper = android(['/system/bin/getprop', wrapper_key]).stdout.decode().strip()
if previous_wrapper:
    raise SystemExit('Probe already has a wrap property; inspect it before changing launch behavior')
launch = android(['/system/bin/am', 'start', '-W', '-n', pkg + '/com.unity3d.player.UnityPlayerActivity', '--ez', 'probe_auto', 'true'])
(args.out / 'launch.txt').write_bytes(launch.stdout + launch.stderr)
if b'Status: ok' not in launch.stdout:
    raise SystemExit('Activity launch did not report success')
metadata = {'apk_sha256': sha, 'package': pkg, 'requested_api': args.api,
            'start_epoch': time.time()}
# Unity's output line supplies the actual persistentDataPath; don't assume a
# host mount mapping. Only the expected application's directory is accepted.
output_dir = None
complete = False
start_monotonic = time.monotonic()
while time.monotonic() - start_monotonic < args.timeout:
    pid = android(['/system/bin/pidof', pkg], check=False).stdout.decode().strip()
    if not pid:
        metadata['error'] = 'Probe process exited before completion'
        break
    metadata['android_pid'] = pid
    logs = android(['/system/bin/logcat', '-d', '-v', 'threadtime', '--pid=' + pid]).stdout
    (args.out / 'logcat.txt').write_bytes(logs)
    for line in logs.decode(errors='replace').splitlines():
        if 'TERRAIN_PROBE_OUTPUT=' in line:
            candidate = line.split('TERRAIN_PROBE_OUTPUT=', 1)[1].strip()
            allowed = ['/storage/emulated/0/Android/data/' + pkg + '/files/', '/data/user/0/' + pkg + '/files/']
            if not any(candidate.startswith(prefix) for prefix in allowed) or '..' in pathlib.PurePosixPath(candidate).parts:
                raise SystemExit('Unexpected output directory in probe log')
            output_dir = candidate
    if output_dir:
        result = android(['/system/bin/test', '-f', output_dir + '/COMPLETE.txt'], check=False)
        if result.returncode == 0:
            complete = True
            break
    time.sleep(5)
metadata['end_epoch'] = time.time()
metadata['output_dir'] = output_dir
metadata['complete'] = complete
(args.out / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
if output_dir:
    result = android(['/system/bin/tar', '-czf', '-', '-C', output_dir, '.'])
    (args.out / 'results.tar.gz').write_bytes(result.stdout)
(args.out / 'crash.txt').write_bytes(android(['/system/bin/logcat', '-b', 'crash', '-d', '-v', 'threadtime']).stdout)
(args.out / 'properties.txt').write_bytes(android(['/system/bin/getprop']).stdout)
print(json.dumps(metadata, indent=2))
if not complete:
    raise SystemExit(metadata.get('error', 'Timed out; available logs and partial output retained'))
print('Capture complete. This is not a visual pass; inspect the PNGs and data reports.')
