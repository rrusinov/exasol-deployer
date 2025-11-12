# ==============================================================================
# DIGITALOCEAN OUTPUTS
# ==============================================================================

output "cluster_id" {
  description = "Unique identifier for this cluster deployment"
  value       = random_id.instance.hex
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

output "node_public_ips" {
  description = "Public IP addresses of all nodes"
  value       = [for droplet in digitalocean_droplet.exasol_node : droplet.ipv4_address]
}

output "node_private_ips" {
  description = "Private IP addresses of all nodes"
  value       = local.node_private_ips
}

output "node_names" {
  description = "Names of all nodes"
  value       = [for idx in range(var.node_count) : "n${idx + 11}"]
}

output "vpc_id" {
  description = "DigitalOcean VPC ID"
  value       = digitalocean_vpc.exasol_vpc.id
}

output "firewall_id" {
  description = "DigitalOcean Firewall ID"
  value       = digitalocean_firewall.exasol_cluster.id
}

output "data_volume_ids" {
  description = "IDs of all data volumes"
  value       = [for vol in digitalocean_volume.data_volume : vol.id]
}

output "summary" {
  description = "Deployment summary"
  value = <<-EOT
    ╔════════════════════════════════════════════════════════════════════════════╗
    ║              Exasol Cluster Deployment (DigitalOcean)                      ║
    ╠════════════════════════════════════════════════════════════════════════════╣
    ║ Cluster ID:     ${random_id.instance.hex}
    ║ Region:         ${var.digitalocean_region}
    ║ Node Count:     ${var.node_count}
    ║ Instance Type:  ${var.instance_type}
    ║ Architecture:   ${var.instance_architecture}
    ╠════════════════════════════════════════════════════════════════════════════╣
    ║ SSH Key:        ${local_file.exasol_private_key_pem.filename}
    ║ SSH Config:     ${local_file.ssh_config.filename}
    ║ Inventory:      ${local_file.ansible_inventory.filename}
    ╠════════════════════════════════════════════════════════════════════════════╣
    ║ Node IPs:                                                                  ║
    %{for idx, ip in digitalocean_droplet.exasol_node[*].ipv4_address~}
    ║   n${idx + 11}: ${ip}
    %{endfor~}
    ╚════════════════════════════════════════════════════════════════════════════╝
  EOT
}
