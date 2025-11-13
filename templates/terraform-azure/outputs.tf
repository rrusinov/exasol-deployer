# Azure-specific outputs in addition to common outputs
output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.exasol.name
}

output "node_names" {
  description = "Names of all nodes"
  value       = azurerm_linux_virtual_machine.exasol_node[*].name
}
