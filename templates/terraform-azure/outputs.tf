output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.exasol.name
}

output "node_public_ips" {
  description = "Public IP addresses of all nodes"
  value       = azurerm_public_ip.exasol_node[*].ip_address
}

output "node_private_ips" {
  description = "Private IP addresses of all nodes"
  value       = azurerm_network_interface.exasol_node[*].private_ip_address
}

output "node_names" {
  description = "Names of all nodes"
  value       = azurerm_linux_virtual_machine.exasol_node[*].name
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
