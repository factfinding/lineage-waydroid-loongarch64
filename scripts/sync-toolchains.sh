#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd "$script_dir/.." && pwd)"
workspace="${1:?Usage: $0 <workspace> [release-tag]}"
release_tag="${2:-v$(<"$source_dir/VERSION")}"
manifest_url="https://github.com/factfinding/lineage-waydroid-loongarch64.git"

command -v repo >/dev/null
mkdir -p "$workspace/llvm21" "$workspace/rust-1.88"

(
    cd "$workspace/llvm21"
    repo init -u "$manifest_url" -b "refs/tags/$release_tag" \
        -m toolchains/manifests/llvm21.xml
    repo sync -c -j8
)

(
    cd "$workspace/rust-1.88"
    repo init -u "$manifest_url" -b "refs/tags/$release_tag" \
        -m toolchains/manifests/rust-1.88.xml
    repo sync -c -j8
)

"$script_dir/apply-toolchain-patches.sh" "$workspace" "$release_tag"
