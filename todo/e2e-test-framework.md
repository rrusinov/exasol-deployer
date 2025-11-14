# Create End-to-End Test Framework

Develop a comprehensive e2e testing framework for Exasol deployments that can define test parameters, generate test plans, execute tests in parallel, and validate deployment outcomes across different cloud providers and configurations.

## Recommended Implementation Language: Python

**Rationale:**
- **JSON/YAML Processing**: Native support for configuration files
- **Parallel Execution**: Excellent `concurrent.futures` and `asyncio` libraries
- **Shell Integration**: `subprocess` module for calling exasol CLI commands
- **Ecosystem**: Rich libraries for testing, logging, and reporting
- **Maintainability**: Cleaner code than complex bash for this scope
- **CI/CD Integration**: Easy to containerize and run in various environments

**Dependencies:** Standard library only (no external packages required)

## Framework Requirements

### Core Components
1. **Test Parameter Definition System**: JSON/YAML-based configuration for defining test parameters and their combinations
2. **Test Plan Generator**: Tool to generate pairwise test combinations for efficient coverage
3. **Parallel Execution Engine**: Framework to run multiple test deployments concurrently
4. **Result Validation System**: Automated validation of deployment success and configuration correctness
5. **Cleanup Management**: Automatic cleanup of test resources and failed deployments

### Test Parameter Structure
```json
{
  "test_suites": {
    "aws_basic": {
      "provider": "aws",
      "parameters": {
        "cluster_size": [1, 2],
        "instance_type": ["m6idn.large", "m6idn.xlarge"],
        "data_volumes_per_node": [1, 3],
        "data_volume_size": [100, 200],
        "root_volume_size": [50, 100]
      },
      "combinations": "pairwise"
    }
  }
}
```

### Combination Strategies
- **Pairwise (2-wise)**: Generates combinations covering all pairs of parameter values. For 5 parameters with 2 values each, produces 8 test cases.
- **Each-Choice (1-wise)**: Generates the full Cartesian product, ensuring every parameter value appears in at least one test. For 5 parameters with 2 values each, produces 32 test cases.
- **Full**: Same as Each-Choice, generates all possible combinations.

### Framework Features
1. **Dry Run Mode**: Generate pairwise test plans without executing deployments
2. **Parallel Execution**: Run multiple pairwise test combinations simultaneously with resource limits
3. **Dependency Management**: Handle test dependencies and resource conflicts
4. **Result Aggregation**: Collect and analyze test results across all pairwise combinations
5. **Failure Handling**: Automatic cleanup and retry logic for failed tests

## Implementation Phases

### Phase 1: Framework Foundation
1. **Directory Structure**: Create `tests/e2e/` directory with Python framework components
2. **Configuration System**: Implement parameter definition and validation using Python's json/yaml support
3. **Test Plan Generator**: Create pairwise test generator to produce efficient test combinations

### Phase 2: Execution Engine
1. **Parallel Runner**: Implement concurrent test execution using `concurrent.futures.ThreadPoolExecutor`
2. **Deployment Management**: Handle deployment lifecycle (init, deploy, validate, cleanup) via subprocess calls
3. **Monitoring System**: Track test progress and resource usage with logging

### Phase 3: Validation & Reporting
1. **Validation Framework**: Implement checks for deployment success and configuration using file parsing
2. **Result Collection**: Gather metrics, logs, and validation results in structured format
3. **Reporting System**: Generate JSON/HTML test reports and failure analysis

### Phase 4: Integration & CI/CD
1. **CI Integration**: Integrate with GitHub Actions for automated e2e testing (Python available in all runners)
2. **Resource Management**: Implement cloud resource quotas and cost controls
3. **Notification System**: Alert on test failures and performance issues

## Success Criteria

- Framework can define and execute pairwise parameter combinations using Python
- Pairwise generation reduces test cases while maintaining coverage of parameter interactions
- Parallel execution with proper resource management via concurrent.futures
- Comprehensive validation of deployment outcomes through subprocess integration
- Automatic cleanup and failure recovery with proper error handling
- Integration with CI/CD pipeline (Python pre-installed in most environments)
- Clear reporting and failure analysis with structured output formats

## Usage Examples

```bash
# Generate pairwise test plan (dry run)
python tests/e2e_framework.py plan --config e2e/configs/aws-basic.json --dry-run

# Execute pairwise tests in parallel
python tests/e2e_framework.py run --config e2e/configs/aws-basic.json --parallel 3

# Run specific pairwise test combination
python tests/e2e_framework.py run --config e2e/configs/aws-basic.json --filter "cluster_size=2,instance_type=m6idn.xlarge"
```

## Alternative Language Considerations

### Bash (Alternative)
- **Pros**: Native integration, no dependencies, consistent with main codebase
- **Cons**: Complex parallel execution, JSON processing cumbersome, harder maintenance
- **Recommendation**: Use for simple wrapper scripts, not full framework

### Go (Alternative)
- **Pros**: Fast compilation, single binary, good concurrency
- **Cons**: Different language paradigm, compilation step, less shell integration
- **Recommendation**: Consider if performance becomes critical

**Final Recommendation: Python with standard library only, using pairwise combinatorial testing**

---

## Current Implementation Analysis (Post-Implementation Review)

### ✅ **Completed Features**
- Framework foundation with Python standard library
- Test parameter definition via JSON configuration
- Pairwise (2-wise), each-choice (1-wise), and full combination strategies
- Parallel execution engine using `concurrent.futures`
- Basic validation (file existence, inventory parsing)
- Automatic cleanup and resource management
- JSON-based result reporting

### ❌ **Critical Missing Features for Real E2E Testing**

#### **Live System Validation Gaps**
The current framework only validates local files but **never inspects the live deployed environment**. This defeats the purpose of end-to-end testing.

**Missing SSH-based validations:**
1. **Device Validation**: No verification of `/dev/exasol_data_*` symlinks
2. **Volume Validation**: No EBS volume attachment/formatting checks
3. **Service Validation**: No verification of `exasol-data-symlinks` service status
4. **Database Validation**: No Exasol DB installation/running checks
5. **Configuration Validation**: No verification of `/home/exasol/exasol-release/config`
6. **Network Validation**: No cluster connectivity testing

#### **Emergency Response & Infrastructure Leak Prevention**
- **No timeout handling** for stuck deployments
- **No resource quota monitoring** to prevent cost overruns
- **No emergency cleanup procedures** for failed tests
- **No cloud resource tracking** to ensure complete destruction

#### **Comprehensive Parameter Validation Matrix**

| Parameter | Current Validation | Missing Live Validation | SSH Check Command |
|----------|-------------------|------------------------|-------------------|
| `--cluster-size` | Inventory file count | Actual running nodes | `nproc` + cluster verification |
| `--instance-type` | Terraform state | Hardware specs | `lscpu`, `free -h` |
| `--data-volume-size` | Terraform config | Actual disk sizes | `lsblk`, `df -h` |
| `--data-volumes-per-node` | Config parsing | Physical volumes | `ls /dev/exasol_data_*` |
| `--root-volume-size` | Terraform config | Root partition size | `df -h /` |
| `--db-version` | Config file | Installed DB version | `/opt/exasol/EXASolution-version` |
| `--db-password` | Config file | Database access | `exasol db client` |
| `--adminui-password` | Config file | UI accessibility | HTTP check to port 8888 |
| `--allowed-cidr` | Security group rules | Actual firewall rules | `iptables -L` |
| `--owner` | Resource tags | Tag presence on all resources | AWS CLI describe-tags |

#### **Template & Ansible Integration Analysis**

**Access Methods Available:**
1. **SSH Key**: Generated in `templates/terraform-common/common.tf` - available for framework use
2. **Inventory File**: Generated at `deployment-dir/inventory.ini` - contains all node IPs
3. **Ansible Playbook**: `templates/ansible/setup-exasol-cluster.yml` - shows validation patterns
4. **Configuration File**: `/home/exasol/exasol-release/config` - contains all runtime parameters

**Validation Patterns from Ansible:**
- Symlink discovery: `ls -1 /dev/exasol_data_*` (line 206)
- Service status: Systemd service checks for `exasol-data-symlinks`
- File existence: Config file and artifact validation
- User creation: SSH key and user `exasol` validation

---

## **Phase 5: Live System Validation Enhancement**

### **Required Implementation Steps**

#### **5.1 SSH Validation Framework**
```python
class SSHValidator:
    def __init__(self, inventory_file, ssh_key_path):
        self.inventory = self._parse_inventory(inventory_file)
        self.ssh_key = ssh_key_path
        
    def validate_symlinks(self):
        """Check /dev/exasol_data_* symlinks on all nodes"""
        
    def validate_volumes(self):
        """Verify EBS volume attachment and sizes"""
        
    def validate_services(self):
        """Check exasol-data-symlinks service status"""
        
    def validate_database(self):
        """Verify Exasol DB installation and version"""
```

#### **5.2 Emergency Response System**
```python
class EmergencyHandler:
    def __init__(self, deployment_dir, timeout_minutes=30):
        self.timeout = timeout_minutes
        self.deployment_dir = deployment_dir
        
    def monitor_deployment(self):
        """Track deployment progress and force cleanup on timeout"""
        
    def emergency_cleanup(self):
        """Force destroy all resources and verify deletion"""
        
    def check_resource_leaks(self):
        """Verify no orphaned resources remain"""
```

#### **5.3 Enhanced Reporting**
- **Live System Metrics**: CPU, memory, disk usage from all nodes
- **Network Connectivity**: Inter-node communication tests
- **Database Health**: Connection tests and status queries
- **Resource Inventory**: Complete list of all cloud resources created

#### **5.4 Cloud Resource Tracking**
```python
class ResourceTracker:
    def track_aws_resources(self, deployment_id):
        """Monitor all AWS resources created"""
        
    def verify_cleanup(self, deployment_id):
        """Ensure no resources remain after cleanup"""
        
    def cost_monitoring(self, deployment_id):
        """Track estimated costs during testing"""
```

---

## **Next Steps & Implementation Priority**

### **High Priority (Critical for E2E Testing)**
1. **Implement SSH validation framework** - Use existing SSH keys and inventory
2. **Add device symlink validation** - Check `/dev/exasol_data_*` on all nodes
3. **Add emergency cleanup procedures** - Prevent infrastructure leaks
4. **Enhance validation with live system checks** - Replace file-only validation

### **Medium Priority (Enhanced Coverage)**
5. **Add database connectivity validation** - Verify Exasol DB is running
6. **Implement resource tracking** - Monitor cloud resource creation/deletion
7. **Add network connectivity tests** - Verify inter-node communication
8. **Enhance reporting with live metrics** - Include system performance data

### **Low Priority (Operational Improvements)**
9. **Add cost monitoring and quotas** - Prevent unexpected charges
10. **Implement retry logic** - Handle transient failures gracefully
11. **Add filter functionality** - Run specific test combinations
12. **Create HTML reports** - Better visualization of test results

---

## **Integration Strategy**

### **Leverage Existing Infrastructure**
- **SSH Keys**: Use `tls_private_key.exasol_key` from Terraform
- **Inventory**: Parse generated `inventory.ini` for node IPs
- **Ansible Patterns**: Reuse validation commands from setup playbook
- **Configuration Files**: Parse `/home/exasol/exasol-release/config` for runtime validation

### **Emergency Response Implementation**
- **Timeout Monitoring**: Track deployment progress with configurable timeouts
- **Force Cleanup**: Use `exasol destroy --force` for stuck deployments
- **Resource Verification**: Cloud provider APIs to confirm complete deletion
- **Alert System**: Notifications for cleanup failures or resource leaks

### **Reporting Enhancement**
- **Live Metrics Collection**: System stats from all nodes via SSH
- **Validation Results**: Detailed pass/fail for each parameter
- **Resource Inventory**: Complete list with cloud resource IDs
- **Cost Tracking**: Estimated costs per test execution

---

## **Success Criteria Update**

- **Live System Validation**: All parameters verified on actual deployed nodes
- **Emergency Response**: Zero infrastructure leaks with automatic cleanup
- **Complete Coverage**: Every `exasol init` parameter validated in live environment
- **Resource Tracking**: Full audit trail of all cloud resources created/destroyed
- **Comprehensive Reporting**: Detailed validation results with system metrics