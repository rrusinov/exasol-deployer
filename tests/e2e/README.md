# Exasol E2E Test Framework

A comprehensive end-to-end testing framework for Exasol deployments across multiple cloud providers.

## Features

- **Parameter-based Testing**: Define test parameters and generate combinations automatically
- **Combination Strategies**: Support for pairwise (2-wise), each-choice (1-wise), and full Cartesian product testing
- **Parallel Execution**: Run multiple test deployments concurrently with configurable limits
- **Multi-Provider Support**: Test across AWS, Azure, GCP, DigitalOcean, and Hetzner
- **Comprehensive Validation**: Automated checks for deployment success and configuration correctness
- **Live Validation & Emergency Handling**: Integrated SSH validation, resource tracking, and timeout-driven cleanup
- **Quota Guardrails & Notifications**: Configurable resource limits with automatic slow-test and failure alerts
- **Result Reporting**: JSON and HTML results with detailed validation information
- **Dry Run Mode**: Generate test plans without executing deployments
- **Automatic Cleanup**: Resource cleanup on test completion or failure

## Directory Structure

```
tests/e2e/
├── e2e_framework.py    # Main framework script
├── configs/           # Test configuration files
│   ├── aws-basic.json
│   └── libvirt-basic.json
└── README.md          # This file
```

Results are stored in `./tmp/tests/results/` by default (auto-created).

## Usage

The framework is used programmatically in Python. Here's how to generate and run tests:

```python
from pathlib import Path
from tests.e2e.e2e_framework import E2ETestFramework

# Initialize framework with config
framework = E2ETestFramework('tests/e2e/configs/aws-basic.json')

# Generate test plan (dry run)
plan = framework.generate_test_plan(dry_run=True)
# Prints test cases to console

# Execute tests
results = framework.run_tests(plan, max_parallel=2)
```

### Command Line Usage

For convenience, you can create simple Python scripts to run tests:

```bash
# Dry run to see test plan
python3 -c "
from tests.e2e.e2e_framework import E2ETestFramework
framework = E2ETestFramework('tests/e2e/configs/aws-basic.json')
framework.generate_test_plan(dry_run=True)
"

# Run tests
python3 -c "
from tests.e2e.e2e_framework import E2ETestFramework
framework = E2ETestFramework('tests/e2e/configs/aws-basic.json')
plan = framework.generate_test_plan()
results = framework.run_tests(plan, max_parallel=2)
"

# Run libvirt tests (requires local libvirt/KVM with network/pool available)
python3 -c "
from tests.e2e.e2e_framework import E2ETestFramework
framework = E2ETestFramework('tests/e2e/configs/libvirt-basic.json')
plan = framework.generate_test_plan()
results = framework.run_tests(plan, max_parallel=1)
"
```

## Configuration Format

Test configurations are defined in JSON format. The framework supports three combination strategies. If no combination strategy is specified, 1-wise testing is used by default:

### 2-wise Testing

Generates combinations covering all pairs of parameter values efficiently:

```json
{
  "test_suites": {
    "aws_2_wise": {
      "provider": "aws",
      "parameters": {
        "cluster_size": [1, 3],
        "instance_type": ["m6idn.large", "m6idn.xlarge"],
        "data_volumes_per_node": [1, 3],
        "data_volume_size": [100, 200],
        "root_volume_size": [50, 100]
      },
      "combinations": "1-wise"
    }
  }
}
```

For 5 parameters with 2 values each, generates 2 test combinations (one with all first values, one with all second values).

### 1-wise Testing

Ensures every parameter value appears at least once, using minimal test combinations:

```json
{
  "test_suites": {
    "aws_1_wise": {
      "provider": "aws",
      "parameters": {
        "cluster_size": [1, 3],
        "instance_type": ["m6idn.large", "m6idn.xlarge"],
        "data_volumes_per_node": [1, 3],
        "data_volume_size": [100, 200],
        "root_volume_size": [50, 100]
      },
      "combinations": "1-wise"
    }
  }
}
```

For parameters with 2 values each, generates 2 test combinations (one with all first values, one with all second values).

### Full Testing

Generates all possible combinations of parameters:

```json
{
  "test_suites": {
    "aws_full": {
      "provider": "aws",
      "parameters": {
        "cluster_size": [1, 3],
        "instance_type": ["m6idn.large", "m6idn.xlarge"]
      },
      "combinations": "full"
    }
  }
}
```

For 2 parameters with 2 values each, generates 4 test combinations.

## Combination Strategies

| Strategy | Description | Use Case |
|----------|-------------|----------|
| 2-wise | Covers all pairs of parameter values | Efficient coverage for interaction testing |
| 1-wise | Every parameter value appears at least once | Minimal coverage for basic validation |
| full | All possible parameter combinations | Exhaustive testing when feasible |

### Optional Settings

You can extend the root configuration with extra sections:

- `resource_limits`: Override defaults such as `max_total_instances`, `max_cluster_size_per_test` to guard against runaway deployments.
- `notifications`: Toggle alerts (`enabled`, `notify_on_failures`, `notify_on_slow_tests`, `slow_test_threshold_seconds`).
- `enable_live_validation`: Set to `false` to run SSH validation in dry-run mode without executing remote commands.

## Validation Checks

The framework performs the following validation checks for each test:

- **Terraform State**: Verifies `.terraform/terraform.tfstate` exists
- **Outputs File**: Checks for `outputs.tf` file presence
- **Inventory File**: Validates `inventory.ini` exists and contains expected nodes
- **Cluster Size**: Verifies the number of nodes matches the specified cluster size
- **Terraform Logs**: Checks for errors in terraform execution logs

## Results

Test results are saved to `./tmp/tests/results/` with timestamps:

- `test_results_YYYYMMDD_HHMMSS.json`: Detailed results with validation information
- `test_results_YYYYMMDD_HHMMSS.html`: Human-friendly report with pass/fail table
- `notifications_YYYYMMDD_HHMMSS.json`: Captured alerts for failed or slow tests (also appended to `notifications.log`)
- `e2e_test_YYYYMMDD_HHMMSS.log`: Execution logs

Results include success/failure status, validation details, execution time, and error messages.

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

The framework uses only Python standard library for maximum compatibility and minimal dependencies. All cloud provider interactions are handled through the existing Exasol CLI commands.</content>
<parameter name="filePath">tests/e2e/README.md
