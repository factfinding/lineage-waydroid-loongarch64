# MediaCodec output regression probe

`CodecProbe.java` runs through Android's public MediaCodec API in a native ART
process. It prints the actual decoder list and software/hardware attributes,
selects a decoder for the input track (or accepts an explicit component name),
and checks that a generated, changing, no-reordering video emits every input
frame, reaches EOS, has monotonic timestamps, and changes output pixels.
The default mode checks byte-buffer output. A third argument `surface` uses an
ImageReader Surface and verifies delivered frame counts and timestamps. It does
not verify EGL import or displayed pixels; use the minigbm YUV import tests and
an application for those checks.

From the workspace root, build with the local JDK and SDK:

```bash
mkdir -p logs/media-codec-probe
lineage-waydroid-23.2/prebuilts/jdk/jdk21/linux-x86/bin/javac \
    -cp android-sdk/platforms/android-36/android.jar \
    -d logs/media-codec-probe \
    lineage-waydroid-loongarch64/tests/media-codec/CodecProbe.java
JAVA_HOME="$PWD/lineage-waydroid-23.2/prebuilts/jdk/jdk21/linux-x86" \
    android-sdk/build-tools/36.1.0/d8 \
    --lib android-sdk/platforms/android-36/android.jar \
    --output logs/media-codec-probe logs/media-codec-probe/CodecProbe.class
ffmpeg -hide_banner -loglevel error -f lavfi \
    -i testsrc2=size=720x1280:rate=30 -frames:v 60 \
    -c:v libaom-av1 -cpu-used 8 -threads 4 -crf 40 \
    logs/media-codec-probe/av1-720p.mp4
```

Push `classes.dex` and the sample to `/data/local/tmp/`, then run:

```bash
adb shell 'CLASSPATH=/data/local/tmp/classes.dex app_process /system/bin CodecProbe /data/local/tmp/av1-720p.mp4'
```

With no arguments the probe only lists components. A second argument chooses a
specific component, e.g. `c2.android.av1.decoder`. A pass has `inputs=60`,
`outputs=60`, nonzero `changed_frames`, and `eos=true`. In byte-buffer mode
changes refer to pixel checksums; in Surface mode they refer to timestamps. Inspect the RESULT and process
exit status, not merely successful component creation or input consumption.
Use H.264 (`libx264 -bf 0`) and VP9 (`libvpx-vp9`) samples for regression checks.
Do not use arbitrary variable-frame-rate or reordered streams with this probe's
one-packet-per-frame and monotonic-timestamp assertions.

### Negotiated pixel formats

`ColorFormatProbe.java` requests planar/flexible YUV420 and RGBAFlexible from
`c2.ffmpeg.h264.decoder`, checking actual red pixels, 12 frames, and EOS. Its
`mixed` mode runs YUV and RGBA instances concurrently. Build with the javac/d8
commands above, substituting this class name. Generate its input with:

```bash
ffmpeg -hide_banner -loglevel error -f lavfi \
    -i color=c=red:s=320x240:r=12 -frames:v 12 -c:v libx264 -bf 0 \
    logs/media-codec-probe/red-h264.mp4
```

Push its dex as `/data/local/tmp/color-format-probe.dex` and the video as
`/data/local/tmp/red-h264.mp4`, then run:

```bash
adb shell 'CLASSPATH=/data/local/tmp/color-format-probe.dex app_process /system/bin ColorFormatProbe /data/local/tmp/red-h264.mp4 mixed'
adb shell 'CLASSPATH=/data/local/tmp/color-format-probe.dex app_process /system/bin ColorFormatProbe /data/local/tmp/red-h264.mp4 0x7f420888'
adb shell 'CLASSPATH=/data/local/tmp/color-format-probe.dex app_process /system/bin ColorFormatProbe /data/local/tmp/red-h264.mp4 6 reject'
adb shell 'CLASSPATH=/data/local/tmp/color-format-probe.dex app_process /system/bin ColorFormatProbe /data/local/tmp/red-h264.mp4 54 reject'
```

Run `mixed` with both `debug.ffmpeg-codec2.pixel_format=YUV_420` and `RGBX_8888`,
recreating the codec between changes. Explicit byte-buffer requests must work
independently of the property, which remains an opaque Surface preference.
RGBAFlexible selects BGRA on this framework; the probe checks all four bytes.
RGB565 (6) and P010 (54) must be rejected during configure, not silently
accepted and replaced with another layout. These are the supported formats of
this FFmpeg implementation, not a restriction on other MediaCodec components.
Also run the changing-video Surface controls with the original RGBX default.

The native `ccodec_unit_test --gtest_filter=ColorLayoutTest.*` checks RGBA/BGRA
channel and alpha metadata, both direct wrapping and forced copying, and the
final MediaCodec-facing buffer range. This complements the Java end-to-end
test; successful frame counts alone cannot detect shifted color bytes.

`AudioCodecProbe.java` checks that the platform AAC decoder is preferred for LC
and xHE-AAC, and that FFmpeg advertises LC but not its incomplete xHE-AAC support.
Build it with the same javac/d8 commands, substituting its class/file name. With
no arguments it checks selection and profiles; with a local media path it also
checks PCM output, changing checksums, monotonic timestamps, and EOS. An optional
second argument forces a decoder. Use both mono and stereo xHE-AAC samples:
mono alone does not exercise MPEG Surround phase processing. Application media
is private diagnostic input and must not be committed. A generated AAC-LC sine
sample covers ordinary AAC but cannot replace the xHE-AAC stereo control.

### Instagram native decoder compatibility

On the patched Waydroid framework, `debug.waydroid.instagram_native_av1=true`
opts Instagram into a process-local `Build.MODEL="Waydroid Emulator"` override.
The hook runs before application code and only when the native bridge is
`libberberis_arm64.so`. Instagram 442.0.0.46.79 has an emulator policy preferring
platform dav1d; actual tested playback after the override selected native
`c2.ffmpeg.vp9.decoder`. Native AV1 playback inside Instagram is not yet verified.
The property name is retained from the AV1 investigation. This is a version-dependent
application compatibility experiment, not a general MediaCodec API switch;
other model-dependent Instagram behavior may also change. System properties
and other applications retain their original model. The LoongArch64 product
sets the property to true in vendor/build.prop, enabling it at every boot.
The framework fallback remains false for products without this setting.

Set the property as root, then force-stop and launch Instagram:

```bash
adb shell setprop debug.waydroid.instagram_native_av1 true
adb shell am force-stop com.instagram.android
adb shell am start -n com.instagram.android/com.instagram.mainactivity.InstagramMainActivity
```

To temporarily revert the policy, set the property to `false`, force-stop, and
launch again. Android restart restores the product default (true). To disable
it permanently, change the product property to false and rebuild, or edit the
device's backed-up vendor/build.prop overlay accordingly. No application data
or media caches need to be cleared. Confirm native codec creation (VP9 in the
validated application playback) and actual video output in logs; the
compatibility-hook log alone does not prove the decoder switched.

Build `InstagramCompatProbe.java` using the javac/d8 commands above. Run it in
fresh `app_process` instances with the property false/true/false, passing the
same boolean as its argument. It checks package exclusion, process isolation,
the opt-in model value, and an unchanged global model property. This probe
requires the experimental framework and Berberis; it does not test playback.
