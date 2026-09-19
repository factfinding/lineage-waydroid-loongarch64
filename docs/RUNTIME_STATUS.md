# Runtime and Translation Status

Last updated: 2026-09-19

This page tracks development-branch runtime results. It is not a statement about the older `v0.2.2` release unless explicitly noted.

## 2026-09-19 source snapshot and full image rebuild

The current application, JIT, media and Helper changes are committed locally.
The user has now authorized a full system/vendor rebuild and paired deployment,
superseding earlier requests to defer image rebuilding. Source revisions and
build/deployment results are recorded in [FULL_IMAGES_20260919.md](FULL_IMAGES_20260919.md).
The automatic host reset remains unresolved; this snapshot is not a host-reset fix.

## 2026-09-19 FFmpeg per-instance output negotiation fix

The temporary global YUV workaround below is superseded by a component fix.
FFmpeg now converts to the pixel format negotiated for each codec instance;
`debug.ffmpeg-codec2.pixel_format` is used only for opaque Surface output.
Explicit YUV420 requests allocate planar YV12 and pass separate Y/U/V strides
to swscale. RGBA, RGBX and BGRA use the matching packed FFmpeg layouts; BGRA
starts at logical B. Unsupported byte-buffer RGB565/P010 requests fail during
configure instead of silently retaining the old format and failing on frames.
Hardware download respects explicit formats in source, but VAAPI is not
runtime-validated on this device.

The RGB control exposed additional framework defects. Gralloc's RGBA/BGRA
layouts omitted alpha and BGRA named the wrong root plane. The MediaImage
converter lacked a complete packed RGBA copy layout and could not wrap BGRA
from its physical first byte. Finally, CCodecBuffers applied a YUV-only plane
offset calculation to RGB, shifting BGRA data by two bytes. These are fixed
alongside format negotiation. RGBX opaque Surface output remains supported.

Validation on the 4 KiB LoongArch host:

- Component builds completed with `-j8`, without rebuilding full images.
- Native `ColorLayoutTest.*` passes, covering RGBA/BGRA channel and alpha
  values, wrapping, forced copying, and final client buffer range.
- Concurrent YUV420-planar and RGBAFlexible decoders each emit 12/12 correct
  red frames and EOS under both global YUV_420 and RGBX_8888 preferences.
- Flexible YUV420 emits 12/12 correct frames; RGB565 and P010 configure are
  rejected as expected.
- Under RGBX_8888, H.264 byte-buffer, H.264 Surface and VP9 Surface controls
  each emit 60/60 frames and EOS. Surface controls check delivery/timestamps,
  not screen pixels. All probes run in native ART without ARM64 translation.

Five component files were installed in writable overlays; full images were
not rebuilt. Original effective files and pre-existing overlay state are in
`/var/lib/waydroid/deploy-backups/20260919-codec-format-negotiation/`.
Restore the five saved relative paths to their matching system/vendor overlay
locations with the container stopped to roll back; then restart the session.
Keep RGBX_8888 as the product default. Game data and the deployed FMAX JIT fix
are preserved. The separate software-codec APEX was not replaced; these
runtime results cover the FFmpeg vendor service and system client libraries.

Deployed SHA-256:

| Component | SHA-256 |
| --- | --- |
| system/lib64/libsfplugin_ccodec.so | `d28c09983e423185fd51a8cca5f6d0ae5c727b3b5192e61a773fe2c476a8f0f5` |
| system/lib64/libcodec2_vndk.so | `79be97a543169dcfae2e1254db89eab475adf88c8befe474617c943391a5a188` |
| system/lib64/libsfplugin_ccodec_utils.so | `630971a1ae041338f2beb887804f45dc2660cb9184ae3e7674148eecdbcdd7f7` |
| vendor/lib64/libcodec2_vndk.so | `eb9e37c9ff448a73e9ff68c5ea174e801451a03cea993727e9a632f035a03c55` |
| vendor/bin/hw/android.hardware.media.c2-ffmpeg-service | `a4bbf81c1d9fb3482b7634c0dcb5af8756e9b0d117a0b384478a4d552bba79b2` |

After restarting Waydroid, `sys.boot_completed=1`, all five effective hashes,
RGBX_8888, and the existing Berberis hash/mode were verified. Concurrent YUV
and RGBA pixel controls passed again. Honor of Kings PID 1529 created its
1280x720 H.264 byte-buffer decoder at 09:42:53; conversion remained
`yuv420p => yuv420p` despite RGBX being the global default. Successive screenshots
show its background video advancing while startup loading reached 96.5%.
The previous format-rejection/Released-state loop did not recur during this
capture. The crash buffer contains a separate Launcher3 taskbar null reference
at 09:40:48; no game crash was observed. After the Start Game control, the
game reached its lobby by 09:45, showing the optional non-Wi-Fi resource
download prompt. That preference was left for the user. Match completion
remains untested.

Evidence: `logs/media-format-negotiation-20260919/`. Reusable probes and
commands: `tests/media-codec/README.md`.

## 2026-09-19 Honor of Kings FFmpeg RGBX/YUV diagnosis (temporary setting)

The Start Game screen's codec error loop is traced to the product-wide
`debug.ffmpeg-codec2.pixel_format=RGBX_8888` setting. The game's libPixVideo
requests YUV420 byte-buffer output from native `c2.ffmpeg.h264.decoder`;
the actual RGB layout is rejected by GraphicView2MediaImageConverter with
`-22`. MediaCodec subsequently reports UNKNOWN_ERROR and enters Released
state, while the application continues dequeuing buffers. This is distinct
from the champion-selection FMAX fallback bug below.

A public CodecProbe running entirely in native LoongArch ART reproduces the
same converter error and Released-state exception. Temporarily changing the
property to `YUV_420` gives 60/60 output frames with EOS for H.264 byte-buffer,
H.264 Surface, and VP9 Surface controls. Restarting the game under YUV restores
its background video and eliminates the observed converter/error loop. The
sampled NDK codec thread drops from about 95% to 3% of one CPU; this is not a
controlled whole-game benchmark. A diagnostic Start Game tap at 09:11:24 then
advances through login to the S44 initial-rank page. Match loading/completion
and the earlier champion-selection scene remain untested in this run.

At this diagnostic stage the device used **temporary `YUV_420`**; source and
image defaults remained RGBX_8888. The per-instance fix above supersedes that
workaround and restores the product default. Original evidence:
`logs/honor-of-kings-20260919/codec-trace/`.

## 2026-09-19 Honor of Kings NaN fallback progress fix

Champion selection froze at 00:22 while a Unity job worker used one CPU and
UnityMain waited on a futex. A 1000-sample capture found the worker unchanged
at `libunity.so + 0x14487b4`: word `0x1e214881`, `fmax s1, s4, s1`, with a
quiet NaN in s4. The earlier MediaCodec log flood was absent during this stall.

The scalar min/max NaN fallback returned to the dispatcher at the same guest
PC without interpreting the instruction. The dispatcher then re-entered the
same cached translation. The candidate enters the interpreter directly when
dispatch is enabled; isolated non-dispatch translations retain their existing
fallback contract. Ordinary finite arithmetic and cache write-through rules
are unchanged.

The new dispatch-progress test covers nine instruction forms and three NaN
placements. It fails on the old translator and passes after the fix. Component
builds and **211/211** device runtime tests pass on the 4 KiB kernel. Candidate
Berberis SHA-256:
`f4645ccd9a8ea4083761c38f656343e11c519fc6ed03d858a3a098c95b7911a6`.
Evidence: `logs/honor-of-kings-20260919/deep-stall/`.

The user authorized deployment after confirming the game was still frozen.
The shared library was installed in the system overlay and Waydroid restarted.
`sys.boot_completed=1`, the effective Android library hash, JIT-enabled mode,
and 4096-byte host pages were verified. The previous `dc93c133...` library is
backed up at
`/var/lib/waydroid/deploy-backups/20260919-sgame-fmax-progress-084900/`.
No full images were rebuilt and game data was preserved. Actual recovery in
the champion-selection scene and the exact synchronization dependency between
UnityMain and the worker still require verification.

## 2026-09-18 Hearthstone TACT child-process follow-up

After restoring the 4 KiB kernel, the main process reached the updater but
reported repair-required error 11. Game logs identify `Failed to send TACT
initialization request`; Android exit-info records three SIGABRT exits for
`com.blizzard.wtcg.hearthstone:tact_service`. A debugger reproduction confirms
that native libartbase read/mmap imports again point into ARM64 libunisec,
with the host PC at the guest read callback and the FD at protected classes.dex.

The initial hook repair's exact main-process name check missed this child
process. The compatibility gate now explicitly includes this audited TACT
process as well. It does not enable arbitrary applications or subprocesses.
Both component builds passed and **210/210** runtime tests passed on the
current 4 KiB device. This follow-up does not change the typed callback
implementation or the ELF alignment repair.

- Deployed Berberis SHA-256: `dc93c13376fc6caa901a2be5519e9877e223581288969b7729f0f2148d988d80`.
- Backup: `/var/lib/waydroid/deploy-backups/20260918-hearthstone-tact-hooks-v2`.
- Waydroid restart completed; effective hash and 4096-byte page size verified.
- Evidence: `logs/hearthstone-20260918/error-followup/`.
- No full images were rebuilt and no game data was manually cleared.

After deployment, the TACT child remains alive and publishes its Binder
service. Logs confirm successful TACT initialization; the DBF/string phase
completes and the 4.72 GB content phase downloads at approximately 17–19 MB/s.
The saved log advances beyond 344 MB downloaded with an empty Android crash
buffer, and the screen shows "正在布置旅店……" instead of error 11.
The game is left downloading; full download, login and matches remain untested.

## 2026-09-18 Hearthstone startup repair

Hearthstone 36.6.251952 (25195200), package `com.blizzard.wtcg.hearthstone`,
exposed two independent compatibility defects during startup:

1. Its ARM64 protection library replaces native `libartbase.so` read/mmap
   imports with ARM64 callbacks. Native ART previously jumped directly into
   guest code. Berberis now registers the native originals before guest JNI
   initialization and wraps guest replacements on JNI return using the
   existing CFI-safe static trampoline pool. The typed callbacks preserve the
   protection library's DEX decryption and calls to the originals. This path
   is restricted to this package and the audited synchronous initialization
   hooks; it is not a general concurrent GOT-write interception mechanism.
2. The protected `libunity.so` tail segment declares 16 KiB alignment, but its
   virtual and file offsets agree only modulo 4 KiB (`p_vaddr=0x1c32000`,
   `p_offset=0x1acc000`). On the 16 KiB host the ordinary mapping places zeros
   at the constructor address instead of the actual code. Bionic now checks
   actual congruence and selects its existing 4 KiB compatibility copying
   loader. This does not relax the 4 KiB congruence requirement.

Component builds passed. The Berberis device suite passed **210/210**, including
six new typed-hook tests. An independent native ELF mapping probe reproduces
zero bytes with the old linker and the correct magic with the candidate;
normal 16 KiB and declared 4 KiB layouts pass with both. See
[`tests/linker-segment-alignment`](../tests/linker-segment-alignment/README.md).

Only Berberis and the ARM64 guest linker overlays were deployed. The native
linker candidate was used temporarily for the regression probe; the native
runtime APEX was not replaced. No full images were rebuilt and no app data
was cleared. Effective hashes were verified after Android boot completed:

- Berberis: `edc6ed84910ed4bc13a6084bedae9b0c96f9174c887b037eaeb84dd379dd71a5`.
- ARM64 linker: `190379f64df40d08b20927a07d2ba23b0c5c9c376669fef370a45b43bed15913`.
- Backups: `/var/lib/waydroid/deploy-backups/20260918-hearthstone-art-hooks-v1`
  and `/var/lib/waydroid/deploy-backups/20260918-hearthstone-linker-alignment`.
- Local evidence: `logs/hearthstone-20260918/REPORT.md` and `fix/` build,
  regression, deployment, logcat and screenshot records.

An ordinary launch (no debugger) passes protected DEX, Unity 6000.3.11f1 and
IL2CPP initialization and reaches the game's first-use privacy/license
agreement screen. The same process stays alive beyond two minutes with an
empty Android crash buffer and unchanged host boot ID. Agreement acceptance
is left to the user; login, resource downloads and matches are not validated.
JIT remains enabled and the Instagram native decoder policy remains true.

A follow-up on the user's restored 4 KiB kernel isolated an input issue:
touch-source drag/tap worked, but mouse-source drag/tap did not; wheel scroll
still worked. Adding `com.blizzard.wtcg.hearthstone` to the device's existing
`persist.waydroid.fake_touch` list (preserving `com.kurogame.mingchao`) and
restarting the app made the same injected mouse drag and privacy-link click
work. This uses Waydroid's existing per-app ViewRootImpl source conversion;
no JIT/framework rebuild is involved. The app was returned to the agreement
screen without accepting it. Evidence: `logs/hearthstone-20260918/input/`.

At the user's request, `com.tencent.tmgp.sgame` (Honor of Kings) was subsequently
added to the same persistent device list, preserving both existing entries.
Property readback passed. Existing Honor of Kings windows require a full app
reopen; its background process was left running while Hearthstone was foreground.
Honor of Kings input behavior is not yet validated. Evidence:
`logs/honor-of-kings-input-20260918/`.

To roll back, stop Waydroid, restore each saved `.overlay` file to its matching
`overlay_rw/system/system/` destination (or remove that single overlay file if
its backup has an `.overlay-absent` marker), then start Waydroid and the desktop
user's graphical session. Do not replace full images or remove app data.

## 2026-09-18 NetEase Cloud Music executable-segment tracking repair

NetEase Cloud Music 9.5.61 (9005061) rewrites the in-memory ELF header of
`libnesec.so`. When another library (`libpoison.so`) loads, Berberis previously
reparsed every ELF header and treated the rejected header as an unloaded
object. It cleared guest executable bits while libnesec was still present in
`link_map`. App-filtered tracing records both erroneous clears immediately
before `HandleNoExec` at libnesec+0x68194, matching the original crash core.
The host mapping being read-only is normal for translated code and is not
itself evidence of missing guest execute permission.

The linker synchronizer now caches executable segments by link_map node and
load bias for each live object, clearing them only when that object leaves
the list. It preserves explicit guest permission revocation and registers
replacement ranges after clearing removed objects. This changes loader
bookkeeping, not ARM64 instruction decoding or JIT optimizations.

`m -j8 libberberis_arm64 berberis_runtime_arm64_loongarch64_tests` passed;
all **204/204** device runtime tests pass, including six new cases for altered
headers, explicit revocation, actual unload, reload and address reuse.
Only the library overlay was deployed; no full images were rebuilt and no
app data was cleared.

- Library SHA-256: `a9805966db7d8f9d7754d5fca29a66f94d7405fdd6225e3a0e96e2cd37fa1528`.
- Backup: `/var/lib/waydroid/deploy-backups/20260918-netease-link-map`.
- Evidence: local `logs/netease-music-20260918/`, including trace, crash analysis,
  build and device test logs. Private app libraries/core files are not published.

After the Waydroid restart, Android reached boot-completed and the effective
library hash matched. An ordinary app launch (no debugger or tracing) loaded
libpoison successfully and reached the first-use terms/privacy dialog. The
same process remained foreground/alive for 127 seconds with an empty crash
buffer and unchanged host boot ID. The notification permission prompt was
declined during validation. Terms acceptance is left to the user, so home,
login and music playback are not yet validated. Berberis tracing is disabled;
JIT remains enabled and the Instagram decoder policy remains true.

The original no-exec fault also exposed missing LoongArch architecture
selection in unwindstack, which aborted while ART tried to report the fault.
That separate diagnostic limitation remains outside this repair.

## 2026-09-17 Instagram process-local decoder policy

An opt-in framework hook changes `Build.MODEL` to `Waydroid Emulator` only in
`com.instagram.android` processes using the Berberis native bridge, before
application initialization. The LoongArch64 product now sets
`debug.waydroid.instagram_native_av1=true` in vendor/build.prop at every boot.
The property name is retained from the original AV1 investigation. Set false
and restart the app to temporarily undo the policy; Android restart restores
the product default. To disable it permanently, change the product property
or the device's vendor/build.prop overlay. The framework fallback is still
false on other products. Global
device properties and other packages are unchanged. No app data was cleared.

Instagram 442.0.0.46.79 contains an emulator branch preferring platform dav1d,
but **the observed application playback after the override selected native
`c2.ffmpeg.vp9.decoder`, not platform AV1**. Multiple clips played, clip changes
and background/foreground return worked, and the user confirmed substantially
smoother video. This verifies a useful native VP9 route; it does not establish
Instagram platform-AV1 playback or isolate why stream selection changed.
Model substitution can also affect other app policies; validation is limited
to this Instagram version. The user requested the validated policy as the default.

Before the switch, two bundled ARM64 dav1d threads used 91.84% and 90.19% of one
logical CPU; Instagram totaled 235.5%. A stable 20-second VP9 sample afterward
used 48.78% in Instagram, 16.35% in the FFmpeg service and 0.25% in swcodec,
with no guest dav1d decoding load. Startup/clip loading had higher transient
costs. These are different clips/codecs, not a matched-content speedup or a
measurement of displayed frame rate.

`m -j8 framework-minus-apex` passed. `InstagramCompatProbe` passed fresh-process
false/true/false tests, checking package exclusion, an unchanged global model,
and no model leakage into a new process. Android reached boot-completed, the
crash buffer stayed empty, and the host boot ID did not change. Only the
framework jar was deployed, not a new full image pair:

- Framework SHA-256: `7da9b0729c0282c814f83039961af8cb64b5d78ac9b753b2ef3b6668b5acddc8`.
- Backup: `/var/lib/waydroid/deploy-backups/20260917-instagram-native-av1`.
- Original framework overlay was absent; full rollback stops the container,
  removes only the newly introduced framework jar overlay, and restarts the
  container/user session. The backup also contains the original deployed jar.
- Local evidence: `logs/instagram-native-av1-20260917/switch/`.
- Probe and usage: `tests/media-codec/InstagramCompatProbe.java` and README.

The subsequent permanent-default deployment changed only vendor/build.prop,
preserving the existing AAC/FFmpeg settings. Its backup is
`/var/lib/waydroid/deploy-backups/20260917-instagram-native-default`.
After a full Waydroid restart, the property automatically read true (no setprop
after restart), `InstagramCompatProbe true` passed, boot-completed was 1, the
global model remained `2509FPN0BC`, and Instagram again created native VP9 and
AAC decoders with an empty crash buffer. Source default:
`device/waydroid/waydroid/waydroid_loongarch64/lineage_waydroid_loongarch64.mk`.
The full image rebuild was cancelled at the user's request; no new image pair
was completed or deployed for the permanent-default change. Product source and
the device overlay retain the setting. Evidence is tracked separately in
`logs/instagram-native-av1-20260917/permanent/`.

## 2026-09-16/17 AV1 fallback, planar YUV and ARM64 SIMD decoding repair

The FFmpeg Codec2 store no longer publishes the built-in hardware-only AV1
implementation when acceleration is disabled, host AV1 capability is missing,
or its hardware context cannot be created. The framework now recognizes
`minigbm_` gralloc variants, exposing native Android software video decoders.
The LoongArch swcodec sandbox includes the common crash-reporting policy and
Mesa affinity calls; the newly exposed dav1d path otherwise died on `geteuid`
and affinity syscalls.

The original public MediaCodec reproduction accepted 60 AV1 input frames and
emitted zero. Native `c2.android.av1-dav1d.decoder` now emits all 60 frames in
both byte-buffer and Surface tests. H.264 and VP9 Surface regressions each
also deliver all 60 frames. FFmpeg byte-buffer RGBX/YUV conversion remains a
separate known limitation; these changes do not repair that mode.

Instagram chooses its bundled ARM64 dav1d on the tested software fallback path.
That exposed a native gralloc/EGL problem: unaligned planar YUV strides could
not be imported, and CPU mapping used a one-row extent for a two-dimensional
R8 backing allocation. gbm_mesa now aligns planes for queried pre-Navi amdgpu
families, following the native amdgpu backend, and maps the same 4096-wide
backing layout used by allocation/import. The alignment adjustment leaves
other GPU families unchanged; other hardware has not been runtime-validated.

The new `minigbm_yuv_import_tests` reproduce the issue without ARM64 translation.
All **6/6** tests pass after repair, including CPU pixel readback, EGL import,
external-texture sampling and exact red output on flexible YUV and YV12 widths
720, 736, 768 and 1024. The original gralloc failed four import cases and the
aligned control's color check. Tests require a device graphics stack and are
not added to generic host presubmit.

Independent ARM64 decoder tests also exposed incorrect Berberis INS (element)
decoding. Its width test checked imm5 bit 2/3 without first excluding
smaller element widths. For example, `0x6e051cc0` (`mov v0.b[2],v6.b[3]`) was
translated as a 32-bit copy, overwriting adjacent bytes. The decoder now uses
the lowest set bit, supports all four widths and preserves untouched lanes.
A second overly broad match treated FMLA/FMLS 2D as 4S. This corrupted the
floating-point forward transform used to create checkasm coefficients; the
remaining inverse-transform failures were downstream of those incorrect inputs.
The 4S lowering and its cache audit now require bit 22 to be zero, leaving 2D
in the interpreter. Existing single-precision JIT optimizations and the
independent fork fix remain enabled.

An ARM64-only APK built from public dav1d sources reproduces the problem without
Instagram. Interpret-only matched reference pixels; old JIT failed 17/1176
checkasm cases. The corrected single-instruction scan passed 4,179 translated
opcodes with twelve random register states each. The temporary generated opcode
scan remains in local evidence, while two durable tests cover 1,920 combinations
of width, lane, alias and register mapping, plus reserved encodings. An additional regression checks that 2D FMLA/FMLS cannot enter the 4S lowering.
The INS/FMLA build passed **197/197**, and unmodified upstream dav1d ARM64
checkasm passed **1176/1176** with JIT enabled. Both scalar and NEON decoding
match reference pixels for 64x64 and three-frame 720x1280 samples; four-thread
720p and a cached 1176x646 Instagram stream also match. The public diagnostic
APK is under `tests/media-codec/dav1d/`; `trim_dsp=false` retains the C fallback.

The bundled Instagram decoder still produced corrupt raw YUV in an isolated
local diagnostic, while interpret-only matched the same reference frames.
A further opcode scan found `0x4e2440a6` (ADDHN2) incorrectly entering TBL:
the TBL mask omitted fixed bit 21. Requiring that bit to be zero preserves all
four TBL lengths and sends SADDL2/SSUBL2/ADDHN2/SUBHN2 to their correct interpreter
fallback. The new regression covers these neighbors, aliases and both cache
modes; the existing TBL test now covers all four table lengths with an independent
byte oracle. A temporary scan passed another **3,585** translated integer SIMD
opcodes with 32 random register states each and was removed from production tests.
The final durable Berberis suite passes **198/198**. After deployment, the exact
bundled decoder matches all three reference frame hashes with normal JIT enabled.
Private application libraries/media are confined to local diagnostic evidence.
The image corruption disappeared, but playback still stalled on xHE-AAC audio.
The product's global FFmpeg rank of zero selected an incomplete USAC decoder:
five stereo cache samples each consumed 106 packets with zero PCM output.
The audio rank is now 272 (native audio rank is 8), and the FFmpeg interface
enumerates supported AAC profiles without advertising xHE-AAC. Mono xHE-AAC
alone did not reproduce this limitation.

The native AAC alternative then exposed a separate integer-sanitizer abort in
`SpatialDecApplyPhase`: conjugating a sine coefficient of `INT_MIN` overflowed.
The two conjugated hybrid-band paths now saturate negative unity to the largest
positive Q31 value. Sanitizers remain enabled. `aac_spatial_phase_test` passes
on x86_64 and LoongArch64 across 64 phases, two channels and four bands.
All five stereo xHE-AAC samples and one mono sample now produce 106/106 PCM
buffers with EOS; ordinary AAC-LC passes through both platform and FFmpeg
decoders (88 packets, 87 PCM buffers after priming). The native AV1 Surface
regression still produces 60/60 frames. `tests/media-codec/AudioCodecProbe.java`
checks profile declaration, default selection and optional local PCM decoding.

After the final component deployment, Instagram Reels screenshots show
continuous motion and the player completes/repeats a 33-second clip. The
application AudioTrack is started, unmuted, stereo 44.1 kHz, on the output device.
The post-restart crash buffer is empty. Earlier clip initialization also emitted
an invalid 1x1 native-window warning; this observation remains in the local
report and is not treated as proof of another corrected graphics defect.

The framework library, FFmpeg service, swcodec APEX, gralloc library and
Berberis are installed as overlays. Backup and rollback state are under
`/var/lib/waydroid/deploy-backups/20260916-instagram-av1-fix`.
The subsequent AAC service/APEX and vendor-property overlay backup is
`/var/lib/waydroid/deploy-backups/20260917-aac-profile-phase`.
The rebuilt system/vendor images have not replaced the deployed image pair.
Application data and the independent Berberis fork fix are preserved. Builds
use `-j8`; source changes remain uncommitted. Detailed tests, component hashes,
application observations and rollback instructions are recorded locally in
`logs/instagram-av1-fix-20260916/REPORT.md`.

## 2026-09-16 Instagram guest-fork recovery

Instagram's `BloksDeviceGpuM` child was stranded in
`TranslationCache::AddAndLockForTranslation`. After the main process exited,
the child retained its Binder descriptor; ActivityManager kept the old process
in its dying state and cancelled subsequent launches with `refused to die`.
Killing only the diagnosed orphan immediately delivered the old process's
Binder death notification and restored startup.

GDB then confirmed the application uses `CloneGuestThread`'s non-CLONE_VM
syscall path, bypassing libc fork callbacks. That path now locks the translation
cache across clone, removes unfinished translation/wrapping/invalidation
records in the child, and preserves the parent's records and completed code.
The bionic path uses its null-entry clone wrapper so host PID/TID caches are
updated. The non-bionic LoongArch syscall fallback also uses the correct
child_tid-before-TLS argument order.

Four new device tests cover inherited lock contention, unfinished transactions,
host identity/guest TID writes, and failure cleanup. Both original reproductions
failed before the clone-path fix; the candidate passes **194/194** tests.
All microbenchmarks ran successfully; no controlled performance comparison is
claimed. Library/test/benchmark and system/vendor image builds passed with
`-j8`. The source changes remain local and uncommitted.

The library is deployed as an overlay, SHA-256
`ef6979c8acb50b898ff7dd3027e9d1e5456181e487fccd5639a9549f37234ea1`.
Backup: `/var/lib/waydroid/deploy-backups/20260916-instagram-fork-fix`.
Four application startup rounds completed without retaining the stuck GPU
child. A new GDB capture confirmed the same guest fork path reaches bionic
clone and its child subsequently exits. The final untraced cold launch took
17943 ms; the app stays foreground and the crash buffer is empty. Background
startup load and a temporary Waydroid container freeze invalidate timing
comparisons with the earlier diagnostic runs.

Only Waydroid restarted; the host boot ID remained
`9d147f15-2b8c-4097-9d2c-366bf83ea015`. Application data and shader caches
were preserved. The rebuilt image pair has not replaced the September 16
RenderScript images on the device. To roll back this library-only deployment,
stop the session/container, verify the exact backup's `overlay-state=absent`,
preserve and remove the new Berberis overlay, then restart as the desktop user.
The image library should again hash to
`8265edf0a3149872d02eef3256489f36b98b60165037a889104059ffa9c6033b`.
Local evidence, artifact hashes and limitations:
`logs/instagram-fork-fix-20260916/REPORT.md`.

## 2026-09-16 ARM64 RenderScript JNI packaged and deployed

The LoongArch64 product now explicitly selects `librs_jni.native_bridge` and
allows `system/lib64/arm64/librs_jni.so` in its artifact paths. The disabled
native `librs_jni` selection did not pull in that independently named guest
module. Earlier manual module builds populated the output directory and
`installed-files.txt`, but the system-image input file list excluded the library.
The earlier statement that the product already included it was incorrect.

`m -j8 librs_jni.native_bridge` and `m -j8 systemimage vendorimage` passed.
Extracting the actual rebuilt EROFS image confirms the library is AArch64 and
matches the previously validated overlay byte for byte (SHA-256
`a448293d3148b56c6923b8090717d6b4f537d76ad75b756f739c807a8ab2b218`).
All ten direct dependencies are present as AArch64 libraries. The unsupported
native JNI variant remains absent, and `config.disable_renderscript=1` remains
set. EROFS and read-only vendor filesystem checks passed. Berberis remains
`8265edf0a3149872d02eef3256489f36b98b60165037a889104059ffa9c6033b`.

| Rebuilt artifact | SHA-256 |
| --- | --- |
| system.img | `3f284813456f54c481238791a04fca1a61142d65d0da949ce953b6c5165cdc3b` |
| vendor.img | `2ce85d34dc1f5dec2079190cada7dd7c5b6b072b38fcab4024c48b25a5783d00` |

The rebuilt pair was subsequently **deployed on September 16** at the user's
request. Both images and the former RenderScript overlay were backed up in
`/var/lib/waydroid/deploy-backups/20260916-195740-renderscript-images`.
Fresh upper/work directories now contain no supplemental file overrides.
Compared with the September 14 system image, the only added regular file is
the ARM64 JNI library; the other modified regular files are build properties
and the license notice. No existing regular file was removed.

Android reaches `sys.boot_completed=1`, build incremental `1789559296`, with
ADB authenticated using the existing key. All **190/190** Berberis correctness
tests pass. The existing ARM64 `com.example.rsnb` test app displays
`RenderScript.create: PASS`, confirmed through both a screenshot and its UI
hierarchy. Its process maps the image's `librs_jni.so`, `libRSDriver.so` and
`libRSCpuRef.so`; no JNI library override remains. The test covers context
creation, finish and destruction, not all RenderScript compute or graphics APIs.

The post-test crash buffer is empty. Host boot ID remained
`f467261d-9c56-42ce-bc7d-d286758da9b3`; only Waydroid restarted. Both games
remain installed, user data and shader caches were preserved, and Helper's
host installation was not changed. The probe was stopped and the launcher
restored after verification. The source change remains local and uncommitted.

For rollback, stop the desktop session and container, preserve the current
image/overlay state, and restore both images and the upper/work directories
from the exact backup above, then start the desktop user's session. Do not
clear Android data. Packaging evidence is in
`logs/renderscript-packaging-20260916/`; deployment, runtime checks and the
PASS captures are in `logs/renderscript-deploy-20260916/`. See also the
[build guidance](BUILDING.md#development-branch-renderscript-note).

## 2026-09-14 full image pair deployed

Replaced both Waydroid images with the accepted September 13 build. Android
reached `sys.boot_completed=1`; all 190 Berberis correctness tests passed and
the post-boot crash buffer was empty. The latest JIT, ART, framework, launcher
and Genshin graphics profile now come directly from the images, with matching
hashes. Only the ARM64 RenderScript JNI supplement remains in the writable
overlay because it is not yet packaged in system.img. Game data, shader caches
and the host Helper installation were preserved. The user also confirmed the
Helper coordinate fix works before requesting this deployment.

The old image pair and complete overlay state are backed up in
`/var/lib/waydroid/deploy-backups/20260914-215615-full-images`.
See [artifacts, checks, limitations and rollback](FULL_IMAGES_20260914.md).

## 2026-09-13 stack and memory JIT optimization deployed

The new candidate removes obsolete branches to the next instruction at 16
memory-emitter sites and consumes cached SP directly for non-flag-setting
ADD/SUB immediates. It keeps the existing region-local register cache,
write-through state model and baseline runtime entry/exit code.

The device passed **190/190** correctness tests, including 1680 new SP-immediate
boundary executions. A same-harness, five-pair comparison across **23 scenarios**
passed the unchanged 3% latency/size gate: fixed-offset memory −25.58%, stack
reads −25.46%, stack writeback −17.88%, and SP region chains −6.35% in median
execution time. System/vendor images built successfully. These are synthetic
results; actual game-loading improvement remains unmeasured.

Library `8265edf0a3149872d02eef3256489f36b98b60165037a889104059ffa9c6033b`
is now deployed through the system library overlay. Waydroid restarted and booted
successfully; the host stayed in the same boot. All 190 tests passed again, and
the fresh game process mapped the exact new library with active JIT compilation,
Unity and IL2CPP loaded, and an empty crash buffer. The previous `c2183d42…`
library is retained in
`/var/lib/waydroid/deploy-backups/20260913-195656-jit-stack-memory`.
Images, game data and shader caches were not changed. Larger SP-residency and
runtime-exit experiments failed performance checks and were withdrawn. See
[changes, exact artifacts, deployment and rollback](BERBERIS_STACK_MEMORY.md).

## 2026-09-13 development source committed

The previously uncommitted runtime work is now recorded on each owning
repository's local `loongarch64/lineage-23.2` branch:

| Repository | Commit | Change |
| --- | --- | --- |
| Berberis | `bae6ed23` | Empty JNI arguments and mixed callback coverage |
| Berberis | `bf312782` | UCVTF fixed-point conversion with 64 fractional bits |
| Berberis | `7c40567f` | Explicit guest linker execution through the ARM64 runner |
| Berberis | `e7781782` | Runtime diagnostics enabled only by profiling |
| Berberis | `aad4bb61` | Five batches of game-loading JIT optimization and tests |
| Mesa | `3bbcc85` | Package-scoped Genshin GPU identity profile |

All ten Berberis working files retain their pre-commit content. The six files
in the fifth-batch candidate snapshot match the committed source byte for byte,
preserving the existing 189/189 runtime, 20/20 assembler and image-build evidence.
The Mesa file matches the deployed profile hash. This source checkpoint does
not rebuild or deploy the device, change release tags, or establish additional
gameplay or host-reset validation. These new commits have not been pushed as
part of this checkpoint; the helper branch was published earlier.

## 2026-09-13 Waydroid Helper keyboard mapping validated

The LoongArch64 helper fork is published on `factfinding/waydroid-helper`, branch
`loongarch64/main`, at `030d85e7d417a86818cba986d12cabd55bd83335`.
It supports the host architecture and explicit ADB targets with instance-owned
scrcpy cleanup. The device passes 110 Python tests, 11 subtests and three Meson
validation checks; the user confirms keyboard mapping works in Genshin.
The current mapper remains running. An earlier automatic host restart during
the trial has no established cause. See [installation and validation details](WAYDROID_HELPER.md).

## 2026-09-13 Genshin GPU identity profile deployed

The radeonsi drirc profile now returns ARM / Mali-G77MC9 only for the China
package `com.miHoYo.Yuanshen`. Five native Android EGL process controls verify
the package-name scope and unchanged versions, extensions and limits. The
restarted real game stores the new identity and initial instancing sizes
32/32, replacing its earlier 32/2 settings. The original strategy byte and
program-binary permission remain enabled.

Only `/vendor/etc/drirc` in the writable vendor overlay was replaced, with a
complete backup and restored read-only mount. The host and Waydroid stayed
in the same boot/session; only Genshin restarted. No cache data or JIT setting
was changed manually. The game may recompile entries automatically because
its source keys and graphics fingerprint can change. Stable gameplay now shows
visible water and reflected sky. A fresh trace and immediate inspection read
all 90 program objects identified by uniform events; water program 284 has a
32-element instance interface.
Three stable reads confirm its ten sampler locations 398–407 map to units 0–9
in both CPU uniform storage and fragment `SamplerUnits`, without manual sampler
correction. Fifth-batch JIT remains enabled. This validates the current scene;
the earlier host-reset cause remains a separate question. See
[the deployed profile and rollback](GENSHIN_GPU_PROFILE.md).

## 2026-09-13 renderer identity explains an instancing-path distinction

A native x86_64 EGL control in LDPlayer changes only its process-name
configuration and receives Adreno 750 under an ordinary name, Mali-G77MC9
under Genshin's name. The running game's capability object stores Mali and
uses initial instancing settings 32/32; la64 stores 32/2. LDPlayer water
program 1247 has a single initial key-0 owner and a reflected 32-element
instance interface. The current la64 water programs 276/278 both expose two
elements, with identical uniform interfaces. A subsequent bounded scan and
repeat reads establish their shared guest owner: key 0 maps to 276, selected
key 2 to 278, and key 32 to 277. Its vertex template is byte-identical to
the LDPlayer owner's template.

Original ARM64 reflection code computes that extent from parsed uniform-name
indices. The instancing metadata constructor clears its dynamic flag unless
the extent is exactly two, alongside other layout conditions. This identifies
a concrete route by which the graphics-identity difference avoids the faulty
reuse path. The current failure involves a same-size key-2 variant; expansion
is unnecessary. Original ARM64 fragments pass 10,384 independent Unicorn
checks. The owner snapshot does not trace historical calls or validate all
Berberis execution. No persistent fix is deployed;
the earlier temporary sampler correction and fifth-batch JIT remain in place.
See [the instancing-path audit](GENSHIN_INSTANCING_PATH.md).

## 2026-09-13 LDPlayer game control captures separate sampler locations and units

The same ARM64 Genshin version renders visible water through Houdini in
LDPlayer. Its live game capability snapshot has version enum 4 and strategy
byte 1, matching la64. Native GLES tracing captures 68 sampler assignments
across six water-interface programs: all use consecutive units, with zero
location-as-value assignments. Paired system/vendor arguments and query
returns agree; the startup trace reports no dropped events.

This establishes an actual initialization difference beyond independent shader
probes. It does not yet identify the guest branch or explain why corresponding
variants follow different initialization paths. Shader interfaces and graphics
settings also differ, so this is not a matched-variant control. See
[the emulator comparison](GENSHIN_EMULATOR_COMPARISON.md) for measured values,
probe validation, the isolated Houdini startup crash and remaining limits.

## 2026-09-13 water restored in a reversible sampler-binding control

In the running Genshin swimming scene, water program 278 assigned its ten
samplers to empty units 128–137. Reference program 276 has the same 99-uniform
interface and uses units 0–9, where the textures are actually bound. Correcting
only those sampler values through Mesa restored the water; rolling back made
it disappear; reapplying restored it again. CPU uniform storage and fragment
`SamplerUnits` agree in each state. The game is left with the corrected mapping.

This is a temporary change to the current program, not a persistent deployed
fix. Fifth-batch JIT remains enabled with the same library hash. The host and
game remained in the same boot/process through the final 13:06 check; debugger
and probes are gone. This establishes the current water symptom's dependence
on sampler bindings, without determining the earlier host-reset cause. See
[the controlled repair](GENSHIN_WATER_SAMPLER_REPAIR.md) for exact mapping,
reversal evidence, coverage limits and remaining work.

## 2026-09-13 12:29 gameplay reached after data clearing; water still missing

The user confirms successful entry into gameplay after clearing Genshin data,
with the water surface still missing. A read-only screenshot confirms gameplay;
host boot ID and game PID remain the same as the 09:28 check, about three hours
earlier. The game still maps fifth-batch Berberis and reports mode 1, 347,752 JIT
successes and 118,222 gear-ups. No device setting or game state was changed by
the agent during this check.

This advances the previous download-only observation. Data clearing has not
fixed the water symptom, while the host has remained in the same boot through
the download-to-gameplay interval. It does not prove permanent reset resolution
or independent root causes. Continue tracking the symptoms separately; the
previous water sampler-binding evidence remains a candidate requiring a fresh
program/sampler mapping and a controlled visual correction in this process.
Evidence: outer-workspace `logs/genshin-cleared-data-20260913/`,
`runtime-in-world.json` and `observation-in-world.json`.

## 2026-09-13 09:28 user cleared Genshin data; no reset reported so far

After JIT restoration, the user reports clearing Genshin's application data and
no further host reset so far. Read-only checks find the same host boot as the
restoration and Genshin host PID 15306 / Android PID 5072 using fifth-batch
Berberis, mode 1, 130,945 JIT successes and 43,395 gear-ups. The screenshot shows
a full resource download at 342.45 / 48,552.73 MB (0.71%). This differs from the
earlier 174.51 MB update download and resource-verification failure paths.

The observation prioritizes application data/cache and the execution paths they
select, but does not isolate a shader cache, prove data corruption, or identify
the mechanism of a whole-host reset. At that check, download completion,
in-world stability and water rendering were unverified. The agent performed only read-only
checks; the user's exact clearing operation/time was not captured. Evidence:
`logs/genshin-cleared-data-20260913/` in the outer workspace.

## 2026-09-13 09:15 Berberis JIT restored on user request

The interpreter control has ended. Only `berberis.mode` was restored to
`lite-translate-or-interpret` in the three Waydroid configuration/property files;
ART retains `dalvik.vm.usejit=true`. The fifth-batch library remains
`c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`.
The preceding configuration is backed up at
`/var/lib/waydroid/deploy-backups/20260913-091517-restore-berberis-jit/`.

Waydroid and the noctis graphical session were restarted, and Android reached
`sys.boot_completed=1`. A normal WaterProbe launch (automatic matrix disabled)
verified mode 1, 34,616 JIT successes and 15,656 gear-ups in host PID 13050 /
Android PID 2949. The verifier checks both the installed and mapped library
content before reading known-build offsets. No Genshin launch or host-reset
reproduction was performed during restoration. This is configuration validation,
not a fix for the rendering or whole-host reset problems. Evidence is in
`logs/genshin-restore-jit-20260913/` in the outer workspace.

## 2026-09-13 earlier Berberis JIT-disabled host-reset control

At the user's request, the September 12 23:55 configuration change sets
`berberis.mode=interpret-only`; native ART remains enabled for this control.
The fifth-batch library hash is unchanged. Android booted and Genshin launched
once as host PID 6867 / Android PID 3804 in boot `ebd8ae9f…`. Direct process
checks through 00:12:52 verify mode 0, zero JIT successes and zero gear-ups.
The host has not rebooted during approximately 15 minutes of this run, but the
app remains on a white startup surface with repeated `NullReferenceException`
in `GameManager.Update` and `LateUpdate`. It has not reached the earlier
resource-download failure stage, so this does not establish whether JIT caused
the host reset. The configuration remains in place. See
[the interpreter control](GENSHIN_NO_JIT_RESET_CONTROL.md)
for configuration backups, live evidence and observation status.

## 2026-09-12 Genshin-associated host resets under investigation

Seven unexpected whole-host resets are confirmed by boot/journal boundaries.
The fifth was covered by an external reconnecting collector: Genshin's last
identifiable stage was resource verification of 1,684 files, about 94 seconds
after its main process started. The final sensor sample shows CPU 44°C,
GPU 54°C and 7.237 GiB available RAM. Neither direct dmesg nor the saved journal
contains a panic, GPU timeout or OOM identifying the cause. These observations
do not establish a hardware fault, JIT regression or connection to missing water.

Following that reset, `kernel.panic` was temporarily changed from 30 to 0 in
boot `1415cf78cb35488080c7d5f8143d341f` so a possible panic can remain onscreen;
the existing `drm.panic_screen=kmsg` setting was unchanged. This is diagnostic
preparation, not a fix, and may require manual restart after a panic. No
persistent configuration, product library or optimization setting was changed.
The next boot restores the configured timeout; immediate rollback is
`ssh la64-root 'sysctl -w kernel.panic=30'`.
See [the host reset investigation](GENSHIN_HOST_RESETS.md) for coverage gaps,
clock offsets, exact evidence and remaining uncertainty.

## 2026-09-12 full optimization restoration rechecked

The user requested restoration of optimizations disabled during the Genshin
investigation. Read-only device checks confirmed that the September 11
restoration remains active: both the overlay and mounted Berberis library have
the complete fifth-batch SHA-256
`c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`.
Live properties and all three persistent Waydroid configuration files agree on
`berberis.mode=lite-translate-or-interpret` and `dalvik.vm.usejit=true`.
No nonempty app wrapper properties or additional Berberis threshold overrides
were present. The audited host service/LXC configuration had no diagnostic
environment overrides. The requested configuration was already in effect, so
no redeployment, configuration rewrite or restart was needed.

Android boot completion and core processes were checked. Genshin started during
verification (host PID 6739 / Android PID 4087). Its mapped library hash/inode
matched the fifth batch; a bounded read-only runtime check found translation
mode 1, 15,200 JIT successes and 3,679 gear-ups. No `BERBERIS_MODE` environment
override was present. ART's enabling property is true; this check does not
claim new ART-generated executable code or a visual rendering fix. Evidence:
`logs/genshin-optimization-restoration-20260912/verified-state.json` and
`game-jit.json` in the outer workspace. The water sampler-binding investigation is recorded in
[the variant-binding report](GENSHIN_SHADER_VARIANT_BINDINGS.md).

## 2026-09-11 water-related GLES control

After the user identified possible missing water in OpenGL Genshin, a separate
ARM64/IL2CPP water probe tested alpha blending, sampled depth, GrabPass copy and
refraction, planar reflection with three render-target formats, and ordinary
versus instanced draws. Windows/D3D11 and la64/GLES3 completed all twelve cases;
all camera/screen captures were reviewed without reproducing missing water.
Fifteen selected GLES entry points were present. All 797 sampled GL diagnostic
events had zero GL errors and complete FBOs; the final Unity log had no errors.
Device JIT remains enabled and was verified in the probe process. These results
do not rule out game-specific shader, resource, JIT or driver defects. See the
[water test report](UNITY_WATER_PROBE.md) for artifacts and limitations.

## 2026-09-11 JIT restored; standalone Terrain probe

The interpreter-only Genshin control was too slow and reported a network failure
before a useful scene comparison. This run does **not** rule out JIT-related
rendering defects, nor establish that the network error was caused by a timeout.
The device has been restored to fifth-batch Berberis
`c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`,
`berberis.mode=lite-translate-or-interpret`, and `dalvik.vm.usejit=true`.
Android boot completion and validated Ethernet connectivity were checked;
Genshin's process maps the restored library. In-game login success remains unverified.
Previous library/configuration backup:
`/var/lib/waydroid/deploy-backups/20260911-194856-genshin-restore-jit/`.

A standalone Unity Terrain/ordinary-Mesh matrix is under
`tests/unity-terrain/`. It avoids networking and game assets, records CPU data
checks and fixed-view screenshots, and supports separate GLES3/Vulkan ARM64
IL2CPP builds. All three builds succeeded; Windows/D3D11 and la64/GLES3 each
completed ten cases with passing CPU checks and visually continuous surfaces
in all camera and screen captures. Vulkan-only initialization could not load
its driver, and the per-app interpreter wrapper failed before entering Unity;
neither is a valid rendered comparison. See the
[Terrain probe report](UNITY_TERRAIN_PROBE.md) for evidence and limitations.
The initial
2022.3.72f1 Editor recommendation was unsuitable for the available Personal
license (Extended LTS restriction); 2022.3.62f3 was installed and used successfully.
Restoration and build logs: `logs/genshin-restore-jit-20260911/`.

## 2026-09-09 Genshin interpreter-only control

At the user's request, both Berberis and ART JIT compilation were disabled at
22:16 (UTC+8): `berberis.mode=interpret-only`, `dalvik.vm.usejit=false`.
Waydroid configuration and generated property files were backed up under
`/var/lib/waydroid/deploy-backups/20260909-221655-genshin-no-jit-config/`.
These settings survive Waydroid restarts until restored. The installed library
remains `e76c0a2851c50314a7ac0779960949e43daf2173290db9f4a7784a8f2ab72c5b`.

Android booted and Genshin PID 2387 (host 9596) launched. Matching-Build-ID
symbols allow direct process verification: translation mode 0 (interpret-only),
JIT successes 0 and gear-ups 0 on two checks. ART has no executable jit-cache
mapping; its profiling-only cache/thread pool remains because profiling is
separate from compilation. AOT code, bridge stubs and GPU shader compilation
remain active. The captured crash buffer is empty; scene comparison is pending.
Evidence and detailed limitations: `logs/genshin-textures-20260909/REPORT.md`.

## 2026-09-09 Genshin terrain regression investigation

Fifth- and second-batch screenshots show extensive missing terrain with
characters/UI and some rocks/trees visible. The user also reports visual problems
on the third batch; its captured viewpoint differs. Each control's game-process
library hash/inode was verified in the scene. No known-good version is established.

At 12:45 (UTC+8), the ongoing comparison skipped the first batch and switched to
the **library preceding all five recent game-loading optimization batches**:
`e76c0a2851c50314a7ac0779960949e43daf2173290db9f4a7784a8f2ab72c5b`.
This still includes the earlier JIT and historical optimizations. Its visual
result is pending; installation alone does not establish a fix. Android boot
completed; Genshin PID 1596 (host 22951) maps the verified hash/inode. Launch
returned `Status: ok` and the captured crash buffer is empty.
Preserved libraries:

- Fifth batch: `/var/lib/waydroid/deploy-backups/20260909-122747-genshin-third-round-control/libberberis_arm64.so`.
- Third batch: `/var/lib/waydroid/deploy-backups/20260909-123702-genshin-second-round-control/libberberis_arm64.so`.
- Second batch: `/var/lib/waydroid/deploy-backups/20260909-124559-genshin-preoptimization-control/libberberis_arm64.so`.

No game data, images or graphics settings were changed. Evidence and control
scripts: `logs/genshin-textures-20260909/`.

## 2026-09-08 game-loading SIMD fallback deployment

The fifth batch adds seven observed fallback families: SHL/USHR 2S/4S,
CMTST 2S/4S, FMAX 4S, BIC 8B/16B, BSL 8B, and UMOV W from any S lane.
New vector writes normalize inactive lanes before updating ThreadState and
register caches. Unity/IL2CPP opcode evidence is recorded separately from
AkSoundEngine audio-thread evidence; no exact main-thread speedup is inferred
from shared opcode-bucket counts. See [scope and validation](BERBERIS_SIMD_FALLBACKS.md).

- Deployed on user request at 21:57 (UTC+8); Android reached `sys.boot_completed=1`.
- Device correctness: 189/189; host assembler tests: 20/20.
- Final translator module build: 01:25; system/vendor image build: 01:33.
  The subsequent benchmark CLI correction's module/image targets passed in 01:20.
- Fourteen original JIT scenarios pass the unchanged 3% latency/size gate in
  five A/B pairs, with unchanged generated sizes and matching checksums.
- Seven new scenarios pass five paired JIT/interpreter comparisons with matching
  checksums. These repeated-instruction gains are not game-loading speedups.
- Candidate SHA-256: `c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`.
- Pre-deployment benchmark affinities were restored and verified. Deployment restarted Waydroid.
- Previous-library backup: `/var/lib/waydroid/deploy-backups/20260908-215745-simd-fallback/libberberis_arm64.so`.
- Game PID 1831 (host 33580) maps the hash/inode-verified new library and Unity;
  the captured crash buffer is empty. IL2CPP was not yet mapped at the last check,
  so full engine initialization and match loading remain unvalidated. Sampling has not started.

## 2026-09-08 cache initialization and width deployment

The fourth optimization batch adds single-instruction TBI/32-bit normalization, direct cached
sources for zero-shift non-flag-setting W arithmetic/logic, and control-flow-aware
GPR initialization. Write-first loads are omitted, later-block loads are delayed,
and loop-crossed loads are hoisted before backedge targets. ThreadState writes
remain immediate. Regions with active SIMD caching retain eager GPR initialization
after broader variants caused a repeatable mixed-SIMD regression.
See [validation and scope details](BERBERIS_DEMAND_WIDTH.md).

- Deployed on user request at 20:47 (UTC+8); Android boot completed and the
  noctis graphical session and LXC container are running.
- Device suite: 181/181, including a real memory-fault recovery test, pending signals,
  nested backedges, and W aliases; host assembler suite: 19/19.
- Final system/vendor image build passed in 01:30.
- Five A/B pairs for each of fourteen microbenchmarks pass the 3% latency/size gate.
  W arithmetic/logic latency -58.71%; memory scenarios -7.16% to -8.56%; mixed SIMD
  -0.17%. Cache-initialization cases change by less than 1%, not a clear speedup.
- Deployed SHA-256: `5f540b72a5571dada88b6caff75f275a2ee9ca1f2f1a249d43d05e37c5b0dc95`.
- Previous-library backup: `/var/lib/waydroid/deploy-backups/20260908-204709-demand-width/libberberis_arm64.so`.
- Game PID 1957 (host 16888) maps the verified new library, Unity and IL2CPP;
  the captured post-launch crash buffer is empty.
- Game affinities restored. First full loading capture: 228.10 s versus the prior
  235.83 s (3.28% shorter), main CPU 192.37 versus 199.21 s. Reads decreased from
  378.88 to 129.21 MiB, so this is not a controlled code speedup.
- GPR cache-initialization sampled share 20.54% → 17.16%; SLLI/SRLI share
  7.28% → 2.18%. ThreadState total remains 35.45%; interpreter hotspots persist.
  44,230 samples, lost=0, matching library hash and empty captured crash buffer.

## 2026-09-08 SP caching and logical-source deployment

A new candidate caches hot SP values in the existing seven GPR slots, keeps all
SP writes immediately visible in ThreadState, combines cached memory bases with
address offsets, and directly consumes cached sources for zero-shift 64-bit
AND/ORR/EOR. It was deployed on user request at 12:41 (UTC+8). Android boot
and a game-launch smoke check passed. See [SP/logical validation and
rollback](BERBERIS_SP_LOGICAL.md).

- Device tests: 175/175; system/vendor build passed in 01:32.
- Eleven microbenchmark scenarios pass the 3% latency/size gate. Three paired
  runs show stack-writeback latency -48.46%, stack reads -3.81%, and ordinary
  immediate memory -3.75%; logical code size -48.48% with unchanged latency.
- An initial +3.30% condition-select control result prompted ten fixed additional
  pairs; all thirteen pairs pooled show -0.20% median latency. No samples omitted.
- Deployed SHA-256: `e80a43d5dbc6996b3f643a806c1f0d6d5320bd52e27a3760ff37b97c81460cf8`.
- Previous-library backup: `/var/lib/waydroid/deploy-backups/20260908-124133-sp-logical/libberberis_arm64.so`.
- Android reached `sys.boot_completed=1`; game PID 1563 mapped the new library,
  Unity and IL2CPP, with an empty captured crash buffer.
- Game affinities restored and verified. These synthetic results do not quantify
  complete match-loading improvement.
- First post-deployment full loading window: 215.73 s versus 253.69 s (14.96%
  shorter), with main CPU time 185.91 s versus 216.37 s. Storage reads were
  much lower (86.31 versus 351.14 MiB), so this is not a controlled code speedup.
  See the linked report for SP/cache hotspots and attribution limits.
- Evening repeat with the same library: 235.83 s, main CPU 199.21 s, storage
  reads 378.88 MiB. This is 7.04% shorter than the second-batch window; it also
  shows why the earlier 215.73 s result should not be treated as a fixed speedup.
  SP/MOVE hotspot changes persist; GPR entry reloads now account for 20.54%.

## 2026-09-07 conditions and direct-source deployment

This earlier development-device library adds selective NZCV condition evaluation,
zero-shift removal, and direct cached sources for a narrow 64-bit ADD/SUB path.
It also fixes a shifted 32-bit SUBS carry boundary exposed by expanded tests.
ThreadState write-through and cache-register allocation rules are preserved.
See [validation and rollback details](BERBERIS_CONDITIONS.md).

- Device suite: 171/171; host assembler suite: 18/18.
- Final system/vendor image build passed in 01:28; deployment replaced only the library.
- All eight microbenchmarks passed the 3% regression gate with the game separated
  from the benchmark's physical core; original game affinities were restored.
- Deployed SHA-256: `723ad863b1d25ac5fc84a4d07e2dcf6b7e3e5ec493ee23c6419aa81a7e11afa9`.
- Previous-library backup: `/var/lib/waydroid/deploy-backups/20260907-230437-conditions/libberberis_arm64.so`.
- Android reached `sys.boot_completed=1`; 金铲铲之战 loaded the new library, Unity,
  and IL2CPP with an empty crash buffer in the post-launch smoke check.
- First user-controlled complete loading capture on 2026-09-08: 253.69 s versus
  the previous complete 273.38 s; main-thread CPU time 216.37 s versus 235.63 s.
  The 7.20% shorter window is a single cross-day observation, not a controlled
  optimization speedup. See the linked report for remaining hotspots and limitations.

## 2026-09-07 immediate-lowering deployment

This earlier deployment used the shorter-constant and immediate-address
Lite JIT candidate described in
[the immediate-lowering validation report](BERBERIS_SMALL_IMMEDIATES.md).
Device correctness passed 167/167 and host assembler tests passed 17/17.
After library-only deployment, Android reached `sys.boot_completed=1` and
金铲铲之战 loaded the new library, Unity, and IL2CPP with an empty crash buffer.
The user clarified that the baseline loading sample was incomplete and the
post-deployment sample complete; their window durations are not comparable.
The user reports somewhat faster loading, without a quantified speedup.
Main-thread constant-building instruction locations fell from 13.06% to
6.44%; see the linked report for workload and profiling limitations. The small-immediates system/vendor image build subsequently passed (34:16).

- Deployed SHA-256: `e222f893c44173802b100c3f56835e1fa120e279cb28dae2bb0328cc0b489807`.
- Previous-library backup: `/var/lib/waydroid/deploy-backups/20260907-221330-small-immediates/libberberis_arm64.so`.
- ThreadState write-through and register allocation rules remain unchanged.

## Validated platform

- LineageOS 23.2 / Android 16 runs under Waydroid on an AOSC OS LoongArch64 host.
- The container reaches `sys.boot_completed=1` with LXC 7.0.0 and seccomp enabled.
- Native LoongArch64 ART, bionic, system services, Chromium WebView, audio, networking, and Mesa GPU acceleration have runtime validation.
- The ABI list prefers `arm64-v8a` for Native Bridge applications while retaining native `loongarch64` and `lp64d` support.
- ARM64 application libraries are loaded through `libberberis_arm64.so`.
- Legacy RenderScript calls made by ARM64 applications use the ARM64
  `librs_jni.so`, `libRSDriver.so`, and `libRSCpuRef.so` stack through
  Berberis. Native LoongArch64 RenderScript remains disabled because libbcc
  has no LoongArch64 backend.

## ARM64 translation pipeline

The LoongArch64 Berberis port is no longer interpreter-only. The current development pipeline is:

```text
ARM64 region
  -> LoongArch64 Lite Translator
  -> generated LoongArch64 machine code
  -> interpreter fallback for unsupported instructions or regions
```

The Lite JIT covers a growing set of integer, branch, memory, atomic, floating-point, and NEON operations. Unsupported paths still enter `InterpretBatch()`, so translation coverage and generated-code quality remain the main CPU-performance limits.

## Write-through GPR cache

The validated development build enables region-local guest GPR mapping:

- Up to seven repeatedly read ARM64 GPRs are cached in LoongArch64 `$s0`-`$s6`.
- Commit `5f0c728d` obtains exact reads and writes through the real translator
  decoder, excluding destination-only registers and ranking write-heavy values
  below source-heavy values.
- Reads use the cached host register.
- Every guest-register write is immediately stored to `ThreadState` and then reflected in the cache.
- `$s8`/`r31` remains the `ThreadState` base. `r21` and `$tp` remain non-allocatable.

Immediate write-through is a correctness requirement, not merely a conservative setting. Generated code may be left through signal delivery, memory-fault recovery, helper calls, or other exceptional exits that bypass a normal region-end flush. A previous deferred-writeback design correlated with application crashes; the isolated write-through implementation has not reproduced them.

## Write-through SIMD cache

Commit `4f457388` added a conservative region-local cache for repeatedly read ARM64 SIMD registers. Commit `3bce713e` extends it to a narrow audited class of full-width floating-point destinations:

- Up to five repeatedly read guest vector registers are cached in LoongArch LSX `$vr4`-`$vr8`.
- Full-width `FMUL`, `FDIV`, `FADD`, `FSUB`, `FMLA`, and `FMLS` destinations may be cached because their audited `StoreV()` lowering writes through before updating the LSX copy.
- Partial writes, lane writes, structure-load destinations, and unaudited writers remain excluded.
- Guest vector writes remain immediately visible in `ThreadState`; there is no deferred SIMD writeback.
- Each directly dispatched target region reloads its own selected vector cache at entry.

In the device regression sequence, five repeated `FMUL V.4S` instructions reduced source-vector loads from ten to two while preserving the same result. This initial implementation deliberately favors correctness over aggressive cache coverage.

## CFI-safe native callback closures

ARM64 applications can pass guest callbacks to native host libraries. Berberis uses libffi closures to adapt these callbacks to the LoongArch64 host ABI. The earlier anonymous executable closure mapping could randomly occupy a 256 KiB CFI shadow slot owned by an unrelated CFI-enabled DSO. A host indirect call would then ask that unrelated DSO to validate the closure and could terminate with `SIGILL`.

Commit `e401483b` replaces anonymous executable closure mappings with a 256 KiB static trampoline table inside `libberberis_arm64.so`:

- 16,384 fixed 16-byte LoongArch64 trampoline entries are part of the library's registered executable segment.
- A dispatcher maps each entry to a process-lifetime `ffi_closure` without clobbering callback argument registers.
- Slot allocation and publication are atomic; concurrent wrapper construction is covered by tests.
- Pool exhaustion is fatal and explicit. There is no fallback to an unsafe anonymous executable mapping.

AAudio's `AAUDIO_ERROR_ILLEGAL_ARGUMENT` (`-898`) observed during rapid uninstall/reinstall stress was diagnosed separately. Audioserver reported that the newly assigned application UID had not yet reached `NativePermissionController`; those attempts never created a stream or entered a callback and are not CFI failures.

## Verification on 2026-08-16

- Built `libberberis_arm64.so` from `e401483b` on `loongarch64/lineage-23.2`; it includes the validated write-through GPR cache from `d0cfbe2` and the static closure trampoline fix.
- Passed `115/115` `LoongArch64RuntimeLibraryTest` tests on the LoongArch64 Waydroid device.
- Deployed library SHA-256: `d5c15d3d11eef579d4251b480303448d30af5563b66fd5e3b71011576d76ffa0`.
- Waydroid reached `sys.boot_completed=1`; the Android crash buffer was empty after deployment.
- Three consecutive AAudio mode-5 runs completed about 5,000 callbacks each with no CFI, `SIGILL`, or fatal signal. A concurrent stress mode containing 1,600 stream-open attempts also completed.
- A cold launch of `com.kurogame.mingchao` remained alive past 60 seconds. The LXC and `system_server` PIDs remained unchanged, and the process had no anonymous `berberis-ffi-closure` executable mapping.

## Verification on 2026-08-17

- Extended linear regions through conditional-branch fallthrough in `dbd1c9c9`; taken branches remain translation-cache side exits.
- Added the source-only SIMD cache in `4f457388` and independently verified the new LoongArch `VOR.V` encoding. Structure-load destinations, including `LD1R`, have explicit stale-cache regression coverage.
- Lowered ARM64 vector AND/OR/EOR directly to LSX in `54e4923e`, including the previously interpreted 64-bit AND/OR forms. Repeated logical sources now use the region SIMD cache instead of four scalar `ThreadState` loads per instruction.
- Passed `125/125` `LoongArch64RuntimeLibraryTest` tests on the LoongArch64 device.
- Deployed library SHA-256: `b429e9be5834bbe8dc5021cbb6593d41af2b22c839d14702bf3ba3bff59f129e`.
- Waydroid reached `sys.boot_completed=1`; Bilibili completed a cold launch, remained alive, and the Android crash buffer stayed empty.
- Deployment backup: `/var/lib/waydroid/deploy-backups/20260818-120201-lsx-logical`.

## Verification on 2026-08-18

- Commit `b9b6b447` routes `DUP V.16B`, `DUP V.2D`, zero/one `MOVI`, and
  `FABS V.4S` through LSX and the common cache-coherent vector helpers.
- `DUP V.16B` no longer uses a mask, 64-bit multiply, and two scalar stores;
  it lowers to an LSX byte broadcast plus the normal vector write-through.
- The SIMD liveness pass now recognizes `FABS V.4S` as unary instead of
  treating opcode bits as a phantom `Rm` source. Five repeated FABS operations
  therefore load their shared guest source once with register mapping enabled,
  versus five times without mapping.
- LLVM 21 independently verified the new `VREPLGR2VR.B` and
  `VREPLGR2VR.D` encodings. Host assembler tests and all `126/126`
  LoongArch64 runtime tests passed on the device.
- Deployed library SHA-256:
  `5aac25f6f7cc0ba546fe871e537f1f8b07d8856cf4cff1c8e84bcd314fa65519`.
- Waydroid reached `sys.boot_completed=1`; the graphical session and core
  Android processes remained running, and the crash buffer was empty.
- Deployment backup:
  `/var/lib/waydroid/deploy-backups/20260818-121818-lsx-broadcast-fabs`.
- Commit `fdde08fa` replaces scalar lane accesses for ARM64 `UZP1`, `UZP2`,
  `ZIP1`, `ZIP2`, and `TRN1` 4S forms with cache-aware LSX picks and
  interleaves. Source/destination alias cases match the interpreter.
- Five repeated ZIP operations reduce source-vector loads from ten to two with
  SIMD register mapping enabled. The expanded device suite passes `127/127`.
- Current deployed library SHA-256:
  `b7878c4162b72cf9b6ea13e5523e993840181ab7619c138aaeecf49e55232929`.
- Current deployment backup:
  `/var/lib/waydroid/deploy-backups/20260818-123045-lsx-permute`.
- Commit `41264228` replaces scalar chunk assembly for both ARM64 EXT forms
  with cache-aware LSX byte shifts. The 64-bit form explicitly concatenates
  only the low source lanes and clears the destination's upper half.
- All legal 64- and 128-bit offsets, destination/source aliasing, and repeated
  source caching pass differential tests. Five repeated EXT operations reduce
  source-vector loads from ten to two; the full device suite passes `128/128`.
- Current deployed library SHA-256:
  `2233be9a7dd0a9575ff2b13772c11176579271f0d3f41a83fc1faeaf25347899`.
- Current deployment backup:
  `/var/lib/waydroid/deploy-backups/20260818-125944-lsx-ext`.
- Commit `6c0eafa7` replaces scalar lane extraction for ARM64 `FADDP V.2S`
  with a cache-aware LSX interleave, split, and vector add sequence. Inactive
  lanes are zeroed before addition so they cannot raise extra FP exceptions.
- NaN, signed-zero, destination alias, and repeated-source tests match the
  interpreter. Five repeated FADDP operations reduce source-vector loads from
  ten to two; the full device suite passes `129/129`.
- Current deployed library SHA-256:
  `c77248a50a5ff5f25275ed4148243b000dec750aaf8a0041eb0ad7cbdd3b5240`.
- Current deployment backup:
  `/var/lib/waydroid/deploy-backups/20260818-131325-lsx-faddp`.

## Verification on 2026-08-21

- Commit `c83b7649` adds repeatable LoongArch64 JIT microbenchmarks for GPR
  caching, SIMD caching, conditional fallthrough, and mixed arithmetic.
- The integration runner executes the full correctness suite, emits JSONL
  latency/code-size data, collects hardware counters with `perf stat`, and can
  fail an A/B run automatically when latency or code size regresses by 3%.
- Commit `5f0c728d` replaces raw ARM64 instruction-field counting with exact
  GPR read/write collection through the existing translator decoder. Guest
  writes remain immediately visible in `ThreadState`.
- Against the `c83b7649` baseline, GPR latency fell 17.08% and generated size
  fell 16.41%; conditional-fallthrough latency fell 12.54% and size fell
  12.81%. The other two scenarios also remained within the regression gate.
- All `145/145` device runtime tests passed. Deployed library SHA-256:
  `be8140d98ce65302d5aef7712349daea699762555e49dbeb255c95b26f23cc94`.
- Waydroid reached `sys.boot_completed=1`; `zygote64`, `surfaceflinger`, and
  `system_server` are running and the Android crash buffer is empty.
- Deployment backup:
  `/var/lib/waydroid/deploy-backups/20260821-222249-berberis-source-aware-gpr`.

## Verification on 2026-08-23

- Commit `3bce713e` moves all guest-memory fault recovery exits after the normal
  region body and removes redundant hot-path branches from structure memory
  operations. Nearby exits update the guest PC relative to `$s7` with one
  `ADDI.D` instead of materializing a full address.
- Added immediate and register post-index lowering for 32-bit `LD1/ST1` lane
  forms, including the hot Unity `ST1 {Vt.S}[lane], [Xn], #4` pattern.
- Audited full-width floating-point accumulators can now remain in the
  write-through SIMD cache. A repeated-FMLA regression reduces vector loads
  from 15 to three and verifies the final `ThreadState` value.
- The gear-up threshold is runtime-selectable through
  `berberis.gear_switch_threshold`; the compiled default remains 1000.
- All `149/149` device runtime tests pass. The four automated microbenchmarks
  pass the 3% regression gate; generated size fell by 0.78% to 2.44% against
  the previous two-tier baseline.
- A controlled 40-second `com.tencent.jkchess` cold-launch comparison read the
  requested threshold in each new process. Threshold 1000 reported a 7.237 s
  activity start, while threshold 128 reported 3.463 s and geared substantially
  more regions. This is promising but order/cache effects mean it is not yet a
  definitive gameplay result.
- Deployed library SHA-256:
  `e019663468123fc740ed399fbf3a1bdccf51361ee9d0b9eb7318cfa01e93035a`.
- Deployment backup:
  `/var/lib/waydroid/deploy-backups/20260823-160628-five-items`.

## Verification on 2026-08-30

- Added an ARM64 Native Bridge variant of `librs_jni.so`. Public NDK bitmap
  and native-window APIs replace dependencies on host-private framework C++
  objects at the guest boundary.
- The framework keeps `config.disable_renderscript=1` for native LoongArch64
  processes, but lazily loads the guest JNI library when an `arm64-v8a`
  application runs with `ro.dalvik.vm.native.bridge=libberberis_arm64.so`.
- Berberis exposes only `librs_jni.so` through the ARM64 guest namespace link;
  the LoongArch64 host library is not made public to applications.
- A minimal ARM64 APK completed `RenderScript.create()` and displayed PASS
  after a container restart with no temporary property override. Its process
  mapped the guest JNI, driver, and CPU reference libraries.
- YouTube `21.34.243` loaded the guest RenderScript stack, fully drew its main
  activity, remained alive for the 90-second observation window, and left the
  Android crash buffer empty.
- All `163/163` LoongArch64 Berberis runtime tests passed on the device.
- Effective overlay SHA-256 values are
  `4a6973704d95a57bbd323bb06bde77e8b08381e6d4ad656eff962d54b66477ef`
  for `framework.jar`,
  `a448293d3148b56c6923b8090717d6b4f537d76ad75b756f739c807a8ab2b218`
  for the guest `librs_jni.so`, and
  `e76c0a2851c50314a7ac0779960949e43daf2173290db9f4a7784a8f2ab72c5b`
  for `libberberis_arm64.so`.
- Final source-matched deployment backup:
  `/var/lib/waydroid/deploy-backups/20260830-185315-arm64-renderscript-source-match`.
- Legacy RenderScript graphics surfaces, FileA3D assets, and font-asset APIs
  are deliberately unsupported across the Native Bridge boundary. The
  validated target is the compute/bitmap path used by current applications.

## Remaining work

- Increase Lite JIT instruction and region coverage to reduce interpreter re-entry.
- Profile region formation, dispatch, helper calls, memory access, and JNI transitions on real applications.
- Expand syscall, signal, JNI, and Native Bridge correctness coverage.
- Keep application protection or emulator-detection failures separate from translation correctness bugs.
- Include the validated development commits in a coordinated tagged release before treating the cache as released functionality.
