# Todo: Add libvirt/KVM Provider Support

## Summary
Enable local testing of Exasol deployments using libvirt/KVM virtualization before moving to cloud providers. This provides a cost-effective local development and testing environment.

**Implementation Plan**: See `libvirt-provider-implementation.md` for detailed architecture and phases.

## Implementation Tasks

### 🏗️ Core Infrastructure
- [ ] Create terraform-libvirt template (main.tf, variables.tf, outputs.tf) for VM deployment
- [ ] Update common.sh to support libvirt provider detection and configuration  
- [ ] Add libvirt-specific options to init command (memory, cpu, disk size, network config)
- [ ] Update ansible playbook setup-exasol-cluster.yml to support libvirt VMs

### 🧪 Testing & Quality
- [ ] Create unit tests for libvirt template and configuration
- [ ] Create e2e tests for libvirt deployment workflow
- [ ] Libvirt integration tests with existing e2e framework

### 📚 Documentation  
- [ ] Update README.md with libvirt setup instructions and requirements
- [ ] Create CLOUD_SETUP_LIBVIRT.md documentation
- [ ] Update main README.md to include libvirt provider option

## Implementation Details

### Provider Variables
```bash
# libvirt-specific command line options
--libvirt-memory <gb>       Memory per VM in GB (default: 4)
--libvirt-vcpus <n>        vCPUs per VM (default: 2)  
--libvirt-network <bridge> Network bridge (default: virbr0)
--libvirt-pool <name>      Storage pool name (default: default)
```

### Architecture Integration
- Follows existing multi-cloud provider pattern
- Reuses common infrastructure (SSH keys, cloud-init, Ansible)
- Minimal impact to existing codebase
- Backward compatible with all current providers

### Benefits
1. **Cost-effective testing**: No cloud provider costs during development
2. **Faster iteration**: Local VM deployment is faster than cloud provisioning
3. **Offline development**: Can work without internet connectivity
4. **Infrastructure validation**: Test terraform/ansible changes locally

### Success Criteria
- Complete e2e deployment with `exasol init --cloud-provider libvirt`
- Multi-node cluster support (1-4 nodes)
- Proper cleanup via `exasol destroy`
- All existing tests still pass

**Timeline Estimate**: 8-12 days
**Priority**: High (enables local testing infrastructure)

---

*Created: $(date)*
*Status: Planning phase complete*