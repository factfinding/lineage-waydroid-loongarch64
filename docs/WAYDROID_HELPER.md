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

The trial authorized the host's existing public ADB key and enabled the runtime
property `service.adb.tcp.port=5555`. `persist.adb.tcp.port` remains empty.
This setup is not reboot-persistent: after restarting Waydroid, verify its
current address, enable runtime adbd if necessary, and verify the selected
device is authorized before starting a new mapper.

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

## Validation and limits

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
