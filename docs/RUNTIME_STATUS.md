# Runtime and Translation Status

Last updated: 2026-08-15

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

## Verification on 2026-08-15

- Built `libberberis_arm64.so` from known-good source commit `9a830d0` plus only the isolated write-through GPR-cache change. The same source is now committed as `d0cfbe2` on `loongarch64/lineage-23.2`.
- Passed `113/113` `LoongArch64RuntimeLibraryTest` tests on the LoongArch64 Waydroid device.
- Deployed library SHA-256: `ebd2a850ca4f7c29d48917400d59260125a83ba9031592c161d81fbc1f241536`.
- Waydroid reached `sys.boot_completed=1`; the Android crash buffer was empty after deployment.
- Manual application testing found no regression, including the previously crashing Instagram post-login path.

## Remaining work

- Increase Lite JIT instruction and region coverage to reduce interpreter re-entry.
- Profile region formation, dispatch, helper calls, memory access, and JNI transitions on real applications.
- Expand syscall, signal, JNI, and Native Bridge correctness coverage.
- Keep application protection or emulator-detection failures separate from translation correctness bugs.
- Publish the validated development commits and include them in a coordinated tagged release before treating the cache as released functionality.
