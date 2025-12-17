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
