variable "oci_region" {
  description = "The OCI region to deploy the cluster in."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "oci_compartment_ocid" {
  description = "The OCID of the OCI compartment where resources will be created."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "oci_tenancy_ocid" {
  description = "The OCID of the OCI tenancy."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "oci_user_ocid" {
  description = "The OCID of the OCI user."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "oci_fingerprint" {
  description = "The fingerprint of the OCI API key."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "oci_private_key_path" {
  description = "The path to the OCI private key file."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "instance_type" {
  description = "The OCI compute shape for the cluster nodes. Value is determined from the selected database version or can be overridden with --instance-type."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
  # Examples:
  # - x86_64: VM.Standard.E4.Flex, VM.Standard3.Flex
  # - arm64:  VM.Standard.A1.Flex
}

variable "instance_architecture" {
  description = "The architecture for the compute instance (e.g., 'x86_64' or 'arm64'). Value is determined from the selected database version."
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

variable "host_password" {
  description = "Host OS password for the exasol user (SSH/console access). Set with --host-password or generated automatically."
  type        = string
  sensitive   = true
  # Value will be set in variables.auto.tfvars during initialization
}

variable "data_volume_size" {
  description = "Size of each data volume in GB. Set with --data-volume-size during initialization."
  type        = number
  # Value will be set in variables.auto.tfvars during initialization
}

variable "data_volumes_per_node" {
  description = "Number of data volumes per node. Set with --data-volumes-per-node during initialization."
  type        = number
  # Value will be set in variables.auto.tfvars during initialization
}

variable "root_volume_size" {
  description = "Size of the root volume in GB. Set with --root-volume-size during initialization."
  type        = number
  # Value will be set in variables.auto.tfvars during initialization
}

variable "owner" {
  description = "Owner tag for resources. Set with --owner during initialization."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "enable_multicast_overlay" {
  description = "Enable VXLAN overlay network for multicast support. Set with --enable-multicast-overlay during initialization."
  type        = bool
  # Value will be set in variables.auto.tfvars during initialization
  # OCI does not support native multicast, so this enables VXLAN overlay
}

variable "infra_desired_state" {
  description = "Desired state of the infrastructure: 'running' or 'stopped'. Used for power control."
  type        = string
  default     = "running"
}
