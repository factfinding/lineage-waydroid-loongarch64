# LoongArch64 Lite JIT cache initialization and width lowering, 2026-09-08

Status: deployed on 2026-09-08 at 20:47 (UTC+8). Final module and system/vendor
image builds passed; Android boot and game-launch smoke checks passed.

This candidate follows the deployed SP/logical-source library. It targets
redundant register-state loads, pointer masking and 32-bit normalization in the
ARM64-to-LoongArch64 Lite JIT. Game loading results for the preceding library are
in [the SP/logical report](BERBERIS_SP_LOGICAL.md); their window differences are
not controlled speedups and are not measurements of this candidate.

## Implementation and control-flow contract

- `BSTRPICK.D` replaces the two shifts used for zero-extending a 32-bit value and
  clearing the top address byte for TBI. `ADDI.W rd,rd,0` replaces the two shifts
  used for signed 32-bit extension. Address masking still modifies only the
  temporary effective address, preserving tagged guest registers and SP.
- Zero-shift, non-flag-setting 32-bit ADD/SUB and non-inverted AND/ORR/EOR consume
  cached source registers directly. Only the final low 32-bit result is retained;
  flag-setting, inverted and nonzero-shift paths keep their existing semantics.
- The actual translator decoder records whether each GPR/SP is read before it
  is written. A cached register first written in the region needs no initial
  ThreadState load, because every write already updates both state and cache.
- Other GPR loads are placed at the beginning of the straight-line block that
  first needs them. Conditional side exits begin new blocks, allowing an early
  exit to avoid loads needed only by later code.
- Initial loads crossed by a local backedge are hoisted to its target. A fixed-point
  pass handles nested/overlapping loops. Host labels bind after initialization,
  ensuring backward branches skip the loads while retaining current cached values.
- Initialization events are sorted once; emission advances a cursor rather than
  scanning all 32 registers at every guest instruction. Entry GPR loads precede
  SIMD-cache loads to preserve their established scheduling.

Forward guest branches still leave the region; this is the dominance assumption
behind the initialization placement. Adding internal forward linking requires a
new control-flow analysis. Each externally entered region initializes its own
mapping. ThreadState writes remain immediate, including SP; no deferred state
flush or cross-region register ABI is introduced. Reserved host registers and the
seven GPR/five SIMD cache slot limits remain unchanged.

## Performance-driven scope limit

The first candidate passed 180 runtime tests but regressed the mixed integer/SIMD
microbenchmark by 5.25%. Moving initialization to straight-line/loop entries and
restoring GPR-before-SIMD ordering still showed a 5.38% regression in a second
five-pair run. These were stable failures, not dismissed as measurement noise.

Consequently, regions with any active SIMD cache retain the prior eager GPR
initialization sequence. Demand initialization applies when SIMD caching is absent.
Width and TBI instruction lowering remain enabled in both cases. The exact
microarchitectural cause of the mixed-case sensitivity has not been established;
no speculative padding or relaxed regression threshold is used.

## Correctness coverage

The final scoped implementation passed **181/181** device tests and **19/19**
host assembler tests. New coverage includes:

- All 2080 legal BSTRPICK bit ranges against an integer reference, six input
  values per range, and signed word-extension boundary values.
- Cached/uncached W ADD/SUB source/destination/zero-register aliases. Existing
  exhaustive W/X logical alias and flag/shift boundary tests also cover the new paths.
- Write-first GPRs, early exits, read-first loop values, changed state at reentry,
  and pending-signal exits. Emitted branch targets are checked to skip initial loads.
- Nested loops with an internal side exit: both backedges must skip the single
  required initial load, and normal/pending-signal/taken-exit execution is verified.
- A real SIGSEGV on a PROT_NONE page. A test handler redirects the host PC to the
  generated recovery entry; the preceding SP update remains visible, the faulting
  post-index load does not update SP or its destination, and the guest PC identifies
  the faulting instruction. The prior signal handler and mapping are restored.

Host assembler tests cover independently assembled encodings, including immediate
boundaries. Existing JNI, SIMD, memory, signal polling and runtime tests are retained.

## Final results

All fourteen scenarios pass the unchanged 3% latency/generated-size gate using
five A/B pairs each. Checksums match in every pair. No failing samples were omitted;
the initial and block-only failed candidates are preserved separately.

| Scenario | Baseline ns/guest | Candidate ns/guest | Latency change | Host bytes before → after |
| --- | ---: | ---: | ---: | ---: |
| `gpr_cached` | 0.3674 | 0.3691 | +0.46% | 544 → 544 |
| `simd_cached` | 0.3585 | 0.3587 | +0.06% | 1056 → 1056 |
| `conditional_fallthrough` | 0.2112 | 0.2093 | -0.90% | 572 → 572 |
| `mixed` | 0.4113 | 0.4106 | -0.17% | 1068 → 1068 |
| `small_immediates` | 0.6445 | 0.6399 | -0.71% | 928 → 924 |
| `immediate_memory` | 0.7021 | 0.6420 | -8.56% | 2852 → 2652 |
| `condition_select` | 0.8410 | 0.8422 | +0.14% | 2384 → 2384 |
| `flag_conditionals` | 1.2261 | 1.2243 | -0.15% | 3128 → 3128 |
| `stack_read` | 0.6980 | 0.6410 | -8.17% | 2852 → 2652 |
| `stack_writeback` | 0.8047 | 0.7471 | -7.16% | 3308 → 3108 |
| `logical_cached` | 0.3673 | 0.3673 | +0.00% | 544 → 544 |
| `cache_write_first` | 0.3269 | 0.3245 | -0.73% | 1048 → 1020 |
| `cache_early_exit` | 6.0345 | 6.0330 | -0.02% | 568 → 568 |
| `integer_w` | 0.7612 | 0.3143 | -58.71% | 2080 → 800 |

The useful measured gains are the W arithmetic/logic and memory scenarios. The
write-first and early-exit scenarios show less than 1% latency change, so no
meaningful execution-time gain is claimed for cache initialization alone. The
write-first case removes seven initial loads (28 bytes); the early-exit path avoids
unused tail-cache loads without reducing total translated code size. These mechanisms
are retained for code/state-load reduction, with control-flow correctness covered.
Mixed SIMD performance returns to baseline with the eager-initialization scope guard.

Translation time is collected once before each run, not gated by the latency/size
comparison. Its medians vary in both directions; for example, mixed translation is
95.28 → 106.99 microseconds, while immediate-memory translation is 90.33 → 89.45
microseconds. Control-flow analysis has a compilation cost, and cold single-translation
measurements are noisy. These microbenchmarks do not establish complete game-loading
improvement; a post-deployment game capture remains necessary.

Final module build: **01:23** (`candidate-build-validated.log`).
Final `m -j8 systemimage vendorimage`: **01:30** (`product-build-validated.log`).
The candidate hash matches the final product library. The final benchmark's saved
game affinities were restored and verified for 18 surviving threads, with no mismatch.
The pre-deployment test preserved the baseline installed library. The subsequent
user-authorized deployment and verified rollback backup are recorded below.

Deployed library SHA-256:
`5f540b72a5571dada88b6caff75f275a2ee9ca1f2f1a249d43d05e37c5b0dc95`.

Evidence: `candidate-validated-run/correctness.log`, `host-tests.log`,
`paired-validated/comparison.txt`, `paired-validated/restore-affinity.json`,
`artifact-sha256.json`, and `installed-library-after-test.txt` in the workspace
artifact directory. `optimization-only.patch` applies cleanly to the saved
pre-edit source; pre-existing unrelated changes remain in place.

## Benchmarks and artifacts

The benchmark suite has fourteen scenarios. Three additions are `integer_w`,
`cache_write_first` and `cache_early_exit`. The early-exit case translates 64 guest
instructions but executes only one per iteration; its timing denominator uses one,
while host bytes per guest describes all 64 translated instructions.

Both versions use the same expanded benchmark source. Each comparison uses five
alternating adjacent A/B pairs and 20,000,000 iterations per scenario on logical
CPU 0. If the game is running, its threads are temporarily restricted to CPUs 2–7,
excluding both SMT threads of the benchmark core, and restored in `finally`.

Workspace artifacts: `logs/jit-demand-width-20260908/`.

- `initial-worktree.patch`, `baseline-source/` and `optimization-only.patch`
  preserve pre-existing changes and isolate this batch's source changes.
- `baseline/` holds the preceding deployed library and the expanded baseline
  benchmark. `candidate-initial/` and `candidate-block/` preserve intermediate
  versions; `candidate/` holds the final candidate.
- `paired/` and `paired-final/` retain the two failed mixed-case comparisons.
- `paired-validated/` contains the final scoped implementation's measurement,
  raw perf counters, checksums and affinity save/restore evidence.

Baseline library SHA-256:
`e80a43d5dbc6996b3f643a806c1f0d6d5320bd52e27a3760ff37b97c81460cf8`.


## Deployment and rollback

Deployed on user request on 2026-09-08 at 20:47 (UTC+8), replacing the Berberis
library override and restarting Waydroid. Android reached `sys.boot_completed=1`;
the noctis graphical session and LXC container are running. Game launch returned
`Status: ok` into `.ApolloZGame`. Host PID 16888 / Android PID 1957 maps the new
library, Unity and IL2CPP. Its executable library mapping inode matches the file
whose SHA-256 was verified. The captured post-launch Android crash buffer is empty.
This is a startup smoke check; the first in-match capture is documented below.

The verified previous-library backup is:
`/var/lib/waydroid/deploy-backups/20260908-204709-demand-width/libberberis_arm64.so`
(SHA-256 `e80a43d5dbc6996b3f643a806c1f0d6d5320bd52e27a3760ff37b97c81460cf8`).
For rollback, use this exact verified backup with the library-only procedure in
`DEVICE.md`, restart the noctis session, and recheck boot, library hash and crashes.

Evidence in the artifact directory: `deployment.log`, `deploy-boot.log`,
`deploy-session.log`, `deploy-game-launch.log`, `deploy-game-verification.json`
and `deploy-crash.log`. The first mapping check preceded IL2CPP initialization;
it is preserved in `deploy-game-verification-initial.json`. The subsequent check
verified all three libraries. `start-sampling.py` is prepared with the new hash
for the next user-controlled window; no loading capture was started by deployment.


## First user-controlled loading capture after deployment

The first fourth-batch window lasted 228.10 seconds, versus the preceding
third-batch evening window of 235.83 seconds (7.73 seconds / 3.28% shorter).
UnityMain CPU time decreased from 199.21 to 192.37 seconds (3.43%). Actual
storage reads also fell from 378.88 to 129.21 MiB and major faults from 1076 to
318. Cache and workload conditions differ; this is not a controlled 3.28% code
speedup and remains within the previous version's two observed window lengths.

GPR cache-initialization load locations decreased from 20.54% to 17.16% of main
sampled cycles; SLLI.D/SRLI.D together decreased from 7.28% to 2.18%, with BSTRPICK.D
at 2.21%. These directions agree with the implementation, but sampled percentages
are not execution counts or directly removable time. Initialization is no longer
necessarily at region entry. ThreadState accesses remain 35.45% and interpreter
fallback hotspots persist. Unknown addresses (1.00%) remain separately classified.

44,230 samples, no reported lost samples, matching library hash, and an empty
captured crash buffer. Full evidence and limitations:
`logs/jkchess-match-demand-width-20260908-205545/REPORT.md`.
