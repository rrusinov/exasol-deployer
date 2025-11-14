#!/usr/bin/env bash
# Deploy command implementation

# Source dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
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

    # Ensure trap can access the deployment directory after this function
    # returns by copying it to a global variable that the trap will use.
    _EXASOL_TRAP_DEPLOY_DIR="$deploy_dir"
    # Use single quotes so ShellCheck won't warn; the variable is global so
    # it will still be available when the trap runs.
    trap 'lock_remove "$_EXASOL_TRAP_DEPLOY_DIR"' EXIT INT TERM

    # Update status
    state_set_status "$deploy_dir" "$STATE_DEPLOY_IN_PROGRESS"

    progress_start "deploy" "begin" "Starting Exasol deployment"

    # Get version information
    local db_version architecture
    db_version=$(state_read "$deploy_dir" "db_version")
    architecture=$(state_read "$deploy_dir" "architecture")

    log_info "Database version: $db_version"
    log_info "Architecture: $architecture"

    # Note: For c4-based deployments, download URLs are handled by Ansible
    # The credentials file contains db_download_url and c4_download_url that
    # are passed to Ansible for downloading files on remote nodes

    # Change to deployment directory
    cd "$deploy_dir" || die "Failed to change to deployment directory"

    # Initialize Terraform/Tofu
    progress_start "deploy" "tofu_init" "Initializing OpenTofu"
    if ! tofu init -upgrade; then
        state_set_status "$deploy_dir" "$STATE_DEPLOYMENT_FAILED"
        progress_fail "deploy" "tofu_init" "OpenTofu initialization failed"
        die "Terraform initialization failed"
    fi
    progress_complete "deploy" "tofu_init" "OpenTofu initialized successfully"

    # Plan
    progress_start "deploy" "tofu_plan" "Planning infrastructure changes"
    if ! tofu plan -out=tfplan; then
        state_set_status "$deploy_dir" "$STATE_DEPLOYMENT_FAILED"
        progress_fail "deploy" "tofu_plan" "Infrastructure planning failed"
        die "Terraform planning failed"
    fi
    progress_complete "deploy" "tofu_plan" "Infrastructure plan created"

    # Apply
    progress_start "deploy" "tofu_apply" "Creating cloud infrastructure"
    if ! run_tofu_with_progress "deploy" "tofu_apply" "Creating cloud infrastructure" tofu apply -auto-approve tfplan; then
        state_set_status "$deploy_dir" "$STATE_DEPLOYMENT_FAILED"
        progress_fail "deploy" "tofu_apply" "Infrastructure creation failed"
        die "Terraform apply failed"
    fi
    progress_complete "deploy" "tofu_apply" "Cloud infrastructure created"

    # Wait for instances to be ready
    progress_start "deploy" "wait_instances" "Waiting for instances to initialize (60s)"
    sleep 60
    progress_complete "deploy" "wait_instances" "Instances ready"

    # Show deployment summary before Ansible configuration
    if tofu output summary >/dev/null 2>&1; then
        log_info ""
        log_info "🚀 Deployment Summary (Infrastructure Ready):"
        tofu output summary
        log_info ""
        log_info "📋 Next: Configuring cluster with Ansible..."
        log_info ""
    fi

    # Check if Ansible playbook exists
    if [[ ! -f "$deploy_dir/.templates/setup-exasol-cluster.yml" ]]; then
        log_warn "Ansible playbook not found, skipping configuration"
        state_set_status "$deploy_dir" "$STATE_DATABASE_READY"
        log_info ""
        log_info "✅ Infrastructure deployed successfully!"
        log_info ""
        log_info "⚠️  Note: Ansible configuration skipped (playbook not found)"
        return 0
    fi

    # Run Ansible
    progress_start "deploy" "ansible_config" "Configuring cluster with Ansible"

    # Check if inventory file was generated
    if [[ ! -f "$deploy_dir/inventory.ini" ]]; then
        log_warn "Ansible inventory not found, skipping configuration"
        state_set_status "$deploy_dir" "$STATE_DATABASE_READY"
        progress_complete "deploy" "ansible_config" "Infrastructure deployed (Ansible skipped)"
        progress_complete "deploy" "complete" "Deployment completed successfully"
        log_info ""
        log_info "⚠️  Note: Ansible configuration skipped (inventory not found)"
        return 0
    fi

    if ! run_ansible_with_progress "deploy" "ansible_config" "Configuring cluster" ansible-playbook -i inventory.ini .templates/setup-exasol-cluster.yml; then
        state_set_status "$deploy_dir" "$STATE_DEPLOYMENT_FAILED"
        progress_fail "deploy" "ansible_config" "Ansible configuration failed"
        die "Ansible configuration failed"
    fi
    progress_complete "deploy" "ansible_config" "Cluster configured successfully"

    # Update status to success
    state_set_status "$deploy_dir" "$STATE_DATABASE_READY"

    # Display results
    progress_complete "deploy" "complete" "Deployment completed successfully"

    # Show outputs if available
    if tofu output -json > /dev/null 2>&1; then
        log_info ""
        log_info "Deployment information:"
        tofu output -json | jq -r 'to_entries[] | "  \(.key): \(.value.value)"'
    fi

    log_info ""
    log_info "Credentials are stored in: $deploy_dir/.credentials.json"
    log_info "Deployment info: $deploy_dir/INFO.txt"
}
