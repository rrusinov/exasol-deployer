variable "digitalocean_token" {
  description = "The DigitalOcean API token for authentication."
  type        = string
  sensitive   = true
  # Value will be set in variables.auto.tfvars during initialization
}

variable "digitalocean_region" {
  description = "The DigitalOcean region to deploy the cluster in (e.g., 'nyc1', 'nyc3', 'sfo3', 'lon1', 'fra1')."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}
