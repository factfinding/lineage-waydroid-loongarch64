# LineageOS Waydroid for LoongArch64

[简体中文](README_zh-CN.md)

This repository is the source entry point for the ongoing LineageOS 23.2 / Android 16 port to Waydroid on LoongArch64.

`v0.2.3` is the current coordinated source and image snapshot. `projects.tsv` records the exact project commits and source trees used by the snapshot. Compatibility and performance work continues on the development branches.

> [!NOTE]
> The public toolchain bootstrap, standalone Chromium WebView APK, and clean LineageOS image build have been verified. See the [reproducibility status](docs/REPRODUCIBILITY.md).

The current system boots to `sys.boot_completed=1` on an AOSC OS LoongArch64 host. Native LoongArch64 ART, bionic, WebView, audio, networking and Mesa graphics have been validated. ARM64 application libraries run through the LoongArch64 Berberis Native Bridge; compatibility and translation performance remain active development areas.

The development branch now includes a region-based ARM64-to-LoongArch64 Lite JIT with interpreter fallback. Its current validated register caches keep selected guest GPRs in LoongArch64 callee-saved registers and audited SIMD values in LSX registers. Guest state remains write-through to `ThreadState`. The device correctness suite currently passes all 211 tests.

ARM64 applications can also use the legacy RenderScript compute and bitmap path through Berberis. The framework lazily loads the ARM64 guest `librs_jni.so`, while native LoongArch64 RenderScript remains disabled because its old libbcc compiler has no LoongArch64 backend. A minimal ARM64 test application and a separately installed YouTube 21.34.243 have completed runtime validation; proprietary Google APKs are not distributed by this repository. Legacy RenderScript graphics-surface, FileA3D and font-asset APIs are not bridged.

See the dated [runtime and translation status](docs/RUNTIME_STATUS.md) for exact test results, limitations, deployed hashes and rollback information. The matching [v0.2.3 images](https://github.com/factfinding/waydroid-loongarch64-builds/releases/tag/v0.2.3-lineage-23.2) include these changes.

## Source layout

- GitHub-native Android and Waydroid projects are published as forks on the `loongarch64/lineage-23.2` branch.
- AOSP projects without an exact GitHub mirror use author-preserving patch series under `patches/`.
- Chromium WebView source is published at [`factfinding/chromium`](https://github.com/factfinding/chromium), branch `loongarch64/webview-151.0.7922.71`.
- Large Clang, Rust, VNDK and WebView build artifacts are intentionally not stored in Git history.
- LLVM 21 and Rust 1.88 source changes and recorded build inputs are documented under [`toolchains/`](toolchains/README.md).
- `projects.tsv` records the source path, publication mode, source location and exact development commit.
- The coordinated source-tag and component-tag policy is documented in [`docs/VERSIONING.md`](docs/VERSIONING.md).

The source stack is:

```text
LineageOS 23.2 / Android 16
  + official Waydroid base-patches-36
  + LoongArch64 platform changes
  + LoongArch64 Berberis Native Bridge
  + ARM64 guest RenderScript compute/bitmap runtime
  + Chromium 151 LoongArch64 WebView
```

## Related repositories

- [Deployable system and vendor images](https://github.com/factfinding/waydroid-loongarch64-builds)
- [Waydroid host changes and package](https://github.com/factfinding/waydroid)
- [AOSC OS LXC seccomp build](https://github.com/factfinding/aosc-os-abbs)
- [Chromium LoongArch64 WebView source](https://github.com/factfinding/chromium/tree/loongarch64/webview-151.0.7922.71)
- [Berberis LoongArch64 Native Bridge](https://github.com/factfinding/platform_frameworks_libs_binary_translation/tree/loongarch64/lineage-23.2)

## Building

The public manifest, patch queues and toolchain bootstrap scripts are available. See the [build instructions](docs/BUILDING.md) for the complete synchronization and build workflow.

```bash
source build/envsetup.sh
lunch lineage_waydroid_loongarch64-bp4a-userdebug
m -j8 systemimage vendorimage
```

Use a 4 KiB-page LoongArch64 kernel for ARM64 application compatibility. Do not use more than `-j8` in the documented WSL2 build environment.

## Licensing

This repository's original scripts and documentation are Apache-2.0 licensed. Android, LineageOS, Waydroid, Chromium and third-party components retain their own upstream licenses and copyright notices. See [docs/LICENSES.md](docs/LICENSES.md).
