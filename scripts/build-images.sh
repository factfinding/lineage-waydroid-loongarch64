#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd "$script_dir/.." && pwd)"
android_root="$(cd "${1:?Usage: $0 <android-source> [dist-dir]}" && pwd)"
dist_dir="${2:-$android_root/out/release-v$(<"$source_dir/VERSION")}"
product_out="$android_root/out/target/product/waydroid_loongarch64"

mkdir -p "$dist_dir"
(
    cd "$android_root"
    set +u
    source build/envsetup.sh
    lunch lineage_waydroid_loongarch64-bp4a-userdebug
    m -j8 systemimage vendorimage
    repo manifest -r -o "$dist_dir/manifest.xml"
)

for image in system.img vendor.img; do
    test -f "$product_out/$image"
    install -m 0644 "$product_out/$image" "$dist_dir/$image"
done
sha256sum "$dist_dir/system.img" "$dist_dir/vendor.img" \
    > "$dist_dir/SHA256SUMS-images"

echo "Images and pinned manifest are in $dist_dir"
