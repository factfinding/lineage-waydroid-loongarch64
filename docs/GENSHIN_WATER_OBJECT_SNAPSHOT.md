# Genshin water object snapshot — 2026-09-11

Follow-up: [2026-09-12 swimming capture](GENSHIN_SWIMMING_SAMPLERS.md) confirms
incorrect sampler mappings through passive tracing and read-only native memory
inspection, and validates the first two instance matrices in that later scene.
The assignment's origin remains unresolved.

The live trace now identifies a water program, but does **not** establish the
rendering defect's root cause or attribute it to a Berberis optimization.

## Confirmed observations

Initial game host PID 19353 / Android PID 5565; owning GLES thread 19465.
Short GDB queries at native Mesa draw boundaries first succeeded on the
standalone water probe, then on Genshin. These are intrusive diagnostic calls,
not passive traces or performance measurements.

- Program 446 had 222 active uniforms, including `_ShallowColor`, `_DeepColor`,
  `_ShoreFade`, `_OpacityByDepth`, `_SSRIntensityMobile`, and water/refraction
  textures. This identifies it as a water program much more specifically than
  the earlier blend-state heuristic. Earlier in-water tracing recorded 33 draws
  of 42 indices with this program, on FBO 1.
- Later, 446 was no longer a valid object. Program 331 drew the same index count
  and exposed the **identical ordered uniform name/type/array-size signature**.
  This identifies another water program; identical reflection metadata does
  not prove identical executable shader code or explain the object change.
- At program 331's actual `glDrawElements` entry: TRIANGLES, 42 UNSIGNED_SHORT
  indices, offset zero, FBO 1, viewport 1072×640. FBO status was COMPLETE.
  Blend was SRC_ALPHA / ONE_MINUS_SRC_ALPHA, depth test LEQUAL, depth writes
  disabled, all color writes enabled, backface culling enabled / clockwise front
  faces. Stencil, scissor, and rasterizer discard were disabled.
- LINK_STATUS was true. An explicit `glValidateProgram` changed validation
  status from false to true and produced an empty log. The initial false value
  is not evidence of a previous failed validation. This query changes the
  program's validation status and log; it is not entirely read-only.
- No shaders remained attached to the linked program, so `glGetShaderSource`
  could not recover GLSL. A 101,125-byte program binary was saved locally,
  format 34655, SHA256
  `10b1f509eb21717598d0be146158f70870496bc9cda0de332f5d128c86bef6cc`.

## Two unresolved leads

### Instancing data

The water shader exposes `UnityInstancing_PerDraw0`: 96 active uniforms for
32 entries containing object/world matrices and transform parameters. It
requires 4608 bytes. At the non-instanced water draw, binding 0 held buffer
5848 with 6144 bytes; indexed start/size queries returned zero. A zero range
size with a whole-buffer binding is **not** proof of a missing buffer.
`unity_BaseInstanceID` was zero.

This is relevant to the earlier eight engine warnings about returning an
instance shader when a non-instance shader was requested. However, using an
instance-capable shader for a normal draw can work when entry zero contains
the correct transform. The matrix contents were **not successfully captured**.
Neither the warnings nor the reflection metadata alone prove incorrect shader
selection or malformed geometry.

### Sampler query discrepancy

All fourteen sampler uniforms returned values 423–436, exactly their uniform
locations, while MAX_COMBINED_TEXTURE_IMAGE_UNITS was 192. The result reproduced
after initializing the output buffer to a sentinel and cross-checking integer
and float queries. Yet program validation passed. Do not label the queried
values as proven GPU sampler mappings or change them speculatively.

A subsequent passive trace recorded no `glUniform1i[v]` upload while water
program 331 was current. Its sampler initialization may have occurred before
that window. Actual texture bindings at its draws used units 0–13. Independently
querying those units found nonzero objects and these relevant dimensions:

| Unit / target | Texture | Level-zero size | Internal format |
| --- | --- | --- | --- |
| 0 / 2D | 2370 | 1072×640 | 35056 |
| 3 / cube, +X face | 2331 | 128×128 | 35898 |
| 4 / 2D | 804 | 512×512 | 37844 |
| 5 / 2D | 1389 | 256×256 | 37812 |
| 6 / 2D | 1095 | 128×128 | 37812 |
| 7, 8 / 3D | 5 | 1×1×1 | 32856 |
| 12 / 2D | 2384 | 536×320 | 35898 |
| 13 / 2D | 2382 | 536×320 | 34842 |

These are unit bindings, **not a proven mapping from sampler names to units**.
Dimensions do not establish valid texture contents, mip completeness, or
correct shader sampling. The sampled ordinary uniforms included
`_OpacityByDepth=6.666667`, `_ShoreFade=0`, and `_CausticDepth=+Infinity`.
Without the shader's equations or a known-good reference these values cannot
be classified as the defect.

## Diagnostic failure and recovery

The first targeted wait for obsolete program 446 timed out and detached. A
screenshot showed an update-required/relogin modal. Contrary to the initial
assumption that this stopped water drawing, passive tracing and the subsequent
331 snapshots showed the scene was still rendering behind the modal.

Snapshots through `water4` succeeded, restored temporary bindings, released
scratch memory, and detached (roughly 1.4–2.1 seconds for the targeted snapshots).
In `water5`, an attempted **synchronous `glMapBufferRange(..., MAP_READ_BIT)`**
of the uniform buffer timed out while other threads were scheduler-locked.
GDB unwound the inferior call; scratch cleanup and detach reported success,
but a subsequent passive capture contained zero draw events. Unwinding a native
driver call does not guarantee that internal locks or driver state are restored.

A follow-up backtrace attachment also failed to finish: thread 19463 (`gdrv0`)
was in D state in `kernel_clone`. SIGINT and SIGTERM did not end that debugger;
the debugger was killed, after which the game process was observed as a zombie.
The precise internal failure chain is unresolved. No usable crash-buffer entry
or matrix data was recovered. **Do not count this attempt as a successful
snapshot and do not repeat synchronous GPU mapping through this GDB method.**
The archived script now rejects its `read_uniform_buffers` option before attach.

The game alone was force-stopped and cold-started with its exact activity.
New host PID: 41069. Screenshots confirmed its resource update screen was
rendering again (96.06 / 117.36 MB at the recorded recovery screenshot).
Waydroid, JIT settings, installed libraries/images, and app data were not reset.

## Next capture and evidence

Use `scripts/capture-genshin-gles-inputs.py` on the host as root, passing the
**current** host PID and a duration of at most five seconds. For example, from
the outer workspace, after checking PID and that the scene is ready:

```sh
ssh la64-root 'python3 - CURRENT_HOST_PID 2' < lineage-waydroid-loongarch64/scripts/capture-genshin-gles-inputs.py
```

This collector observes application calls through uprobes; it never calls GL,
maps GPU buffers, or changes application GL state. It records buffer bindings,
buffer uploads, uniform uploads, texture bindings and draws at system and Mesa
boundaries. Raw payload prefixes are capped at 64 bytes; ignore any word beyond
the API's supplied byte/count range, and treat faulted reads as unavailable.
Persistent mapped writes and historical uploads are not recovered. Count Mesa
draws only, and do not equate program IDs across process lifetimes.

The collector's device smoke capture registered and removed 36 events, with
312 event lines and no cleanup errors. It uses `--no-bpf-event` to avoid an
unrelated perf BPF synthesis failure encountered during an earlier attempt;
that failed attempt also cleaned up its probes.

Evidence under the outer workspace `logs/gles-object-snapshot-20260911/`:

- `gl-snapshot-game2-20260911/`: four candidate-program reflection results.
- `gl-snapshot-water2-20260911/`: program 331 draw and ordinary uniform values.
- `gl-snapshot-water3-20260911/`: sentinel/cross-query sampler check, validation.
- `gl-snapshot-water4-20260911/`: texture dimensions, UBO metadata, program binary.
- `gl-snapshot-water5-20260911/`: failed map query and cleanup result.
- `genshin-gl-live-20260911-222144/`, `uniform-trace-analysis.json`: passive
  texture/uniform trace before the failed map query.
- `genshin-gl-live-20260911-222855/`: new collector smoke capture after recovery.
- `current-screen.png`, `recovered-screen2.png`, `recover-game-start2.txt`,
  `post-map-backtraces.txt`: update modal, recovery and incident records.

Next priorities: capture the water program's initialization uploads and matrix
buffer updates, compare their guest/native arguments, then inspect shader/output
behavior using a capture mechanism that does not synchronously call into a
stopped driver. No API-completeness or JIT correctness conclusion is warranted
from the present evidence alone.
