# AWS End-to-End Deployment Tests

Implement comprehensive e2e tests for AWS deployments using the e2e test framework, covering cluster sizes of 1 and 2 nodes with various parameter combinations including instance types, data volumes, and storage configurations.

## Test Scope

### Primary Test Dimensions
- **Cluster Size**: 1 node, 2 nodes (default configurations)
- **Instance Types**: Default instance type + next larger instance in same family
- **Data Volumes per Node**: 1, 2, 3 volumes
- **Data Volume Size**: 100GB, 200GB
- **Root Volume Size**: 50GB, 100GB

### Test Combinations
Generate matrix of parameter combinations, grouped into logical test suites that can run in parallel:

```json
{
  "test_suites": {
    "aws_cluster_size_1": {
      "cluster_size": [1],
      "instance_type": ["m6idn.large", "m6idn.xlarge"],
      "data_volumes_per_node": [1, 2],
      "data_volume_size": [100, 200],
      "root_volume_size": [50]
    },
    "aws_cluster_size_2": {
      "cluster_size": [2],
      "instance_type": ["m6idn.large"],
      "data_volumes_per_node": [1, 3],
      "data_volume_size": [100],
      "root_volume_size": [50, 100]
    }
  }
}
```

## Test Execution Strategy

### Parallel Test Groups
Divide tests into independent groups that can run concurrently:
- **Group A**: Single-node tests with varying storage configurations
- **Group B**: Two-node tests with different instance types
- **Group C**: Mixed configuration tests (different volume counts/sizes)

### Test Lifecycle per Combination
1. **Setup**: Generate unique deployment directory and parameters
2. **Init**: Run `exasol init` with test parameters
3. **Deploy**: Execute `exasol deploy` and monitor progress
4. **Validate**: Comprehensive checks of deployment success
5. **Test**: Run basic functionality tests (if applicable)
6. **Cleanup**: Destroy deployment and verify resource cleanup

## Validation Checks

### Deployment Validation
- Terraform state exists and is valid
- All EC2 instances created and running
- Security groups properly configured
- EBS volumes attached and formatted
- Ansible inventory generated correctly

### Service Validation
- SSH connectivity to all nodes
- Exasol services running on all nodes
- Database cluster formed correctly
- AdminUI accessible (if enabled)
- Basic database connectivity tests

### Configuration Validation
- Instance types match requested configuration
- Volume counts and sizes correct
- Network configuration proper
- SSH keys deployed correctly

## Implementation Phases

### Phase 1: Test Configuration
1. **Parameter Definition**: Create JSON configuration files for all test combinations
2. **Test Grouping**: Organize combinations into parallel execution groups
3. **Resource Planning**: Calculate required AWS resources and quotas

### Phase 2: Test Implementation
1. **Test Templates**: Create reusable test templates for AWS deployments
2. **Validation Scripts**: Implement comprehensive validation checks
3. **Error Handling**: Add retry logic and failure recovery

### Phase 3: Execution & Monitoring
1. **Parallel Execution**: Implement concurrent test running with resource limits
2. **Progress Monitoring**: Real-time tracking of test execution and results
3. **Resource Management**: Monitor AWS resource usage and costs

### Phase 4: Results & Analysis
1. **Result Collection**: Gather logs, metrics, and validation results
2. **Failure Analysis**: Detailed analysis of failed test combinations
3. **Performance Metrics**: Track deployment times and resource usage

## Success Criteria

- All test combinations execute successfully on AWS
- Parallel execution reduces total test time
- Comprehensive validation catches configuration issues
- Clear reporting of failures with actionable information
- Cost-effective resource usage within AWS limits
- Integration with CI/CD for automated regression testing

## Test Execution Examples

```bash
# Run all AWS e2e tests
e2e-framework run --config e2e/configs/aws-deployment-tests.json

# Run only single-node tests
e2e-framework run --config e2e/configs/aws-deployment-tests.json --filter "cluster_size=1"

# Run specific combination
e2e-framework run --config e2e/configs/aws-deployment-tests.json --filter "cluster_size=2,instance_type=m6idn.large,data_volumes_per_node=3"
```

## Dependencies

- **Prerequisite**: e2e-test-framework.md must be completed first
- **AWS Resources**: Requires AWS account with sufficient quotas for parallel deployments
- **Cost Management**: Implement resource tagging and automatic cleanup to control costs