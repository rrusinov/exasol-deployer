# Exoscale-specific variables

variable "exoscale_zone" {
  description = "Exoscale zone"
  type        = string
  default     = "ch-gva-2"
}

variable "exoscale_api_key" {
  description = "Exoscale API key"
  type        = string
  sensitive   = true
}

variable "exoscale_api_secret" {
  description = "Exoscale API secret"
  type        = string
  sensitive   = true
}

# Common variables (inherited from common.tf)
variable "instance_type" {
  description = "Instance type"
  type        = string
}

variable "instance_architecture" {
  description = "Instance architecture (x86_64 or arm64)"
  type        = string
  default     = "x86_64"
}

variable "node_count" {
  description = "Number of nodes in the cluster"
  type        = number
  default     = 1
}

variable "data_volume_size" {
  description = "Size of data volumes in GB"
  type        = number
  default     = 100
}

variable "data_volumes_per_node" {
  description = "Number of data volumes per node"
  type        = number
  default     = 1
}

variable "root_volume_size" {
  description = "Size of root volume in GB"
  type        = number
  default     = 50
}

variable "allowed_cidr" {
  description = "CIDR block allowed to access the cluster"
  type        = string
  default     = "0.0.0.0/0"
}

variable "owner" {
  description = "Owner tag for resources"
  type        = string
  default     = "exasol-deployer"
}

variable "enable_multicast_overlay" {
  description = "Enable multicast overlay network"
  type        = bool
  default     = false
}

variable "host_password" {
  description = "Password for the exasol user on the host"
  type        = string
  sensitive   = true
}

variable "infra_desired_state" {
  description = "Desired infrastructure state (running or stopped)"
  type        = string
  default     = "running"
}
