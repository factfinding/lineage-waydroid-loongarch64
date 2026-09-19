#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workspace_root="$(cd "$script_dir/../../../.." && pwd)"
cd "$workspace_root"
probe_dir="${1:-$workspace_root/logs/dav1d-regression}"
mkdir -p "$probe_dir"
probe_dir="$(cd "$probe_dir" && pwd)"
ndk_bin="$PWD/android-sdk/ndk/28.0.13004108/toolchains/llvm/prebuilt/linux-x86_64/bin"
sdk_bin="$PWD/android-sdk/build-tools/36.1.0"
export JAVA_HOME="$PWD/lineage-waydroid-23.2/prebuilts/jdk/jdk21/linux-x86"
export PATH="$PWD/lineage-waydroid-23.2/prebuilts/build-tools/linux-x86/bin:$JAVA_HOME/bin:$PATH"
mkdir -p "$probe_dir/apk/lib/arm64-v8a" "$probe_dir/classes"
cat > "$probe_dir/cross.ini" <<CROSS
[binaries]
c = '$ndk_bin/aarch64-linux-android29-clang'
ar = '$ndk_bin/llvm-ar'
strip = '$ndk_bin/llvm-strip'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
CROSS
meson setup --reconfigure "$probe_dir/build" lineage-waydroid-23.2/external/libdav1d \
    --cross-file "$probe_dir/cross.ini" --buildtype release --default-library static \
    -Denable_tools=false -Denable_tests=true -Dbitdepths=8 -Dtrim_dsp=false -Dc_args=-fPIC
ninja -C "$probe_dir/build" -j8 tests/checkasm src/libdav1d.a
if [[ ! -f "$probe_dir/debug.jks" ]]; then
    keytool -genkeypair -keystore "$probe_dir/debug.jks" -storepass android \
        -keypass android -alias androiddebugkey -keyalg RSA -validity 3650 \
        -dname 'CN=AV1 Diagnostic Test'
fi
"$ndk_bin/llvm-objcopy" --redefine-sym main=dav1d_checkasm_main "$probe_dir/build/tests/checkasm.p/checkasm_checkasm.c.o" "$probe_dir/checkasm-main.o"
checkasm_objects=("$probe_dir/checkasm-main.o")
for obj in "$probe_dir"/build/tests/checkasm.p/*.o "$probe_dir"/build/tests/libcheckasm_bitdepth_8.a.p/*.o; do
    [[ "$obj" == */checkasm_checkasm.c.o ]] || checkasm_objects+=("$obj")
done
"$ndk_bin/aarch64-linux-android29-clang++" -O2 -shared -fPIC -static-libstdc++ -Ilineage-waydroid-23.2/external/libdav1d/include -I"$probe_dir/build/include" "$script_dir/probe.cpp" "${checkasm_objects[@]}" "$probe_dir/build/src/libdav1d.a" -lm -o "$probe_dir/apk/lib/arm64-v8a/libdav1dprobe.so"
"$JAVA_HOME/bin/javac" -source 8 -target 8 -cp android-sdk/platforms/android-36/android.jar -d "$probe_dir/classes" "$script_dir/src/com/example/dav1dprobe/MainActivity.java"
"$sdk_bin/d8" --lib android-sdk/platforms/android-36/android.jar --output "$probe_dir/apk" "$probe_dir/classes/com/example/dav1dprobe/MainActivity.class"
"$sdk_bin/aapt2" link -o "$probe_dir/unsigned.apk" --manifest "$script_dir/AndroidManifest.xml" -I android-sdk/platforms/android-36/android.jar
python3 - "$probe_dir" <<'PY'
from pathlib import Path
import zipfile, sys
p=Path(sys.argv[1])
with zipfile.ZipFile(p/'unsigned.apk','a') as z:
    for f in (p/'apk').rglob('*'):
        if f.is_file(): z.write(f,str(f.relative_to(p/'apk')))
PY
"$sdk_bin/zipalign" -f -p 4 "$probe_dir/unsigned.apk" "$probe_dir/aligned.apk"
"$sdk_bin/apksigner" sign --ks "$probe_dir/debug.jks" --ks-pass pass:android --out "$probe_dir/probe.apk" "$probe_dir/aligned.apk"
printf 'Built %s/probe.apk\n' "$probe_dir"
