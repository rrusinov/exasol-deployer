variable "gcp_project" {
  description = "The GCP project ID to use (auto-detected from credentials file if not provided)."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization

  validation {
    condition     = length(trimspace(var.gcp_project)) > 0
    error_message = "The gcp_project must not be empty."
  }
}

variable "gcp_region" {
  description = "The GCP region to deploy the cluster in."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "gcp_zone" {
  description = "The GCP zone to deploy the cluster in. Defaults to <region>-a if left empty."
  type        = string
  default     = ""
}

variable "gcp_credentials_file" {
  description = "Path to the GCP service account credentials JSON file."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization

  validation {
    condition     = fileexists(var.gcp_credentials_file)
    error_message = "The gcp_credentials_file must exist and be readable."
  }
}

variable "instance_type" {
  description = "The GCP machine type for the cluster nodes."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
  # Examples:
  # - x86_64: n2-standard-16, n2-highmem-16
  # - arm64:  t2a-standard-16
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
  description = "Enable spot instances for cost savings (GCP Preemptible VMs)."
  type        = bool
  default     = false
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
