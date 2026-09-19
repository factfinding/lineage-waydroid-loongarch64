# v0.2.3 source and image snapshot

This source tag corresponds to the September 19, 2026 LineageOS 23.2 / Android 16
Waydroid image pair for LoongArch64. It retains the exact device-tested code;
release preparation updates source metadata and documentation only.

- All 29 Android forks and Chromium carry the coordinated `v0.2.3` tag.
- `projects.tsv` records each Android source commit, base and tree. Patch-mode
  projects are published as author-preserving patch queues; applying them can
  produce different commit IDs but must reproduce the recorded source tree.
- `components.tsv` pins the WebView, host packages and separate Helper update.
- Installed LLVM/Rust binaries remain generated inputs. The Rust artifact row
  records its source checkout before toolchain installation, not the generated
  toolchain contents. Bootstrap sources and recipes are retained under toolchains/.
- This image pair passed 211 Berberis and eight native color/GPU/AAC tests plus
  H.264, VP9 and native AV1 playback controls. Helper passed 116 tests and 11
  subtests. See [the complete deployment record](../../docs/FULL_IMAGES_20260919.md).
- The image contains Google services and Play Store, whose proprietary sources
  are not part of this source publication. Upstream component licenses apply.

[Download images and installation instructions](https://github.com/factfinding/waydroid-loongarch64-builds/releases/tag/v0.2.3-lineage-23.2).
Use a 4 KiB-page host kernel. ARM64 compatibility remains experimental and the
test host's prior automatic resets remain unresolved. The pair was incrementally
rebuilt and validated on hardware; a fresh clean bootstrap was not repeated.
