terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
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

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      "owner" = var.owner
    }
  }
}

# ==============================================================================
# SSH Key Pair - AWS-specific wrapper
# Common SSH key generation (tls_private_key, local_file, random_id) is in common.tf
# ==============================================================================

resource "aws_key_pair" "exasol_auth" {
  key_name   = "exasol-cluster-key-${random_id.instance.hex}"
  public_key = tls_private_key.exasol_key.public_key_openssh
}

locals {
  # Map the architecture variable to the string used in the AMI name filter.
  # AWS and Ubuntu AMIs often use 'amd64' in the name for 'x86_64' architecture.
  ami_name_arch = var.instance_architecture == "x86_64" ? "amd64" : "arm64"

  # Group volume IDs by node for Ansible inventory
  # Creates a map: { "0" => ["vol-xxx", "vol-yyy"], "1" => ["vol-zzz", "vol-aaa"], ... }
  node_volumes = {
    for node_idx in range(var.node_count) : node_idx => [
      for vol_idx in range(var.data_volumes_per_node) :
      aws_ebs_volume.data_volume[node_idx * var.data_volumes_per_node + vol_idx].id
    ]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Get latest Ubuntu 24.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's account

  filter {
    name = "name"
    # Use the local variable to dynamically set amd64 or arm64
    values = ["ubuntu/images/hvm-ssd*/ubuntu-*-24.04-${local.ami_name_arch}-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name = "architecture"
    # Use the input variable directly
    values = [var.instance_architecture]
  }
}

data "aws_ec2_instance_type_offerings" "supported" {
  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }

  filter {
    name   = "location"
    values = data.aws_availability_zones.available.names
  }

  location_type = "availability-zone"
}

locals {
  # Prioritize user-supplied AZs, otherwise iterate over everything available in the region.
  preferred_azs = length(var.preferred_availability_zones) > 0 ? var.preferred_availability_zones : data.aws_availability_zones.available.names

  # Only keep AZs that actually support the chosen instance type.
  supported_azs = distinct(tolist(data.aws_ec2_instance_type_offerings.supported.locations))

  prioritized_supported_azs = [
    for az in local.preferred_azs : az
    if contains(local.supported_azs, az)
  ]

  selected_az = try(local.prioritized_supported_azs[0], null)
}

# Create a new VPC
resource "aws_vpc" "exasol_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "exasol-vpc"
  }
}

# Create a subnet
resource "aws_subnet" "exasol_subnet" {
  vpc_id                  = aws_vpc.exasol_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = local.selected_az

  tags = {
    Name = "exasol-subnet"
  }

  lifecycle {
    precondition {
      condition     = local.selected_az != null
      error_message = "Instance type ${var.instance_type} is not available in any AZ within region ${var.aws_region}. Select a different instance type/region or expand preferred_availability_zones."
    }
  }
}

# Security Group
resource "aws_security_group" "exasol_cluster" {
  name        = "exasol-cluster-sg"
  description = "Security group for Exasol cluster"
  vpc_id      = aws_vpc.exasol_vpc.id

  # External access rules - dynamically created for each port
  dynamic "ingress" {
    for_each = {
      22    = "SSH access"
      2581  = "Default bucketfs"
      8443  = "Exasol Admin UI"
      8563  = "Default Exasol database connection"
      20002 = "Exasol container ssh"
      20003 = "Exasol confd API"
    }

    content {
      from_port   = ingress.key
      to_port     = ingress.key
      protocol    = "tcp"
      cidr_blocks = [var.allowed_cidr]
      description = ingress.value
    }
  }

  # ICMP for network diagnostics
  ingress {
    description = "ICMP from allowed CIDR"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.allowed_cidr]
  }

  # Allow all traffic between cluster nodes
  ingress {
    description = "All traffic within cluster"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow all outbound
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "exasol-cluster-sg"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.exasol_vpc.id

  tags = {
    Name = "exasol-igw"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.exasol_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "exasol-public-rt"
  }
}

# Associate Route Table with Subnet
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.exasol_subnet.id
  route_table_id = aws_route_table.public.id
}

# EC2 Instances
resource "aws_instance" "exasol_node" {
  count                  = var.node_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.exasol_auth.key_name
  subnet_id              = aws_subnet.exasol_subnet.id
  vpc_security_group_ids = [aws_security_group.exasol_cluster.id]

  # Cloud-init user-data to create exasol user before Ansible runs
  user_data = <<-EOF
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
    # This works across different distributions (ubuntu, admin, ec2-user, etc.)
    for user_home in /home/ubuntu /home/admin /home/ec2-user /home/debian; do
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
    for cloud_user in ubuntu admin ec2-user debian; do
      if id -u "$cloud_user" >/dev/null 2>&1; then
        echo "$cloud_user ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/10-$cloud_user-user"
        chmod 0440 "/etc/sudoers.d/10-$cloud_user-user"
      fi
    done
  EOF

  user_data_replace_on_change = true

  # Spot Instance configuration
  dynamic "instance_market_options" {
    for_each = var.enable_spot_instances ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        spot_instance_type             = "persistent"
        instance_interruption_behavior = "stop"
      }
    }
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name    = "n${count.index + 11}"
    Role    = "worker"
    Cluster = "exasol-cluster"
  }

  # Wait for instance to be ready
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

# EBS Data Volumes
# Creates data_volumes_per_node volumes for each node
resource "aws_ebs_volume" "data_volume" {
  count             = var.node_count * var.data_volumes_per_node
  availability_zone = aws_instance.exasol_node[floor(count.index / var.data_volumes_per_node)].availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name        = "n${floor(count.index / var.data_volumes_per_node) + 11}-data-${(count.index % var.data_volumes_per_node) + 1}"
    Cluster     = "exasol-cluster"
    VolumeIndex = tostring((count.index % var.data_volumes_per_node) + 1)
    NodeIndex   = tostring(floor(count.index / var.data_volumes_per_node) + 11)
  }
}

# Attach Data Volumes
resource "aws_volume_attachment" "data_attachment" {
  count       = var.node_count * var.data_volumes_per_node
  device_name = "/dev/sd${substr("fghijklmnopqrstuvwxyz", count.index % var.data_volumes_per_node, 1)}"
  volume_id   = aws_ebs_volume.data_volume[count.index].id
  instance_id = aws_instance.exasol_node[floor(count.index / var.data_volumes_per_node)].id
}

# Generate Ansible Inventory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tftpl", {
    instances    = aws_instance.exasol_node
    node_volumes = local.node_volumes
    ssh_key      = local_file.exasol_private_key_pem.filename
  })
  filename = "${path.module}/inventory.ini"
  file_permission = "0644" # REMOVED executable flag

  depends_on = [aws_instance.exasol_node, aws_volume_attachment.data_attachment]
}

# Generate SSH config
resource "local_file" "ssh_config" {
  content = <<-EOF
    # Exasol Cluster SSH Config
    %{for idx, instance in aws_instance.exasol_node~}
    Host n${idx + 11}
        HostName ${instance.public_ip}
        User exasol
        IdentityFile ${local_file.exasol_private_key_pem.filename}
        StrictHostKeyChecking no
        UserKnownHostsFile=/dev/null

    %{endfor~}
  EOF
  filename = "${path.module}/ssh_config"
  file_permission = "0644" # REMOVED executable flag

  depends_on = [aws_instance.exasol_node]
}
