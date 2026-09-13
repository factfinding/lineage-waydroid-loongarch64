# LoongArch64 Lite JIT conditions and direct sources, 2026-09-07

Status: deployed on 2026-09-07 after validation and the user confirming the game
was finished. Android boot and a game-launch smoke check passed.

## Change

This follows the deployed small-immediates candidate. The main-thread samples
still showed substantial state loads, register moves, and condition handling.

- `EmitCondition` extracts only the NZCV bits required by the condition. AL/NV
  no longer load flags; LT avoids the previous double inversion. Immediate
  AND/XOR instructions replace loading a mask into another register.
- `ShiftOperand` omits a zero shift after preserving required width normalization.
  Nonzero rotates use the short constant loader introduced in the previous batch.
- `ReadXOrZero` returns a read-only cached source register or the architectural
  zero register. A narrow 64-bit ADD/SUB path with no flag update and zero shift
  uses these sources directly, avoiding temporary copies. All stores still write
  through immediately, then update any corresponding cache entry.
- Extended differential testing exposed a 32-bit shifted SUBS carry boundary:
  W2=0x80000000 shifted left by 1 must be zero as a 32-bit operand. The previous
  host temporary could retain bit 32. Shifted flag-setting W operations now
  normalize the RHS after LSL spill or ASR sign extension before flag calculation.

No cross-region cache preservation or deferred state/flags writeback is introduced.
Source-use accounting continues through the actual decoder for cache selection.

## Validation

- Baseline library exactly matches the deployed first-batch candidate:
  `e222f893c44173802b100c3f56835e1fa120e279cb28dae2bb0328cc0b489807`.
- Final candidate library SHA-256:
  `723ad863b1d25ac5fc84a4d07e2dcf6b7e3e5ec493ee23c6419aa81a7e11afa9`.
- Module build passed for the library, runtime tests, microbenchmark, and host tests.
- Final device suite: **171/171** passed. Host assembler suite: **18/18** passed.
- New coverage: all 16 B.cond conditions across 16 NZCV values; all integer
  conditional-select variants in both widths across those conditions and flags;
  shifted arithmetic/logical edge cases; cached and uncached ADD/SUB with source,
  destination, and zero-register aliasing. Existing CCMP and floating select tests
  also passed.
- The first run failed the newly exposed shifted-SUBS case and an old code-size
  assertion that assumed cached sources were still copied. Both were corrected;
  the complete suite was rerun successfully. Initial failure logs are retained.
- Final `m -j8 systemimage vendorimage` passed in **01:28**.

## Microbenchmark comparison

Both versions use the same eight-scenario benchmark source, including new
`condition_select` (CSEL across all conditions) and `flag_conditionals` (CMP
followed by a not-taken B.GE) scenarios. The older `conditional_fallthrough`
uses CBZ and ADD; it benefits from the direct ADD-source path, not NZCV decoding.

The final run uses 20,000,000 iterations per scenario, three rounds, and alternating
version order for each adjacent scenario pair. Benchmarks run on logical CPU 0.
Game threads were temporarily restricted to CPUs 2–7, separating them from both
SMT threads of the benchmark core; original per-thread affinities were saved and
restored afterward. These are isolated synthetic measurements, not gameplay FPS
or complete loading-time measurements.

| Scenario | Baseline ns/guest | Candidate ns/guest | Time change | Host bytes before → after |
| --- | ---: | ---: | ---: | ---: |
| `gpr_cached` | 0.4956 | 0.3578 | -27.80% | 1312 → 544 |
| `simd_cached` | 0.3815 | 0.3858 | +1.13% | 1056 → 1056 |
| `conditional_fallthrough` | 0.3939 | 0.2333 | -40.77% | 956 → 572 |
| `mixed` | 0.4454 | 0.4351 | -2.31% | 1260 → 1068 |
| `small_immediates` | 0.7525 | 0.6884 | -8.52% | 1120 → 928 |
| `immediate_memory` | 0.7782 | 0.7719 | -0.81% | 3044 → 3044 |
| `condition_select` | 1.2240 | 0.9275 | -24.22% | 4112 → 2384 |
| `flag_conditionals` | 1.8428 | 1.3047 | -29.20% | 4024 → 3128 |

All checksums match. All eight scenarios pass the 3% latency/code-size gate.
The unchanged SIMD and memory controls vary by +1.13% and -0.81%, respectively.
The mixed-case latency change of -2.31% is small relative to measurement variation.

Earlier unrestricted-game runs (`pinned/` and `pinned-paired/`) failed the memory
control gate, with large cycle variation despite essentially identical instruction
counts. Those logs are retained; they motivated physical-core separation, rather
than changing thresholds or discarding a failing target scenario. The final
`isolated-paired/` result is reported above.

The user clarified that the original pre-optimization loading sample missed part
of loading, whereas the subsequent sample was complete. Their 225.30/273.38-second
windows are not comparable full-load durations. The user felt the first batch was
faster. This second batch passed the post-deployment startup check described below;
the first user-controlled loading sample after this batch is documented below.

## Artifacts and reproduction

Workspace directory: `logs/jit-conditions-20260907/`.

- `initial-worktree.patch` records all pre-existing changes; `optimization-only.patch`
  contains only this batch and applies to the saved pre-edit source.
- `baseline/` and `candidate/` preserve the compared binaries.
- `candidate-build-final.log`, `candidate-final-run/correctness.log`, `host-tests.log`,
  and `product-build-final.log` record final validation.
- `isolated-paired/run-isolated.py` preserves/restores game affinity;
  `run-ab.py` runs the adjacent pairs; median JSONL files and `ab-comparison.txt`
  contain results. `original-affinity.json` and `restore-affinity.log` document cleanup.
- `deploy-candidate.sh` checks both library hashes and backs up the installed version
  before any restart. Its execution is recorded in `deployment.log`.

## Deployment and rollback

The user confirmed the match was finished and requested deployment. Library-only
deployment completed at 23:04 on 2026-09-07. The Android-visible library has the
candidate SHA-256 above; its inode matches the mapped library in the game process.
Waydroid session/LXC are running and Android reached `sys.boot_completed=1`.

金铲铲之战 was started through its policy activity; Activity Manager reported
`Status: ok` and `.ApolloZGame`. Android PID 2868 loaded the new Berberis library,
ARM64 Unity and IL2CPP, and remained alive with an empty crash buffer in the
post-launch check. This is startup validation, not a full-match stability or
loading-time measurement.

Previous first-batch library backup:
`/var/lib/waydroid/deploy-backups/20260907-230437-conditions/libberberis_arm64.so`
Its SHA-256 is `e222f893c44173802b100c3f56835e1fa120e279cb28dae2bb0328cc0b489807`.
Use this exact verified backup with the `DEVICE.md` library deployment procedure
to roll back, then restart the noctis session and recheck Android boot and hashes.

Evidence: `deployment.log`, `post-deploy-boot-initial.txt`,
`post-deploy-game-launch.log`, `post-deploy-game-maps.txt`,
`post-deploy-il2cpp.txt`, and `post-deploy-crash.log` in the artifact directory.
The built system/vendor images were not deployed.


## First full loading capture after deployment, 2026-09-08

The user-controlled loading window was 253.69 seconds, versus 273.38 seconds for
the previous complete first-batch capture: 19.69 seconds (7.20%) shorter. UnityMain
CPU time fell from 235.63 to 216.37 seconds (8.17%); read volume was similar at
353.84 versus 351.14 MiB. This is one cross-day observation after a host restart,
not a controlled A/B result; cache, match contents and manual boundaries can differ.
The earlier incomplete 225.30-second sample is excluded from this comparison.

52,392 cycles:u samples were recorded at 99 Hz with zero reported lost samples.
The candidate hash was verified and the captured crash buffer was empty.
UnityMain cycles remain concentrated in JIT code (82.16%) and the Berberis library
(12.26%); ART accounts for 0.21%. JIT ThreadState access locations account for
36.34% of main-thread cycles, including cache reloads at 16.27%. MOVE locations
remain 10.12% (6.05% excluding zero moves), so this capture does not independently
quantify the narrow direct-source optimization's effect. SIMD interpreter decoding
also remains prominent. Percentages are sampled cycle locations, not removable time.

Evidence: `logs/jkchess-match-conditions-20260908-120506/REPORT.md`, raw perf and
telemetry, matching-build symbol attribution, and instruction comparison artifacts.
