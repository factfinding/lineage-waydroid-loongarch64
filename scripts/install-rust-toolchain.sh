#!/bin/bash

set -euo pipefail

android_root="${1:?Usage: $0 <android-source> <rust-toolchain-archive>}"
archive="${2:?Usage: $0 <android-source> <rust-toolchain-archive>}"
destination="$android_root/prebuilts/rust/linux-x86/1.88.0"
staging="$(mktemp -d)"
trap 'rm -rf -- "$staging"' EXIT

test -f "$archive"
test -d "$destination"
tar -xJf "$archive" -C "$staging"

for directory in bin etc lib lib64 libexec share; do
    if [[ -d "$staging/$directory" ]]; then
        mkdir -p "$destination/$directory"
        rsync -a --delete "$staging/$directory/" "$destination/$directory/"
    fi
done
if [[ -f "$staging/BUILD.bazel" ]]; then
    install -m 0644 "$staging/BUILD.bazel" "$destination/BUILD.bazel"
fi

"$destination/bin/rustc" --version
