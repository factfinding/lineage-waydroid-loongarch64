#!/usr/bin/env python3
"""Stage tracked Unity sources on NTFS and invoke the Windows Editor from WSL."""
import argparse
import pathlib
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--editor', required=True, type=pathlib.Path,
                    help='WSL path to Unity.exe (not Unity Hub.exe)')
parser.add_argument('--work', required=True, type=pathlib.Path,
                    help='Dedicated project directory on a Windows drive')
parser.add_argument('--api', choices=['gles3', 'vulkan', 'windows'], default='gles3')
parser.add_argument('--suite', choices=['terrain', 'water'], default='terrain')
args = parser.parse_args()
if args.suite == 'water' and args.api == 'vulkan':
    parser.error('The water diagnostic plugin requires GLES3; use gles3 or windows')
root = pathlib.Path(__file__).resolve().parents[1]
if not args.editor.is_file():
    parser.error('Unity Editor executable does not exist')
if not str(args.work.resolve()).startswith('/mnt/'):
    parser.error('--work must be on a mounted Windows drive')
args.work.mkdir(parents=True, exist_ok=True)
for directory in ['Assets', 'Packages', 'ProjectSettings']:
    shutil.copytree(root / directory, args.work / directory, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('*.meta', 'Generated', 'Resources'))
stem = args.suite.capitalize() + 'Probe'
output = args.work / 'Builds' / (('windows' if args.suite == 'terrain' else 'windows-water') + '/' + stem + '.exe' if args.api == 'windows' else args.suite + '-' + args.api + '.apk')
output.parent.mkdir(parents=True, exist_ok=True)
log = args.work / 'Builds' / ('build-' + args.suite + '-' + args.api + '.log')
def winpath(path):
    return subprocess.check_output(['wslpath', '-w', str(path.resolve())], text=True).strip()
if args.suite == 'water' and args.api != 'windows':
    ndk = args.editor.parent / 'Data/PlaybackEngines/AndroidPlayer/NDK'
    clang = ndk / 'toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe'
    source = args.work / 'water_gl.c'
    shutil.copy2(root / 'native/water_gl.c', source)
    plugin = args.work / 'Assets/Plugins/Android/arm64-v8a/libwater_gl.so'
    plugin.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(clang), '--target=aarch64-linux-android26', '-shared', '-fPIC',
                    '-O2', '-Wall', '-Wextra', '-Werror', winpath(source), '-o', winpath(plugin),
                    '-lEGL', '-lGLESv3', '-Wl,-soname,libwater_gl.so'], check=True)
command = [str(args.editor), '-batchmode', '-quit', '-nographics', '-job-worker-count', '8',
           '-projectPath', winpath(args.work), '-buildTarget', 'Win64' if args.api == 'windows' else 'Android',
           '-executeMethod', 'La64.TerrainProbe.ProbeBuild.Build',
           '-probeSuite', args.suite,
           '-terrainApi', args.api, '-terrainTarget', 'windows' if args.api == 'windows' else 'android',
           '-terrainOutput', winpath(output), '-logFile', winpath(log)]
print('Build:', args.api, '\nProject:', args.work, '\nLog:', log, flush=True)
result = subprocess.run(command)
artifacts = root / 'Builds'
artifacts.mkdir(exist_ok=True)
if log.exists():
    shutil.copy2(log, artifacts / log.name)
if result.returncode:
    raise SystemExit(result.returncode)
if not output.is_file():
    raise SystemExit('Editor exited without producing the requested build; inspect log')
if args.api == 'windows':
    shutil.copytree(output.parent, artifacts / output.parent.name, dirs_exist_ok=True)
else:
    shutil.copy2(output, artifacts / output.name)
print('Build artifact:', artifacts, flush=True)
