#!/usr/bin/env bash
# State management functions

# Include guard
if [[ -n "${__EXASOL_STATE_SH_INCLUDED__:-}" ]]; then
    return 0
fi
readonly __EXASOL_STATE_SH_INCLUDED__=1

# Source common functions
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/common.sh"

# State file names
readonly STATE_FILE=".exasol.json"
readonly LOCK_FILE=".exasolLock.json"
readonly VARS_FILE="variables.auto.tfvars"

# Deployment states
readonly STATE_INITIALIZED="initialized"
readonly STATE_DEPLOYMENT_IN_PROGRESS="deployment_in_progress"
readonly STATE_DEPLOYMENT_FAILED="deployment_failed"
readonly STATE_DATABASE_CONNECTION_FAILED="database_connection_failed"
readonly STATE_DATABASE_READY="database_ready"

# Export state constants for use in other scripts
export STATE_INITIALIZED STATE_DEPLOYMENT_IN_PROGRESS STATE_DEPLOYMENT_FAILED \
       STATE_DATABASE_CONNECTION_FAILED STATE_DATABASE_READY

# Initialize state file
state_init() {
    local deploy_dir="$1"
    local db_version="$2"
    local architecture="$3"
    local cloud_provider="${4:-aws}"  # Default to aws for backward compatibility

    local state_file="$deploy_dir/$STATE_FILE"

    if [[ -f "$state_file" ]]; then
        log_warn "State file already exists: $state_file"
        return 1
    fi

    cat > "$state_file" <<EOF
{
  "version": "1.0",
  "status": "$STATE_INITIALIZED",
  "db_version": "$db_version",
  "architecture": "$architecture",
  "cloud_provider": "$cloud_provider",
  "created_at": "$(get_timestamp)",
  "updated_at": "$(get_timestamp)"
}
EOF

    log_debug "Created state file: $state_file"
}

# Read state
state_read() {
    local deploy_dir="$1"
    local key="$2"

    local state_file="$deploy_dir/$STATE_FILE"

    if [[ ! -f "$state_file" ]]; then
        log_error "State file not found: $state_file"
        return 1
    fi

    jq -r ".$key // empty" "$state_file"
}

# Update state
state_update() {
    local deploy_dir="$1"
    local key="$2"
    local value="$3"

    local state_file="$deploy_dir/$STATE_FILE"

    if [[ ! -f "$state_file" ]]; then
        log_error "State file not found: $state_file"
        return 1
    fi

    local temp_file="${state_file}.tmp"

    jq --arg key "$key" --arg value "$value" --arg updated "$(get_timestamp)" \
        '.[$key] = $value | .updated_at = $updated' \
        "$state_file" > "$temp_file"

    mv "$temp_file" "$state_file"
    log_debug "Updated state: $key = $value"
}

# Set deployment status
state_set_status() {
    local deploy_dir="$1"
    local status="$2"

    state_update "$deploy_dir" "status" "$status"
}

# Get deployment status
state_get_status() {
    local deploy_dir="$1"

    state_read "$deploy_dir" "status"
}

# Check if lock exists
lock_exists() {
    local deploy_dir="$1"
    local lock_file="$deploy_dir/$LOCK_FILE"

    [[ -f "$lock_file" ]]
}

# Create lock file
lock_create() {
    local deploy_dir="$1"
    local operation="$2"

    local lock_file="$deploy_dir/$LOCK_FILE"

    if lock_exists "$deploy_dir"; then
        log_error "Lock file already exists: $lock_file"
        log_error "Another operation may be in progress."
        return 1
    fi

    cat > "$lock_file" <<EOF
{
  "operation": "$operation",
  "pid": $$,
  "started_at": "$(get_timestamp)",
  "hostname": "$(hostname)"
}
EOF

    log_debug "Created lock file: $lock_file"
}

# Remove lock file
lock_remove() {
    local deploy_dir="$1"
    local lock_file="$deploy_dir/$LOCK_FILE"

    if [[ -f "$lock_file" ]]; then
        rm -f "$lock_file"
        log_debug "Removed lock file: $lock_file"
    fi
}

# Remove lock if PID is no longer running
cleanup_stale_lock() {
    local deploy_dir="$1"
    local lock_file="$deploy_dir/$LOCK_FILE"

    if [[ ! -f "$lock_file" ]]; then
        return 0
    fi

    local pid
    pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null || echo "")

    if [[ -z "$pid" ]]; then
        log_warn "Removing stale lock without PID information: $lock_file"
        rm -f "$lock_file"
        return 0
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        log_warn "Removing stale lock (PID $pid no longer running)"
        rm -f "$lock_file"
    fi
}

# Get lock info
lock_info() {
    local deploy_dir="$1"
    local key="$2"

    local lock_file="$deploy_dir/$LOCK_FILE"

    if [[ ! -f "$lock_file" ]]; then
        return 1
    fi

    jq -r ".$key // empty" "$lock_file"
}

# Wait for lock to be released (with timeout)
lock_wait() {
    local deploy_dir="$1"
    local timeout="${2:-300}"  # Default 5 minutes
    local elapsed=0

    while lock_exists "$deploy_dir"; do
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timeout waiting for lock to be released"
            return 1
        fi

        log_info "Waiting for lock to be released... ($elapsed/$timeout seconds)"
        sleep 5
        elapsed=$((elapsed + 5))
    done
}

# Get deployment status with lock detection
get_deployment_status() {
    local deploy_dir="$1"

    # Check if deployment directory exists
    if [[ ! -d "$deploy_dir" ]]; then
        echo "error: deployment directory not found"
        return 1
    fi

    # Check if state file exists
    if [[ ! -f "$deploy_dir/$STATE_FILE" ]]; then
        echo "error: not a deployment directory"
        return 1
    fi

    cleanup_stale_lock "$deploy_dir"

    # If lock exists, operation is in progress
    if lock_exists "$deploy_dir"; then
        local operation
        operation=$(lock_info "$deploy_dir" "operation")
        echo "${operation}_in_progress"
        return 0
    fi

    # Otherwise, return status from state file
    state_get_status "$deploy_dir"
}

# Write variables file
write_variables_file() {
    local deploy_dir="$1"
    shift
    local vars_file="$deploy_dir/$VARS_FILE"

    # Write variables as HCL
    {
        for var in "$@"; do
            local key="${var%%=*}"
            local value="${var#*=}"

            # Check if value is a number or boolean
            if [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
                echo "$key = $value"
            else
                echo "$key = \"$value\""
            fi
        done
    } > "$vars_file"

    log_debug "Created variables file: $vars_file"
}
