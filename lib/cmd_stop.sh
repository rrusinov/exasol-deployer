#!/usr/bin/env bash
# Stop command implementation

# Source dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=lib/state.sh
source "$LIB_DIR/state.sh"

# Show help for stop command
show_stop_help() {
    cat <<'EOF'
Stop a running Exasol database deployment.

This command gracefully stops the Exasol database services without terminating
cloud instances. This is useful for cost optimization when the database is not
needed while preserving the infrastructure for later use.

The instances will remain running and can be restarted using 'exasol start'.

Usage:
  exasol stop [flags]

Flags:
  --deployment-dir <path>        Directory with deployment files (default: ".")
  -h, --help                     Show help

Prerequisites:
  - Deployment must be in 'database_ready', 'database_connection_failed', or 'stop_failed' state
  - No other operations can be in progress

Example:
  exasol stop --deployment-dir ./my-deployment
EOF
}

# Stop command
cmd_stop() {
    local deploy_dir=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_stop_help
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

    # Check current state and validate transition
    local current_state
    current_state=$(state_get_status "$deploy_dir")

    if ! validate_stop_transition "$current_state"; then
        die "Cannot stop from current state: $current_state"
    fi

    # Check for existing lock
    if lock_exists "$deploy_dir"; then
        local lock_op lock_pid
        lock_op=$(lock_info "$deploy_dir" "operation")
        lock_pid=$(lock_info "$deploy_dir" "pid")
        die "Another operation is in progress: $lock_op (PID: $lock_pid)"
    fi

    # Create lock
    lock_create "$deploy_dir" "stop" || die "Failed to create lock"

    setup_operation_guard "$deploy_dir" "$STATE_STOP_FAILED" "stop_success"

    # Update status
    state_set_status "$deploy_dir" "$STATE_STOP_IN_PROGRESS"

    progress_start "stop" "begin" "Starting Exasol database stop operation"

    log_info "Stopping Exasol database cluster..."
    log_info "Current state: $current_state"

    local cloud_provider
    cloud_provider=$(state_read "$deploy_dir" "cloud_provider" 2>/dev/null || echo "unknown")
    local infra_power_supported="false"
    case "$cloud_provider" in
        aws|azure|gcp|libvirt)
            infra_power_supported="true"
            ;;
        *)
            infra_power_supported="false"
            ;;
    esac

    # Change to deployment directory
    cd "$deploy_dir" || die "Failed to change to deployment directory"

    # Check if Ansible playbook exists
    if [[ ! -f "$deploy_dir/.templates/stop-exasol-cluster.yml" ]]; then
        log_error "Ansible playbook not found: .templates/stop-exasol-cluster.yml"
        state_set_status "$deploy_dir" "$STATE_STOP_FAILED"
        progress_fail "stop" "playbook_missing" "Stop playbook not found"
        die "Stop playbook not found"
    fi

    # Check if inventory file exists
    if [[ ! -f "$deploy_dir/inventory.ini" ]]; then
        log_error "Ansible inventory not found: inventory.ini"
        state_set_status "$deploy_dir" "$STATE_STOP_FAILED"
        progress_fail "stop" "inventory_missing" "Ansible inventory not found"
        die "Ansible inventory not found"
    fi

    # Run Ansible to stop the database
    progress_start "stop" "ansible_stop" "Stopping database services with Ansible"

    local ansible_extra=(-i inventory.ini .templates/stop-exasol-cluster.yml)
    [[ "$infra_power_supported" == "false" ]] && ansible_extra+=(-e "power_off_fallback=true")

    if ! run_ansible_with_progress "stop" "ansible_stop" "Stopping database services" ansible-playbook "${ansible_extra[@]}"; then
        state_set_status "$deploy_dir" "$STATE_STOP_FAILED"
        progress_fail "stop" "ansible_stop" "Failed to stop database services"
        die "Ansible stop operation failed"
    fi
    progress_complete "stop" "ansible_stop" "Database services stopped successfully"

    # If provider supports infra power control, stop instances via tofu
    if [[ "$infra_power_supported" == "true" ]]; then
        progress_start "stop" "tofu_stop" "Stopping infrastructure (powering off instances)"
        if ! run_tofu_with_progress "stop" "tofu_stop" "Powering off instances" tofu apply -auto-approve -refresh=false -target="aws_ec2_instance_state.exasol_node_state" -target="azapi_resource_action.vm_power_off" -target="google_compute_instance.exasol_node" -target="libvirt_domain.exasol_node" -var "infra_desired_state=stopped"; then
            state_set_status "$deploy_dir" "$STATE_STOP_FAILED"
            progress_fail "stop" "tofu_stop" "Failed to stop infrastructure (tofu apply)"
            die "Infrastructure stop (tofu apply) failed"
        fi
        progress_complete "stop" "tofu_stop" "Infrastructure powered off"
    else
        log_warn "Provider '$cloud_provider' does not support power control via tofu. Instances were issued in-guest shutdown; manual power-on will be required for start."
    fi

    # Update status to stopped
    state_set_status "$deploy_dir" "$STATE_STOPPED"
    operation_success

    # Display results
    progress_complete "stop" "complete" "Stop operation completed successfully"

    log_info ""
    log_info "✓ Exasol Database Stopped Successfully!"
    log_info ""
    log_info "The database services have been stopped. Cloud instances are still running."
    log_info "To restart the database, run: exasol start --deployment-dir $deploy_dir"
    log_info "To terminate cloud instances, run: exasol destroy --deployment-dir $deploy_dir"
}
