#!/usr/bin/env bash
# Destroy command implementation

# Source dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"

# Destroy command
cmd_destroy() {
    local deploy_dir=""
    local auto_approve=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --deployment-dir)
                deploy_dir="$2"
                shift 2
                ;;
            --auto-approve)
                auto_approve=true
                shift
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
        die "Not a deployment directory: $deploy_dir"
    fi

    # Check if anything was actually deployed
    if [[ ! -f "$deploy_dir/terraform.tfstate" ]]; then
        log_warn "No Terraform state found. Nothing to destroy."
        # Do NOT remove the deployment directory automatically.
        # Inform the user that the directory is preserved and can be removed manually.
        log_info "Deployment directory preserved: $deploy_dir"
        log_info "If you want to remove it, delete it manually when it's safe to do so."
        return 0
    fi

    # Check for existing lock
    if lock_exists "$deploy_dir"; then
        local lock_op lock_pid
        lock_op=$(lock_info "$deploy_dir" "operation")
        lock_pid=$(lock_info "$deploy_dir" "pid")
        die "Another operation is in progress: $lock_op (PID: $lock_pid)"
    fi

    progress_start "destroy" "begin" "Starting Exasol deployment destruction"

    log_info "Deployment directory: $deploy_dir"

    # Get deployment info
    local db_version architecture
    db_version=$(state_read "$deploy_dir" "db_version")
    architecture=$(state_read "$deploy_dir" "architecture")

    log_info "Database version: $db_version"
    log_info "Architecture: $architecture"

    # Confirmation prompt
    if [[ "$auto_approve" == false ]]; then
        progress_update "destroy" "confirm" "Waiting for user confirmation"
        log_warn "⚠️  WARNING: This will destroy all resources including data!"
        log_warn "⚠️  Make sure you have backups of any important data."
        echo ""
        read -p "Are you sure you want to destroy all resources? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            progress_complete "destroy" "confirm" "Destruction cancelled by user"
            log_info "Destruction cancelled"
            return 0
        fi
        progress_complete "destroy" "confirm" "Destruction confirmed"
    fi

    # Create lock
    lock_create "$deploy_dir" "destroy" || die "Failed to create lock"

    # Ensure trap can access the deployment directory after this function
    # returns by copying it to a global variable that the trap will use.
    _EXASOL_TRAP_DEPLOY_DIR="$deploy_dir"
    # Use single quotes so ShellCheck won't warn; the variable is global so
    # it will still be available when the trap runs.
    trap 'lock_remove "$_EXASOL_TRAP_DEPLOY_DIR"' EXIT INT TERM

    # Change to deployment directory
    cd "$deploy_dir" || die "Failed to change to deployment directory"

    # Run Terraform destroy
    progress_start "destroy" "tofu_destroy" "Destroying cloud infrastructure"

    local destroy_rc=0
    if ! run_tofu_with_progress "destroy" "tofu_destroy" "Destroying cloud infrastructure" tofu destroy -auto-approve; then
        destroy_rc=$?
        lock_remove "$deploy_dir"
        progress_fail "destroy" "tofu_destroy" "Infrastructure destruction failed"
        log_error "Terraform destroy failed"
        # Do not exit here with die() because we want to reach the final
        # inspection/notification block and inform the user that manual
        # cleanup is required before removing the deployment directory.
    else
        destroy_rc=0
        progress_complete "destroy" "tofu_destroy" "Cloud infrastructure destroyed"
    fi

    # Clean up generated files only if destroy succeeded
    if [[ $destroy_rc -eq 0 ]]; then
        progress_start "destroy" "cleanup" "Cleaning up deployment files"
        rm -f inventory.ini ssh_config tfplan exasol-key.pem
        # Remove Terraform state and caches so subsequent destroy runs are no-ops
        rm -f terraform.tfstate terraform.tfstate.backup
        rm -rf .terraform

        # Remove lock
        lock_remove "$deploy_dir"

        progress_complete "destroy" "cleanup" "Deployment files cleaned up"
        progress_complete "destroy" "complete" "All resources destroyed successfully"
    else
        # Keep the lock removal as we already removed it on failure above.
        log_warn "Some resources may not have been destroyed. Manual inspection and cleanup are required."
        log_warn "The deployment directory will NOT be removed automatically."
        log_info "Please investigate the failure and clean up resources/files before deleting the deployment directory: $deploy_dir"
    fi

}
