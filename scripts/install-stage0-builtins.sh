#!/bin/bash

set -euo pipefail

android_root="${1:?Usage: $0 <android-source> <builtins-archive>}"
builtins="${2:?Usage: $0 <android-source> <builtins-archive>}"
clang_dir="$android_root/prebuilts/clang/host/linux-x86/clang-r563880c"
resource_dir="$clang_dir/lib/clang/21/lib/linux"

test -x "$clang_dir/bin/clang"
test -f "$builtins"
mkdir -p "$resource_dir"
install -m 0644 "$builtins" \
    "$resource_dir/libclang_rt.builtins-loongarch64-android.a"

echo "Installed stage-0 builtins in $resource_dir"
