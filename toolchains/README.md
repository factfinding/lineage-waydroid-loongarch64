# LoongArch64 toolchain source

The Android product currently uses a locally rebuilt LLVM 21 toolchain and Rust 1.88 host tools. Their binary payloads are not committed to this repository. The source changes used for those builds are published here as author-preserving patch queues.

This is development documentation, not yet a clean-room reproducible binary release. The pinned manifests and self-contained bootstrap scripts are public, but the complete clean build still has to be run and its binary checksums frozen before the source prerelease can be promoted.

## Bootstrap workflow

From a `v0.2.2` checkout, synchronize the exact LLVM and Rust inputs:

```bash
scripts/sync-toolchains.sh /path/to/toolchain-workspace v0.2.2
```

After synchronizing and patching the matching Android source tree, build both toolchains:

```bash
scripts/build-toolchains.sh \
  /path/to/toolchain-workspace \
  /path/to/lineage-waydroid-23.2 \
  /path/to/toolchain-workspace/dist
```

The build has four explicit stages:

1. Build an LLVM 21 host compiler without Android device runtimes.
2. Build a freestanding LoongArch64 compiler-rt archive and use it to build the minimum bionic sysroot objects.
3. Build the complete LLVM 21 LoongArch64 Android runtime set and install it into the Android tree.
4. Build Rust 1.88 against that LLVM 21 package and install it into the Android tree.

No existing LoongArch64 compiler or runtime binary is an input to stage 1 or stage 2. The stage-0 archive uses the newly built LLVM host compiler, the pinned NDK r28 headers and the tagged Android bionic/kernel headers.

## LLVM 21

The checkout was initialized from Android's public `llvm-toolchain` manifest. Modified projects:

| Project | Base | Development head |
| --- | --- | --- |
| `toolchain/llvm-project` | `5e96669f06077099aa41290cdb4c5e6fa0f59349` | `2841e3fd523669ee12ded0b70fed7cdc946c3e6d` |
| `toolchain/llvm_android` | `38546691df970516709cc907bc7387004f69c60c` | `34aa339c07fe966c118d89fbbdca01b97d98fd9f` |

Patch queues are under `llvm21/patches/`. They add the LoongArch64 Android runtime configuration, libc++ sysroot bootstrap, compiler-rt sanitizer support and Android 16 sysroot integration used by the current prebuilt.

The original checkout command was based on:

```bash
repo init -u https://android.googlesource.com/platform/manifest -b llvm-toolchain
repo sync -c -j8
```

## Rust 1.88

Modified projects:

| Project | Base | Development head |
| --- | --- | --- |
| `toolchain/android_rust` | `083779c7ebba8f829d4c38fe4f1ef6fd0d797e56` | `db3f113c833ee70f886a1adea81015a7eec89e23` |
| `toolchain/rustc` | `4064bccf7e83b1ddbfc1bace9235c9d3eb9f512b` | `e267d333e28dacf128aa5a839e9e1252555959a5` |

Patch queues are under `rust-1.88/patches/`. They add the LoongArch64 Android Rust target, enable the LoongArch LLVM backend, and adapt Rust 1.88's LLVM wrapper to Android LLVM 21 APIs.

The recorded build invocation was:

```bash
toolchain/android_rust/tools/build.py \
  --build-name loongarch64-1.88-clang21 \
  --ndk toolchain/prebuilts/ndk/releases/r27 \
  --clang-prebuilt /path/to/llvm21/stage2-install \
  --llvm-prebuilt /path/to/llvm21/stage2-install \
  --llvm-version 21 \
  --llvm-linkage static \
  --no-bare-targets \
  --no-device-targets \
  --host-multilibs \
  --no-cargo-audit \
  --no-bolt-opt \
  --lto none \
  --no-cgu1 \
  --no-copy-and-patch
```

The output directory contains the LLVM archive, Rust archive, stage-0 archive and `SHA256SUMS`. Before a formal release, this workflow will be run from clean checkouts and those checksums will be frozen together.
