# Genshin water: LDPlayer and la64 comparison — 2026-09-13

The same ARM64 game version renders a visible water surface in LDPlayer.
Read-only inspection of the running game finds the same version enum and
variant-strategy byte previously observed on la64. Startup tracing also captures
correct, separate sampler locations and texture-unit values in six water-interface
programs. The strategy byte alone does not explain why water was missing on la64.

The earlier la64 binding correction remains separate, direct evidence that
incorrect sampler assignments caused the missing surface in that scene. See
[the reversible water correction](GENSHIN_WATER_SAMPLER_REPAIR.md) and
[the ARM64 instruction audit](GENSHIN_ARM64_SAMPLER_INSTRUCTION_AUDIT.md).

The subsequent [instancing-path investigation](GENSHIN_INSTANCING_PATH.md)
finds that LDPlayer reports Mali-G77MC9 specifically under Genshin's process
name, including in a native x86_64 control. The game uses a 32-element initial
water interface there, whereas the current la64 water pair exposes two
elements. Original ARM64 code requires an extent of exactly two to retain
the dynamic-instancing flag. This is a more specific path distinction than
the shared version-strategy byte; see that report for runtime limits.

## Actual game observation

Both installations report version code 1223, version name
`7.0.0_47144228_47194594` and primary ABI `arm64-v8a`. LDPlayer 14.0.26.1
runs Android 14 on x86_64, with Houdini translating the ARM64 game. The la64
installation runs Android 16 with Berberis.

The five resource-version markers `data_revision`, `res_revision`,
`silence_revision`, `audio_revision` and `base_res_version_hash` also match
byte-for-byte by SHA-256. This checks revision markers, not every asset file.

A private screenshot before enabling emulator Root shows the character
swimming with visible water. A second screenshot after Root was enabled and
the game successfully restarted shows the water surface and reflections.
Characters, camera direction, graphics settings and selected shader variant
have not been matched across platforms; these are visual controls, not a
pixel-identical comparison.

The native x86_64 diagnostic opens the emulator game's memory read-only. It
checks the mapped ARM64 ELF header and its zero-offset load segment before
using the same game's relative addresses:

| Field | la64 retained observation | LDPlayer live observation |
| --- | ---: | ---: |
| Engine version enum, capability + `0x728` | 4 | 4 |
| Variant strategy byte, capability + `0x70d` | 1 | 1 |
| Actual GL major/minor, + `0x80c` / `0x810` | 3.2 | 3.1 |
| Original instruction at guest RVA `0x52a4670` | `0x2a0003e1` | `0x2a0003e1` |

The capability pointer is read from guest load bias + `0x150a6210`; historical
absolute addresses and Berberis register-save layouts are not reused.
An early startup read found the object's fields still zero; the initialized
read at approximately 15:00 UTC+8 supplies the LDPlayer values above.
These are snapshots, not observations of the strategy input at its branch.

## Captured game initialization

A 120-second native GLES trace covers a subsequent game startup and entry
into the water scene. A separate four-second trace records texture binding
calls from the same surviving process. No shader sources, sampler values or
game memory are changed by these collectors.

The startup record contains 454,730 events, of which 452,926 belong to Genshin.
Both the system GLESv2 wrapper and vendor GLES implementation are traced.
All 181,467 paired API entries agree in their arguments; all 44,996 paired
uniform-location returns agree. All six CPUs report zero overruns, commit
overruns, dropped events and remaining entries. There are 508 `glLinkProgram`
entries per layer and no `glProgramBinary` or `glProgramBinaryOES` entries in
the captured game calls. This is an observation of these APIs during this run,
not a claim that no other kind of shader cache exists.

Six programs contain the combined water sampler names: 994, 1003, 1006,
1238, 1247 and 1250. Their 68 known sampler assignments per layer all use
consecutive units starting at zero; none assigns its location as its value.
The system and vendor observations are two layers of the same calls, not
136 independent assignments. Programs 1247 and 1250 each appear in 22
`glUseProgram` calls in the later four-second binding trace.

For program 1247, the initialization is:

| Sampler | Queried location | Assigned texture unit |
| --- | ---: | ---: |
| `_CameraDepthTexture` | 3 | 0 |
| `_Normal01` | 46 | 1 |
| `_Normal02` | 49 | 2 |
| `_ReflectionSkyCubeMap` | 57 | 3 |
| `_SSRTexture` | 65 | 4 |
| `_SceneScaledBufferBeforTransParent` | 66 | 5 |
| `_SkyGradientLUTForFog` | 71 | 6 |
| `unity_MeshDistanceFieldTexture0` | 119 | 7 |
| `unity_MeshDistanceFieldTexture1` | 120 | 8 |
| `unity_VolumeMask0` | 122 | 9 |
| `unity_VolumeMask1` | 123 | 10 |

Program 1250 has 12 known samplers, including the additional foam sampler,
and assigns units 0–11. These interfaces differ from both the current
ten-sampler la64 program and the retained 14-sampler source fixture.

The binding trace contains 65,574 events across 4.014925 seconds. The observed
`glActiveTexture` calls select only units 0–13. Its host ADB command exceeded
a 15-second deadline covering setup, capture and return; retained event times
confirm that the capture itself lasted about four seconds. Subsequent checks
found successful cleanup, zero remaining owned events/instances, the same
game PID, and no trace-buffer loss.

Two later four-second attempts added draw and `eglMakeCurrent` probes, first
with the PID filter and then without it. Both captured zero API events and
zero per-CPU read events; they provide no draw-state evidence. Cleanup stopped
the idle trace reader and removed all owned events and instances. The game's
foreground activity, process and visible water were subsequently confirmed,
but this later observation does not explain the empty capture windows.

Uniform names throughout the program interface are queried before and between
the sampler assignments. This is consistent with the full-reflection path
identified in the ARM64 audit. The actual guest call sites were not captured,
so it does not yet prove which guest function made these calls or why la64
used the variant-reuse path. No draw calls or EGL context switches were part
of these first two traces; program attribution assumes the observed thread's
context has not changed, and interface matching alone is not a water draw.

The result narrows the remaining investigation to how the game creates and
initializes the corresponding variants, including any cache-dependent choices.
It does not justify declaring all upstream Berberis execution correct or
attributing the entire discrepancy to the version-strategy byte.

## Same-source shader controls

Six independent runs compile, link and query the retained 14-sampler water
source pair: native la64, native x86_64 in LDPlayer, and ARM64 through Houdini,
each with instancing array sizes 2 and 32. All 24 checks pass.

These sources are the earlier 14-sampler fixture; they are not the ten-sampler
program in the later la64 swimming-scene correction. No resource-dependent
water draw is performed by these probes.

Both executable ABIs in LDPlayer return identical sampler locations, types
and default values. Increasing the array size leaves their locations stable.
The fresh native la64 run instead shifts the 14 locations from 153–166 to
423–436, matching the earlier source control.

| Example sampler | la64, array 2 | la64, array 32 | LDPlayer, both ABIs and sizes |
| --- | ---: | ---: | ---: |
| `_CameraDepthTexture` | 153 | 423 | 3 |
| `_Normal01` | 158 | 428 | 68 |
| `_ReflectionSkyCubeMap` | 156 | 426 | 79 |
| `_SceneScaledBufferBeforTransParent` | 165 | 435 | 88 |
| `unity_VolumeMask1` | 163 | 433 | 151 |

All queried sampler values are initially zero. Reflection is compared by
name because enumeration order differs. LDPlayer's locations are not simply
texture units 0–13. Stability across variants therefore does not by itself
make assigning a location as a texture-unit value correct.

The independent x86_64/Houdini result demonstrates that this uniform-layout
difference can arise without Berberis. It does not establish how the actual
game selects shader sources, creates variants or binds textures on LDPlayer.

## Graphics capabilities

| Independent context | la64 | LDPlayer, native and Houdini |
| --- | --- | --- |
| GLES / GLSL ES | 3.2 / 3.20 | 3.1 / 3.10 |
| AEP extension advertised | Yes | Yes |
| Fragment / combined texture units | 32 / 192 | 32 / 192 |
| Program-binary formats | 1 | 0 |
| Maximum uniform-block size | 2147483647 bytes | 65536 bytes |

These ordinary-name independent probes report Qualcomm / Adreno 750 in
LDPlayer; the Windows host has an RTX 4070 Ti SUPER. The running Genshin game
instead records ARM / Mali-G77MC9, and a later native process-name control
reproduces that change. The guest renderer string describes a virtual graphics
interface. la64 uses Mesa 26.1.6 on a Polaris-family AMD GPU.

Both LDPlayer binary-roundtrip tests exit 77 with `SKIP` because no program
binary formats are advertised. Zero roundtrip or pixel checks execute, so
these skips neither reproduce nor refute the separate Mesa binary-import
state issue. The capability difference is a reason to trace the game's actual
cache path, not evidence that it has taken a particular path.

## Emulator access and startup limitation

The initial LDPlayer instance had Root disabled and rejected access to the
game's process mappings. The user authorized enabling Root and restarting it.
Root access subsequently worked. The saved pre-command configuration already
had Root enabled; the CLI command setting it to 1 changed no configuration
bytes. The observed reboot should not be attributed to that no-op command.

The first game startup after that reboot crashed in `DeserializeWork` with
SIGSEGV, address `0xdead1007`, and a Houdini native backtrace. No debugger or
uprobes had been attached. The next startup reached the water scene with Root
still enabled. This is insufficient to attribute the first crash to Root or
shader initialization; it is also separate from the la64 host reset issue.

Private evidence is under `logs/genshin-emulator-comparison-20260913/`:
`comparison.json`, the six source-run records, `fixture-manifest.json`,
`emulator-game-capability.json`, and the version and process-exit records.
UID-bearing screenshots, APK files and process data are not published here.
