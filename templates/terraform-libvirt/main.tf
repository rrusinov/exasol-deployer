terraform {
  required_version = ">= 1.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "= 0.7.6"
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

locals {
  # Provider-specific info for common outputs
  provider_name = "Libvirt"
  provider_code = "libvirt"
  region_name   = "local"

  # exasol init populates libvirt_uri via virsh/CLI detection. Fail early if missing.
  libvirt_uri = trimspace(var.libvirt_uri)

  # Group volume IDs by node for Ansible inventory
  node_volumes = {
    for node_idx in range(var.node_count) : node_idx => [
      for vol_idx in range(var.data_volumes_per_node) :
      libvirt_volume.data_volume[node_idx * var.data_volumes_per_node + vol_idx].id
    ]
  }

  # Node IPs for common outputs (libvirt uses private IPs only)
  node_public_ips  = [for domain in libvirt_domain.exasol_node : try(domain.network_interface[0].addresses[0], "")]
  node_private_ips = [for domain in libvirt_domain.exasol_node : try(domain.network_interface[0].addresses[0], "")]

  # GRE mesh overlay not used on libvirt; keep empty to satisfy common inventory template
  gre_data = {}
}

provider "libvirt" {
  uri = local.libvirt_uri
}

# ==============================================================================
# CLOUD-INIT DISK
# ==============================================================================

resource "libvirt_cloudinit_disk" "commoninit" {
  count = var.node_count
  name  = "commoninit-n${count.index + 11}-${random_id.instance.hex}.iso"
  pool  = var.libvirt_disk_pool
  # Use the shared cloud-init script from terraform-common to avoid duplication
  user_data = local.cloud_init_script
}

# ==============================================================================
# BASE IMAGE - Ubuntu Cloud Image
# ==============================================================================

resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-base-${random_id.instance.hex}.qcow2"
  pool   = var.libvirt_disk_pool
  source = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-${var.instance_architecture == "arm64" ? "arm64" : "amd64"}.img"
  format = "qcow2"

  # Fix permissions for QEMU to access the backing file
  # This is needed when creating CoW volumes from this base
  lifecycle {
    ignore_changes = [source]
  }
}

# ==============================================================================
# ROOT VOLUMES - One per node (based on Ubuntu image)
# ==============================================================================

resource "libvirt_volume" "root_volume" {
  count          = var.node_count
  name           = "n${count.index + 11}-root-${random_id.instance.hex}.qcow2"
  pool           = var.libvirt_disk_pool
  base_volume_id = libvirt_volume.ubuntu_base.id
  size           = var.root_volume_size * 1073741824 # Convert GB to bytes
}

# ==============================================================================
# DATA VOLUMES
# ==============================================================================

resource "libvirt_volume" "data_volume" {
  count = var.node_count * var.data_volumes_per_node
  name  = "n${floor(count.index / var.data_volumes_per_node) + 11}-data-${(count.index % var.data_volumes_per_node) + 1}-${random_id.instance.hex}.qcow2"
  pool  = var.libvirt_disk_pool
  size  = var.data_volume_size * 1073741824 # Convert GB to bytes
}

# ==============================================================================
# COMPUTE INSTANCES (VMs)
# ==============================================================================

resource "libvirt_domain" "exasol_node" {
  count   = var.node_count
  name    = "n${count.index + 11}-${random_id.instance.hex}"
  memory  = var.libvirt_memory_gb * 1024 # Convert GB to MB
  vcpu    = var.libvirt_vcpus
  running = var.infra_desired_state == "stopped" ? false : true
  type    = var.libvirt_domain_type

  # Use host CPU to ensure required instruction sets (e.g., SSSE3) are available
  cpu {
    mode = "host-passthrough"
  }

  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id

  dynamic "network_interface" {
    for_each = var.libvirt_network_bridge != "" ? [1] : []
    content {
      network_name   = var.libvirt_network_bridge
      wait_for_lease = true
    }
  }

  dynamic "network_interface" {
    for_each = var.libvirt_network_bridge == "" ? [1] : []
    content {
      # User networking (slirp), no network_name needed
    }
  }

  # Root disk
  disk {
    volume_id = libvirt_volume.root_volume[count.index].id
  }

  # Data disks
  dynamic "disk" {
    for_each = range(var.data_volumes_per_node)
    content {
      volume_id = libvirt_volume.data_volume[count.index * var.data_volumes_per_node + disk.value].id
    }
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  # Use cloud-init to initialize the system
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

# ==============================================================================
# DISK CLEANUP
# ==============================================================================
# Terraform libvirt provider handles volume cleanup automatically during destroy.
# No manual cleanup is needed - volumes defined as resources will be destroyed
# when their dependent domains are destroyed.

# Ansible inventory is generated in common.tf
# SSH config is generated in common.tf
