# Development build

The source branches, patch queues and complete bootstrap scripts are public. The LLVM 21 and Rust 1.88 bootstrap plus the LineageOS image build have been verified from clean workspaces. Their large binary outputs are not stored in Git history.

## 1. Synchronize LineageOS 23.2

The shortest tagged workflow is:

```bash
git clone https://github.com/factfinding/lineage-waydroid-loongarch64.git
cd lineage-waydroid-loongarch64
git checkout v0.2.3
scripts/sync-android.sh /path/to/lineage-waydroid-23.2 v0.2.3
```

The equivalent manual steps are shown below.

### Manual initialization

```bash
mkdir lineage-waydroid-23.2
cd lineage-waydroid-23.2
repo init -u https://github.com/LineageOS/android.git -b lineage-23.2
cd ..
```

Clone this repository next to, or anywhere outside, the Android source tree:

```bash
git clone https://github.com/factfinding/lineage-waydroid-loongarch64.git
cd lineage-waydroid-loongarch64
git checkout v0.2.3
cd ../lineage-waydroid-23.2
```

### Install manifests and sync

```bash
../lineage-waydroid-loongarch64/scripts/install-local-manifests.sh "$PWD" v0.2.3
repo sync -c -j8
```

Projects published as GitHub forks are selected by `03-loongarch64.xml`. Supplying the release tag pins them to the matching coordinated tags. Projects for which no exact GitHub mirror exists remain on their canonical AOSP revision and receive the recorded patch queues.

### Apply Waydroid and LoongArch64 patch queues

```bash
../lineage-waydroid-loongarch64/scripts/apply-waydroid-patches.sh "$PWD"
../lineage-waydroid-loongarch64/scripts/apply-patches.sh "$PWD"
```

The first script applies Waydroid's `base-patches-36` to projects that are not
replaced by published LoongArch64 forks. Those forks already contain the
Waydroid changes. The second script applies the remaining LoongArch64 queues
and verifies both the expected base and resulting source tree. Patch commits
preserve their original authorship.

## 2. Build toolchains

Build and install the pinned LLVM 21 and Rust 1.88 toolchains before the product build:

```bash
../lineage-waydroid-loongarch64/scripts/sync-toolchains.sh \
  /path/to/toolchain-workspace v0.2.3
../lineage-waydroid-loongarch64/scripts/build-toolchains.sh \
  /path/to/toolchain-workspace "$PWD"
```

## 3. Build WebView

```bash
../lineage-waydroid-loongarch64/scripts/build-webview.sh \
  "$PWD" /path/to/webview-workspace
```

The script checks out the tagged Chromium source, pins depot_tools, synchronizes Chromium dependencies, builds `SystemWebView64.apk`, and installs it into the Android source tree.

## 4. Build images

```bash
../lineage-waydroid-loongarch64/scripts/build-images.sh \
  "$PWD" /path/to/release-output
```

The current WSL2 build environment must not exceed `-j8` because larger parallel builds have exhausted memory in practice.

The toolchain, standalone WebView, and image stages were clean-build verified for `v0.2.2`. The `v0.2.3` image pair was incrementally rebuilt and device-validated; a new clean bootstrap was not repeated.

## Development-branch RenderScript note

The current development branches build an ARM64 Native Bridge variant of
`librs_jni.so` as part of the product. No LoongArch64 libbcc build is required.

The LoongArch64 product explicitly selects `librs_jni.native_bridge` in
`frameworks/libs/binary_translation/enable_arm64_to_loongarch64.mk`. Selecting
the disabled native `librs_jni` module through `handheld_system.mk` does not
select this separately named guest module. A manually built library can remain
in `out/target/product/.../system/` and appear in `installed-files.txt` while
being excluded by the system image's input file list. The September 14 deployed
images had that omission and required an overlay; the September 16 packaging
fix adds both the guest product package and its allowed artifact path.

Runtime behavior:

- `config.disable_renderscript=1` intentionally keeps the unsupported native
  LoongArch64 runtime out of Zygote processes.
- The framework initializes RenderScript lazily only for `arm64-v8a`
  applications when the configured bridge is `libberberis_arm64.so`.
- Berberis links the ARM64 guest application namespace to the guest
  `librs_jni.so`; the host library is not exposed as a public application
  library.

A normal `systemimage` build includes the framework, Berberis and ARM64 guest
JNI changes with that fix. Validate the image contents, not just the staging
directory or installed-files report. The image must contain
`/system/lib64/arm64/librs_jni.so` as an AArch64 ELF; its native LoongArch64
counterpart remains disabled. After deployment, verify both the configuration
and runtime path:

```bash
getprop config.disable_renderscript
getprop ro.dalvik.vm.native.bridge
grep librs_jni /proc/$(pidof <arm64-package>)/maps
```

The expected values are `1`, `libberberis_arm64.so`, and a mapping below
`/system/lib64/arm64/`. See [RUNTIME_STATUS.md](RUNTIME_STATUS.md) for the
validated application results and unsupported legacy APIs.
