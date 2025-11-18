# Progress Tracking Metrics

This directory contains calibration data for progress tracking across different cloud providers, operations, and cluster sizes.

> **📖 For detailed calibration instructions, see [METRICS_CALIBRATION.md](../docs/METRICS_CALIBRATION.md)**

## Metric File Format

Each metric file follows the naming convention:
```
<provider>.<operation>.<nodes>.txt
```

Examples:
- `aws.deploy.1.txt`
- `aws.deploy.4.txt`
- `libvirt.start.2.txt`

### File Contents

```
total_lines=1903
provider=aws
operation=deploy
nodes=4
timestamp=2025-01-18T10:00:00Z
duration=420
```

- `total_lines`: Number of output lines produced during the operation
- `provider`: Cloud provider (aws, azure, gcp, libvirt, digitalocean, hetzner)
- `operation`: Operation type (deploy, start, stop, destroy, health)
- `nodes`: Number of cluster nodes
- `timestamp`: When this measurement was taken (ISO 8601 format)
- `duration`: Total operation time in seconds

## Timing Files (Optional)

For ETA calculation, timing files track elapsed time at specific line numbers:

```
<provider>.<operation>.<nodes>node(s).txt.timing
```

Format:
```
# line_number elapsed_seconds
1 0.1
10 1.2
50 5.8
100 12.3
200 25.6
1903 420.5
```

## How It Works

### 1. Metric Loading

When an operation starts, the progress tracker:
1. Loads all matching metrics: `<provider>.<operation>.*.txt`
2. Calculates linear regression: `lines = base + (nodes - 1) * per_node`
3. Estimates total lines for the current configuration

### 2. Progress Calculation

The regression formula is calculated from available measurements:
- **Base**: Lines for 1-node deployment
- **Per-node**: Additional lines per extra node

Example with aws.deploy:
- 1 node: 994 lines
- 4 nodes: 1903 lines
- Formula: `lines = 994 + (nodes - 1) * 303`
- For 2 nodes: `994 + (2-1) * 303 = 1297 lines`

### 3. ETA Calculation

ETA is calculated using:
```
lines_per_sec = current_line / elapsed_time
remaining_lines = estimated_total - current_line
eta = remaining_lines / lines_per_sec
```

Display format: `[XX%] [ETA: Xm] output_line`

### 4. Calibration Mode

To record new metrics during operation:
```bash
PROGRESS_CALIBRATE=true ./exasol deploy --deployment-dir ./my-deployment
```

This creates a metric file in `<deployment-dir>/metrics/` which can be merged into `lib/metrics/`.

## Fallback Strategy

If no metrics are available for a provider/operation combination:
1. Use the maximum `total_lines` from all known metrics
2. This ensures progress still displays, even if less accurate

## Metric Sources

Metrics can be loaded from two locations (in order):
1. **Global metrics**: `lib/metrics/` (version-controlled, shared across deployments)
2. **Deployment metrics**: `<deployment-dir>/metrics/` (per-deployment calibration)

Both locations are scanned and all matching files are used for regression calculation.

## Adding New Metrics

### Manual Creation

Create a file with the format above:
```bash
cat > lib/metrics/aws.deploy.8nodes.txt <<EOF
total_lines=3140
provider=aws
operation=deploy
nodes=8
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
duration=720
EOF
```

### Automated Calibration

1. Run operation with calibration flag:
   ```bash
   PROGRESS_CALIBRATE=true ./exasol deploy --deployment-dir ./test-deployment
   ```

2. Copy generated metric:
   ```bash
   cp ./test-deployment/metrics/*.txt lib/metrics/
   ```

3. Commit to version control

## Usage in Code

### Load and Calculate Regression

```bash
source lib/progress_tracker.sh

# Calculate regression for aws deploy
read base per_node < <(progress_calculate_regression "aws" "deploy")
echo "Base: $base, Per-node: $per_node"

# Estimate lines for 3-node deployment
total=$(progress_estimate_lines "aws" "deploy" 3)
echo "Estimated lines: $total"
```

### Wrap Command Execution

```bash
# From exasol main script
progress_wrap_command "deploy" "$DEPLOYMENT_DIR" cmd_deploy --deployment-dir "$DEPLOYMENT_DIR" "$@"
```

This automatically:
- Detects provider and node count from deployment
- Calculates expected lines
- Displays progress with ETA
- Records metrics if PROGRESS_CALIBRATE=true

## Provider-Specific Notes

### AWS/Azure/GCP
- Operations have distinct phases (tofu apply, ansible playbook)
- Track the entire top-level operation (not sub-phases)

### DigitalOcean/Hetzner/libvirt
- `start` operation includes wait-for-health polling
- Track from start of `exasol start` to completion
- Polling intervals affect line count

### All Providers
- `health --wait-for` is tracked when called from `start`
- Standalone `health` commands are tracked separately
- `health --quiet` produces minimal output (different metrics)

## Best Practices

1. **Calibrate for each provider**: Different providers have different output patterns
2. **Multiple node counts**: Calibrate for 1, 2, 4, 8 nodes to improve regression accuracy
3. **Periodic recalibration**: Re-measure after significant code changes
4. **Version control**: Commit metric files to share across team
5. **Deployment-specific**: Use deployment-dir metrics for provider-specific optimizations
