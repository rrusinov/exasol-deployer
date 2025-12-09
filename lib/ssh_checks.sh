#!/usr/bin/env bash
# SSH connectivity helper functions

if [[ -n "${__EXASOL_SSH_CHECKS_SH_INCLUDED__:-}" ]]; then
    return 0
fi
readonly __EXASOL_SSH_CHECKS_SH_INCLUDED__=1

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"

# Sanitize integer input with a minimum bound; fall back to provided default
_ssh_resolve_int() {
    local candidate="$1"
    local default_value="$2"
    local min_value="${3:-0}"

    if [[ "$candidate" =~ ^[0-9]+$ ]] && (( candidate >= min_value )); then
        echo "$candidate"
    else
        echo "$default_value"
    fi
}

# Parse command string into array with a sensible default
_ssh_parse_command() {
    local command_string="$1"
    local array_name="$2"
    # shellcheck disable=SC2178
    local -n command_ref="$array_name"
    command_ref=()
    if [[ -n "$command_string" ]]; then
        read -r -a command_ref <<<"$command_string"
    fi
    if [[ ${#command_ref[@]} -eq 0 ]]; then
        command_ref=("true")
    fi
}

# Run an SSH command with retry handling; sets SSH_RETRY_* globals
ssh_run_with_retries() {
    local ssh_config="$1"
    local host="$2"
    local timeout_input="${3:-10}"
    local attempts_input="${4:-1}"
    local retry_delay_input="${5:-0}"
    shift 5
    local -a command=("$@")

    local timeout
    timeout=$(_ssh_resolve_int "$timeout_input" 10 1)
    local attempts
    attempts=$(_ssh_resolve_int "$attempts_input" 1 1)
    local retry_delay
    retry_delay=$(_ssh_resolve_int "$retry_delay_input" 0 0)

    if [[ ${#command[@]} -eq 0 ]]; then
        command=("true")
    fi

    declare -g SSH_RETRY_ATTEMPT_COUNT=0
    declare -g SSH_RETRY_LAST_ERROR=""

    local attempt
    local ssh_output=""
    for (( attempt = 1; attempt <= attempts; attempt++ )); do
        SSH_RETRY_ATTEMPT_COUNT=$attempt
        if ssh_output=$(ssh -F "$ssh_config" \
            -o BatchMode=yes \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout="$timeout" \
            "$host" "${command[@]}" 2>&1); then
            SSH_RETRY_LAST_ERROR=""
            return 0
        fi

        SSH_RETRY_LAST_ERROR="$ssh_output"
        if (( attempt < attempts )) && (( retry_delay > 0 )); then
            sleep "$retry_delay"
        fi
    done

    if [[ -n "$SSH_RETRY_LAST_ERROR" ]]; then
        SSH_RETRY_LAST_ERROR=$(echo "$SSH_RETRY_LAST_ERROR" | tr '\r' ' ' | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')
    fi
    return 1
}

# Worker used by the parallel connectivity check

_ssh_connectivity_worker() {
    local ssh_config="$1"
    local host="$2"
    local timeout="$3"
    local attempts="$4"
    local retry_delay="$5"
    local command_string="$6"
    local result_file="$7"

    local -a command_tokens
    _ssh_parse_command "$command_string" command_tokens

    if ssh_run_with_retries "$ssh_config" "$host" "$timeout" "$attempts" "$retry_delay" "${command_tokens[@]}"; then
        cat >"$result_file" <<EOF
status=success
attempt=$SSH_RETRY_ATTEMPT_COUNT
EOF
        return 0
    fi

    cat >"$result_file" <<EOF
status=failure
attempt=$SSH_RETRY_ATTEMPT_COUNT
error=$SSH_RETRY_LAST_ERROR
EOF
    return 1
}

# Read worker result, log outcome, and populate global arrays
_ssh_process_result() {
    local host="$1"
    local result_file="$2"

    local status=""
    local attempt=""
    local error_message=""

    if [[ -f "$result_file" ]]; then
        while IFS='=' read -r key value; do
            case "$key" in
                status) status="$value" ;;
                attempt) attempt="$value" ;;
                error) error_message="$value" ;;
            esac
        done <"$result_file"
    fi

    if [[ "$status" == "success" ]]; then
        log_info "SSH connectivity to $host passed (attempt ${attempt:-1})"
        SSH_CONNECTIVITY_SUCCESS_HOSTS+=("$host")
        return 0
    fi

    log_warn "SSH connectivity to $host failed after ${attempt:-0} attempt(s)"
    if [[ -n "$error_message" ]]; then
        log_debug "SSH last error for $host: $error_message"
    fi
    SSH_CONNECTIVITY_FAILED_HOSTS+=("$host")
    return 1
}

# Wait for the oldest background job to finish and process its result
_ssh_wait_for_first_job() {
    # shellcheck disable=SC2178
    local -n pids_ref="$1"
    # shellcheck disable=SC2178
    local -n hosts_ref="$2"
    # shellcheck disable=SC2178
    local -n result_files_ref="$3"

    local pid="${pids_ref[0]}"
    local host="${hosts_ref[0]}"

    wait "$pid" 2>/dev/null || true

    local result_file="${result_files_ref[$host]}"
    _ssh_process_result "$host" "$result_file"
    rm -f "$result_file" 2>/dev/null || true

           pids_ref=("${pids_ref[@]:1}")
           hosts_ref=("${hosts_ref[@]:1}")
}

# Check SSH connectivity for the provided hosts (optionally in parallel)
ssh_check_connectivity() {
    local ssh_config="$1"
    local grace_seconds_input="$2"
    local attempts_input="$3"
    local retry_delay_input="$4"
    local timeout_input="$5"
    local parallelism_input="${6:-1}"
    local command_string="${7:-}"
    shift 7
    local -a hosts=("$@")

    if [[ ${#hosts[@]} -eq 0 ]]; then
        log_warn "No hosts provided for SSH connectivity check"
        return 0
    fi

    if [[ ! -f "$ssh_config" ]]; then
        log_warn "SSH config not found: $ssh_config"
        return 1
    fi

    local grace_seconds
    grace_seconds=$(_ssh_resolve_int "$grace_seconds_input" 0 0)

    if (( grace_seconds > 0 )); then
        log_info "Waiting ${grace_seconds}s before running SSH connectivity checks..."
        sleep "$grace_seconds"
    fi

    local attempts
    attempts=$(_ssh_resolve_int "$attempts_input" 10 1)
    local retry_delay
    retry_delay=$(_ssh_resolve_int "$retry_delay_input" 10 0)
    local timeout
    timeout=$(_ssh_resolve_int "$timeout_input" 10 1)

    local parallelism
    parallelism=$(_ssh_resolve_int "$parallelism_input" "${#hosts[@]}" 1)
    if (( parallelism > ${#hosts[@]} )); then
        parallelism=${#hosts[@]}
    fi

    if [[ -z "$command_string" ]]; then
        command_string="true"
    fi

    log_info "Testing SSH connectivity for ${#hosts[@]} host(s) (parallelism: $parallelism, timeout: ${timeout}s, attempts: $attempts)..."

    declare -ag SSH_CONNECTIVITY_SUCCESS_HOSTS
    SSH_CONNECTIVITY_SUCCESS_HOSTS=()
    declare -ag SSH_CONNECTIVITY_FAILED_HOSTS
    SSH_CONNECTIVITY_FAILED_HOSTS=()

    local result_dir
    result_dir=$(get_runtime_temp_dir)
    local -A host_result_files=()
    local -a active_pids=()
    local -a active_hosts=()

    local host
    for host in "${hosts[@]}"; do
        local sanitized_host="${host//[[:space:]]/}"
        [[ -z "$sanitized_host" ]] && continue

        local result_file="$result_dir/ssh_check_${sanitized_host}_$$_$RANDOM.tmp"
        host_result_files["$sanitized_host"]="$result_file"

        (
            _ssh_connectivity_worker "$ssh_config" "$sanitized_host" "$timeout" "$attempts" "$retry_delay" "$command_string" "$result_file"
        ) &
        active_pids+=("$!")
        active_hosts+=("$sanitized_host")

        while (( ${#active_pids[@]} >= parallelism )); do
            _ssh_wait_for_first_job active_pids active_hosts host_result_files
        done
    done

    while (( ${#active_pids[@]} > 0 )); do
        _ssh_wait_for_first_job active_pids active_hosts host_result_files
    done

    if [[ ${#SSH_CONNECTIVITY_FAILED_HOSTS[@]} -eq 0 ]]; then
        log_info "SSH connectivity check completed successfully."
        return 0
    fi

    log_warn "SSH connectivity failed for: ${SSH_CONNECTIVITY_FAILED_HOSTS[*]}"
    return 1
}

# Return host|ansible_host pairs for the requested inventory group
ssh_inventory_collect_host_entries() {
    local inventory_file="$1"
    local group_name="${2:-exasol_nodes}"

    if [[ ! -f "$inventory_file" ]]; then
        return 1
    fi

    awk -v target="$group_name" '
        BEGIN { section = "" }
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*#/ { next }
        /^\[/ {
            section = $0
            gsub(/^\[/, "", section)
            gsub(/\].*$/, "", section)
            next
        }
        section == target {
            host = $1
            ansible_host = ""
            for (i = 2; i <= NF; i++) {
                if ($i ~ /^ansible_host=/) {
                    split($i, kv, "=")
                    ansible_host = kv[2]
                    break
                }
            }
            gsub(/[[:space:]]+/, "", host)
            gsub(/[[:space:]]+/, "", ansible_host)
            if (host != "") {
                print host "|" ansible_host
            }
        }
    ' "$inventory_file"
}

# Convenience helper to list host names only
ssh_inventory_collect_hosts() {
    local inventory_file="$1"
    local group_name="${2:-exasol_nodes}"
    ssh_inventory_collect_host_entries "$inventory_file" "$group_name" | cut -d'|' -f1
}

# Run connectivity checks for all hosts from an inventory file
ssh_check_inventory_connectivity() {
    local inventory_file="$1"
    local ssh_config="$2"
    local grace_seconds="$3"
    local attempts="$4"
    local retry_delay="$5"
    local timeout="$6"
    local parallelism="${7:-1}"
    local command_string="${8:-}"

    if [[ ! -f "$inventory_file" ]]; then
        log_warn "Inventory file not found: $inventory_file"
        return 1
    fi

    local -a hosts=()
    while IFS= read -r host; do
        [[ -n "$host" ]] && hosts+=("$host")
    done < <(ssh_inventory_collect_hosts "$inventory_file")

    if [[ ${#hosts[@]} -eq 0 ]]; then
        log_warn "No hosts found in $inventory_file; skipping SSH connectivity check"
        return 0
    fi

    ssh_check_connectivity "$ssh_config" "$grace_seconds" "$attempts" "$retry_delay" "$timeout" "$parallelism" "$command_string" "${hosts[@]}"
    return $?
}
