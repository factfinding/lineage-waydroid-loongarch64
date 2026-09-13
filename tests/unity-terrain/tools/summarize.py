#!/usr/bin/env python3
"""Unpack a collected probe run and summarize data checks (not a visual verdict)."""
import argparse
import json
import pathlib
import tarfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('run', type=pathlib.Path)
args = p.parse_args()
output = args.run / 'results'
output.mkdir(exist_ok=True)
with tarfile.open(args.run / 'results.tar.gz', 'r:gz') as archive:
    for entry in archive:
        parts = pathlib.PurePosixPath(entry.name).parts
        if entry.isdir():
            continue
        if not entry.isfile() or entry.name.startswith('/') or '..' in parts:
            raise SystemExit('Unexpected archive entry: ' + entry.name)
        # The probe writes a flat directory. Reject unexpected descendants.
        if len(parts) != 1:
            raise SystemExit('Unexpected nested output: ' + entry.name)
        with archive.extractfile(entry) as source:
            (output / parts[0]).write_bytes(source.read())
environment = json.loads((output / 'environment.json').read_text())
records = [json.loads(p.read_text()) for p in sorted(output.glob('*-data.json'))]
expected = environment.get('expectedCases', 10)
summary = {
    'environment': environment,
    'complete_marker': (output / 'COMPLETE.txt').exists(),
    'case_count': len(records),
    'camera_images': len(list(output.glob('*-camera.png'))),
    'screen_images': len(list(output.glob('*-screen.png'))),
    'all_cpu_data_checks_pass': len(records) == expected and all(r['cpuReadbackPass'] for r in records),
    'all_shaders_supported': len(records) == expected and all(r['shaderSupported'] for r in records),
    'skipped_cases': [r['caseName'] for r in records if r.get('skipped')],
    'visual_pass': None,
    'cases': records,
}
(args.run / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps({k: v for k, v in summary.items() if k != 'cases'}, indent=2))
