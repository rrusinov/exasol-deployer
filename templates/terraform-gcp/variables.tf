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
