# Waydroid Helper on LoongArch64

Validated on 2026-09-13. The user reports that keyboard mapping works in
Genshin Impact on the local LoongArch64 device.

## Source

- Fork: <https://github.com/factfinding/waydroid-helper>
- Branch: `loongarch64/main`
- Validated source: `030d85e7d417a86818cba986d12cabd55bd83335`
- Upstream base: `17f5f326de9facdbb3d9f6b02354a4dcb0f628fd`
- [Mapping instructions and example layout](https://github.com/factfinding/waydroid-helper/blob/loongarch64/main/docs/KEY_MAPPING_LOONGARCH64.md)

The four commits add real LoongArch64 architecture detection, configurable ADB
targets and ownership-aware scrcpy cleanup, an optional fixed-size layout
launcher, and required AppStream metadata. Extension architecture checks remain
in effect. The input listener binds to the host loopback address. Cleanup tracks
each instance's reverse tunnels rather than removing all ADB reverse mappings.

## Local installation

The trial uses AOSC OS, KDE Wayland, Python 3.14.7, system PyGObject 3.57.1,
GTK 4.22.1 and libadwaita 1.9.1. PyWayland 0.4.19 was compiled natively.
A separate venv with `--system-site-packages` reuses the system GTK bindings;
the older PyGObject pin in upstream requirements was not imposed on the host.

Device paths, owned by the desktop user:

| Purpose | Path |
| --- | --- |
| Source | `~/waydroid-helper-la64-src/` |
| Venv | `~/.local/share/waydroid-helper-la64/venv/` |
| Install prefix | `~/.local/share/waydroid-helper-la64/install/` |
| Launcher | `~/.local/bin/waydroid-helper` |
| Desktop entry | `~/.local/share/applications/com.jaoushingan.WaydroidHelper.desktop` |
| Saved layouts | `~/.config/waydroid-helper/layouts/` |

Meson installation used a staging `DESTDIR`; only the staged user prefix was
copied into the live prefix. Upstream's absolute system service and D-Bus
installation paths were not deployed, and no new privileged services or system
polkit policy were activated. The installed GSettings schema was compiled.
The optional runner and JSON example are source files, not installed commands.

The launcher exports `WAYDROID_ADB_SERIAL=192.168.240.2:5555` and the private
`GSETTINGS_SCHEMA_DIR`, then runs the installed entry point with the venv Python.
The successful user test ran without a `GSK_RENDERER` override. The current
Android canvas is 1340 by 800; align the mapper with the game when using a
fixed-size window. Launch the UI as the desktop user in the Wayland session.

## ADB setup and reversal

The initial trial authorized the host's existing public ADB key and enabled the runtime
property `service.adb.tcp.port=5555`. `persist.adb.tcp.port` was left empty.
That initial setup was not reboot-persistent: after restarting Waydroid, verify its
current address, enable runtime adbd if necessary, and verify the selected
device is authorized before starting a new mapper.

On 2026-09-14, the user reported that mapping stopped working after a host
restart. Helper and its mapping window were running, but `adbd` was stopped,
both TCP port properties were empty, `persist.sys.usb.config=none`, and global
`adb_enabled=0`. The mapper journal records five failed attempts to connect to
`192.168.240.2:5555`, after which `ScrcpyLifecycleService.setup()` stops retrying.

The connection was restored and the settings made persistent:

- `persist.adb.tcp.port=5555` (the runtime port override stays empty).
- `persist.sys.usb.config=adb`, with current `sys.usb.config=adb`.
- Global `adb_enabled=1`.

The installed `init.usb.rc` applies the persistent USB configuration on boot
and starts adbd for `adb`; `AdbService.systemReady()` also derives its enabled
state from that persistent property. Both settings are needed: storing the TCP
port alone does not start a disabled daemon. Adbd started without restarting
Android, the existing host key was accepted, and `adb get-state` returned
`device`. Shell and screen-resolution queries passed. `ro.adb.secure=1` was
preserved; no key or mapping-layout files were changed. A subsequent reboot has
not yet been used to verify persistence end to end.

The failed mapping window needs to be closed and reopened to retry the control
connection; save any pending layout edits first. F1 changes mapping/edit mode
but does not restart the exhausted connection task. The existing window was
left intact, and no automatic game input was sent.

The pre-change properties and setting are saved in
`/var/lib/waydroid/deploy-backups/20260914-205256-helper-adb-persistent`.
To reverse this change, use SSH/LXC to restore the values from its `before.json`,
including the persistent TCP/USB properties and global ADB setting. Private
diagnostic records are in `logs/waydroid-helper-reboot-20260914/`.

ADB state was backed up under:

- `/var/lib/waydroid/deploy-backups/20260913-171151-waydroid-helper-adb`
- `/var/lib/waydroid/deploy-backups/20260913-172335-waydroid-helper-adb`

To undo the trial, first close the mapper and helper normally. Preserve user
layouts, then remove only the trial's user launcher, desktop entry and private
install tree if no longer wanted. Restore ADB properties and key state from the
applicable backup, preserving any independently added keys. The first backup
records the state before the host key was added; the second already includes
that authorization. Do not remove reverse tunnels belonging to other clients.

No Android image, Berberis JIT setting, game data or shader cache was changed
for this helper installation.

## 2026-09-14 mapping viewport correction

The mapper previously maximized to 1920×1030 at desktop origin (0, 0), while
Waydroid rendered 1340×800 at (243, 142). Scaling the entire overlay to Android
therefore displaced touches from the visible key markers. The installed fix
aligns the mapper to the unique Waydroid buffer rectangle using an owned KWin
script. GTK scales one stable Android-sized canvas, including pointer coordinates;
drag bounds, context menus and settings popovers use that same canvas.

The mapper follows game-window movement and minimizes when its target is absent,
minimized or ambiguous. Explicit `--window-size` keeps manual alignment available.
Normal window close now waits for asynchronous cleanup before destroying the
last window, allowing its KWin script and ADB control resources to be released.

Device validation: 116 Python tests plus 11 subtests, Meson build and three
metadata checks passed. Real GTK tests cover shrinking, enlargement, nonuniform
scaling and inverse pointer transforms. The installed window passed five point
round trips. Actual KWin geometry matched before and after moving the game window
and restoring it. Closing the installed probe left no owned script, control
listener or reverse tunnel. A fresh installed mapper was opened in edit mode and
its scrcpy connection completed. No automated game inputs were sent; Android
and the game remained running.

Only the user-installed Helper Python files and its source snapshot were updated.
The original files and a per-file SHA-256 manifest are backed up at
`~/.local/state/waydroid-helper-la64/viewport-backup-20260914-213145/`.
For rollback, close the mapper, restore each manifest entry with a backup and
remove only newly added files whose manifest backup is null, then reopen it.
Private evidence is in `logs/waydroid-helper-coordinate-20260914/`.

Automatic alignment is tested on this KWin session. Cross-monitor DPI changes,
other KWin versions and live Android resolution/rotation changes have not been
validated. Reopen the mapper after changing Android resolution. The fix is local
on `loongarch64/main`; it has not yet been committed or pushed.

## Earlier validation and limits

- Device Python suite: 110 passed, with 11 subtests passed.
- Meson build passed; desktop, GSettings and AppStream validation passed, 3/3.
- The four installed runtime modules match the published source by SHA-256.
- Main UI and real Genshin keyboard mapping were validated; the latter is the
  user's report. The automatic input probe did not complete a separate test.
- The example layout and optional fixed-size runner have syntax, JSON and CLI
  checks; the user's report does not independently validate those entry points.

The host spontaneously restarted during the trial around 17:20 CST. The journal
ends abruptly without a captured fault-site panic, GPU reset or orderly shutdown;
no cause is established. The agent had not sent automatic test keys before that
restart. The subsequent successful gameplay test does not resolve the reset.

Private build, installation, source-hash and reset evidence remains in workspace
`logs/waydroid-helper-la64-20260913/`; these generated logs and game screenshots
are not source artifacts. The passing test record is `tests-device-updated.txt`;
the earlier `tests-device-final.txt` retains the AppStream failure that prompted
the metadata fix.
