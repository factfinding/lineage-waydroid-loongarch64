#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd "$script_dir/.." && pwd)"
workspace="${1:?Usage: $0 <toolchain-workspace> <android-source> [dist-dir]}"
android_root="$(cd "${2:?Usage: $0 <toolchain-workspace> <android-source> [dist-dir]}" && pwd)"
dist_dir="${3:-$workspace/dist}"
llvm_root="$(cd "$workspace/llvm21" && pwd)"
rust_root="$(cd "$workspace/rust-1.88" && pwd)"
version="$(<"$source_dir/VERSION")"
stage0_builtins="$dist_dir/libclang_rt.builtins-loongarch64-android-stage0.a"
llvm_python="$llvm_root/prebuilts/python/linux-x86/bin/python3"
llvm_build="$llvm_root/toolchain/llvm_android/build.py"

mkdir -p "$dist_dir"
test "$(git -C "$llvm_root/toolchain/llvm-project" rev-parse 'HEAD^{tree}')" = \
    6d1a7f3adc778ad251b5de3a53a21d79cf82c3cc
test "$(git -C "$llvm_root/toolchain/llvm_android" rev-parse 'HEAD^{tree}')" = \
    2eb445bd16179f53405bd564991498b717856d1c
test "$(git -C "$rust_root/toolchain/android_rust" rev-parse 'HEAD^{tree}')" = \
    797e4a8ee9f18a6764748840d6177ccfb7bc56a4
test "$(git -C "$rust_root/toolchain/rustc" rev-parse 'HEAD^{tree}')" = \
    24e1ed5c8332ecdbc3aaa4a97682f86716438c5b

# First build the LLVM 21 host compiler without device runtimes.
(
    cd "$llvm_root"
    AOSP_ROOT="$android_root" LLVM_ANDROID_ARCHES=loongarch64 \
        "$llvm_python" "$llvm_build" \
        --build-name "loongarch64-$version" \
        --no-build=windows,lldb \
        --no-lto --no-pgo --no-bolt \
        --skip-tests --skip-package --skip-runtimes \
        --skip-source-setup --skip-apply-patches --no-incremental
)

# A freestanding compiler-rt archive breaks the initial bionic/toolchain
# dependency cycle. It uses the host compiler built above plus only public
# LLVM, NDK headers and Android headers.
"$script_dir/build-stage0-builtins.sh" \
    "$llvm_root" "$android_root" "$stage0_builtins"
"$script_dir/install-stage0-builtins.sh" "$android_root" "$stage0_builtins"

# Build only the bionic objects needed to construct the full LLVM runtime
# sysroot. The product and architecture definitions come from the source tag.
(
    cd "$android_root"
    source build/envsetup.sh
    lunch lineage_waydroid_loongarch64-bp4a-userdebug
    m -j8 libc libm libdl crtbegin_so crtbegin_dynamic crtbegin_static \
        crtend_so crtend_android
)

# Use the freshly built compiler and bionic outputs to create the LoongArch64
# sysroot, then build and package all required LLVM device runtimes.
AOSP_ROOT="$android_root" \
LOONGARCH64_BOOTSTRAP_BUILTINS="$stage0_builtins" \
    "$llvm_root/toolchain/llvm_android/scripts/prepare_loongarch64_libcxx_sysroot.sh"
(
    cd "$llvm_root"
    AOSP_ROOT="$android_root" LLVM_ANDROID_ARCHES=loongarch64 \
        "$llvm_python" "$llvm_build" \
        --build-name "loongarch64-$version" \
        --no-build=windows,lldb \
        --no-lto --no-pgo --no-bolt \
        --skip-tests --create-tar --package-stage2-install \
        --skip-source-setup --skip-apply-patches --incremental
)

llvm_archive="$llvm_root/out/stage2-install.tar.xz"
test -f "$llvm_archive"
install -m 0644 "$llvm_archive" "$dist_dir/clang-21-loongarch64-android.tar.xz"

# Overlay the clean LLVM package onto the Android prebuilt directory. Files
# outside the package carry Android's build metadata and remain untouched.
rsync -a "$llvm_root/out/stage2-install/" \
    "$android_root/prebuilts/clang/host/linux-x86/clang-r563880c/"

# Rust 1.88 is linked against the LLVM 21 package produced above.
(
    cd "$rust_root"
    toolchain/android_rust/tools/build.py \
        --build-name "loongarch64-1.88-clang21" \
        --ndk toolchain/prebuilts/ndk/releases/r27 \
        --clang-prebuilt "$llvm_root/out/stage2-install" \
        --llvm-prebuilt "$llvm_root/out/stage2-install" \
        --llvm-version 21 --llvm-linkage static \
        --no-bare-targets --no-device-targets --host-multilibs \
        --no-cargo-audit --no-bolt-opt --lto none --no-cgu1 \
        --no-copy-and-patch
)

rust_archive="$rust_root/dist/rust-loongarch64-1.88-clang21.tar.xz"
test -f "$rust_archive"
install -m 0644 "$rust_archive" "$dist_dir/rust-1.88-clang21.tar.xz"
"$script_dir/install-rust-toolchain.sh" "$android_root" "$rust_archive"

sha256sum \
    "$stage0_builtins" \
    "$dist_dir/clang-21-loongarch64-android.tar.xz" \
    "$dist_dir/rust-1.88-clang21.tar.xz" \
    > "$dist_dir/SHA256SUMS"

echo "Toolchain artifacts are in $dist_dir"
