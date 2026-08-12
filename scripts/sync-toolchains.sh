#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd "$script_dir/.." && pwd)"
workspace="${1:?Usage: $0 <workspace> [release-tag]}"
release_tag="${2:-v$(<"$source_dir/VERSION")}"
manifest_url="https://github.com/factfinding/lineage-waydroid-loongarch64.git"

command -v repo >/dev/null
mkdir -p "$workspace/llvm21" "$workspace/rust-1.88"

sync_projects() {
    # Fetch concurrently, then serialize worktree checkout.  On WSL2, repo's
    # parallel checkout can leave its final worker waiting on an exited Git
    # process after large clone bundles have already been unpacked.
    repo sync -c -j8 -n --no-tags
    repo sync -c -j1 -l
}

(
    cd "$workspace/llvm21"
    repo init -u "$manifest_url" -b "refs/tags/$release_tag" \
        -m toolchains/manifests/llvm21.xml
    sync_projects
)

(
    cd "$workspace/rust-1.88"
    repo init -u "$manifest_url" -b "refs/tags/$release_tag" \
        -m toolchains/manifests/rust-1.88.xml
    sync_projects
)

"$script_dir/apply-toolchain-patches.sh" "$workspace" "$release_tag"
