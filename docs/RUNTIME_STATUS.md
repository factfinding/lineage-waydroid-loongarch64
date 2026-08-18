# Runtime and Translation Status

Last updated: 2026-08-18

This page tracks development-branch runtime results. It is not a statement about the older `v0.2.2` release unless explicitly noted.

## Validated platform

- LineageOS 23.2 / Android 16 runs under Waydroid on an AOSC OS LoongArch64 host.
- The container reaches `sys.boot_completed=1` with LXC 7.0.0 and seccomp enabled.
- Native LoongArch64 ART, bionic, system services, Chromium WebView, audio, networking, and Mesa GPU acceleration have runtime validation.
- The ABI list prefers `arm64-v8a` for Native Bridge applications while retaining native `loongarch64` and `lp64d` support.
- ARM64 application libraries are loaded through `libberberis_arm64.so`.

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

- Up to seven frequently used ARM64 GPRs are cached in LoongArch64 `$s0`-`$s6`.
- Registers used only once are not cached, limiting code-size growth.
- Reads use the cached host register.
- Every guest-register write is immediately stored to `ThreadState` and then reflected in the cache.
- `$s8`/`r31` remains the `ThreadState` base. `r21` and `$tp` remain non-allocatable.

Immediate write-through is a correctness requirement, not merely a conservative setting. Generated code may be left through signal delivery, memory-fault recovery, helper calls, or other exceptional exits that bypass a normal region-end flush. A previous deferred-writeback design correlated with application crashes; the isolated write-through implementation has not reproduced them.

## Read-only SIMD cache

Commit `4f457388` adds a conservative region-local cache for repeatedly read ARM64 SIMD registers:

- Up to five source-only guest vector registers are cached in LoongArch LSX `$vr4`-`$vr8`.
- Any register that may be written by a data-processing instruction, scalar/vector load, pair load, or structure load in the region is excluded. This includes partial vector destinations.
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

## Remaining work

- Increase Lite JIT instruction and region coverage to reduce interpreter re-entry.
- Profile region formation, dispatch, helper calls, memory access, and JNI transitions on real applications.
- Expand syscall, signal, JNI, and Native Bridge correctness coverage.
- Keep application protection or emulator-detection failures separate from translation correctness bugs.
- Include the validated development commits in a coordinated tagged release before treating the cache as released functionality.
