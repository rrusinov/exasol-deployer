# ==============================================================================
# OUTPUTS - Libvirt Provider
# ==============================================================================
# Standard outputs are included from common-outputs.tf
# This file only contains libvirt-specific outputs

output "cluster_info" {
  description = "Libvirt-specific cluster information"
  value = {
    node_count    = var.node_count
    instance_type = "libvirt-custom"
    memory_gb     = var.libvirt_memory_gb
    vcpus         = var.libvirt_vcpus
    network       = var.libvirt_network_bridge
    storage_pool  = var.libvirt_disk_pool
  }
}

output "access_urls" {
  description = "Access URLs for cluster services"
  value = {
    admin_ui = "https://${local.node_public_ips[0]}:8443"
    database = "${local.node_public_ips[0]}:8563"
  }
  sensitive = true
}