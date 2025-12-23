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
