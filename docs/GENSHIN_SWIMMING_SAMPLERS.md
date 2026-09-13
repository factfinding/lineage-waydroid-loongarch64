# Genshin swimming: incorrect sampler mappings — 2026-09-12

The user's swimming scene exposes a concrete water-rendering state error:
water program 355's fragment samplers reference texture units **167–180**, which
have no textures bound. The application's water draws bind their textures to
**0–13**. The faulty assignment's origin is not yet captured, and no rendering
fix or attribution to a particular Berberis optimization has been established.

## Capture and identity

Game host PID 4963, public GLES thread 6526. Screenshots before and after show
the same camera near Mondstadt, with swimming controls/status and the reported
missing surface. This is a new process, so yesterday's program IDs were not
reused as identities.

The first passive capture spans 2.14386316 seconds and contains 267,556 events.
It records 125 observed program IDs and 10,708 downstream draw calls. Program
355 submits two water meshes per cycle: 132 and 48 UNSIGNED_SHORT indices,
28 calls each, using ordinary `glDrawElements`. Its uniform locations and
subsequently read names identify the same 222-uniform water interface as the
previous snapshots.

All **133,778** paired system-GLES/Mesa calls matched in their actual arguments
and captured, in-range upload prefixes. No unmatched boundary or payload
mismatch was found. This only covers observed calls, not earlier shader setup
or unrecorded portions of uploaded data. Instrumented counts are not FPS.

## Sampler evidence

No GDB attachment or inferior GL calls were used. A short uprobe at native
`_mesa_uniform` recorded the program/context pointers passed by Mesa itself.
The exact local and deployed `libgallium_dri.so` build IDs both equal
`29895dc125573fdbf6329ae0ef9e5db5c5804715`. Structure offsets were compiled with
the original LoongArch64 Mesa compile command and headers, then used for bounded
read-only `/proc/4963/mem` reads. Program metadata was checked before and after;
the dedicated water snapshots passed that stability check. The process was not
stopped, so these are not atomic full-frame snapshots.

| Sampler | Uniform location | Stored value | Fragment `SamplerUnits` |
| --- | ---: | ---: | ---: |
| `_CameraDepthTexture` | 423 | 423 | 167 |
| `_ReflectionSkyCubeMap` | 426 | 426 | 170 |
| `_Normal01` | 428 | 428 | 172 |
| `_Normal02` | 429 | 429 | 173 |
| `_SceneScaledBufferBeforTransParent` | 435 | 435 | 179 |
| `_SSRTexture` | 436 | 436 | 180 |

All fourteen sampler values follow the same pattern. These are non-bindless
samplers. Mesa stores `gl_program::SamplerUnits` as bytes: the observed stage
values match the low byte of 423–436. CPU texture-object bindings for units
167–180 are zero for 2D, 3D and cube targets. The public API trace places the
water textures in 0–13. Queries of those low units outside a draw are not used
to associate particular texture objects with water, because other draws reuse
the units.

The saved `UniformDataDefaults` entries are all zero, while the current sampler
storage is nonzero and incorrect. This points toward a later assignment or
corruption, rather than these values simply being the saved link defaults.
It does not identify the responsible API call or component.

Comparison programs provide a useful control: stone/grass program 251 maps
locations 171–175 to 0–4; terrain program 540 maps locations 214–227 to 0–13;
program 222 maps 137–139 to 0–2. Other shaders also contain the incorrect
location-as-value pattern, including a terrain shader with height/normal and
terrain-hole samplers. A wider sweep read 136 program objects, 134 passing the
strict whole-metadata stability check; it found 370 low-unit values and 108
location-as-value cases above 31. These sweep counts exclude unstable objects
and are not an exhaustive list of rendering failures.

An early hypothesis about a 255 boundary was disproved: correctly mapped
samplers exist above 255, and incorrect ones below it. Do not add a fix based
on that threshold. Yesterday's anomalous sampler queries are now independently
supported by native CPU state, rather than being dismissed as a query artifact.

## Matrix hypothesis narrowed

A second passive capture records the first 320 bytes of buffer uploads. For
the water draws, `glBufferSubData` uploads 6144 bytes and binds the resulting
buffer at uniform binding 0. The two draws set `unity_BaseInstanceID` to 0 and 1.
The first two entries match the shader's declared offsets:

- Entry zero: object-to-world at 0, inverse at 64, transform parameters at 128.
- Entry one: object-to-world at 144, inverse at 208, transform parameters at 272.

In all seven checked water uploads, both matrix/inverse products are identity
at the captured float precision. Translations are approximately
`(112.836426, 202.399994, 352.633057)` and
`(175.141602, 202.399994, 41.773071)`. Thus the first two entries are populated,
and their 144-byte stride matches the shader. The allocation/upload size 6144
is not evidence of a 192-byte instance stride.

All 14,764 system/Mesa pairs in this shorter capture also matched. These
observations substantially weaken the earlier missing/wrong-layout instance
matrix hypothesis for this scene. They do not verify every vertex, transform,
or shader equation.

## Initialization remains to be captured

Update: the subsequent authorized restart captured the faulty assignment at
the guest boundary. See [the initialization trace](GENSHIN_SAMPLER_INITIALIZATION.md).
The paragraphs below describe the earlier capture's limitation.

A timed five-second capture included a brief HOME/foreground cycle, preserving
PID 4963 and the scene. No link, program-binary load, uniform-location lookup,
scalar sampler setter, or direct-program sampler setter was observed. Existing
programs were retained; foregrounding is insufficient to replay shader setup.
This capture also observed driver-side uniform execution on Mesa's worker
thread, so public API call time must not be equated with worker execution time.

The next decisive trace must cover program creation and sampler initialization,
including `glUniform1i[v]` and `glProgramUniform1i[v]`, and follow the values into
Mesa's `_mesa_uniform`. That will distinguish incorrect incoming values from
driver-side changes. The existing process was not restarted for this task.

## Guest-to-host argument trace validated

The 15:48 two-second capture adds probes at the proxy's generic
`TrampolineFuncGenerator::Func(HostCode, ThreadState*)` entries. Before the
wrapper extracts arguments, it records ARM64 x0–x3 and x30 from `ThreadState`;
vector forms also record the first pointed-to 32-bit element. The recorded
callee address identifies the actual host API, since these trampolines serve
multiple functions. Compare only the ABI-defined low 32 bits of integer
parameters and the full width of pointer parameters.

`genshin-gl-live-20260912-154854/bridge-verification.json` contains 1,272 matched
guest/host `glUniform1iv` calls, no mismatches and no unmatched boundaries.
All captured guest return addresses resolve to this process's `libyuanshen.so`
mapping at file offset `0x528f84c`. That offset identifies an observed caller,
not a proven faulty instruction. No link, binary load, location lookup or
scalar/direct-program setter was captured. Thus this validates the new probes
on ordinary frame updates, not the missing sampler-initialization interval.
The trace contains 350,897 events, including 87,416 generic bridge events;
all 58 probes were removed, and PID 4963 remained alive with `TracerPid: 0`.

`scripts/prepare-gles-bridge-probes.py` generates the optional fourth argument
to `scripts/capture-genshin-gles-inputs.py`. It accepts unstripped libraries or
the device libraries' compressed `.gnu_debugdata`, calculates ELF file offsets,
and records build IDs. The recorder refuses a mismatch before using an offset.
The device EGL proxy is `d7e924027853d8d4e367f366c545fa91`; the GLESv2 proxy is
`e5505d5df58fc0d541643b53eee3577f`. Local unstripped products differed, so this
run used symbols extracted from the actual device libraries. That difference
is probe provenance, not evidence that it causes the water failure.

The current helper remains a short trace attached to an existing PID. A cold
launch requires a collector armed before program creation and covering the new
process; simply restarting while recording `perf -p` against the old PID will
miss it. Generic bridge probes generate substantial traffic and need selective
collection before extending the interval. No game restart was performed here.

The decisive comparison is: guest arguments and pointed-to values, native GLES
arguments, Mesa worker `_mesa_uniform` arguments, and stored sampler state.
If inputs are already incorrect at the guest boundary, use the saved caller to
trace the value producer and build a small JIT/interpreter differential case.
If the first change occurs at the bridge or Mesa boundary, investigate that
component instead. Correct setter inputs with incorrect later state require
tracking subsequent writes; entry traces alone cannot prove storage correctness.

## Evidence and helpers

Outer-workspace directory: `logs/genshin-swimming-20260912/`.

- `before.png`, `after.png`: scene context.
- `genshin-gl-live-20260912-131912/`: primary public API capture.
- `genshin-gl-live-20260912-132327/`: larger matrix upload prefixes.
- `genshin-gl-live-20260912-132511/`: native program/context pointer events.
- `program-355-memory.json`, `program-355-memory2.json`, `program-355-final.json`:
  native program, uniform, sampler, default and texture-binding records.
- `program-sampler-comparison.json`, `all-program-sampler-comparison.json`:
  control shaders and wider survey.
- `mesa-layout.cc`, `mesa-layout.s`, `mesa-layout.json`,
  `mesa-compile-command.json`: layout provenance for the matching build.
- `verify-inputs.py`, `verification.json`: argument/payload pairing and matrix
  verification, using only words within each API's supplied byte/count range.
- `genshin-gl-live-20260912-133722/`: foreground-cycle capture, exact action
  timestamps, counts and probe cleanup.

`scripts/capture-genshin-gles-inputs.py` now also observes sampler initialization
APIs. `scripts/read-mesa-program-memory.py` accepts host PID, the native program
pointer, expected program ID, matching-build layout JSON, and optionally the
context pointer. It refuses a different Mesa build ID and never writes memory
or calls into the application. Its layout and pointer inputs must be regenerated
and verified for a different device/build/process; these are not stable ABI.

The early specialized collectors attempted tracefs event filters, which perf
did not inherit. Their files therefore contain other programs/uploads too;
analysis explicitly selects the relevant program and upload size. Use perf's
per-event `--filter` for future filtered captures. All private probes were
removed by each capture's cleanup path; no tracer remained attached.
