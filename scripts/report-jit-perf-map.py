#!/usr/bin/env python3
# Copyright (C) 2026 The Android Open Source Project
# SPDX-License-Identifier: Apache-2.0

"""Aggregate perf samples using a Berberis perf map.

Linux perf does not apply perf-PID.map symbols when Berberis code is backed by
its executable memfd.  This helper extracts sample IPs with ``perf script`` and
resolves them against the map explicitly.
"""

import argparse
import bisect
import collections
import pathlib
import subprocess


def read_map(path: pathlib.Path) -> tuple[list[int], list[tuple[int, str]]]:
    regions: list[tuple[int, int, str]] = []
    with path.open(encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            fields = line.rstrip("\n").split(maxsplit=2)
            if len(fields) != 3:
                raise ValueError(f"{path}:{line_number}: malformed perf-map entry")
            start = int(fields[0], 16)
            size = int(fields[1], 16)
            regions.append((start, start + size, fields[2]))
    regions.sort()
    return [region[0] for region in regions], [(region[1], region[2]) for region in regions]


def sample_ips(perf: str, data: pathlib.Path):
    command = [perf, "script", "-i", str(data), "-G", "-F", "ip"]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, text=True)
    assert process.stdout is not None
    for line in process.stdout:
        value = line.strip()
        if value:
            yield int(value, 16)
    if process.wait() != 0:
        raise subprocess.CalledProcessError(process.returncode, command)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("perf_data", type=pathlib.Path)
    parser.add_argument("perf_map", type=pathlib.Path)
    parser.add_argument("--perf", default="perf", help="perf executable (default: perf)")
    parser.add_argument("--limit", type=int, default=40, help="number of regions to print")
    args = parser.parse_args()

    starts, regions = read_map(args.perf_map)
    counts: collections.Counter[str] = collections.Counter()
    total = 0
    mapped = 0
    for ip in sample_ips(args.perf, args.perf_data):
        total += 1
        index = bisect.bisect_right(starts, ip) - 1
        if index >= 0 and ip < regions[index][0]:
            mapped += 1
            counts[regions[index][1]] += 1

    jit_percent = mapped * 100 / total if total else 0.0
    print(f"samples={total} jit_mapped={mapped} jit_percent={jit_percent:.2f}")
    print("samples  all%   jit%   region")
    for symbol, count in counts.most_common(args.limit):
        all_percent = count * 100 / total if total else 0.0
        mapped_percent = count * 100 / mapped if mapped else 0.0
        print(f"{count:7d} {all_percent:6.2f} {mapped_percent:6.2f}  {symbol}")


if __name__ == "__main__":
    main()
