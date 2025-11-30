variable "hetzner_token" {
  description = "The Hetzner Cloud API token for authentication."
  type        = string
  sensitive   = true
  # Value will be set in variables.auto.tfvars during initialization
}

variable "hetzner_location" {
  description = "The Hetzner Cloud location (e.g., 'nbg1', 'fsn1', 'hel1')."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "hetzner_network_zone" {
  description = "The Hetzner Cloud network zone (e.g., 'eu-central' for Germany locations, 'us-east' for US locations)."
  type        = string
  default     = "eu-central"
  # Value will be set in variables.auto.tfvars during initialization
}

variable "instance_type" {
  description = "The Hetzner Cloud server type for the cluster nodes (e.g., 'cpx31', 'ccx33', 'cax21')."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
  # Examples:
  # - x86_64: cpx11, cpx21, cpx31, cpx41, cpx51
  # - x86_64 dedicated: ccx13, ccx23, ccx33, ccx43, ccx53, ccx63
  # - arm64: cax11, cax21, cax31, cax41
}

variable "instance_architecture" {
  description = "The architecture for the server (e.g., 'x86_64' or 'arm64'). Value is determined from the selected database version."
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
  description = "The size of the root volume in GB. Note: Hetzner images come with fixed root disk sizes."
  type        = number
  default     = 50
  # Note: Hetzner servers have fixed root disk sizes per server type
  # This variable is kept for consistency but may not affect the actual root disk size
}

variable "data_volume_size" {
  description = "The size of the data volume in GB. Set with --data-volume-size during initialization."
  type        = number
  # Value will be set in variables.auto.tfvars during initialization
  # Minimum size: 10 GB, billed per GB
}

variable "data_volumes_per_node" {
  description = "The number of data volumes to attach to each node."
  type        = number
  default     = 1
  # Optional: Can be overridden in variables.auto.tfvars
}

variable "owner" {
  description = "Owner label for all resources. Set with --owner during initialization."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "enable_spot_instances" {
  description = "Enable spot instances for cost savings. Not supported on Hetzner Cloud."
  type        = bool
  default     = false
  # Hetzner Cloud does not have spot/preemptible instances
  # This variable is kept for consistency with other cloud providers
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
