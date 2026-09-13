# Unity Terrain probe: 2026-09-11

The standalone test builds and runs. Windows and LoongArch64 Waydroid/GLES3
both render all ten Mesh/Terrain cases without the extensive missing terrain
observed in Genshin. This narrows the reproduction: it does **not** establish
that Genshin uses standard Terrain, or rule out a translator defect in another
instruction or rendering path.

Source and reproduction commands: [tests/unity-terrain](../tests/unity-terrain/README.md).

## Environment and build

- Unity **2022.3.62f3**, revision `96770f904ca7`, Built-In Render Pipeline.
  Windows Editor, Android Build Support, SDK/NDK and OpenJDK were installed
  through the existing Hub. Windows/D3D11/Mono and Android ARM64-only/IL2CPP
  GLES3 and Vulkan builds all succeeded.
- The initial 2022.3.72f1 recommendation was incorrect for the available
  Personal license: the Editor required Extended LTS licensing and exited 198.
  62f3 was verified by actual successful builds with the available license.
- Windows reference: Windows 11, RTX 4070 Ti SUPER, Direct3D 11, Mono.
- Device: Loongson 3A6000, Android 16 Waydroid, AMD polaris10,
  OpenGL ES 3.2 / Mesa 26.1.6, host kernel `7.1.7-aosc-main-4k`.
  Android's emulated device/CPU strings are not evidence of physical ARM hardware.
- Restored fifth-batch Berberis SHA-256:
  `c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`.
  Global mode is `lite-translate-or-interpret`; ART JIT is enabled.

## Results

| Run | Data checks | Rendered output | Interpretation |
| --- | --- | --- | --- |
| Windows D3D11 / Mono | 10/10 | All 10 camera and 10 screen images reviewed; continuous surfaces | Reference for this fixture |
| la64 GLES3 / IL2CPP / Berberis JIT | 10/10 | All 10 camera and 10 screen images reviewed; continuous surfaces | Standard Terrain cases did not reproduce missing terrain |
| la64 Vulkan-only / IL2CPP | No scene output | Unity hardware-requirement dialog during initialization | Vulkan comparison unavailable on this configuration |
| la64 GLES3 / attempted per-app interpreter | No scene output | ARM64 `libmain.so` failed to load | Invalid interpreter control; no rendering conclusion |

The ten cases cover ordinary unlit/lit Mesh, flat/hilly Terrain, one/two layers,
instancing off/on, and heightmap pixel error 1/20. Inputs are deterministic,
asymmetric heightmaps shared by Mesh and Terrain. The fixtures use uncompressed
RGBA32 textures and no game resources, network, AssetBundles, foliage, holes,
baked lighting, or custom terrain shader. Independent host checks passed for
height hashes, peaks, all 32,768 triangle windings/indices, vertex coverage and
8,192 alpha sums.

All GLES3 shaders reported supported. Terrain height readback differs from
input within the allowed quantization tolerance (maximum normalized error
`1.52587890625e-5`); the maximum alpha error was about `0.000980407`.
Screenshots were visually compared, not declared pixel-identical across APIs
or GPUs. `COMPLETE.txt` and `cpuReadbackPass` alone are not visual passes.

Direct process inspection confirmed that the successful GLES3 run mapped the
expected library/inode: Android PID 10745 / host PID 24720, translation mode 1,
42,814 successful JIT translations and 17,255 gear-ups at inspection time.
These counters establish active JIT, not exclusive JIT execution.

The Vulkan launch logged failure to load `vulkan.radeon.so` and
`vulkan.waydroid.so` in the loader's namespace, followed by `Vulkan detection: 0`.
The captured screen showed Unity's hardware-requirement warning. Selecting
Continue did not produce a scene; the probe was subsequently force-stopped.
This is an initialization/availability finding, not evidence of a Vulkan
Terrain shader bug or an explanation of Genshin's missing terrain.

For the per-app interpreter experiment, `wrap.<package>` launched through
`env BERBERIS_MODE=interpret-only`. This launch did not correctly initialize
Native Bridge: `libmain.so` was rejected as EM_AARCH64 instead of host machine
258. The wrap property was restored to empty immediately after launch. The
unusable option was removed from the runner; its experimental script and logs
were retained. The earlier `runtime-initial.json` sampled the previous normal
process before the new launch and is **not** interpreter-run evidence.
The failed probe was force-stopped; no pure interpreter scene was captured.

## Artifacts

Paths below are relative to the outer `/home/noctis/aosp-la64` workspace;
generated binaries, images and logs are not integration-repository source.

- `logs/terrain-probe-windows-20260911/`: reference data, images, summary and contact sheets.
- `logs/terrain-probe-gles3-20260911/`: successful device capture, process verification,
  data reports, all images, `contact-sheet.png` and `screen-contact-sheet.png`.
- `logs/terrain-probe-vulkan-20260911/`: initialization logs and warning screenshot;
  no completed Terrain matrix.
- `logs/terrain-probe-gles3-interpret-20260911/`: invalid wrapper-launch control.
- `logs/genshin-restore-jit-20260911/`: restoration, installation, build and fixture-check logs.
- `lineage-waydroid-loongarch64/tests/unity-terrain/Builds/`: APKs, Windows reference and Editor logs.

| APK | SHA-256 |
| --- | --- |
| `terrain-gles3.apk` | `c42854313c6f44fb593ec87256b802fae17788e5acc9f6aed07fe42a964067d9` |
| `terrain-vulkan.apk` | `75c17b1892a6013e28e4913ee2d6a000456cc32c4d8ec2c717d40aabbfa26163` |

## Remaining investigation

There is still no confirmed known-good Genshin scene on a reference translator
version. An original ARM64 Android run would also provide a closer reference
than Windows/Mono. The next useful evidence is the game's actual terrain draw
path: whether geometry is submitted, shader/link errors, texture and buffer
contents, and whether culling or draw parameters suppress it. Extend the probe
with a specific failing operation found there; success of these standard API
cases does not justify reverting or exonerating every JIT optimization.

A working per-process interpreter control remains desirable but requires a
Native Bridge-compatible launch/configuration mechanism. It was not achieved
by this test and is not represented as a passing comparison.
