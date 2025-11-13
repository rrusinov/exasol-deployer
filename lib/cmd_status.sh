#!/usr/bin/env bash
# Status command implementation

# Source dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"

# Show help for status command
show_status_help() {
    cat <<'EOF'
Show the status of a deployment.

Returns JSON output with deployment status information.

Usage:
  exasol status [deployment-dir]

Flags:
  -h, --help                     Show help

Examples:
  exasol status ./my-deployment
  exasol status
EOF
}

# Status command
cmd_status() {
    # Check for help flag first
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_status_help
        return 0
    fi

    local deploy_dir="$1"

    # Validate deployment directory
    if [[ ! -d "$deploy_dir" ]]; then
        cat <<EOF
{
  "status": "error",
  "message": "Deployment directory not found: $deploy_dir"
}
EOF
        return 1
    fi

    if [[ ! -f "$deploy_dir/$STATE_FILE" ]]; then
        cat <<EOF
{
  "status": "error",
  "message": "Not a deployment directory (missing $STATE_FILE)"
}
EOF
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

    # Build JSON output
    cat <<EOF
{
  "status": "$status",
  "db_version": "$db_version",
  "architecture": "$architecture",
  "terraform_state_exists": $terraform_state_exists,
  "created_at": "$created_at",
  "updated_at": "$updated_at"$(if lock_exists "$deploy_dir"; then echo ",
  \"lock\": {
    \"operation\": \"$lock_operation\",
    \"started_at\": \"$lock_started_at\",
    \"pid\": $lock_pid
  }"; fi)
}
EOF
}
