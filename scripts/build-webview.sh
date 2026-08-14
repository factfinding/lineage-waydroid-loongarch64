#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd "$script_dir/.." && pwd)"
android_root="$(cd "${1:?Usage: $0 <android-source> <webview-workspace> [dist-dir]}" && pwd)"
workspace="${2:?Usage: $0 <android-source> <webview-workspace> [dist-dir]}"
dist_dir="${3:-$workspace/dist}"
chromium_dir="$workspace/src"
depot_tools="$workspace/depot_tools"
release_tag="v$(<"$source_dir/VERSION")"
depot_revision="d22ef3bf62a8c3c76d9c7427015bdfec7665587a"
output_dir="$chromium_dir/out/loong64"
builtins="$android_root/prebuilts/clang/host/linux-x86/clang-r563880c/lib/clang/21/lib/linux/libclang_rt.builtins-loongarch64-android.a"

mkdir -p "$workspace" "$dist_dir"
if [[ ! -d "$depot_tools/.git" ]]; then
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$depot_tools"
fi
git -C "$depot_tools" fetch origin "$depot_revision"
git -C "$depot_tools" switch --detach "$depot_revision"
export PATH="$depot_tools:$PATH"

if [[ ! -d "$chromium_dir/.git" ]]; then
    git clone --depth 1 --branch "$release_tag" \
        https://github.com/factfinding/chromium.git "$chromium_dir"
fi
test "$(git -C "$chromium_dir" rev-parse HEAD)" = \
    5103c22dfa55f8288b723a8653f6785239932da7
git -C "$chromium_dir" diff --quiet
git -C "$chromium_dir" diff --cached --quiet
if [[ -e "$output_dir" ]]; then
    echo "Refusing an incremental WebView build: remove $output_dir first." >&2
    exit 1
fi

(
    cd "$workspace"
    if [[ ! -f .gclient ]]; then
        gclient config --name src --unmanaged \
            https://github.com/factfinding/chromium.git
    fi
    if ! grep -Eq '^target_os[[:space:]]*=' .gclient; then
        printf '\ntarget_os = ["android"]\n' >> .gclient
    fi
    gclient sync --no-history -j8 -D -R
)

# Chromium's pinned Rust sysroot does not yet ship Android LoongArch64 libc
# definitions.  LoongArch64 and RISC-V64 use the asm-generic syscall ABI, so
# derive the missing module from the matching vendored libc version and drop
# the RISC-V-specific compatibility HWCAP constants.
rust_android="$chromium_dir/third_party/rust-toolchain/lib/rustlib/src/rust/library/vendor/libc-0.2.185/src/unix/linux_like/android/b64"
install -D -m 0644 "$rust_android/riscv64/mod.rs" \
    "$rust_android/loongarch64/mod.rs"
sed -i \
    '/^\/\/ From NDK.s asm\/hwcap.h$/,/^pub const COMPAT_HWCAP_ISA_C:/d' \
    "$rust_android/loongarch64/mod.rs"
if ! grep -q 'target_arch = "loongarch64"' "$rust_android/mod.rs"; then
    sed -i '/    } else if #\[cfg(target_arch = "riscv64")\] {/i\
    } else if #[cfg(target_arch = "loongarch64")] {\
        mod loongarch64;\
        pub use self::loongarch64::*;' "$rust_android/mod.rs"
fi
rust_android_raw="$chromium_dir/third_party/rust-toolchain/lib/rustlib/src/rust/library/std/src/os/android/raw.rs"
sed -i \
    's/target_arch = "aarch64", target_arch = "riscv64"/target_arch = "aarch64", target_arch = "riscv64", target_arch = "loongarch64"/' \
    "$rust_android_raw"

# BoringSSL has no LoongArch assembly backend, but its portable implementation
# only needs the native word size to select the generic 64-bit code paths.
boringssl_target="$chromium_dir/third_party/boringssl/src/include/openssl/target.h"
if ! grep -q 'defined(__loongarch__)' "$boringssl_target"; then
    sed -i '/#elif defined(__riscv) && __SIZEOF_POINTER__ == 8/i\
#elif defined(__loongarch__) && __SIZEOF_POINTER__ == 8\
#define OPENSSL_64_BIT' "$boringssl_target"
fi

# Match the generated four-reference declarations. Clang 23 diagnoses the
# older unspecified array bounds as mismatched declarations under -Werror.
libvpx_lsx_sad="$chromium_dir/third_party/libvpx/source/libvpx/vpx_dsp/loongarch/sad_lsx.c"
sed -i 's/const uint8_t \*const refs\[\]/const uint8_t *const refs[4]/g' \
    "$libvpx_lsx_sad"

# Newer Clang correctly preserves the const qualifier of libvpx convolution
# inputs.  The LoongArch LSX sources still declare a handful of read-only
# cursor variables as writable pointers, unlike their function parameters.
libvpx_lsx="$chromium_dir/third_party/libvpx/source/libvpx/vpx_dsp/loongarch"
sed -i \
    -e 's/^  uint8_t \*src_tmp1;$/  const uint8_t *src_tmp1;/' \
    "$libvpx_lsx/vpx_convolve8_avg_vert_lsx.c"
sed -i \
    -e 's/^    uint8_t \*src_tmp0 = src + 8;$/    const uint8_t *src_tmp0 = src + 8;/' \
    "$libvpx_lsx/vpx_convolve8_lsx.c"
sed -i \
    -e 's/^  uint8_t \*src_tmp;$/  const uint8_t *src_tmp;/' \
    -e 's/^    uint8_t \*src_tmp0 = src + src_stride;$/    const uint8_t *src_tmp0 = src + src_stride;/' \
    "$libvpx_lsx/vpx_convolve8_vert_lsx.c"
sed -i \
    -e 's/^    uint8_t \*src_tmp = src + 16;$/    const uint8_t *src_tmp = src + 16;/' \
    "$libvpx_lsx/vpx_convolve_avg_lsx.c"
sed -i \
    -e 's/^  uint8_t \*src_tmp1 = src + src_stride4;$/  const uint8_t *src_tmp1 = src + src_stride4;/' \
    -e 's/^  uint8_t \*src_tmp1 = src + 8;$/  const uint8_t *src_tmp1 = src + 8;/' \
    "$libvpx_lsx/vpx_convolve8_horiz_lsx.c"

# Generate the Android NDK sysroot exported by the tagged platform source.
(
    cd "$android_root"
    set +u
    source build/envsetup.sh
    lunch lineage_waydroid_loongarch64-bp4a-userdebug
    m -j8 ndk
)

test -f "$builtins"
install -D -m 0644 "$builtins" \
    "$chromium_dir/third_party/llvm-build/Release+Asserts/lib/clang/23/lib/linux/libclang_rt.builtins-loongarch64-android.a"

aosp_ndk="$android_root/out/soong/ndk/sysroot"
chromium_ndk="$chromium_dir/third_party/android_toolchain/ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
mkdir -p \
    "$chromium_ndk/usr/include/loongarch64-linux-android" \
    "$chromium_ndk/usr/lib/loongarch64-linux-android/36"
rsync -a "$aosp_ndk/usr/include/loongarch64-linux-android/" \
    "$chromium_ndk/usr/include/loongarch64-linux-android/"
for header in bits/fenv_loongarch64.h fenv.h setjmp.h sys/stat.h sys/ucontext.h sys/user.h; do
    install -D -m 0644 "$aosp_ndk/usr/include/$header" \
        "$chromium_ndk/usr/include/$header"
done
rsync -a "$aosp_ndk/usr/lib/loongarch64-linux-android/current/" \
    "$chromium_ndk/usr/lib/loongarch64-linux-android/36/"
install -m 0644 \
    "$android_root/out/soong/.intermediates/bionic/libc/crtbegin_dynamic/android_loongarch64/crtbegin_dynamic.o" \
    "$chromium_ndk/usr/lib/loongarch64-linux-android/36/crtbegin_dynamic.o"
install -m 0644 \
    "$android_root/out/soong/.intermediates/bionic/libc/crtend_android/android_loongarch64/crtend_android.o" \
    "$chromium_ndk/usr/lib/loongarch64-linux-android/36/crtend_android.o"
install -m 0644 "$builtins" \
    "$chromium_ndk/usr/lib/loongarch64-linux-android/36/libatomic.a"

# Generate the Android LoongArch64 FFmpeg configuration with FFmpeg's own
# configure script, then export it into Chromium's platform-config directory.
# The generated GN file is patched separately because regenerating it requires
# build directories for every Chromium-supported FFmpeg platform.
export PATH="$chromium_dir/third_party/llvm-build/Release+Asserts/bin:$PATH"
(
    cd "$chromium_dir"
    python3 media/ffmpeg/scripts/build_ffmpeg.py \
        android loong64 --branding Chrome
    cd media/ffmpeg/scripts
    python3 - <<'PY'
from robo_build import CopyConfigPythonTranslation
from robo_lib.config import RoboConfiguration

CopyConfigPythonTranslation(RoboConfiguration())
PY
)
ffmpeg_dir="$chromium_dir/third_party/ffmpeg"
# ffversion.h is created late by FFmpeg's build and may not be present when
# the generic config exporter scans the directory.  Copy the generated header
# explicitly so Chromium can compile libavcodec/version.c from a fresh tree.
install -D -m 0644 \
    "$ffmpeg_dir/build.loong64.android/Chrome/libavutil/ffversion.h" \
    "$ffmpeg_dir/chromium/config/Chrome/android/loong64/libavutil/ffversion.h"
ffmpeg_patch="$source_dir/patches/chromium-third-party-ffmpeg/0001-ffmpeg-add-Android-LoongArch64-sources.patch"
if git -C "$ffmpeg_dir" apply --check "$ffmpeg_patch"; then
    git -C "$ffmpeg_dir" apply "$ffmpeg_patch"
elif ! git -C "$ffmpeg_dir" apply --reverse --check "$ffmpeg_patch"; then
    echo "FFmpeg LoongArch64 source-list patch does not apply cleanly." >&2
    exit 1
fi
v8_dir="$chromium_dir/v8"
v8_patch="$source_dir/patches/chromium-v8/0001-v8-read-LoongArch64-bionic-signal-context.patch"
if git -C "$v8_dir" apply --check "$v8_patch"; then
    git -C "$v8_dir" apply "$v8_patch"
elif ! git -C "$v8_dir" apply --reverse --check "$v8_patch"; then
    echo "V8 LoongArch64 Android signal-context patch does not apply cleanly." >&2
    exit 1
fi

for density in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
    install -D -m 0644 \
        "$chromium_dir/chrome/android/java/res_chromium_base/mipmap-$density/app_icon.png" \
        "$chromium_dir/android_webview/nonembedded/java/res_icon/drawable-$density/icon_webview.png"
done

gn_args='target_os="android" target_cpu="loong64" is_debug=false is_official_build=true is_chrome_branded=false use_official_google_api_keys=false ffmpeg_branding="Chrome" proprietary_codecs=true enable_resource_allowlist_generation=false enable_remoting=false is_component_build=false symbol_level=0 enable_nacl=false blink_symbol_level=0 webview_devui_show_icon=false dfmify_dev_ui=false disable_fieldtrial_testing_config=true android_default_version_name="151.0.7922.71" android_default_version_code="792207170" loongarch_webview_only=true use_crash_key_stubs=true build_tflite_with_xnnpack=false build_litert_with_xnnpack=false clang_use_default_sample_profile=false'
(
    cd "$chromium_dir"
    source build/android/envsetup.sh
    gn gen out/loong64 --args="$gn_args"
    ninja -j8 -C out/loong64 system_webview_apk
)

apk="$output_dir/apks/SystemWebView64.apk"
test -f "$apk"
install -m 0644 "$apk" "$dist_dir/webview-loongarch64.apk"
install -D -m 0644 "$apk" \
    "$android_root/external/chromium-webview/prebuilt/loongarch64/webview.apk"

# The Chromium WebView project keeps the active Soong definition and README in
# patches/.  repo sync leaves the pickup symlinks absent, so create the same
# links used by Android's WebView prebuilt integration before building images.
webview_prebuilt="$android_root/external/chromium-webview"
for link in Android.bp README; do
    case "$link" in
        Android.bp) target="patches/os_pickup.bp" ;;
        README) target="patches/README" ;;
    esac
    if [[ ! -e "$webview_prebuilt/$link" && ! -L "$webview_prebuilt/$link" ]]; then
        ln -s "$target" "$webview_prebuilt/$link"
    fi
    if [[ "$(readlink "$webview_prebuilt/$link")" != "$target" ]]; then
        echo "Unexpected $webview_prebuilt/$link; expected a link to $target." >&2
        exit 1
    fi
done
sha256sum "$dist_dir/webview-loongarch64.apk"
