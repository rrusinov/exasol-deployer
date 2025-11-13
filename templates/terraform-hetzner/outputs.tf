# Hetzner-specific outputs in addition to common outputs
output "network_id" {
  description = "Hetzner Network ID"
  value       = hcloud_network.exasol_network.id
}

output "firewall_id" {
  description = "Hetzner Firewall ID"
  value       = hcloud_firewall.exasol_cluster.id
}

output "data_volume_ids" {
  description = "IDs of all data volumes"
  value       = [for vol in hcloud_volume.data_volume : vol.id]
}


