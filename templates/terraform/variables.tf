variable "aws_profile" {
  description = "The AWS profile to use for authentication."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "The AWS region to deploy the cluster in."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "The EC2 instance type for the cluster nodes."
  type        = string
  #default     = "c8g.16xlarge" #graviton 64 vCPUs 128GB
  default     = "c7a.16xlarge" #x86_64
}

variable "instance_architecture" {
  description = "The architecture for the EC2 instance (e.g., 'x86_64' or 'arm64')."
  type        = string
  default     = "x86_64"

  validation {
    # Ensure the value is one of the two most common AWS architectures
    condition     = contains(["x86_64", "arm64"], var.instance_architecture)
    error_message = "The instance_architecture must be either 'x86_64' or 'arm64'."
  }
}

variable "node_count" {
  description = "The number of nodes in the cluster."
  type        = number
  default     = 4
}

variable "allowed_cidr" {
  description = "The CIDR block allowed to access the cluster for SSH and Admin UI."
  type        = string
  # IMPORTANT: For security, it's best to set this to your own IP address.
  # You can find it by searching "what is my ip".
  default     = "0.0.0.0/0"
}

variable "root_volume_size" {
  description = "The size of the root volume in GB."
  type        = number
  default     = 300
}

variable "data_volume_size" {
  description = "The size of the data volume in GB."
  type        = number
  default     = 700
}

