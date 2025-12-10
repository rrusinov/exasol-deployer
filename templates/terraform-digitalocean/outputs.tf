# DigitalOcean-specific outputs in addition to common outputs
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
