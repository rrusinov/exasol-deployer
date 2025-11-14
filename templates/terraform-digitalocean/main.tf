terraform {
  required_version = ">= 1.0"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
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

provider "digitalocean" {
  token = var.digitalocean_token
}

# ==============================================================================
# SSH Key Pair - DigitalOcean-specific wrapper
# Common SSH key generation (tls_private_key, local_file, random_id) is in common.tf
# ==============================================================================

resource "digitalocean_ssh_key" "exasol_auth" {
  name       = "exasol-cluster-key-${random_id.instance.hex}"
  public_key = tls_private_key.exasol_key.public_key_openssh
}

locals {
  # Provider-specific info for common outputs
  provider_name = "DigitalOcean"
  provider_code = "digitalocean"
  region_name = var.digitalocean_region

  # Group volume IDs by node for Ansible inventory
  node_volumes = {
    for node_idx in range(var.node_count) : node_idx => [
      for vol_idx in range(var.data_volumes_per_node) :
      digitalocean_volume.data_volume[node_idx * var.data_volumes_per_node + vol_idx].id
    ]
  }

  # Node IPs for common outputs
  node_public_ips = [for droplet in digitalocean_droplet.exasol_node : droplet.ipv4_address]
  node_private_ips = [for droplet in digitalocean_droplet.exasol_node : droplet.ipv4_address_private]
}

# ==============================================================================
# NETWORKING
# ==============================================================================

resource "digitalocean_vpc" "exasol_vpc" {
  name     = "exasol-vpc-${random_id.instance.hex}"
  region   = var.digitalocean_region
  ip_range = "10.0.0.0/16"
}

# ==============================================================================
# FIREWALL
# ==============================================================================

resource "digitalocean_firewall" "exasol_cluster" {
  name = "exasol-cluster-fw-${random_id.instance.hex}"

  droplet_ids = digitalocean_droplet.exasol_node[*].id

  dynamic "inbound_rule" {
    for_each = local.exasol_firewall_ports
    content {
      protocol         = "tcp"
      port_range       = tostring(inbound_rule.key)
      source_addresses = [var.allowed_cidr]
    }
  }

  # ICMP for network diagnostics
  inbound_rule {
    protocol         = "icmp"
    source_addresses = [var.allowed_cidr]
  }

  # Allow all traffic within the VPC (private network)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "1-65535"
    source_addresses = ["10.0.0.0/16"]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "1-65535"
    source_addresses = ["10.0.0.0/16"]
  }

  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["10.0.0.0/16"]
  }

  # Allow all outbound
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# ==============================================================================
# COMPUTE INSTANCES
# ==============================================================================

# Get latest Ubuntu 24.04 image
data "digitalocean_image" "ubuntu" {
  slug = "ubuntu-24-04-x64"
  # Note: DigitalOcean doesn't have arm64 droplets yet, only x86_64
}

resource "digitalocean_droplet" "exasol_node" {
  count    = var.node_count
  name     = "n${count.index + 11}-${random_id.instance.hex}"
  size     = var.instance_type
  image    = data.digitalocean_image.ubuntu.id
  region   = var.digitalocean_region
  vpc_uuid = digitalocean_vpc.exasol_vpc.id
  ssh_keys = [digitalocean_ssh_key.exasol_auth.id]

  tags = [
    "owner:${var.owner}",
    "role:worker",
    "cluster:exasol-cluster",
    "node:n${count.index + 11}"
  ]

  # Cloud-init user-data to create exasol user before Ansible runs
  user_data = local.cloud_init_script

  # Resize root disk if needed
  resize_disk = var.root_volume_size > 25 ? true : false

  # Wait for droplet to be ready
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

# ==============================================================================
# STORAGE VOLUMES
# ==============================================================================

# Data Volumes
resource "digitalocean_volume" "data_volume" {
  count                   = var.node_count * var.data_volumes_per_node
  name                    = "n${floor(count.index / var.data_volumes_per_node) + 11}-data-${(count.index % var.data_volumes_per_node) + 1}-${random_id.instance.hex}"
  size                    = var.data_volume_size
  region                  = var.digitalocean_region
  initial_filesystem_type = "ext4"

  description = "Data volume ${(count.index % var.data_volumes_per_node) + 1} for node n${floor(count.index / var.data_volumes_per_node) + 11}"

  tags = [
    "owner:${var.owner}",
    "cluster:exasol-cluster",
    "volume_index:${(count.index % var.data_volumes_per_node) + 1}",
    "node_index:${floor(count.index / var.data_volumes_per_node) + 11}"
  ]
}

# Attach Data Volumes to Droplets
resource "digitalocean_volume_attachment" "data_attachment" {
  count      = var.node_count * var.data_volumes_per_node
  volume_id  = digitalocean_volume.data_volume[count.index].id
  droplet_id = digitalocean_droplet.exasol_node[floor(count.index / var.data_volumes_per_node)].id
}

# ==============================================================================
# OUTPUTS AND INVENTORY
# ==============================================================================

# Generate Ansible Inventory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tftpl", {
    public_ips   = local.node_public_ips
    private_ips  = local.node_private_ips
    node_volumes = local.node_volumes
    cloud_provider = local.provider_code
    ssh_key      = local_file.exasol_private_key_pem.filename
  })
  filename        = "${path.module}/inventory.ini"
  file_permission = "0644"

  depends_on = [digitalocean_droplet.exasol_node, digitalocean_volume_attachment.data_attachment]
}

# Generate SSH config
# SSH config is generated in common.tf
