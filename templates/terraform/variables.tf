variable "aws_profile" {
  description = "The AWS profile to use for authentication."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "aws_region" {
  description = "The AWS region to deploy the cluster in."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "preferred_availability_zones" {
  description = "Optional list of AZs (e.g., [\"us-east-1a\", \"us-east-1b\"]) to prioritize. The deployer will fall back to any AZ that supports the selected instance type."
  type        = list(string)
  default     = []
}

variable "instance_type" {
  description = "The EC2 instance type for the cluster nodes. Value is determined from the selected database version or can be overridden with --instance-type."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
  # Examples:
  # - x86_64: m6idn.large, c7a.16xlarge
  # - arm64:  c8g.16xlarge
}

variable "instance_architecture" {
  description = "The architecture for the EC2 instance (e.g., 'x86_64' or 'arm64'). Value is determined from the selected database version."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization

  validation {
    condition     = contains(["x86_64", "arm64"], var.instance_architecture)
    error_message = "The instance_architecture must be either 'x86_64' or 'arm64'."
  }
}

variable "node_count" {
  description = "The number of nodes in the cluster. Set with --cluster-size during initialization."
  type        = number
  # Value will be set in variables.auto.tfvars during initialization
}

variable "allowed_cidr" {
  description = "The CIDR block allowed to access the cluster for SSH and Admin UI. Set with --allowed-cidr during initialization."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
  # IMPORTANT: For security, set this to your own IP address (e.g., "1.2.3.4/32")
}

variable "root_volume_size" {
  description = "The size of the root volume in GB."
  type        = number
  default     = 50
  # Fixed default value - not configurable via command line
}

variable "data_volume_size" {
  description = "The size of the data volume in GB. Set with --data-volume-size during initialization."
  type        = number
  # Value will be set in variables.auto.tfvars during initialization
}

variable "data_volumes_per_node" {
  description = "The number of data volumes to attach to each node."
  type        = number
  default     = 1
  # Optional: Can be overridden in variables.auto.tfvars
}

variable "owner" {
  description = "Owner tag for all resources. Set with --owner during initialization."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}
