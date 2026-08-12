#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd "$script_dir/.." && pwd)"
workspace="${1:?Usage: $0 <workspace> [release-tag]}"
release_tag="${2:-v$(<"$source_dir/VERSION")}"

if [[ "$(git -C "$source_dir" describe --tags --exact-match 2>/dev/null || true)" != "$release_tag" ]]; then
    echo "Checkout $release_tag in lineage-waydroid-loongarch64 before applying its patches." >&2
    exit 1
fi

apply_queue() {
    local project="$1"
    local queue="$2"
    local patch

    test -d "$project/.git"
    git -C "$project" diff --quiet
    git -C "$project" diff --cached --quiet
    for patch in "$queue"/*.patch; do
        git -C "$project" am "$patch"
    done
}

apply_queue "$workspace/llvm21/toolchain/llvm-project" \
    "$source_dir/toolchains/llvm21/patches/toolchain__llvm-project"
apply_queue "$workspace/llvm21/toolchain/llvm_android" \
    "$source_dir/toolchains/llvm21/patches/toolchain__llvm_android"
apply_queue "$workspace/rust-1.88/toolchain/android_rust" \
    "$source_dir/toolchains/rust-1.88/patches/toolchain__android_rust"
apply_queue "$workspace/rust-1.88/toolchain/rustc" \
    "$source_dir/toolchains/rust-1.88/patches/toolchain__rustc"

echo "Applied $release_tag toolchain patch queues."
