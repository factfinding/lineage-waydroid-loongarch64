# ARM64 dav1d regression APK

This diagnostic links the workspace's public dav1d sources into an ARM64-only
JNI library, exercising Native Bridge rather than native LoongArch MediaCodec.
It supports scalar/NEON frame comparison and upstream dav1d checkasm.
No Instagram code or account data is used.

Run `build.sh [absolute-output-directory]` from any directory. It requires the
workspace Android SDK/NDK, JDK and Ninja, plus Meson on PATH. Generated files,
including the local diagnostic signing key, stay in the output directory.
`trim_dsp=false` is essential: otherwise CPU mask zero can still use assembly.
The build uses at most eight jobs and does not install or change device settings.

Generate a small IVF AV1 stream with FFmpeg, decode the same file on a reference
machine to planar 8-bit YUV420, and push the IVF to
`/data/local/tmp/av1-probe.ivf`. Install `probe.apk` and launch:

```sh
adb shell am start -W -n com.example.dav1dprobe/.MainActivity
adb logcat -d -s Dav1dProbe
```

The app logs FNV-1a 64-bit hashes of visible Y/U/V pixels for both scalar and
assembly decoding, with one decoding thread by default. Pass `--ei threads 4`
for four threads (accepted range 1–16), after force-stopping the previous run.
Compare each hash against the
reference raw frame (offset basis 14695981039346656037, prime 1099511628211,
arithmetic modulo 2^64). It also writes the first frame as `files/scalar.yuv`
and `files/asm.yuv` in its own app directory. Hash logging alone is not a pass;
both paths must match the independent reference for every frame.

For checkasm, force-stop the probe first and launch with `--es test msac`,
`--es test ipred_8bpc`, or another upstream test name. To run every test, pass
`*` as a literal string, preserving the quotes through the remote shell.
For one function, use `--es test itx_8bpc:inv_txfm_add_4x8_adst_adst_1_8bpc`.
Results are in the app's `files/checkasm.txt`; the log reports the return code.
Run as a diagnostic app: checkasm installs signal handlers and should not be
loaded into a production process. Root may be needed to retrieve files in this
Waydroid environment, where `run-as` can fail on setegid.

On 2026-09-16 the old JIT failed 17/1176 checkasm cases and produced corrupt
AV1 output while interpret-only matched reference pixels. A single-instruction
differential test isolated `0x6e051cc0` (`mov v0.b[2],v6.b[3]`): INS decoding
incorrectly tested width bits without respecting the lowest set bit. Durable
coverage for every width, lane, ignored source-index bit and alias combination
is in Berberis's LoongArch runtime tests.

A second diagnosis found incorrect FMLA/FMLS 2D matching in the 4S lowering.
This corrupted the floating-point forward transform used to generate checkasm
inputs, leaving inverse-transform failures after INS was fixed. Restricting the
4S match by bit 22 routes 2D through the interpreter. Do not interpret a checkasm
failure as proof that the tested assembly routine itself is faulty; compare its
input fixture as well.

A bundled decoder version later exposed another matcher bug absent from these
public checkasm vectors: ADDHN2 `0x4e2440a6` matched TBL because bit 21 was not
checked. Fixing that bit also excludes SADDL2, SSUBL2 and SUBHN2. The permanent
Berberis regression tests those neighbors and every valid TBL table length.
Passing one decoder version's checkasm is not proof that every application
codec path is covered; use matching encoded input and independent pixel hashes.
