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
Infrastructure planning:::Creating cloud infrastructure|Initializing the backend|Initializing provider plugins|OpenTofu used the selected providers|execution plan|tofu (init|plan)
Network setup:::vpc|subnet|network interface|network_interface|security group|firewall|virtual network|vnet|route table|nat gateway
Instance creation:::aws_instance|libvirt_domain|droplet|virtual machine|compute instance|exasol_node|instance_state
Storage provisioning:::volume|disk|block_device|storage account|root_volume|data_volume|ebs
Ansible connection setup:::Configuring cluster with Ansible|ansible-playbook|inventory\\.ini|ssh_config|PLAY \\[Play 1 - Gather Host Facts\\]
Exasol installation:::Setup and Configure Exasol Cluster|Install Exasol|Exasol installation|Load credentials and configuration|Derive artifact
Cluster configuration:::Configure cluster|Create final Exasol config|hosts file entry|Apply configuration|Verify C4 configuration
Service startup:::Start Exasol database deployment|Starting services|Wait for C4 deployment|c4\\.service|c4_cloud_command
Health checks:::Wait for database to boot|Health check|Health report|Status reached: database_ready
Deployment validation:::Deployment complete|Deployment completed|Deployment Complete!|Cluster Deployment Complete|deployment completed!
EOF
}

progress_start_steps() {
    cat <<'EOF'
Powering on instances:::Powering on instances|Powering on the VMs|power on the VMs|aws_ec2_instance_state.*->.*running|Starting Exasol database cluster
Waiting for boot:::Waiting for cluster to become healthy|Waiting for status|Health check remaining time|Refreshing Terraform state
Starting Exasol services:::Starting database services via Ansible|Start Exasol Database|Play 2 - Start Exasol Database|Start Exasol database cluster on|Status reached: database_ready
Health checks:::Health report|Health check completed|Database Started Successfully|database services have been started
EOF
}

progress_stop_steps() {
    cat <<'EOF'
Stopping Exasol services:::Stopping Exasol database cluster|Stop Exasol Database|Stop c4\\.service|Stop c4_cloud_command\\.service
Verifying service shutdown:::Verify all services are stopped|stage a/a1|stop summary|Confirm successful stop|cluster stopped successfully
Powering off instances:::Powering off|state.*->.*stopped|Stopping instances|power control|does not support automatic power control|Power off hosts via in-guest shutdown
Verification:::PLAY RECAP|stop completed
EOF
}

progress_destroy_steps() {
    cat <<'EOF'
Infrastructure planning:::Destroying cloud infrastructure|execution plan|will be destroyed
Destroying instances:::exasol_node.*destroy|aws_instance.*destroy|instance .*destroy
Destroying storage:::volume.*destroy|disk.*destroy|block device.*destroy
Destroying network:::vpc.*destroy|subnet.*destroy|security group.*destroy|network.*destroy
Cleanup verification:::Destroy complete!|Deployment Destroyed Successfully|resources have been destroyed
EOF
}
