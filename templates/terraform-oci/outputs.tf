# Instance public IPs for SSH access
output "instance_public_ips" {
  description = "Public IP addresses of the Exasol cluster nodes"
  value       = oci_core_instance.exasol[*].public_ip
}

# Instance private IPs for internal communication
output "instance_private_ips" {
  description = "Private IP addresses of the Exasol cluster nodes"
  value       = oci_core_instance.exasol[*].private_ip
}

# Instance IDs for reference
output "instance_ids" {
  description = "Instance IDs of the Exasol cluster nodes"
  value       = oci_core_instance.exasol[*].id
}

# VCN information
output "vcn_id" {
  description = "ID of the VCN"
  value       = oci_core_vcn.exasol.id
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = oci_core_subnet.exasol.id
}
