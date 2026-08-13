#!/bin/bash

set -euo pipefail

llvm_root="${1:?Usage: $0 <llvm-workspace> <android-source> <output-archive>}"
android_root="${2:?Usage: $0 <llvm-workspace> <android-source> <output-archive>}"
output_archive="${3:?Usage: $0 <llvm-workspace> <android-source> <output-archive>}"
build_dir="$llvm_root/out/stage0-loongarch64-libunwind"
clang_dir="$llvm_root/out/stage2-install"
cmake_bin="$llvm_root/prebuilts/cmake/linux-x86/bin/cmake"
ninja_bin="$llvm_root/prebuilts/build-tools/linux-x86/bin/ninja"
ndk_sysroot="$llvm_root/toolchain/prebuilts/ndk/releases/r28/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
header_overlay="$llvm_root/out/stage0-loongarch64-builtins/include"
loongarch_uapi="$android_root/bionic/libc/kernel/uapi/asm-loongarch"
target=loongarch64-linux-android10000

test -x "$clang_dir/bin/clang"
test -d "$ndk_sysroot/usr/include"
test -f "$header_overlay/sys/ucontext.h"
test -d "$loongarch_uapi/asm"

rm -rf -- "$build_dir"
mkdir -p "$build_dir" "$(dirname "$output_archive")"

common_flags="-I$header_overlay -I$loongarch_uapi -D_LIBUNWIND_USE_DLADDR=0"
linker_flags="-unwindlib=none -nostdlib++ -resource-dir $clang_dir/lib/clang/21"

"$cmake_bin" -G Ninja \
    -S "$llvm_root/toolchain/llvm-project/runtimes" \
    -B "$build_dir/build" \
    -DCMAKE_MAKE_PROGRAM="$ninja_bin" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$clang_dir/bin/clang" \
    -DCMAKE_CXX_COMPILER="$clang_dir/bin/clang++" \
    -DCMAKE_ASM_COMPILER="$clang_dir/bin/clang" \
    -DCMAKE_C_COMPILER_TARGET="$target" \
    -DCMAKE_CXX_COMPILER_TARGET="$target" \
    -DCMAKE_ASM_COMPILER_TARGET="$target" \
    -DCMAKE_SYSROOT="$ndk_sysroot" \
    -DCMAKE_C_FLAGS="$common_flags" \
    -DCMAKE_CXX_FLAGS="$common_flags" \
    -DCMAKE_EXE_LINKER_FLAGS="$linker_flags" \
    -DCMAKE_SHARED_LINKER_FLAGS="$linker_flags" \
    -DCMAKE_AR="$clang_dir/bin/llvm-ar" \
    -DCMAKE_RANLIB="$clang_dir/bin/llvm-ranlib" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DLLVM_ENABLE_RUNTIMES=libunwind \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_PLUGINS=OFF \
    -DLLVM_ENABLE_LIBCXX=ON \
    -DLLVM_STATIC_LINK_CXX_STDLIB=ON \
    -DLLVM_USE_LINKER=lld \
    -DLIBUNWIND_TARGET_TRIPLE="$target" \
    -DLIBUNWIND_HIDE_SYMBOLS=FALSE \
    -DLIBUNWIND_ENABLE_SHARED=FALSE \
    -DLIBUNWIND_ENABLE_STATIC=TRUE \
    -DLIBUNWIND_ENABLE_ASSERTIONS=FALSE \
    -DLIBUNWIND_USE_FRAME_HEADER_CACHE=TRUE \
    -DLIBUNWIND_HAS_DL_LIB=FALSE \
    -DLIBUNWIND_HAS_PTHREAD_LIB=FALSE \
    -DLIBUNWIND_INCLUDE_TESTS=FALSE
"$ninja_bin" -C "$build_dir/build" -j8 unwind

install -m 0644 "$build_dir/build/lib/libunwind.a" "$output_archive"
sha256sum "$output_archive"
