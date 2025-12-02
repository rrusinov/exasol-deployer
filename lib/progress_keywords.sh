#!/usr/bin/env bash
# Keyword definitions for progress tracking

# Include guard
if [[ -n "${__EXASOL_PROGRESS_KEYWORDS_SH_INCLUDED__:-}" ]]; then
    return 0
fi
readonly __EXASOL_PROGRESS_KEYWORDS_SH_INCLUDED__=1

# Return ordered step definitions for a given operation.
# Each line: "<label>:::<pattern>"
progress_get_step_definitions() {
    local operation="$1"
    case "$operation" in
        deploy)
            progress_deploy_steps
            ;;
        start)
            progress_start_steps
            ;;
        stop)
            progress_stop_steps
            ;;
        destroy)
            progress_destroy_steps
            ;;
        *)
            return 1
            ;;
    esac
}

progress_deploy_steps() {
    cat <<'EOF'
Terraform Init:::PROGRESS_MARKER: deploy:01|tofu init|terraform init|Initializing the backend|Initializing provider plugins
Network Creation:::PROGRESS_MARKER: deploy:02|(vpc|network|vnet).*Creating|subnet.*Creating|security.*group.*Creating|firewall.*Creating
Compute Provisioning:::PROGRESS_MARKER: deploy:03|(instance|server|domain|droplet).*Creating|exasol_node.*Creating
Volume Provisioning:::PROGRESS_MARKER: deploy:04|(volume|disk).*Creating|block_device.*Creating
SSH Connectivity:::PROGRESS_MARKER: deploy:05|Waiting for VMs to boot and SSH to become available|Testing SSH connectivity to nodes
Ansible Connection:::PROGRESS_MARKER: deploy:06|PLAY \\[Play 1.*Gather Host Facts\\]|Configuring cluster with Ansible
Node Configuration:::PROGRESS_MARKER: deploy:07|SECTION 1:.*Node & Network Setup|Set hostname to n11|Install required system packages
SSH Key Distribution:::PROGRESS_MARKER: deploy:08|SECTION 2:.*SSH.*Inter-Node|Generate SSH key for exasol user
GRE Mesh Services Started:::PROGRESS_MARKER: deploy:08c|GRE_Mesh_Services_Started
GRE Mesh Connectivity Validated:::PROGRESS_MARKER: deploy:08d|GRE_Mesh_Connectivity_Validated
Disk Discovery:::PROGRESS_MARKER: deploy:09|SECTION 3A:.*Discover data disks|exasol-data-symlinks|Discover existing /dev/exasol_data
Config Generation:::PROGRESS_MARKER: deploy:10|Create final Exasol config|PLAY \\[Play 3.*Final Configuration
Artifact Transfer:::PROGRESS_MARKER: deploy:11|(Transfer|Download).*(database|c4)|local Exasol database tarball|Download Exasol database
Checksum Verification:::PROGRESS_MARKER: deploy:12|SECTION 5:.*Verify Checksums|Verify database tarball checksum|Verify c4 binary checksum
C4 Diagnostic:::PROGRESS_MARKER: deploy:13|Verify C4 configuration diagnostic|c4 host diag
Exasol Deployment:::PROGRESS_MARKER: deploy:14|Start Exasol database deployment|c4 host play
Database Startup:::PROGRESS_MARKER: deploy:15|Wait for database to boot.*stage.*d|Wait for C4 deployment
Deploy Complete:::PROGRESS_MARKER: deploy:16|cluster deployment completed|Exasol cluster deployment completed
EOF
}

progress_start_steps() {
    cat <<'EOF'
Infrastructure Power-On:::PROGRESS_MARKER: start:01|Powering on instances|Powering on the VMs|aws_ec2_instance_state.*->.*running|Starting Exasol database cluster
SSH Connectivity:::PROGRESS_MARKER: start:02|Waiting for VMs to boot and SSH to become available|Testing SSH connectivity to nodes
Ansible Connection:::PROGRESS_MARKER: start:03|PLAY \\[Play 1.*Gather Host Facts\\]|Waiting for cluster to become healthy
Service Startup:::PROGRESS_MARKER: start:04|Start (c4\\.service|c4_cloud_command)|Starting database services via Ansible|Play 2 - Start Exasol Database
Database Boot:::PROGRESS_MARKER: start:05|Wait.*stage.*d|All.*nodes reached.*stage.*d|Status reached: database_ready
Start Complete:::PROGRESS_MARKER: start:06|started successfully.*all nodes|Database Started Successfully|database services have been started
EOF
}

progress_stop_steps() {
    cat <<'EOF'
Database Shutdown:::PROGRESS_MARKER: stop:01|Database shutdown complete|Found running databases|Stop each running database|Verify databases are stopped
Service Shutdown:::PROGRESS_MARKER: stop:02|Stopping Exasol database cluster|Stop Exasol Database|Stop (c4\\.service|c4_cloud_command)
Stage Verification:::PROGRESS_MARKER: stop:03|Wait.*stage (a|a1)|nodes.*stage.*a/a1|Verify all services are stopped
Infrastructure Power-Off:::PROGRESS_MARKER: stop:04|Powering off|power control|in-guest shutdown|state.*->.*stopped
Stop Validation:::PROGRESS_MARKER: stop:05|PLAY RECAP|stop summary
Stop Complete:::PROGRESS_MARKER: stop:06|stopped successfully|stop completed|cluster stopped successfully
EOF
}

progress_destroy_steps() {
    cat <<'EOF'
Destroy Planning:::PROGRESS_MARKER: destroy:01|Destroying cloud infrastructure|execution plan|will be destroyed
Compute Removal:::PROGRESS_MARKER: destroy:02|(instance|server|domain|droplet).*destroy|exasol_node.*destroy
Volume Removal:::PROGRESS_MARKER: destroy:03|(volume|disk).*destroy|block device.*destroy
Network Removal:::PROGRESS_MARKER: destroy:04|(vpc|network|subnet|security.*group).*destroy|firewall.*destroy
Destroy Complete:::PROGRESS_MARKER: destroy:05|Destroy complete!|Deployment Destroyed Successfully|resources have been destroyed
EOF
}
