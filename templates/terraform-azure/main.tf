terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
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

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription
}

# ==============================================================================
# SSH Key Pair
# Common SSH key generation (tls_private_key, local_file, random_id) is in common.tf
# ==============================================================================

# ==============================================================================
# Resource Group
# ==============================================================================

resource "azurerm_resource_group" "exasol" {
  name     = "exasol-cluster-${random_id.instance.hex}"
  location = var.azure_region

  tags = {
    owner = var.owner
  }
}

# ==============================================================================
# Networking
# ==============================================================================

resource "azurerm_virtual_network" "exasol" {
  name                = "exasol-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.exasol.location
  resource_group_name = azurerm_resource_group.exasol.name

  tags = {
    owner = var.owner
  }
}

resource "azurerm_subnet" "exasol" {
  name                 = "exasol-subnet"
  resource_group_name  = azurerm_resource_group.exasol.name
  virtual_network_name = azurerm_virtual_network.exasol.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ==============================================================================
# Network Security Group
# ==============================================================================

resource "azurerm_network_security_group" "exasol" {
  name                = "exasol-nsg"
  location            = azurerm_resource_group.exasol.location
  resource_group_name = azurerm_resource_group.exasol.name

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Exasol-Database"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8563"
    source_address_prefix      = var.allowed_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Exasol-AdminUI"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8443"
    source_address_prefix      = var.allowed_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Exasol-BucketFS"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2581"
    source_address_prefix      = var.allowed_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Exasol-ContainerSSH"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "20002"
    source_address_prefix      = var.allowed_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Exasol-ConfdAPI"
    priority                   = 150
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "20003"
    source_address_prefix      = var.allowed_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowVnetInBound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  tags = {
    owner = var.owner
  }
}

# ==============================================================================
# Public IPs
# ==============================================================================

resource "azurerm_public_ip" "exasol_node" {
  count               = var.node_count
  name                = "exasol-pip-${count.index + 11}"
  location            = azurerm_resource_group.exasol.location
  resource_group_name = azurerm_resource_group.exasol.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    owner = var.owner
  }
}

# ==============================================================================
# Network Interfaces
# ==============================================================================

resource "azurerm_network_interface" "exasol_node" {
  count               = var.node_count
  name                = "exasol-nic-${count.index + 11}"
  location            = azurerm_resource_group.exasol.location
  resource_group_name = azurerm_resource_group.exasol.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.exasol.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.exasol_node[count.index].id
  }

  tags = {
    owner = var.owner
  }
}

resource "azurerm_network_interface_security_group_association" "exasol_node" {
  count                     = var.node_count
  network_interface_id      = azurerm_network_interface.exasol_node[count.index].id
  network_security_group_id = azurerm_network_security_group.exasol.id
}

# ==============================================================================
# Get Ubuntu Image
# ==============================================================================

data "azurerm_platform_image" "ubuntu" {
  location  = azurerm_resource_group.exasol.location
  publisher = "Canonical"
  offer     = "0001-com-ubuntu-server-jammy"
  sku       = var.instance_architecture == "x86_64" ? "22_04-lts-gen2" : "22_04-lts-arm64"
}

# ==============================================================================
# Virtual Machines
# ==============================================================================
# Note: cloud_init_script is defined in common.tf

resource "azurerm_linux_virtual_machine" "exasol_node" {
  count               = var.node_count
  name                = "n${count.index + 11}"
  location            = azurerm_resource_group.exasol.location
  resource_group_name = azurerm_resource_group.exasol.name
  size                = var.instance_type
  admin_username      = "azureuser"

  # Spot instance configuration
  priority        = var.enable_spot_instances ? "Spot" : "Regular"
  eviction_policy = var.enable_spot_instances ? "Deallocate" : null
  max_bid_price   = var.enable_spot_instances ? -1 : null # -1 means pay up to on-demand price

  network_interface_ids = [
    azurerm_network_interface.exasol_node[count.index].id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.exasol_key.public_key_openssh
  }

  os_disk {
    name                 = "exasol-osdisk-${count.index + 11}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.root_volume_size
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = var.instance_architecture == "x86_64" ? "22_04-lts-gen2" : "22_04-lts-arm64"
    version   = "latest"
  }

  # Cloud-init custom_data (base64 encoded automatically by Azure provider)
  custom_data = base64encode(local.cloud_init_script)

  tags = {
    Name    = "n${count.index + 11}"
    Role    = "worker"
    Cluster = "exasol-cluster"
    owner   = var.owner
  }
}

# ==============================================================================
# Data Disks
# ==============================================================================

resource "azurerm_managed_disk" "data_volume" {
  count                = var.node_count * var.data_volumes_per_node
  name                 = "exasol-data-${floor(count.index / var.data_volumes_per_node) + 11}-${(count.index % var.data_volumes_per_node) + 1}"
  location             = azurerm_resource_group.exasol.location
  resource_group_name  = azurerm_resource_group.exasol.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.data_volume_size

  tags = {
    Cluster     = "exasol-cluster"
    VolumeIndex = tostring((count.index % var.data_volumes_per_node) + 1)
    NodeIndex   = tostring(floor(count.index / var.data_volumes_per_node) + 11)
    owner       = var.owner
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "data_attachment" {
  count              = var.node_count * var.data_volumes_per_node
  managed_disk_id    = azurerm_managed_disk.data_volume[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.exasol_node[floor(count.index / var.data_volumes_per_node)].id
  lun                = count.index % var.data_volumes_per_node
  caching            = "None"
}

# ==============================================================================
# Outputs for Ansible Inventory
# ==============================================================================

locals {
  # Provider-specific info for common outputs
  provider_name = "Azure"
  region_name = var.azure_region

  # Group volume IDs by node for Ansible inventory
  node_volumes = {
    for node_idx in range(var.node_count) : node_idx => [
      for vol_idx in range(var.data_volumes_per_node) :
      azurerm_managed_disk.data_volume[node_idx * var.data_volumes_per_node + vol_idx].id
    ]
  }

  # Node IPs for common outputs
  node_public_ips = azurerm_public_ip.exasol_node[*].ip_address
  node_private_ips = azurerm_network_interface.exasol_node[*].private_ip_address
}

# ==============================================================================
# Generate Ansible Inventory
# ==============================================================================

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tftpl", {
    instances    = azurerm_linux_virtual_machine.exasol_node
    node_volumes = local.node_volumes
    ssh_key      = local_file.exasol_private_key_pem.filename
  })
  filename        = "${path.module}/inventory.ini"
  file_permission = "0644"

  depends_on = [azurerm_linux_virtual_machine.exasol_node, azurerm_virtual_machine_data_disk_attachment.data_attachment]
}

# ==============================================================================
# Generate SSH Config
# ==============================================================================

resource "local_file" "ssh_config" {
  content = <<-EOF
    # Exasol Cluster SSH Config
    %{for idx, instance in azurerm_linux_virtual_machine.exasol_node~}
    Host n${idx + 11}
        HostName ${azurerm_public_ip.exasol_node[idx].ip_address}
        User exasol
        IdentityFile ${local_file.exasol_private_key_pem.filename}
        StrictHostKeyChecking no
        UserKnownHostsFile=/dev/null

    %{endfor~}
  EOF
  filename        = "${path.module}/ssh_config"
  file_permission = "0644"

  depends_on = [azurerm_linux_virtual_machine.exasol_node]
}
