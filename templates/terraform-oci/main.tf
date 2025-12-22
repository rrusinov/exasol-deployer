terraform {
  required_version = ">= 1.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
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

# Common firewall configuration is provided by common-firewall.tf
# (copied during init from terraform-common/common-firewall.tf)

provider "oci" {
  tenancy_ocid     = var.oci_tenancy_ocid
  user_ocid        = var.oci_user_ocid
  fingerprint      = var.oci_fingerprint
  private_key_path = var.oci_private_key_path
  region           = var.oci_region
}

# ==============================================================================
# SSH Key Pair
# Common SSH key generation (tls_private_key, local_file, random_id) is in common.tf
# ==============================================================================

locals {
  # Provider-specific info for common outputs
  provider_name = "OCI"
  provider_code = "oci"
  region_name   = var.oci_region

  # Map architecture variable to string used in image name filter
  arch_filter = var.instance_architecture == "arm64" ? "aarch64" : "x86_64"

  # Ubuntu image selection
  ubuntu_image_id = data.oci_core_images.ubuntu.images[0].id

  # Physical IPs for multicast overlay (used by common overlay logic)
  physical_ips = [for instance in oci_core_instance.exasol : instance.private_ip]

  # Node IPs for common outputs
  node_public_ips  = [for instance in oci_core_instance.exasol : instance.public_ip]
  node_private_ips = var.enable_multicast_overlay ? local.overlay_network_ips : local.physical_ips

  # VXLAN multicast overlay (uses common logic)
  overlay_data = local.overlay_data_common

  # Power control capability
  supports_power_control = false

  # OCI-specific cloud-init template
  # Template is copied to .templates/ in deployment directory during init
  cloud_init_template_path = "${path.module}/.templates/cloud-init-oci.tftpl"

  # Node volumes for Ansible inventory
  node_volumes = {
    for node_idx in range(var.node_count) : node_idx => [
      for vol_idx in range(var.data_volumes_per_node) :
      oci_core_volume.exasol_data[node_idx * var.data_volumes_per_node + vol_idx].id
    ]
  }

  # Volume attachment connection details for Ansible (IQN, portal, port)
  node_volume_attachments = {
    for node_idx in range(var.node_count) : node_idx => [
      for vol_idx in range(var.data_volumes_per_node) : {
        id   = oci_core_volume.exasol_data[node_idx * var.data_volumes_per_node + vol_idx].id
        iqn  = oci_core_volume_attachment.exasol_data[node_idx * var.data_volumes_per_node + vol_idx].iqn
        ipv4 = oci_core_volume_attachment.exasol_data[node_idx * var.data_volumes_per_node + vol_idx].ipv4
        port = oci_core_volume_attachment.exasol_data[node_idx * var.data_volumes_per_node + vol_idx].port
      }
    ]
  }

  # Ingress source ranges: generated VCN plus optional VXLAN overlay network
  overlay_network_cidr    = "172.16.0.0/16"
  ingress_private_sources = concat(
    [oci_core_vcn.exasol.cidr_block],
    var.enable_multicast_overlay ? [local.overlay_network_cidr] : []
  )
}

# ==============================================================================
# VCN (Virtual Cloud Network)
# ==============================================================================

resource "oci_core_vcn" "exasol" {
  compartment_id = var.oci_compartment_ocid
  display_name   = "exasol-vcn-${random_id.instance.hex}"
  dns_label      = "exasol${substr(random_id.instance.hex, 0, 6)}"
  # Use range derived from cluster ID to ensure uniqueness while being deterministic
  # Format: 10.X.0.0/16 where X is derived from cluster ID hex digits
  # Provides 254 possible unique networks
  cidr_block = "10.${(parseint(substr(random_id.instance.hex, 0, 2), 16) % 254) + 1}.0.0/16"

  freeform_tags = {
    "owner" = var.owner
  }
}

resource "oci_core_internet_gateway" "exasol" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.exasol.id
  display_name   = "exasol-igw-${random_id.instance.hex}"
  enabled        = true

  freeform_tags = {
    "owner" = var.owner
  }
}

resource "oci_core_default_route_table" "exasol" {
  manage_default_resource_id = oci_core_vcn.exasol.default_route_table_id
  display_name               = "exasol-rt-${random_id.instance.hex}"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.exasol.id
  }

  freeform_tags = {
    "owner" = var.owner
  }
}

# ==============================================================================
# Subnet
# ==============================================================================

resource "oci_core_subnet" "exasol" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.exasol.id
  display_name   = "exasol-subnet-${random_id.instance.hex}"
  dns_label      = "subnet${substr(random_id.instance.hex, 0, 6)}"
  # Use /24 subnet from the VCN's /16 range
  cidr_block = cidrsubnet(oci_core_vcn.exasol.cidr_block, 8, 1)

  freeform_tags = {
    "owner" = var.owner
  }
}

# ==============================================================================
# Security List
# ==============================================================================

resource "oci_core_default_security_list" "exasol" {
  manage_default_resource_id = oci_core_vcn.exasol.default_security_list_id
  display_name               = "exasol-sl-${random_id.instance.hex}"

  # Egress rules - allow all outbound traffic
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # Ingress rules - Use common firewall ports
  dynamic "ingress_security_rules" {
    for_each = local.exasol_firewall_ports
    content {
      protocol = "6" # TCP
      source   = var.allowed_cidr

      tcp_options {
        min = ingress_security_rules.key
        max = ingress_security_rules.key
      }
    }
  }

  # Allow all traffic from generated private ranges (VCN CIDR and optional VXLAN overlay)
  dynamic "ingress_security_rules" {
    for_each = toset(local.ingress_private_sources)
    content {
      protocol    = "all"
      source      = ingress_security_rules.value
      description = "Allow all traffic within generated private ranges"
    }
  }

  # VXLAN overlay network (UDP 4789) for multicast support
  dynamic "ingress_security_rules" {
    for_each = var.enable_multicast_overlay ? toset(local.ingress_private_sources) : []
    content {
      protocol = "17" # UDP
      source   = ingress_security_rules.value

      udp_options {
        min = 4789
        max = 4789
      }
    }
  }

  freeform_tags = {
    "owner" = var.owner
  }
}

# ==============================================================================
# Data Source: Availability Domains
# ==============================================================================

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.oci_compartment_ocid
}

# ==============================================================================
# Data Source: Latest Ubuntu 22.04 LTS Image
# ==============================================================================

data "oci_core_images" "ubuntu" {
  compartment_id   = var.oci_compartment_ocid
  operating_system = "Canonical Ubuntu"
  sort_by          = "TIMECREATED"
  sort_order       = "DESC"

  filter {
    name   = "display_name"
    values = ["^Canonical-Ubuntu-24\\.04-[0-9].*$"]
    regex  = true
  }
}

# ==============================================================================
# Compute Instances
# ==============================================================================

resource "oci_core_instance" "exasol" {
  count               = var.node_count
  compartment_id      = var.oci_compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[count.index % length(data.oci_identity_availability_domains.ads.availability_domains)].name
  display_name        = "exasol-node-${count.index + 1}-${random_id.instance.hex}"
  shape               = var.instance_type

  # Flexible shapes require shape_config
  dynamic "shape_config" {
    for_each = can(regex("Flex$", var.instance_type)) ? [1] : []
    content {
      # Default to 2 OCPUs and 8GB RAM for flexible shapes
      ocpus         = 2
      memory_in_gbs = 8
    }
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.exasol.id
    display_name     = "exasol-vnic-${count.index + 1}-${random_id.instance.hex}"
    assign_public_ip = true
    hostname_label   = "n${count.index + 11}"
  }

  source_details {
    source_type = "image"
    source_id   = local.ubuntu_image_id
    boot_volume_size_in_gbs = var.root_volume_size
  }

  metadata = {
    ssh_authorized_keys = tls_private_key.exasol_key.public_key_openssh
    user_data = base64encode(templatefile(local.cloud_init_template_path, {
      base_cloud_init = local.cloud_init_script
    }))
  }

  freeform_tags = {
    "owner" = var.owner
  }

  # Prevent accidental termination
  lifecycle {
    ignore_changes = [
      source_details[0].source_id, # Ignore image updates
    ]
  }
}

# ==============================================================================
# Instance Power Control
# ==============================================================================

# OCI instances use manual power control (like DigitalOcean/Hetzner)
# Power control is handled through in-guest shutdown and manual power-on

resource "oci_core_volume" "exasol_data" {
  count               = var.node_count * var.data_volumes_per_node
  compartment_id      = var.oci_compartment_ocid
  display_name        = "exasol-data-${floor(count.index / var.data_volumes_per_node) + 1}-${(count.index % var.data_volumes_per_node) + 1}-${random_id.instance.hex}"
  size_in_gbs         = var.data_volume_size
  availability_domain = oci_core_instance.exasol[floor(count.index / var.data_volumes_per_node)].availability_domain

  freeform_tags = {
    "owner" = var.owner
  }
}

resource "oci_core_volume_attachment" "exasol_data" {
  count           = var.node_count * var.data_volumes_per_node
  attachment_type = "iscsi"
  instance_id     = oci_core_instance.exasol[floor(count.index / var.data_volumes_per_node)].id
  volume_id       = oci_core_volume.exasol_data[count.index].id
  display_name    = "exasol-data-attachment-${floor(count.index / var.data_volumes_per_node) + 1}-${(count.index % var.data_volumes_per_node) + 1}-${random_id.instance.hex}"
  device          = "/dev/oracleoci/oraclevd${substr("bcdefghijklmnopqrstuvwxyz", count.index % var.data_volumes_per_node, 1)}"

  # Timeouts for volume attachment operations
  timeouts {
    create = "10m"
    delete = "10m"
  }

  # Wait for instance to be running before attaching volumes
  depends_on = [oci_core_instance.exasol]
}

# Power Control - OCI instances use manual power control
# Start: Manual power-on via OCI console/CLI
# Stop: In-guest shutdown via Ansible (poweroff command)
