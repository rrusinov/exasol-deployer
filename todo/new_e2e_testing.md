# E2E Testing and Validation

## Overview
This document consolidates all end-to-end testing initiatives for the Exasol deployer, including framework implementation, provider coverage expansion, test scenario expansion, and health check testing recommendations.

## E2E Test Framework Implementation

**Status: Partially Implemented** - Core framework exists but critical live system validation is not fully integrated.

Develop a comprehensive e2e testing framework for Exasol deployments that can define test parameters, generate test plans, execute tests in parallel, and validate deployment outcomes across different cloud providers and configurations.

**Current Status**: The framework foundation is implemented with parameter definition, test plan generation, parallel execution, and basic validation. Enhanced components for SSH validation, emergency response, and resource tracking have been created but need full integration.

### Recommended Implementation Language: Python

**Rationale:**
- **JSON/YAML Processing**: Native support for configuration files
- **Parallel Execution**: Excellent `concurrent.futures` and `asyncio` libraries
- **Shell Integration**: `subprocess` module for calling exasol CLI commands
- **Ecosystem**: Rich libraries for testing, logging, and reporting
- **Maintainability**: Cleaner code than complex bash for this scope
- **CI/CD Integration**: Easy to containerize and run in various environments

**Dependencies:** Standard library only (no external packages required)

### Framework Requirements

#### Core Components
1. **Test Parameter Definition System**: JSON/YAML-based configuration for defining test parameters and their combinations ✅
2. **Test Plan Generator**: Tool to generate pairwise test combinations for efficient coverage ✅
3. **Parallel Execution Engine**: Framework to run multiple test deployments concurrently ✅
4. **Result Validation System**: Automated validation of deployment success and configuration correctness ⚠️ (Partially implemented - needs live system validation)
5. **Cleanup Management**: Automatic cleanup of test resources and failed deployments ✅

#### Test Parameter Structure
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

#### Combination Strategies
- **Pairwise (2-wise)**: Generates combinations covering all pairs of parameter values. For 5 parameters with 2 values each, produces 8 test cases.
- **Each-Choice (1-wise)**: Generates the full Cartesian product, ensuring every parameter value appears in at least one test. For 5 parameters with 2 values each, produces 32 test cases.
- **Full**: Same as Each-Choice, generates all possible combinations.

#### Framework Features
1. **Dry Run Mode**: Generate pairwise test plans without executing deployments
2. **Parallel Execution**: Run multiple pairwise test combinations simultaneously with resource limits
3. **Dependency Management**: Handle test dependencies and resource conflicts
4. **Result Aggregation**: Collect and analyze test results across all pairwise combinations
5. **Failure Handling**: Automatic cleanup and retry logic for failed tests

### Implementation Status

#### Phase 1: Framework Foundation ✅ Completed
1. **Directory Structure**: Create `tests/e2e/` directory with Python framework components ✅
2. **Configuration System**: Implement parameter definition and validation using Python's json/yaml support ✅
3. **Test Plan Generator**: Create pairwise test generator to produce efficient test combinations ✅

#### Phase 2: Execution Engine ✅ Completed
1. **Parallel Runner**: Implement concurrent test execution using `concurrent.futures.ThreadPoolExecutor` ✅
2. **Deployment Management**: Handle deployment lifecycle (init, deploy, validate, cleanup) via subprocess calls ✅
3. **Monitoring System**: Track test progress and resource usage with logging ✅

#### Phase 3: Validation & Reporting ⚠️ Partially Completed
1. **Validation Framework**: Implement checks for deployment success and configuration using file parsing ✅
   - **Live System Validation**: SSH-based validation of deployed environments ⚠️ (Partially implemented)
2. **Result Collection**: Gather metrics, logs, and validation results in structured format ✅
3. **Reporting System**: Generate JSON/HTML test reports and failure analysis ⚠️ (JSON only, HTML not implemented)

#### Phase 4: Integration & CI/CD ✅ Framework Exists
1. **CI Integration**: Integrate with GitHub Actions for automated e2e testing (Python available in all runners) ✅
2. **Resource Management**: Implement cloud resource quotas and cost controls ⚠️ (Partially implemented)
3. **Notification System**: Alert on test failures and performance issues ❌ (Not implemented)

#### Phase 5: Live System Validation Enhancement ⚠️ Partially Implemented
Enhanced components exist but need full integration:

1. **SSH Validation Framework** ✅ (Framework exists)
2. **Emergency Response System** ✅ (Framework exists)
3. **Enhanced Reporting** ✅ (Framework exists)
4. **Cloud Resource Tracking** ✅ (Framework exists)

## E2E Tests for All Providers

**Problem**: Currently only AWS has basic E2E tests; other providers (Azure, GCP, Hetzner, DigitalOcean) are untested.

**Solution**: Create comprehensive E2E test configurations for each provider.

### Implementation Steps
- Create provider-specific test configuration files
- Implement provider authentication setup
- Define test parameters for each provider
- Add validation checks for provider-specific resources
- Configure parallel test execution

### Files to Create
- tests/e2e/configs/azure-basic.json
- tests/e2e/configs/gcp-basic.json
- tests/e2e/configs/hetzner-basic.json
- tests/e2e/configs/digitalocean-basic.json

## Expand E2E Test Coverage

**Problem**: Current tests only cover basic configurations with 1-wise strategy; missing advanced scenarios.

**Solution**: Expand test coverage to include spot instances and other configuration options.

### Implementation Steps
- Add spot/preemptible instance tests
- Include different regions/locations
- Test network configurations
- Add custom instance types
- Implement 2-wise combination strategy
- Add failure scenario tests

### Test Scenarios to Add
- Spot instance deployments (AWS, Azure, GCP)
- Different regions/locations testing
- Custom network configurations
- Mixed architecture deployments
- Database version testing
- Configuration edge cases
- Failure recovery scenarios

## E2E Test Recommendations for Health Check Feature

This section provides recommendations for end-to-end testing of the enhanced `exasol health` command in live AWS/Azure/GCP deployments.

### Test Environment Setup

#### Prerequisites
- Active AWS/Azure/GCP account with permissions to create/destroy resources
- Exasol deployer configured and tested
- SSH access to deployed instances
- AWS CLI / Azure CLI / gcloud CLI installed and configured

#### Test Deployment
Create a test deployment using the standard process:
```bash
./exasol init --deployment-dir ./health-test --cloud-provider aws
./exasol deploy --deployment-dir ./health-test
```

### Test Scenarios

#### 1. Basic Health Check (Healthy State)
**Objective**: Verify health check passes on a healthy deployment

#### 2. JSON Output Format
**Objective**: Verify JSON output is properly formatted and contains all data

#### 3. Spontaneous IP Change Detection
**Objective**: Detect when instance IPs change (simulating provider-initiated reboot)

#### 4. Service Failure and Auto-Remediation
**Objective**: Detect failed services and restart them with --try-fix

#### 5. Cloud Metadata Validation (AWS)
**Objective**: Verify cloud provider instance count matches expected

#### 6. Multiple Concurrent Issues
**Objective**: Test detection of multiple simultaneous problems

#### 7. Backup and Rollback
**Objective**: Verify backups are created and can be used for rollback

#### 8. State Management and Locking
**Objective**: Verify health check integrates with state management

#### 9. Progress Tracking
**Objective**: Verify progress events are logged

#### 10. Volume Attachments Check
**Objective**: Verify volume detection works correctly

#### 11. Cluster State Validation
**Objective**: Verify c4 cluster status check works

#### 12. Long-Running Deployment Testing
**Objective**: Test health check on deployment over time

### Test Matrix

| Test Scenario | AWS | Azure | GCP | Exit Code | JSON Output | --update | --try-fix |
|--------------|-----|-------|-----|-----------|-------------|----------|-----------|
| 1. Basic Health | ✓ | ✓ | ✓ | 0 | ✓ | - | - |
| 2. JSON Output | ✓ | ✓ | ✓ | 0 | ✓ | - | - |
| 3. IP Change | ✓ | ✓ | ✓ | 1→0 | ✓ | ✓ | - |
| 4. Service Fail | ✓ | ✓ | ✓ | 1→0/2 | ✓ | - | ✓ |
| 5. Cloud Metadata | ✓ | ⚠️ | ⚠️ | 1 | ✓ | - | - |
| 6. Multi-Issue | ✓ | ✓ | ✓ | 1 | ✓ | ✓ | ✓ |
| 7. Backup | ✓ | ✓ | ✓ | - | - | ✓ | - |
| 8. State/Lock | ✓ | ✓ | ✓ | - | - | - | - |
| 9. Progress | ✓ | ✓ | ✓ | - | - | - | - |
| 10. Volumes | ✓ | ✓ | ✓ | 0/1 | ✓ | - | - |
| 11. Cluster | ✓ | ✓ | ✓ | 0 | ✓ | - | - |
| 12. Long-Running | ✓ | ✓ | ✓ | varies | ✓ | - | - |

### Automated Test Script Template

```bash
#!/usr/bin/env bash
# e2e-health-test.sh - Automated E2E testing for health check

set -euo pipefail

DEPLOYMENT_DIR="./health-e2e-test"
LOG_FILE="health-e2e-results.log"

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"
}

assert_exit_code() {
    local expected=$1
    local actual=$2
    local test_name=$3

    if [[ "$actual" -eq "$expected" ]]; then
        log "✓ PASS: $test_name (exit code $actual)"
        return 0
    else
        log "✗ FAIL: $test_name (expected $expected, got $actual)"
        return 1
    fi
}

# Test 1: Basic Health Check
test_basic_health() {
    log "Running Test 1: Basic Health Check"
    ./exasol health --deployment-dir "$DEPLOYMENT_DIR"
    assert_exit_code 0 $? "Basic health check on healthy deployment"
}

# Test 2: JSON Output
test_json_output() {
    log "Running Test 2: JSON Output"
    ./exasol health --deployment-dir "$DEPLOYMENT_DIR" --output-format json > /tmp/health.json
    jq . /tmp/health.json >/dev/null
    assert_exit_code 0 $? "JSON output valid"
}

# Test 3: Service Failure
test_service_failure() {
    log "Running Test 3: Service Failure and Remediation"

    # Stop service
    ssh -F "$DEPLOYMENT_DIR/ssh_config" n11 sudo systemctl stop c4.service

    # Should detect failure
    ./exasol health --deployment-dir "$DEPLOYMENT_DIR"
    assert_exit_code 1 $? "Health check detects service failure"

    # Should fix with --try-fix
    ./exasol health --deployment-dir "$DEPLOYMENT_DIR" --try-fix
    assert_exit_code 0 $? "Health check repairs service failure"
}

# Run all tests
main() {
    log "Starting E2E Health Check Tests"

    test_basic_health
    test_json_output
    test_service_failure

    log "E2E Health Check Tests Complete"
}

main "$@"
```

## Success Criteria

- Framework can define and execute pairwise parameter combinations using Python ✅
- Pairwise generation reduces test cases while maintaining coverage of parameter interactions ✅
- Parallel execution with proper resource management via concurrent.futures ✅
- Comprehensive validation of deployment outcomes through subprocess integration ⚠️ (Partially completed - needs live system validation)
- Automatic cleanup and failure recovery with proper error handling ✅
- Integration with CI/CD pipeline (Python pre-installed in most environments) ✅
- Clear reporting and failure analysis with structured output formats ✅ (JSON) / ⚠️ (HTML not implemented)

## Usage Examples

```bash
# Generate pairwise test plan (dry run)
python tests/e2e_framework.py plan --config e2e/configs/aws-basic.json --dry-run

# Execute pairwise tests in parallel
python tests/e2e_framework.py run --config e2e/configs/aws-basic.json --parallel 3

# Run specific pairwise test combination
python tests/e2e_framework.py run --config e2e/configs/aws-basic.json --filter "cluster_size=2,instance_type=m6idn.xlarge"
```

## Next Steps & Implementation Priority

### High Priority (Critical for Complete E2E Testing)
1. **Integrate SSH validation with main framework** - Connect existing SSH validator to perform live system checks
2. **Implement comprehensive live validation** - Use SSH to verify all deployment parameters on live nodes
3. **Integrate emergency response system** - Connect emergency handler with timeout monitoring and cleanup
4. **Enhance validation with live system checks** - Replace file-only validation with SSH-based verification

### Medium Priority (Enhanced Coverage)
5. **Add database connectivity validation** - Verify Exasol DB is running via SSH
6. **Integrate resource tracking** - Connect resource tracker with main framework for leak prevention
7. **Add network connectivity tests** - Verify inter-node communication via SSH
8. **Enhance reporting with live metrics** - Include system performance data from SSH checks

### Low Priority (Operational Improvements)
9. **Add cost monitoring and quotas** - Prevent unexpected charges
10. **Implement retry logic** - Handle transient failures gracefully
11. **Add filter functionality** - Run specific test combinations
12. **Create HTML reports** - Better visualization of test results

## Integration Strategy

### Leverage Existing Infrastructure
- **SSH Keys**: Use `tls_private_key.exasol_key` from Terraform
- **Inventory**: Parse generated `inventory.ini` for node IPs
- **Ansible Patterns**: Reuse validation commands from setup playbook
- **Configuration Files**: Parse `/home/exasol/exasol-release/config` for runtime validation

### Emergency Response Implementation
- **Timeout Monitoring**: Track deployment progress with configurable timeouts
- **Force Cleanup**: Use `exasol destroy --force` for stuck deployments
- **Resource Verification**: Cloud provider APIs to confirm complete deletion
- **Alert System**: Notifications for cleanup failures or resource leaks

### Reporting Enhancement
- **Live Metrics Collection**: System stats from all nodes via SSH
- **Validation Results**: Detailed pass/fail for each parameter
- **Resource Inventory**: Complete list with cloud resource IDs
- **Cost Tracking**: Estimated costs per test execution

## Success Criteria Update

- **Live System Validation**: All parameters verified on actual deployed nodes via SSH ✅ (Framework exists) / ⚠️ (Not fully integrated)
- **Emergency Response**: Zero infrastructure leaks with automatic cleanup and timeout handling ✅ (Framework exists) / ⚠️ (Not fully integrated)
- **Complete Coverage**: Every `exasol init` parameter validated in live environment ⚠️ (Partially implemented)
- **Resource Tracking**: Full audit trail of all cloud resources created/destroyed ✅ (Framework exists) / ⚠️ (Not fully integrated)
- **Comprehensive Reporting**: Detailed validation results with system metrics from live nodes ✅ (JSON) / ⚠️ (HTML not implemented)