variable "azure_subscription" {
  description = "The Azure subscription ID to use for authentication."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "azure_client_id" {
  description = "Service principal client/app ID."
  type        = string
  default     = null
}

variable "azure_client_secret" {
  description = "Service principal client secret."
  type        = string
  default     = null
}

variable "azure_tenant_id" {
  description = "Azure AD tenant ID for the service principal."
  type        = string
  default     = null
}

variable "azure_region" {
  description = "The Azure region to deploy the cluster in."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "instance_type" {
  description = "The Azure VM size for the cluster nodes."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
  # Examples:
  # - x86_64: Standard_D16ds_v5, Standard_E16ds_v5
  # - arm64:  Standard_D16pds_v5
}

variable "instance_architecture" {
  description = "The architecture for the VM (e.g., 'x86_64' or 'arm64')."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization

  validation {
    condition     = contains(["x86_64", "arm64"], var.instance_architecture)
    error_message = "The instance_architecture must be either 'x86_64' or 'arm64'."
  }
}

variable "node_count" {
  description = "The number of nodes in the cluster."
  type        = number
  # Value will be set in variables.auto.tfvars during initialization
}

variable "allowed_cidr" {
  description = "The CIDR block allowed to access the cluster."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "root_volume_size" {
  description = "The size of the root volume in GB."
  type        = number
  default     = 50
}

variable "data_volume_size" {
  description = "The size of the data volume in GB."
  type        = number
  # Value will be set in variables.auto.tfvars during initialization
}

variable "data_volumes_per_node" {
  description = "The number of data volumes to attach to each node."
  type        = number
  default     = 1
}

variable "owner" {
  description = "Owner tag for all resources."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "enable_spot_instances" {
  description = "Enable spot instances for cost savings (Azure Spot VMs)."
  type        = bool
  default     = false
}

variable "enable_multicast_overlay" {
  description = "Enable Tinc VPN overlay network for multicast support. Set with --enable-multicast-overlay during initialization."
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
