terraform {
  required_version = ">= 1.0"
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = "~> 0.59"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "exoscale" {
  key    = var.exoscale_api_key
  secret = var.exoscale_api_secret
}

# ==============================================================================
# SSH Key Pair - Exoscale-specific wrapper
# Common SSH key generation (tls_private_key, local_file, random_id) is in common.tf
# ==============================================================================

resource "exoscale_ssh_key" "exasol_auth" {
  name       = "exasol-cluster-key-${random_id.instance.hex}"
  public_key = tls_private_key.exasol_key.public_key_openssh
}

locals {
  # Provider-specific info for common outputs
  provider_name = "Exoscale"
  provider_code = "exoscale"
  region_name   = var.exoscale_zone

  # Private network CIDR and IP assignments
  private_network_cidr = "10.0.0.0/24"
  private_network_start = "10.0.0.10"
  
  # Generate deterministic private IPs for each node
  node_private_ips_static = [
    for i in range(var.node_count) : cidrhost(local.private_network_cidr, 10 + i)
  ]

  # Physical IPs for multicast overlay (deterministic private IPs)
  physical_ips = local.node_private_ips_static

  # Node IPs for common outputs
  node_public_ips  = [for instance in exoscale_compute_instance.exasol_nodes : instance.public_ip_address]
  node_private_ips = var.enable_multicast_overlay ? local.overlay_network_ips : local.physical_ips

  # VXLAN multicast overlay (uses common logic)
  overlay_data = local.overlay_data_common

  # Exoscale-specific cloud-init template with private network configuration
  cloud_init_template_path = "${path.module}/.templates/cloud-init-exoscale.tftpl"

  # Node volumes for Ansible inventory
  # Exoscale uses volume IDs for device paths
  node_volumes = {
    for node_idx in range(var.node_count) : node_idx => [
      for vol_idx in range(var.data_volumes_per_node) :
      exoscale_block_storage_volume.exasol_data[node_idx * var.data_volumes_per_node + vol_idx].id
    ]
  }
}

# ==============================================================================
# Private Network
# ==============================================================================

resource "exoscale_private_network" "exasol_cluster" {
  zone        = var.exoscale_zone
  name        = "exasol-private-${random_id.instance.hex}"
  description = "Private network for Exasol cluster"
  
  netmask  = "255.255.255.0"
  start_ip = local.private_network_start
  end_ip   = cidrhost(local.private_network_cidr, 250)

  labels = {
    owner = var.owner
    role  = "exasol-network"
  }
}

# ==============================================================================
# Security Group
# ==============================================================================

resource "exoscale_security_group" "exasol_cluster" {
  name        = "exasol-cluster-${random_id.instance.hex}"
  description = "Security group for Exasol cluster"
}

# External access rules - dynamically created for each port using common firewall configuration
resource "exoscale_security_group_rule" "external_access" {
  for_each = local.exasol_firewall_ports

  security_group_id = exoscale_security_group.exasol_cluster.id
  type              = "INGRESS"
  protocol          = "TCP"
  start_port        = each.key
  end_port          = each.key
  cidr              = var.allowed_cidr
  description       = each.value
}

resource "exoscale_security_group_rule" "cluster_internal" {
  security_group_id      = exoscale_security_group.exasol_cluster.id
  type                   = "INGRESS"
  protocol               = "TCP"
  start_port             = 1
  end_port               = 65535
  user_security_group_id = exoscale_security_group.exasol_cluster.id
  description            = "Internal cluster communication"
}

resource "exoscale_security_group_rule" "cluster_internal_udp" {
  security_group_id      = exoscale_security_group.exasol_cluster.id
  type                   = "INGRESS"
  protocol               = "UDP"
  start_port             = 1
  end_port               = 65535
  user_security_group_id = exoscale_security_group.exasol_cluster.id
  description            = "Internal cluster communication (UDP)"
}

# ==============================================================================
# Compute Instances
# ==============================================================================

resource "exoscale_compute_instance" "exasol_nodes" {
  count = var.node_count
  
  name        = "exasol-node-${count.index + 1}-${random_id.instance.hex}"
  zone        = var.exoscale_zone
  type        = var.instance_type
  template_id = data.exoscale_template.ubuntu.id
  
  disk_size = var.root_volume_size
  
  ssh_key = exoscale_ssh_key.exasol_auth.name
  
  security_group_ids = [exoscale_security_group.exasol_cluster.id]
  
  # Power state management - stop/start instances without destroying them
  state = var.infra_desired_state == "stopped" ? "stopped" : "running"
  
  # Attach to private network with static IP
  network_interface {
    network_id = exoscale_private_network.exasol_cluster.id
    ip_address = local.node_private_ips_static[count.index]
  }
  
  # Attach data volumes to this instance
  block_storage_volume_ids = [
    for vol_idx in range(var.data_volumes_per_node) :
    exoscale_block_storage_volume.exasol_data[count.index * var.data_volumes_per_node + vol_idx].id
  ]
  
  user_data = base64encode(templatefile(local.cloud_init_template_path, {
    base_cloud_init = local.cloud_init_script
  }))

  labels = {
    owner = var.owner
    role  = "exasol-node"
  }

  # Prevent destruction during normal operations
  lifecycle {
    ignore_changes = [
      user_data,
      template_id
    ]
  }

  depends_on = [
    exoscale_block_storage_volume.exasol_data,
    exoscale_private_network.exasol_cluster
  ]
}

# ==============================================================================
# Data Volume Storage
# ==============================================================================

resource "exoscale_block_storage_volume" "exasol_data" {
  count = var.node_count * var.data_volumes_per_node
  
  name = "exasol-data-${floor(count.index / var.data_volumes_per_node) + 1}-${(count.index % var.data_volumes_per_node) + 1}-${random_id.instance.hex}"
  zone = var.exoscale_zone
  size = var.data_volume_size
  
  labels = {
    owner = var.owner
    role  = "exasol-data"
  }
}

# ==============================================================================
# Data Sources
# ==============================================================================

data "exoscale_template" "ubuntu" {
  zone = var.exoscale_zone
  name = "Linux Ubuntu 22.04 LTS 64-bit"
}
