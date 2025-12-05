# Exasol E2E Test Framework

A comprehensive end-to-end testing framework for Exasol deployments across multiple cloud providers.

## Features

- **Workflow Engine**: All tests execute via the workflow engine - no legacy hardcoded flows
- **Modular Configuration**: Separate SUT and workflow definitions for maximum reusability
- **Workflow-Based Testing**: Define complex multi-step test scenarios with validation
- **Parallel Execution**: Run multiple test deployments concurrently with configurable limits
- **Multi-Provider Support**: Test across AWS, Azure, GCP, and Libvirt
- **Comprehensive Validation**: Automated checks for deployment success and configuration correctness
- **Failsafety Testing**: Cluster stop/start operations, node reboot, and recovery validation
- **Complete Logging**: All workflow step commands and output captured in suite-specific logs
- **Result Reporting**: Detailed JSON and HTML reports with step-by-step validation information

## Directory Structure

```
tests/e2e/
├── e2e_framework.py              # Main framework (uses workflow engine)
├── workflow_engine.py            # Workflow execution engine
├── configs/                      # Test configuration files
│   ├── aws.jso   n               # AWS provider test suite
│   ├── azure.json                # Azure provider test suite
│   ├── gcp.jso   n               # GCP provider test suite
│   ├── hetzner.json              # Hetzner provider test suite
│   ├── digitalocean.json         # DigitalOcean provider test suite
│   ├── libvirt.json              # Libvirt provider test suite
│   ├── sut/                      # System Under Test definitions
│   │   ├── aws-1n.json           # AWS single node
│   │   ├── aws-4n.json           # AWS 4-node cluster
│   │   ├── aws-8n-vx-spot.json   # AWS 8-node with VXLAN & spot
│   │   ├── azure-1n.json         # Azure configurations
│   │   ├── gcp-1n.json           # GCP configurations
│   │   ├── hetzner-1n.json       # Hetzner configurations
│   │   ├── digitalocean-1n.json  # DigitalOcean configurations
│   │   └── libvirt-3n.json       # Libvirt configurations
│   └── workflow/                 # Test workflow definitions
│       ├── simple.json           # Basic deploy/destroy
│       ├── basic.json            # Deploy/stop/start/destroy
│       └── node-reboot.json      # Node reboot recovery test
└── E2E-README.md                 # This file
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

# Stop on first failure (for debugging)
./tests/run_e2e.sh --provider libvirt --stop-on-error

# Specify database version
./tests/run_e2e.sh --db-version exasol-2025.1.8

# Re-run specific suite from execution directory
./tests/run_e2e.sh --rerun ./tmp/tests/e2e-20251203-120000 aws-1n_basic

# Run specific test by suite name
./tests/run_e2e.sh --run-tests libvirt-3n_basic
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
  "max_concurrent_nodes": 10,
  "test_suites": [
    {
      "sut": "sut/aws-1n.json",
      "workflow": "workflow/basic.json"
    },
    {
      "sut": "sut/aws-4n.json",
      "workflow": "workflow/basic.json"
    }
  ]
}
```

**Optional Fields:**
- `max_concurrent_nodes`: Maximum total nodes that can run simultaneously across all tests. The scheduler will intelligently pack tests based on their `cluster_size` to stay within this limit. For example, with `max_concurrent_nodes: 4`, you could run: 1x4-node OR 1x3-node+1x1-node OR 2x2-node OR 4x1-node tests simultaneously. This prevents resource exhaustion on local systems (libvirt) and respects cloud provider quotas.

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

**Note:** The `workflow_name` field is **not needed** - the workflow name is derived from the filename (e.g., `basic.json` → `basic`). The suite name combines both: `{sut-name}_{workflow-name}` (e.g., `aws-4n_basic`).

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

The framework supports dynamic validation checks based on data from `exasol status` and `exasol health` commands.

### Cluster Status Checks

Format: `cluster_status==<value>` or `cluster_status!=<value>`

Validates the cluster status from `.exasol.json` state file.

**Examples:**
- `cluster_status==database_ready` - Cluster is ready
- `cluster_status==stopped` - Cluster is stopped
- `cluster_status!=error` - Cluster is not in error state

**Valid Status Values:**
- `database_ready` - Cluster deployed and database is ready
- `stopped` - Cluster is stopped
- `starting` - Cluster is starting up
- `stopping` - Cluster is shutting down  
- `error` - Cluster is in error state
- `degraded` - Cluster is degraded (some nodes down but operational)
- `deploy_failed` - Deployment failed
- `stop_failed` - Stop operation failed
- `start_failed` - Start operation failed

### Health Status Checks

Format: `health_status[<nodes>].<component>==<value>` or `!=<value>`

Validates health status from `exasol health --output-format json` command.

**Node Selectors:**
- `[*]` - All nodes (aggregate check across all nodes)
- `[n11]` - Specific node (note: per-node checks not yet supported, falls back to aggregate)
- `[n11,n12,n13]` - Multiple nodes (note: per-node checks not yet supported, falls back to aggregate)

**Component Selectors:**
Components map to the health check categories returned by `exasol health`:
- `.ssh` → SSH connectivity checks
- `.adminui` → Admin UI service checks (part of services)
- `.database` → Database service checks (part of services)
- `.cos_ssh` → COS SSH connectivity (part of SSH checks)

**Value Comparisons:**
- `ok` or `true` → Expects all nodes passed (failed count = 0, passed count > 0)
- `failed` or `false` → Expects some failures (failed count > 0)

**Current Implementation:**
The health check uses aggregate data from `exasol health --output-format json`:
```json
{
  "status": "healthy",
  "checks": {
    "ssh": {"passed": 3, "failed": 0},
    "services": {"active": 12, "failed": 0}
  },
  "issues_count": 0,
  "issues": []
}
```

For `health_status[*].ssh==ok`, the check verifies that `checks.ssh.failed == 0` and `checks.ssh.passed > 0`.

**Examples:**
- `health_status[*].ssh==ok` - SSH OK on all nodes (no failed SSH checks)
- `health_status[*].adminui==ok` - Admin UI services OK on all nodes (no failed services)
- `health_status[*].database==ok` - Database services OK on all nodes (no failed services)
- `health_status[*].ssh!=ok` - Some SSH failures detected
- `health_status[*].database!=failed` - No database failures detected (same as ==ok)

**Note:** Per-node granular health checks are not yet supported by the current `exasol health` JSON output. The [*] wildcard selector checks aggregate health across all nodes. Specific node selectors ([n11], [n12,n13]) fall back to aggregate checks with a warning logged.

### Validation Step Configuration

```json
{
  "step": "validate",
  "description": "Validate cluster state",
  "checks": [
    "cluster_status==database_ready",
    "health_status[*].ssh==ok",
    "health_status[*].adminui==ok"
  ],
  "allow_failures": ["health_status[*].adminui==ok"],
  "retry": {
    "max_attempts": 5,
    "delay_seconds": 30
  }
}
```

**Fields:**
- `checks` (required): List of validation check strings
- `allow_failures` (optional): List of checks that can fail without failing the step
- `retry` (optional): Retry configuration
  - `max_attempts`: Maximum number of retry attempts
  - `delay_seconds`: Delay between retries in seconds
- `description` (optional): Human-readable description of what's being validated

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
./tests/run_e2e.sh --rerun ./tmp/tests/e2e-20251203-120000 aws-4n_basic
```

The rerun will:
- Use the same execution directory
- Append results to existing results.json
- Create new log file with run number (e.g., aws-4n_basic-run2.log)
- Create new deployment directory with run number (e.g., deployments/aws-4n_basic-run2/)
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

### Configuration Validation

The E2E framework includes comprehensive configuration validation to ensure correctness before tests run:

**Schema Validation (`tests/e2e/config_schema.py`):**
- Defines supported workflow steps, validation checks, and SUT parameters
- Validates workflow step configurations against schema
- Validates SUT parameters for each provider
- Validates validation check syntax and values

**Unit Tests (`tests/e2e/test_config_validation.py`):**
- Tests workflow configuration files are valid
- Tests SUT configuration files are valid
- Tests documentation matches implementation
- Tests schema definitions are consistent

**Run validation tests:**
```bash
cd tests/e2e
python3 -m unittest test_config_validation -v
```

**Key Validation Features:**
- Workflow step validation (required/optional fields, provider support)
- Validation check syntax validation (cluster_status, health_status patterns)
- SUT parameter validation (type checking, provider compatibility)
- Documentation consistency checks (ensures README matches implementation)

### Adding New Features

**Adding a New Workflow Step:**
1. Add step handler to `WorkflowExecutor._execute_step()` in `workflow_engine.py`
2. Implement `_execute_<step_name>()` method
3. Add step schema to `WORKFLOW_STEPS` in `config_schema.py`
4. Update documentation in `E2E-README.md`
5. Run validation tests to ensure consistency

**Adding a New Validation Check Component:**
1. Add component mapping to `HEALTH_CHECK_COMPONENTS` in `config_schema.py`
2. Update `_create_health_status_check()` in `workflow_engine.py`
3. Document in validation checks section of README
4. Run validation tests

**Adding a New SUT Parameter:**
1. Add parameter to `SUT_PARAMETERS` in `config_schema.py`
2. Add parameter mapping in `WorkflowExecutor._execute_init()` in `workflow_engine.py`
3. Document in SUT Configuration Parameters section
4. Run validation tests

---

# Workflow-Based E2E Testing

## Overview

The workflow-based testing framework extends the basic E2E test infrastructure to support complex, multi-step test scenarios including cluster stop/start operations, node reboot testing, and validation.

## Key Features

- **Sequential Workflow Execution**: Define test scenarios as a sequence of steps
- **Node-Specific Operations**: Target individual nodes for restart operations
- **Custom Validation**: Per-step validation with retry logic and failure handling
- **Rich Reporting**: Detailed step-by-step results with timing and validation data

## Resource Management

The framework includes intelligent resource management to prevent overcommitment:

### Automatic Cleanup on Failure

When a test fails, the framework automatically:
1. Attempts to run `exasol destroy` on the failed deployment
2. Frees up resources (nodes, memory) for subsequent tests
3. Continues with remaining tests in the queue

This prevents resource exhaustion when tests fail partway through.

### Stop on Error (Debugging Mode)

Use `--stop-on-error` to halt execution after the first test failure:

```bash
./tests/run_e2e.sh --provider libvirt --stop-on-error
```

**Behavior:**
- Stops scheduling new tests after first failure
- Allows currently running tests to complete
- Preserves failed deployment for debugging
- Useful for investigating test failures locally

**Without --stop-on-error (default):**
- Cleans up failed deployments automatically
- Continues executing remaining tests
- Better for CI/CD and unattended runs

### Resource-Aware Scheduling

See `max_concurrent_nodes` in provider configuration for details on limiting total nodes.

## Provider Support

All workflow operations are supported across all providers:

| Provider | Cluster Stop (SSH) | Cluster Start | Node Reboot (SSH) |
|----------|-------------------|---------------|-------------------|
| **AWS** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Azure** | ✅ Yes | ✅ Yes | ✅ Yes |
| **GCP** | ✅ Yes | ✅ Yes | ✅ Yes |
| **DigitalOcean** | ✅ Yes | ⚠️ Manual* | ✅ Yes |
| **Hetzner** | ✅ Yes | ⚠️ Manual* | ✅ Yes |
| **libvirt** | ✅ Yes | ⚠️ Manual* | ✅ Yes |

**Legend:**
- ✅ **Yes**: Fully supported and implemented
- ⚠️ **Manual***: VMs are powered off; requires manual power-on via provider interface

**Note:** 
- Cluster stop uses `exasol stop` command via SSH (works on all providers)
- Cluster start uses `exasol start` command - requires VMs to be running
- For DigitalOcean/Hetzner/libvirt: after cluster stop, VMs must be manually powered on before cluster start
- Node reboot uses SSH `sudo reboot` command

## Workflow Configuration Format

Workflows are stored in `tests/e2e/configs/workflow/` and define sequences of test steps independent of specific deployment parameters.

## Workflow Configuration Format

Workflows are stored in `tests/e2e/configs/workflow/` and define sequences of test steps independent of specific deployment parameters.

### Workflow File Structure

```json
{
  "description": "Brief description of the workflow purpose",
  "steps": [
    { "step": "init" },
    { "step": "deploy" },
    { "step": "validate", "checks": [...] },
    { "step": "destroy" }
  ]
}
```

**Key Points:**
- Workflows are **abstract and reusable** - no deployment-specific parameters
- The `workflow_name` field is **not needed** - derived from filename (e.g., `basic.json` → `basic`)
- The `description` field is **optional** for self-explanatory steps
- Suite name format: `{sut-name}_{workflow-name}` (e.g., `aws-4n_basic`)

### SUT (System Under Test) File Structure

SUT configurations define infrastructure parameters and are stored in `tests/e2e/configs/sut/`.

```json
{
  "description": "Brief description of the SUT configuration",
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

**Key Points:**
- The `sut_name` field is **not needed** - derived from filename (e.g., `aws-4n.json` → `aws-4n`)
- The `provider` field is **required** and must be one of: `aws`, `azure`, `gcp`, `digitalocean`, `hetzner`, `libvirt`
- The `parameters` field is **required** and contains deployment-specific parameters
- See [SUT Configuration Parameters](#sut-configuration-parameters) section for available parameters

### Supported Workflow Steps

The following step types are supported (in typical lifecycle order):

| Step | Required Fields | Optional Fields | Description |
|------|----------------|-----------------|-------------|
| `init` | `step` | `description` | Initialize deployment directory |
| `deploy` | `step` | `description` | Deploy the cluster |
| `validate` | `step`, `checks` | `description`, `allow_failures`, `retry` | Perform validation checks |
| `stop_cluster` | `step` | `description` | Stop entire cluster |
| `start_cluster` | `step` | `description` | Start entire cluster |
| `restart_node` | `step`, `target_node` | `description`, `method` | Restart specific node |
| `custom_command` | `step`, `command` | `description` | Execute custom shell command |
| `destroy` | `step` | `description` | Destroy cluster and cleanup |

### Workflow Execution Behavior

**Important:** Workflows abort immediately when any step fails. Subsequent steps are **not executed**.

For example, if a workflow has these steps:
```json
["init", "deploy", "validate", "stop_cluster", "validate", "start_cluster", "destroy"]
```

And the first `validate` step fails, then `stop_cluster`, the second `validate`, `start_cluster`, and `destroy` steps are **skipped**.

**Automatic Cleanup:**
- When a workflow step fails, the E2E framework **automatically destroys** the deployment
- This frees resources for subsequent tests
- Use `--stop-on-error` flag to **preserve** failed deployments for debugging (disables automatic cleanup)

**Retry Configuration:**
The `retry` field in validation steps applies **only to individual validation checks**, not to workflow continuation:
```json
{
  "step": "validate",
  "checks": ["health_status[*].ssh==ok"],
  "retry": {
    "max_attempts": 5,
    "delay_seconds": 30
  }
}
```
This will retry the SSH health check up to 5 times with 30s delays, but if all attempts fail, the workflow stops and no further steps execute.

### Basic Structure

```json
{
  "description": "Basic deploy and destroy workflow",
  "steps": [
    { "step": "init" },
    { "step": "deploy" },
    { "step": "validate", "checks": [
      "cluster_status==database_ready",
      "health_status[*].ssh==ok"
    ] },
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
    "cluster_status==database_ready",
    "health_status[*].ssh==ok",
    "health_status[*].database==ok"
  ],
  "allow_failures": ["health_status[*].adminui==ok"],
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

#### 6. `restart_node` - Restart Specific Node
Restart a specific node via SSH. Use `description` for node-specific operations.

```json
{
  "step": "restart_node",
  "description": "Restart node n12 via SSH",
  "target_node": "n12",
  "method": "ssh"
}
```
**Supported Methods:**
- `ssh`: Reboot via SSH `sudo reboot` command - **works for all providers**

#### 7. `custom_command` - Execute Custom Shell Command
Execute a custom shell command with variable substitution support.

```json
{
  "step": "custom_command",
  "description": "Start database manually via COS SSH",
  "command": "ssh -F $deployment_dir/ssh_config n11-cos 'confd_client db_start db_name: Exasol'"
}
```

**Supported Variables:**
- `$deployment_dir`: Path to the deployment directory
- `$provider`: Cloud provider name

**Features:**
- Executes arbitrary shell commands
- Variable substitution in command string
- Supports pipes, redirects, and complex shell syntax
- Command output logged to test suite log
- Command failure causes workflow to abort

**Use Cases:**
- Manual database operations (start, stop, backup)
- Custom health checks or diagnostics
- Provider-specific operations
- Testing edge cases and recovery scenarios

#### 8. `destroy` - Destroy Cluster
Destroy the cluster and clean up all cloud resources.

```json
{
  "step": "destroy"
}
```
**Note:** This step tears down the entire deployment. It's typically used at the end of a test workflow to ensure proper cleanup.

## Example Workflows

### 1. Basic Deploy and Destroy

```json
{
  "description": "Basic deploy and destroy workflow",
  "steps": [
    {"step": "init"},
    {"step": "deploy"},
    {"step": "validate", "description": "Validate deployment", "checks": [
      "cluster_status==database_ready",
      "health_status[*].ssh==ok"
    ]},
    {"step": "destroy"}
  ]
}
```

### 2. Start/Stop Test

```json
{
  "description": "Deploy, stop, start, and destroy workflow",
  "steps": [
    {"step": "init"},
    {"step": "deploy"},
    {"step": "validate", "description": "Validate initial deployment", "checks": [
      "cluster_status==database_ready",
      "health_status[*].database==ok"
    ]},
    {"step": "stop_cluster"},
    {"step": "validate", "description": "Validate cluster stopped", "checks": ["cluster_status==stopped"]},
    {"step": "start_cluster"},
    {"step": "validate", "description": "Validate cluster restarted", "checks": [
      "cluster_status==database_ready",
      "health_status[*].database==ok"
    ]},
    {"step": "destroy"}
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
