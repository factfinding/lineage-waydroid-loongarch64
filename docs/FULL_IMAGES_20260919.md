# Full image snapshot, 2026-09-19

The user requested committing the current source, rebuilding both images, and
deploying them together. This is a development snapshot, not a published release.
Source commits below are local; no push, tag or release publication was requested.

## Source snapshot

| Project | Commit | Scope |
| --- | --- | --- |
| bionic | `b63ad31b8747c80becebcb63650c545989d0b816` | linker: validate actual segment alignment for 16 KiB loading |
| device/waydroid/waydroid | `6d6a520292cb17156a4744450fd2c4fb8c980ab0` | waydroid: persist native media decoder compatibility policies |
| external/aac | `fd89fd7619a606c355627a9552c8eb61182cad87` | aac: saturate conjugated spatial phase coefficients |
| external/minigbm | `722be37992483615bb04a497b9446ac0a2120575` | minigbm: align planar imports and map complete R8 backing |
| external/stagefright-plugins | `57278b3821bec08eb5076be0ecdce6eee42d45b6` | codec2: negotiate output layouts and report usable codecs |
| frameworks/av | `d7addfee0c2ed512b1a07619338e718634a933b9` | media: repair packed color buffers and native decoder availability |
| frameworks/base | `f79ce4a21cd8c7376891ce8dda690e41057755dd` | framework: scope Instagram native decoder policy to its process |
| frameworks/libs/binary_translation | `3647dbf15a7350f8a289d9bc262534c4870482af` | berberis: retain runtime compatibility and JIT progress fixes |
| ../waydroid-helper | `8e2c6fcf6dfab43b0769817f48f15170e9dfd248` | Align key mapping with the actual Waydroid viewport |

The integration repository also retains linker/media probes, the AAC and
minigbm patch queues, Helper validation, and dated runtime/performance reports.
Installed LLVM/Rust binaries remain generated build inputs rather than source
commits; use the existing toolchain build recipes to reproduce them. The nested
vendor/extra/init checkout is a clean repo-managed project, not a new submodule.

## Build and deployment

Build in progress using `scripts/build-images.sh` (`m -j8 systemimage vendorimage`).
The resulting pinned manifest and SHA256SUMS-images are retained with the image
artifacts under `out/full-images-20260919/`. Deployment must reconcile all
existing component overrides against the image contents, preserve the old pair
and complete overlay/configuration state, and retain Android user data.

Host automatic resets remain unresolved. This snapshot includes validated
application/JIT/media fixes and does not claim to repair the host reset cause.
