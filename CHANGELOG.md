# Changelog

## Unreleased

- Add a region-based ARM64-to-LoongArch64 Lite JIT with interpreter fallback.
- Enable a write-through guest GPR cache using LoongArch64 `$s0`-`$s6`; `ThreadState` remains authoritative at every guest instruction boundary.
- Reject deferred register writeback after application testing exposed stale guest state across exceptional generated-code exits.
- Remove the unsuccessful Instagram-specific trap diagnostics, guest-libc protection exception, host-call recovery experiment, and ARM64 jump-buffer experiment from the active development line.
- Add progressively broader integer, memory, atomic, floating-point and NEON Lite JIT coverage, cache-aware LSX lowering, longer regions and automated microbenchmarks.
- Replace anonymous executable libffi closures with a static CFI-safe trampoline pool for ARM64-to-host callbacks.
- Build and lazily load an ARM64 guest `librs_jni.so` so Native Bridge applications can use legacy RenderScript compute and bitmap operations without requiring a LoongArch64 libbcc backend.
- Keep native LoongArch64 RenderScript disabled and leave legacy graphics-surface, FileA3D and font-asset APIs explicitly unsupported across the bridge.
- Validate `RenderScript.create()` with a minimal ARM64 APK and validate YouTube 21.34.243 through main-screen rendering and a 90-second observation window with an empty crash buffer.
- Pass all 163 LoongArch64 runtime-library tests on the target device.

## v0.2.2

- Publish the coordinated LineageOS 23.2 / Android 16 LoongArch64 source snapshot.
- Tag all published Android/Lineage source forks and Chromium WebView at their recorded commits.
- Prefer `arm64-v8a` in the supported ABI list so dynamically unpacked ARM64 application libraries are selected for Native Bridge processes.
- Retain native `loongarch64` and `lp64d` ABI support.
- Record exact project commits and source-tree hashes in `projects.tsv`.
- Complete clean LLVM 21 and Rust 1.88 bootstrap verification.
- Complete a clean `system.img` and `vendor.img` build from the published workflow.
- Include the required LoongArch64 libffi, SwiftShader, minigbm and WebRTC patch queues.
