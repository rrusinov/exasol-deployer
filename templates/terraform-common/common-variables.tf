# ==============================================================================
# COMMON VARIABLES (shared across all cloud providers)
# These variables are used by all cloud providers with the same definition.
#
# NOTE: These variables are redefined in each provider's variables.tf for
# better organization and to allow provider-specific documentation/examples.
# The definitions here serve as documentation and reference.
# ==============================================================================

# ==============================================================================
# INFRASTRUCTURE STATE MANAGEMENT
# ==============================================================================

variable "infra_desired_state" {
  description = "Desired state of infrastructure: 'running' or 'stopped'"
  type        = string
  default     = "running"
  
  validation {
    condition     = contains(["running", "stopped"], var.infra_desired_state)
    error_message = "infra_desired_state must be either 'running' or 'stopped'."
  }
}

variable "instance_architecture" {
  description = "The architecture for the instances (e.g., 'x86_64' or 'arm64')."
  type        = string

  validation {
    condition     = contains(["x86_64", "arm64"], var.instance_architecture)
    error_message = "The instance_architecture must be either 'x86_64' or 'arm64'."
  }
}

variable "node_count" {
  description = "The number of nodes in the cluster."
  type        = number
}

variable "allowed_cidr" {
  description = "The CIDR block allowed to access the cluster."
  type        = string
}

variable "host_password" {
  description = "Host OS password for the exasol user (e.g., SSH/console logins)."
  type        = string
  sensitive   = true
}

variable "root_volume_size" {
  description = "The size of the root volume in GB."
  type        = number
  default     = 50
}

variable "data_volume_size" {
  description = "The size of the data volume in GB."
  type        = number
}

variable "data_volumes_per_node" {
  description = "The number of data volumes to attach to each node."
  type        = number
  default     = 1
}

variable "owner" {
  description = "Owner tag/label for all resources."
  type        = string
}

variable "enable_spot_instances" {
  description = "Enable spot/preemptible instances for cost savings."
  type        = bool
  default     = false
}

variable "enable_multicast_overlay" {
  description = "Enable VXLAN overlay network for multicast support."
  type        = bool
  default     = false
}

variable "instance_type" {
  description = "The instance/VM type for the cluster nodes (provider-specific)."
  type        = string
}
