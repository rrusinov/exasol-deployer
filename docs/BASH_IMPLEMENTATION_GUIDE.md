# Bash Implementation Guide - Quick Reference

This guide provides actionable steps for implementing a bash version based on the Go source code analysis.

## Phase 1: Foundation (Core State Management)

### 1.1 Configuration Path Functions

Create file: lib/paths.sh

These functions define the locations of all configuration and state files:

get_workflow_state_file() { echo ".workflowState.json"; }
get_lock_file() { echo ".exasolLock.json"; }
get_vars_file() { echo "vars.tfvars"; }
get_plan_file() { echo "plan.tfplan"; }
get_tofu_binary() { echo "tofu"; }  # or "tofu.exe" on Windows
get_tofu_config_dir() { echo "."; }
get_exasol_config_file() { echo "exasolConfig.yaml"; }

# Helper to build full path
get_deployment_path() {
    local deployment_dir="$1"
    local filename="$2"
    echo "$deployment_dir/$filename"
}

### 1.2 JSON/YAML Read-Write Functions

Create file: lib/config.sh

read_json() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo "Error: file not found: $path" >&2
        return 1
    fi
    jq . "$path"
}

write_json() {
    local path="$1"
    local data="$2"
    local permissions="${3:-0644}"
    
    echo "$data" | jq . > "$path" || return 1
    chmod "$permissions" "$path"
}

# Utility: Find file matching glob pattern
find_file_matching() {
    local dir="$1"
    local pattern="$2"
    local matches
    
    mapfile -t matches < <(find "$dir" -maxdepth 1 -name "$pattern" 2>/dev/null)
    
    if [ ${#matches[@]} -eq 0 ]; then
        echo "Error: no file matched pattern \"$pattern\"" >&2
        return 1
    fi
    
    echo "${matches[0]}"
}

### 1.3 Workflow State Management

Create file: lib/state.sh

STATE_INITIALIZED="initialized"
STATE_FAILED="deployment_failed"
STATE_SUCCESSFUL="deployment_successful"
STATE_UNKNOWN="unknown"

read_workflow_state() {
    local state_file="$1"
    
    if [ ! -f "$state_file" ]; then
        echo "$STATE_UNKNOWN"
        return 1
    fi
    
    # Check which field is set (union type in JSON)
    if jq -e '.initialized' "$state_file" > /dev/null 2>&1; then
        echo "$STATE_INITIALIZED"
    elif jq -e '.deploymentFailed' "$state_file" > /dev/null 2>&1; then
        echo "$STATE_FAILED"
    elif jq -e '.deploymentSuccessful' "$state_file" > /dev/null 2>&1; then
        echo "$STATE_SUCCESSFUL"
    else
        echo "$STATE_UNKNOWN"
        return 1
    fi
}

write_workflow_state() {
    local state_file="$1"
    local state="$2"
    local error_msg="$3"
    
    local json
    case "$state" in
        "$STATE_INITIALIZED")
            json='{"initialized": {}}'
            ;;
        "$STATE_FAILED")
            # Escape error message for JSON
            error_msg=$(echo "$error_msg" | jq -Rs .)
            json="{\"deploymentFailed\": {\"error\": $error_msg}}"
            ;;
        "$STATE_SUCCESSFUL")
            json='{"deploymentSuccessful": {}}'
            ;;
        *)
            echo "Error: unknown state: $state" >&2
            return 1
            ;;
    esac
    
    write_json "$state_file" "$json"
}

### 1.4 File-Based Locking

Create file: lib/lock.sh

acquire_lock() {
    local lock_file="$1"
    
    if [ -f "$lock_file" ]; then
        return 1  # Lock already exists (already locked)
    fi
    
    # Create lock file with timestamp
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local json="{\"time\": \"$timestamp\"}"
    
    write_json "$lock_file" "$json" 0644
}

release_lock() {
    local lock_file="$1"
    rm -f "$lock_file"
}

is_locked() {
    local lock_file="$1"
    [ -f "$lock_file" ]
}

with_lock() {
    local lock_file="$1"
    shift
    local cmd="$@"
    
    if ! acquire_lock "$lock_file"; then
        echo "Error: deployment is currently in progress" >&2
        return 1
    fi
    
    # Ensure lock is released even if command fails
    trap "release_lock '$lock_file'" EXIT INT TERM
    
    $cmd
    local exit_code=$?
    
    release_lock "$lock_file"
    return $exit_code
}

---

## Phase 2: Validation and Directory Management

### 2.1 Deployment Directory Validation

Create file: lib/validation.sh

validate_deployment_dir() {
    local deployment_dir="$1"
    local allow_existing="${2:-false}"
    
    # Create directory if it doesn't exist
    mkdir -p "$deployment_dir" || {
        echo "Error: could not create deployment directory: $deployment_dir" >&2
        return 1
    }
    
    # Check if directory is empty
    local file_count
    file_count=$(find "$deployment_dir" -maxdepth 1 -type f | wc -l)
    
    if [ "$file_count" -gt 0 ] && [ "$allow_existing" = "false" ]; then
        echo "Error: deployment directory is not empty" >&2
        return 1
    fi
}

### 2.2 Variable Validation

Create file: lib/variables.sh

# Define known variables
declare -A KNOWN_VARIABLES=(
    [instance_type]="t3.medium"
    [region]="us-west-2"
    [cluster_size]="1"
)

declare -A REQUIRED_VARIABLES=(
    [instance_type]="true"
    [region]="false"
    [cluster_size]="false"
)

validate_variables() {
    local -n provided_vars=$1
    
    for var_name in "${!provided_vars[@]}"; do
        if [ -z "${KNOWN_VARIABLES[$var_name]+x}" ]; then
            echo "Error: unknown variable: $var_name" >&2
            return 1
        fi
    done
    
    return 0
}

write_tfvars() {
    local output_file="$1"
    shift
    local -n vars=$1
    
    {
        for var_name in "${!vars[@]}"; do
            local value="${vars[$var_name]}"
            if [[ "$value" =~ ^[0-9]+$ ]]; then
                echo "$var_name = $value"
            else
                value="${value//\"/\\\"}"
                echo "$var_name = \"$value\""
            fi
        done
    } > "$output_file"
}

---

## Phase 3: Status Command Implementation

Create file: cmd/status.sh

#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/../lib/paths.sh"
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/state.sh"
source "$(dirname "$0")/../lib/lock.sh"

status_command() {
    local deployment_dir="${1:-.}"
    
    local lock_file
    lock_file=$(get_deployment_path "$deployment_dir" "$(get_lock_file)")
    
    # Check if locked (deployment in progress)
    if is_locked "$lock_file"; then
        output_status "deployment_in_progress" "Deployment is currently in progress."
        return 0
    fi
    
    # Read workflow state
    local state_file
    state_file=$(get_deployment_path "$deployment_dir" "$(get_workflow_state_file)")
    
    if [ ! -f "$state_file" ]; then
        output_status "unknown" "No deployment state found." ""
        return 1
    fi
    
    local state
    state=$(read_workflow_state "$state_file") || {
        output_status "unknown" "" "Failed to read workflow state"
        return 1
    }
    
    case "$state" in
        "initialized")
            output_status "initialized" "Ready for deployment." ""
            ;;
        "deployment_failed")
            local error
            error=$(jq -r '.deploymentFailed.error // ""' "$state_file")
            output_status "deployment_failed" "Deployment failed." "$error"
            ;;
        "deployment_successful")
            output_status "database_ready" "The database is running and ready." ""
            ;;
        *)
            output_status "unknown" "" "Unknown state: $state"
            return 1
            ;;
    esac
}

output_status() {
    local status="$1"
    local message="${2:-}"
    local error="${3:-}"
    
    # Output JSON using jq
    printf '{"status":"%s"' "$status"
    [ -n "$message" ] && printf ',"message":"%s"' "$message"
    [ -n "$error" ] && printf ',"error":"%s"' "$error"
    printf '}\n'
}

status_command "$@"

---

## Key Implementation Checklist

PHASE 1: FOUNDATION
- [ ] Create lib/paths.sh with path constants
- [ ] Create lib/config.sh with JSON/YAML read/write
- [ ] Create lib/state.sh with workflow state management
- [ ] Create lib/lock.sh with file-based locking
- [ ] Test: State file creation and reading
- [ ] Test: Lock acquisition and release

PHASE 2: VALIDATION
- [ ] Create lib/validation.sh for directory validation
- [ ] Create lib/variables.sh for variable validation
- [ ] Test: Directory empty check
- [ ] Test: Variable validation
- [ ] Test: Variable write to tfvars format

PHASE 3: STATUS COMMAND
- [ ] Implement cmd/status.sh
- [ ] Test: Status returns correct JSON
- [ ] Test: Lock detection in status
- [ ] Test: State reading from file

PHASE 4: INIT COMMAND
- [ ] Implement cmd/init.sh
- [ ] Extract terraform files from assets
- [ ] Extract platform-specific tofu binary
- [ ] Create vars.tfvars from variables
- [ ] Write initial workflow state

PHASE 5: DEPLOY COMMAND
- [ ] Implement cmd/deploy.sh
- [ ] Lock acquisition for deploy
- [ ] Terraform init, plan, apply
- [ ] Post-deploy script execution (SSH)
- [ ] State update (success or failure)

PHASE 6: DESTROY COMMAND
- [ ] Implement cmd/destroy.sh
- [ ] Lock acquisition for destroy
- [ ] Terraform destroy execution
- [ ] Reset state to initialized

PHASE 7: MAIN ENTRY POINT
- [ ] Create main exasol-deployer script
- [ ] Command routing
- [ ] Argument parsing
- [ ] Help and version

TESTING & POLISH
- [ ] All exit codes are correct (0 success, non-zero failure)
- [ ] All error messages are clear
- [ ] Permissions are set correctly (0600 for secrets)
- [ ] Lock is always released (use traps)
- [ ] JSON output is valid
- [ ] Works with absolute and relative paths

---

## Critical Success Factors

1. State isolation: Each deployment directory is independent
2. Atomic operations: Use locking to prevent concurrent modifications
3. Clear state machine: Explicit states with well-defined transitions
4. Portable artifacts: Self-contained directory
5. Error recovery: Failed states should be debuggable
6. Configuration flexibility: Variable system extensible

