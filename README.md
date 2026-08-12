# LineageOS Waydroid for LoongArch64

[简体中文](README_zh-CN.md)

This repository is the source entry point for the ongoing LineageOS 23.2 / Android 16 port to Waydroid on LoongArch64.

`v0.2.2` is the first versioned public source snapshot. `projects.tsv` records the exact project commits and source trees used by the snapshot. Compatibility and performance work continues on the development branches.

> [!NOTE]
> The public toolchain bootstrap workflow is now available, but its clean rebuild, WebView packaging and clean image build are still pending. See the [reproducibility status](docs/REPRODUCIBILITY.md).

The current system boots to `sys.boot_completed=1` on an AOSC OS LoongArch64 host. Native LoongArch64 ART, bionic, WebView, audio, networking and Mesa graphics have been validated. ARM64 application libraries run through the LoongArch64 Berberis Native Bridge; compatibility and translation performance remain active development areas.

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
  + Chromium 151 LoongArch64 WebView
```

## Related repositories

- [Deployable system and vendor images](https://github.com/factfinding/waydroid-loongarch64-builds)
- [Waydroid host changes and package](https://github.com/factfinding/waydroid)
- [AOSC OS LXC seccomp build](https://github.com/factfinding/aosc-os-abbs)
- [Chromium LoongArch64 WebView source](https://github.com/factfinding/chromium/tree/loongarch64/webview-151.0.7922.71)
- [Berberis LoongArch64 Native Bridge](https://github.com/factfinding/platform_frameworks_libs_binary_translation/tree/loongarch64/lineage-23.2)

## Building

The public manifest and prebuilt bootstrap are still being assembled. The eventual build target is:

See the current [development build instructions](docs/BUILDING.md) for source synchronization and patch application.

```bash
source build/envsetup.sh
lunch lineage_waydroid_loongarch64-bp4a-userdebug
m -j8 systemimage vendorimage
```

Use a 4 KiB-page LoongArch64 kernel for ARM64 application compatibility. Do not use more than `-j8` in the documented WSL2 build environment.

## Licensing

This repository's original scripts and documentation are Apache-2.0 licensed. Android, LineageOS, Waydroid, Chromium and third-party components retain their own upstream licenses and copyright notices. See [docs/LICENSES.md](docs/LICENSES.md).
