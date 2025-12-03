# Exasol E2E Test Framework

A comprehensive end-to-end testing framework for Exasol deployments across multiple cloud providers.

## Features

- **Workflow Engine**: All tests execute via the workflow engine - no legacy hardcoded flows
- **Modular Configuration**: Separate SUT and workflow definitions for maximum reusability
- **Workflow-Based Testing**: Define complex multi-step test scenarios with validation
- **Parallel Execution**: Run multiple test deployments concurrently with configurable limits
- **Multi-Provider Support**: Test across AWS, Azure, GCP, and Libvirt
- **Comprehensive Validation**: Automated checks for deployment success and configuration correctness
- **Failsafety Testing**: Node crash simulation, stop/start operations, and recovery validation
- **Complete Logging**: All workflow step commands and output captured in suite-specific logs
- **Result Reporting**: Detailed JSON and HTML reports with step-by-step validation information

## Directory Structure

```
tests/e2e/
├── e2e_framework.py           # Main framework (uses workflow engine)
├── workflow_engine.py         # Workflow execution engine
├── configs/                   # Test configuration files
│   ├── aws.json              # AWS provider test suite
│   ├── azure.json            # Azure provider test suite
│   ├── gcp.json              # GCP provider test suite
│   ├── libvirt.json          # Libvirt provider test suite
│   ├── sut/                  # System Under Test definitions
│   │   ├── aws-1n.json       # AWS single node
│   │   ├── aws-4n.json       # AWS 4-node cluster
│   │   ├── aws-8n-vx-spot.json # AWS 8-node with VXLAN & spot
│   │   ├── azure-1n.json     # Azure configurations
│   │   ├── gcp-1n.json       # GCP configurations
│   │   └── libvirt-3n.json   # Libvirt configurations
│   └── workflow/             # Test workflow definitions
│       ├── basic.json        # Basic deploy/destroy
│       ├── enhanced.json     # Deploy/stop/start
│       └── failsafety.json   # Comprehensive failsafety tests
└── E2E-README.md             # This file
```

Results are stored in `./tmp/tests/e2e-YYYYMMDD-HHMMSS/` with auto-generated execution timestamps.

## Usage

### Using run_e2e.sh (Recommended)

```bash
# List all available tests
./tests/run_e2e.sh --list-tests

# Run tests for specific provider
./tests/run_e2e.sh --provider aws

# Run tests with parallelism
./tests/run_e2e.sh --provider libvirt --parallel 2

# Specify database version
./tests/run_e2e.sh --db-version exasol-2025.1.4

# Re-run specific suite from execution directory
./tests/run_e2e.sh --rerun ./tmp/tests/e2e-20251203-120000 aws-1n_basic

# Run specific test by suite name
./tests/run_e2e.sh --run-tests libvirt-3n_failsafety
```

### Programmatic Usage

```python
from tests.e2e.e2e_framework import E2ETestFramework

# Initialize framework with config
framework = E2ETestFramework('tests/e2e/configs/aws.json')

# Generate and run tests
plan = framework.generate_test_plan()
results = framework.run_tests(plan, max_parallel=2)
```

## Configuration Format

### New Modular Configuration Structure (Recommended)

Test configurations are now organized in a modular structure separating System Under Test (SUT) definitions from workflow definitions:

#### Provider-Level Configuration

Provider-level configs reference pairs of SUT and workflow definitions:

```json
{
  "provider": "aws",
  "description": "AWS E2E test configurations",
  "test_suites": [
    {
      "sut": "sut/aws-1n.json",
      "workflow": "workflow/basic.json"
    },
    {
      "sut": "sut/aws-4n.json",
      "workflow": "workflow/enhanced.json"
    }
  ]
}
```

#### SUT (System Under Test) Configuration

Defines the infrastructure parameters. The name is automatically derived from the filename.

```json
{
  "description": "AWS 4-node cluster configuration",
  "provider": "aws",
  "parameters": {
    "cluster_size": 4,
    "instance_type": "t3a.xlarge",
    "data_volumes_per_node": 2,
    "data_volume_size": 200,
    "root_volume_size": 100
  }
}
```

**Note:** The `sut_name` field is **not needed** - the suite name is derived from the filename (e.g., `aws-4n.json` → `aws-4n`).

#### Workflow Configuration

Defines the test scenario steps. The name is automatically derived from the filename.

```json
{
  "description": "Deploy, stop, start workflow",
  "steps": [
    {"step": "init"},
    {"step": "deploy"},
    {"step": "validate",
     "checks": ["cluster_status", "ssh_connectivity"]},
    {"step": "stop_cluster"},
    {"step": "validate",
     "checks": ["cluster_status_stopped"]},
    {"step": "start_cluster"},
    {"step": "validate",
     "checks": ["cluster_status", "database_running"]},
    {"step": "destroy"}
  ]
}
```

**Note:** The `workflow_name` field is **not needed** - the workflow name is derived from the filename (e.g., `enhanced.json` → `enhanced`). The suite name combines both: `{sut-name}_{workflow-name}` (e.g., `aws-4n_enhanced`).

### Benefits of Modular Structure

- **Reusability**: Same SUT can be tested with different workflows
- **Maintainability**: Update infrastructure or test logic independently
- **Clarity**: Clear separation between what to test and how to test it
- **Scalability**: Easy to add new SUTs or workflows without duplication
- **Simplicity**: No redundant name fields - filenames are the names

### SUT Configuration Parameters

The following parameters can be specified in the `parameters` section of SUT configuration files. Parameter names use underscores and map 1:1 to command-line flags (underscore becomes hyphen). For example, `enable_multicast_overlay` → `--enable-multicast-overlay`.

#### Common Parameters (All Providers)

| Parameter | Type | CLI Flag | Description | Example |
|-----------|------|----------|-------------|---------|
| `cluster_size` | int | `--cluster-size` | Number of nodes in the cluster | `4` |
| `data_volumes_per_node` | int | `--data-volumes-per-node` | Number of data volumes per node | `2` |
| `data_volume_size` | int | `--data-volume-size` | Size of each data volume in GB | `200` |
| `root_volume_size` | int | `--root-volume-size` | Size of root volume in GB | `100` |

#### Cloud Provider Parameters

| Parameter | Type | CLI Flag | Providers | Description |
|-----------|------|----------|-----------|-------------|
| `instance_type` | string | `--instance-type` | AWS, Azure, GCP, DO | Cloud instance type (e.g., `t3a.xlarge`, `Standard_D4s_v3`) |
| `libvirt_memory` | int | `--libvirt-memory` | Libvirt | Memory in GB for VMs |
| `libvirt_vcpus` | int | `--libvirt-vcpus` | Libvirt | Number of vCPUs |

#### Boolean Flags (Set to `true` to Enable)

| Parameter | CLI Flag | Providers | Description |
|-----------|----------|-----------|-------------|
| `enable_multicast_overlay` | `--enable-multicast-overlay` | All | Enable VXLAN overlay network for multicast support. Enabled by default for Hetzner and GCP. |
| `aws_spot_instance` | `--aws-spot-instance` | AWS | Enable spot instances for cost savings |
| `azure_spot_instance` | `--azure-spot-instance` | Azure | Enable low-priority instances for cost savings |
| `gcp_spot_instance` | `--gcp-spot-instance` | GCP | Enable preemptible instances for cost savings |

#### Example: AWS 8-Node Cluster with VXLAN and Spot Instances

```json
{
  "description": "AWS 8-node cluster with VXLAN networking",
  "provider": "aws",
  "parameters": {
    "cluster_size": 8,
    "instance_type": "t3a.2xlarge",
    "data_volumes_per_node": 3,
    "data_volume_size": 200,
    "root_volume_size": 100,
    "enable_multicast_overlay": true,
    "aws_spot_instance": true
  }
}
```

**Filename:** `sut/aws-8n-vx-spot.json` → Suite prefix: `aws-8n-vx-spot`

#### Example: Libvirt 2-Node with VXLAN Overlay

```json
{
  "description": "Libvirt dual node with VXLAN overlay",
  "provider": "libvirt",
  "parameters": {
    "cluster_size": 2,
    "libvirt_memory": 8,
    "libvirt_vcpus": 4,
    "data_volumes_per_node": 2,
    "data_volume_size": 50,
    "root_volume_size": 50,
    "enable_multicast_overlay": true
  }
}
```

**Filename:** `sut/libvirt-2n-vx.json` → Suite prefix: `libvirt-2n-vx`

**Note:** Parameter names follow a 1:1 mapping convention where underscores in the parameter name become hyphens in the CLI flag (e.g., `enable_multicast_overlay` → `--enable-multicast-overlay`). The `enable_multicast_overlay` parameter enables VXLAN overlay networking, which provides multicast support required by Exasol. This is automatically enabled for Hetzner and GCP providers.

## Validation Checks

The framework performs the following validation checks for each test:

- **Terraform State**: Verifies `.terraform/terraform.tfstate` exists
- **Outputs File**: Checks for `outputs.tf` file presence
- **Inventory File**: Validates `inventory.ini` exists and contains expected nodes
- **Cluster Size**: Verifies the number of nodes matches the specified cluster size
- **Terraform Logs**: Checks for errors in terraform execution logs

## Results

Test results are organized in execution-specific directories:

### Directory Structure

```
./tmp/tests/e2e-YYYYMMDD-HHMMSS/        # Execution directory
├── results.json                          # Test results with step details
├── results.html                          # Interactive HTML report
├── execution.log                         # Framework execution log
├── {suite-name}.log                      # Individual suite logs
├── {suite-name}-run2.log                 # Rerun logs (if applicable)
└── retained-deployments/                 # Retained failed deployments
    └── {suite-name}/                     # Deployment directory
```

### Result Files

- **results.json**: Detailed test results including:
  - Success/failure status for each test
  - Execution timestamp and directory
  - Step-by-step workflow execution with timing
  - Validation details and error messages
  - Resource parameters and SUT descriptions
  - Notification summaries

- **results.html**: Interactive HTML report featuring:
  - Summary statistics (total, passed, failed, execution time)
  - Suite-based organization with descriptive names
  - Expandable workflow steps with individual status and timing
  - Color-coded status indicators (pass/fail/pending)
  - Parameter display and SUT descriptions
  - Error details for failed tests

- **Suite Logs**: Individual log files for each test suite
  - `{suite-name}.log`: First run (contains all workflow step command output)
  - `{suite-name}-run2.log`, `{suite-name}-run3.log`: Subsequent reruns
  - Each log captures:
    - Workflow step execution
    - Command invocations (e.g., `./exasol init`, `./exasol deploy`)
    - Full STDOUT and STDERR from each command
    - Exit codes and error messages

### Log File Format

Each suite log file captures complete command execution:

```
[2025-12-03 11:04:17] Starting workflow test libvirt-1n_basic (libvirt)
[2025-12-03 11:04:17] Workflow has 4 steps
Running command: ./exasol init --cloud-provider libvirt --deployment-dir tmp/tests/.../libvirt-1n_basic ...
STDOUT:
[INFO] Initializing deployment directory: tmp/tests/.../libvirt-1n_basic
[INFO]   Cloud Provider: Local libvirt/KVM deployment
...
Command exited with 0
✓ Step: init - completed (1.2s)
Running command: ./exasol deploy --deployment-dir tmp/tests/.../libvirt-1n_basic
STDOUT:
[INFO] Starting deployment...
...
```

### Rerunning Tests

To rerun a specific suite from a previous execution:

```bash
# Format: --rerun <execution-dir> <suite-name>
./tests/run_e2e.sh --rerun ./tmp/tests/e2e-20251203-120000 aws-4n_enhanced
```

The rerun will:
- Use the same execution directory
- Append results to existing results.json
- Create new log file with run number (e.g., aws-4n_enhanced-run2.log)
- Create new deployment directory with run number (e.g., deployments/aws-4n_enhanced-run2/)
- Update the HTML report with latest results

## Requirements

- Python 3.6+
- Exasol CLI (`./exasol` command available)
- Cloud provider credentials configured
- Standard library only (no external dependencies)

## Integration with CI/CD

The framework can be integrated with GitHub Actions and other CI/CD systems:

```yaml
- name: Run E2E Tests
  run: |
    python3 -c "
    from tests.e2e.e2e_framework import E2ETestFramework
    framework = E2ETestFramework('tests/e2e/configs/aws-basic.json')
    plan = framework.generate_test_plan()
    results = framework.run_tests(plan, max_parallel=2)
    "
```

## Development

The framework uses only Python standard library for maximum compatibility and minimal dependencies. All cloud provider interactions are handled through the existing Exasol CLI commands.

---

# Workflow-Based E2E Testing

## Overview

The workflow-based testing framework extends the basic E2E test infrastructure to support complex, multi-step test scenarios including failsafety testing, start/stop operations, node-specific actions, and custom verification steps.

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
| **AWS** | ✅ Yes | 🚧 Planned | ✅ Yes | 🚧 Planned | ✅ Yes |
| **Azure** | ✅ Yes | 🚧 Planned | ✅ Yes | 🚧 Planned | ✅ Yes |
| **GCP** | ✅ Yes | 🚧 Planned | ✅ Yes | 🚧 Planned | ✅ Yes |
| **DigitalOcean** | ⚠️ Manual | ❌ No | ✅ Yes | ❌ No | ✅ Yes |
| **Hetzner** | ⚠️ Manual | ❌ No | ✅ Yes | ❌ No | ✅ Yes |
| **libvirt** | ⚠️ Manual | ❌ No | ✅ Yes | ❌ No | ✅ Yes |

**Legend:**
- ✅ **Yes**: Fully supported and implemented
- ⚠️ **Manual**: In-guest shutdown works; requires manual power-on via provider interface
- 🚧 **Planned**: Provider APIs support this, but not yet implemented in framework
- ❌ **No**: Not supported; workflow steps will raise `NotImplementedError`

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

Workflows are stored in `tests/e2e/configs/workflow/` and define sequences of test steps independent of specific deployment parameters.

### Basic Structure

```json
{
  "description": "Basic deploy and destroy workflow",
  "steps": [
    { "step": "init" },
    { "step": "deploy" },
    { "step": "validate", "checks": ["cluster_status", "ssh_connectivity"] },
    { "step": "destroy" }
  ]
}
```

**Note:** 
- Workflows are abstract and reusable - they don't contain deployment-specific parameters like `cluster_size` or `instance_type`. Those are defined in SUT (System Under Test) configurations and combined at the provider level.
- The `description` field is optional for standard steps (init, deploy, stop_cluster, etc.) as their purpose is self-explanatory. It's useful for validation steps to clarify what's being checked, or for custom commands and node-specific operations.
- The `workflow_name` field is not needed - the name is derived from the filename.

### Available Step Types

The workflow steps follow a natural lifecycle order from cluster creation to destruction. The `description` field is optional for standard steps.

#### 1. `init` - Initialize Deployment
Initialize a new deployment directory with the specified parameters.

```json
{
  "step": "init"
}
```

#### 2. `deploy` - Deploy Cluster
Deploy the cluster using the initialized configuration.

```json
{
  "step": "deploy"
}
```

#### 3. `validate` - Validation Step
Perform validation checks on the cluster state. Supports multiple checks, retry logic, and optional failures. Use `description` to clarify what's being validated.

```json
{
  "step": "validate",
  "description": "Validate cluster state after restart",
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
Gracefully stop all nodes in the cluster.

```json
{
  "step": "stop_cluster"
}
```

#### 5. `start_cluster` - Start Entire Cluster
Start all nodes in the cluster.

```json
{
  "step": "start_cluster"
}
```

#### 6. `stop_node` - Stop Specific Node (Planned: AWS/Azure/GCP)
Stop a specific node via provider API. Use `description` to indicate which node and why.

```json
{
  "step": "stop_node",
  "description": "Stop node n12 for failover testing",
  "target_node": "n12"
}
```
**Note:** Not yet implemented. Will raise `NotImplementedError` for all providers.

#### 7. `start_node` - Start Specific Node (Planned: AWS/Azure/GCP)
Start a specific node via provider API. Use `description` to indicate recovery intent.

```json
{
  "step": "start_node",
  "description": "Recover node n12",
  "target_node": "n12"
}
```
**Note:** Not yet implemented. Will raise `NotImplementedError` for all providers.

#### 8. `restart_node` - Restart Specific Node
Restart a specific node either gracefully via SSH or through power cycle. Use `description` for node-specific operations.

```json
{
  "step": "restart_node",
  "description": "Restart node n12 via SSH",
  "target_node": "n12",
  "method": "ssh"
}
```
**Supported Methods:**
- `ssh` (default): Reboot via SSH `sudo reboot` command - **works for all providers**
- `graceful`: Power cycle (stop then start) - **planned for AWS/Azure/GCP**, raises `NotImplementedError` for all providers currently

#### 9. `crash_node` - Simulate Node Crash
Simulate a hard crash on a specific node for testing recovery scenarios. Use `description` to explain the test scenario.

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
- `destroy`: Hard power-off via provider API - **planned for AWS/Azure/GCP** (not yet implemented)

#### 10. `custom_command` - Execute Custom Command
Execute a custom shell command or script for validation or operations. Always use `description` to explain what the command does.

```json
{
  "step": "custom_command",
  "description": "Run custom verification script",
  "custom_command": ["./scripts/verify_data.sh", "--check-integrity"]
}
```

#### 11. `destroy` - Destroy Cluster
Destroy the cluster and clean up all cloud resources.

```json
{
  "step": "destroy"
}
```
**Note:** This step tears down the entire deployment. It's typically used at the end of a test workflow to ensure proper cleanup.

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

### 1. Basic Deploy and Destroy

```json
{
  "workflow_name": "basic",
  "description": "Basic deploy and destroy workflow",
  "steps": [
    {"step": "init"},
    {"step": "deploy"},
    {"step": "validate", "description": "Validate deployment", "checks": ["cluster_status", "ssh_connectivity"]},
    {"step": "destroy"}
  ]
}
```

### 2. Start/Stop Test

```json
{
  "workflow_name": "enhanced",
  "description": "Deploy, stop, start, and destroy workflow",
  "steps": [
    {"step": "init"},
    {"step": "deploy"},
    {"step": "validate", "description": "Validate initial deployment", "checks": ["cluster_status", "database_running"]},
    {"step": "stop_cluster"},
    {"step": "validate", "description": "Validate cluster stopped", "checks": ["cluster_status_stopped"]},
    {"step": "start_cluster"},
    {"step": "validate", "description": "Validate cluster restarted", "checks": ["cluster_status", "database_running"]},
    {"step": "destroy"}
  ]
}
```

### 3. Single Node Failure Test

```json
{
  "workflow": [
    {"step": "init"},
    {"step": "deploy"},
    {"step": "validate", "description": "All nodes running", "checks": ["all_nodes_running"]},
    {"step": "stop_node", "description": "Stop node n12 for failover test", "target_node": "n12"},
    {"step": "validate", "description": "Cluster degraded with n12 down", "checks": [
      "cluster_degraded",
      "node_status:n11:running",
      "node_status:n12:stopped",
      "node_status:n13:running"
    ]},
    {"step": "start_node", "description": "Recover node n12", "target_node": "n12"},
    {"step": "validate", "description": "All nodes recovered", "checks": ["all_nodes_running"]},
    {"step": "destroy"}
  ]
}
```

### 4. Crash Recovery Test

```json
{
  "workflow": [
    {"step": "init"},
    {"step": "deploy"},
    {"step": "crash_node", "description": "Simulate hard crash on n11", "target_node": "n11", "method": "destroy"},
    {"step": "crash_node", "description": "Simulate hard crash on n12", "target_node": "n12", "method": "destroy"},
    {"step": "validate", "description": "Cluster critical with 2 nodes down", "checks": ["cluster_critical"], "allow_failures": ["database_down"]},
    {"step": "start_node", "description": "Recover n11", "target_node": "n11"},
    {"step": "start_node", "description": "Recover n12", "target_node": "n12"},
    {"step": "validate", "checks": ["cluster_status"], "retry": {"max_attempts": 5, "delay_seconds": 30}}
  ]
}
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

## Troubleshooting Workflow Tests

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
```</content>
<parameter name="filePath">tests/e2e/README.md
