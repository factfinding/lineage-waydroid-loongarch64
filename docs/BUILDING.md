# Development build

The source branches and patch queues are public, but the Clang 21 and Rust 1.88 bootstrap artifacts are not published yet. These instructions therefore describe the source-sync stage; a clean end-to-end public build is not claimed yet.

## 1. Initialize LineageOS 23.2

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
git checkout v0.2.2
cd ../lineage-waydroid-23.2
```

## 2. Install manifests and sync

```bash
../lineage-waydroid-loongarch64/scripts/install-local-manifests.sh "$PWD" v0.2.2
repo sync -c -j8
```

Projects published as GitHub forks are selected by `03-loongarch64.xml`. Supplying the release tag pins them to the matching coordinated tags. Projects for which no exact GitHub mirror exists remain on their canonical AOSP revision and receive the recorded patch queues.

## 3. Apply AOSP patch queues

```bash
../lineage-waydroid-loongarch64/scripts/apply-patches.sh "$PWD"
```

The script verifies both the expected base and the resulting source tree. Patch commits preserve their original authorship.

## 4. Build target

Build and install the pinned LLVM 21 and Rust 1.88 toolchains before the product build:

```bash
../lineage-waydroid-loongarch64/scripts/sync-toolchains.sh \
  /path/to/toolchain-workspace v0.2.2
../lineage-waydroid-loongarch64/scripts/build-toolchains.sh \
  /path/to/toolchain-workspace "$PWD"
```

Then build the product:

```bash
source build/envsetup.sh
lunch lineage_waydroid_loongarch64-bp4a-userdebug
m -j8 systemimage vendorimage
```

The current WSL2 build environment must not exceed `-j8` because larger parallel builds have exhausted memory in practice.

The scripts and pinned inputs are public, but `v0.2.2` remains a prerelease until this entire sequence, WebView packaging and the image build have completed in clean directories.
