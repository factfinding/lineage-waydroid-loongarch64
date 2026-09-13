# Genshin sampler initialization traced across restart — 2026-09-12

The authorized restart reproduced the missing water and captured the faulty
assignment. Water program 342 receives `glUniform1i(423, 423)` through
`glUniform1i(436, 436)`. The incorrect second argument already exists in ARM64
`ThreadState` before Native Bridge converts arguments. The bridge, public GLES
and Mesa setter preserve the supplied values.

This locates the assignment; it does **not** establish why the game selects
this path. In particular, an upstream translated condition or corrupted flag
has not been excluded. Do not label this a confirmed JIT regression or a
confirmed game bug yet.

## Capture and validation

Host game PID changed from 4963 to 34346. Waydroid itself was not restarted.
`scripts/capture-genshin-sampler-init.py` registers probes against the stable
container filesystem, enables system-wide perf events and waits for perf's
acknowledgement before force-stop/start of the exact game component.

The first interval starts before launch and lasts 240 seconds. The second
180-second interval attaches to the new process and covers scene loading.
Their recording windows overlap. The screenshots show resource preparation,
world loading and the returned swimming scene with missing water.

| Interval | Guest/host calls matched | Argument mismatches | Location-as-value assignments |
| --- | ---: | ---: | ---: |
| `genshin-sampler-init-20260912-160429` | 48,453 | 0 | 11 |
| `genshin-sampler-init-20260912-160822` | 49,697 | 0 | 301 |

Two early scalar calls in the first interval have no matching bridge entry;
they are excluded from the matched count. All second-interval scalar/vector
integer calls match. The ordered sequences of location, count and first value
at the public GLES API and Mesa `_mesa_uniform` also match for all 49,697
second-interval calls. Vector payload comparison covers the first element only.

Each capture removes all 51 of its probes. Final verification found no remaining
`gsinit_`/`gwater_` probes, `TracerPid: 0`, a live PID 34346 and an empty Android
crash buffer. No ptrace, GL calls, GPU mapping or application memory writes were
used.

## Water assignment and controls

Twelve water-related program interfaces were observed in the second interval.
They form six consecutive pairs with the same ordered sampler names. The first
member uses compact texture units and the second uses uniform locations as units.
For the final pair:

| Program | Sampler locations | Values passed to GLES |
| --- | --- | --- |
| 341 | 153–166 | 0–13 |
| 342 | 423–436 | 423–436 |

Both were loaded using `glProgramBinary`. Program 342 matches the previously
observed water interface (old PID 4963, program 355), including `_CameraDepthTexture`,
`_Normal01`, `_Normal02`, `_SceneScaledBufferBeforTransParent` and `_SSRTexture`.
Do not assume program IDs survive process restarts.

At monotonic time 29416.11279551, the first bad water call has guest arguments
`[423, 423]`, with guest return address `0x7ffc1a9f067c`. Mesa subsequently
receives program 342, location 423, value 423. A read-only snapshot after loading
passes the whole-metadata identity check and confirms 222 uniforms, the same
423–436 stored values and the corresponding truncated stage sampler units.

## The original ARM64 branch

All 301 location-as-value assignments in the second interval come from
`libyuanshen.so` file offset `0x52a467c` (the return address). Nearby code:

```asm
ldr  w8, [x19, #0x2c]
tbz  w8, #0, other_path
...
bl   query_uniform_location_helper
ldr  x8, [x25, #0x6e8]
mov  w1, w0                 // file offset 0x52a4670
ldr  x8, [x8, #0x118]
blr  x8                    // glUniform1i
```

The helper calls the active-uniform query and uniform-location query, then
returns the location in w0. This branch explicitly copies w0 to w1. The other
branch uses `mov w1, w23`, where x23 is a loop index incremented from zero.
Thus the observed equal arguments agree with the original code on the taken
path. The 1,024-byte memory range beginning at `0x7ffc1a9f0400` exactly matches
the installed library at file offset `0x52a4400`, including this instruction.
This is not evidence that Berberis rewrote that instruction.

The observed normal setup calls use a different caller, file offset
`0x52964b0`; frame integer updates use `0x528f84c`. The later
[variant-binding investigation](GENSHIN_SHADER_VARIANT_BINDINGS.md) traces
`[x19 + 0x2c]` to a graphics-version-controlled global byte, recovers the
water source templates, and reproduces both location ranges with native source
compilation. Merely interpreting the copy instruction does not test the earlier
decision; the follow-up also checks the flag's original producer and runtime
inputs.

## Why Mesa preserves out-of-range values

Offsets compiled from the matching Mesa build show:

- Context flags: 8, so `GL_CONTEXT_FLAG_NO_ERROR_BIT_KHR` is enabled.
- `MaxCombinedTextureImageUnits`: 192.
- `NumExplicitUniformLocations`: zero for both programs 341 and 342.

The last field is not serialized by Mesa's program-binary path. Its zero value
after binary import does not establish whether the source used explicit
locations; the per-uniform `remap_location` and remap table are serialized.

Mesa's `_mesa_uniform` bypasses `validate_uniform` in a no-error context, then
stores the input. This explains why these out-of-range values reach storage.
Disabling error suppression would not, by itself, supply the correct 0–13
mapping. No Mesa setting or game code was changed in this investigation.

## Tools and evidence

Outer-workspace directory: `logs/genshin-init-20260912/`.

- Both capture directories: `perf.data`, `events.txt`, probe manifests,
  process mappings, cleanup results and analysis JSON.
- `analyze-init.py`: guest/host pairing, name lookup, setter and program records.
- Second capture `host-driver-sequence.json`: 49,697 ordered comparisons.
- `program-342-memory.json`: stable read-only water-program snapshot.
- `bad-caller.bin`, `bad-caller-file.bin`, `bad-caller.asm`,
  `caller-code-comparison.json`: exact original-code comparison.
- `location-helper.bin`, `location-helper-caller.asm`: helper disassembly.
- `mesa-init-layout.cc`, `.s`, `.json`: context and explicit-location offsets.
- `world-progress.png`: returned swimming scene.

The new collector uses per-event perf filters, not tracefs filter files.
Its bridge filter recognizes the public dispatch stubs' instruction words,
which remain stable under ASLR. This filter only reduces traffic: analysis
still resolves the actual callee through process maps and ELF file offsets.
Proxy offsets require matching build IDs; the private Mesa symbol and layout
require build ID `29895dc125573fdbf6329ae0ef9e5db5c5804715`.

See [the preceding swimming snapshot](GENSHIN_SWIMMING_SAMPLERS.md) for the
earlier texture bindings, matrix checks and limitations.
