#!/usr/bin/env bash
# Template Builder - Generates cloud-specific templates from shared components
# This avoids code duplication while keeping templates simple and readable

# Include guard
if [[ -n "${__EXASOL_TEMPLATE_BUILDER_SH_INCLUDED__:-}" ]]; then
    return 0
fi
readonly __EXASOL_TEMPLATE_BUILDER_SH_INCLUDED__=1

# Get the common cloud-init script
get_cloud_init_script() {
    cat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Create exasol group
groupadd -f exasol

# Create exasol user with sudo privileges
if ! id -u exasol >/dev/null 2>&1; then
  useradd -m -g exasol -G sudo -s /bin/bash exasol
fi

# Enable passwordless sudo for exasol user
echo "exasol ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/11-exasol-user
chmod 0440 /etc/sudoers.d/11-exasol-user

# Copy SSH authorized_keys from default cloud user to exasol user
for user_home in /home/ubuntu /home/azureuser /home/admin /home/ec2-user /home/debian; do
  if [ -d "$user_home/.ssh" ] && [ -f "$user_home/.ssh/authorized_keys" ]; then
    mkdir -p /home/exasol/.ssh
    cp "$user_home/.ssh/authorized_keys" /home/exasol/.ssh/
    chown -R exasol:exasol /home/exasol/.ssh
    chmod 700 /home/exasol/.ssh
    chmod 600 /home/exasol/.ssh/authorized_keys
    break
  fi
done

# Ensure original cloud user also has passwordless sudo
for cloud_user in ubuntu azureuser admin ec2-user debian; do
  if id -u "$cloud_user" >/dev/null 2>&1; then
    echo "$cloud_user ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/10-$cloud_user-user"
    chmod 0440 "/etc/sudoers.d/10-$cloud_user-user"
  fi
done
EOF
}

# Get common SSH key generation block
get_ssh_key_generation() {
    cat <<'EOF'
resource "tls_private_key" "exasol_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "exasol_private_key_pem" {
  content  = tls_private_key.exasol_key.private_key_pem
  filename = "${path.module}/exasol-key.pem"

  provisioner "local-exec" {
    command = "chmod 400 ${self.filename}"
  }
}

resource "random_id" "instance" {
  byte_length = 8
}
EOF
}

# Get common inventory template
get_inventory_template() {
    cat <<'EOF'
[exasol_nodes]
%{~ for idx, node in nodes }
n${idx + 11} ansible_host=${node.public_ip} ansible_user=exasol private_ip=${node.private_ip} data_volume_ids='${jsonencode(node.volume_ids)}'
%{~ endfor }

[exasol_nodes:vars]
ansible_user=exasol
ansible_ssh_private_key_file=${ssh_key}
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF
}

# Get common SSH config generation
get_ssh_config_generation() {
    cat <<'EOF'
resource "local_file" "ssh_config" {
  content = join("\n", [
    for idx, ip in local.node_public_ips : <<-SSHEOF
    Host n${idx + 11}
        HostName ${ip}
        User exasol
        IdentityFile ${local_file.exasol_private_key_pem.filename}
        StrictHostKeyChecking no
        UserKnownHostsFile=/dev/null

    SSHEOF
  ])
  filename        = "${path.module}/ssh_config"
  file_permission = "0644"

  depends_on = [DEPENDS_ON_PLACEHOLDER]
}
EOF
}

# Get common variables
get_common_variables() {
    cat <<'EOF'
variable "instance_architecture" {
  description = "The architecture for the instances (e.g., 'x86_64' or 'arm64')."
  type        = string

  validation {
    condition     = contains(["x86_64", "arm64"], var.instance_architecture)
    error_message = "The instance_architecture must be either 'x86_64' or 'arm64'."
  }
}

variable "node_count" {
  description = "The number of nodes in the cluster."
  type        = number
}

variable "allowed_cidr" {
  description = "The CIDR block allowed to access the cluster."
  type        = string
}

variable "root_volume_size" {
  description = "The size of the root volume in GB."
  type        = number
  default     = 50
}

variable "data_volume_size" {
  description = "The size of the data volume in GB."
  type        = number
}

variable "data_volumes_per_node" {
  description = "The number of data volumes to attach to each node."
  type        = number
  default     = 1
}

variable "owner" {
  description = "Owner tag/label for all resources."
  type        = string
}

variable "enable_spot_instances" {
  description = "Enable spot/preemptible instances for cost savings."
  type        = bool
  default     = false
}

variable "instance_type" {
  description = "The instance/VM type for the cluster nodes (provider-specific)."
  type        = string
}
EOF
}
