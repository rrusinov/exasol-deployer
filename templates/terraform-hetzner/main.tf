terraform {
  required_version = ">= 1.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.48"
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

provider "hcloud" {
  token = var.hetzner_token
}

# ==============================================================================
# SSH Key Pair - Hetzner-specific wrapper
# Common SSH key generation (tls_private_key, local_file, random_id) is in common.tf
# ==============================================================================

resource "hcloud_ssh_key" "exasol_auth" {
  name       = "exasol-cluster-key-${random_id.instance.hex}"
  public_key = tls_private_key.exasol_key.public_key_openssh

  labels = {
    owner = var.owner
  }
}

locals {
  # Provider-specific info for common outputs
  provider_name = "Hetzner Cloud"
  region_name = var.hetzner_location

  # Map architecture to Hetzner server type prefix
  # Hetzner uses different naming: cx, cpx, ccx series for x86_64, cax for arm64
  server_type_prefix = var.instance_architecture == "arm64" ? "cax" : "cpx"

  # Group volume IDs by node for Ansible inventory
  node_volumes = {
    for node_idx in range(var.node_count) : node_idx => [
      for vol_idx in range(var.data_volumes_per_node) :
      hcloud_volume.data_volume[node_idx * var.data_volumes_per_node + vol_idx].id
    ]
  }

  # Node IPs for common outputs
  node_public_ips = [for server in hcloud_server.exasol_node : server.ipv4_address]
  node_private_ips = local.node_public_ips
}

# Get available Hetzner locations
data "hcloud_locations" "available" {}

# ==============================================================================
# NETWORKING
# ==============================================================================

resource "hcloud_network" "exasol_network" {
  name     = "exasol-network-${random_id.instance.hex}"
  ip_range = "10.0.0.0/16"

  labels = {
    owner = var.owner
  }
}

resource "hcloud_network_subnet" "exasol_subnet" {
  network_id   = hcloud_network.exasol_network.id
  type         = "cloud"
  network_zone = var.hetzner_network_zone
  ip_range     = "10.0.1.0/24"
}

# ==============================================================================
# FIREWALL
# ==============================================================================

resource "hcloud_firewall" "exasol_cluster" {
  name = "exasol-cluster-fw-${random_id.instance.hex}"

  labels = {
    owner = var.owner
  }

  # SSH access
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [var.allowed_cidr]
  }

  # Default bucketfs
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "2581"
    source_ips = [var.allowed_cidr]
  }

  # Exasol Admin UI
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8443"
    source_ips = [var.allowed_cidr]
  }

  # Exasol database connection
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8563"
    source_ips = [var.allowed_cidr]
  }

  # Exasol container ssh
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "20002"
    source_ips = [var.allowed_cidr]
  }

  # Exasol confd API
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "20003"
    source_ips = [var.allowed_cidr]
  }

  # ICMP for network diagnostics
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = [var.allowed_cidr]
  }

  # Allow all traffic within the cluster (using private network)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "any"
    source_ips = ["10.0.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "any"
    source_ips = ["10.0.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["10.0.0.0/16"]
  }
}

# ==============================================================================
# COMPUTE INSTANCES
# ==============================================================================

# Get latest Ubuntu 24.04 image
data "hcloud_image" "ubuntu" {
  with_selector     = "os-flavor=ubuntu"
  with_architecture = var.instance_architecture
  most_recent       = true
  # Filter for Ubuntu 24.04 - Hetzner uses format like "ubuntu-24.04"
}

resource "hcloud_server" "exasol_node" {
  count       = var.node_count
  name        = "n${count.index + 11}-${random_id.instance.hex}"
  server_type = var.instance_type
  location    = var.hetzner_location
  image       = data.hcloud_image.ubuntu.id
  ssh_keys    = [hcloud_ssh_key.exasol_auth.id]
  firewall_ids = [hcloud_firewall.exasol_cluster.id]

  labels = {
    owner   = var.owner
    role    = "worker"
    cluster = "exasol-cluster"
    node    = "n${count.index + 11}"
  }

  # Cloud-init user-data to create exasol user before Ansible runs
  user_data = local.cloud_init_script

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  # Wait for server to be ready
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

# Attach servers to private network
resource "hcloud_server_network" "exasol_node_network" {
  count     = var.node_count
  server_id = hcloud_server.exasol_node[count.index].id
  network_id = hcloud_network.exasol_network.id
  ip        = "10.0.1.${count.index + 10}"
}

# ==============================================================================
# STORAGE VOLUMES
# ==============================================================================

# Data Volumes
resource "hcloud_volume" "data_volume" {
  count    = var.node_count * var.data_volumes_per_node
  name     = "n${floor(count.index / var.data_volumes_per_node) + 11}-data-${(count.index % var.data_volumes_per_node) + 1}-${random_id.instance.hex}"
  size     = var.data_volume_size
  location = var.hetzner_location
  format   = "ext4"

  labels = {
    owner       = var.owner
    cluster     = "exasol-cluster"
    volume_index = tostring((count.index % var.data_volumes_per_node) + 1)
    node_index  = tostring(floor(count.index / var.data_volumes_per_node) + 11)
  }
}

# Attach Data Volumes to Servers
resource "hcloud_volume_attachment" "data_attachment" {
  count     = var.node_count * var.data_volumes_per_node
  volume_id = hcloud_volume.data_volume[count.index].id
  server_id = hcloud_server.exasol_node[floor(count.index / var.data_volumes_per_node)].id
  automount = false
}

# ==============================================================================
# OUTPUTS AND INVENTORY
# ==============================================================================

# Generate Ansible Inventory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tftpl", {
    instances    = hcloud_server.exasol_node
    node_volumes = local.node_volumes
    ssh_key      = local_file.exasol_private_key_pem.filename
  })
  filename        = "${path.module}/inventory.ini"
  file_permission = "0644"

  depends_on = [hcloud_server.exasol_node, hcloud_volume_attachment.data_attachment]
}

# Generate SSH config
resource "local_file" "ssh_config" {
  content = <<-EOF
    # Exasol Cluster SSH Config
    %{for idx, instance in hcloud_server.exasol_node~}
    Host n${idx + 11}
        HostName ${instance.ipv4_address}
        User exasol
        IdentityFile ${local_file.exasol_private_key_pem.filename}
        StrictHostKeyChecking no
        UserKnownHostsFile=/dev/null

    %{endfor~}
  EOF
  filename        = "${path.module}/ssh_config"
  file_permission = "0644"

  depends_on = [hcloud_server.exasol_node]
}
