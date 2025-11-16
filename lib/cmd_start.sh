#!/usr/bin/env bash
# Start command implementation

# Source dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=lib/state.sh
source "$LIB_DIR/state.sh"

# Show help for start command
show_start_help() {
    cat <<'EOF'
Start a stopped Exasol database deployment.

This command starts the Exasol database services on an existing deployment
that was previously stopped using 'exasol stop'. The cloud instances must
still be running.

Usage:
  exasol start [flags]

Flags:
  --deployment-dir <path>        Directory with deployment files (default: ".")
  -h, --help                     Show help

Prerequisites:
  - Deployment must be in 'stopped' or 'start_failed' state
  - Cloud instances must still be running
  - No other operations can be in progress

Example:
  exasol start --deployment-dir ./my-deployment
EOF
}

# Start command
cmd_start() {
    local deploy_dir=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_start_help
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

    if ! validate_start_transition "$current_state"; then
        die "Cannot start from current state: $current_state"
    fi

    # Check for existing lock
    if lock_exists "$deploy_dir"; then
        local lock_op lock_pid
        lock_op=$(lock_info "$deploy_dir" "operation")
        lock_pid=$(lock_info "$deploy_dir" "pid")
        die "Another operation is in progress: $lock_op (PID: $lock_pid)"
    fi

    # Create lock
    lock_create "$deploy_dir" "start" || die "Failed to create lock"

    setup_operation_guard "$deploy_dir" "$STATE_START_FAILED" "start_success"

    # Update status
    state_set_status "$deploy_dir" "$STATE_START_IN_PROGRESS"

    progress_start "start" "begin" "Starting Exasol database start operation"

    log_info "Starting Exasol database cluster..."
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
    if [[ ! -f "$deploy_dir/.templates/start-exasol-cluster.yml" ]]; then
        log_error "Ansible playbook not found: .templates/start-exasol-cluster.yml"
        state_set_status "$deploy_dir" "$STATE_START_FAILED"
        progress_fail "start" "playbook_missing" "Start playbook not found"
        die "Start playbook not found"
    fi

    # Check if inventory file exists
    if [[ ! -f "$deploy_dir/inventory.ini" ]]; then
        log_error "Ansible inventory not found: inventory.ini"
        state_set_status "$deploy_dir" "$STATE_START_FAILED"
        progress_fail "start" "inventory_missing" "Ansible inventory not found"
        die "Ansible inventory not found"
    fi

    # If provider supports infra power control, start instances via tofu first
    if [[ "$infra_power_supported" == "true" ]]; then
        progress_start "start" "tofu_start" "Starting infrastructure (powering on instances)"
        if ! run_tofu_with_progress "start" "tofu_start" "Powering on instances" tofu apply -auto-approve -refresh=false -target="aws_ec2_instance_state.exasol_node_state" -target="azapi_resource_action.vm_power_on" -target="google_compute_instance.exasol_node" -target="libvirt_domain.exasol_node" -var "infra_desired_state=running"; then
            state_set_status "$deploy_dir" "$STATE_START_FAILED"
            progress_fail "start" "tofu_start" "Failed to start infrastructure (tofu apply)"
            die "Infrastructure start (tofu apply) failed"
        fi
        progress_complete "start" "tofu_start" "Infrastructure powered on"
    else
        log_warn "Provider '$cloud_provider' lacks tofu-based power control. Ensure instances are running before continuing; start will attempt services regardless."
    fi

    # Refresh IPs in inventory/ssh_config before Ansible (similar to deploy)
    if command -v exasol >/dev/null 2>&1; then
        log_info "Refreshing inventory and ssh_config via health --update"
        cmd_health --deployment-dir "$deploy_dir" --update --quiet >/dev/null 2>&1 || true
    fi

    # Run Ansible to start the database
    progress_start "start" "ansible_start" "Starting database services with Ansible"

    if ! run_ansible_with_progress "start" "ansible_start" "Starting database services" ansible-playbook -i inventory.ini .templates/start-exasol-cluster.yml; then
        state_set_status "$deploy_dir" "$STATE_START_FAILED"
        progress_fail "start" "ansible_start" "Failed to start database services"
        die "Ansible start operation failed"
    fi
    progress_complete "start" "ansible_start" "Database services started successfully"

    # Validate database connectivity (optional - best effort)
    progress_start "start" "validation" "Validating database connectivity"

    local validation_passed=true
    if [[ -f "$deploy_dir/inventory.ini" ]] && [[ -f "$deploy_dir/ssh_config" ]]; then
        # Try to check if c4.service is active on the first node
        local first_host
        first_host=$(awk '/^\[exasol_nodes\]/,/^\[/ {if ($1 !~ /^\[/ && NF > 0) {print $1; exit}}' "$deploy_dir/inventory.ini")

        if [[ -n "$first_host" ]]; then
            log_debug "Checking c4.service status on $first_host"
            if ssh -F "$deploy_dir/ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$first_host" \
                "sudo systemctl is-active c4.service" >/dev/null 2>&1; then
                log_info "Database services are active"
            else
                log_warn "Could not verify database service status"
                validation_passed=false
            fi
        fi
    fi

    if $validation_passed; then
        progress_complete "start" "validation" "Database connectivity validated"
        state_set_status "$deploy_dir" "$STATE_DATABASE_READY"
    else
        progress_complete "start" "validation" "Database started but connectivity validation incomplete"
        state_set_status "$deploy_dir" "$STATE_DATABASE_CONNECTION_FAILED"
        log_warn "Database started but connectivity could not be fully validated"
        log_info "Run 'exasol health --deployment-dir $deploy_dir' to check database status"
    fi
    operation_success

    # Display results
    progress_complete "start" "complete" "Start operation completed successfully"

    log_info ""
    log_info "✓ Exasol Database Started Successfully!"
    log_info ""
    log_info "The database services have been started and should be ready for use."
    log_info "Run 'exasol status --deployment-dir $deploy_dir' to check deployment status"
    log_info "Run 'exasol health --deployment-dir $deploy_dir' for detailed health checks"
}
