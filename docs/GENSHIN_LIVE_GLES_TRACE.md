# Genshin live GLES trace — 2026-09-11

Follow-up: [water object snapshots](GENSHIN_WATER_OBJECT_SNAPSHOT.md) identify
water programs and record their uniforms, draw state and texture dimensions.
That report also documents a failed synchronous GPU-buffer read and game
restart; the initial passive trace below did not cause that incident.

Attached Linux uprobes to the already-running Genshin host process 19353
(Android PID 5565). The game was not restarted and no game/system files were
changed. Captured the system GLES dispatch and Mesa entry points, then removed
all 64 private trace events. Cleanup reports no errors or remaining probes.

## What was captured

The game maps native `libGLESv2.so`, the Berberis GLES/EGL proxies,
`libGLESv2_mesa.so`, and `libgallium_dri.so`. The trace confirms calls through
the system GLES2 library to Mesa; the GLES2 soname also carries GLES3 functions.

The requested recording interval was two seconds. Event timestamps span
**2.39923353 seconds**, including perf startup/shutdown timing. All 56,594 events
are on `UnityGfxDeviceW`, host TID 19465. The screenshot was taken after collection;
it is scene context, not a pixel-aligned frame capture.

- 50 `eglSwapBuffers` calls.
- 12,423 downstream draws: 9,740 `glDrawElements`, 1,982
  `glDrawElementsInstanced`, and 701 `glDrawArrays`.
- 93 observed program IDs. System-wrapper and Mesa calls were both captured;
  draw statistics count **only Mesa** so each call is counted once.
- Program switches, FBO bindings, blend/depth enables, depth-write masks,
  blend factors, depth functions and color-write masks were recorded.
- No `glShaderSource`, `glCompileShader`, `glLinkProgram` or `glProgramBinary`
  event occurred at these probed boundaries in this window.
- No `glGetError` or `glCheckFramebufferStatus` call was observed. Thus this
  capture provides **no GL error or FBO completeness verdict for the game**.
  The earlier standalone probe's zero-error result must not be substituted here.

These are instrumented observations, not an unperturbed FPS measurement.
Uprobes can slow rendering. No instruction/data changes remain after cleanup.

## How this narrows the next step

`program-draws.csv` groups observed draws by program, including index/vertex
counts, framebuffer IDs, instancing and observed blend-on/depth-write-off state.
Some programs render into FBO 0; many others use offscreen targets. Neither
program number nor blend state identifies water on its own. UI and effects can
blend, while a water shader can copy/refraction-sample the background and write
opaque output. All such classification remains provisional.

State tracking is per observed thread. Initial state is unknown until its setter
is seen; this is not a complete context snapshot or an exhaustive API trace.
Vertex buffers, textures, sampler/uniform bindings, shader sources and output
pixels were not captured. The trace cannot yet distinguish missing geometry
submission from a draw producing transparent/discarded/occluded pixels.

The next useful comparison is the same scene with a camera looking toward and
away from the affected surface, to narrow program/draw candidates. A render
capture or instrumentation layer can then associate candidates with pixels and
inspect shader variants, textures, depth and blend state. Such a layer must
handle programs already created, or be loaded at game startup to record their
creation; historical shader compilation cannot be recovered by merely attaching
entry probes after loading has completed.

Android's stock GLES layer loader constructs dispatch hooks during EGL loader
initialization. Simply changing its debug-layer settings does not insert a new
layer into this existing process. No debug-layer settings have been changed and
no restart is requested or performed by this trace. Source reference:
`frameworks/native/opengl/libs/EGL/GLES_layers.md` in the Android tree.

## Evidence

Paths relative to the outer `/home/noctis/aosp-la64` workspace:

- `logs/genshin-gl-live-20260911/capture-live.py`: exact host-side probe collector.
  It resolves ELF virtual addresses to file offsets and reads native LoongArch
  argument registers r4–r8. Return probes observe existing application calls;
  they do not invoke GL queries themselves.
- `logs/genshin-gl-live-20260911/genshin-gl-live-20260911-210746/`:
  `manifest.json`, `maps.txt`, `perf.data`, `events.txt`, `analysis.json`,
  `program-draws.csv`, recording diagnostics and `cleanup.json`.
- `logs/genshin-gl-live-20260911/current-screen.png`: post-capture scene screenshot.
- `logs/genshin-gl-live-20260911/post-state.txt`: game still present, no remaining
  uprobe events.

An initial registration attempt failed before creating any probe because opening
the tracefs control file with append mode was rejected. The collector was corrected
to use `os.open(..., O_WRONLY)` without truncation. The successful run above is the
only rendering sample used for these findings.

## Retained diagnostic tools

The integration repository also retains `capture-genshin-gles-inputs.py`,
`capture-genshin-sampler-init.py`, `prepare-gles-bridge-probes.py`,
`read-mesa-program-memory.py` and `capture-la64-host-reset.py` under `scripts/`.
These are investigation tools for the recorded device and Mesa builds; inspect
their arguments, build-ID checks and local artifact paths before reusing them.
The memory reader's texture-binding inspection is fixed to units 0–13 and
167–180 from an earlier snapshot. It is not the generic validator for the later
profile-enabled scene in [the GPU profile report](GENSHIN_GPU_PROFILE.md).
