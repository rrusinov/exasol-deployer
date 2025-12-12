#!/usr/bin/env bash
# Status command implementation

# Source dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=lib/state.sh
source "$LIB_DIR/state.sh"

# Show help for status command
show_status_help() {
    cat <<'EOF'
Show the status of a deployment.

Returns JSON output with deployment status information.

Usage:
  exasol status [flags]

Flags:
  --deployment-dir <path>        Directory with deployment files (default: ".")
  --show-details                 Print deployment outputs (instance details, ports, etc.)
  -h, --help                     Show help

Examples:
  exasol status --deployment-dir ./my-deployment
  exasol status --deployment-dir ./my-deployment --show-details
EOF
}

# Emit error JSON for status command
status_error_json() {
    local message="$1"
    cat <<EOF
{
  "status": "error",
  "message": "$message"
}
EOF
}

# Collect deployment detail outputs derived from OpenTofu
status_get_details() {
    local deploy_dir="$1"
    local fetch_details="$2"
    local empty="{}"

    if [[ "$fetch_details" != "true" ]]; then
        echo "$empty"
        return 0
    fi

    if ! command -v "${TOFU_BINARY:-tofu}" >/dev/null 2>&1; then
        log_debug "Skipping detail collection: ${TOFU_BINARY:-tofu} command not found"
        echo "$empty"
        return 0
    fi

    local raw_outputs
    if ! raw_outputs=$("${TOFU_BINARY:-tofu}" -chdir="$deploy_dir" output -json 2>/dev/null); then
        log_debug "Failed to read deployment details via ${TOFU_BINARY:-tofu} output -json"
        echo "$empty"
        return 0
    fi

    local flattened
    if ! flattened=$(echo "$raw_outputs" | jq 'with_entries(.value = .value.value // .value)' 2>/dev/null); then
        log_debug "Failed to process deployment output JSON for details"
        echo "$empty"
        return 0
    fi

    local processed
    if ! processed=$(echo "$flattened" | jq '
        def instance_count:
          if has("node_names") and ((.node_names | type) == "array") then (.node_names | length)
          elif has("instance_details") and ((.instance_details | type) == "object") then (.instance_details | keys | length)
          elif has("node_public_ips") and ((.node_public_ips | type) == "array") then (.node_public_ips | length)
          else 0 end;
        del(.summary) | .instance_count = instance_count
    ' 2>/dev/null); then
        log_debug "Failed to finalize deployment details JSON"
        echo "$empty"
        return 0
    fi

    echo "$processed"
}

# Status command
cmd_status() {
    local deploy_dir=""
    local show_details="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_status_help
                return 0
                ;;
            --deployment-dir)
                deploy_dir="$2"
                shift 2
                ;;
            --show-details)
                show_details="true"
                shift
                ;;
            *)
                if [[ -z "$deploy_dir" ]]; then
                    deploy_dir="$1"
                    shift
                else
                    log_error "Unknown option: $1"
                    return 1
                fi
                ;;
        esac
    done

    if [[ -z "$deploy_dir" ]]; then
        deploy_dir="."
    fi

    # Validate deployment directory
    if [[ ! -d "$deploy_dir" ]]; then
        status_error_json "Deployment directory not found: $deploy_dir"
        return 1
    fi

    if [[ ! -f "$deploy_dir/$STATE_FILE" ]]; then
        status_error_json "Not a deployment directory (missing $STATE_FILE)"
        return 1
    fi
    # Get current status
    local status
    status=$(get_deployment_status "$deploy_dir")

    # Read additional information from state file
    local db_version architecture created_at updated_at
    db_version=$(state_read "$deploy_dir" "db_version")
    architecture=$(state_read "$deploy_dir" "architecture")
    created_at=$(state_read "$deploy_dir" "created_at")
    updated_at=$(state_read "$deploy_dir" "updated_at")

    # Check if Terraform state exists
    local terraform_state_exists="false"
    if [[ -f "$deploy_dir/terraform.tfstate" ]]; then
        terraform_state_exists="true"
    fi

    # If lock exists, get lock information
    local lock_operation lock_started_at lock_pid
    if lock_exists "$deploy_dir"; then
        lock_operation=$(lock_info "$deploy_dir" "operation")
        lock_started_at=$(lock_info "$deploy_dir" "started_at")
        lock_pid=$(lock_info "$deploy_dir" "pid")
    fi

    local lock_section=""
    if lock_exists "$deploy_dir"; then
        lock_section=$(cat <<EOF
,
  "lock": {
    "operation": "$lock_operation",
    "started_at": "$lock_started_at",
    "pid": $lock_pid
  }
EOF
)
    fi

    local details_section=""
    if [[ "$show_details" == "true" ]]; then
        local details_json="{}"
        if ! details_json=$(status_get_details "$deploy_dir" "$show_details"); then
            details_json="{}"
        fi
        details_section=$(cat <<EOF
,
  "details": $details_json
EOF
)
    fi

    # Build JSON output
    cat <<EOF
{
  "status": "$status",
  "db_version": "$db_version",
  "architecture": "$architecture",
  "terraform_state_exists": $terraform_state_exists,
  "created_at": "$created_at",
  "updated_at": "$updated_at"$lock_section$details_section
}
EOF
}
