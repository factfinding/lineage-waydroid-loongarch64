# LoongArch64 stack operands and redundant memory branches, 2026-09-13

Status: **deployed on 2026-09-13** using the library overlay. The final `lite-only`
revision passed 190/190 device correctness tests, all 23 scenarios in a five-pair
performance gate, and the system/vendor image build. After deployment, all 190
tests passed again and the real game mapped the new library with active JIT
compilation. Actual in-match loading impact has not yet been measured.

## Workload and changes

The user-delimited 金铲铲之战 loading capture is recorded under
`logs/jkchess-match-simd-fallback-20260913-180302/`. Its 228.368-second window
contains 197.26 seconds of main-thread CPU time and no lost/throttled perf events.
Generated JIT code accounts for 81.24% of main-thread user-cycle samples. The
sampled generated-code analysis finds ThreadState accesses, cache reloads and
unconditional branches to the next instruction among the remaining overheads.
Instruction samples can skid; the code snapshot was taken after the capture,
so matching mapping identity does not prove historical bytes. These proportions
are diagnostic leads, not predicted loading-speed gains.

The final source change retains two improvements:

1. **Use cached SP directly for non-flag-setting ADD/SUB immediates.**
   `TranslateAddSubImmediate` uses
   `AddImmediate(t0, ReadXOrSp(rn, t0), delta, t1)` only for `rn == 31` with
   flags disabled. It removes the source copy when SP is cached. Results stay
   in a temporary until `StoreXOrSp` commits architectural state. Uncached SP
   still loads normally; W results zero-extend and flag-setting paths retain
   their original lowering.
2. **Remove unconditional branches to the next instruction at 16 emitter sites.**
   Memory-fault recovery exits already live outside the hot body. Their obsolete
   terminal `B +4` instructions can fall through instead. Scalar/vector memory,
   pairs, tag-zeroing, exclusives and atomics benefit. Each emitted occurrence
   saves four host bytes. Required conditional branches, shared join labels,
   barriers, recovery points and architectural writeback order remain intact.

SP retains its original region-local cache rules and competes for the existing
seven GPR slots. All writes remain write-through. The runtime entry, exit and
continuation source is identical to the baseline; there is no new generated-code
ABI or signal/helper coherence requirement.

## Correctness and build

The existing 189 tests remain unchanged. The new
`LiteSpImmediateSourcesMatchInterpreterAtBoundaries` case adds 1680 generated-code
executions spanning mapping on/off, X/W widths, ADD/SUB, immediate shifts 0/12,
immediates 0/1/2047/2048/4095, destination aliases and seven boundary inputs.
All GPRs, SP, flags and PC are checked against the interpreter; independent
modular-arithmetic checks cover W truncation, overflow and unchanged SP when
only an ordinary destination is written. Existing memory, atomic, tagged-SP,
fault and signal tests also pass in the complete **190/190** device run.

- Modules: `m -j8 libberberis_arm64 berberis_runtime_arm64_loongarch64_tests berberis_runtime_arm64_loongarch64_microbench` passed.
- Device: `scripts/run-berberis-microbench.sh --skip-build --iterations 500000` passed all correctness tests before quick performance measurements.
- Images: `m -j8 systemimage vendorimage` passed in 1m29s.
- Source checks: `git diff --check` passed; the runtime file matches baseline.

The host assembler's relevant 20 tests passed earlier in this investigation;
no encoder changes followed. An optional broader 1175-test host invocation was
stopped during slow WSL death-test handling and is not claimed as a full pass.

## Paired performance results

Baseline: binary_translation commit
`aad4bb6127918b3e6ec7974a1e234c775afdd74d`. Both backends were built with the same
23-scenario harness, SHA-256
`720bdeb83d62caaa0a66f1bed29bc7719d039d1523dfa35f0cef28d24e2b917b`.
The rebuilt baseline executable is
`3ed26567c0bbebf83cd85ba522ad5b1e3a479b112a73f4b85d49c783986e954d`.

The game was exited with the user's authorization. Measurements pin CPU0 and
alternate baseline/candidate order per scenario and round: five pairs, 20 million
iterations per executable per pair, 230 measurements total. Raw JSON, user-cycle,
instruction, branch and branch-miss counters, command order and elapsed times
are preserved under `paired/lite-only-full/`. Every checksum matches; generated
size is stable within each version. The median latency and size comparisons
pass the unchanged **3% gate for all 23 scenarios**:

| Scenario | Latency change | Host bytes | Size change |
| --- | ---: | ---: | ---: |
| `gpr_cached` | -1.21% | 544 → 544 | +0.00% |
| `simd_cached` | -0.05% | 1056 → 1056 | +0.00% |
| `conditional_fallthrough` | -0.14% | 572 → 572 | +0.00% |
| `mixed` | +0.07% | 1068 → 1068 | +0.00% |
| `small_immediates` | -0.06% | 924 → 924 | +0.00% |
| `immediate_memory` | -25.58% | 2652 → 2460 | -7.24% |
| `condition_select` | -0.05% | 2384 → 2384 | +0.00% |
| `flag_conditionals` | -0.23% | 3128 → 3128 | +0.00% |
| `stack_read` | -25.46% | 2652 → 2460 | -7.24% |
| `stack_writeback` | -17.88% | 3108 → 2916 | -6.18% |
| `logical_cached` | -0.21% | 544 → 544 | +0.00% |
| `cache_write_first` | -0.12% | 1020 → 1020 | +0.00% |
| `cache_early_exit` | -0.12% | 568 → 568 | +0.00% |
| `integer_w` | -0.07% | 800 → 800 | +0.00% |
| `simd_shl32` | +0.04% | 796 → 796 | +0.00% |
| `simd_ushr32` | -0.60% | 796 → 796 | +0.00% |
| `simd_cmtst32` | -0.56% | 1824 → 1824 | +0.00% |
| `simd_fmax4s` | -0.10% | 2080 → 2080 | +0.00% |
| `simd_bic` | -0.21% | 1312 → 1312 | +0.00% |
| `simd_bsl8` | -0.08% | 2084 → 2084 | +0.00% |
| `simd_umovs` | -0.10% | 1052 → 1052 | +0.00% |
| `sp_region_chain` | -6.35% | 1692 → 1500 | -11.35% |
| `sp_region_chain_unmapped` | +0.27% | 1500 → 1500 | +0.00% |

These are region-execution microbenchmarks. The timed loop includes native
entry/exit and state-setting helpers. SP chains split 64 guest instructions into
sixteen four-instruction regions, using real translation-cache dispatch for the
first fifteen. The unmapped control disables register mapping. SP is balanced
and never dereferenced; final PC, SP and x0 are checked independently of the
checksum. Size counts all sixteen regions. Translation and warm-up are outside
the timed loop.

The native benchmark function has the same 64-byte alignment in both builds.
This does not fix all code or ThreadState cache-line placement and is not proof
of identical microarchitectural behavior. Five paired medians reduce transient
noise; small sub-percent changes are not presented as meaningful gains. The
memory changes reduce both generated size and measured latency. A fresh
user-delimited in-game capture is needed to establish loading-speed improvement.

## Artifact identities and device state

All evidence paths below are relative to
`logs/jit-sp-residency-20260913/`; generated logs/binaries remain workspace build
products. The candidate library and benchmark are distinct from the rejected
experiments stored alongside them.

| Artifact | SHA-256 |
| --- | --- |
| Library | `8265edf0a3149872d02eef3256489f36b98b60165037a889104059ffa9c6033b` |
| Microbenchmark | `5e7213dc4de23c5710d489a4aa52a0b2617353af4285f7166489954e023500aa` |
| Device tests | `01076a49bd91e2964ba3b5074241729c02347079d033ad05541f886523adca92` |
| system.img | `0ad90eec082af4f393b785bb1a7d2e0cff005902dcb63f67c0dedf7bbc2dd439` |
| vendor.img | `673ad0de578670b693fc6e6c2563a3c8aa65e3fd3c5a06d6daa1a41d1fd11bb7` |

The final source snapshot and hashes are in `candidate-lite-only-source/`,
`candidate-lite-only-source.diff`, `candidate-lite-only-artifacts.json` and
`candidate-lite-only-images.json`. Build logs are `candidate-lite-only-build.log`
and `lite-only-images-build.log`; correctness is in
`lite-only-device/correctness.log`. The complete acceptance result is
`paired/lite-only-full/compare-3pct.log` with its manifest and raw records.

Before deployment, the performance runs retained host boot ID
`161d7690-4e65-46ea-8a92-01181251e4d1`, LXC PID 2116 and the fifth-batch installed
library `c2183d42…`. The following deployment is separate from those benchmarks.

## Deployment and rollback

At the user's request, the validated library was installed at
`/var/lib/waydroid/overlay_rw/system/system/lib64/libberberis_arm64.so`.
The previous file was backed up and hash-verified in
`/var/lib/waydroid/deploy-backups/20260913-195656-jit-stack-memory`.
Its SHA-256 is
`c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`.
The atomic replacement preserved the original extended attributes, root ownership
and 0644 mode while the container was stopped. Images, game data, shader caches
and JIT settings were not changed.

Waydroid restarted as noctis and reached `sys.boot_completed=1` with LXC PID
32429; the host boot ID stayed unchanged. All 190 correctness tests passed again.
The fresh game process (host 35692 / Android 2758) loaded Unity and IL2CPP. Both
its process-visible library and executable mapping's backing file match the new
`8265edf0…` library hash. Over 68.50 seconds, the same process kept JIT mode 1,
successful compilation counts rose 53751 → 99697 and hot-region upgrades rose
9046 → 17746. These counters demonstrate JIT activity, not a loading-speed gain.
The final crash buffer is empty and the game is left running.

Helper/mapper processes were absent before deployment and runtime ADB was already
disabled; that state was preserved. No key mapping or shader cache was changed.
Deployment records, exact-build symbol validation and rollback details are under
`logs/jit-stack-memory-deploy-20260913-115522-utc/`. For rollback, use the exact
backup above and the stop/restore/start sequence in `DEVICE.md`; verify its
previous hash before copying. Actual game-loading impact awaits a new capture.

## Withdrawn experiments

Cross-region SP residency, early entry loads, explicit exit alignment, MOV
specialization and direct outside-residence zero stores were withdrawn after
performance regressions. In particular, the last `stack-exit` variant passed
190 correctness tests but regressed logical and GPR controls by about 30%.
Restoring the baseline runtime removed those control regressions. Its IP profile
reproduced extra cycles without increased branch or L1 instruction-cache misses;
it does not establish the microarchitectural cause. The larger experiments'
tests, binaries and images do not validate this accepted revision.

[The rejected SP-residency record](BERBERIS_SP_RESIDENCY.md) preserves the failure
evidence. Additional limits are in `benchmark-measurement-limitations.md` and
`cycle-ip-diagnostic/REPORT.md` under the evidence directory.
