output "ami_id" {
  description = "The AMI ID used for the instances."
  value       = data.aws_ami.ubuntu.id
}

output "instance_details" {
  description = "Detailed information for each created instance."
  value = {
    for idx, instance in aws_instance.exasol_node :
    "exasol-node-${idx + 1}" => {
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

output "private_key_file" {
  description = "Path to the generated private SSH key. IMPORTANT: Keep this file secure."
  value       = local_file.exasol_private_key_pem.filename
}

output "ssh_config_file" {
  description = "Path to the generated SSH config file for easy access."
  value       = local_file.ssh_config.filename
}

output "ansible_inventory_file" {
  description = "Path to the generated Ansible inventory file."
  value       = local_file.ansible_inventory.filename
}

output "ansible_command" {
  description = "The command to run the Ansible playbook against the new infrastructure."
  value       = "ansible-playbook -i ${local_file.ansible_inventory.filename} setup-exasol-cluster.yml"
}

output "next_steps" {
  description = "Next steps to provision the cluster and connect to the nodes."
  value = <<-EOT

    ✅ Infrastructure created successfully!

    Next steps:
    1. Wait ~60 seconds for instances to fully boot.
    2. Run the Ansible playbook:
       ansible-playbook -i ${local_file.ansible_inventory.filename} setup-exasol-cluster.yml

    3. Connect to a node using the generated SSH config:
       ssh -F ${local_file.ssh_config.filename} exasol-node-1

    Or use individual SSH commands:
    ${join("\n    ", [for idx, instance in aws_instance.exasol_node : "ssh -i ${local_file.exasol_private_key_pem.filename} ubuntu@${instance.public_ip}  # exasol-node-${idx + 1}"])}
  EOT
}

