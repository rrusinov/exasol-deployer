#!/bin/bash
# Deploy command implementation

# Source dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/versions.sh"

# Deploy command
cmd_deploy() {
    local deploy_dir=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
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

    # Trap to ensure lock is removed on exit. Expand $deploy_dir now so the
    # trap uses a literal path when it runs (avoids unbound variable with set -u).
    trap "lock_remove \"$deploy_dir\"" EXIT INT TERM

    # Update status
    state_set_status "$deploy_dir" "$STATE_DEPLOYMENT_IN_PROGRESS"

    log_info "🚀 Starting Exasol deployment"
    log_info "======================================"

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
    log_info ""
    log_info "📦 Initializing OpenTofu..."
    if ! tofu init -upgrade; then
        state_set_status "$deploy_dir" "$STATE_DEPLOYMENT_FAILED"
        die "Terraform initialization failed"
    fi

    # Plan
    log_info ""
    log_info "📋 Planning infrastructure..."
    if ! tofu plan -out=tfplan; then
        state_set_status "$deploy_dir" "$STATE_DEPLOYMENT_FAILED"
        die "Terraform planning failed"
    fi

    # Apply
    log_info ""
    log_info "🏗️  Creating infrastructure..."
    if ! tofu apply -auto-approve tfplan; then
        state_set_status "$deploy_dir" "$STATE_DEPLOYMENT_FAILED"
        die "Terraform apply failed"
    fi

    # Wait for instances to be ready
    log_info ""
    log_info "⏳ Waiting 60 seconds for instances to initialize..."
    sleep 60

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
    log_info ""
    log_info "⚙️  Configuring cluster with Ansible..."

    # Check if inventory file was generated
    if [[ ! -f "$deploy_dir/inventory.ini" ]]; then
        log_warn "Ansible inventory not found, skipping configuration"
        state_set_status "$deploy_dir" "$STATE_DATABASE_READY"
        log_info ""
        log_info "✅ Infrastructure deployed successfully!"
        log_info ""
        log_info "⚠️  Note: Ansible configuration skipped (inventory not found)"
        return 0
    fi

    if ! ansible-playbook -i inventory.ini .templates/setup-exasol-cluster.yml; then
        state_set_status "$deploy_dir" "$STATE_DEPLOYMENT_FAILED"
        die "Ansible configuration failed"
    fi

    # Update status to success
    state_set_status "$deploy_dir" "$STATE_DATABASE_READY"

    # Display results
    log_info ""
    log_info "✅ Deployment completed successfully!"
    log_info "======================================"

    # Show outputs if available
    if tofu output -json > /dev/null 2>&1; then
        log_info ""
        log_info "Deployment information:"
        tofu output -json | jq -r 'to_entries[] | "  \(.key): \(.value.value)"'
    fi

    log_info ""
    log_info "Credentials are stored in: $deploy_dir/.credentials.json"
}
