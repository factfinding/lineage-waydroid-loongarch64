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
    73b3d61f832092ad0ce92cf367557bae6f862ac0
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
    gclient sync --no-history -j8 -D -R
)

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
install -m 0644 "$apk" \
    "$android_root/external/chromium-webview/prebuilt/loongarch64/webview.apk"
sha256sum "$dist_dir/webview-loongarch64.apk"
