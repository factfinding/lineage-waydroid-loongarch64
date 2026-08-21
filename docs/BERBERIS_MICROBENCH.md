# Berberis LoongArch64 automated benchmarks

The automated suite replaces slow application-only iteration with two gates:

1. the complete LoongArch64 Berberis correctness test binary;
2. stable translated regions covering GPR caching, SIMD caching, conditional
   fallthrough layout, and mixed integer/SIMD arithmetic.

Run it from the integration repository while the Waydroid container is running:

```bash
scripts/run-berberis-microbench.sh
```

The script incrementally builds both modules with `-j8`, copies them into the
running container, requires the correctness suite to pass, and writes results
under `../logs/berberis-microbench-<timestamp>/`. Use `--skip-build` for repeated
runs and `--iterations N` to change the sample duration.
Pass `--start-container` when the Waydroid user session is stopped; without
that explicit option the script does not change session state.

For an automated A/B gate, pass the previous JSONL file as the baseline:

```bash
scripts/run-berberis-microbench.sh --skip-build \
  --baseline ../logs/berberis-microbench-BASELINE/benchmarks.jsonl
```

The command exits unsuccessfully when any scenario regresses by more than 3%
in either latency or generated code size. For standalone comparison, use
`scripts/compare-berberis-microbench.py BASELINE CANDIDATE`; both thresholds
can be overridden explicitly.

`benchmarks.jsonl` reports translation time, generated host-code size, elapsed
time, and nanoseconds per guest instruction. The `perf-*.csv` files report host
cycles, instructions, branches, and branch misses. `metadata.txt` records the
exact Berberis commit, so two runs can be compared without guessing which
binary was tested.

Use at least three runs before judging a small change. Compare one scenario at
a time and treat a change as useful only if correctness still passes and the
relevant latency/counter result improves consistently. These synthetic regions
are regression and code-generation tools; an application-level sample remains
the final validation for JNI, graphics, syscall, and workload-mix effects.
