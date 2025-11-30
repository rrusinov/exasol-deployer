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

# ==============================================================================
# VPC Network
# ==============================================================================

resource "google_compute_network" "exasol" {
  name                    = "exasol-network-${random_id.instance.hex}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "exasol" {
  name = "exasol-subnet"
  # Use range derived from cluster ID to ensure uniqueness while being deterministic
  # Format: 10.X.Y.0/24 where X and Y are derived from cluster ID hex digits
  # Provides 254 × 256 = 65,024 possible unique networks
  # Use /16 network and carve a /24 subnet from it for instances
  # Reserve 10.254.0.0/16 for GRE overlay across providers
  ip_cidr_range = cidrsubnet("10.${(parseint(substr(random_id.instance.hex, 0, 2), 16) % 253) + 1}.0.0/16", 8, 1)
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
  node_public_ips  = [for instance in google_compute_instance.exasol_node : instance.network_interface[0].access_config[0].nat_ip]
  node_private_ips = [for instance in google_compute_instance.exasol_node : instance.network_interface[0].network_ip]

  # GRE mesh overlay not used on GCP; keep empty to satisfy common inventory template
  gre_data = {}
}

# ==============================================================================
# Compute Instances
# ==============================================================================

resource "google_compute_instance" "exasol_node" {
  count          = var.node_count
  name           = "n${count.index + 11}"
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

  network_interface {
    subnetwork = google_compute_subnetwork.exasol.id

    access_config {
      # Ephemeral public IP
    }
  }

  metadata = {
    ssh-keys       = local.ssh_keys_metadata
    startup-script = local.cloud_init_script
  }

  tags = ["exasol-cluster"]

  labels = {
    name    = "n${count.index + 11}"
    role    = "worker"
    cluster = "exasol-cluster"
    owner   = var.owner
  }
}

# ==============================================================================
# Data Disks
# ==============================================================================

resource "google_compute_disk" "data_volume" {
  count = var.node_count * var.data_volumes_per_node
  name  = "exasol-data-${floor(count.index / var.data_volumes_per_node) + 11}-${(count.index % var.data_volumes_per_node) + 1}"
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

resource "google_compute_attached_disk" "data_attachment" {
  count    = var.node_count * var.data_volumes_per_node
  disk     = google_compute_disk.data_volume[count.index].id
  instance = google_compute_instance.exasol_node[floor(count.index / var.data_volumes_per_node)].id
}

# ==============================================================================
# Outputs for Ansible Inventory
# ==============================================================================

# ==============================================================================
# Generate Ansible Inventory
# ==============================================================================

# Ansible inventory is generated in common.tf
# SSH config is generated in common.tf
