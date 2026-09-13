# Genshin water restored by correcting sampler bindings — 2026-09-13

A controlled in-game correction restored the missing water surface while the
user's character was swimming. Restoring the original bindings made the water
disappear again; applying the correction again restored it. The game is left
with the corrected bindings. This directly establishes the sampler mapping as
a cause of the missing water in this scene.

This was a temporary correction to one live Mesa program. It is not a deployed
compatibility patch and can be lost when the program is recreated or the game
restarts. No JIT, Mesa library, image, shader source or persistent configuration
was replaced. No game data or shader cache was cleared or explicitly rewritten.
The fifth-batch Berberis JIT remained enabled throughout.

## Fresh process and mapping

The user had cleared application data before this investigation. Historical
program IDs and locations from September 12 were therefore not reused.

- Host boot: `7d14b950-3c0e-4186-9a9d-c9c69cd9284d`.
- Genshin: host PID 15306, Android PID 5072, start time 257654 clock ticks.
- Context-owning worker: host LWP 15390, `UnityGfxDeviceW`.
- Mesa build ID: `29895dc125573fdbf6329ae0ef9e5db5c5804715`.
- Target water program: 278; independently inspected reference: 276.
- Both programs have the same ordered 99 uniform names and sampler locations.
  Reference 276 stores units 0–9; target 278 originally stores 128–137.

A two-second passive trace observed 86 water draws using program 278: 43 with
132 indices and 43 with 48 indices, drawing triangles into FBO 1. Read-only
inspection found the required textures bound to units 0–9, while the sampled
2D, 3D and cube bindings in units 128–137 were all empty.

| Sampler | Location / original unit | Correct unit | Observed texture target / object |
| --- | ---: | ---: | --- |
| `_CameraDepthTexture` | 128 | 0 | 2D / 2219 |
| `_ReflectionSkyCubeMap` | 129 | 1 | cube / 2183 |
| `_SkyGradientLUTForFog` | 130 | 2 | 2D / 2199 |
| `_Normal01` | 131 | 3 | 2D / 1551 |
| `_Normal02` | 132 | 4 | 2D / 1103 |
| `unity_MeshDistanceFieldTexture0` | 133 | 5 | 3D / 5 |
| `unity_MeshDistanceFieldTexture1` | 134 | 6 | 3D / 5 |
| `unity_VolumeMask0` | 135 | 7 | 2D / 3 |
| `unity_VolumeMask1` | 136 | 8 | 2D / 3 |
| `_SceneScaledBufferBeforTransParent` | 137 | 9 | 2D / 2230 |

Here 128–137 are within the context's combined texture-unit limit of 192.
The demonstrated defect is the wrong mapping to empty units, not an
out-of-range uniform argument. The historical 14-sampler, 423–436 variant is
a different program and remains separate evidence.

## Reversible visual control

| State | CPU uniform values and fragment `SamplerUnits` | Screenshot observation |
| --- | --- | --- |
| Original | 128–137 | Water surface absent; character swimming over the visible bottom |
| First correction | 0–9 | Water surface, reflection and submerged character visible |
| Rollback | 128–137 | Water surface absent again |
| Final correction | 0–9 | Water surface restored again |

All three transactions updated exactly the ten sampler entries through Mesa's
own `_mesa_uniform` function on the context-owning worker. This updates both
uniform storage and derived sampler/texture state through the normal Mesa
implementation. Merely writing uniform storage would not be an equivalent
control. Both CPU values and fragment-stage `SamplerUnits` were checked after
each transaction, and a later read-only snapshot still found units 0–9.

Each transaction checked the live Mesa build and symbol bytes, process start
time, context, active program, full uniform-name list, sampler types, locations,
storage pointers and original values. The worker was stopped at an existing
integer uniform update for this program; its temporary scalar input was
restored after every injected setter call. Register restoration and debugger
detachment were also checked. Transactions lasted 0.727, 0.704 and 0.676 seconds,
respectively; all 30 setter calls returned and reported restored scratch state.
These are complete transaction durations, not individual setter costs.

The camera remained in the same swimming scene, although game lighting and
animation continued. This is a visible reversal control, not a pixel-identical
image comparison or a claim that every water variant is fixed.

## Final runtime and host-reset limits

The final device check at approximately 13:06:51 UTC+8 found the same host boot,
game PID and process start time, no traced game threads, and zero remaining
uprobes. `berberis.mode=lite-translate-or-interpret`, `dalvik.vm.usejit=true`
and `sys.boot_completed=1` remained in effect. The installed and mapped
Berberis library both match fifth-batch SHA-256
`c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`.
The final read reports translation mode 1, 351,306 JIT successes and 124,593
gear-ups.

There was no host reboot during this control. The external collector has
documented SSH reconnection gaps, so its streams must not be described as
uninterrupted. Its 1,777 sensor samples all report the same boot and a present
game process. It stopped at its configured deadline, with the last device
sensor timestamp 13:05:28.530 UTC+8, 11.58 seconds after the final setter call.
The saved in-window kernel and selected Android streams contain no recorded
panic, GPU reset, OOM, fatal application error or `NullReferenceException`.
See the local `setter-window-audit.md` for exact coverage and classifications.
Neither the successful correction nor the lack of a reset in this interval
determines the cause of the September 12 host resets.

The prior [ARM64 variant initialization investigation](GENSHIN_SHADER_VARIANT_BINDINGS.md)
explains how the game can produce the wrong mapping without assuming a JIT
error. This run independently reproduces the wrong live state and establishes
its visual effect; it does not retrace the fresh process's initialization call
or prove all translated code correct. The separately observed Mesa program
binary-import sampler inconsistency was not repaired by this experiment.

## Evidence and follow-up

Private outer-workspace artifacts are in
`logs/genshin-water-recheck-20260913/`: `mapping.json`, `all-programs.json`,
`water-draws.json`, `water-before.json`, `water-final.json`, the three
`setter-{apply,rollback,reapply}.json` records, `runtime-final.json`,
`final-device-state.json`, and the four visual-control screenshots. The local
worker helper and process-specific configurations record the exact operation.
Their addresses and IDs must not be reused in another process. Raw Android
logs and unredacted screenshots remain private because they can contain
account information.

A persistent compatibility fix should correct sampler mapping when affected
variants are initialized or restored, using verified sampler reflection and
texture-unit assignments. Uniform locations must remain independent of texture
unit values. A global rule rewriting every `glUniform1i(location, location)`
would also alter valid application calls and is not justified by this result.
The live debugger correction is an experiment, not the permanent mechanism.
