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

This command powers on cloud instances (if supported) and waits for the
database to become healthy. For providers without automatic power control
(DigitalOcean, Hetzner, libvirt), you'll be prompted to manually power on
the machines first.

Usage:
  exasol start [flags]

Flags:
  --deployment-dir <path>        Directory with deployment files (default: ".")
  -h, --help                     Show help

Prerequisites:
  - Deployment must be in 'stopped' or 'start_failed' state
  - No other operations can be in progress

Behavior by Provider:
  - AWS/Azure/GCP: Automatically powers on instances and waits for database
  - DigitalOcean/Hetzner/libvirt: Displays power-on instructions and waits

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

    # Step 1: Set status to start_in_progress (operation guard start)
    state_set_status "$deploy_dir" "$STATE_START_IN_PROGRESS"

    log_info "Starting Exasol database cluster..."
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

    # Prepare exasol command path for later use
    local exasol_cmd="${LIB_DIR}/../exasol"

    # Check if required files exist
    if [[ ! -f "$deploy_dir/.templates/start-exasol-cluster.yml" ]]; then
        log_error "Ansible playbook not found: .templates/start-exasol-cluster.yml"
        state_set_status "$deploy_dir" "$STATE_START_FAILED"
        die "Start playbook not found"
    fi

    if [[ ! -f "$deploy_dir/inventory.ini" ]]; then
        log_error "Ansible inventory not found: inventory.ini"
        state_set_status "$deploy_dir" "$STATE_START_FAILED"
        die "Ansible inventory not found"
    fi

    # Step 2: Infrastructure start (automatic for aws/gcp/azure; manual for libvirt/digitalocean/hetzner)
    if [[ "$infra_power_supported" == "true" ]]; then
        log_info "Powering on instances via tofu..."
        # Note: We enable refresh to ensure Terraform sees the current state (running=false)
        # This is important for all providers to detect state drift and apply changes correctly
        if ! tofu apply -auto-approve -target="aws_ec2_instance_state.exasol_node_state" -target="azapi_resource_action.vm_power_on" -target="google_compute_instance.exasol_node" -target="libvirt_domain.exasol_node" -var "infra_desired_state=running"; then
            state_set_status "$deploy_dir" "$STATE_START_FAILED"
            operation_success  # Release lock
            die "Infrastructure start (tofu apply) failed"
        fi

        # Refresh Terraform state to get updated IPs (critical for AWS where IPs change on stop/start)
        log_info "Refreshing Terraform state to fetch updated IPs..."
        if ! tofu refresh -var "infra_desired_state=running" >/dev/null 2>&1; then
            log_warn "Failed to refresh Terraform state; inventory may have stale IPs"
        fi

        # Regenerate inventory and ssh_config with new IPs from refreshed state
        log_info "Regenerating inventory and ssh_config with updated IPs..."
        if ! tofu apply -auto-approve -refresh=false \
            -target="local_file.ansible_inventory" \
            -target="local_file.ssh_config" \
            -target="local_file.info_file" \
            -var "infra_desired_state=running" >/dev/null 2>&1; then
            log_warn "Failed to regenerate inventory files; attempting to continue"
        fi

        # Run Ansible to start the database services
        log_info "Starting database services via Ansible..."
        if ! ansible-playbook -i inventory.ini .templates/start-exasol-cluster.yml; then
            state_set_status "$deploy_dir" "$STATE_START_FAILED"
            die "Ansible start operation failed"
        fi

        # Validate database connectivity (optional - best effort)
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
            state_set_status "$deploy_dir" "$STATE_DATABASE_READY"
        else
            state_set_status "$deploy_dir" "$STATE_DATABASE_CONNECTION_FAILED"
            log_warn "Database started but connectivity could not be fully validated"
        fi
        operation_success

        # Display results
        log_info ""
        log_info "✓ Exasol Database Started Successfully!"
        log_info ""
        log_info "The database services have been started and should be ready for use."
        return 0
    else
        log_warn "Provider '$cloud_provider' does not support automatic power control."
        log_info ""

        # Provider-specific power-on instructions
        case "$cloud_provider" in
            libvirt)
                log_info "Please power on the VMs using virsh:"
                log_info "  virsh list --all  # List all VMs to find the VM names"
                log_info "  virsh start <vm-name>  # Start each VM"
                log_info ""
                log_info "Alternatively, use virt-manager GUI to power on the VMs."
                ;;
            digitalocean)
                log_info "Please power on the Droplets using DigitalOcean console or CLI:"
                log_info "  Web Console: https://cloud.digitalocean.com/droplets"
                log_info "  CLI: doctl compute droplet-action power-on <droplet-id>"
                log_info ""
                log_info "To list all droplets: doctl compute droplet list"
                ;;
            hetzner)
                log_info "Please power on the servers using Hetzner Cloud Console or CLI:"
                log_info "  Web Console: https://console.hetzner.cloud/"
                log_info "  CLI: hcloud server poweron <server-name>"
                log_info ""
                log_info "To list all servers: hcloud server list"
                ;;
            *)
                log_info "Please manually power on the machines using your provider's interface."
                ;;
        esac

        log_info ""
    fi

    # Step 3: For manual providers, set status to 'started' and wait for health.
    # Keep the start operation lock in place so only this command updates state;
    # do not mark operation_success until health completes.
    state_set_status "$deploy_dir" "$STATE_STARTED"

    # Step 4: Call health --update --wait-for database_ready,15m
    log_info "Waiting for cluster to become healthy (timeout: 15 minutes)..."
    log_info ""

    if "$exasol_cmd" health --deployment-dir "$deploy_dir" --update --wait-for database_ready,15m; then
        # Step 5: Success - print result and return
        log_info ""
        log_info "✓ Exasol Database Started Successfully!"
        log_info ""
        log_info "The database services have been started and are ready for use."
        operation_success
        return 0
    else
        # Step 5: Failure - print error and return
        log_error ""
        log_error "✗ Failed to reach 'database_ready' status within 15 minutes."
        log_error ""
        log_error "Please verify that:"
        if [[ "$infra_power_supported" == "false" ]]; then
            log_error "  1. VMs have been manually powered on via your provider interface"
            log_error "  2. VMs are reachable via SSH"
        else
            log_error "  1. VMs are reachable via SSH"
        fi
        log_error "  3. Database services are running"
        log_error ""
        log_error "Run 'exasol health --deployment-dir $deploy_dir' for detailed diagnostics"
        log_error ""
        state_set_status "$deploy_dir" "$STATE_START_FAILED"
        operation_success
        return 1
    fi
}
