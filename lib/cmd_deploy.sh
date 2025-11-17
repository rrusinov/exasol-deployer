#!/usr/bin/env bash
# Deploy command implementation

# Source dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=lib/state.sh
source "$LIB_DIR/state.sh"
# shellcheck source=lib/versions.sh
source "$LIB_DIR/versions.sh"

# Show help for deploy command
show_deploy_help() {
    cat <<'EOF'
Deploy using an existing deployment directory.

Once a deployment is complete, state files will be stored in the deployment directory.
Do not delete the deployment directory until the 'destroy' command has been executed.

Usage:
  exasol deploy [flags]

Flags:
  --deployment-dir <path>        Directory with deployment files (default: ".")
  -h, --help                     Show help

Example:
  exasol deploy --deployment-dir ./my-deployment
EOF
}

# Deploy command
cmd_deploy() {
    local deploy_dir=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_deploy_help
                return 0
                ;;
            --deployment-dir)
                deploy_dir="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Set defaults
    if [[ -z "$deploy_dir" ]]; then
        deploy_dir="$(pwd)"
    fi
    deploy_dir=$(validate_directory "$deploy_dir")

    # Set deployment directory for progress tracking
    export EXASOL_DEPLOY_DIR="$deploy_dir"

    # Validate deployment directory
    if [[ ! -d "$deploy_dir" ]]; then
        die "Deployment directory not found: $deploy_dir"
    fi

    if ! is_deployment_directory "$deploy_dir"; then
        die "Not a deployment directory: $deploy_dir (run 'init' first)"
    fi

    # Check for existing lock
    if lock_exists "$deploy_dir"; then
        local lock_op lock_pid
        lock_op=$(lock_info "$deploy_dir" "operation")
        lock_pid=$(lock_info "$deploy_dir" "pid")
        die "Another operation is in progress: $lock_op (PID: $lock_pid)"
    fi

    # Create lock
    lock_create "$deploy_dir" "deploy" || die "Failed to create lock"

    setup_operation_guard "$deploy_dir" "$STATE_DEPLOYMENT_FAILED" "deploy_success"

    # Update status
    state_set_status "$deploy_dir" "$STATE_DEPLOY_IN_PROGRESS"

    # Get version information and cluster size for progress tracking
    local db_version architecture cluster_size
    db_version=$(state_read "$deploy_dir" "db_version")
    architecture=$(state_read "$deploy_dir" "architecture")
    cluster_size=$(state_read "$deploy_dir" "cluster_size")
    cluster_size=${cluster_size:-1}

    log_info "Database version: $db_version"
    log_info "Architecture: $architecture"
    log_info "Cluster size: $cluster_size nodes"

    # Calculate total estimated lines for entire deploy operation
    # Based on actual measurements from real deployments
    local total_lines
    total_lines=$(estimate_lines "deploy" "$cluster_size")

    # Initialize cumulative progress tracking for entire deploy
    progress_init_cumulative "$total_lines"
    export PROGRESS_CUMULATIVE_MODE=1

    # Calculate sub-operation estimates for cumulative tracking
    # These are proportional estimates based on typical deploy breakdown
    local tofu_lines ansible_lines
    tofu_lines=$((total_lines * 50 / 100))      # ~50% of deploy is infrastructure
    ansible_lines=$((total_lines * 50 / 100))   # ~50% is ansible configuration

    # Note: For c4-based deployments, download URLs are handled by Ansible
    # The credentials file contains db_download_url and c4_download_url that
    # are passed to Ansible for downloading files on remote nodes

    # Change to deployment directory
    cd "$deploy_dir" || die "Failed to change to deployment directory"

    # Run all tofu operations (init, plan, apply) as one cumulative step
    log_info "Creating cloud infrastructure..."

    # Combine all tofu operations and track as single progress block
    if ! { tofu init -upgrade && tofu plan -out=tfplan && tofu apply -auto-approve tfplan; } 2>&1 | \
        progress_prefix_cumulative "$tofu_lines"; then
        state_set_status "$deploy_dir" "$STATE_DEPLOYMENT_FAILED"
        die "Infrastructure deployment failed"
    fi

    # Check if Ansible playbook exists
    if [[ ! -f "$deploy_dir/.templates/setup-exasol-cluster.yml" ]]; then
        log_warn "Ansible playbook not found, skipping configuration"
        state_set_status "$deploy_dir" "$STATE_DATABASE_READY"
        operation_success
        log_info ""
        log_info "✅ Infrastructure deployed successfully!"
        log_info ""
        log_info "⚠️  Note: Ansible configuration skipped (playbook not found)"
        return 0
    fi

    # Check if inventory file was generated
    if [[ ! -f "$deploy_dir/inventory.ini" ]]; then
        log_warn "Ansible inventory not found, skipping configuration"
        state_set_status "$deploy_dir" "$STATE_DATABASE_READY"
        operation_success
        log_info ""
        log_info "⚠️  Note: Ansible configuration skipped (inventory not found)"
        return 0
    fi

    log_info "Configuring cluster with Ansible..."
    if ! ansible-playbook -i inventory.ini .templates/setup-exasol-cluster.yml 2>&1 | \
        progress_prefix_cumulative "$ansible_lines"; then
        state_set_status "$deploy_dir" "$STATE_DEPLOYMENT_FAILED"
        die "Ansible configuration failed"
    fi

    # Disable cumulative mode after deploy
    unset PROGRESS_CUMULATIVE_MODE

    # Update status to success
    state_set_status "$deploy_dir" "$STATE_DATABASE_READY"
    operation_success

    log_info ""
    log_info "✅ Exasol Cluster Deployment Complete!"
    log_info "Check $deploy_dir/INFO.txt for commands or run 'exasol status --show-details' for deployment details."
}
