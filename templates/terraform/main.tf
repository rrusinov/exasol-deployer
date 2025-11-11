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
# SSH Key Pair Generation (NEW SECTION)
# This creates a new SSH key pair dynamically for this deployment.
# ==============================================================================

resource "tls_private_key" "exasol_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "exasol_auth" {
  key_name   = "exasol-cluster-key-${random_id.instance.hex}"
  public_key = tls_private_key.exasol_key.public_key_openssh
}

resource "local_file" "exasol_private_key_pem" {
  content  = tls_private_key.exasol_key.private_key_pem
  filename = "${path.module}/exasol-key.pem"

  provisioner "local-exec" {
    command = "chmod 400 ${self.filename}"
  }
}

resource "random_id" "instance" {
  byte_length = 8
}

locals {
  # Map the architecture variable to the string used in the AMI name filter.
  # AWS and Ubuntu AMIs often use 'amd64' in the name for 'x86_64' architecture.
  ami_name_arch = var.instance_architecture == "x86_64" ? "amd64" : "arm64"
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

  # Spot Instance configuration
  #instance_market_options {
  #  market_type = "spot"
  #  spot_options {
  #    spot_instance_type    = "persistent"
  #    instance_interruption_behavior = "stop" #"hibernate"
  #  }
  #}

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
resource "aws_ebs_volume" "data_volume" {
  count             = var.node_count
  availability_zone = aws_instance.exasol_node[count.index].availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name    = "n${count.index + 11}-data"
    Cluster = "exasol-cluster"
  }
}

# Attach Data Volumes
resource "aws_volume_attachment" "data_attachment" {
  count       = var.node_count
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data_volume[count.index].id
  instance_id = aws_instance.exasol_node[count.index].id
}

# Generate Ansible Inventory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tftpl", {
    instances = aws_instance.exasol_node
    ssh_key   = local_file.exasol_private_key_pem.filename
  })
  filename = "${path.module}/inventory.ini"
  file_permission = "0644" # REMOVED executable flag

  depends_on = [aws_instance.exasol_node]
}

# Generate SSH config
resource "local_file" "ssh_config" {
  content = <<-EOF
    # Exasol Cluster SSH Config
    %{for idx, instance in aws_instance.exasol_node~}
    Host n${idx + 11}
        HostName ${instance.public_ip}
        User ubuntu
        IdentityFile ${local_file.exasol_private_key_pem.filename}
        StrictHostKeyChecking no
        UserKnownHostsFile=/dev/null

    %{endfor~}
  EOF
  filename = "${path.module}/ssh_config"
  file_permission = "0644" # REMOVED executable flag

  depends_on = [aws_instance.exasol_node]
}

