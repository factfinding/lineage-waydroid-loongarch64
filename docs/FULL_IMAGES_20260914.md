# Full image deployment, 2026-09-14

The user requested replacing both Waydroid images after confirming the Helper
coordinate fix works. The accepted September 13 `lite-only` image pair was
installed in `/etc/waydroid-extra/images/`. Both hashes match the final successful
`m -j8 systemimage vendorimage` build record; no new build was needed.

| Artifact | SHA-256 |
| --- | --- |
| system.img | `0ad90eec082af4f393b785bb1a7d2e0cff005902dcb63f67c0dedf7bbc2dd439` |
| vendor.img | `673ad0de578670b693fc6e6c2563a3c8aa65e3fd3c5a06d6daa1a41d1fd11bb7` |
| Effective Berberis | `8265edf0a3149872d02eef3256489f36b98b60165037a889104059ffa9c6033b` |
| Effective vendor drirc | `6376bd518cb270f47c02c4315d21daebe603cbe7b5499e31dd96edc3be2b7402` |

System EROFS extraction/integrity checking and read-only vendor filesystem
checking passed. Destination image hashes were verified before replacement.
The original images, complete writable/work overlay directories, configuration,
base properties and before/after hashes are preserved at:

`/var/lib/waydroid/deploy-backups/20260914-215615-full-images/`

## Overlay reconciliation

The image contains byte-identical copies of all five previously overridden
components: Berberis, ART APEX, framework.jar, Launcher3QuickStep and vendor
drirc. Those duplicate overrides were moved into the backup so the image copies
are now effective. Fresh upper/work directories avoid reusing stale overlayfs
metadata with the replacement lower images.

The ARM64 `/system/lib64/arm64/librs_jni.so` is still absent from system.img.
Its existing validated override was copied, with its metadata, into the new
upper directory. It is the only remaining writable file override, with SHA-256
`a448293d3148b56c6923b8090717d6b4f537d76ad75b756f739c807a8ab2b218`.
Thus this deployment uses the new full image pair while retaining that
RenderScript compatibility supplement. It does not claim all supplements have
been packaged into the images.

On September 16, product selection was fixed and new images were built and
inspected with this library included, then deployed with the user's approval.
That deployment supersedes this image pair and removes the last library
override; see the latest entry in [RUNTIME_STATUS.md](RUNTIME_STATUS.md).

## Verification

- Android reaches `sys.boot_completed=1`, with system incremental version
  `1789296000` and build date September 13, 18:40 CST.
- Host boot ID stayed `7f8df3ba-96b8-4bce-8db0-90b26e162e15`; this deployment
  restarted Waydroid, not the host. New LXC init PID is 33743.
- All **190/190** Berberis correctness tests passed against the installed
  runtime. The test binary hash is
  `01076a49bd91e2964ba3b5074241729c02347079d033ad05541f886523adca92`.
- Effective runtime hashes match the image/retained-file inventory. Berberis
  remains `lite-translate-or-interpret`; ART JIT remains enabled.
- The post-boot Android crash buffer is empty. Boot logging includes an
  unsupported fs-verity operation and AppSearch index recovery; neither
  prevented startup. An empty crash buffer does not mean all logs are error-free.
- Both game packages remain installed. No game data or shader cache was cleared,
  and no gameplay or new loading-time comparison was performed.
- Helper's host installation and layout files were preserved. Persistent ADB
  TCP port and USB settings remain configured, with `ro.adb.secure=1`.
  After networking initialized, ADB reconnected with the existing host key,
  reported `device`, and returned `sys.boot_completed=1` through its shell.
  The resumed foreground activity is Launcher3's QuickstepLauncher.

Private evidence is in workspace `logs/full-images-20260914/`, including the
deployment script, overlay comparison, build-artifact hashes, transfer record,
correctness log and boot verification. Raw images and logs are not source.

## Rollback

Stop the mapper and the desktop user's Waydroid session, then stop
`waydroid-container.service`. Verify LXC is stopped and its rootfs unmounted.
Preserve the replacement images and current overlay directories in a separate
backup before restoring both original images and the `overlay_rw` and
`overlay_work` directories from the exact backup above. Restore the recorded
configuration/base properties only if needed, without overwriting later user
changes. Verify the old-image hashes in `old-images.sha256`, start the container
service, then start the graphical session as `noctis` and check Android boot.
Do not clear `/var/lib/waydroid/data` or remove deployment backups.
