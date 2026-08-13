# Changelog

## v0.2.2

- Publish the coordinated LineageOS 23.2 / Android 16 LoongArch64 source snapshot.
- Tag all published Android/Lineage source forks and Chromium WebView at their recorded commits.
- Prefer `arm64-v8a` in the supported ABI list so dynamically unpacked ARM64 application libraries are selected for Native Bridge processes.
- Retain native `loongarch64` and `lp64d` ABI support.
- Record exact project commits and source-tree hashes in `projects.tsv`.
- Complete clean LLVM 21 and Rust 1.88 bootstrap verification.
- Complete a clean `system.img` and `vendor.img` build from the published workflow.
- Include the required LoongArch64 libffi, SwiftShader, minigbm and WebRTC patch queues.
