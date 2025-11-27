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
  # Provider-specific info for common outputs
  provider_name = "AWS"
  provider_code = "aws"
  region_name   = var.aws_region

  # Map architecture variable to string used in AMI name filter.
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

  # Node public IPs for common outputs
  node_public_ips  = [for instance in aws_instance.exasol_node : instance.public_ip]
  node_private_ips = [for instance in aws_instance.exasol_node : instance.private_ip]

  # GRE mesh overlay not used on AWS; keep empty to satisfy common inventory template
  gre_data = {}
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

# Create a new VPC
resource "aws_vpc" "exasol_vpc" {
  # Use range derived from cluster ID to ensure uniqueness while being deterministic
  # Format: 10.X.Y.0/24 where X and Y are derived from cluster ID hex digits
  # Provides 253 × 256 = 64,768 possible unique networks (10.254.0.0/16 reserved for GRE overlay)
  # Use a /16 network and carve subnets from it to avoid collisions across clusters
  cidr_block           = "10.${(parseint(substr(random_id.instance.hex, 0, 2), 16) % 253) + 1}.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "exasol-vpc"
  }
}

# Create a subnet carved from the VPC /16 (produce a /24)
resource "aws_subnet" "exasol_subnet" {
  vpc_id                  = aws_vpc.exasol_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.exasol_vpc.cidr_block, 8, 1)
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone

  tags = {
    Name = "exasol-subnet"
  }
}

# Security Group
resource "aws_security_group" "exasol_cluster" {
  name        = "exasol-cluster-sg"
  description = "Security group for Exasol cluster"
  vpc_id      = aws_vpc.exasol_vpc.id

  # External access rules - dynamically created for each port
  dynamic "ingress" {
    for_each = local.exasol_firewall_ports

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
  user_data = local.cloud_init_script

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

# Manage instance power state via OpenTofu when requested
resource "aws_ec2_instance_state" "exasol_node_state" {
  count       = var.node_count
  instance_id = aws_instance.exasol_node[count.index].id
  state       = var.infra_desired_state == "stopped" ? "stopped" : "running"
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

# Ansible inventory is generated in common.tf
# SSH config is generated in common.tf
