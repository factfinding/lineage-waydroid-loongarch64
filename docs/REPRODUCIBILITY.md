# Reproducibility status

`v0.2.2` is currently a source prerelease. A formal release requires every row below to have a recorded clean-build result and SHA256 digest.

| Component | Public source/input | Self-contained command | Clean rebuild |
| --- | --- | --- | --- |
| LLVM/Clang 21 | Complete and pinned | Implemented | Pending |
| Rust 1.88 | Complete and pinned | Implemented | Pending |
| Chromium WebView APK | Chromium and depot_tools pinned | Implemented | Pending |
| LineageOS manifest | Source forks tagged; patch trees pinned | Implemented | Pending clean sync |
| `system.img` / `vendor.img` | Source snapshot pinned | Documented | Pending clean build |

Existing local artifacts are useful reference outputs only. They are not accepted as release inputs and will not be uploaded until rebuilt by the public workflow.
