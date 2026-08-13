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

# Replace each rustlib target actually carried by the custom archive, but
# preserve the official Android and host-multilib targets that are not rebuilt.
if [[ -d "$staging/lib/rustlib" ]]; then
    while IFS= read -r -d '' rustlib; do
        name="$(basename "$rustlib")"
        [[ "$name" == src ]] && continue
        rm -rf -- "$destination/lib/rustlib/$name"
    done < <(find "$staging/lib/rustlib" -mindepth 1 -maxdepth 1 \
        -type d -print0)
fi

for directory in bin etc lib lib64 libexec share; do
    if [[ -d "$staging/$directory" ]]; then
        mkdir -p "$destination/$directory"
        # The custom package deliberately builds only the Linux x86_64 host
        # compiler.  Keep Android's official 1.88 target libraries and host
        # multilibs, then overlay the rebuilt compiler and libraries on top.
        rsync -a "$staging/$directory/" "$destination/$directory/"
    fi
done
if [[ -f "$staging/BUILD.bazel" ]]; then
    install -m 0644 "$staging/BUILD.bazel" "$destination/BUILD.bazel"
fi

"$destination/bin/rustc" --version
