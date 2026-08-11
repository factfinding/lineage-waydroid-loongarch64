#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd "$script_dir/.." && pwd)"
android_root="${1:-$PWD}"

while IFS=$'\t' read -r project_path mode upstream locator reference_head base_commit reference_tree; do
    [[ -z "$project_path" || "$project_path" == \#* ]] && continue
    [[ "$mode" != "patch" ]] && continue

    project_dir="$android_root/$project_path"
    patch_dir="$source_dir/$locator"

    if [[ ! -d "$project_dir/.git" ]]; then
        echo "Missing Git project: $project_path" >&2
        exit 1
    fi
    if [[ "$(git -C "$project_dir" rev-parse 'HEAD^{tree}')" == "$reference_tree" ]]; then
        echo "Current: $project_path"
        continue
    fi
    if ! git -C "$project_dir" merge-base --is-ancestor "$base_commit" HEAD; then
        echo "Unexpected base for $project_path (need ancestor $base_commit)" >&2
        exit 1
    fi

    echo "Applying: $project_path"
    git -C "$project_dir" am "$patch_dir"/*.patch

    actual_tree="$(git -C "$project_dir" rev-parse 'HEAD^{tree}')"
    if [[ "$actual_tree" != "$reference_tree" ]]; then
        echo "Tree mismatch for $project_path: $actual_tree != $reference_tree" >&2
        exit 1
    fi
done < "$source_dir/projects.tsv"
