#!/usr/bin/env bash
set -euo pipefail

main() {
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <deployment_dir> <target_host> [threshold_seconds]" >&2
        exit 1
    fi

    local deployment_dir="$1"
    local target_host="$2"
    local threshold="${3:-300}"

    local uptime_secs
    uptime_secs=$(ssh -F "$deployment_dir/ssh_config" -n -T -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$target_host" "cat /proc/uptime | cut -d. -f1")
    echo "uptime=$uptime_secs"
    if [[ "$uptime_secs" -lt "$threshold" ]]; then
        return 0
    fi
    return 1
}

main "$@"
