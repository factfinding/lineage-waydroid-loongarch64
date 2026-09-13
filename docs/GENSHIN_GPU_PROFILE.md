# Genshin GPU identity profile — 2026-09-13

The China Genshin package `com.miHoYo.Yuanshen` now has a Mesa drirc profile
for the `radeonsi` driver. It returns `ARM` for `GL_VENDOR` and
`Mali-G77MC9` for `GL_RENDERER`. This targets the renderer-dependent
instancing initialization described in [the path audit](GENSHIN_INSTANCING_PATH.md).

The profile changes these two strings. GLES/GLSL versions, extensions,
limits, driver binaries, Android product identity and Berberis configuration
are unchanged. It does not match other packages or the international Genshin
package.

## Source and deployment

Mesa commit `3bbcc85b5fc8a12249d519c1111571a89027e95a` preserves this
configuration on the local `loongarch64/lineage-23.2` development branch.

The application entry is added to the existing `radeonsi` device in
`external/mesa3d/src/util/00-mesa-defaults.conf`. Waydroid's existing product
copy rule installs that file as `/vendor/etc/drirc`. A standalone reference
entry is retained at [configs/mesa/genshin-radeonsi.conf](../configs/mesa/genshin-radeonsi.conf).
Merge this entry into existing configuration; do not replace the entire
defaults file with the standalone fragment.

XML comparison verifies that the only semantic change is this application
and its two options. The installed defaults matched the source baseline
before deployment.

| File | SHA-256 |
| --- | --- |
| Original drirc | `279eca9934c5e25e32807db188e3d357989cfb9e0aea90bfde1e7ca32904f7b0` |
| Profile-enabled drirc | `6376bd518cb270f47c02c4315d21daebe603cbe7b5499e31dd96edc3be2b7402` |

Only the live vendor overlay's `etc/drirc` was replaced, atomically, after
backing up the complete original file. The vendor mount was returned to its
original read-only state. No system/vendor image or library was replaced;
neither the host nor Waydroid was restarted. Genshin alone was force-stopped
and launched through its normal launcher activity.

The successful deployment backup is
`/var/lib/waydroid/deploy-backups/20260913-162753-genshin-gpu-profile/`.
An earlier attempt using util-linux's reconfigure path failed before writing
the target and left it unchanged; its separate backup is retained. The
successful helper used `mount(2)` with VFS flags only, avoiding replay of
overlay-specific options rejected by this kernel.

To roll back, verify the current candidate hash and the backup's original
hash, temporarily remount the vendor overlay writable, atomically restore
the complete backed-up `drirc`, and restore the read-only mount. Restart
Genshin so it initializes a new graphics capability object. Remove the source
application entry as well if future image builds should omit the profile.
No shader cache deletion is part of profile rollback.

## Validation

Five independent native LoongArch64 Android EGL probe processes compare the
same executable under ordinary and Genshin process names:

| Configuration | Process name | Returned vendor / renderer |
| --- | --- | --- |
| Before | Ordinary | AMD / Radeon Polaris |
| Before | Genshin | AMD / Radeon Polaris |
| After | Ordinary | AMD / Radeon Polaris |
| After | Genshin | ARM / Mali-G77MC9 |
| After | Ordinary again | AMD / Radeon Polaris |

All five processes exit successfully. Android `getprogname()` matches the
supplied name. The ordinary processes' complete GL query output is unchanged;
the Genshin-named control changes exactly the vendor and renderer strings.
All queried versions, extensions and limits agree with the baseline. The
Android-visible config hash also matches the candidate.

The restarted real game independently stores `ARM / Mali-G77MC9`, GLES
`3.2 Mesa 26.1.6`, the same version enum 4 and strategy byte 1, and initial
instancing sizes **32/32**. Before deployment those sizes were 32/2. Program
binary permission remains enabled. This verifies the live application's
configuration and initial-size selection.

### In-game water validation

After scene loading, the screenshot shows the character swimming in visible
water with reflected sky. The new game process has received no manual sampler
correction. The first scene trace was interrupted by a duplicate-login event
and scene reload; its historical program pointers are excluded from the final
mapping result. Once the user confirmed stable gameplay, a fresh two-second
trace was followed immediately by read-only program inspection on the host.
All 90 program objects identified by uniform events were read successfully.
Water program 284 has
189 reflected uniforms and a 32-element instance interface.

Three subsequent stable reads agree on its CPU uniform values and the fragment
program's `SamplerUnits`, using each uniform's reflected opaque index:

| Water sampler | Location | CPU unit | Fragment unit |
| --- | ---: | ---: | ---: |
| `_CameraDepthTexture` | 398 | 0 | 0 |
| `_ReflectionSkyCubeMap` | 399 | 1 | 1 |
| `_SkyGradientLUTForFog` | 400 | 2 | 2 |
| `_Normal01` | 401 | 3 | 3 |
| `_Normal02` | 402 | 4 | 4 |
| `unity_MeshDistanceFieldTexture0` | 403 | 5 | 5 |
| `unity_MeshDistanceFieldTexture1` | 404 | 6 | 6 |
| `unity_VolumeMask0` | 405 | 7 | 7 |
| `unity_VolumeMask1` | 406 | 8 | 8 |
| `_SceneScaledBufferBeforTransParent` | 407 | 9 | 9 |

All ten active sampler bits are set, `SamplersValidated` is true, and the
sampler types agree with the fragment program's texture targets. There are
zero samplers storing their location as the unit in this state.

The trace contains 114 `glDrawElements` calls using water program 284. Rebuilding
texture bindings from the render thread's `glActiveTexture` and `glBindTexture`
calls finds observed nonzero bindings for all ten required sampler targets at
all 114 draws. The 84,466 parsed events match perf's sample count with no
explicit lost-event record; all 11 probes were removed. No water sampler setter
was observed in this steady-state trace, so initialization is established by
the stored state rather than a captured setter-call history. Binding reconstruction
uses API entries and assumes no unrecorded context switch or alternative binding
path; it does not inspect GPU texture contents.

These observations validate
the current water scene after normal profile-driven initialization; they do
not cover every game shader variant or establish the cause of earlier host
resets.

The 16:54 CST final check retains the same host boot ID, LXC init and game
process. The installed config hash still matches the candidate and the vendor
overlay is read-only. Fifth-batch Berberis remains in
`lite-translate-or-interpret` mode with SHA-256
`c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`;
ART JIT remains enabled. `TracerPid` is zero, the GLES probes are absent and
the bounded log collectors have stopped. These checks are retained in
`final-health.json`.

## Shader caches

No cache or application data was manually cleared. The game hashes the five
stage source strings after the instancing-size substitution. Changing 2 to
32 therefore selects the corresponding source-content key. An existing
matching size-32 entry can still be reused.

An additional cache fingerprint includes GL vendor, renderer and version.
Depending on the game's fingerprint-selection setting, the identity change
can cause the game to invalidate and rebuild entries automatically. Therefore
manual full-cache rebuilding is unnecessary, but the first startup may do
additional compilation. This is not a promise that all entries are reused or
that every entry is rebuilt.

The builder adds some precision/workaround text after its source-content hash;
do not equate that hash with every byte eventually passed to GL. The separately
observed Mesa program-binary import inconsistency is not fixed by changing
identity strings and must remain a separate diagnostic if it recurs.

Private evidence is under `logs/genshin-gpu-profile-20260913/`, including the
deployment manifests, native controls, live capability snapshot,
`stable-scene-trace/`, `water-driver-validation.json` and
`screen-stable-water.png`. The
cache-key instruction audit is retained in
`logs/genshin-init-path-20260913/cache-key-review.md`. Screenshots and raw
startup logs remain private.
