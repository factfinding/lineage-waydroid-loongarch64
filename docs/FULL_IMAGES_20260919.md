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

`scripts/build-images.sh` (`m -j8 systemimage vendorimage`) completed successfully
in 16 minutes. The pinned manifest and SHA256SUMS-images are retained with the
image artifacts under `out/full-images-20260919/`. All eight changed Android
projects in the manifest match the source commits above.

| Artifact | SHA-256 |
| --- | --- |
| system.img | `32c43db3a0c873dd9f7d7ab53087db977a6cd3a7e405a2eccd05e5fc43f4865c` |
| vendor.img | `69002bb4ca6a42c63d7fc4e4c3fc24cf390b78f9c572ddb0ec40b13b48cfe8df` |

EROFS extraction/integrity checking and read-only vendor filesystem checking
passed. All eleven existing overlay files are present in the extracted images
and match the installed build outputs. Nine are byte-identical to their current
overrides. The vendor property file changes only its build date/incremental;
the decoder and Instagram compatibility settings are preserved. The remaining
change is the software-codec APEX: extraction shows only `libcodec2_vndk.so` and
`libsfplugin_ccodec_utils.so` changed, incorporating the current RGB buffer fixes
into that namespace as well. Other APEX files, including the AAC implementation,
remain byte-identical to the previous validated APEX.

The image includes ARM64 `librs_jni.so` and its ten direct guest dependencies;
the unsupported native LoongArch64 variant remains disabled. Source-tree status
is clean for all committed projects. The parent vendor/extra checkout only
reports its separately managed, clean init project.

Both images were transferred and their complete destination SHA-256 checks
passed before and after installation. The old pair, complete writable/work
overlay directories, configuration, manifest and hash records are preserved at:

`/var/lib/waydroid/deploy-backups/20260919-112402-full-images/`

Fresh overlay directories replace the old ones, so all eleven component
overrides now come from the images. Android user data and the host Helper
installation/layouts were preserved. The desktop user's Waydroid session was
stopped before replacement and restarted afterward.

## Post-deployment validation

- Android reaches `sys.boot_completed=1`; system and vendor incremental versions
  are both `1789785338`. The desktop is visible and the existing application
  packages, Google services and Play Store remain installed.
- All fifteen effective component hashes match the extracted images, including
  the three checked libraries in the active software-codec APEX. There are no
  remaining writable file overrides.
- Berberis correctness: **211/211**. Native RGB wrapping/copying: **1/1**.
  GPU YUV imports: **6/6**. AAC spatial phase saturation: **1/1**.
- Concurrent YUV420 and RGBA byte-buffer decoders each produce all twelve red
  frames and EOS; flexible YUV420 also passes. Unsupported RGB565 and P010 are
  rejected during configuration.
- H.264 byte-buffer and Surface, VP9 Surface, and native dav1d AV1 Surface each
  produce **60/60** frames, 59 changed frames/timestamps and EOS. Surface controls
  check delivery/timestamps; the GPU import and color tests check actual pixels.
- Platform AAC remains preferred; FFmpeg correctly excludes xHE-AAC. Instagram's
  compatibility probe passes with its per-process model override and unchanged
  global model. The product default remains enabled.
- Berberis is `lite-translate-or-interpret`, ART JIT is enabled, and the native
  RenderScript disable property remains 1. ARM64 RenderScript is packaged in the
  image. Existing game fake-touch configuration is unchanged.
- Helper source validation before deployment passed **116 tests and 11 subtests**
  using the device's existing virtual environment; its host installation was not
  replaced during this image deployment.
- The final Android crash buffer is empty. Host boot ID remains
  `8f1ca1a8-eacb-4ebb-b2e5-deb720aeaf9f`; only Waydroid was restarted. No new game
  loading benchmark, match, or live Instagram playback comparison was performed.

Private evidence and deployment scripts are under workspace
`logs/full-images-20260919/`; images, extracted files and logs are build artifacts,
not source commits.

## Rollback

Stop any mapper, the desktop user's Waydroid session and the container service.
Verify LXC is stopped and the rootfs unmounted. Preserve the new images and
overlay directories in a separate backup, then restore both old images and both
overlay directories from the exact backup above. Check `old-images.sha256`,
start the service and the graphical session as `noctis`, and verify Android boot.
Restore saved configuration only if needed, preserving subsequent user changes.
Do not clear Android data or delete deployment backups.

Host automatic resets remain unresolved. This snapshot includes validated
application/JIT/media fixes and does not claim to repair the host reset cause.
