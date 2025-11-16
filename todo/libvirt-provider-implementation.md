# Libvirt Provider Support Implementation Plan

## Overview
Add local libvirt/KVM support to enable on-premises testing before cloud deployment. This follows the existing multi-cloud architecture pattern.

## Current Architecture Analysis ✅

- **Multi-cloud framework** with provider-specific terraform templates
- **Common shared infrastructure**: SSH keys, cloud-init, Ansible orchestration
- **Provider detection** via `SUPPORTED_PROVIDERS` array in cmd_init.sh
- **Standard workflow**: init → deploy → status → destroy
- **Cloud-agnostic Ansible** playbooks that work across providers

## Implementation Phases

### Phase 1: Core Terraform Infrastructure (High Priority)

#### 1.1 Create libvirt terraform templates
- `templates/terraform-libvirt/main.tf` - VM provisioning with KVM
- `templates/terraform-libvirt/variables.tf` - libvirt-specific variables  
- `templates/terraform-libvirt/outputs.tf` - output definitions

**Key libvirt resources:**
- `libvirt_domain` for VM instances
- `libvirt_volume` for disk management  
- `libvirt_network` for network configuration
- Ubuntu cloud image support with cloud-init

**Variables needed:**
- `libvirt_memory_gb` (default: 4GB)
- `libvirt_vcpus` (default: 2)
- `libvirt_network_bridge` (default: "virbr0")
- `libvirt_disk_pool` (default: "default")

#### 1.2 Provider configuration
- Terraform libvirt provider setup
- KVM connection configuration
- Network bridge setup support

### Phase 2: Command Integration (High Priority)

#### 2.1 Update cmd_init.sh
```bash
# Add libvirt to SUPPORTED_PROVIDERS array
[libvirt]="Local libvirt/KVM deployment"

# Add libvirt-specific flags
--libvirt-memory <gb>       Memory per VM in GB (default: 4)
--libvirt-vcpus <n>        vCPUs per VM (default: 2)  
--libvirt-network <bridge> Network bridge (default: virbr0)
--libvirt-pool <name>      Storage pool name (default: default)
```

#### 2.2 Variable generation
- Update `write_provider_variables()` function
- Add libvirt case with new variables
- Ensure proper terraform.tfvars generation

#### 2.3 Validation and defaults
- Set appropriate defaults for local testing
- Validate libvirt connectivity during init
- Check KVM availability and permissions

### Phase 3: Ansible & Network Adjustments (Medium Priority)

#### 3.1 Ansible compatibility
- Verify existing `setup-exasol-cluster.yml` works with libvirt VMs
- Adjust for local networking (no public IPs)
- Ensure proper hostname resolution on bridge network

#### 3.2 Network configuration
- Private IP assignment via DHCP
- Host file management for inter-node communication
- SSH access via local network bridge

#### 3.3 Cloud-init adjustments
- Modify cloud-init script for libvirt environment
- Ensure proper user creation and SSH setup
- Handle local metadata vs cloud provider metadata

### Phase 4: Testing Infrastructure (Medium Priority)

#### 4.1 Unit tests
- `tests/test_libvirt_template.sh` - validate terraform syntax
- `tests/test_libvirt_variables.sh` - test variable validation
- `tests/test_libvirt_integration.sh` - basic connectivity tests

#### 4.2 E2E tests  
- `tests/e2e/configs/libvirt-basic.json` - full deployment workflow via e2e framework
- Integration with existing e2e framework
- Cleanup verification tests

#### 4.3 Test environment setup
- Mock libvirt environment for CI/CD
- Test container with KVM emulation
- Automated cleanup between test runs

### Phase 5: Documentation & UX (Medium Priority)

#### 5.1 Setup documentation
- `CLOUD_SETUP_LIBVIRT.md` with complete setup instructions
- KVM installation guide for Ubuntu/Debian/CentOS
- Network bridge configuration steps
- Permission requirements (libvirt, KVM groups)

#### 5.2 User experience
- Update main README.md to include libvirt
- Add libvirt examples to help output
- Integration testing instructions
- Troubleshooting guide for common issues

#### 5.3 Integration documentation
- "Test locally, deploy to cloud" workflow guide
- Performance comparison notes
- Migration path from libvirt to cloud providers

## Technical Architecture

### Terraform Provider Structure
```hcl
# libvirt provider configuration
provider "libvirt" {
  uri = "qemu:///system"
}

# VM resources following existing pattern
resource "libvirt_domain" "exasol_node" {
  count = var.node_count
  name  = "n${count.index + 11}"
  # ... configuration
}
```

### Network Architecture
- **Default**: virbr0 (NAT network)
- **Alternative**: bridge configuration for external access
- **Private IPs**: 192.168.122.x range
- **DNS**: Local hosts file + mDNS support

### Disk Management  
- **Root volume**: Ubuntu cloud image (20-50GB)
- **Data volumes**: Following existing pattern (/dev/exadata_*)
- **Storage pool**: Default libvirt pool or custom
- **Format**: qcow2 with copy-on-write

## Integration Points

### Existing Code Changes Required
1. `lib/cmd_init.sh` - Provider support, validation, variables
2. `lib/versions.sh` - Libvirt instance type mapping
3. `templates/terraform-common/common.tf` - Minor adjustments if needed
4. Main `README.md` - Provider documentation

### Backward Compatibility
- All existing cloud providers remain unchanged
- Common infrastructure unchanged  
- No impact on existing deployments
- Optional feature addition only

## Success Criteria

### Functional
- [ ] Full e2e deployment: `exasol init --cloud-provider libvirt`
- [ ] Multi-node cluster deployment (1-4 nodes)
- [ ] Exasol database functional on libvirt VMs
- [ ] Proper cleanup via `exasol destroy`

### Quality  
- [ ] All existing tests still pass
- [ ] New unit tests with 80%+ coverage
- [ ] Documentation complete and tested
- [ ] Shellcheck compliance maintained

### Usability
- [ ] Simple setup for new users
- [ ] Clear error messages and validation
- [ ] Works on standard Ubuntu/KVM setups
- [ ] Reasonable performance for testing

## Timeline Estimate
- **Phase 1**: Terraform templates (2-3 days)
- **Phase 2**: Command integration (2 days)  
- **Phase 3**: Ansible adjustments (1-2 days)
- **Phase 4**: Testing infrastructure (2-3 days)
- **Phase 5**: Documentation (1-2 days)

**Total: ~8-12 days** for complete implementation

## Next Steps
1. Start with Phase 1 - create terraform-libvirt templates
2. Test basic VM provisioning manually
3. Gradually integrate with existing framework
4. Add testing and documentation progressively
