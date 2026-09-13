# Berberis LoongArch64 automated benchmarks

The automated suite replaces slow application-only iteration with two gates:

1. the complete LoongArch64 Berberis correctness test binary;
2. stable translated regions covering GPR caching, SIMD caching, conditional
   fallthrough layout, mixed integer/SIMD arithmetic, small immediates, and
   fixed-offset memory accesses, condition selects, flag-based branches, stack
   addressing and writeback, and cached logical sources.

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

The `small_immediates` scenario repeats ADD/SUB immediates, MOVZ, and a
register ADD. `immediate_memory` repeats two fixed-offset loads, an immediate
ADD, and a pair store over a small resident buffer. Both exercise instruction
patterns seen in the 金铲铲之战 Unity main-thread loading sample; they do not
replay the game or predict its total loading time. Rebuild the same benchmark
source against both translator versions when comparing newly added scenarios.

See [the 2026-09-07 immediate-lowering validation](BERBERIS_SMALL_IMMEDIATES.md)
for measured results and the distinction from application loading time.

`condition_select` covers all 16 conditions using CSEL and fixed flags.
`flag_conditionals` alternates CMP and a not-taken B.GE side exit; unlike the
CBZ-based `conditional_fallthrough`, it exercises NZCV condition evaluation.

See [conditions and direct-source validation](BERBERIS_CONDITIONS.md) for the
second-batch A/B results and the effect of sharing a physical core with the game.

`stack_read` uses the same small-buffer load/load/add/pair-store pattern as
`immediate_memory`, with SP as the address base. `stack_writeback` combines
a pre-index STP, scalar LDR, post-index LDP and SUB, balancing SP each iteration.
`logical_cached` covers 64-bit AND/ORR/EOR and the ORR zero-source MOV alias.
These brought the suite to eleven scenarios; see [SP and logical-source
validation](BERBERIS_SP_LOGICAL.md).

`integer_w` adds cached zero-shift W arithmetic/logic, `cache_write_first` exercises
seven registers initialized before their first read, and `cache_early_exit` exits
before using cached tail operands. The early-exit case executes one instruction
out of 64 translated instructions; timing uses the actual executed count. These
bring the suite to fourteen scenarios. See [cache initialization and width
validation](BERBERIS_DEMAND_WIDTH.md).

`simd_shl32`, `simd_ushr32`, `simd_cmtst32`, `simd_fmax4s`, `simd_bic`,
`simd_bsl8` and `simd_umovs` bring the suite to twenty-one scenarios. The first
four families were observed in `libAkSoundEngine.so`; the latter three in
`libunity.so` and `libil2cpp.so`, during an earlier user-controlled loading
window. Each scenario repeats 64 operations over fixed inputs; BSL also reads
its previous destination as a mask. Audio-thread evidence is separate from
Unity/IL2CPP evidence and is not attributed to the Unity main thread.

For these seven straight-line scenarios only, the benchmark executable accepts
`--interpreter`, which runs `InterpretBatch` with a 64-instruction limit and no
translation-cache lookup. JSON identifies `backend` as `jit` or `interpreter`.
Interpreter results have zero generated host bytes; their `translate_ns` is
only the empty setup timing and has no compilation meaning. Compare execution
latency and checksums manually rather than using the generated-size gate for
an interpreter-to-JIT comparison. These figures exclude production translation,
dispatch and region-break behavior and do not predict game-loading speedups.

An older binary cannot JIT these new scenarios. For this transition, rebuild
the same benchmark source against each backend, use the existing fourteen
scenarios for the usual 3% latency/size regression gate, and compare the seven
new scenarios separately against interpreter mode. When the interpreter is
unchanged, use the same final executable for both executor modes, as in
[the SIMD fallback report](BERBERIS_SIMD_FALLBACKS.md). Do not
pass different scenario sets to the comparison script.
