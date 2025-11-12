# ==============================================================================
# COMMON OUTPUTS
# Helper locals for generating outputs (used by provider-specific outputs.tf)
# ==============================================================================

locals {
  # SSH config content generator (provider-agnostic)
  ssh_config_content = join("\n", [
    for idx, ip in local.node_public_ips : <<-EOF
    Host n${idx + 11}
        HostName ${ip}
        User exasol
        IdentityFile ${local_file.exasol_private_key_pem.filename}
        StrictHostKeyChecking no
        UserKnownHostsFile=/dev/null

    EOF
  ])
}

# Standard outputs (to be included in each provider's outputs.tf)
output "ssh_key_path" {
  description = "Path to the SSH private key"
  value       = local_file.exasol_private_key_pem.filename
}

output "ssh_config_path" {
  description = "Path to the SSH config file"
  value       = local_file.ssh_config.filename
}

output "inventory_path" {
  description = "Path to the Ansible inventory file"
  value       = local_file.ansible_inventory.filename
}
