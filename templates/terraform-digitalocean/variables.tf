variable "digitalocean_token" {
  description = "The DigitalOcean API token for authentication."
  type        = string
  sensitive   = true
  # Value will be set in variables.auto.tfvars during initialization
}

variable "digitalocean_region" {
  description = "The DigitalOcean region to deploy the cluster in (e.g., 'nyc1', 'nyc3', 'sfo3', 'lon1', 'fra1')."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "instance_type" {
  description = "The DigitalOcean droplet size for the cluster nodes (e.g., 's-2vcpu-4gb', 'c-4', 'g-8vcpu-32gb')."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
  # Examples:
  # - Basic: s-1vcpu-1gb, s-2vcpu-2gb, s-2vcpu-4gb, s-4vcpu-8gb
  # - General Purpose: g-2vcpu-8gb, g-4vcpu-16gb, g-8vcpu-32gb
  # - CPU-Optimized: c-2, c-4, c-8, c-16, c-32
  # - Memory-Optimized: m-2vcpu-16gb, m-4vcpu-32gb, m-8vcpu-64gb
}

variable "instance_architecture" {
  description = "The architecture for the droplet (e.g., 'x86_64' or 'arm64'). Value is determined from the selected database version."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
  # Note: DigitalOcean currently only supports x86_64 droplets

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
  description = "The size of the root volume in GB. NOTE: This parameter is ignored for DigitalOcean."
  type        = number
  default     = 50
  # Note: DigitalOcean droplet disk size is determined by the instance type slug
  # (e.g., s-2vcpu-4gb = 80GB, s-4vcpu-8gb = 160GB) and cannot be customized independently.
  # This variable is kept for consistency with other cloud providers but has no effect.
}

variable "data_volume_size" {
  description = "The size of the data volume in GB. Set with --data-volume-size during initialization."
  type        = number
  # Value will be set in variables.auto.tfvars during initialization
  # Minimum size: 1 GB, maximum: 16384 GB (16 TB)
}

variable "data_volumes_per_node" {
  description = "The number of data volumes to attach to each node."
  type        = number
  default     = 1
  # Optional: Can be overridden in variables.auto.tfvars
  # Note: DigitalOcean allows up to 7 volumes per droplet
}

variable "owner" {
  description = "Owner tag for all resources. Set with --owner during initialization."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "enable_spot_instances" {
  description = "Enable spot instances for cost savings. Not supported on DigitalOcean."
  type        = bool
  default     = false
  # DigitalOcean does not have spot/preemptible instances
  # This variable is kept for consistency with other cloud providers
}

variable "enable_multicast_overlay" {
  description = "Enable VXLAN overlay network for multicast support. Set with --enable-multicast-overlay during initialization."
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
