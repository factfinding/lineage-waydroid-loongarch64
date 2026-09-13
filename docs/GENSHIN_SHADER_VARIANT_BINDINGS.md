# Genshin water shader variant binding investigation — 2026-09-12

The observed bad sampler initialization is explained by the game's original
ARM64 rendering code and the independently reproduced native shader layout.
The game reuses reflection information for a new instancing variant, obtains
the new program's uniform locations, and uses those locations as texture-unit
numbers. For the observed water program this writes 423–436, while the real
textures are bound to units 0–13.

Fresh source compilation in a native LoongArch64 Android process reproduces
the location ranges without Native Bridge or the old game binaries. This
establishes the layout and erroneous-assignment chain without requiring a JIT
error. It does not prove every translated instruction correct. At the end of
this September 12 investigation, an in-game rendering comparison after
correcting the mapping was still needed.

**September 13 visual control completed:** in the fresh process, water program
278 has ten samplers incorrectly set to 128–137. Reference program 276 has the
same 99-uniform interface and correctly uses 0–9. Correcting the current water
program restored the surface; restoring the original values removed it again;
reapplying restored it. The corrected state remains active, with fifth-batch
JIT enabled and the same host boot. This is a temporary live-program correction,
not a deployed persistent fix or an explanation for the earlier host resets.
See [the controlled repair](GENSHIN_WATER_SAMPLER_REPAIR.md).

**Instruction-identification challenge rechecked:** a September 13 audit
re-read the live ARM64 bytes, checked aliases and bitfields independently,
executed the unmodified local fragment with Unicorn, and ran focused
interpreter/JIT comparisons on the LoongArch device. No discrepancy was found
in the checked cases. The historical API trace directly records wrong
arguments but lacks a simultaneous strategy-flag or per-instruction trace;
the later flag snapshot must not be treated as such a trace. See
[the instruction audit](GENSHIN_ARM64_SAMPLER_INSTRUCTION_AUDIT.md) for results
and the distinction between isolated replay and the original game execution.

**September 13 follow-up:** the user cleared game data, completed startup and
reports that water is still missing with fifth-batch JIT enabled. At 12:29
UTC+8 the host boot/game PID match the 09:28 download observation; a new
screenshot confirms gameplay. This shows that the reported clearing operation
did not resolve the water symptom, but does not establish which caches were
removed or whether the current program repeats the exact sampler assignments
below. All program IDs, locations and object addresses in this September 12
report remain historical evidence; establish the new process's mapping before
any corrective visual control. See outer-workspace
`logs/genshin-cleared-data-20260913/observation-in-world.json`.

The September 12 work below continues
[the startup sampler trace](GENSHIN_SAMPLER_INITIALIZATION.md).
No game restart, product-code change, image deployment, game-memory write or
shader-cache modification was performed during that September 12 investigation.
The September 13 correction is separately documented above.

## Runtime identity

- Game host PID: `34346`; program IDs below belong only to this process.
- Container init host PID: `2159`.
- Native driver: OpenGL ES 3.2, Mesa 26.1.6, radeonsi/polaris10/ACO.
- Driver build ID: `29895dc125573fdbf6329ae0ef9e5db5c5804715`.
- Installed Berberis SHA-256:
  `c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`.
- Fragment texture-unit limit: 32; combined limit: 192.
- The game context has `GL_CONTEXT_FLAG_NO_ERROR_BIT_KHR` set.

Code offsets refer to the installed ARM64 `libyuanshen.so`. Its mapping base
in this process is `0x7ffc1574c000`. Local source HEAD alone does not identify
the deployed translator.

## The branch flag comes from graphics-version initialization

The flag previously observed at `[x19+0x2c]` belongs to a stack frame, not a
shader object. Function `0x52a4088` allocates the frame and sets `x19=sp`.
It loads the global capabilities object from slot `0x150a6210`, reads byte
`+0x70d`, and saves that byte to the stack local.

The producer at `0x52b119c..0x52b11c4`, inside initializer `0x52aa250`, computes:

```c
binding_strategy = (uint32_t)(version - 10) < 3 ||
                   (uint32_t)(version - 3) < 2;
```

The current capabilities object is `0x7ffd3bc307b0`. The selected version enum
at `+0x728` is 4 and the strategy byte at `+0x70d` is 1, agreeing with this
original predicate. Enum 4 is the engine's GLES 3.1 AEP selection: caller
`0x47a405c` checks `GL_ANDROID_extension_pack_es31a` and can downgrade it to 3.
It should not be confused with the actual context version, separately queried
as major 3/minor 2 at `+0x80c/+0x810`.

The same flag also affects uniform-block binding reflection. Its exact symbol
name is unknown; calling it specifically an explicit-uniform-location support
flag would go beyond the evidence. A read-only audit of the relevant translator
load, bit-test and move handling found no obvious discrepancy. The current
flag value itself is consistent with the original ARM64 version predicate.

## Full reflection and variant reflection use different sampler values

Full reflection function `0x529482c` uses an independent sampler counter.
Its observed setter return offset is `0x52964b0`; program 341 receives 0–13.
It also saves active-uniform indices for later variant reflection.

Variant builder `0x528ea04` calls reflection-reuse function `0x52a4088` at
`0x528f3ec`. The reference is the first entry in the shader's variant array;
the target is the newly selected variant. For each saved sampler index,
helper `0x52a79ec` does the equivalent of:

```c
name = glGetActiveUniform(reference_program, saved_index, ...);
location = glGetUniformLocation(target_program, name);
if (binding_strategy)
    glUniform1i(location, location);       // observed bad branch
else
    glUniform1i(location, sampler_index);  // index increments from zero
```

The bad path does not retrieve the reference sampler's actual texture-unit
value. Its setter returns at `0x52a467c`; the `mov w1,w0` at `0x52a4670`
explicitly duplicates the queried location. The preceding trace observed
matching guest, native GLES and Mesa arguments, including 423/423 for the
first sampler in program 342. The relevant live ARM64 bytes matched the
installed library.

Because the context suppresses error validation, these out-of-range units
reach Mesa storage. Enabling normal error checks would reject bad assignments;
it would not create the missing mapping to units 0–13.

## Recovered water sources explain the 270-location difference

A two-second optional guest-context capture identified the enclosing graphics
object. A subsequent bounded, read-only search of two relevant allocator
regions found one matching water variant array and owner:

| Object | Address / value |
| --- | --- |
| Shader owner | `0x7ffd8da5c4e0` |
| Variant array | `0x7ffd6ccfbb30` |
| Entry 0 | key 0, program 341 |
| Entry 1 | key 32, program 342 |
| Entry size / count | 144 bytes / 2 |

The owner header, array and source metadata were stable across the reads.
Source contents were read once; metadata stability does not independently
prove immutable string storage. The search took 0.249 seconds and opened
`/proc/34346/mem` read-only. It did not attach a debugger or call GL in the game.

The recovered vertex template is 3,322 bytes and the fragment template is
73,364 bytes. Both declare GLSL ES 300. All 14 fragment samplers are ordinary
uniforms without explicit location or binding qualifiers. The fragment's
`layout(location=0)` is attached to its output, not to a sampler.

The vertex template defaults `UNITY_RUNTIME_INSTANCING_ARRAY_SIZE` to 2.
The variant builder patches the identifier at byte 832 with `32`, padded to
the original 35 bytes. No fragment patch is present. The affected uniform
block contains two four-vec4 matrix arrays and one vec4 per instance:

```glsl
layout(std140) uniform UnityInstancing_PerDraw0 {
    unity_Builtins0Array_Type
        unity_Builtins0Array[UNITY_RUNTIME_INSTANCING_ARRAY_SIZE];
};
```

Thirty additional instances, each with nine vec4 members, account for the
observed layout shift: `(32 - 2) * 9 = 270 = 423 - 153`. Uniform locations are
identifiers used to update uniforms; they are not texture-unit indices.

The fragment template omits default float precision. Original helper
`0x52a5484` adds `precision highp float;\n` for the currently selected version
and capabilities. The highp selector is `capabilities+0x7ea=1`. Helper
`0x52b3624` inserts it at byte 99, after the leading preprocessor block and
before the first actual source token. Known Adreno/transpose workaround flags
`+0x7ff/+0x7e7` are zero. A reconstructed input preserves that insertion point;
it is not a captured historical `glShaderSource` argument.

## Independent native driver controls

An independent LoongArch64 Android EGL process used a 1×1 pbuffer and the same
deployed driver. It neither used Native Bridge nor attached to the game.

First, importing the two copied game-cache binaries reproduced sampler
locations 153–166 and 423–436, with queried defaults of zero. Each cache file
contains a four-byte format enum `0x875f` followed by its binary payload.

Second, compiling and linking the recovered sources, with the missing highp
float declaration supplied in a diagnostic copy, reproduced the same result
without loading either old binary:

| Instancing array size | Active uniforms | 14 sampler locations | Queried defaults |
| --- | ---: | --- | --- |
| 2 | 132 | 153–166 | all zero |
| 32 | 222 | 423–436 | all zero |

Each run passed nine compile/link/query/export checks. These controls compile
the resource-dependent water shader but do not draw it. The first adjusted
copy inserted the highp float declaration immediately after the existing int
precision declaration. Its exported payloads were 72,965 and 101,069 bytes,
each 56 bytes smaller than the corresponding old game binary, so historical
byte identity is not asserted. A second pair of tests placed the declaration
at the helper's exact current insertion point and reproduced the same locations
and payload sizes, again passing nine checks per case. Results and hashes are
in `mesa-binary-probe/reconstructed-source-comparison.json`. These reconstructed
binaries also differ from the historical cache files.

## Separately reproduced Mesa binary-import sampler-state defect

Twelve synthetic source/binary roundtrip cases cover GLSL ES 310/320,
implicit sampler locations, explicit locations, distinct explicit bindings,
and zero/270 padding uniforms. The suite checks both queried values and a
pixel rendered from 14 differently colored textures. Every draw starts with
a magenta clear to exclude a stale output pixel.

There were 2,180 checks and 36 failures. All failures were the three RGB
channels on the first draw after binary import, across all 12 cases:

- Explicit locations survive padding and binary roundtrip correctly.
- Imported CPU uniform values reset to source defaults as expected.
- Rendering initially uses the sampler-unit mapping that was active at export.
- Setting each sampler to another legal unit and back to its default repairs
  rendering in every case. Subsequent runtime assignments also render correctly.

The matching Mesa `src/compiler/glsl/serialize.cpp` serializes
`UniformDataDefaults` but separately serializes current stage `SamplerUnits`.
The two readers restore these inconsistent states. This is a native driver
defect reproduced without the game or translation. Its contribution to this
game's water failure has not been established, and it does not explain why
the game subsequently issues `glUniform1i(location, location)`.

`NumExplicitUniformLocations=0` after binary import is not evidence of missing
explicit location support: that aggregate field is not serialized, while
individual `remap_location` values and the uniform remap table are serialized.

## Repair direction and remaining validation

The primary compatibility target is the variant sampler mapping: preserve the
correct texture-unit assignment when looking up each new variant's uniform
location. A global conversion of every integer uniform, or blindly clamping
out-of-range values, would also affect unrelated uniforms and cannot recover
the intended mapping. Any workaround should be limited to a verified sampler
interface and then checked in the same in-game water scene.

The independently reproduced Mesa import defect warrants a separate fix and
regression test keeping CPU defaults and executable sampler state consistent.
That driver fix alone is not expected to stop the game issuing bad setters.
No product fix or in-game visual A/B validation was performed in this pass.

## Evidence and collector changes

Outer-workspace artifacts are under `logs/genshin-branch-20260912/`:

- `static-analysis.md`, reduced assembly and `global-flag.json`: original
  flag producer, caller chain and runtime value.
- `runtime-capabilities.json`: installed translator identity and capability
  fields used in this analysis.
- `shader-source-recovery.md`, `water-source-search.json`,
  `shader-source-layout.json`, `water-source-manifest.json`: source ownership,
  bounded search and checksums.
- `fragment-precision.asm`, `fragment-precision-runtime.json`: default float
  precision reconstruction.
- `water-*.glsl`: recovered templates, variant and reconstructed input.
- `binaries/`: copied game-cache fixtures; game originals were not modified.
- `mesa-binary-probe/`: native test sources, executables, exact build commands,
  complete results, comparison JSON and exported control binaries.
- `genshin-sampler-init-20260912-163945/`: two-second guest-context capture,
  process maps, event manifest, raw perf data and probe cleanup result.
- `final-state.json`: game PID 34346 alive with `TracerPid: 0`, running
  container PID 2159, empty crash buffer, no remaining private probes or
  diagnostic processes. The graphical session also remained running as noctis.

The reusable collector `scripts/capture-genshin-sampler-init.py` gained
`--guest-context`, an optional capture of selected guest registers and two
audited memory fields. Interpret them only at the documented guest caller
offsets: x19 is a stack frame in the reflection-copy function, whereas x29
identifies the graphics object at the audited frame-update caller. Existing
build-ID guards, per-event filtering and probe cleanup remain in use.
