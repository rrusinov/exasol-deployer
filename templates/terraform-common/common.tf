# ==============================================================================
# COMMON TERRAFORM CONFIGURATION
# This file contains shared elements used across all cloud providers
# ==============================================================================

# ==============================================================================
# Random ID for unique resource naming
# ==============================================================================

resource "random_id" "instance" {
  byte_length = 8
}

# ==============================================================================
# SSH Key Pair Generation (Common across all providers)
# ==============================================================================

resource "tls_private_key" "exasol_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "exasol_private_key_pem" {
  content  = tls_private_key.exasol_key.private_key_pem
  filename = "${path.module}/exasol-key.pem"

  provisioner "local-exec" {
    command = "chmod 400 ${self.filename}"
  }
}

# ==============================================================================
# Cloud-Init Script (Common across all providers)
# Only the injection method differs per cloud
# ==============================================================================

locals {
  # Standard cloud-init script for creating exasol user
  # Works across all Linux distributions (Ubuntu, Debian, RHEL, Amazon Linux, etc.)
  cloud_init_script = <<-EOF
    #!/usr/bin/env bash
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
    # Supports: root (DigitalOcean, Hetzner), ubuntu, azureuser, admin, ec2-user, debian
    for user_home in /root /home/ubuntu /home/azureuser /home/admin /home/ec2-user /home/debian; do
      if [ -d "$user_home/.ssh" ] && [ -f "$user_home/.ssh/authorized_keys" ]; then
        mkdir -p /home/exasol/.ssh
        cp "$user_home/.ssh/authorized_keys" /home/exasol/.ssh/
        chown -R exasol:exasol /home/exasol/.ssh
        chmod 700 /home/exasol/.ssh
        chmod 600 /home/exasol/.ssh/authorized_keys
        break
      fi
    done

    # Ensure our generated SSH key is authorized even when the provider does not inject one (e.g., libvirt)
    mkdir -p /home/exasol/.ssh
    echo "${tls_private_key.exasol_key.public_key_openssh}" > /home/exasol/.ssh/authorized_keys
    chown -R exasol:exasol /home/exasol/.ssh
    chmod 700 /home/exasol/.ssh
    chmod 600 /home/exasol/.ssh/authorized_keys

    # Ensure original cloud user also has passwordless sudo (for compatibility)
    for cloud_user in ubuntu azureuser admin ec2-user debian; do
      if id -u "$cloud_user" >/dev/null 2>&1; then
        echo "$cloud_user ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/10-$cloud_user-user"
        chmod 0440 "/etc/sudoers.d/10-$cloud_user-user"
      fi
    done

    if command -v apt-get >/dev/null 2>&1; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y iproute2
    fi
  EOF
}

# ==============================================================================
# SSH Config Generation (Common across all providers)
# Each provider must set local.node_public_ips for this to work
# ==============================================================================

resource "local_file" "ssh_config" {
  content         = <<-EOF
# Exasol Cluster SSH Config
%{for idx, ip in local.node_public_ips~}
Host n${idx + 11}
    HostName ${ip}
    User exasol
    IdentityFile ${abspath(local_file.exasol_private_key_pem.filename)}
    IdentitiesOnly yes
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
    ConnectTimeout 30
    ConnectionAttempts 5
    ServerAliveInterval 60
    ServerAliveCountMax 3

Host n${idx + 11}-cos
    HostName ${ip}
    User root
    Port 20002
    IdentityFile ${abspath(local_file.exasol_private_key_pem.filename)}
    IdentitiesOnly yes
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
    ConnectTimeout 30
    ConnectionAttempts 5
    ServerAliveInterval 60
    ServerAliveCountMax 3

%{endfor~}
  EOF
  filename        = "${path.module}/ssh_config"
  file_permission = "0644"

  # Each provider must ensure this depends on their instances being created
}

# ==============================================================================
# Ansible Inventory Generation (Common across all providers)
# Each provider must set locals: node_public_ips, node_private_ips, node_volumes, provider_code
# ==============================================================================

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tftpl", {
    public_ips     = local.node_public_ips
    private_ips    = local.node_private_ips
    node_volumes   = local.node_volumes
    cloud_provider = local.provider_code
    ssh_key        = local_file.exasol_private_key_pem.filename
    overlay_data   = try(local.overlay_data, {})
  })
  filename        = "${path.module}/inventory.ini"
  file_permission = "0644"

  # Each provider must ensure this depends on their instances and volume attachments being created
}

# ==============================================================================
# VXLAN Multicast Overlay Logic (shared across providers)
# ==============================================================================

locals {
  # Reserve 172.16.0.0/16 for multicast overlay across providers
  # Overlay network IPs (172.16.0.0/16) - used for Exasol clustering
  overlay_network_ips = [for idx in range(var.node_count) : "172.16.0.${idx + 11}"]

  # Determine seed nodes (first 2 nodes in the cluster for redundancy)
  seed_node_indices = slice([for idx in range(var.node_count) : idx], 0, min(2, var.node_count))

  # Common overlay data structure - providers can override physical_ips
  # This respects the enable_multicast_overlay variable (for AWS, Azure, DigitalOcean, Libvirt)
  overlay_data_common = var.enable_multicast_overlay ? {
    for idx in range(var.node_count) : idx => {
      overlay_ip  = local.overlay_network_ips[idx]
      physical_ip = try(local.physical_ips[idx], "")
      is_seed     = contains(local.seed_node_indices, idx)
      seed_nodes = [
        for seed_idx in local.seed_node_indices : {
          name = "n${seed_idx + 11}"
          ip   = try(local.physical_ips[seed_idx], "")
        }
      ]
    }
  } : {}

  # Always-on overlay data structure for providers that require overlay unconditionally
  # Used by GCP and Hetzner (they require overlay networking for proper multicast)
  overlay_data_always_on = {
    for idx in range(var.node_count) : idx => {
      overlay_ip  = local.overlay_network_ips[idx]
      physical_ip = local.physical_ips[idx]
      is_seed     = contains(local.seed_node_indices, idx)
      seed_nodes = [
        for seed_idx in local.seed_node_indices : {
          name = "n${seed_idx + 11}"
          ip   = local.physical_ips[seed_idx]
        }
      ]
    }
  }
}

# These are used by the common outputs but defined in provider-specific variables.tf
# variable "node_count" { ... }
# variable "data_volumes_per_node" { ... }
# variable "owner" { ... }
# variable "enable_multicast_overlay" { ... }
