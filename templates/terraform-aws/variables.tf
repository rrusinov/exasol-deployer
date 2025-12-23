variable "aws_profile" {
  description = "The AWS profile to use for authentication."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "aws_region" {
  description = "The AWS region to deploy the cluster in."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}

variable "availability_zone" {
  description = "The AWS availability zone to deploy resources in. Set during initialization based on instance type availability."
  type        = string
  # Value will be set in variables.auto.tfvars during initialization
}
