#!/bin/bash

set -euo pipefail

llvm_root="${1:?Usage: $0 <llvm-workspace> <android-source> <output-archive>}"
android_root="${2:?Usage: $0 <llvm-workspace> <android-source> <output-archive>}"
output_archive="${3:?Usage: $0 <llvm-workspace> <android-source> <output-archive>}"
build_dir="$llvm_root/out/stage0-loongarch64-builtins"
clang_dir="$llvm_root/out/stage2-install"
cmake_bin="$llvm_root/prebuilts/cmake/linux-x86/bin/cmake"
ninja_bin="$llvm_root/prebuilts/build-tools/linux-x86/bin/ninja"
ndk_sysroot="$llvm_root/toolchain/prebuilts/ndk/releases/r28/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
header_overlay="$build_dir/include"
loongarch_uapi="$android_root/bionic/libc/kernel/uapi/asm-loongarch"

test -x "$clang_dir/bin/clang"
test -d "$ndk_sysroot/usr/include"
test -d "$loongarch_uapi/asm"

rm -rf -- "$build_dir"
mkdir -p "$header_overlay/sys" "$header_overlay/bits" "$(dirname "$output_archive")"
install -m 0644 "$android_root/bionic/libc/include/sys/user.h" "$header_overlay/sys/user.h"
install -m 0644 "$android_root/bionic/libc/include/sys/ucontext.h" "$header_overlay/sys/ucontext.h"
install -m 0644 \
    "$android_root/bionic/libc/include/bits/fenv_loongarch64.h" \
    "$header_overlay/bits/fenv_loongarch64.h"

"$cmake_bin" -G Ninja \
    -S "$llvm_root/toolchain/llvm-project/compiler-rt/lib/builtins" \
    -B "$build_dir/build" \
    -DCMAKE_MAKE_PROGRAM="$ninja_bin" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$clang_dir/bin/clang" \
    -DCMAKE_ASM_COMPILER="$clang_dir/bin/clang" \
    -DCMAKE_C_COMPILER_TARGET=loongarch64-linux-android10000 \
    -DCMAKE_ASM_COMPILER_TARGET=loongarch64-linux-android10000 \
    -DCMAKE_SYSROOT="$ndk_sysroot" \
    -DCMAKE_C_FLAGS="-I$header_overlay -I$loongarch_uapi" \
    -DCMAKE_AR="$clang_dir/bin/llvm-ar" \
    -DCMAKE_RANLIB="$clang_dir/bin/llvm-ranlib" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
    -DCOMPILER_RT_BUILTINS_HIDE_SYMBOLS=ON \
    -DCOMPILER_RT_INCLUDE_TESTS=OFF \
    -DCOMPILER_RT_OS_DIR=linux
"$ninja_bin" -C "$build_dir/build" -j8

install -m 0644 \
    "$build_dir/build/lib/linux/libclang_rt.builtins-loongarch64.a" \
    "$output_archive"
sha256sum "$output_archive"
