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
  # Group volume IDs by node for Ansible inventory
  node_volumes = {
    for node_idx in range(var.node_count) : node_idx => [
      for vol_idx in range(var.data_volumes_per_node) :
      digitalocean_volume.data_volume[node_idx * var.data_volumes_per_node + vol_idx].id
    ]
  }
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

  # SSH access
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = [var.allowed_cidr]
  }

  # Default bucketfs
  inbound_rule {
    protocol         = "tcp"
    port_range       = "2581"
    source_addresses = [var.allowed_cidr]
  }

  # Exasol Admin UI
  inbound_rule {
    protocol         = "tcp"
    port_range       = "8443"
    source_addresses = [var.allowed_cidr]
  }

  # Exasol database connection
  inbound_rule {
    protocol         = "tcp"
    port_range       = "8563"
    source_addresses = [var.allowed_cidr]
  }

  # Exasol container ssh
  inbound_rule {
    protocol         = "tcp"
    port_range       = "20002"
    source_addresses = [var.allowed_cidr]
  }

  # Exasol confd API
  inbound_rule {
    protocol         = "tcp"
    port_range       = "20003"
    source_addresses = [var.allowed_cidr]
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
  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail

    # Create exasol group
    groupadd -f exasol

    # Create exasol user with sudo privileges
    if ! id -u exasol >/dev/null 2>&1; then
      useradd -m -g exasol -G sudo -s /bin/bash exasol
    fi

    # Enable passwordless sudo for exasol user
    echo "exasol ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/11-exasol-user
    chmod 0440 /etc/sudoers.d/11-exasol-user

    # Copy SSH authorized_keys from default cloud user to exasol user
    # DigitalOcean uses 'root' by default
    for user_home in /root /home/ubuntu /home/admin; do
      if [ -d "$user_home/.ssh" ] && [ -f "$user_home/.ssh/authorized_keys" ]; then
        mkdir -p /home/exasol/.ssh
        cp "$user_home/.ssh/authorized_keys" /home/exasol/.ssh/
        chown -R exasol:exasol /home/exasol/.ssh
        chmod 700 /home/exasol/.ssh
        chmod 600 /home/exasol/.ssh/authorized_keys
        break
      fi
    done

    # Ensure original cloud user also has passwordless sudo (for compatibility)
    for cloud_user in ubuntu admin; do
      if id -u "$cloud_user" >/dev/null 2>&1; then
        echo "$cloud_user ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/10-$cloud_user-user"
        chmod 0440 "/etc/sudoers.d/10-$cloud_user-user"
      fi
    done
  EOF

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

locals {
  node_public_ips = [for droplet in digitalocean_droplet.exasol_node : droplet.ipv4_address]
  node_private_ips = [for droplet in digitalocean_droplet.exasol_node : droplet.ipv4_address_private]
}

# Generate Ansible Inventory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tftpl", {
    instances    = digitalocean_droplet.exasol_node
    node_volumes = local.node_volumes
    ssh_key      = local_file.exasol_private_key_pem.filename
  })
  filename        = "${path.module}/inventory.ini"
  file_permission = "0644"

  depends_on = [digitalocean_droplet.exasol_node, digitalocean_volume_attachment.data_attachment]
}

# Generate SSH config
resource "local_file" "ssh_config" {
  content = <<-EOF
    # Exasol Cluster SSH Config
    %{for idx, droplet in digitalocean_droplet.exasol_node~}
    Host n${idx + 11}
        HostName ${droplet.ipv4_address}
        User exasol
        IdentityFile ${local_file.exasol_private_key_pem.filename}
        StrictHostKeyChecking no
        UserKnownHostsFile=/dev/null

    %{endfor~}
  EOF
  filename        = "${path.module}/ssh_config"
  file_permission = "0644"

  depends_on = [digitalocean_droplet.exasol_node]
}
