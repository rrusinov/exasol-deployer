output "project_id" {
  description = "The GCP project ID"
  value       = var.gcp_project
}

output "node_public_ips" {
  description = "Public IP addresses of all nodes"
  value       = [for instance in google_compute_instance.exasol_node : instance.network_interface[0].access_config[0].nat_ip]
}

output "node_private_ips" {
  description = "Private IP addresses of all nodes"
  value       = [for instance in google_compute_instance.exasol_node : instance.network_interface[0].network_ip]
}

output "node_names" {
  description = "Names of all nodes"
  value       = google_compute_instance.exasol_node[*].name
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
