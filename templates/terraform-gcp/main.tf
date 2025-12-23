terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
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

provider "google" {
  project     = var.gcp_project
  region      = var.gcp_region
  credentials = file(var.gcp_credentials_file)
}

# ==============================================================================
# SSH Key Pair
# Common SSH key generation (tls_private_key, local_file, random_id) is in common.tf
# ==============================================================================

# Get current user info for OS Login
data "google_client_openid_userinfo" "me" {}



# ==============================================================================
# VPC Network
# ==============================================================================

resource "google_compute_network" "exasol" {
  name                    = "exasol-network-${random_id.instance.hex}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "exasol" {
  name = "exasol-subnet-${random_id.instance.hex}"
  # Use range derived from cluster ID to ensure uniqueness while being deterministic
  # Format: 10.X.0.0/16 where X is derived from cluster ID hex digits
  # Provides 254 possible unique networks
  # Use /16 network and carve a /24 subnet from it for instances
  ip_cidr_range = cidrsubnet("10.${(parseint(substr(random_id.instance.hex, 0, 2), 16) % 254) + 1}.0.0/16", 8, 1)
  region        = var.gcp_region
  network       = google_compute_network.exasol.id
}

# ==============================================================================
# Firewall Rules
# ==============================================================================

resource "google_compute_firewall" "exasol_external" {
  name    = "exasol-external-${random_id.instance.hex}"
  network = google_compute_network.exasol.name

  allow {
    protocol = "tcp"
    ports    = [for port in keys(local.exasol_firewall_ports) : tostring(port)]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.allowed_cidr]
  target_tags   = ["exasol-cluster"]
}

resource "google_compute_firewall" "exasol_internal" {
  name    = "exasol-internal-${random_id.instance.hex}"
  network = google_compute_network.exasol.name

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_tags = ["exasol-cluster"]
  target_tags = ["exasol-cluster"]
}

# ==============================================================================
# Get Ubuntu Image
# ==============================================================================

data "google_compute_image" "ubuntu" {
  family  = var.instance_architecture == "x86_64" ? "ubuntu-2204-lts" : "ubuntu-2204-lts-arm64"
  project = "ubuntu-os-cloud"
}

# ==============================================================================
# Cloud-Init Metadata
# ==============================================================================
# Note: cloud_init_script is defined in common.tf

locals {
  # Provider-specific info for common outputs
  provider_name     = "GCP"
  provider_code     = "gcp"
  region_name       = var.gcp_region
  selected_gcp_zone = length(trimspace(var.gcp_zone)) > 0 ? trimspace(var.gcp_zone) : "${var.gcp_region}-a"

  # SSH keys metadata
  ssh_keys_metadata = "ubuntu:${tls_private_key.exasol_key.public_key_openssh}"

  # Group volume IDs by node for Ansible inventory
  node_volumes = {
    for node_idx in range(var.node_count) : node_idx => [
      for vol_idx in range(var.data_volumes_per_node) :
      google_compute_disk.data_volume[node_idx * var.data_volumes_per_node + vol_idx].id
    ]
  }

  # Node IPs for common outputs
  # IMPORTANT: Use overlay IPs as "private IPs" so Exasol uses them for clustering
  node_public_ips  = [for instance in google_compute_instance.exasol_node : instance.network_interface[0].access_config[0].nat_ip]
  node_private_ips = local.overlay_network_ips # Overlay IPs for Exasol clustering

  # Physical IPs for multicast overlay (used by common overlay logic)
  physical_ips = [for instance in google_compute_instance.exasol_node : instance.network_interface[0].network_ip]

  # Overlay mesh data for Ansible inventory (GCP requires overlay for proper networking - always enabled)
  overlay_data = local.overlay_data_always_on

  # Volume attachment details (empty for GCP - uses direct volume attachment)
  node_volume_attachments = {}

  # Generic cloud-init template (shared across providers)
  # Template is copied to .templates/ in deployment directory during init
  cloud_init_template_path = "${path.module}/.templates/cloud-init-generic.tftpl"


}

# ==============================================================================
# Compute Instances
# ==============================================================================

resource "google_compute_instance" "exasol_node" {
  count          = var.node_count
  name           = "n${count.index + 11}-${random_id.instance.hex}"
  machine_type   = var.instance_type
  zone           = local.selected_gcp_zone
  desired_status = var.infra_desired_state == "stopped" ? "TERMINATED" : "RUNNING"

  # Spot (preemptible) instance configuration
  scheduling {
    preemptible         = var.enable_spot_instances
    automatic_restart   = !var.enable_spot_instances
    on_host_maintenance = var.enable_spot_instances ? "TERMINATE" : "MIGRATE"
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = var.root_volume_size
      type  = "pd-ssd"
    }
  }

  # Attach data disks inline to ensure they persist across stop/start cycles
  dynamic "attached_disk" {
    for_each = range(var.data_volumes_per_node)
    content {
      source      = google_compute_disk.data_volume[count.index * var.data_volumes_per_node + attached_disk.value].id
      device_name = google_compute_disk.data_volume[count.index * var.data_volumes_per_node + attached_disk.value].name
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.exasol.id

    access_config {
      # Ephemeral public IP
    }
  }

  metadata = {
    ssh-keys = local.ssh_keys_metadata
    user-data = templatefile(local.cloud_init_template_path, {
      base_cloud_init = local.cloud_init_script
    })
  }

  tags = ["exasol-cluster"]

  labels = {
    name    = "n${count.index + 11}"
    role    = "worker"
    cluster = "exasol-cluster"
    owner   = var.owner
  }

  # Ensure disks are created before attaching them
  depends_on = [google_compute_disk.data_volume]
}

# ==============================================================================
# Data Disks
# ==============================================================================

resource "google_compute_disk" "data_volume" {
  count = var.node_count * var.data_volumes_per_node
  name  = "exasol-data-${random_id.instance.hex}-${floor(count.index / var.data_volumes_per_node) + 11}-${(count.index % var.data_volumes_per_node) + 1}"
  type  = "pd-ssd"
  zone  = local.selected_gcp_zone
  size  = var.data_volume_size

  labels = {
    cluster      = "exasol-cluster"
    volume_index = tostring((count.index % var.data_volumes_per_node) + 1)
    node_index   = tostring(floor(count.index / var.data_volumes_per_node) + 11)
    owner        = var.owner
  }
}

# ==============================================================================
# Outputs for Ansible Inventory
# ==============================================================================

# ==============================================================================
# Generate Ansible Inventory
# ==============================================================================

# Ansible inventory is generated in common.tf
# SSH config is generated in common.tf
