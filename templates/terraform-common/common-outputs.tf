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
        IdentityFile ${abspath(local_file.exasol_private_key_pem.filename)}
        StrictHostKeyChecking no
        UserKnownHostsFile=/dev/null

    EOF
  ])

  # Generate simple summary output (provider-agnostic)
  # Each provider should set local.provider_name and local.region_name
  summary_box = <<-EOT
    ✅ Exasol Cluster Deployment (${local.provider_name}) Complete!
    
    Cluster Information:
    - Cluster ID: ${random_id.instance.hex}
    - Region: ${local.region_name}
    - Node Count: ${var.node_count}
    - Instance Type: ${var.instance_type}
    - Architecture: ${var.instance_architecture}
    
    Connection Information:
    - SSH Key: ${local_file.exasol_private_key_pem.filename}
    - SSH Config: ${local_file.ssh_config.filename}
    - Inventory: ${local_file.ansible_inventory.filename}
    
    Node Access:
    %{for idx, ip in local.node_public_ips~}
    - n${idx + 11}: ${ip} (ssh -F ${local_file.ssh_config.filename} n${idx + 11})
    %{endfor~}
    
    Next Steps:
    1. Wait ~60 seconds for instances to fully boot
    2. Run Ansible: ansible-playbook -i ${local_file.ansible_inventory.filename} setup-exasol-cluster.yml
    3. Connect using SSH commands above
  EOT
}

# Standard outputs (to be included in each provider's outputs.tf)
output "summary" {
  description = "Deployment summary with connection information"
  value       = local.summary_box
}

output "cluster_id" {
  description = "Unique identifier for this cluster deployment"
  value       = random_id.instance.hex
}

output "node_public_ips" {
  description = "Public IP addresses of all nodes"
  value       = local.node_public_ips
}

output "node_private_ips" {
  description = "Private IP addresses of all nodes"
  value       = local.node_private_ips
}

output "node_names" {
  description = "Names of all nodes"
  value       = [for idx in range(var.node_count) : "n${idx + 11}"]
}

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

output "ansible_command" {
  description = "The command to run the Ansible playbook"
  value       = "ansible-playbook -i ${local_file.ansible_inventory.filename} setup-exasol-cluster.yml"
}

output "open_ports" {
  description = "Open ports for the Exasol cluster"
  value       = [for port, desc in local.exasol_firewall_ports : { port = port, name = desc }]
}
