#!/usr/bin/env python3

"""Compare two Berberis microbenchmark JSONL result files."""

import argparse
import json
import sys
from pathlib import Path


def load_results(path: Path) -> dict[str, dict]:
    results = {}
    with path.open(encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
                results[record["benchmark"]] = record
            except (json.JSONDecodeError, KeyError) as error:
                raise ValueError(f"{path}:{line_number}: invalid result: {error}") from error
    return results


def percent_change(before: float, after: float) -> float:
    return (after / before - 1.0) * 100.0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument(
        "--max-latency-regression",
        type=float,
        default=3.0,
        help="allowed ns/guest regression in percent (default: 3)",
    )
    parser.add_argument(
        "--max-size-regression",
        type=float,
        default=3.0,
        help="allowed host-code-size regression in percent (default: 3)",
    )
    args = parser.parse_args()

    try:
        baseline = load_results(args.baseline)
        candidate = load_results(args.candidate)
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 2

    if baseline.keys() != candidate.keys():
        print(
            "benchmark sets differ: "
            f"baseline={sorted(baseline)} candidate={sorted(candidate)}",
            file=sys.stderr,
        )
        return 2

    print("benchmark                     latency        host size     result")
    print("----------------------------  -------------  ------------  ------")
    failed = False
    for name in sorted(baseline):
        before = baseline[name]
        after = candidate[name]
        latency_change = percent_change(before["ns_per_guest"], after["ns_per_guest"])
        size_change = percent_change(
            before["host_bytes_per_guest"], after["host_bytes_per_guest"]
        )
        passed = (
            latency_change <= args.max_latency_regression
            and size_change <= args.max_size_regression
        )
        failed |= not passed
        print(
            f"{name:28}  {latency_change:+10.2f}%  {size_change:+9.2f}%  "
            f"{'PASS' if passed else 'FAIL'}"
        )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
