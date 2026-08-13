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
stage0_libunwind="$dist_dir/libunwind-exported-loongarch64-android-stage0.a"
llvm_python="$llvm_root/prebuilts/python/linux-x86/bin/python3"
llvm_build="$llvm_root/toolchain/llvm_android/build.py"
host_gcc_root="$llvm_root/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8"
host_gcc_lib="$host_gcc_root/lib/gcc/x86_64-linux/4.8.3"
host_target_lib="$host_gcc_root/x86_64-linux/lib64"
host_libcxx_include="$llvm_root/out/stage1-install/include/c++/v1"

mkdir -p "$dist_dir"
test "$(git -C "$llvm_root/toolchain/llvm-project" rev-parse 'HEAD^{tree}')" = \
    1655c8bd88c43294e6ad10fca3b013e962186c74
test "$(git -C "$llvm_root/toolchain/llvm_android" rev-parse 'HEAD^{tree}')" = \
    6f11f5074da5a3b291be585882e44c7c6a03d446
test "$(git -C "$rust_root/toolchain/android_rust" rev-parse 'HEAD^{tree}')" = \
    797e4a8ee9f18a6764748840d6177ccfb7bc56a4
test "$(git -C "$rust_root/toolchain/rustc" rev-parse 'HEAD^{tree}')" = \
    6b38bfdc528402c49633de874b5f993b20d0b2c8

# First build the LLVM 21 host compiler without device runtimes.  BOLT's
# nested runtime CMake project does not inherit the GCC search paths supplied
# by llvm_android to the parent build, so provide them through the environment.
# They affect only this host-only bootstrap invocation.
bootstrap_args=(--no-incremental)
source_setup_args=()
if [[ -x "$llvm_root/out/stage1-install/bin/clang" &&
      -d "$llvm_root/out/llvm-project/llvm" ]]; then
    bootstrap_args=(--skip-source-setup --incremental)
    source_setup_args=(--skip-apply-patches)
fi
(
    cd "$llvm_root"
    AOSP_ROOT="$android_root" LLVM_ANDROID_ARCHES=loongarch64 \
    CFLAGS="-B$host_gcc_lib" \
    CXXFLAGS="-B$host_gcc_lib -isystem $host_libcxx_include" \
    LDFLAGS="-B$host_gcc_lib -L$host_gcc_lib -L$host_target_lib" \
        "$llvm_python" "$llvm_build" \
        --build-name "loongarch64-$version" \
        --no-build=windows,lldb \
        --no-lto --no-pgo --no-bolt \
        --skip-tests --skip-package --skip-runtimes \
        "${source_setup_args[@]}" "${bootstrap_args[@]}"
)

# Rust's bootstrap sanity check requires FileCheck even when tests are skipped;
# llvm_android builds it but does not install it in this host-only mode.
test -x "$llvm_root/out/stage2/bin/FileCheck"
install -m 0755 "$llvm_root/out/stage2/bin/FileCheck" \
    "$llvm_root/out/stage2-install/bin/FileCheck"

# Android must use the newly built compiler for the bootstrap bionic build.
# The stock r563880c compiler accepts LoongArch64 but crashes while emitting
# ThinLTO bitcode for the target.  Overlaying (without --delete) keeps the
# Android wrapper metadata and any files that are not part of stage2-install.
rsync -a "$llvm_root/out/stage2-install/" \
    "$android_root/prebuilts/clang/host/linux-x86/clang-r563880c/"

# A freestanding compiler-rt archive breaks the initial bionic/toolchain
# dependency cycle. It uses the host compiler built above plus only public
# LLVM, NDK headers and Android headers.
"$script_dir/build-stage0-builtins.sh" \
    "$llvm_root" "$android_root" "$stage0_builtins"
"$script_dir/install-stage0-builtins.sh" "$android_root" "$stage0_builtins"
"$script_dir/build-stage0-libunwind.sh" \
    "$llvm_root" "$android_root" "$stage0_libunwind"
"$script_dir/install-stage0-libunwind.sh" "$android_root" "$stage0_libunwind"

# android_rust names the 32-bit GNU host target i686 while LLVM installs the
# same runtime set under its i386 triple.
llvm_runtime_dir="$llvm_root/out/stage2-install/lib/clang/21/lib"
if [[ -d "$llvm_runtime_dir/i386-unknown-linux-gnu" &&
      ! -e "$llvm_runtime_dir/i686-unknown-linux-gnu" ]]; then
    ln -s i386-unknown-linux-gnu "$llvm_runtime_dir/i686-unknown-linux-gnu"
fi

# Rust 1.88 is linked against the host LLVM 21 package.  Build and install it
# before bionic because libc's dependency graph compiles the Rust core crate.
# Host Rust does not depend on the Android device runtime sysroot.
rust_source_args=()
if [[ -d "$rust_root/out/rustc/src" ]]; then
    rust_source_args=(--no-copy-and-patch)
fi
(
    cd "$rust_root"
    toolchain/android_rust/tools/build.py \
        --build-name "loongarch64-1.88-clang21" \
        --ndk toolchain/prebuilts/ndk/releases/r27 \
        --clang-prebuilt "$android_root/prebuilts/clang/host/linux-x86/clang-r563880c" \
        --llvm-prebuilt "$llvm_root/out/stage2-install" \
        --llvm-version 21 --llvm-linkage static \
        --no-bare-targets --no-device-targets --no-host-multilibs \
        --no-cargo-audit --no-bolt-opt --lto none --no-cgu1 \
        "${rust_source_args[@]}"
)

rust_archive="$rust_root/dist/rust-loongarch64-1.88-clang21.tar.xz"
test -f "$rust_archive"
install -m 0644 "$rust_archive" "$dist_dir/rust-1.88-clang21.tar.xz"
"$script_dir/install-rust-toolchain.sh" "$android_root" "$rust_archive"

# Build only the bionic objects needed to construct the full LLVM runtime
# sysroot. The product and architecture definitions come from the source tag.
(
    cd "$android_root"
    set +u
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

sha256sum \
    "$stage0_builtins" \
    "$stage0_libunwind" \
    "$dist_dir/clang-21-loongarch64-android.tar.xz" \
    "$dist_dir/rust-1.88-clang21.tar.xz" \
    > "$dist_dir/SHA256SUMS"

echo "Toolchain artifacts are in $dist_dir"
