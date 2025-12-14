#!/usr/bin/env bash
set -euo pipefail

main() {
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <deployment_dir> <cos_host> [max_attempts] [sleep_seconds]" >&2
        exit 1
    fi

    local deployment_dir="$1"
    local cos_host="$2"
    local max_attempts="${3:-100}"
    local sleep_seconds="${4:-5}"

    local ssh_opts=(-F "$deployment_dir/ssh_config" -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10)

    local info state connectible last_error
    local attempt=1
    echo "Starting DB check/start sequence for $cos_host (max_attempts=$max_attempts sleep=$sleep_seconds)"
    while [[ $attempt -le $max_attempts ]]; do
        info=$(ssh "${ssh_opts[@]}" "$cos_host" 'confd_client db_info db_name: Exasol -j' 2>/dev/null || true)
        if [[ -n "$info" ]]; then
            state=$(printf "%s" "$info" | jq -r ".state" 2>/dev/null || echo unknown)
            connectible=$(printf "%s" "$info" | jq -r ".connectible" 2>/dev/null || echo unknown)
        else
            state="unknown"
            connectible="unknown"
        fi

        echo "attempt=$attempt state=$state connectible=$connectible"

        if [[ "$state" == "running" && "${connectible,,}" == "yes" ]]; then
            # Also verify DB port responds
            db_response=$(
                ssh "${ssh_opts[@]}" "$cos_host" 'curl -sk --max-time 5 "https://localhost:8563/" 2>/dev/null' 2>/dev/null || true
            )
            if [[ -n "$db_response" && ( "$db_response" == *"status"* || "$db_response" == *"WebSocket"* || "$db_response" == *"error"* ) ]]; then
                echo "DB is running, connectible, and HTTP responds"
                return 0
            fi

            # Running/connectible but HTTP check failed: restart database
            echo "HTTP check failed while running/connectible; stopping DB to restart"
            ssh "${ssh_opts[@]}" "$cos_host" 'confd_client db_stop db_name: Exasol' || true
            # Wait for setup before retrying start
            for _ in $(seq 1 20); do
                info=$(ssh "${ssh_opts[@]}" "$cos_host" 'confd_client db_info db_name: Exasol -j' 2>/dev/null || true)
                echo "Waiting for setup state before restart, info_raw=$info"
                if [[ -n "$info" ]]; then
                    state=$(printf "%s" "$info" | jq -r ".state" 2>/dev/null || echo unknown)
                else
                    state="unknown"
                fi
                if [[ "$state" == "setup" ]]; then
                    echo "DB reached setup state after stop"
                    break
                fi
                sleep "$sleep_seconds"
            done
            # Force a restart in next loop iteration
            sleep "$sleep_seconds"
            attempt=$((attempt + 1))
            continue
        fi

        # If still in stopping/starting transient, wait
        if [[ "$state" == "stopping" || "$state" == "starting" ]]; then
            echo "State $state, waiting before retry"
            sleep "$sleep_seconds"
            attempt=$((attempt + 1))
            continue
        fi

        # If in setup or any other non-running state, try to start now
        echo "Attempting db_start"
        if ! ssh "${ssh_opts[@]}" "$cos_host" 'confd_client db_start db_name: Exasol'; then
            last_error="db_start failed"
        fi

        sleep "$sleep_seconds"
        attempt=$((attempt + 1))
    done

    echo "${last_error:-database did not reach running/connectible}" >&2
    return 1
}

main "$@"
