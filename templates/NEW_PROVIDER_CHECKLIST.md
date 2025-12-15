# New Cloud Provider Integration Checklist

This checklist ensures complete integration when adding a new cloud provider to the Exasol deployer.

## 1. Terraform Templates

### Core Files (Required)
- [ ] `templates/terraform-<provider>/main.tf` - Main provider resources
- [ ] `templates/terraform-<provider>/variables.tf` - Provider-specific variables  
- [ ] `templates/terraform-<provider>/outputs.tf` - Output definitions
- [ ] `templates/terraform-<provider>/cloud-init-<provider>.tftpl` - Cloud-init template

### Key Implementation Requirements

#### Firewall/Security Groups
- [ ] Use `local.exasol_firewall_ports` from common-firewall.tf
- [ ] Include all required ports: 22, 443, 8563, 20002, 20003, 2581
- [ ] Example: `for_each = local.exasol_firewall_ports`

#### Power Control
- [ ] Implement proper start/stop without destroying instances
- [ ] Use provider-specific power state management (not `count = 0`)
- [ ] Examples:
  - AWS: `aws_ec2_instance_state` resource
  - Azure: `azapi_resource_action` with powerOff/start
  - GCP: `desired_status = "TERMINATED"/"RUNNING"`
  - Exoscale: `state = "stopped"/"running"`

#### Cloud-Init Script Path
- [ ] Use `/tmp/bootstrap-exasol-cluster.sh` (not `/var/run` - noexec issue)
- [ ] Template: `path: /tmp/bootstrap-exasol-cluster.sh`

#### Volume Management
- [ ] Define `node_volumes` mapping for Ansible inventory
- [ ] Use provider-specific volume identifiers (IDs, names, etc.)

## 2. Ansible Integration

### Disk Symlink Script
- [ ] Create `templates/ansible/exasol-data-symlinks-<provider>.sh.j2`
- [ ] Implement three functions:
  - `provider_init_discovery()` - Initialize device discovery
  - `provider_find_device(vol_id, volume_index)` - Find device for volume
  - `provider_log_available_devices()` - Debug logging
- [ ] Add provider to supported list in `templates/ansible/exasol-data-symlinks.sh.j2`

### Provider-Specific Device Patterns
Document the device discovery pattern for your provider:
- AWS: `/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_*`
- Azure: `/dev/disk/azure/data/by-lun/*`
- GCP: Device index mapping
- Hetzner: `/dev/disk/by-id/scsi-0HC_Volume_*`
- DigitalOcean: `/dev/disk/by-id/scsi-0DO_Volume_*`
- Exoscale: `/dev/disk/by-id/virtio-*` (17-char UUID prefix)
- libvirt: Device index mapping

## 3. Command Integration

### Power Control Commands
- [ ] Add provider to supported list in `lib/cmd_start.sh` and `lib/cmd_stop.sh`
- [ ] Add Terraform target to power control commands:
  ```bash
  -target="<provider_resource>.<resource_name>"
  ```
- [ ] Example: `-target="exoscale_compute_instance.exasol_nodes"`

### Provider Detection
- [ ] Add provider to case statements in command files where needed
- [ ] Ensure provider is recognized in validation logic

## 4. Configuration Files

### Instance Types
- [ ] Add provider-specific instance types to `instance-types.conf`
- [ ] Format: `<provider>:<instance_type>:<vcpus>:<memory_gb>:<architecture>`
- [ ] **Verify architecture support**: Ensure ARM64 instance types actually exist
- [ ] Use different instance families for x86_64 vs arm64 (if supported)
- [ ] If ARM64 not supported, comment it out like DigitalOcean:
  ```ini
  [provider]
  x86_64=instance-type-name
  # arm64 not supported by Provider
  ```

#### Architecture Support Verification
- [ ] **Research provider documentation** for ARM64/Graviton support
- [ ] **Check instance naming patterns**:
  - AWS: `t3a.medium` (x86) vs `t4g.medium` (ARM)
  - Azure: `Standard_D2s_v3` (x86) vs `Standard_D2pls_v5` (ARM)
  - GCP: `e2-medium` (x86) vs `t2a-standard-1` (ARM)
  - Hetzner: `cpx32` (x86) vs `cax22` (ARM)
- [ ] **Don't assume ARM64 support** - many providers don't offer it
- [ ] **Test with provider CLI/API** if available (e.g., `exo compute instance-type list`)

### Permissions (Optional)
- [ ] Create `lib/permissions/<provider>.json` if needed
- [ ] Document required cloud permissions for deployment

## 5. Testing

### Unit Tests
- [ ] Create `tests/test_template_validation_<provider>.sh`
- [ ] Test template validation and variable substitution

### E2E Tests
- [ ] Add provider config to `tests/e2e/configs/<provider>.json`
- [ ] Create test scenarios in `tests/e2e/configs/sut/<provider>-*.json`

#### E2E Test Scenarios by Provider Type

**Providers with Native Power Control (AWS, Azure, GCP, Exoscale):**
- [ ] `<provider>-1n.json` - Single node basic deployment
- [ ] `<provider>-4n.json` - Multi-node cluster (if supported)
- [ ] `<provider>-*-spot.json` - Spot/preemptible instances (if supported)
- [ ] **Required test workflows**:
  - `workflow/simple.json` - Basic deploy → destroy
  - `workflow/basic.json` - **Power control cycle**: deploy → stop → start → destroy
  - `workflow/node-reboot.json` - **Reboot resilience**: deploy → reboot nodes → validate recovery → destroy
- [ ] **E2E config must include all three workflows**:
  ```json
  "test_suites": [
    {"sut": "sut/<provider>-1n.json", "workflow": "workflow/simple.json"},
    {"sut": "sut/<provider>-4n.json", "workflow": "workflow/basic.json"},
    {"sut": "sut/<provider>-4n.json", "workflow": "workflow/node-reboot.json"}
  ]
  ```

**Providers with Manual Power Control (Hetzner, DigitalOcean, libvirt):**
- [ ] `<provider>-1n.json` - Single node basic deployment  
- [ ] `<provider>-4n.json` - Multi-node cluster (if supported)
- [ ] **Required test workflows**:
  - `workflow/simple.json` - Basic deploy → destroy
  - `workflow/node-reboot.json` - **Reboot resilience** (mandatory for all providers)
- [ ] **Manual power testing**: deploy → stop (with manual power-on instructions) → destroy
- [ ] Multicast overlay testing (usually required for these providers)

#### Example Test Configurations

**Native Power Control Provider:**
```json
{
  "description": "<Provider> 4-node cluster with power control testing",
  "provider": "<provider>",
  "parameters": {
    "cluster_size": 4,
    "instance_type": "<provider_instance_type>",
    "data_volumes_per_node": 2,
    "data_volume_size": 20,
    "root_volume_size": 50
  }
}
```

**Manual Power Control Provider:**
```json
{
  "description": "<Provider> single node with multicast overlay",
  "provider": "<provider>",
  "parameters": {
    "cluster_size": 1,
    "instance_type": "<provider_instance_type>",
    "data_volumes_per_node": 1,
    "data_volume_size": 20,
    "root_volume_size": 50,
    "enable_multicast_overlay": true
  }
}
```

### Manual Testing Checklist
- [ ] `init` - Creates deployment directory with correct templates
- [ ] `deploy` - Successfully provisions infrastructure and configures cluster
- [ ] `stop` - Powers off instances without destroying them
- [ ] `start` - Powers on instances and waits for database ready
- [ ] `health` - All health checks pass
- [ ] `destroy` - Cleanly removes all resources

## 6. Documentation

### Cloud Setup Guide
- [ ] Create `clouds/CLOUD_SETUP_<PROVIDER>.md`
- [ ] Include:
  - Prerequisites and account setup
  - API credentials configuration
  - Required permissions
  - Region/zone selection
  - Example init commands

### Update Main Documentation
- [ ] Add provider to README.md feature list
- [ ] Add provider badge to supported providers badge
- [ ] Update cloud provider setup links
- [ ] Add provider-specific examples
- [ ] Update provider count in feature descriptions

#### README.md Updates Required:

**1. Provider Badge (top of README)**
```markdown
[![Cloud Providers](https://img.shields.io/badge/Cloud-AWS%20%7C%20Azure%20%7C%20GCP%20%7C%20Hetzner%20%7C%20DigitalOcean%20%7C%20Exoscale%20%7C%20<PROVIDER>%20%7C%20libvirt-orange.svg)](#cloud-provider-setup)
```

**2. Features Section - Multi-Cloud Support**
```markdown
- **Multi-Cloud Support**:
  - [AWS] Amazon Web Services
  - [AZR] Microsoft Azure  
  - [GCP] Google Cloud Platform
  - [HTZ] Hetzner Cloud
  - [DO] DigitalOcean
  - [EXO] Exoscale
  - [<CODE>] <Provider Name>
  - [LAB] libvirt/KVM (local or remote over SSH for Linux hosts)
```

**3. Cloud Provider Setup Links**
```markdown
- **[<Provider>](clouds/CLOUD_SETUP_<PROVIDER>.md)** - Brief description
```

**4. Quick Start Examples**
Add provider-specific init example in the "Initialize Deployment" section

**5. Update Provider Count**
Update any mentions of "X providers" or "multiple cloud providers" to reflect the new count

## 7. Common Issues to Avoid

### Template Issues
- [ ] ❌ Don't use `/var/run` for scripts (noexec mount)
- [ ] ❌ Don't use `count = 0` for power control (destroys instances)
- [ ] ❌ Don't hardcode firewall ports (use common configuration)

### Missing Integration Points
- [ ] ❌ Forgetting to add provider to power control target lists
- [ ] ❌ Missing symlink script causes disk setup failures
- [ ] ❌ Not using common firewall ports (missing COS port 20002)

### Testing Gaps
- [ ] ❌ Not testing stop/start cycle
- [ ] ❌ Not verifying disk symlinks are created correctly
- [ ] ❌ Not testing SSH key authentication

## 8. Optional: Utility Scripts Integration

### Resource Management Scripts (Optional)
- [ ] Add provider support to `scripts/generate-limits-report.sh`
- [ ] Add provider support to `scripts/cleanup-resources.sh`
- [ ] **Requires native cloud CLI tools** (e.g., `aws`, `az`, `gcloud`, `hcloud`, `doctl`, `exo`, `virsh`)
- [ ] Add provider to supported list in script help/validation
- [ ] Implement provider-specific resource collection/cleanup functions

#### Implementation Requirements:
- [ ] **generate-limits-report.sh**: Add `collect_<provider>_data()` function
- [ ] **cleanup-resources.sh**: Add `cleanup_<provider>()` function  
- [ ] **CLI tool check**: Use `check_cli_tool "<cli>" "Install: <url>"` pattern
- [ ] **Resource filtering**: Support tag/label and prefix filtering
- [ ] **Error handling**: Graceful fallback when CLI not installed

**Note**: These scripts are not included in packaged releases and require cloud provider CLI tools to be installed separately. See [Scripts README](scripts/README.md) for prerequisites.

After implementation, verify with these commands:

```bash
# Template validation
./tests/test_template_validation_<provider>.sh

# Basic functionality
./exasol init --cloud-provider <provider> --deployment-dir ./test-<provider>
./exasol deploy --deployment-dir ./test-<provider>
./exasol health --deployment-dir ./test-<provider>
./exasol stop --deployment-dir ./test-<provider>
./exasol start --deployment-dir ./test-<provider>
./exasol destroy --deployment-dir ./test-<provider> --auto-approve
```

## 9. Validation Commands

After implementation, verify with these commands:

```bash
# Template validation
./tests/test_template_validation_<provider>.sh

# Basic functionality
./exasol init --cloud-provider <provider> --deployment-dir ./test-<provider>
./exasol deploy --deployment-dir ./test-<provider>
./exasol health --deployment-dir ./test-<provider>
./exasol stop --deployment-dir ./test-<provider>
./exasol start --deployment-dir ./test-<provider>
./exasol destroy --deployment-dir ./test-<provider> --auto-approve
```

## 10. Code Review Checklist

---

**Note**: This checklist is based on lessons learned from existing provider implementations and common integration issues. Always test thoroughly before considering a provider integration complete.
