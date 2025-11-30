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

variable "enable_spot_instances" {
  description = "Enable spot instances for cost savings (AWS only). Set with --aws-spot-instance during initialization."
  type        = bool
  default     = false
}

variable "enable_gre_mesh" {
  description = "Enable GRE mesh network overlay for multicast support. Set with --enable-gre-mesh during initialization."
  type        = bool
  default     = false
}

variable "infra_desired_state" {
  description = "Desired infrastructure power state ('running' or 'stopped')."
  type        = string
  default     = "running"

  validation {
    condition     = contains(["running", "stopped"], var.infra_desired_state)
    error_message = "infra_desired_state must be either 'running' or 'stopped'."
  }
}

variable "availability_zone" {
  description = "The AWS availability zone to deploy resources in. Set during initialization based on instance type availability."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}
