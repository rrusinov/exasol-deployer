variable "hetzner_token" {
  description = "The Hetzner Cloud API token for authentication."
  type        = string
  sensitive   = true
  # Value will be set in variables.auto.tfvars during initialization
}

variable "hetzner_location" {
  description = "The Hetzner Cloud location (e.g., 'nbg1', 'fsn1', 'hel1')."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "hetzner_network_zone" {
  description = "The Hetzner Cloud network zone (e.g., 'eu-central' for Germany locations, 'us-east' for US locations)."
  type        = string
  default     = "eu-central"
  # Value will be set in variables.auto.tfvars during initialization
}
