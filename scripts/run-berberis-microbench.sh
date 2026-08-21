#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
integration_root="$(cd "${script_dir}/.." && pwd)"
workspace_root="$(cd "${integration_root}/.." && pwd)"
android_root="${ANDROID_ROOT:-${workspace_root}/lineage-waydroid-23.2}"
user_host="${LA64_USER_HOST:-la64-device}"
root_host="${LA64_ROOT_HOST:-la64-root}"
iterations=500000
skip_build=false
start_container=false
output_dir=""
baseline=""

usage() {
    cat <<'EOF'
Usage: scripts/run-berberis-microbench.sh [options]

Options:
  --iterations N   Timed iterations per scenario (default: 500000)
  --output DIR     Result directory (default: ../logs/berberis-microbench-TIME)
  --baseline FILE  Compare against an earlier benchmarks.jsonl and gate at 3%
  --skip-build     Reuse existing test and benchmark binaries
  --start-container
                   Start the noctis Waydroid session when LXC is stopped
  -h, --help       Show this help

Environment:
  ANDROID_ROOT     Android source tree
  LA64_USER_HOST   Unprivileged SSH alias (default: la64-device)
  LA64_ROOT_HOST   Root SSH alias (default: la64-root)
EOF
}

while (($#)); do
    case "$1" in
        --iterations)
            iterations="${2:?missing iteration count}"
            shift 2
            ;;
        --output)
            output_dir="${2:?missing output directory}"
            shift 2
            ;;
        --baseline)
            baseline="${2:?missing baseline file}"
            shift 2
            ;;
        --skip-build)
            skip_build=true
            shift
            ;;
        --start-container)
            start_container=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ ! "${iterations}" =~ ^[1-9][0-9]*$ ]]; then
    echo "--iterations must be a positive integer" >&2
    exit 2
fi

if [[ -z "${output_dir}" ]]; then
    output_dir="${workspace_root}/logs/berberis-microbench-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "${output_dir}"

if [[ "${skip_build}" == false ]]; then
    (
        cd "${android_root}"
        source build/envsetup.sh >/dev/null
        lunch lineage_waydroid_loongarch64-bp4a-userdebug >/dev/null
        m -j8 \
            berberis_runtime_arm64_loongarch64_tests \
            berberis_runtime_arm64_loongarch64_microbench
    ) 2>&1 | tee "${output_dir}/build.log"
fi

product_out="${android_root}/out/target/product/waydroid_loongarch64"
test_binary="${product_out}/data/nativetest64/berberis_runtime_arm64_loongarch64_tests/berberis_runtime_arm64_loongarch64_tests"
bench_binary="${product_out}/system/bin/berberis_runtime_arm64_loongarch64_microbench"
for binary in "${test_binary}" "${bench_binary}"; do
    if [[ ! -x "${binary}" ]]; then
        echo "Missing executable: ${binary}" >&2
        exit 1
    fi
done

container_state="$(ssh "${root_host}" \
    "lxc-info -P /var/lib/waydroid/lxc -n waydroid -sH" 2>/dev/null || true)"
if [[ "${container_state}" != "RUNNING" && "${start_container}" == true ]]; then
    ssh "${user_host}" \
        'nohup env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus waydroid session start > /home/noctis/waydroid-session.log 2>&1 < /dev/null &'
    for _ in {1..60}; do
        container_state="$(ssh "${root_host}" \
            "lxc-info -P /var/lib/waydroid/lxc -n waydroid -sH" 2>/dev/null || true)"
        [[ "${container_state}" == "RUNNING" ]] && break
        sleep 1
    done
fi
if [[ "${container_state}" != "RUNNING" ]]; then
    echo "Waydroid container is ${container_state:-unavailable}; start the user session or pass --start-container." >&2
    exit 1
fi

remote_suffix="$(date +%Y%m%d-%H%M%S)-$$"
remote_test="/home/noctis/berberis-la64-tests-${remote_suffix}"
remote_bench="/home/noctis/berberis-la64-microbench-${remote_suffix}"
scp "${test_binary}" "${user_host}:${remote_test}"
scp "${bench_binary}" "${user_host}:${remote_bench}"

ssh "${root_host}" \
    "lxc-attach -P /var/lib/waydroid/lxc -n waydroid -- /system/bin/sh -c 'cat > /data/local/tmp/berberis-la64-tests && chmod 0755 /data/local/tmp/berberis-la64-tests' < ${remote_test}"
ssh "${root_host}" \
    "lxc-attach -P /var/lib/waydroid/lxc -n waydroid -- /system/bin/sh -c 'cat > /data/local/tmp/berberis-la64-microbench && chmod 0755 /data/local/tmp/berberis-la64-microbench' < ${remote_bench}"

echo "Running correctness suite..."
ssh "${root_host}" \
    "lxc-attach -P /var/lib/waydroid/lxc -n waydroid -- /data/local/tmp/berberis-la64-tests" \
    2>&1 | tee "${output_dir}/correctness.log"

echo "Running microbenchmarks..."
ssh "${root_host}" \
    "lxc-attach -P /var/lib/waydroid/lxc -n waydroid -- /data/local/tmp/berberis-la64-microbench --benchmark all --iterations ${iterations}" \
    | tee "${output_dir}/benchmarks.jsonl"

benchmarks=(gpr_cached simd_cached conditional_fallthrough mixed)
events="cycles:u,instructions:u,branches:u,branch-misses:u"
for benchmark in "${benchmarks[@]}"; do
    echo "Collecting perf stat for ${benchmark}..."
    ssh "${root_host}" \
        "perf stat -x, -e ${events} -- lxc-attach -P /var/lib/waydroid/lxc -n waydroid -- /data/local/tmp/berberis-la64-microbench --benchmark ${benchmark} --iterations ${iterations}" \
        >"${output_dir}/perf-${benchmark}.jsonl" \
        2>"${output_dir}/perf-${benchmark}.csv"
done

{
    printf 'timestamp=%s\n' "$(date --iso-8601=seconds)"
    printf 'android_root=%s\n' "${android_root}"
    printf 'berberis_commit=%s\n' "$(git -C "${android_root}/frameworks/libs/binary_translation" rev-parse HEAD)"
    printf 'iterations=%s\n' "${iterations}"
    printf 'device=%s\n' "${root_host}"
} >"${output_dir}/metadata.txt"

if [[ -n "${baseline}" ]]; then
    "${script_dir}/compare-berberis-microbench.py" \
        "${baseline}" "${output_dir}/benchmarks.jsonl" \
        | tee "${output_dir}/comparison.txt"
fi

echo "Results: ${output_dir}"
