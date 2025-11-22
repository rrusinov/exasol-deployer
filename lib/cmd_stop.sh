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

    # Get cluster size for progress estimation
    local cluster_size
    cluster_size=$(state_read "$deploy_dir" "cluster_size")
    cluster_size=${cluster_size:-1}

    log_info "Stopping Exasol database cluster..."
    log_info "Current state: $current_state"

    local cloud_provider
    cloud_provider=$(state_read "$deploy_dir" "cloud_provider" 2>/dev/null || echo "unknown")
    local infra_power_supported="false"
    case "$cloud_provider" in
        aws|azure|gcp)
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
        die "Stop playbook not found"
    fi

    # Check if inventory file exists
    if [[ ! -f "$deploy_dir/inventory.ini" ]]; then
        log_error "Ansible inventory not found: inventory.ini"
        state_set_status "$deploy_dir" "$STATE_STOP_FAILED"
        die "Ansible inventory not found"
    fi

    # Run Ansible to stop the database
    local ansible_extra=(-i inventory.ini .templates/stop-exasol-cluster.yml)
    [[ "$infra_power_supported" == "false" ]] && ansible_extra+=(-e "power_off_fallback=true")

    if ! ansible-playbook "${ansible_extra[@]}"; then
        # For providers without infra power control, unreachable hosts after shutdown are expected
        if [[ "$infra_power_supported" == "false" ]]; then
            log_warn "Ansible reported unreachable hosts after shutdown; this is expected if VMs are powered off."
        else
            state_set_status "$deploy_dir" "$STATE_STOP_FAILED"
            die "Ansible stop operation failed"
        fi
    fi

    # If provider supports infra power control, stop instances via tofu
    if [[ "$infra_power_supported" == "true" ]]; then
        # Note: We enable refresh to ensure Terraform sees the current state (running=true)
        # This is important for all providers to detect state drift and apply changes correctly
        if ! tofu apply -auto-approve -target="aws_ec2_instance_state.exasol_node_state" -target="azapi_resource_action.vm_power_off" -target="google_compute_instance.exasol_node" -target="libvirt_domain.exasol_node" -var "infra_desired_state=stopped"; then
            state_set_status "$deploy_dir" "$STATE_STOP_FAILED"
            die "Infrastructure stop (tofu apply) failed"
        fi
    else
        log_warn "Provider '$cloud_provider' does not support power control via tofu."
        log_info ""
        log_info "Instances have been issued an in-guest shutdown command."
        log_info ""
    fi

    # Verify VMs are actually powered off by checking SSH connectivity
    # If we can SSH to any VM, the power-off failed
    log_info "Verifying VMs are powered off..."
    local -a hosts=()
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^\[.*\] ]] && continue
        local host
        host=$(echo "$line" | awk '{print $1}')
        [[ -n "$host" ]] && hosts+=("$host")
    done < <(awk '/^\[exasol_nodes\]/,/^\[/ {print}' "$deploy_dir/inventory.ini")

    local -a check_pids=()
    local temp_dir
    temp_dir=$(mktemp -d)

    for host in "${hosts[@]}"; do
        (
            if ssh -F "$deploy_dir/ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$host" \
                "true" >/dev/null 2>&1; then
                echo "running" > "$temp_dir/$host"
            else
                echo "stopped" > "$temp_dir/$host"
            fi
        ) &
        check_pids+=($!)
    done

    for pid in "${check_pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # For providers without infra power control, unreachable hosts after shutdown are success
    if [[ "$infra_power_supported" == "false" ]]; then
        local all_stopped=true
        for host in "${hosts[@]}"; do
            if [[ -f "$temp_dir/$host" ]] && grep -q "running" "$temp_dir/$host"; then
                all_stopped=false
                break
            fi
        done
        if [[ "$all_stopped" == "true" ]]; then
            state_set_status "$deploy_dir" "$STATE_STOPPED"
            operation_success
            log_info "✓ All VMs are powered off and unreachable. Stop operation successful."
            return 0
        else
            state_set_status "$deploy_dir" "$STATE_STOP_FAILED"
            die "Some VMs are still reachable after stop operation."
        fi
    fi

    # Check results - if any VM is still reachable via SSH, stop failed
    local any_running=false
    for host in "${hosts[@]}"; do
        if [[ -f "$temp_dir/$host" ]] && [[ "$(cat "$temp_dir/$host")" == "running" ]]; then
            log_warn "VM $host is still reachable via SSH"
            any_running=true
        fi
    done

    rm -rf "$temp_dir"

    if [[ "$any_running" == true ]]; then
        state_set_status "$deploy_dir" "$STATE_STOP_FAILED"
        operation_success  # Remove lock
        log_error ""
        log_error "✗ Stop operation completed but VMs are still running"
        log_error ""
        log_error "Status set to 'stop_failed'. Please check the logs and try again."
        return 1
    fi

    # All VMs powered off successfully
    state_set_status "$deploy_dir" "$STATE_STOPPED"
    operation_success

    # Display results
    log_info ""
    log_info "✓ Exasol Database Stopped Successfully!"
    log_info ""
    log_info "VMs have been powered off."
    log_info "To restart the database, run: exasol start --deployment-dir $deploy_dir"
    log_info "To terminate cloud instances, run: exasol destroy --deployment-dir $deploy_dir"
}
