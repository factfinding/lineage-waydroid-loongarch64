#!/bin/bash

set -euo pipefail

android_root="${1:?Usage: $0 <android-source> <libunwind-archive>}"
libunwind="${2:?Usage: $0 <android-source> <libunwind-archive>}"
clang_dir="$android_root/prebuilts/clang/host/linux-x86/clang-r563880c"
resource_dir="$clang_dir/lib/clang/21/lib/linux/loongarch64"

test -x "$clang_dir/bin/clang"
test -f "$libunwind"
mkdir -p "$resource_dir"
install -m 0644 "$libunwind" "$resource_dir/libunwind-exported.a"

echo "Installed stage-0 exported libunwind in $resource_dir"
