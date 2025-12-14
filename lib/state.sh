#!/usr/bin/env bash
# State management functions

# Include guard
if [[ -n "${__EXASOL_STATE_SH_INCLUDED__:-}" ]]; then
    return 0
fi
readonly __EXASOL_STATE_SH_INCLUDED__=1

# Source common functions
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"

# State file names
readonly STATE_FILE=".exasol.json"
readonly LOCK_FILE=".exasolLock.json"
readonly VARS_FILE="variables.auto.tfvars"

# Deployment states
readonly STATE_INITIALIZED="initialized"
readonly STATE_DEPLOY_IN_PROGRESS="deploy_in_progress"
readonly STATE_DEPLOYMENT_FAILED="deployment_failed"
readonly STATE_DATABASE_CONNECTION_FAILED="database_connection_failed"
readonly STATE_DATABASE_READY="database_ready"
readonly STATE_DESTROY_IN_PROGRESS="destroy_in_progress"
readonly STATE_DESTROY_FAILED="destroy_failed"
readonly STATE_DESTROYED="destroyed"
readonly STATE_STOPPED="stopped"
readonly STATE_STARTED="started"
readonly STATE_START_IN_PROGRESS="start_in_progress"
readonly STATE_START_FAILED="start_failed"
readonly STATE_STOP_IN_PROGRESS="stop_in_progress"
readonly STATE_STOP_FAILED="stop_failed"

# Export state constants for use in other scripts
export STATE_INITIALIZED STATE_DEPLOY_IN_PROGRESS STATE_DEPLOYMENT_FAILED \
       STATE_DATABASE_CONNECTION_FAILED STATE_DATABASE_READY STATE_DESTROY_IN_PROGRESS \
       STATE_DESTROY_FAILED STATE_DESTROYED STATE_STOPPED STATE_STARTED \
       STATE_START_IN_PROGRESS STATE_START_FAILED STATE_STOP_IN_PROGRESS STATE_STOP_FAILED

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

    "${JQ_BINARY:-jq}" -r ".$key // empty" "$state_file"
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

# Validate lock file structure and content
validate_lock_file() {
    local lock_file="$1"
    
    # Check if file exists and is readable
    [[ -f "$lock_file" && -r "$lock_file" ]] || return 1
    
    # Validate JSON structure and extract PID safely
    local jq_output
    jq_output=$("${JQ_BINARY:-jq}" -r '.pid // empty' "$lock_file" 2>/dev/null) || return 1
    
    # Check if PID field exists and is numeric
    [[ -n "$jq_output" && "$jq_output" =~ ^[0-9]+$ ]] || return 1
    
    # Check if PID process is still running
    kill -0 "$jq_output" 2>/dev/null || return 1
    
    # Return the valid PID
    echo "$jq_output"
    return 0
}

# Create lock file with validation and retry logic
lock_create() {
    local deploy_dir="$1"
    local operation="$2"

    local lock_file="$deploy_dir/$LOCK_FILE"

    if [[ "${EXASOL_LOG_LEVEL:-}" == "debug" ]]; then
        log_debug "lock_create: attempting for $operation at $lock_file"
    fi

    # If lock file doesn't exist, proceed to creation
    if [[ ! -f "$lock_file" ]]; then
        if [[ "${EXASOL_LOG_LEVEL:-}" == "debug" ]]; then
            log_debug "lock_create: no existing lock file, proceeding to creation"
        fi
    else
        # Lock file exists - validate it
        local valid_pid
        if valid_pid=$(validate_lock_file "$lock_file"); then
            # Lock file is valid and owned by active process
            log_error "Lock already held by active process: PID $valid_pid"
            return 1
        else
            # Lock file is invalid - start retry period
            log_warn "Invalid lock file detected, starting 5-second validation period"
            
            local retry_count=0
            local max_retries=5
            
            while [[ $retry_count -lt $max_retries ]]; do
                sleep 1
                retry_count=$((retry_count + 1))
                
                if valid_pid=$(validate_lock_file "$lock_file"); then
                    # File became valid during retry period
                    log_error "Lock became valid during retry, held by active process: PID $valid_pid"
                    return 1
                fi
                
                [[ "${EXASOL_LOG_LEVEL:-}" == "debug" ]] && log_debug "lock_create: retry $retry_count/$max_retries - lock file still invalid"
            done
            
            # After retry period, file is still invalid - remove it
            log_warn "Lock file remains invalid after 5 seconds, removing stale/corrupted lock: $lock_file"
            rm -f "$lock_file"
        fi
    fi

    # Try to create lock atomically (noclobber)
    if ! ( set -o noclobber; : > "$lock_file" ) 2>/dev/null; then
        if [[ -f "$lock_file" ]]; then
            log_error "Lock file already exists: $lock_file"
            log_error "Another operation may be in progress."
            return 1
        fi
        log_error "Unable to create lock file (permission or FS error): $lock_file"
        return 1
    fi

    [[ "${EXASOL_LOG_LEVEL:-}" == "debug" ]] && log_debug "lock_create: noclobber succeeded for $lock_file"

    cat > "$lock_file" <<EOF
{
  "operation": "$operation",
  "pid": $$,
  "started_at": "$(get_timestamp)",
  "hostname": "$(hostname)"
}
EOF

    # If another process removed our just-created lock, treat as failure
    if [[ ! -f "$lock_file" ]]; then
        log_error "Failed to persist lock file: $lock_file"
        return 1
    fi

    # Verify the written JSON to ensure we own the lock and it matches the PID
    local written_pid
    written_pid=$("${JQ_BINARY:-jq}" -r '.pid // empty' "$lock_file" 2>/dev/null || echo "")
    if [[ -z "$written_pid" || "$written_pid" -ne $$ ]]; then
        log_error "Lock file content mismatch, removing lock: $lock_file"
        rm -f "$lock_file"
        return 1
    fi

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

    # Use the new validation function to check lock validity
    local valid_pid
    if valid_pid=$(validate_lock_file "$lock_file"); then
        # Lock file is valid and process is running - don't remove
        return 0
    else
        # Lock file is invalid or process is not running - remove it
        log_warn "Removing invalid or stale lock: $lock_file"
        rm -f "$lock_file"
        return 0
    fi
}

# Get lock info
lock_info() {
    local deploy_dir="$1"
    local key="${2:-}"

    local lock_file="$deploy_dir/$LOCK_FILE"

    if [[ ! -f "$lock_file" ]]; then
        return 1
    fi

    if [[ -z "$key" ]]; then
        # If no key specified, return entire lock file
        cat "$lock_file"
    else
        # Return specific key value
        "${JQ_BINARY:-jq}" -r ".$key // empty" "$lock_file"
    fi
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

# Validate state transition for start command
validate_start_transition() {
    local current_state="$1"

    case "$current_state" in
        "$STATE_STOPPED"|"$STATE_START_FAILED")
            # Valid states to start from
            return 0
            ;;
        "$STATE_DEPLOY_IN_PROGRESS"|"$STATE_DESTROY_IN_PROGRESS"|"$STATE_STOP_IN_PROGRESS"|"$STATE_START_IN_PROGRESS")
            log_error "Cannot start: another operation is in progress (state: $current_state)"
            return 1
            ;;
        "$STATE_DESTROYED")
            log_error "Cannot start: deployment has been destroyed"
            return 1
            ;;
        "$STATE_DATABASE_READY")
            log_error "Cannot start: database is already running (state: $current_state)"
            return 1
            ;;
        "$STATE_INITIALIZED"|"$STATE_DEPLOYMENT_FAILED"|"$STATE_DATABASE_CONNECTION_FAILED")
            log_error "Cannot start: deployment is not in a stoppable state (state: $current_state)"
            log_info "Please run 'exasol deploy' first to fully deploy the database"
            return 1
            ;;
        *)
            log_error "Cannot start from unknown state: $current_state"
            return 1
            ;;
    esac
}

# Validate state transition for stop command
validate_stop_transition() {
    local current_state="$1"

    case "$current_state" in
        "$STATE_DATABASE_READY"|"$STATE_DATABASE_CONNECTION_FAILED"|"$STATE_STOP_FAILED"|"$STATE_STARTED")
            # Valid states to stop from
            return 0
            ;;
        "$STATE_DEPLOY_IN_PROGRESS"|"$STATE_DESTROY_IN_PROGRESS"|"$STATE_STOP_IN_PROGRESS"|"$STATE_START_IN_PROGRESS")
            log_error "Cannot stop: another operation is in progress (state: $current_state)"
            return 1
            ;;
        "$STATE_DESTROYED")
            log_error "Cannot stop: deployment has been destroyed"
            return 1
            ;;
        "$STATE_STOPPED")
            log_error "Cannot stop: database is already stopped (state: $current_state)"
            return 1
            ;;
        "$STATE_INITIALIZED"|"$STATE_DEPLOYMENT_FAILED"|"$STATE_START_FAILED")
            log_error "Cannot stop: database is not running (state: $current_state)"
            return 1
            ;;
        *)
            log_error "Cannot stop from unknown state: $current_state"
            return 1
            ;;
    esac
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
