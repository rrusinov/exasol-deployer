# Libvirt/KVM Setup Guide

This guide covers setting up libvirt/KVM virtualization for local Exasol deployments using the Exasol Deployer.

## Overview

The libvirt provider enables local testing of Exasol deployments using KVM virtualization before moving to cloud providers. This provides a cost-effective local development and testing environment.

> Status: Only Linux system libvirt is supported (local `qemu:///system` or remote `qemu+ssh://.../system`). macOS and session libvirt daemons are not supported.

## Prerequisites

### System Requirements

- **Operating System**: Linux (Ubuntu 20.04+, Debian 10+, CentOS 8+, RHEL 8+)
- **CPU**: Hardware virtualization support (Intel VT-x or AMD-V)
- **Memory**: Minimum 8GB RAM (16GB+ recommended for multi-node clusters)
- **Storage**: Minimum 100GB free disk space
- **Permissions**: User membership in `libvirt` and `kvm` groups

### Hardware Virtualization Check

Verify your system supports virtualization:

**Linux**:
```bash
# Check for Intel VT-x or AMD-V
egrep -c '(vmx|svm)' /proc/cpuinfo

# Should return > 0 if virtualization is supported
# If 0, check BIOS settings to enable virtualization
```

**macOS**: not supported for libvirt deployments.

## Installation

### Ubuntu/Debian

```bash
# Update package index
sudo apt update

# Install required packages
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst genisoimage

# Install OpenTofu (if not already installed)
curl -fsSL https://get.opentofu.org | sudo bash
```

### CentOS/RHEL

```bash
# Install EPEL repository
sudo yum install -y epel-release

# Install required packages
sudo yum install -y qemu-kvm libvirt-daemon libvirt-client bridge-utils virt-install genisoimage

# Install OpenTofu
curl -fsSL https://get.opentofu.org | sudo bash
```

### macOS

macOS libvirt is not supported. Use a Linux host (local or remote via SSH) running a system libvirt daemon.

**Connection URI (system only)**:
- `exasol init` runs `virsh uri` and records the detected value in `variables.auto.tfvars`.
- Only system daemons are supported: use `qemu:///system` locally or `qemu+ssh://user@libvirt-host/system` remotely.
- If `virsh` isn't available, install libvirt or pass `--libvirt-uri qemu:///system`.

## Firmware Selection

The Terraform template exposes a `libvirt_firmware` variable so you can align firmware with the hypervisor in use.

- `exasol init` defaults this to `"efi"` for libvirt.
- Override the value in `variables.auto.tfvars` if your host requires a different firmware label or a fully qualified path to an `.fd` file.

```hcl
# variables.auto.tfvars
libvirt_firmware = "/usr/share/OVMF/OVMF_CODE.fd" # or "bios" for legacy
```

This template targets Linux KVM hosts (local or remote system libvirt).

## User Configuration

### Add User to Required Groups

```bash
# Add your user to libvirt and kvm groups
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER

# Log out and log back in for group changes to take effect
# Or use newgrp for current session:
newgrp libvirt
newgrp kvm
```

### Verify Group Membership

```bash
# Check if user is in required groups
groups $USER | grep -E '(libvirt|kvm)'
```

## Service Configuration

### Start and Enable Libvirt Services

```bash
# Start libvirtd service
sudo systemctl start libvirtd

# Enable libvirtd to start on boot
sudo systemctl enable libvirtd

# Check service status
sudo systemctl status libvirtd
```

**macOS**:
```bash
# Libvirt daemon is managed by Homebrew services
brew services list | grep libvirt

# Should show libvirt started
# If not running:
brew services start libvirt
```

### Configure QEMU for Copy-on-Write Volumes

**IMPORTANT**: Configure qemu.conf to allow access to backing files for copy-on-write volumes. This prevents "Permission denied" errors during VM creation.

**Note on System vs User Session**: The Exasol deployer uses `qemu:///system` (system-wide libvirt daemon) rather than `qemu:///session` (user session) because system mode provides:
- Full network bridging support
- Access to system storage pools
- Better resource management
- Standard production configuration

VMs are managed by the system libvirtd daemon, but users in the `libvirt` group can fully manage them. QEMU processes run as `libvirt-qemu` user (not root) for security.

```bash
# Edit qemu.conf
sudo vi /etc/libvirt/qemu.conf

# Add or uncomment these lines:
user = "libvirt-qemu"
group = "libvirt-qemu"
dynamic_ownership = 1
security_driver = "none"

# Save and restart libvirtd
sudo systemctl restart libvirtd

# Verify the settings:
sudo grep -E "^(user|group|dynamic_ownership|security_driver)" /etc/libvirt/qemu.conf

# Quick automated configuration (alternative to manual editing):
sudo sed -i 's/^#*user = .*/user = "libvirt-qemu"/' /etc/libvirt/qemu.conf
sudo sed -i 's/^#*group = .*/group = "libvirt-qemu"/' /etc/libvirt/qemu.conf
sudo sed -i 's/^#*dynamic_ownership = .*/dynamic_ownership = 1/' /etc/libvirt/qemu.conf
sudo sed -i 's/^#*security_driver = .*/security_driver = "none"/' /etc/libvirt/qemu.conf
grep -q "^user = " /etc/libvirt/qemu.conf || echo 'user = "libvirt-qemu"' | sudo tee -a /etc/libvirt/qemu.conf
grep -q "^group = " /etc/libvirt/qemu.conf || echo 'group = "libvirt-qemu"' | sudo tee -a /etc/libvirt/qemu.conf
grep -q "^dynamic_ownership = " /etc/libvirt/qemu.conf || echo 'dynamic_ownership = 1' | sudo tee -a /etc/libvirt/qemu.conf
grep -q "^security_driver = " /etc/libvirt/qemu.conf || echo 'security_driver = "none"' | sudo tee -a /etc/libvirt/qemu.conf
sudo systemctl restart libvirtd
```

### Verify Libvirt Installation

```bash
# Test libvirt connectivity
virsh list --all

# Should return:
# Id   Name   State
# ----  ----  -----
#
```

## Network Configuration

### Default Network

Libvirt typically creates a default NAT network. Verify it's active:

```bash
# Check default network status
virsh net-info default

# Start default network if not running
sudo virsh net-start default
sudo virsh net-autostart default
```

### Custom Bridge Network (Optional)

For better performance or external access, create a dedicated bridge:

```bash
# Create bridge network XML
cat > bridge-network.xml <<EOF
<network>
  <name>exasol-bridge</name>
  <forward mode='bridge'/>
  <bridge name='br0'/>
</network>
EOF

# Define and start the network
virsh net-define bridge-network.xml
virsh net-start exasol-bridge
virsh net-autostart exasol-bridge
```

## Storage Configuration

### Default Storage Pool

Verify the default storage pool:

```bash
# Check default pool status
virsh pool-info default

# Start default pool if not running
sudo virsh pool-start default
sudo virsh pool-autostart default
```

### Custom Storage Pool (Optional)

For larger deployments, create a dedicated storage pool:

```bash
# Create directory for custom pool
sudo mkdir -p /var/lib/libvirt/exasol-pool
sudo chown libvirt:libvirt /var/lib/libvirt/exasol-pool

# Create pool XML
cat > exasol-pool.xml <<EOF
<pool type='dir'>
  <name>exasol-pool</name>
  <target>
    <path>/var/lib/libvirt/exasol-pool</path>
  </target>
</pool>
EOF

# Define and start the pool
virsh pool-define exasol-pool.xml
virsh pool-start exasol-pool
virsh pool-autostart exasol-pool
```

## Terraform Provider Setup

### Install Libvirt Terraform Provider

The Exasol Deployer will automatically download the libvirt provider, but you can install it manually:

```bash
# Create plugin directory
mkdir -p ~/.terraform.d/plugins

# Download libvirt provider (example for Linux AMD64)
wget https://github.com/dmacvicar/libvirt-provider/releases/download/v0.7.0/terraform-provider-libvirt-0.7.0+git.1674638952.9c0f373a.Fedora_38.x86_64.tar.gz

# Extract and install
tar xzf terraform-provider-libvirt-0.7.0+git.1674638952.9c0f373a.Fedora_38.x86_64.tar.gz
mv terraform-provider-libvirt ~/.terraform.d/plugins/
```

## Testing the Setup

### Verify Complete Setup

```bash
# Test libvirt connectivity
virsh list --all

# Test network connectivity
virsh net-list --all

# Test storage pool
virsh pool-list --all

# Test OpenTofu
tofu version
```

### Run Basic Test

```bash
# Create test deployment
mkdir -p ~/test-libvirt
cd ~/test-libvirt

# Initialize libvirt deployment
exasol init --cloud-provider libvirt --deployment-dir . --cluster-size 1

# Verify templates are created
ls -la .templates/

# (Optional) Test Terraform validation
cd .templates
tofu init
tofu validate
```

## Usage Examples

### Basic Single-Node Deployment

```bash
# Initialize with defaults (4GB RAM, 2 vCPUs)
exasol init --cloud-provider libvirt --deployment-dir ./my-deployment

# Deploy
exasol deploy --deployment-dir ./my-deployment
```

### Multi-Node Deployment with Custom Resources

```bash
# Initialize with custom configuration
exasol init --cloud-provider libvirt --deployment-dir ./my-cluster \
    --cluster-size 3 \
    --libvirt-memory 8 \
    --libvirt-vcpus 4 \
    --libvirt-network default \
    --libvirt-pool default \
    --data-volume-size 500

# Deploy
exasol deploy --deployment-dir ./my-cluster
```

### High-Performance Testing

```bash
# Initialize for performance testing
exasol init --cloud-provider libvirt --deployment-dir ./perf-test \
    --cluster-size 1 \
    --libvirt-memory 32 \
    --libvirt-vcpus 16 \
    --data-volume-size 1000 \
    --data-volumes-per-node 4
```

## Accessing Your Cluster

```bash
# Recommended: Using generated SSH config
ssh -F ./my-deployment/ssh_config n11
```

Host OS password for the `exasol` user (useful for console access or password-based SSH if enabled):
```bash
cat .credentials.json | jq -r '.host_password'
```

## Troubleshooting

### Common Issues

#### Permission Denied Errors

```bash
# Symptoms: "Permission denied" when running virsh commands
# Solution: Ensure user is in libvirt and kvm groups
sudo usermod -aG libvirt,kvm $USER
newgrp libvirt
```

#### Network Bridge Issues

```bash
# Symptoms: VMs can't get IP addresses
# Solution: Check default network status
virsh net-info default
sudo virsh net-start default
sudo virsh net-autostart default
```

#### Storage Pool Issues

```bash
# Symptoms: Can't create VM volumes
# Solution: Check storage pool status
virsh pool-info default
sudo virsh pool-start default
sudo virsh pool-autostart default
```

#### KVM Acceleration Not Available

```bash
# Symptoms: Very slow VM performance
# Solution: Check KVM module and permissions
lsmod | grep kvm
ls -la /dev/kvm
sudo chmod 666 /dev/kvm  # Temporary fix
```

#### Cloud-init ISO Creation Fails

```bash
# Symptoms: Error "mkisofs: executable file not found in $PATH"
# Solution: Install genisoimage package
# Ubuntu/Debian:
sudo apt install -y genisoimage

# CentOS/RHEL:
sudo yum install -y genisoimage

# macOS: not supported for libvirt deployments

# Verify installation (Linux):
which mkisofs
# Should output: /usr/bin/mkisofs (Linux)
```

#### QEMU Permission Denied on Base Image

```bash
# Symptoms: Error "Could not open '/var/lib/libvirt/images/ubuntu-base-*.qcow2': Permission denied"
# Root cause: AppArmor/SELinux is blocking QEMU from accessing backing files for copy-on-write volumes
#
# Solution 1: Configure qemu.conf properly (RECOMMENDED - TESTED & WORKING)
sudo vi /etc/libvirt/qemu.conf

# Add or uncomment these lines:
user = "libvirt-qemu"
group = "libvirt-qemu"
dynamic_ownership = 1
security_driver = "none"

# Save and restart libvirtd
sudo systemctl restart libvirtd

# Verify the settings took effect:
sudo grep -E "^(user|group|dynamic_ownership|security_driver)" /etc/libvirt/qemu.conf

# Expected output:
# user = "libvirt-qemu"
# group = "libvirt-qemu"
# dynamic_ownership = 1
# security_driver = "none"

# Alternative: Use sed to apply all settings at once
sudo sed -i 's/^#*user = .*/user = "libvirt-qemu"/' /etc/libvirt/qemu.conf
sudo sed -i 's/^#*group = .*/group = "libvirt-qemu"/' /etc/libvirt/qemu.conf
sudo sed -i 's/^#*dynamic_ownership = .*/dynamic_ownership = 1/' /etc/libvirt/qemu.conf
sudo sed -i 's/^#*security_driver = .*/security_driver = "none"/' /etc/libvirt/qemu.conf
# If lines don't exist, append them:
grep -q "^user = " /etc/libvirt/qemu.conf || echo 'user = "libvirt-qemu"' | sudo tee -a /etc/libvirt/qemu.conf
grep -q "^group = " /etc/libvirt/qemu.conf || echo 'group = "libvirt-qemu"' | sudo tee -a /etc/libvirt/qemu.conf
grep -q "^dynamic_ownership = " /etc/libvirt/qemu.conf || echo 'dynamic_ownership = 1' | sudo tee -a /etc/libvirt/qemu.conf
grep -q "^security_driver = " /etc/libvirt/qemu.conf || echo 'security_driver = "none"' | sudo tee -a /etc/libvirt/qemu.conf
sudo systemctl restart libvirtd

# Solution 2: Put AppArmor in complain mode (alternative, requires apparmor-utils)
sudo apt install -y apparmor-utils  # Ubuntu/Debian
sudo aa-complain /usr/sbin/libvirtd
sudo systemctl restart libvirtd

# Verify:
sudo aa-status | grep libvirt
# Should show "libvirtd (complain)" instead of "libvirtd (enforce)"
```

### Debug Commands

```bash
# Check libvirtd logs
sudo journalctl -u libvirtd -f

# Check VM console
virsh console <vm-name>

# Check VM details
virsh dominfo <vm-name>

# Check network configuration
virsh net-dumpxml default

# Check storage pool details
virsh pool-dumpxml default
```

### Performance Optimization

#### Enable KVM Acceleration

Ensure KVM is being used for best performance:

```bash
# Verify KVM is available
kvm-ok

# Should output: "INFO: /dev/kvm exists" and "KVM acceleration can be used"
```

#### Optimize Storage

Use SSD storage for better I/O performance:

```bash
# Create SSD-backed storage pool
sudo mkdir -p /var/lib/libvirt/ssd-pool
sudo chown libvirt:libvirt /var/lib/libvirt/ssd-pool

# Create pool configuration
cat > ssd-pool.xml <<EOF
<pool type='dir'>
  <name>ssd-pool</name>
  <target>
    <path>/var/lib/libvirt/ssd-pool</path>
  </target>
</pool>
EOF

virsh pool-define ssd-pool.xml
virsh pool-start ssd-pool
virsh pool-autostart ssd-pool
```

#### Network Optimization

For better network performance, consider using a bridge network:

```bash
# Create bridge interface (requires root)
sudo ip link add name br0 type bridge
sudo ip link set br0 up
sudo ip addr add 192.168.100.1/24 dev br0
```

## Security Considerations

### Isolation

- Libvirt VMs are isolated at the kernel level
- Use dedicated networks for production testing
- Implement proper firewall rules

### Resource Limits

```bash
# Set resource limits for libvirt
# Edit /etc/libvirt/libvirtd.conf
max_clients = 20
max_workers = 20
max_requests = 20
max_client_requests = 5
```

### Access Control

```bash
# Restrict libvirt access to specific users
# Edit /etc/libvirt/libvirtd.conf
unix_sock_group = "libvirt"
unix_sock_ro_perms = "0777"
unix_sock_rw_perms = "0770"
```

## Migration to Cloud

Libvirt deployments are ideal for:

1. **Development**: Test configurations locally before cloud deployment
2. **CI/CD**: Automated testing without cloud costs
3. **Proof of Concept**: Validate setups before production deployment

To migrate from libvirt to cloud:

1. Export configuration from libvirt deployment
2. Initialize cloud deployment with same parameters
3. Deploy to cloud provider
4. Migrate data if needed

## Support

For issues with libvirt setup:

1. Check libvirt documentation: https://libvirt.org/
2. Review KVM documentation: https://www.linux-kvm.org/
3. Consult your Linux distribution documentation
4. Check Exasol Deployer issues: https://github.com/sst/exasol-deployer/issues

---

**Note**: This setup is intended for development and testing. For production deployments, use cloud providers with proper infrastructure management.
