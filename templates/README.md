# Deployment Templates

Infrastructure-as-code templates for deploying Exasol clusters across multiple cloud providers using OpenTofu. The templates are organized to minimize code duplication while maintaining clarity.

## Directory Structure

```
templates/
├── README.md                    # This file
├── terraform-common/            # Shared components across all providers
│   ├── common.tf               # SSH keys, cloud-init script, random ID
│   ├── common-variables.tf     # Standard variables (node_count, owner, etc.)
│   ├── common-outputs.tf       # Helpers for outputs generation
│   └── inventory.tftpl         # Unified Ansible inventory template
├── terraform/                   # AWS-specific templates (default)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── inventory.tftpl
├── terraform-azure/             # Azure-specific templates
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── inventory.tftpl
├── terraform-gcp/               # GCP-specific templates
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── inventory.tftpl
└── ansible/                     # Cloud-agnostic Ansible playbooks
    ├── setup-exasol-cluster.yml
    ├── config.j2
    ├── exasol-data-symlinks.sh.j2
    └── exasol-data-symlinks.service
```

## Common Components (`terraform-common/`)

These files contain **reusable elements** that are identical across all cloud providers:

### `common.tf`
- **SSH Key Generation**: Creates RSA 4096-bit key pair
- **Random ID**: For unique resource naming
- **Cloud-Init Script**: OS-agnostic user provisioning script
  - Creates `exasol` user with sudo privileges
  - Works across all Linux distributions (Ubuntu, Debian, RHEL, etc.)
  - Copies SSH keys from default cloud user

### `common-variables.tf`
Standard variables used by all providers:
- `instance_architecture` - x86_64 or arm64
- `node_count` - Number of cluster nodes
- `allowed_cidr` - IP range for access
- `root_volume_size` - OS disk size
- `data_volume_size` - Data disk size
- `data_volumes_per_node` - Number of data disks per node
- `owner` - Resource owner tag/label
- `enable_spot_instances` - Cost optimization flag
- `instance_type` - VM/instance type (provider-specific value)

### `common-outputs.tf`
Helper outputs used by all providers:
- `ssh_key_path` - Path to generated private key
- `ssh_config_path` - Path to SSH config file
- `inventory_path` - Path to Ansible inventory

### `inventory.tftpl`
Unified Ansible inventory template that works with all providers.
Expects a `nodes` list with `public_ip`, `private_ip`, and `volume_ids`.

## Cloud-Specific Templates

Each cloud provider has its own directory with provider-specific resources:

### AWS (`terraform/`)
- **Networking**: VPC, Subnet, Security Groups, Internet Gateway
- **Compute**: EC2 instances with `user_data` for cloud-init
- **Storage**: EBS volumes (gp3)
- **Spot Instances**: Via `instance_market_options`
- **AZ Selection**: Automatic selection based on instance type availability

### Azure (`terraform-azure/`)
- **Networking**: Virtual Network, Subnet, NSG
- **Compute**: Linux VMs with `custom_data` for cloud-init
- **Storage**: Managed Disks (Premium_LRS)
- **Spot Instances**: Azure Spot VMs with priority/eviction policy
- **Images**: Ubuntu 22.04 LTS (Canonical)

### GCP (`terraform-gcp/`)
- **Networking**: VPC Network, Subnet, Firewall Rules
- **Compute**: Compute Instances with `startup-script` for cloud-init
- **Storage**: Persistent Disks (pd-ssd)
- **Spot Instances**: Preemptible VMs
- **Images**: Ubuntu 22.04 LTS from ubuntu-os-cloud

## How Templates Are Used

1. **Init Time**: When running `exasol init --cloud-provider <provider>`, the system:
   - Copies `terraform-common/` to `.templates/terraform-common/`
   - Copies `terraform-<provider>/` to `.templates/`
   - Copies `ansible/` to `.templates/`
   - Creates symlinks in deployment directory

2. **Template Structure**: Provider-specific templates can reference common components:
   ```hcl
   # In provider-specific main.tf
   locals {
     # Use cloud-init from common
     cloud_init_script = file("${path.module}/.templates/terraform-common/common.tf")
     # Or inline the same script
   }
   ```

3. **Inventory Generation**: All providers use the common inventory template format:
   ```terraform
   resource "local_file" "ansible_inventory" {
     content = templatefile("${path.module}/.templates/terraform-common/inventory.tftpl", {
       nodes = local.nodes_data  # Provider-specific format conversion
       ssh_key = local_file.exasol_private_key_pem.filename
     })
   }
   ```

## Adding a New Cloud Provider

To add support for a new provider (e.g., Hetzner):

1. **Create directory**: `templates/terraform-hetzner/`

2. **Copy structure from existing provider** (e.g., AWS or Azure)

3. **Modify provider-specific parts**:
   - Provider configuration block
   - Network resources (VPC/VNet equivalent)
   - Firewall/Security rules
   - Compute instance resources
   - Storage/disk resources

4. **Keep common elements**:
   - Use the same cloud-init script (inline or reference)
   - Use the same SSH key generation
   - Use the same variable names from `common-variables.tf`
   - Convert node data to common format for inventory template

5. **Test the provider**:
   ```bash
   ./exasol init --cloud-provider hetzner --deployment-dir ./test-hetzner
   cd ./test-hetzner
   tofu init
   tofu plan
   ```

## Cloud-Init Injection Methods

Each provider uses a different method to inject cloud-init, but the script content is identical:

| Provider | Method | Encoding |
|----------|--------|----------|
| **AWS** | `user_data` attribute | Plain text or base64 |
| **Azure** | `custom_data` attribute | Auto base64-encoded |
| **GCP** | `metadata.startup-script` | Plain text |
| **DigitalOcean** | `user_data` attribute | Plain text |
| **Hetzner** | `user_data` attribute | Plain text |
| **Libvirt** | `libvirt_cloudinit_disk.user_data` | Plain text |

## Benefits of This Structure

✅ **Minimal Duplication**: Common code is in one place
✅ **Easy Maintenance**: Fix once, applies everywhere
✅ **Clear Separation**: Cloud-specific vs. shared logic
✅ **Easy Testing**: Test common components independently
✅ **Simple Addition**: Adding new providers is straightforward
✅ **Readable**: Each provider template is self-contained and clear

## Best Practices

1. **Don't modify common files** for provider-specific needs
2. **Keep cloud-init script identical** across all providers
3. **Use consistent node data format** for inventory generation
4. **Follow naming conventions**: n11, n12, etc. for all providers
5. **Document provider-specific quirks** in template comments
