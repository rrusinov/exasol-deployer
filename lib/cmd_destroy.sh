#!/usr/bin/env bash
# Destroy command implementation

# Source dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=lib/state.sh
source "$LIB_DIR/state.sh"

# Show help for destroy command
show_destroy_help() {
    cat <<'EOF'
Destroy an active deployment using its deployment directory.

Destroying a deployment releases all resources - including all data storage.
If you want to retain any data, ensure you've created and moved backups to another safe location.

Usage:
  exasol destroy [flags]

Flags:
  --deployment-dir <path>        Directory with deployment files (default: ".")
  --auto-approve                 Skip confirmation prompt
  -h, --help                     Show help

Examples:
  exasol destroy --deployment-dir ./my-deployment
  exasol destroy --deployment-dir ./my-deployment --auto-approve
EOF
}

# Destroy command - entry point
cmd_destroy() {
    cmd_destroy_confirm "$@"
}

# Destroy confirmation phase - handles validation and user confirmation
cmd_destroy_confirm() {
    local deploy_dir=""
    local auto_approve=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_destroy_help
                return 0
                ;;
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
        # Update status to destroyed since infrastructure appears to be gone
        state_set_status "$deploy_dir" "$STATE_DESTROYED"
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

    log_info "Deployment directory: $deploy_dir"

    # Get deployment info
    local db_version architecture
    db_version=$(state_read "$deploy_dir" "db_version")
    architecture=$(state_read "$deploy_dir" "architecture")

    log_info "Database version: $db_version"
    log_info "Architecture: $architecture"

    # Confirmation prompt
    if [[ "$auto_approve" == false ]]; then
        log_warn "⚠️  WARNING: This will destroy all resources including data!"
        log_warn "⚠️  Make sure you have backups of any important data."
        echo ""
        echo -e "\033[31mAre you sure you want to destroy all resources? (yes/no): \033[0m" >&2
        read -r confirm </dev/tty
        if [[ "$confirm" != "yes" ]]; then
            log_info "Destruction cancelled"
            return 0
        fi
    fi

    # Proceed to execution phase
    cmd_destroy_execute "$deploy_dir" "$db_version" "$architecture"
}

# Destroy execution phase - performs the actual destruction
cmd_destroy_execute() {
    local deploy_dir="$1"
    local db_version="$2"
    local architecture="$3"

    # Update status to destroy in progress
    state_set_status "$deploy_dir" "$STATE_DESTROY_IN_PROGRESS"

    # Create lock
    lock_create "$deploy_dir" "destroy" || die "Failed to create lock"
    setup_operation_guard "$deploy_dir" "$STATE_DESTROY_FAILED" "destroy_success"

    # Get cluster size for progress estimation
    local cluster_size
    cluster_size=$(state_read "$deploy_dir" "cluster_size")
    cluster_size=${cluster_size:-1}


    # Change to deployment directory
    cd "$deploy_dir" || die "Failed to change to deployment directory"

    # Check for Azure and add delay if needed
    local cloud_provider
    cloud_provider=$(state_read "$deploy_dir" "cloud_provider")
        if [[ "$cloud_provider" == "azure" ]]; then
            local state_file="$deploy_dir/.exasol.json"
            if [[ -f "$state_file" ]]; then
                local created_at now epoch_diff sleep_time
                created_at=$(jq -r '.created_at // empty' "$state_file")
                if [[ -n "$created_at" ]]; then
                    # Try to parse as epoch seconds, else as ISO8601
                    if [[ "$created_at" =~ ^[0-9]+$ ]]; then
                        now=$(date +%s)
                        epoch_diff=$(( now - created_at ))
                    else
                        # Parse ISO8601 to epoch
                        now=$(date +%s)
                        created_epoch=$(date -d "$created_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$created_at" +%s 2>/dev/null)
                        if [[ -n "$created_epoch" ]]; then
                            epoch_diff=$(( now - created_epoch ))
                        else
                            epoch_diff=240
                        fi
                    fi
                    if [[ $epoch_diff -lt 240 ]]; then
                        sleep_time=$(( 240 - epoch_diff ))
                        log_info "Azure deployment detected. Waiting $sleep_time seconds to avoid NIC reservation issues (Azure may reserve NICs for up to 240 seconds after VM deletion)..."
                        sleep $sleep_time
                    fi
                fi
            fi
        fi

    # Run Terraform destroy
    log_info "Destroying cloud infrastructure..."

    local destroy_rc=0
    if ! tofu destroy -auto-approve; then
        destroy_rc=$?
        state_set_status "$deploy_dir" "$STATE_DESTROY_FAILED"
        log_error "Terraform destroy failed"
        # Do not exit here with die() because we want to reach the final
        # inspection/notification block and inform the user that manual
        # cleanup is required before removing the deployment directory.
    else
        destroy_rc=0
    fi

    # Clean up generated files only if destroy succeeded
    if [[ $destroy_rc -eq 0 ]]; then
        rm -f inventory.ini ssh_config tfplan exasol-key.pem
        # Remove Terraform state and caches so subsequent destroy runs are no-ops
        rm -f terraform.tfstate terraform.tfstate.backup
        rm -rf .terraform

        # Update deployment status to destroyed
        state_set_status "$deploy_dir" "$STATE_DESTROYED"

        operation_success

        # Display success message
        log_info ""
        log_info "✓ Exasol Deployment Destroyed Successfully!"
        log_info ""
        log_info "All cloud resources have been destroyed."
        log_info "The deployment directory has been preserved: $deploy_dir"
        log_info "You can safely delete it manually when ready."
    else
        # Keep the lock removal as we already removed it on failure above.
        log_warn "Some resources may not have been destroyed. Manual inspection and cleanup are required."
        log_warn "The deployment directory will NOT be removed automatically."
        log_info "Please investigate the failure and clean up resources/files before deleting the deployment directory: $deploy_dir"
    fi

}
