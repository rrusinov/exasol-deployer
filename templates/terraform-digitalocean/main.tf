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
  region_name   = var.digitalocean_region

  # Group volume IDs by node for Ansible inventory
  # Note: DigitalOcean uses volume names (not UUIDs) in /dev/disk/by-id/scsi-0DO_Volume_<name>
  node_volumes = {
    for node_idx in range(var.node_count) : node_idx => [
      for vol_idx in range(var.data_volumes_per_node) :
      digitalocean_volume.data_volume[node_idx * var.data_volumes_per_node + vol_idx].name
    ]
  }

  # Physical IPs for Tinc VPN (used by common Tinc logic)
  physical_ips = [for droplet in digitalocean_droplet.exasol_node : droplet.ipv4_address_private]

  # Node IPs for common outputs
  node_public_ips  = [for droplet in digitalocean_droplet.exasol_node : droplet.ipv4_address]
  node_private_ips = var.enable_multicast_overlay ? local.overlay_network_ips : local.physical_ips

  # Tinc mesh overlay (uses common logic)
  tinc_data = local.tinc_data_common

  # Generic cloud-init template (shared across providers)
  # Template is copied to .templates/ in deployment directory during init
  cloud_init_template_path = "${path.module}/.templates/cloud-init-generic.tftpl"
}

# ==============================================================================
# NETWORKING
# ==============================================================================

resource "digitalocean_vpc" "exasol_vpc" {
  name   = "exasol-vpc-${random_id.instance.hex}"
  region = var.digitalocean_region
  # Use range derived from cluster ID to ensure uniqueness while being deterministic
  # This avoids conflicts with existing VPCs from failed/previous deployments
  # Format: 10.X.Y.0/24 where X and Y are derived from cluster ID hex digits
  # Provides 254 × 256 = 65,024 possible unique networks
  # Use a /16 network and carve /24 subnets from it to reduce collision risk
  # Reserve 10.254.0.0/16 for GRE overlay across providers
  ip_range = "10.${(parseint(substr(random_id.instance.hex, 0, 2), 16) % 253) + 1}.0.0/16"
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
    source_addresses = [digitalocean_vpc.exasol_vpc.ip_range]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "1-65535"
    source_addresses = [digitalocean_vpc.exasol_vpc.ip_range]
  }

  inbound_rule {
    protocol         = "icmp"
    source_addresses = [digitalocean_vpc.exasol_vpc.ip_range]
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
  user_data = templatefile(local.cloud_init_template_path, {
    base_cloud_init = local.cloud_init_script
  })

  # Note: resize_disk parameter is not used because DigitalOcean droplet disk size
  # is determined by the instance type slug and cannot be customized independently
  # (e.g., s-2vcpu-4gb always comes with 80GB disk)

  # Wait for droplet and cloud-init to be ready
  # DigitalOcean needs extra time for cloud-init to create exasol user and copy SSH keys
  provisioner "local-exec" {
    command = "sleep 60"
  }
}

# ==============================================================================
# STORAGE VOLUMES
# ==============================================================================

# Data Volumes
resource "digitalocean_volume" "data_volume" {
  count  = var.node_count * var.data_volumes_per_node
  name   = "n${floor(count.index / var.data_volumes_per_node) + 11}-data-${(count.index % var.data_volumes_per_node) + 1}-${random_id.instance.hex}"
  size   = var.data_volume_size
  region = var.digitalocean_region
  # Note: Leave unformatted so DigitalOcean doesn't auto-mount at /mnt/<volume-name>
  # Exasol will format and manage the volumes directly via /dev/exasol_data_* symlinks

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

# Ansible inventory is generated in common.tf
# SSH config is generated in common.tf
