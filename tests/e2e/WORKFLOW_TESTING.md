# Workflow-Based E2E Testing Framework

## Overview

The workflow-based testing framework extends the existing E2E test infrastructure to support complex, multi-step test scenarios including failsafety testing, start/stop operations, node-specific actions, and custom verification steps.

## Key Features

- **Sequential Workflow Execution**: Define test scenarios as a sequence of steps
- **Node-Specific Operations**: Target individual nodes for operations (stop, start, restart, crash)
- **Custom Validation**: Per-step validation with retry logic and failure handling
- **Crash Simulation**: Simulate hard crashes and test recovery (AWS/Azure/GCP only)
- **External Commands**: Execute custom verification commands
- **Rich Reporting**: Detailed step-by-step results with timing and validation data

## Provider-Specific Limitations

The workflow engine enforces provider-specific limitations on power control operations:

### Power Control Support by Provider

| Provider | Cluster Stop/Start | Node Stop/Start | Node Crash (SSH) | Node Crash (API) | Node Reboot (SSH) |
|----------|-------------------|-----------------|------------------|------------------|-------------------|
| **AWS** | ✅ Yes | ✅ Yes* | ✅ Yes | 🚧 Planned | ✅ Yes |
| **Azure** | ✅ Yes | ✅ Yes* | ✅ Yes | 🚧 Planned | ✅ Yes |
| **GCP** | ✅ Yes | ✅ Yes* | ✅ Yes | 🚧 Planned | ✅ Yes |
| **DigitalOcean** | ⚠️ Manual | ❌ No | ✅ Yes | ❌ No | ✅ Yes |
| **Hetzner** | ⚠️ Manual | ❌ No | ✅ Yes | ❌ No | ✅ Yes |
| **libvirt** | ⚠️ Manual | ❌ No | ✅ Yes | ❌ No | ✅ Yes |

\* Not yet implemented for AWS/Azure/GCP, but supported by provider APIs

**Legend:**
- ✅ **Yes**: Fully supported and implemented
- ⚠️ **Manual**: Issues in-guest shutdown; requires manual power-on via provider interface
- 🚧 **Planned**: Supported by provider but not yet implemented in framework
- ❌ **No**: Not supported by provider; workflow steps will raise `NotImplementedError`

### Unsupported Operations

For **DigitalOcean, Hetzner, and libvirt**, the following workflow steps will raise `NotImplementedError`:
- `stop_node` - Individual node power off via API
- `start_node` - Individual node power on via API
- `crash_node` with `method: "destroy"` - Hard crash via power API
- `restart_node` with `method: "graceful"` - Power cycle restart

### Universal Operations (Work on All Providers)

The following operations work on **all providers** via SSH:
- ✅ `restart_node` with `method: "ssh"` (default) - Graceful reboot via `sudo reboot`
- ✅ `crash_node` with `method: "ssh"` (default) - Hard crash via SysRq or `poweroff -f`

## Workflow Configuration Format

### Basic Structure

```json
{
  "test_suites": {
    "suite_name": {
      "provider": "libvirt|aws|azure|gcp",
      "test_type": "workflow",
      "description": "Test description",
      "parameters": {
        "cluster_size": 3,
        "libvirt_memory_gb": 8,
        ...
      },
      "requirements": {
        "libvirt_available": true,
        "min_memory_gb": 32
      },
      "workflow": [
        { "step": "init", "description": "..." },
        { "step": "deploy", "description": "..." },
        { "step": "validate", "checks": [...] },
        ...
      ]
    }
  }
}
```

### Available Step Types

#### 1. `init` - Initialize Deployment
```json
{
  "step": "init",
  "description": "Initialize deployment"
}
```

#### 2. `deploy` - Deploy Cluster
```json
{
  "step": "deploy",
  "description": "Deploy cluster"
}
```

#### 3. `validate` - Validation Step
```json
{
  "step": "validate",
  "description": "Validate cluster state",
  "checks": [
    "cluster_status",
    "ssh_connectivity",
    "database_running"
  ],
  "allow_failures": ["optional_check"],
  "retry": {
    "max_attempts": 5,
    "delay_seconds": 30
  }
}
```

#### 4. `stop_cluster` - Stop Entire Cluster
```json
{
  "step": "stop_cluster",
  "description": "Stop all cluster nodes"
}
```

#### 5. `start_cluster` - Start Entire Cluster
```json
{
  "step": "start_cluster",
  "description": "Start all cluster nodes"
}
```

#### 6. `stop_node` - Stop Specific Node (AWS/Azure/GCP only)
```json
{
  "step": "stop_node",
  "description": "Stop node n12",
  "target_node": "n12"
}
```
**Note:** Not supported for DigitalOcean, Hetzner, or libvirt. Will raise `NotImplementedError`.

#### 7. `start_node` - Start Specific Node (AWS/Azure/GCP only)
```json
{
  "step": "start_node",
  "description": "Start node n12",
  "target_node": "n12"
}
```
**Note:** Not supported for DigitalOcean, Hetzner, or libvirt. Will raise `NotImplementedError`.

#### 8. `restart_node` - Restart Specific Node
```json
{
  "step": "restart_node",
  "description": "Reboot node via SSH",
  "target_node": "n12",
  "method": "ssh"
}
```
**Supported Methods:**
- `ssh` (default): Reboot via SSH `sudo reboot` command - **works for all providers**
- `graceful`: Power cycle (stop then start) - **only for AWS/Azure/GCP**, raises `NotImplementedError` for DigitalOcean/Hetzner/libvirt

#### 9. `crash_node` - Simulate Node Crash
```json
{
  "step": "crash_node",
  "description": "Simulate hard crash on n11",
  "target_node": "n11",
  "method": "ssh"
}
```
**Supported Methods:**
- `ssh` (default): Hard crash via SSH using SysRq trigger or `poweroff -f` - **works for all providers**
  - Attempts to use kernel SysRq trigger (`echo b > /proc/sysrq-trigger`) for immediate reboot without filesystem sync
  - Falls back to `poweroff -f` which forces immediate shutdown, skipping systemd
  - Simulates ungraceful shutdown similar to power loss or kernel panic
- `destroy`: Hard power-off via provider API - **only for AWS/Azure/GCP** (not yet implemented)

#### 10. `custom_command` - Execute Custom Command
```json
{
  "step": "custom_command",
  "description": "Run custom verification script",
  "custom_command": ["./scripts/verify_data.sh", "--check-integrity"]
}
```

## Built-in Validation Checks

### Cluster Status Checks
- `cluster_status` - Cluster is healthy and operational
- `cluster_status_stopped` - Cluster is fully stopped
- `cluster_degraded` - Cluster is degraded but operational
- `cluster_critical` - Cluster is in critical state

### Node Status Checks
- `all_nodes_running` - All nodes are running
- `ssh_connectivity` - SSH connectivity to all nodes
- `vms_powered_off` - All VMs are powered off
- `node_status:<node>` - Check specific node status (e.g., `node_status:n12`)
- `node_status:<node>:<state>` - Check node in specific state (e.g., `node_status:n12:running`)

### Database Checks
- `database_running` - Database services are running
- `database_degraded` - Database is in degraded state
- `database_down` - Database is completely down
- `admin_ui_accessible` - Admin UI is accessible
- `data_integrity` - Verify data integrity after operations

## Example Workflows

### 1. Basic Start/Stop Test

```json
{
  "workflow": [
    {"step": "init", "description": "Initialize"},
    {"step": "deploy", "description": "Deploy cluster"},
    {"step": "validate", "checks": ["cluster_status", "database_running"]},
    {"step": "stop_cluster", "description": "Stop cluster"},
    {"step": "validate", "checks": ["cluster_status_stopped"]},
    {"step": "start_cluster", "description": "Start cluster"},
    {"step": "validate", "checks": ["cluster_status", "database_running"]}
  ]
}
```

### 2. Single Node Failure Test

```json
{
  "workflow": [
    {"step": "init"},
    {"step": "deploy"},
    {"step": "validate", "checks": ["all_nodes_running"]},
    {"step": "stop_node", "target_node": "n12"},
    {"step": "validate", "checks": [
      "cluster_degraded",
      "node_status:n11:running",
      "node_status:n12:stopped",
      "node_status:n13:running"
    ]},
    {"step": "start_node", "target_node": "n12"},
    {"step": "validate", "checks": ["all_nodes_running"]}
  ]
}
```

### 3. Crash Recovery Test

```json
{
  "workflow": [
    {"step": "init"},
    {"step": "deploy"},
    {"step": "crash_node", "target_node": "n11", "method": "destroy"},
    {"step": "crash_node", "target_node": "n12", "method": "destroy"},
    {"step": "validate", "checks": ["cluster_critical"], "allow_failures": ["database_down"]},
    {"step": "start_node", "target_node": "n11"},
    {"step": "start_node", "target_node": "n12"},
    {"step": "validate", "checks": ["cluster_status"], "retry": {"max_attempts": 5, "delay_seconds": 30}}
  ]
}
```

## Running Workflow Tests

### Using the E2E Framework

```bash
# Run all workflow tests
./tests/run_e2e.sh --provider libvirt

# Run specific workflow test
./tests/run_e2e.sh --run-test libvirt-workflow-failsafety_basic

# List all available tests
./tests/run_e2e.sh --list-tests
```

### Direct Python Execution

```python
from tests.e2e.e2e_framework import E2ETestFramework
from tests.e2e.workflow_integration import add_workflow_support_to_framework, parse_workflow_test_plans

# Create framework
framework = E2ETestFramework(config_path="tests/e2e/configs/libvirt-failsafety.json")

# Add workflow support
add_workflow_support_to_framework(framework)

# Generate and run test plans
test_plans = framework.generate_test_plan()
results = framework.run_tests(test_plans, max_parallel=1)
```

## Extending the Framework

### Adding Custom Validation Checks

```python
from tests.e2e.workflow_engine import ValidationRegistry

# In your test code
def custom_check(context: Dict[str, Any]) -> bool:
    # Your custom validation logic
    deploy_dir = context['deploy_dir']
    # ... perform checks ...
    return True

# Register the check
validation_registry.register(
    "my_custom_check",
    "Description of check",
    custom_check,
    allow_failure=False
)
```

### Adding Custom Step Types

Extend the `WorkflowExecutor` class:

```python
def _execute_my_custom_step(self, step: WorkflowStep):
    """Execute custom step"""
    # Your implementation
    pass

# Add to executor
executor._execute_my_custom_step = _execute_my_custom_step
```

## Test Results

### Result Structure

```json
{
  "deployment_id": "libvirt-workflow-failsafety_basic-...",
  "success": true,
  "duration": 123.45,
  "workflow_steps": [
    {
      "step_type": "init",
      "description": "Initialize deployment",
      "status": "completed",
      "duration": 5.2,
      "error": null,
      "validation_results": []
    },
    {
      "step_type": "validate",
      "description": "Validate cluster",
      "status": "completed",
      "duration": 8.1,
      "validation_results": [
        {"check": "cluster_status", "passed": true, "attempts": 1},
        {"check": "database_running", "passed": true, "attempts": 1}
      ]
    }
  ]
}
```

## Best Practices

1. **Start Simple**: Begin with basic workflows and add complexity gradually
2. **Use Validation Steps**: Add validation after each significant operation
3. **Allow Expected Failures**: Use `allow_failures` for checks that may fail in degraded states
4. **Add Retry Logic**: Use retry configuration for checks that may need time to stabilize
5. **Document Workflows**: Add clear descriptions to each step
6. **Test Incrementally**: Test each workflow step independently before combining
7. **Clean Up**: Workflow tests will cleanup automatically, but you can retain artifacts on failure

## Troubleshooting

### Common Issues

**Issue**: Workflow test fails at validation step
- Check the validation logs in the test output directory
- Verify the check names are correct
- Add retry logic if the system needs time to stabilize

**Issue**: Node operations fail
- Ensure the provider supports the operation (e.g., libvirt for local testing)
- Check that node names match the actual deployment
- Verify permissions for provider operations (e.g., virsh access)

**Issue**: Timeout during step execution
- Increase timeout in subprocess calls
- Add delays between dependent operations
- Check system resources (memory, CPU)

### Debug Logging

Enable debug logging:

```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

Check test logs:
```bash
cat tmp/tests/test_output/<deployment_id>/test.log
```

## Integration with CI/CD

Add workflow tests to your CI pipeline:

```yaml
# .github/workflows/e2e-workflow.yml
- name: Run Workflow Tests
  run: |
    ./tests/run_e2e.sh --provider libvirt --parallel 2
```

## Future Enhancements

- Support for parallel step execution within a workflow
- Conditional step execution based on previous results
- Step groups with rollback capabilities
- Integration with monitoring/alerting systems
- Provider-agnostic node operations
- Advanced chaos engineering scenarios
