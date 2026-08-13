# Reproducibility status

`v0.2.2` is the first coordinated public source release. The LLVM/Rust bootstrap and LineageOS image build were verified from clean workspaces on 2026-08-13. The standalone Chromium WebView APK is the remaining clean-build gap and is not included as a reproduced binary artifact yet.

| Component | Public source/input | Self-contained command | Clean rebuild |
| --- | --- | --- | --- |
| LLVM/Clang 21 | Complete and pinned | Implemented | Passed |
| Rust 1.88 | Complete and pinned | Implemented | Passed |
| Chromium WebView APK | Chromium and depot_tools pinned | Implemented | Pending |
| LineageOS manifest | Source forks tagged; patch trees pinned | Implemented | Passed clean sync |
| `system.img` / `vendor.img` | Source snapshot pinned | Implemented | Passed clean build |

## Verified SHA256 digests

| Artifact | SHA256 |
| --- | --- |
| `clang-21-loongarch64-android.tar.xz` | `a920cfd6663aa156a382e95aae1bc4944abb464f2d4486a9f1a2a9f3d4700579` |
| `rust-1.88-clang21.tar.xz` | `5bb8d6d25b947872d9a2f5df006790b242b137ef024e439e042c78ce786f3a53` |
| `libclang_rt.builtins-loongarch64-android-stage0.a` | `d13d991587636f4313054b17e29aa07d2d21262e305a4a5f8d435f15884a70c4` |
| `libunwind-exported-loongarch64-android-stage0.a` | `b5afc33d901260b0b1e0abed811ec8f50879f9642c7507122b1038065e864c59` |
| `system.img` | `08ed7a18595a3d3204e97a42f13206b96bd6aefae836338dfb12f319fa9b59e2` |
| `vendor.img` | `4de1c61e16ca4802d24f9fd89d12256bcf7d79e74ecc9a61c0acd3f6f7fbdaff` |

The image build also exports a revision-pinned Repo manifest alongside the images. Binary publication remains separate from this source tag.
