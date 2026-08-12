#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd "$script_dir/.." && pwd)"
android_root="${1:?Usage: $0 <android-source> [release-tag]}"
release_tag="${2:-v$(<"$source_dir/VERSION")}"

mkdir -p "$android_root"
(
    cd "$android_root"
    repo init -u https://github.com/LineageOS/android.git -b lineage-23.2
)
"$script_dir/install-local-manifests.sh" "$android_root" "$release_tag"
(
    cd "$android_root"
    # Fetch concurrently but serialize checkout.  This avoids repo's parallel
    # checkout deadlock with very large clone bundles on WSL2.
    repo sync -c -j8 -n --no-tags
    repo sync -c -j1 -l
)
"$script_dir/apply-patches.sh" "$android_root"

echo "Synchronized and patched $release_tag in $android_root"
