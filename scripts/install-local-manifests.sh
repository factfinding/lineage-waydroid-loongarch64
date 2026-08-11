#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd "$script_dir/.." && pwd)"
android_root="${1:-$PWD}"
release_tag="${2:-}"
destination="$android_root/.repo/local_manifests"

if [[ ! -d "$android_root/.repo" ]]; then
    echo "Run repo init for LineageOS 23.2 before installing local manifests." >&2
    exit 1
fi

mkdir -p "$destination"
install -m 0644 "$source_dir"/local_manifests/*.xml "$destination"/

if [[ -z "$release_tag" ]] && git -C "$source_dir" rev-parse --git-dir >/dev/null 2>&1; then
    release_tag="$(git -C "$source_dir" describe --tags --exact-match 2>/dev/null || true)"
fi

if [[ -n "$release_tag" ]]; then
    if [[ ! "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Invalid release tag: $release_tag" >&2
        exit 1
    fi

    sed -i -E \
        "/remote=\"loongarch\"/ s#revision=\"refs/heads/[^\"]+\"#revision=\"refs/tags/$release_tag\"#" \
        "$destination"/*.xml
    echo "Pinned published LoongArch64 projects to $release_tag"
fi

echo "Installed LoongArch64 local manifests in $destination"
echo "Run: repo sync -c -j8"
