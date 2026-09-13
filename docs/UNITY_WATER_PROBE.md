# Water-related GLES tests — 2026-09-11

The standalone water matrix did not reproduce Genshin's missing surfaces.
The tested GLES entry points are available through ARM64 translation, and the
covered rendering paths work. This does not prove that every API or shader
used by Genshin works, or establish whether every missing surface is water.

Source and commands: [water probe](../tests/unity-terrain/WATER.md).

## Scope

Unity 2022.3.62f3, Built-In pipeline, fixed perspective camera, checkerboard
riverbed and three colored pillars. Windows/D3D11/Mono provides the reference;
the device runs ARM64-only/IL2CPP through Berberis on la64, OpenGL ES 3.2,
Mesa 26.1.6, AMD polaris10, host kernel `7.1.7-aosc-main-4k`.

Twelve captures cover the no-water reference, opaque water mesh, alpha blend,
sampled depth, depth-dependent alpha, GrabPass copy/refraction, planar reflection
in ARGB32/ARGBHalf/ARGBFloat, and four ordinary versus four instanced draws.
Reflection render targets are also saved separately. No network or game assets
are required. This is not a reproduction of Genshin's custom water shader.

## Findings

- Both platforms completed all twelve cases without skipped formats or unsupported
  shaders. Transparent, depth-dependent, refractive and reflective paths are visible.
- On la64, the no-offset color copy is pixel-identical to the background reference.
  That case deliberately looks like there is no water; it tests copying, not tinting.
- One water plane, four ordinary draws and four instanced draws have identical
  fixed-camera RGB captures on la64. The two instancing paths are also identical
  on Windows. This does not reproduce the shader-variant mismatch logged by Genshin.
- The la64 alpha=0.5 result matches half foreground plus half background over
  38,964 interior water pixels, with a maximum difference of 0.5 in 8-bit units.
- ARGB32, ARGBHalf and ARGBFloat reflection captures match on la64. The requested
  formats were actually allocated. This tests these formats with this scene;
  it does not stress arbitrary HDR values, precision ranges, or every FBO combination.
- The ARM64 diagnostic plugin runs in the GLES render context. All 15 selected
  procedures have non-null addresses; 166 extensions were enumerated. Sampled
  main and reflection FBOs report `GL_FRAMEBUFFER_COMPLETE` (`0x8cd5`), and sampled
  pre/post GL errors are zero across 797 final-run events. The final captured
  log has no Unity error records. Entry-point presence alone does not validate its
  full implementation. Errors already consumed by Unity cannot be recovered here.

Windows and la64 captures are not pixel-identical: their background-only scene
already differs in shading. The cross-platform image metrics are descriptive,
not a universal pass threshold. Same-platform paired checks above are stronger
evidence for the specific operations they isolate.

The first Android build logged a missing `BoxCollider` type when creating cubes:
IL2CPP stripped a component reached internally by `CreatePrimitive`. A `link.xml`
retention rule fixed this test-program error. The diagnostic plugin also limits
each event to 256 samples so leaving the test window open cannot grow its log
without bound. The initial captures are retained separately from the final APK.

## Artifacts

Paths are relative to the outer `/home/noctis/aosp-la64` workspace.

- `logs/water-probe-windows-20260911/`: Windows reference, all images and player log.
- `logs/water-probe-gles3-20260911/`: initial capture, including the unrelated
  test-program component-stripping errors.
- `logs/water-probe-gles3-final-20260911/`: component-retention fix control.
- `logs/water-probe-gles3-bounded-20260911/`: final APK capture with bounded logging.
- `logs/water-probe-build-20260911/`: build orchestration and initial comparison records.
- `lineage-waydroid-loongarch64/tests/unity-terrain/Builds/water-gles3.apk`:
  SHA-256 `ad331f2bc834aa37ce0d1dd33780f7d67472512c93d4c2480f46f1f3a19a9fd1`.

The test changes no Berberis library, system image, global JIT setting or game
data. Only its own package is installed/restarted. Device JIT remains enabled.
Final process inspection verified translation mode 1 with 39,780 JIT successes
and 16,569 gear-ups, mapping the expected fifth-batch library. All twelve camera
and twelve screen images were visually reviewed on both platforms.

## Implication for Genshin

No missing API was found among the selected water-related entry points, and
these basic water rendering paths work. The remaining concrete game evidence
is eight warnings that a non-instanced shader was requested but an instanced
shader was returned, recorded in `logs/genshin-water-api-20260911/`.
The warning has not been tied to a water material or missing draw.

The next discriminating evidence is the actual game's water draw submission,
shader variant, resources and depth/blend state. The results here do not justify
declaring every JIT optimization correct or clearing game shader/resource caches.

Follow-up: [live GLES tracing](GENSHIN_LIVE_GLES_TRACE.md) recorded the running
game without restarting it: 50 swap calls, 12,423 downstream draws and 93 observed
program IDs. No shader creation or GL error-query calls were observed in that
window; candidate draws are not yet mapped to the missing surface.
