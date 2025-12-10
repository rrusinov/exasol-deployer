# AWS-specific outputs in addition to common outputs
output "ami_id" {
  description = "The AMI ID used for the instances."
  value       = data.aws_ami.ubuntu.id
}

output "instance_details" {
  description = "Detailed information for each created instance."
  value = {
    for idx, instance in aws_instance.exasol_node :
    "n${idx + 11}" => {
      instance_id = instance.id
      public_ip   = instance.public_ip
      private_ip  = instance.private_ip
      az          = instance.availability_zone
    }
  }
}

output "security_group_id" {
  description = "The ID of the security group applied to the cluster."
  value       = aws_security_group.exasol_cluster.id
}

output "vpc_id" {
  description = "The ID of the VPC created for the cluster."
  value       = aws_vpc.exasol_vpc.id
}

