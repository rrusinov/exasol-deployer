variable "libvirt_memory_gb" {
    description = "Memory per VM in GB for libvirt provider."
    type        = number
    default     = 4
}

variable "libvirt_vcpus" {
    description = "Number of virtual CPUs per VM for libvirt provider."
    type        = number
    default     = 2
}

variable "libvirt_network_bridge" {
    description = "Libvirt network name (e.g., 'default' which typically uses virbr0 bridge)."
    type        = string
    default     = "default"
}

variable "libvirt_disk_pool" {
    description = "Storage pool name for libvirt provider."
    type        = string
    default     = "default"
}

variable "instance_type" {
    description = "The instance type mapping (used for compatibility with common framework)."
    type        = string
    # Value will be set in variables.auto.tfvars during initialization
}

variable "instance_architecture" {
    description = "The architecture for the VM (e.g., 'x86_64' or 'arm64'). Value is determined from the selected database version."
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
    # For libvirt, this typically allows local network access
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

variable "infra_desired_state" {
    description = "Desired infrastructure power state ('running' or 'stopped')."
    type        = string
    default     = "running"

    validation {
        condition     = contains(["running", "stopped"], var.infra_desired_state)
        error_message = "infra_desired_state must be either 'running' or 'stopped'."
    }
}