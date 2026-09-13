# LoongArch64 Lite JIT immediate lowering, 2026-09-07

Status: deployed on 2026-09-07 after device tests and microbenchmarks; Android
boot and a game-launch smoke check passed. One post-deployment match-loading
sample is recorded below. The user confirmed the baseline window was partial
and the new window complete; total loading durations are not comparable.

## Motivation and implementation

The user-controlled 金铲铲之战 match-loading sample ran from 21:30:02 to
21:33:48 on 2026-09-07. UnityMain spent 83.12% of its sampled cycles in
translated code. Small constants and address offsets repeatedly expanded to
four constant-building instructions followed by a register ALU instruction.
This change addresses that shared overhead across the many main-thread regions.
The earlier application-update sample is not used as a match-loading baseline.

- Add `Assembler::LiOptimized` for variable-length 64-bit constants. It uses
  ADDI.D or ORI for small values and omits redundant upper-immediate operations.
- Use it for ordinary translated instruction constants. Preserve the original
  four-word `Li` for layout-sensitive callers and existing exit/dispatch paths.
- Lower encodable ADD/SUB immediates and memory address offsets to ADDI.D;
  eliminate zero-offset address additions.
- Preserve the original positive RHS for ARM64 NZCV calculations, 32-bit
  zero extension, SP/ZR behavior, TBI ordering, recovery points, and immediate
  ThreadState write-through. Register allocation is unchanged.

## Validation

- Build: `m -j8 libberberis_arm64 berberis_runtime_arm64_loongarch64_tests
  berberis_runtime_arm64_loongarch64_microbench berberis_host_tests` passed.
- Device correctness: **167/167** tests passed (baseline **163/163**).
- Host assembler tests: **17/17** passed.
- Added tests execute 25 boundary constants and 256 deterministic random
  constants with a poisoned destination, compare 960 arithmetic cases against
  the interpreter, exercise W/X/Q load-offset boundaries, and bound generated
  code size for simple immediate instructions.
- Added `small_immediates` and `immediate_memory` benchmark scenarios and
  included them in the standard runner's hardware-counter collection.
- Product build: `m -j8 systemimage vendorimage` passed (34:16).

## A/B results

Both binaries use the same six-scenario benchmark source. The baseline includes
all pre-existing uncommitted changes; their content is preserved. Its library
hash exactly matches the library deployed during the game sample.

The final comparison pins execution to logical CPU 2 on the Loongson 3A6000,
uses 20,000,000 iterations per scenario, and alternates baseline/candidate order
across three rounds. Values below are medians. The game remains running during
testing. An earlier unpinned run showed noise in unchanged control scenarios;
the pinned comparison is the reported result.

| Scenario | Before ns/guest | After ns/guest | Time change | Host bytes before → after |
| --- | ---: | ---: | ---: | ---: |
| `gpr_cached` | 0.4791 | 0.4885 | +1.96% | 1312 → 1312 |
| `simd_cached` | 0.3805 | 0.3744 | -1.60% | 1056 → 1056 |
| `conditional_fallthrough` | 0.3723 | 0.3698 | -0.67% | 956 → 956 |
| `mixed` | 0.4719 | 0.4161 | -11.82% | 1516 → 1260 |
| `small_immediates` | 0.7930 | 0.7451 | -6.04% | 1824 → 1120 |
| `immediate_memory` | 0.9518 | 0.7644 | -19.69% | 4068 → 3044 |

All checksums match, and every scenario passes the existing 3% latency/size
regression gate. Across all six scenarios, median user instructions decrease
from 53,691,591,046 to 43,770,500,899 (18.48%) and median user cycles decrease
from 10,943,753,375 to 10,026,259,630 (8.38%). These aggregate perf counts also
include process setup and benchmark harness overhead.

These are synthetic code-generation measurements, not a prediction of total
game loading-time improvement. The first post-deployment user-controlled
sample below is not duration-comparable to the incomplete baseline window. ThreadState traffic and flag handling
remain possible targets for subsequent work.

## Reproduction and artifacts

Local artifact directory: `logs/jit-small-immediates-20260907/` under the workspace.
It contains the initial worktree patch, optimization-only patch, both binaries,
module/product build logs, correctness output, and the three A/B rounds under
`pinned/`. `pinned/run-ab.py` records the exact alternating perf commands.
`ab-comparison.txt` in that directory contains the regression gate result.

- Berberis HEAD before changes: `dae27f2f` (plus preserved local changes).
- Baseline library SHA-256:
  `e76c0a2851c50314a7ac0779960949e43daf2173290db9f4a7784a8f2ab72c5b`
- Candidate library SHA-256:
  `e222f893c44173802b100c3f56835e1fa120e279cb28dae2bb0328cc0b489807`

The candidate is archived under `candidate/libberberis_arm64.so`.

## Deployment

Library-only deployment completed at 22:13 on 2026-09-07. The user approved
restarting Waydroid. The Android-visible library hash matches the candidate
above, and the game process mapping's inode matches the deployed library.
Waydroid session and LXC are running; `sys.boot_completed=1`.

金铲铲之战 was launched through
`com.tencent.jkchess/com.tencent.gcloud.msdk.core.policy.ZGamePolicyActivity`.
Activity Manager reported `Status: ok`, with `.ApolloZGame` as the resulting
activity. Android PID 3595 loaded the new Berberis library plus ARM64
`libunity.so` and `libil2cpp.so`; the crash buffer remained empty in the
post-launch smoke check. This validates startup only, not an entire match or
its loading-time improvement.

Previous library backup:
`/var/lib/waydroid/deploy-backups/20260907-221330-small-immediates/libberberis_arm64.so`
(SHA-256 equals the baseline hash above). To roll back, follow `DEVICE.md`'s
library deployment procedure using this exact verified backup as the source,
then restart the noctis session and recheck boot and hashes.

Local evidence: `deployment.log`, `post-deploy-status.txt`,
`post-deploy-game-launch-explicit.log`, `post-deploy-game-maps.txt`,
`post-deploy-game-runtime.txt`, and `post-deploy-crash.log` in the artifact
directory above. The full system/vendor image build is separate from this
library-only deployment and was still running at deployment time.

## First post-deployment match sample

The user-controlled 22:23:27–22:28:00 window lasted 273.38 seconds. The user
subsequently clarified that the previous 225.30-second sample missed part of
loading, while this sample covers complete loading. The two window durations
must not be used to claim a slowdown or calculate an end-to-end speedup.
The user reports that loading feels somewhat faster; this is subjective
feedback, and equal-boundary timing is still needed to quantify the gain.
Resource activity and profiling configuration also differ between samples.

Reading and decoding 13,983 sampled main-thread JIT IPs shows constant-building
instruction locations (LU12I.W/LU32I.D/LU52I.D/ORI) dropping from 13.06% to
6.44% of main-thread sampled cycles; excluding ORI, 10.30% to 5.32%.
ThreadState accesses remain at 33.02%, including 14.46% in GPR cache reloads.
This supports the targeted code-generation improvement while leaving other
substantial costs. Instruction-location shares are not precise stall costs.

The new game process did not enable `berberis.profiling`, so this sample has
no JIT guest-region map. Host JIT instruction analysis remains possible, but
exact ARM64 region attribution cannot be reproduced from this sample alone.
Both runs need matching profiling configuration for a controlled comparison.

All collection processes stopped, perf reported zero lost samples, and the
crash buffer remained empty. Detailed evidence and limitations are in the
workspace artifact `logs/jkchess-match-optimized-20260907-222327/REPORT.md`.
