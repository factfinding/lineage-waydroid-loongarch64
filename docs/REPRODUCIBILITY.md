# Reproducibility status

`v0.2.2` is the first coordinated public source release. The LLVM/Rust bootstrap, standalone Chromium WebView APK, and WebView-integrated LineageOS images were verified from clean workspaces on 2026-08-13 and 2026-08-14.

| Component | Public source/input | Self-contained command | Clean rebuild |
| --- | --- | --- | --- |
| LLVM/Clang 21 | Complete and pinned | Implemented | Passed |
| Rust 1.88 | Complete and pinned | Implemented | Passed |
| Chromium WebView APK | Chromium and depot_tools pinned | Implemented | Passed |
| LineageOS manifest | Source forks tagged; patch trees pinned | Implemented | Passed clean sync |
| `system.img` / `vendor.img` | Source snapshot pinned | Implemented | Passed clean build |

## Verified SHA256 digests

| Artifact | SHA256 |
| --- | --- |
| `clang-21-loongarch64-android.tar.xz` | `a920cfd6663aa156a382e95aae1bc4944abb464f2d4486a9f1a2a9f3d4700579` |
| `rust-1.88-clang21.tar.xz` | `5bb8d6d25b947872d9a2f5df006790b242b137ef024e439e042c78ce786f3a53` |
| `libclang_rt.builtins-loongarch64-android-stage0.a` | `d13d991587636f4313054b17e29aa07d2d21262e305a4a5f8d435f15884a70c4` |
| `libunwind-exported-loongarch64-android-stage0.a` | `b5afc33d901260b0b1e0abed811ec8f50879f9642c7507122b1038065e864c59` |
| `webview-loongarch64.apk` | `d5856563b22cc481190c83afc60c3a3780dbbcd32ba8a914ea36deb70bd7cf5f` |
| `system.img` | `f094e3d865120b3483bd94b277366c99efc456e8dde6624906af0f199c38bdd3` |
| `vendor.img` | `5df1b071dedc09d96b1b10b5ad490e6245095091f8cdf5c876770277dc6f03d5` |

The image build also exports a revision-pinned Repo manifest alongside the images. Binary publication remains separate from this source tag.
