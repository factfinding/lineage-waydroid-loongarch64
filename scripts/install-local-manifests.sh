#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd "$script_dir/.." && pwd)"
android_root="${1:-$PWD}"
destination="$android_root/.repo/local_manifests"

if [[ ! -d "$android_root/.repo" ]]; then
    echo "Run repo init for LineageOS 23.2 before installing local manifests." >&2
    exit 1
fi

mkdir -p "$destination"
install -m 0644 "$source_dir"/local_manifests/*.xml "$destination"/

echo "Installed LoongArch64 local manifests in $destination"
echo "Run: repo sync -c -j8"
