#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd "$script_dir/.." && pwd)"
android_root="${1:-$PWD}"
patch_root="$android_root/vendor/extra/waydroid-patches/base-patches-36"
tag_name="autopatch/base-patches-36"
current_project=""
skip_project=false

if [[ ! -d "$patch_root" ]]; then
    echo "Missing Waydroid patch queue: $patch_root" >&2
    exit 1
fi

finish_project() {
    if [[ -n "$current_project" && "$skip_project" == false ]]; then
        git -C "$android_root/$current_project" tag -f "$tag_name"
    fi
}

while IFS= read -r relative_patch; do
    project_path="${relative_patch%/*}"

    if [[ "$project_path" != "$current_project" ]]; then
        finish_project
        current_project="$project_path"
        mode="$(awk -F '\t' -v project="$project_path" \
            '$1 == project { print $2; exit }' "$source_dir/projects.tsv")"
        skip_project=false

        # Published forks were created on top of base-patches-36 and already
        # contain these changes.  Their release checkouts are intentionally
        # shallow, so the original Waydroid commits are not visible to the
        # upstream patch script's history-based duplicate detection.
        if [[ "$mode" == "fork" ]]; then
            echo "Contained in fork: $project_path"
            skip_project=true
        elif git -C "$android_root/$project_path" rev-parse -q --verify \
            "refs/tags/$tag_name" >/dev/null; then
            echo "Current: $project_path"
            skip_project=true
        else
            echo "Applying Waydroid patches: $project_path"
        fi
    fi

    if [[ "$skip_project" == false ]]; then
        if ! git -C "$android_root/$project_path" am -3 \
            "$patch_root/$relative_patch"; then
            git -C "$android_root/$project_path" am --abort || true
            exit 1
        fi
    fi
done < <(
    cd "$patch_root"
    find . -type f -name '*.patch' -printf '%P\n' | sort
)

finish_project
echo "Waydroid base-patches-36 applied to non-fork projects"
