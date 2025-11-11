#!/bin/bash
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

        # Ask if user wants to clean up the directory
        if [[ "$auto_approve" == false ]]; then
            echo ""
            read -p "Remove deployment directory? (yes/no): " confirm
            if [[ "$confirm" == "yes" ]]; then
                rm -rf "$deploy_dir"
                log_info "Deployment directory removed"
            fi
        fi
        return 0
    fi

    # Check for existing lock
    if lock_exists "$deploy_dir"; then
        local lock_op lock_pid
        lock_op=$(lock_info "$deploy_dir" "operation")
        lock_pid=$(lock_info "$deploy_dir" "pid")
        die "Another operation is in progress: $lock_op (PID: $lock_pid)"
    fi

    log_info "🗑️  Destroying Exasol deployment"
    log_info "======================================"
    log_info "Deployment directory: $deploy_dir"
    log_info ""

    # Get deployment info
    local db_version architecture
    db_version=$(state_read "$deploy_dir" "db_version")
    architecture=$(state_read "$deploy_dir" "architecture")

    log_info "Database version: $db_version"
    log_info "Architecture: $architecture"
    log_info ""

    # Confirmation prompt
    if [[ "$auto_approve" == false ]]; then
        log_warn "⚠️  WARNING: This will destroy all resources including data!"
        log_warn "⚠️  Make sure you have backups of any important data."
        echo ""
        read -p "Are you sure you want to destroy all resources? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Destruction cancelled"
            return 0
        fi
    fi

    # Create lock
    lock_create "$deploy_dir" "destroy" || die "Failed to create lock"

    # Trap to ensure lock is removed on exit
    trap "lock_remove '$deploy_dir'" EXIT INT TERM

    # Change to deployment directory
    cd "$deploy_dir" || die "Failed to change to deployment directory"

    # Run Terraform destroy
    log_info ""
    log_info "🗑️  Destroying infrastructure..."

    if ! tofu destroy -auto-approve; then
        lock_remove "$deploy_dir"
        die "Terraform destroy failed"
    fi

    # Clean up generated files
    log_info ""
    log_info "🧹 Cleaning up deployment files..."

    rm -f inventory.ini ssh_config tfplan exasol-key.pem
    rm -rf .terraform terraform.tfstate.backup

    # Remove lock
    lock_remove "$deploy_dir"

    log_info ""
    log_info "✅ All resources destroyed successfully!"
    log_info ""

    # Ask if user wants to remove the deployment directory
    if [[ "$auto_approve" == false ]]; then
        read -p "Remove deployment directory? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            cd ..
            rm -rf "$deploy_dir"
            log_info "Deployment directory removed"
        else
            log_info "Deployment directory preserved: $deploy_dir"
        fi
    else
        log_info "Deployment directory preserved: $deploy_dir"
    fi
}
