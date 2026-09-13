# Runtime and Translation Status

Last updated: 2026-09-13

This page tracks development-branch runtime results. It is not a statement about the older `v0.2.2` release unless explicitly noted.

## 2026-09-13 development source committed

The previously uncommitted runtime work is now recorded on each owning
repository's local `loongarch64/lineage-23.2` branch:

| Repository | Commit | Change |
| --- | --- | --- |
| Berberis | `bae6ed23` | Empty JNI arguments and mixed callback coverage |
| Berberis | `bf312782` | UCVTF fixed-point conversion with 64 fractional bits |
| Berberis | `7c40567f` | Explicit guest linker execution through the ARM64 runner |
| Berberis | `e7781782` | Runtime diagnostics enabled only by profiling |
| Berberis | `aad4bb61` | Five batches of game-loading JIT optimization and tests |
| Mesa | `3bbcc85` | Package-scoped Genshin GPU identity profile |

All ten Berberis working files retain their pre-commit content. The six files
in the fifth-batch candidate snapshot match the committed source byte for byte,
preserving the existing 189/189 runtime, 20/20 assembler and image-build evidence.
The Mesa file matches the deployed profile hash. This source checkpoint does
not rebuild or deploy the device, change release tags, or establish additional
gameplay or host-reset validation. These new commits have not been pushed as
part of this checkpoint; the helper branch was published earlier.

## 2026-09-13 Waydroid Helper keyboard mapping validated

The LoongArch64 helper fork is published on `factfinding/waydroid-helper`, branch
`loongarch64/main`, at `030d85e7d417a86818cba986d12cabd55bd83335`.
It supports the host architecture and explicit ADB targets with instance-owned
scrcpy cleanup. The device passes 110 Python tests, 11 subtests and three Meson
validation checks; the user confirms keyboard mapping works in Genshin.
The current mapper remains running. An earlier automatic host restart during
the trial has no established cause. See [installation and validation details](WAYDROID_HELPER.md).

## 2026-09-13 Genshin GPU identity profile deployed

The radeonsi drirc profile now returns ARM / Mali-G77MC9 only for the China
package `com.miHoYo.Yuanshen`. Five native Android EGL process controls verify
the package-name scope and unchanged versions, extensions and limits. The
restarted real game stores the new identity and initial instancing sizes
32/32, replacing its earlier 32/2 settings. The original strategy byte and
program-binary permission remain enabled.

Only `/vendor/etc/drirc` in the writable vendor overlay was replaced, with a
complete backup and restored read-only mount. The host and Waydroid stayed
in the same boot/session; only Genshin restarted. No cache data or JIT setting
was changed manually. The game may recompile entries automatically because
its source keys and graphics fingerprint can change. Stable gameplay now shows
visible water and reflected sky. A fresh trace and immediate inspection read
all 90 program objects identified by uniform events; water program 284 has a
32-element instance interface.
Three stable reads confirm its ten sampler locations 398–407 map to units 0–9
in both CPU uniform storage and fragment `SamplerUnits`, without manual sampler
correction. Fifth-batch JIT remains enabled. This validates the current scene;
the earlier host-reset cause remains a separate question. See
[the deployed profile and rollback](GENSHIN_GPU_PROFILE.md).

## 2026-09-13 renderer identity explains an instancing-path distinction

A native x86_64 EGL control in LDPlayer changes only its process-name
configuration and receives Adreno 750 under an ordinary name, Mali-G77MC9
under Genshin's name. The running game's capability object stores Mali and
uses initial instancing settings 32/32; la64 stores 32/2. LDPlayer water
program 1247 has a single initial key-0 owner and a reflected 32-element
instance interface. The current la64 water programs 276/278 both expose two
elements, with identical uniform interfaces. A subsequent bounded scan and
repeat reads establish their shared guest owner: key 0 maps to 276, selected
key 2 to 278, and key 32 to 277. Its vertex template is byte-identical to
the LDPlayer owner's template.

Original ARM64 reflection code computes that extent from parsed uniform-name
indices. The instancing metadata constructor clears its dynamic flag unless
the extent is exactly two, alongside other layout conditions. This identifies
a concrete route by which the graphics-identity difference avoids the faulty
reuse path. The current failure involves a same-size key-2 variant; expansion
is unnecessary. Original ARM64 fragments pass 10,384 independent Unicorn
checks. The owner snapshot does not trace historical calls or validate all
Berberis execution. No persistent fix is deployed;
the earlier temporary sampler correction and fifth-batch JIT remain in place.
See [the instancing-path audit](GENSHIN_INSTANCING_PATH.md).

## 2026-09-13 LDPlayer game control captures separate sampler locations and units

The same ARM64 Genshin version renders visible water through Houdini in
LDPlayer. Its live game capability snapshot has version enum 4 and strategy
byte 1, matching la64. Native GLES tracing captures 68 sampler assignments
across six water-interface programs: all use consecutive units, with zero
location-as-value assignments. Paired system/vendor arguments and query
returns agree; the startup trace reports no dropped events.

This establishes an actual initialization difference beyond independent shader
probes. It does not yet identify the guest branch or explain why corresponding
variants follow different initialization paths. Shader interfaces and graphics
settings also differ, so this is not a matched-variant control. See
[the emulator comparison](GENSHIN_EMULATOR_COMPARISON.md) for measured values,
probe validation, the isolated Houdini startup crash and remaining limits.

## 2026-09-13 water restored in a reversible sampler-binding control

In the running Genshin swimming scene, water program 278 assigned its ten
samplers to empty units 128–137. Reference program 276 has the same 99-uniform
interface and uses units 0–9, where the textures are actually bound. Correcting
only those sampler values through Mesa restored the water; rolling back made
it disappear; reapplying restored it again. CPU uniform storage and fragment
`SamplerUnits` agree in each state. The game is left with the corrected mapping.

This is a temporary change to the current program, not a persistent deployed
fix. Fifth-batch JIT remains enabled with the same library hash. The host and
game remained in the same boot/process through the final 13:06 check; debugger
and probes are gone. This establishes the current water symptom's dependence
on sampler bindings, without determining the earlier host-reset cause. See
[the controlled repair](GENSHIN_WATER_SAMPLER_REPAIR.md) for exact mapping,
reversal evidence, coverage limits and remaining work.

## 2026-09-13 12:29 gameplay reached after data clearing; water still missing

The user confirms successful entry into gameplay after clearing Genshin data,
with the water surface still missing. A read-only screenshot confirms gameplay;
host boot ID and game PID remain the same as the 09:28 check, about three hours
earlier. The game still maps fifth-batch Berberis and reports mode 1, 347,752 JIT
successes and 118,222 gear-ups. No device setting or game state was changed by
the agent during this check.

This advances the previous download-only observation. Data clearing has not
fixed the water symptom, while the host has remained in the same boot through
the download-to-gameplay interval. It does not prove permanent reset resolution
or independent root causes. Continue tracking the symptoms separately; the
previous water sampler-binding evidence remains a candidate requiring a fresh
program/sampler mapping and a controlled visual correction in this process.
Evidence: outer-workspace `logs/genshin-cleared-data-20260913/`,
`runtime-in-world.json` and `observation-in-world.json`.

## 2026-09-13 09:28 user cleared Genshin data; no reset reported so far

After JIT restoration, the user reports clearing Genshin's application data and
no further host reset so far. Read-only checks find the same host boot as the
restoration and Genshin host PID 15306 / Android PID 5072 using fifth-batch
Berberis, mode 1, 130,945 JIT successes and 43,395 gear-ups. The screenshot shows
a full resource download at 342.45 / 48,552.73 MB (0.71%). This differs from the
earlier 174.51 MB update download and resource-verification failure paths.

The observation prioritizes application data/cache and the execution paths they
select, but does not isolate a shader cache, prove data corruption, or identify
the mechanism of a whole-host reset. At that check, download completion,
in-world stability and water rendering were unverified. The agent performed only read-only
checks; the user's exact clearing operation/time was not captured. Evidence:
`logs/genshin-cleared-data-20260913/` in the outer workspace.

## 2026-09-13 09:15 Berberis JIT restored on user request

The interpreter control has ended. Only `berberis.mode` was restored to
`lite-translate-or-interpret` in the three Waydroid configuration/property files;
ART retains `dalvik.vm.usejit=true`. The fifth-batch library remains
`c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`.
The preceding configuration is backed up at
`/var/lib/waydroid/deploy-backups/20260913-091517-restore-berberis-jit/`.

Waydroid and the noctis graphical session were restarted, and Android reached
`sys.boot_completed=1`. A normal WaterProbe launch (automatic matrix disabled)
verified mode 1, 34,616 JIT successes and 15,656 gear-ups in host PID 13050 /
Android PID 2949. The verifier checks both the installed and mapped library
content before reading known-build offsets. No Genshin launch or host-reset
reproduction was performed during restoration. This is configuration validation,
not a fix for the rendering or whole-host reset problems. Evidence is in
`logs/genshin-restore-jit-20260913/` in the outer workspace.

## 2026-09-13 earlier Berberis JIT-disabled host-reset control

At the user's request, the September 12 23:55 configuration change sets
`berberis.mode=interpret-only`; native ART remains enabled for this control.
The fifth-batch library hash is unchanged. Android booted and Genshin launched
once as host PID 6867 / Android PID 3804 in boot `ebd8ae9f…`. Direct process
checks through 00:12:52 verify mode 0, zero JIT successes and zero gear-ups.
The host has not rebooted during approximately 15 minutes of this run, but the
app remains on a white startup surface with repeated `NullReferenceException`
in `GameManager.Update` and `LateUpdate`. It has not reached the earlier
resource-download failure stage, so this does not establish whether JIT caused
the host reset. The configuration remains in place. See
[the interpreter control](GENSHIN_NO_JIT_RESET_CONTROL.md)
for configuration backups, live evidence and observation status.

## 2026-09-12 Genshin-associated host resets under investigation

Seven unexpected whole-host resets are confirmed by boot/journal boundaries.
The fifth was covered by an external reconnecting collector: Genshin's last
identifiable stage was resource verification of 1,684 files, about 94 seconds
after its main process started. The final sensor sample shows CPU 44°C,
GPU 54°C and 7.237 GiB available RAM. Neither direct dmesg nor the saved journal
contains a panic, GPU timeout or OOM identifying the cause. These observations
do not establish a hardware fault, JIT regression or connection to missing water.

Following that reset, `kernel.panic` was temporarily changed from 30 to 0 in
boot `1415cf78cb35488080c7d5f8143d341f` so a possible panic can remain onscreen;
the existing `drm.panic_screen=kmsg` setting was unchanged. This is diagnostic
preparation, not a fix, and may require manual restart after a panic. No
persistent configuration, product library or optimization setting was changed.
The next boot restores the configured timeout; immediate rollback is
`ssh la64-root 'sysctl -w kernel.panic=30'`.
See [the host reset investigation](GENSHIN_HOST_RESETS.md) for coverage gaps,
clock offsets, exact evidence and remaining uncertainty.

## 2026-09-12 full optimization restoration rechecked

The user requested restoration of optimizations disabled during the Genshin
investigation. Read-only device checks confirmed that the September 11
restoration remains active: both the overlay and mounted Berberis library have
the complete fifth-batch SHA-256
`c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`.
Live properties and all three persistent Waydroid configuration files agree on
`berberis.mode=lite-translate-or-interpret` and `dalvik.vm.usejit=true`.
No nonempty app wrapper properties or additional Berberis threshold overrides
were present. The audited host service/LXC configuration had no diagnostic
environment overrides. The requested configuration was already in effect, so
no redeployment, configuration rewrite or restart was needed.

Android boot completion and core processes were checked. Genshin started during
verification (host PID 6739 / Android PID 4087). Its mapped library hash/inode
matched the fifth batch; a bounded read-only runtime check found translation
mode 1, 15,200 JIT successes and 3,679 gear-ups. No `BERBERIS_MODE` environment
override was present. ART's enabling property is true; this check does not
claim new ART-generated executable code or a visual rendering fix. Evidence:
`logs/genshin-optimization-restoration-20260912/verified-state.json` and
`game-jit.json` in the outer workspace. The water sampler-binding investigation is recorded in
[the variant-binding report](GENSHIN_SHADER_VARIANT_BINDINGS.md).

## 2026-09-11 water-related GLES control

After the user identified possible missing water in OpenGL Genshin, a separate
ARM64/IL2CPP water probe tested alpha blending, sampled depth, GrabPass copy and
refraction, planar reflection with three render-target formats, and ordinary
versus instanced draws. Windows/D3D11 and la64/GLES3 completed all twelve cases;
all camera/screen captures were reviewed without reproducing missing water.
Fifteen selected GLES entry points were present. All 797 sampled GL diagnostic
events had zero GL errors and complete FBOs; the final Unity log had no errors.
Device JIT remains enabled and was verified in the probe process. These results
do not rule out game-specific shader, resource, JIT or driver defects. See the
[water test report](UNITY_WATER_PROBE.md) for artifacts and limitations.

## 2026-09-11 JIT restored; standalone Terrain probe

The interpreter-only Genshin control was too slow and reported a network failure
before a useful scene comparison. This run does **not** rule out JIT-related
rendering defects, nor establish that the network error was caused by a timeout.
The device has been restored to fifth-batch Berberis
`c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`,
`berberis.mode=lite-translate-or-interpret`, and `dalvik.vm.usejit=true`.
Android boot completion and validated Ethernet connectivity were checked;
Genshin's process maps the restored library. In-game login success remains unverified.
Previous library/configuration backup:
`/var/lib/waydroid/deploy-backups/20260911-194856-genshin-restore-jit/`.

A standalone Unity Terrain/ordinary-Mesh matrix is under
`tests/unity-terrain/`. It avoids networking and game assets, records CPU data
checks and fixed-view screenshots, and supports separate GLES3/Vulkan ARM64
IL2CPP builds. All three builds succeeded; Windows/D3D11 and la64/GLES3 each
completed ten cases with passing CPU checks and visually continuous surfaces
in all camera and screen captures. Vulkan-only initialization could not load
its driver, and the per-app interpreter wrapper failed before entering Unity;
neither is a valid rendered comparison. See the
[Terrain probe report](UNITY_TERRAIN_PROBE.md) for evidence and limitations.
The initial
2022.3.72f1 Editor recommendation was unsuitable for the available Personal
license (Extended LTS restriction); 2022.3.62f3 was installed and used successfully.
Restoration and build logs: `logs/genshin-restore-jit-20260911/`.

## 2026-09-09 Genshin interpreter-only control

At the user's request, both Berberis and ART JIT compilation were disabled at
22:16 (UTC+8): `berberis.mode=interpret-only`, `dalvik.vm.usejit=false`.
Waydroid configuration and generated property files were backed up under
`/var/lib/waydroid/deploy-backups/20260909-221655-genshin-no-jit-config/`.
These settings survive Waydroid restarts until restored. The installed library
remains `e76c0a2851c50314a7ac0779960949e43daf2173290db9f4a7784a8f2ab72c5b`.

Android booted and Genshin PID 2387 (host 9596) launched. Matching-Build-ID
symbols allow direct process verification: translation mode 0 (interpret-only),
JIT successes 0 and gear-ups 0 on two checks. ART has no executable jit-cache
mapping; its profiling-only cache/thread pool remains because profiling is
separate from compilation. AOT code, bridge stubs and GPU shader compilation
remain active. The captured crash buffer is empty; scene comparison is pending.
Evidence and detailed limitations: `logs/genshin-textures-20260909/REPORT.md`.

## 2026-09-09 Genshin terrain regression investigation

Fifth- and second-batch screenshots show extensive missing terrain with
characters/UI and some rocks/trees visible. The user also reports visual problems
on the third batch; its captured viewpoint differs. Each control's game-process
library hash/inode was verified in the scene. No known-good version is established.

At 12:45 (UTC+8), the ongoing comparison skipped the first batch and switched to
the **library preceding all five recent game-loading optimization batches**:
`e76c0a2851c50314a7ac0779960949e43daf2173290db9f4a7784a8f2ab72c5b`.
This still includes the earlier JIT and historical optimizations. Its visual
result is pending; installation alone does not establish a fix. Android boot
completed; Genshin PID 1596 (host 22951) maps the verified hash/inode. Launch
returned `Status: ok` and the captured crash buffer is empty.
Preserved libraries:

- Fifth batch: `/var/lib/waydroid/deploy-backups/20260909-122747-genshin-third-round-control/libberberis_arm64.so`.
- Third batch: `/var/lib/waydroid/deploy-backups/20260909-123702-genshin-second-round-control/libberberis_arm64.so`.
- Second batch: `/var/lib/waydroid/deploy-backups/20260909-124559-genshin-preoptimization-control/libberberis_arm64.so`.

No game data, images or graphics settings were changed. Evidence and control
scripts: `logs/genshin-textures-20260909/`.

## 2026-09-08 game-loading SIMD fallback deployment

The fifth batch adds seven observed fallback families: SHL/USHR 2S/4S,
CMTST 2S/4S, FMAX 4S, BIC 8B/16B, BSL 8B, and UMOV W from any S lane.
New vector writes normalize inactive lanes before updating ThreadState and
register caches. Unity/IL2CPP opcode evidence is recorded separately from
AkSoundEngine audio-thread evidence; no exact main-thread speedup is inferred
from shared opcode-bucket counts. See [scope and validation](BERBERIS_SIMD_FALLBACKS.md).

- Deployed on user request at 21:57 (UTC+8); Android reached `sys.boot_completed=1`.
- Device correctness: 189/189; host assembler tests: 20/20.
- Final translator module build: 01:25; system/vendor image build: 01:33.
  The subsequent benchmark CLI correction's module/image targets passed in 01:20.
- Fourteen original JIT scenarios pass the unchanged 3% latency/size gate in
  five A/B pairs, with unchanged generated sizes and matching checksums.
- Seven new scenarios pass five paired JIT/interpreter comparisons with matching
  checksums. These repeated-instruction gains are not game-loading speedups.
- Candidate SHA-256: `c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`.
- Pre-deployment benchmark affinities were restored and verified. Deployment restarted Waydroid.
- Previous-library backup: `/var/lib/waydroid/deploy-backups/20260908-215745-simd-fallback/libberberis_arm64.so`.
- Game PID 1831 (host 33580) maps the hash/inode-verified new library and Unity;
  the captured crash buffer is empty. IL2CPP was not yet mapped at the last check,
  so full engine initialization and match loading remain unvalidated. Sampling has not started.

## 2026-09-08 cache initialization and width deployment

The fourth optimization batch adds single-instruction TBI/32-bit normalization, direct cached
sources for zero-shift non-flag-setting W arithmetic/logic, and control-flow-aware
GPR initialization. Write-first loads are omitted, later-block loads are delayed,
and loop-crossed loads are hoisted before backedge targets. ThreadState writes
remain immediate. Regions with active SIMD caching retain eager GPR initialization
after broader variants caused a repeatable mixed-SIMD regression.
See [validation and scope details](BERBERIS_DEMAND_WIDTH.md).

- Deployed on user request at 20:47 (UTC+8); Android boot completed and the
  noctis graphical session and LXC container are running.
- Device suite: 181/181, including a real memory-fault recovery test, pending signals,
  nested backedges, and W aliases; host assembler suite: 19/19.
- Final system/vendor image build passed in 01:30.
- Five A/B pairs for each of fourteen microbenchmarks pass the 3% latency/size gate.
  W arithmetic/logic latency -58.71%; memory scenarios -7.16% to -8.56%; mixed SIMD
  -0.17%. Cache-initialization cases change by less than 1%, not a clear speedup.
- Deployed SHA-256: `5f540b72a5571dada88b6caff75f275a2ee9ca1f2f1a249d43d05e37c5b0dc95`.
- Previous-library backup: `/var/lib/waydroid/deploy-backups/20260908-204709-demand-width/libberberis_arm64.so`.
- Game PID 1957 (host 16888) maps the verified new library, Unity and IL2CPP;
  the captured post-launch crash buffer is empty.
- Game affinities restored. First full loading capture: 228.10 s versus the prior
  235.83 s (3.28% shorter), main CPU 192.37 versus 199.21 s. Reads decreased from
  378.88 to 129.21 MiB, so this is not a controlled code speedup.
- GPR cache-initialization sampled share 20.54% → 17.16%; SLLI/SRLI share
  7.28% → 2.18%. ThreadState total remains 35.45%; interpreter hotspots persist.
  44,230 samples, lost=0, matching library hash and empty captured crash buffer.

## 2026-09-08 SP caching and logical-source deployment

A new candidate caches hot SP values in the existing seven GPR slots, keeps all
SP writes immediately visible in ThreadState, combines cached memory bases with
address offsets, and directly consumes cached sources for zero-shift 64-bit
AND/ORR/EOR. It was deployed on user request at 12:41 (UTC+8). Android boot
and a game-launch smoke check passed. See [SP/logical validation and
rollback](BERBERIS_SP_LOGICAL.md).

- Device tests: 175/175; system/vendor build passed in 01:32.
- Eleven microbenchmark scenarios pass the 3% latency/size gate. Three paired
  runs show stack-writeback latency -48.46%, stack reads -3.81%, and ordinary
  immediate memory -3.75%; logical code size -48.48% with unchanged latency.
- An initial +3.30% condition-select control result prompted ten fixed additional
  pairs; all thirteen pairs pooled show -0.20% median latency. No samples omitted.
- Deployed SHA-256: `e80a43d5dbc6996b3f643a806c1f0d6d5320bd52e27a3760ff37b97c81460cf8`.
- Previous-library backup: `/var/lib/waydroid/deploy-backups/20260908-124133-sp-logical/libberberis_arm64.so`.
- Android reached `sys.boot_completed=1`; game PID 1563 mapped the new library,
  Unity and IL2CPP, with an empty captured crash buffer.
- Game affinities restored and verified. These synthetic results do not quantify
  complete match-loading improvement.
- First post-deployment full loading window: 215.73 s versus 253.69 s (14.96%
  shorter), with main CPU time 185.91 s versus 216.37 s. Storage reads were
  much lower (86.31 versus 351.14 MiB), so this is not a controlled code speedup.
  See the linked report for SP/cache hotspots and attribution limits.
- Evening repeat with the same library: 235.83 s, main CPU 199.21 s, storage
  reads 378.88 MiB. This is 7.04% shorter than the second-batch window; it also
  shows why the earlier 215.73 s result should not be treated as a fixed speedup.
  SP/MOVE hotspot changes persist; GPR entry reloads now account for 20.54%.

## 2026-09-07 conditions and direct-source deployment

This earlier development-device library adds selective NZCV condition evaluation,
zero-shift removal, and direct cached sources for a narrow 64-bit ADD/SUB path.
It also fixes a shifted 32-bit SUBS carry boundary exposed by expanded tests.
ThreadState write-through and cache-register allocation rules are preserved.
See [validation and rollback details](BERBERIS_CONDITIONS.md).

- Device suite: 171/171; host assembler suite: 18/18.
- Final system/vendor image build passed in 01:28; deployment replaced only the library.
- All eight microbenchmarks passed the 3% regression gate with the game separated
  from the benchmark's physical core; original game affinities were restored.
- Deployed SHA-256: `723ad863b1d25ac5fc84a4d07e2dcf6b7e3e5ec493ee23c6419aa81a7e11afa9`.
- Previous-library backup: `/var/lib/waydroid/deploy-backups/20260907-230437-conditions/libberberis_arm64.so`.
- Android reached `sys.boot_completed=1`; 金铲铲之战 loaded the new library, Unity,
  and IL2CPP with an empty crash buffer in the post-launch smoke check.
- First user-controlled complete loading capture on 2026-09-08: 253.69 s versus
  the previous complete 273.38 s; main-thread CPU time 216.37 s versus 235.63 s.
  The 7.20% shorter window is a single cross-day observation, not a controlled
  optimization speedup. See the linked report for remaining hotspots and limitations.

## 2026-09-07 immediate-lowering deployment

This earlier deployment used the shorter-constant and immediate-address
Lite JIT candidate described in
[the immediate-lowering validation report](BERBERIS_SMALL_IMMEDIATES.md).
Device correctness passed 167/167 and host assembler tests passed 17/17.
After library-only deployment, Android reached `sys.boot_completed=1` and
金铲铲之战 loaded the new library, Unity, and IL2CPP with an empty crash buffer.
The user clarified that the baseline loading sample was incomplete and the
post-deployment sample complete; their window durations are not comparable.
The user reports somewhat faster loading, without a quantified speedup.
Main-thread constant-building instruction locations fell from 13.06% to
6.44%; see the linked report for workload and profiling limitations. The small-immediates system/vendor image build subsequently passed (34:16).

- Deployed SHA-256: `e222f893c44173802b100c3f56835e1fa120e279cb28dae2bb0328cc0b489807`.
- Previous-library backup: `/var/lib/waydroid/deploy-backups/20260907-221330-small-immediates/libberberis_arm64.so`.
- ThreadState write-through and register allocation rules remain unchanged.

## Validated platform

- LineageOS 23.2 / Android 16 runs under Waydroid on an AOSC OS LoongArch64 host.
- The container reaches `sys.boot_completed=1` with LXC 7.0.0 and seccomp enabled.
- Native LoongArch64 ART, bionic, system services, Chromium WebView, audio, networking, and Mesa GPU acceleration have runtime validation.
- The ABI list prefers `arm64-v8a` for Native Bridge applications while retaining native `loongarch64` and `lp64d` support.
- ARM64 application libraries are loaded through `libberberis_arm64.so`.
- Legacy RenderScript calls made by ARM64 applications use the ARM64
  `librs_jni.so`, `libRSDriver.so`, and `libRSCpuRef.so` stack through
  Berberis. Native LoongArch64 RenderScript remains disabled because libbcc
  has no LoongArch64 backend.

## ARM64 translation pipeline

The LoongArch64 Berberis port is no longer interpreter-only. The current development pipeline is:

```text
ARM64 region
  -> LoongArch64 Lite Translator
  -> generated LoongArch64 machine code
  -> interpreter fallback for unsupported instructions or regions
```

The Lite JIT covers a growing set of integer, branch, memory, atomic, floating-point, and NEON operations. Unsupported paths still enter `InterpretBatch()`, so translation coverage and generated-code quality remain the main CPU-performance limits.

## Write-through GPR cache

The validated development build enables region-local guest GPR mapping:

- Up to seven repeatedly read ARM64 GPRs are cached in LoongArch64 `$s0`-`$s6`.
- Commit `5f0c728d` obtains exact reads and writes through the real translator
  decoder, excluding destination-only registers and ranking write-heavy values
  below source-heavy values.
- Reads use the cached host register.
- Every guest-register write is immediately stored to `ThreadState` and then reflected in the cache.
- `$s8`/`r31` remains the `ThreadState` base. `r21` and `$tp` remain non-allocatable.

Immediate write-through is a correctness requirement, not merely a conservative setting. Generated code may be left through signal delivery, memory-fault recovery, helper calls, or other exceptional exits that bypass a normal region-end flush. A previous deferred-writeback design correlated with application crashes; the isolated write-through implementation has not reproduced them.

## Write-through SIMD cache

Commit `4f457388` added a conservative region-local cache for repeatedly read ARM64 SIMD registers. Commit `3bce713e` extends it to a narrow audited class of full-width floating-point destinations:

- Up to five repeatedly read guest vector registers are cached in LoongArch LSX `$vr4`-`$vr8`.
- Full-width `FMUL`, `FDIV`, `FADD`, `FSUB`, `FMLA`, and `FMLS` destinations may be cached because their audited `StoreV()` lowering writes through before updating the LSX copy.
- Partial writes, lane writes, structure-load destinations, and unaudited writers remain excluded.
- Guest vector writes remain immediately visible in `ThreadState`; there is no deferred SIMD writeback.
- Each directly dispatched target region reloads its own selected vector cache at entry.

In the device regression sequence, five repeated `FMUL V.4S` instructions reduced source-vector loads from ten to two while preserving the same result. This initial implementation deliberately favors correctness over aggressive cache coverage.

## CFI-safe native callback closures

ARM64 applications can pass guest callbacks to native host libraries. Berberis uses libffi closures to adapt these callbacks to the LoongArch64 host ABI. The earlier anonymous executable closure mapping could randomly occupy a 256 KiB CFI shadow slot owned by an unrelated CFI-enabled DSO. A host indirect call would then ask that unrelated DSO to validate the closure and could terminate with `SIGILL`.

Commit `e401483b` replaces anonymous executable closure mappings with a 256 KiB static trampoline table inside `libberberis_arm64.so`:

- 16,384 fixed 16-byte LoongArch64 trampoline entries are part of the library's registered executable segment.
- A dispatcher maps each entry to a process-lifetime `ffi_closure` without clobbering callback argument registers.
- Slot allocation and publication are atomic; concurrent wrapper construction is covered by tests.
- Pool exhaustion is fatal and explicit. There is no fallback to an unsafe anonymous executable mapping.

AAudio's `AAUDIO_ERROR_ILLEGAL_ARGUMENT` (`-898`) observed during rapid uninstall/reinstall stress was diagnosed separately. Audioserver reported that the newly assigned application UID had not yet reached `NativePermissionController`; those attempts never created a stream or entered a callback and are not CFI failures.

## Verification on 2026-08-16

- Built `libberberis_arm64.so` from `e401483b` on `loongarch64/lineage-23.2`; it includes the validated write-through GPR cache from `d0cfbe2` and the static closure trampoline fix.
- Passed `115/115` `LoongArch64RuntimeLibraryTest` tests on the LoongArch64 Waydroid device.
- Deployed library SHA-256: `d5c15d3d11eef579d4251b480303448d30af5563b66fd5e3b71011576d76ffa0`.
- Waydroid reached `sys.boot_completed=1`; the Android crash buffer was empty after deployment.
- Three consecutive AAudio mode-5 runs completed about 5,000 callbacks each with no CFI, `SIGILL`, or fatal signal. A concurrent stress mode containing 1,600 stream-open attempts also completed.
- A cold launch of `com.kurogame.mingchao` remained alive past 60 seconds. The LXC and `system_server` PIDs remained unchanged, and the process had no anonymous `berberis-ffi-closure` executable mapping.

## Verification on 2026-08-17

- Extended linear regions through conditional-branch fallthrough in `dbd1c9c9`; taken branches remain translation-cache side exits.
- Added the source-only SIMD cache in `4f457388` and independently verified the new LoongArch `VOR.V` encoding. Structure-load destinations, including `LD1R`, have explicit stale-cache regression coverage.
- Lowered ARM64 vector AND/OR/EOR directly to LSX in `54e4923e`, including the previously interpreted 64-bit AND/OR forms. Repeated logical sources now use the region SIMD cache instead of four scalar `ThreadState` loads per instruction.
- Passed `125/125` `LoongArch64RuntimeLibraryTest` tests on the LoongArch64 device.
- Deployed library SHA-256: `b429e9be5834bbe8dc5021cbb6593d41af2b22c839d14702bf3ba3bff59f129e`.
- Waydroid reached `sys.boot_completed=1`; Bilibili completed a cold launch, remained alive, and the Android crash buffer stayed empty.
- Deployment backup: `/var/lib/waydroid/deploy-backups/20260818-120201-lsx-logical`.

## Verification on 2026-08-18

- Commit `b9b6b447` routes `DUP V.16B`, `DUP V.2D`, zero/one `MOVI`, and
  `FABS V.4S` through LSX and the common cache-coherent vector helpers.
- `DUP V.16B` no longer uses a mask, 64-bit multiply, and two scalar stores;
  it lowers to an LSX byte broadcast plus the normal vector write-through.
- The SIMD liveness pass now recognizes `FABS V.4S` as unary instead of
  treating opcode bits as a phantom `Rm` source. Five repeated FABS operations
  therefore load their shared guest source once with register mapping enabled,
  versus five times without mapping.
- LLVM 21 independently verified the new `VREPLGR2VR.B` and
  `VREPLGR2VR.D` encodings. Host assembler tests and all `126/126`
  LoongArch64 runtime tests passed on the device.
- Deployed library SHA-256:
  `5aac25f6f7cc0ba546fe871e537f1f8b07d8856cf4cff1c8e84bcd314fa65519`.
- Waydroid reached `sys.boot_completed=1`; the graphical session and core
  Android processes remained running, and the crash buffer was empty.
- Deployment backup:
  `/var/lib/waydroid/deploy-backups/20260818-121818-lsx-broadcast-fabs`.
- Commit `fdde08fa` replaces scalar lane accesses for ARM64 `UZP1`, `UZP2`,
  `ZIP1`, `ZIP2`, and `TRN1` 4S forms with cache-aware LSX picks and
  interleaves. Source/destination alias cases match the interpreter.
- Five repeated ZIP operations reduce source-vector loads from ten to two with
  SIMD register mapping enabled. The expanded device suite passes `127/127`.
- Current deployed library SHA-256:
  `b7878c4162b72cf9b6ea13e5523e993840181ab7619c138aaeecf49e55232929`.
- Current deployment backup:
  `/var/lib/waydroid/deploy-backups/20260818-123045-lsx-permute`.
- Commit `41264228` replaces scalar chunk assembly for both ARM64 EXT forms
  with cache-aware LSX byte shifts. The 64-bit form explicitly concatenates
  only the low source lanes and clears the destination's upper half.
- All legal 64- and 128-bit offsets, destination/source aliasing, and repeated
  source caching pass differential tests. Five repeated EXT operations reduce
  source-vector loads from ten to two; the full device suite passes `128/128`.
- Current deployed library SHA-256:
  `2233be9a7dd0a9575ff2b13772c11176579271f0d3f41a83fc1faeaf25347899`.
- Current deployment backup:
  `/var/lib/waydroid/deploy-backups/20260818-125944-lsx-ext`.
- Commit `6c0eafa7` replaces scalar lane extraction for ARM64 `FADDP V.2S`
  with a cache-aware LSX interleave, split, and vector add sequence. Inactive
  lanes are zeroed before addition so they cannot raise extra FP exceptions.
- NaN, signed-zero, destination alias, and repeated-source tests match the
  interpreter. Five repeated FADDP operations reduce source-vector loads from
  ten to two; the full device suite passes `129/129`.
- Current deployed library SHA-256:
  `c77248a50a5ff5f25275ed4148243b000dec750aaf8a0041eb0ad7cbdd3b5240`.
- Current deployment backup:
  `/var/lib/waydroid/deploy-backups/20260818-131325-lsx-faddp`.

## Verification on 2026-08-21

- Commit `c83b7649` adds repeatable LoongArch64 JIT microbenchmarks for GPR
  caching, SIMD caching, conditional fallthrough, and mixed arithmetic.
- The integration runner executes the full correctness suite, emits JSONL
  latency/code-size data, collects hardware counters with `perf stat`, and can
  fail an A/B run automatically when latency or code size regresses by 3%.
- Commit `5f0c728d` replaces raw ARM64 instruction-field counting with exact
  GPR read/write collection through the existing translator decoder. Guest
  writes remain immediately visible in `ThreadState`.
- Against the `c83b7649` baseline, GPR latency fell 17.08% and generated size
  fell 16.41%; conditional-fallthrough latency fell 12.54% and size fell
  12.81%. The other two scenarios also remained within the regression gate.
- All `145/145` device runtime tests passed. Deployed library SHA-256:
  `be8140d98ce65302d5aef7712349daea699762555e49dbeb255c95b26f23cc94`.
- Waydroid reached `sys.boot_completed=1`; `zygote64`, `surfaceflinger`, and
  `system_server` are running and the Android crash buffer is empty.
- Deployment backup:
  `/var/lib/waydroid/deploy-backups/20260821-222249-berberis-source-aware-gpr`.

## Verification on 2026-08-23

- Commit `3bce713e` moves all guest-memory fault recovery exits after the normal
  region body and removes redundant hot-path branches from structure memory
  operations. Nearby exits update the guest PC relative to `$s7` with one
  `ADDI.D` instead of materializing a full address.
- Added immediate and register post-index lowering for 32-bit `LD1/ST1` lane
  forms, including the hot Unity `ST1 {Vt.S}[lane], [Xn], #4` pattern.
- Audited full-width floating-point accumulators can now remain in the
  write-through SIMD cache. A repeated-FMLA regression reduces vector loads
  from 15 to three and verifies the final `ThreadState` value.
- The gear-up threshold is runtime-selectable through
  `berberis.gear_switch_threshold`; the compiled default remains 1000.
- All `149/149` device runtime tests pass. The four automated microbenchmarks
  pass the 3% regression gate; generated size fell by 0.78% to 2.44% against
  the previous two-tier baseline.
- A controlled 40-second `com.tencent.jkchess` cold-launch comparison read the
  requested threshold in each new process. Threshold 1000 reported a 7.237 s
  activity start, while threshold 128 reported 3.463 s and geared substantially
  more regions. This is promising but order/cache effects mean it is not yet a
  definitive gameplay result.
- Deployed library SHA-256:
  `e019663468123fc740ed399fbf3a1bdccf51361ee9d0b9eb7318cfa01e93035a`.
- Deployment backup:
  `/var/lib/waydroid/deploy-backups/20260823-160628-five-items`.

## Verification on 2026-08-30

- Added an ARM64 Native Bridge variant of `librs_jni.so`. Public NDK bitmap
  and native-window APIs replace dependencies on host-private framework C++
  objects at the guest boundary.
- The framework keeps `config.disable_renderscript=1` for native LoongArch64
  processes, but lazily loads the guest JNI library when an `arm64-v8a`
  application runs with `ro.dalvik.vm.native.bridge=libberberis_arm64.so`.
- Berberis exposes only `librs_jni.so` through the ARM64 guest namespace link;
  the LoongArch64 host library is not made public to applications.
- A minimal ARM64 APK completed `RenderScript.create()` and displayed PASS
  after a container restart with no temporary property override. Its process
  mapped the guest JNI, driver, and CPU reference libraries.
- YouTube `21.34.243` loaded the guest RenderScript stack, fully drew its main
  activity, remained alive for the 90-second observation window, and left the
  Android crash buffer empty.
- All `163/163` LoongArch64 Berberis runtime tests passed on the device.
- Effective overlay SHA-256 values are
  `4a6973704d95a57bbd323bb06bde77e8b08381e6d4ad656eff962d54b66477ef`
  for `framework.jar`,
  `a448293d3148b56c6923b8090717d6b4f537d76ad75b756f739c807a8ab2b218`
  for the guest `librs_jni.so`, and
  `e76c0a2851c50314a7ac0779960949e43daf2173290db9f4a7784a8f2ab72c5b`
  for `libberberis_arm64.so`.
- Final source-matched deployment backup:
  `/var/lib/waydroid/deploy-backups/20260830-185315-arm64-renderscript-source-match`.
- Legacy RenderScript graphics surfaces, FileA3D assets, and font-asset APIs
  are deliberately unsupported across the Native Bridge boundary. The
  validated target is the compute/bitmap path used by current applications.

## Remaining work

- Increase Lite JIT instruction and region coverage to reduce interpreter re-entry.
- Profile region formation, dispatch, helper calls, memory access, and JNI transitions on real applications.
- Expand syscall, signal, JNI, and Native Bridge correctness coverage.
- Keep application protection or emulator-detection failures separate from translation correctness bugs.
- Include the validated development commits in a coordinated tagged release before treating the cache as released functionality.
