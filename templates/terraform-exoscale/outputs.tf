# Exoscale-specific outputs

output "public_ips" {
  description = "Public IP addresses of the instances"
  value       = exoscale_compute_instance.exasol_nodes[*].public_ip_address
}

output "private_ips" {
  description = "Private IP addresses of the instances"
  value       = local.node_private_ips_static
}

output "instance_ids" {
  description = "Instance IDs"
  value       = exoscale_compute_instance.exasol_nodes[*].id
}

output "ssh_key_name" {
  description = "SSH key name"
  value       = exoscale_ssh_key.exasol_auth.name
}
