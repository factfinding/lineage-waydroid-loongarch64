# Game-loading SIMD fallback candidate, 2026-09-08

Status: fifth batch deployed on user request at 2026-09-08 21:57 (UTC+8).
Installed SHA-256: `c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`.
The candidate replaces seven observed fallback families with LoongArch64 Lite
JIT lowering. ThreadState writes remain immediate; register reservations and
signal/fault exits are unchanged. The library-only deployment restarted Waydroid;
Android reached `sys.boot_completed=1`. Previous-library backup:
`/var/lib/waydroid/deploy-backups/20260908-215745-simd-fallback/libberberis_arm64.so`.

## Workload evidence and thread attribution

The latest 20:55 loading capture identifies interpreter/SIMD decode overhead,
but many sampled IPs fall in shared decoder and result-store code. Those IPs
alone cannot identify the most frequently interpreted guest opcode.

The earlier partial loading capture contains concrete interpreter-entry logs.
Only entries inside 2026-09-07 21:30:02.730–21:33:48.028 were used as workload
evidence, not as a full-duration baseline. Counts are per-thread shared opcode
buckets logged at powers of two, not exact per-PC or per-instruction counts.

| Family | Observed encoding | Guest library | File offset | Android log TID |
| --- | --- | --- | ---: | ---: |
| FMAX 4S | `0x4e32f631` | libAkSoundEngine.so | 2879824 | 5334 |
| CMTST 4S | `0x4ea08c00` | libAkSoundEngine.so | 1812484 | 5334 |
| SHL 4S | `0x4f3f57de` | libAkSoundEngine.so | 2768900 | 5334 |
| USHR 4S | `0x6f29075a` | libAkSoundEngine.so | 2768540 | 5334 |
| BIC 16B | `0x4e621edc` | libunity.so | 4224104 | 5134 |
| BSL 8B | `0x2e6a1d40` | libil2cpp.so | 211436276 | 5134 |
| UMOV W,S lane | `0x0e0c3c08` | libunity.so | 6856256 | 5134 |

SHL and USHR each appear in thirteen log records inside that window. FMAX and
CMTST each have one observation. The current process still maps the same seven
instruction encodings at the corresponding library file offsets. This proves
code continuity, not their dynamic frequency in the latest loading window.

An early analysis incorrectly described the audio-thread entries as main-thread
evidence. This attribution was corrected: audio-engine evidence is separate.
TID 5134 emits Unity application/graphics initialization logs; saved perf names
the main thread as host TID 8075, but the old per-thread NSpid mapping is not
preserved. No exact current main-thread benefit is claimed from these log counts.

## Implementation

- SHL/USHR 2S and 4S use LSX word shifts. SHL supports 0–31; USHR supports 1–32,
  with #32 explicitly producing zero rather than wrapping an LSX immediate.
- CMTST 2S/4S uses vector AND, per-word equality with zero, and inversion.
- FMAX 4S uses VFMAX plus an unordered-lane mask to reproduce the current
  interpreter's default-NaN result. Signed zero, infinities, subnormals, quiet
  and signaling NaN bit patterns have differential coverage.
- BIC 8B/16B uses vector inversion and AND; BSL 8B uses VBITSEL with the old
  destination as mask. All inputs are read before the destination is updated.
- UMOV Wd,Vn.S[lane] supports all four lanes and WZR. Uncached sources use one
  word load; cached sources use a shuffle/extract and 32-bit normalization.
- New Q=0 vector results are zeroed in the upper 64 bits **before** StoreV,
  keeping both ThreadState and cached destinations coherent. Audited full-vector
  destinations may be cached. UMOV records only its vector source, and shift
  immediates are not mistaken for a source register.

Other lane widths, scalar/FP16 forms and unrelated instructions retain their
existing behavior. This batch does not introduce cross-region linking or
remove ThreadState stores. The NaN contract follows the existing interpreter;
the tests do not establish every possible guest FPCR mode or FP exception mode.

## Correctness and builds

- **189/189** device runtime tests passed (`candidate-unity-run/correctness.log`).
- **20/20** host assembler tests passed. New LSX encodings were independently
  assembled with LLVM, including both word-shift immediate boundaries.
- Eight new device tests cover all shift amounts, register aliases including
  v31/WZR, inactive lanes, NaNs/zeros, repeated cached writes, cached vector
  reads into GPRs, and rejection of unaudited neighboring encodings.
- Existing signal, memory-fault recovery, JNI, atomics and register-cache tests
  remain in the suite.
- Final module build passed in 01:25 (`candidate-unity-build.log`).
- System/vendor image build passed in 01:33 (`product-build-final.log`).
  After the untimed benchmark CLI correction, module/image build targets
  passed again in 01:20 (`product-build-final-harness.log`).
- Candidate SHA-256: `c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`.

## Performance

The JIT regression controls use the same benchmark source on both translators;
the baseline is rebuilt against the fourth-batch translator. After this gate,
only an untimed CLI allowlist was corrected to admit all seven interpreter
scenarios. The translator library and runtime tests did not change. The original fourteen JIT scenarios use
five alternating adjacent A/B pairs each, 20,000,000 iterations per run on CPU 0.
All pass the unchanged 3% latency/generated-size gate, and checksums match.

| Control | Before ns/guest | After ns/guest | Latency change | Host bytes |
| --- | ---: | ---: | ---: | ---: |
| `gpr_cached` | 0.3727 | 0.3757 | +0.80% | 544 → 544 |
| `simd_cached` | 0.3863 | 0.3758 | -2.72% | 1056 → 1056 |
| `conditional_fallthrough` | 0.2252 | 0.2165 | -3.86% | 572 → 572 |
| `mixed` | 0.4589 | 0.4397 | -4.18% | 1068 → 1068 |
| `small_immediates` | 0.6635 | 0.6591 | -0.66% | 924 → 924 |
| `immediate_memory` | 0.6611 | 0.6593 | -0.27% | 2652 → 2652 |
| `condition_select` | 0.8696 | 0.8572 | -1.43% | 2384 → 2384 |
| `flag_conditionals` | 1.2833 | 1.3071 | +1.85% | 3128 → 3128 |
| `stack_read` | 0.6519 | 0.6682 | +2.50% | 2652 → 2652 |
| `stack_writeback` | 0.7615 | 0.7664 | +0.64% | 3108 → 3108 |
| `logical_cached` | 0.3734 | 0.3709 | -0.67% | 544 → 544 |
| `cache_write_first` | 0.3402 | 0.3310 | -2.70% | 1020 → 1020 |
| `cache_early_exit` | 5.7575 | 5.7949 | +0.65% | 568 → 568 |
| `integer_w` | 0.3372 | 0.3395 | +0.68% | 800 → 800 |

Seven new scenarios separately compare interpreter and JIT execution in the
same final candidate benchmark binary, using five alternating pairs and
200,000 iterations each. The interpreter implementation is unchanged by this
batch. The old translator rejects all seven at instruction zero. Each loop
contains 64 guest operations.
Interpreter reference runs InterpretBatch without translation-cache lookup;
JIT translation is outside the timed loop. All A/B checksums match.

| New scenario | Interpreter ns/guest | JIT ns/guest | Execution ratio | JIT host bytes |
| --- | ---: | ---: | ---: | ---: |
| `simd_shl32` | 105.6080 | 0.2927 | 360.8× | 796 |
| `simd_ushr32` | 105.9960 | 0.2895 | 366.1× | 796 |
| `simd_cmtst32` | 122.3541 | 0.5746 | 212.9× | 1824 |
| `simd_fmax4s` | 57.2897 | 0.6240 | 91.8× | 2080 |
| `simd_bic` | 30.5294 | 0.4767 | 64.0× | 1312 |
| `simd_bsl8` | 30.9460 | 1.6750 | 18.5× | 2084 |
| `simd_umovs` | 37.6420 | 0.4274 | 88.1× | 1052 |

These are repeated-instruction microbenchmarks, **not game-loading speedups**.
Real code mixes supported and unsupported operations, pays translation/dispatch
costs, and executes on several threads. Removing one fallback may join more
translated instructions, but these measurements do not quantify that effect.
The audio-engine improvements also must not be attributed directly to the
main-thread critical path. Cold translation timing is retained separately and
is not covered by the execution-time/size gate. A post-deployment loading
capture is still required.

The game was temporarily kept off CPU 0 and its SMT sibling during paired
measurements. Original affinities were restored and checked; see
`paired-final/restore-affinity.json` and
`paired-final/fallback-final/restore-affinity.json`. No installed game library
was replaced.

## Reproducibility and retained intermediate work

Artifacts: `logs/jit-simd-fallback-20260908/`.

- `baseline-source/`, `candidate-source/`, `initial-worktree.patch` and
  `optimization-only.patch` preserve pre-existing edits and isolate this batch.
- `historical-window-entries.json`, `historical-tid5134-window-entries.json`,
  `current-guest-opcodes.json`, `current-unity-guest-opcodes.json` and
  `thread-attribution.txt` record the workload evidence and attribution limit.
- `paired-final/` holds the final JIT controls and `fallback-final/` holds the
  completed seven-family executor comparison; `paired/` and
  `paired-validated/` retain the earlier four-family measurements.
- During harness preparation, an invalid null-cache query mode was fixed to
  non-sequential checks for these branch-free scenarios. A stale initial
  benchmark was inadvertently run after a failed transfer and returned 134;
  the game remained alive. Final transferred binaries were hash-verified and
  the corrected interpreter smoke check passed. A later CLI allowlist omission
  initially rejected three newly added interpreter scenarios; it was fixed
  before the complete same-binary comparison. These incomplete runs remain
  separate from final results. See `harness-correction.json`.
- Original build errors, benchmark intermediates and thread-attribution
  corrections remain in the artifact directory. No samples were discarded
  to obtain a passing regression result.


## Pre-deployment test-session device state

Android remained boot-complete and the installed fourth-batch library hash was
verified after testing (`device-after-test.txt`). The test-time game affinities
were restored while its process was still alive. A later process-mapping check
found that the original game process had exited: Android records PID 1957 as
SIGNALED / status 9 at 21:47:53.283. The available exit record does not identify
the sender. The captured crash buffer was empty. This candidate was never
installed in that process. No game restart was performed during the optimization
and benchmark session; the subsequent authorized deployment is recorded above.
Evidence: `installed-library-after-test.json`, `game-exit-info.txt`,
`crash-after-test.txt`, and the saved kernel/logcat window.

## Deployment smoke check

Library-only deployment completed on user request at 21:57 (UTC+8).
The user session and LXC are running; Android reports `sys.boot_completed=1`.
Game launch returned `Status: ok`. Android PID 1831 (host 33580) maps the
new library: SHA-256 and executable-mapping inode both match. `libunity.so`
and a UnityMain thread are present; `libil2cpp.so` was not yet mapped at the
last check. The full engine/match-loading path has therefore not been validated.
The captured post-launch crash buffer is empty. No sampling was started.
The next-window helper `start-sampling.py` now requires this deployed hash.
See `deployment.log`, `deployment-status.json`, `deploy-game-verification.json`,
`deploy-game-launch.log`, and `deploy-crash.log` in the artifact directory.
