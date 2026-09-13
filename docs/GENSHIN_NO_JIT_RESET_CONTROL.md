# Genshin host reset: Berberis interpreter control

Started September 12, 2026 at approximately 23:58 UTC+8, following the user's
explicit request to disable JIT and try the game. This is a control for the
whole-host reset reported in [the reset investigation](GENSHIN_HOST_RESETS.md).

**Control ended September 13 at 09:15 UTC+8:** the user requested JIT restoration.
`berberis.mode` is again `lite-translate-or-interpret`; ART remains enabled and
the fifth-batch library is unchanged. Waydroid restarted and completed Android
boot. A WaterProbe process verified mode 1 with positive JIT/gear-up counters.
See [current runtime status](RUNTIME_STATUS.md) and outer-workspace
`logs/genshin-restore-jit-20260913/`. The observations below describe the earlier
interpreter experiment, not the current device setting. Genshin was not launched
as part of restoration, and the host-reset cause remains unresolved.

Only the ARM64 translator execution mode was changed:

- `berberis.mode=interpret-only` in all three Waydroid configuration/property
  files. The setting persists until restored, including across host reboots.
- Native ART retains `dalvik.vm.usejit=true` for this single-variable control.
- The Berberis library remains fifth-batch SHA-256
  `c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`.
- Kernel settings were not changed for this run. The current boot has
  `kernel.panic=30`; the earlier temporary zero expired at the preceding reset.

The exact prior configuration is backed up at
`/var/lib/waydroid/deploy-backups/20260912-235527-genshin-host-reset-no-berberis-jit/`.
The three saved files are `waydroid.cfg`, `waydroid_base.prop` and `waydroid.prop`.
Restoration requires stopping Waydroid, restoring these exact files, starting
the container service and the desktop user's session, then checking live
properties and the next game process. No image or game-data rollback is needed.

Android reached `sys.boot_completed=1`. Live properties were checked before the
game launch. Genshin was launched once via its main activity; host PID 6867,
Android PID 3804, in boot `ebd8ae9f-591d-4181-bdd9-6b9ed2854ddd`.
Hash-guarded reads of that process's Berberis globals at 23:58:27, intermediate
checks, and the final 00:12:52 check all reported translation mode 0, JIT
successes 0 and gear-ups 0. These
checks establish that ARM64 guest translation JIT is disabled; ART caches or
bridge stubs must not be mistaken for guest JIT activity.

The first screenshots show the app's early black startup surface, changing to
white by the 00:04:32 capture. Subsequent captures through 00:10:40 remain white;
no matched resource-download-stage observation has been established. The notification
shade was collapsed once for observation, and the game's activity was confirmed
resumed. A longer interval without a reset at this early stage would not by
itself prove that disabling JIT prevents the observed download-stage reset.
The prior interpreter experiment was slow enough to encounter a game network
failure before providing a useful in-scene control.

The external collector `continuous-03-no-jit/` was armed before the game launch,
with original deadline **September 13, 00:57:44 development-computer time (UTC+8)**.
It records effective panic-related sysctls in every sensor sample, correcting
the previous run's missing final-value evidence. The preceding `continuous-02`
collector was stopped only after the replacement was armed.

However, `continuous-03-no-jit` received SIGTERM at **00:05:08.296** and exited
early. Its last sensor sample was received at 00:05:07.661. The signal sender
was not recorded, so its source is unknown. This was a collector termination,
not a host reset: subsequent direct reads find the same boot and game PID.
A detached replacement, `continuous-04-no-jit`, was armed at approximately
**00:07:17**, with deadline **01:07:16**. It was still receiving data at the
00:12:52 check. There is a sensor coverage gap of approximately 130 seconds;
the last target Android record in the first collector was at 00:04:03, giving
the application-log evidence a longer gap. This run must not be described as
uninterrupted external capture.

## Observed outcome at 00:12:52

The host has not rebooted, and the same Genshin process has remained alive for
approximately 15 minutes with guest JIT counters still zero. Nevertheless, this
is **not a successful matched-stage control**: the game is stuck on a white
startup surface and repeatedly reports `NullReferenceException` on two paths:

- `MoleMole.GameManager.MEPBOKMFCLI` followed by `GameManager.Update`.
- `MoleMole.GameManager.IOMCEKMHFDN` followed by `GameManager.LateUpdate`.

The earliest retained instance in the second collector has Android log time
**September 13, 00:07:19.415**. Because of the preceding capture gap, this does
not establish the actual first occurrence. Repeated frame-update exceptions
are evidence of a startup problem, not evidence of a completed download-stage
test. The available logs and screenshots have not reached the resource stage
shown immediately before the earlier automatic reset.

Thus this observation neither proves a Berberis JIT regression caused the
host reset nor rules JIT out. Disabling JIT changes execution speed as well as
which code executes; the reason for these application exceptions is not yet
established. The game and interpreter setting have been left in place, with
the bounded replacement collector running for subsequent observation.

Evidence is in the outer workspace's
`logs/genshin-host-reset-20260912/no-jit-control/`: configuration backup/result,
launch record, hash-guarded runtime verifier, runtime checks and screenshots.
Raw Android output in the associated continuous capture may contain private
session information; only sanitized findings belong in public reports.

The sanitized exception analysis is `no-jit-control/exception-analysis.md`.
No claim of a fixed reset or an isolated JIT regression has been made.
