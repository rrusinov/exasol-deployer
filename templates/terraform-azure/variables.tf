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
