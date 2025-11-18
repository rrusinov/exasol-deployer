# Progress Metrics Calibration Guide

This guide explains how to calibrate progress tracking metrics for accurate ETA calculations and progress bars in Exasol Deployer.

## Overview

Progress calibration creates empirical data about operation durations and output patterns for different cloud providers, operations, and cluster sizes. This enables:

- Accurate progress percentages during long-running operations
- Realistic ETA calculations
- Provider-specific optimizations
- Better user experience during deployments

## Quick Start

```bash
# 1. Run operation with calibration enabled
PROGRESS_CALIBRATE=true ./exasol deploy --deployment-dir ./test-deployment

# 2. Copy generated metrics to global repository
cp ./test-deployment/metrics/*.txt lib/metrics/

# 3. Commit the calibration data
git add lib/metrics/
git commit -m "Add calibration data for aws.deploy.4"
```

## Detailed Process

### Step 1: Prepare Test Environment

Create a test deployment directory and initialize it:

```bash
# Create test deployment
mkdir test-deployment
cd test-deployment

# Initialize with your target configuration
../exasol init --cloud-provider aws --deployment-dir .

# Edit variables.auto.tfvars as needed for your test scenario
# For example, set node_count = 4 for a 4-node cluster
```

### Step 2: Run Calibration

Execute the operation with calibration enabled:

```bash
# Enable calibration mode
export PROGRESS_CALIBRATE=true

# Run the operation (deploy, start, stop, destroy, or health)
../exasol deploy --deployment-dir .

# Note: This will take longer as it records detailed timing data
```

**Environment Variables:**
- `PROGRESS_CALIBRATE=true`: Enables calibration recording
- `PROGRESS_RECORD_FILE`: Automatically set to the metrics file path

### Step 3: Verify Calibration Data

Check that metrics were generated:

```bash
# List generated metrics
ls -la metrics/

# Example output:
# aws.deploy.4.txt

# View the calibration data
cat metrics/aws.deploy.4.txt
```

**Expected Content:**
```
provider=aws
operation=deploy
nodes=4
timestamp=2025-01-18T10:30:45Z
total_lines=1903
duration=420
line_offset_1=0
line_offset_2=1
line_offset_3=2
...
```

### Step 4: Merge to Global Metrics

Copy calibration data to the shared metrics repository:

```bash
# Option 1: Manual copy
cp metrics/*.txt ../lib/metrics/

# Option 2: Use the add-metrics command (recommended)
../exasol add-metrics --deployment-dir .

# Preview what would be copied
../exasol add-metrics --deployment-dir . --dry-run

# Verify the files
ls -la ../lib/metrics/aws.deploy.4.txt
```

### Step 5: Commit and Share

```bash
# Add to version control
git add lib/metrics/
git commit -m "Add calibration data for aws.deploy.4

- Duration: 420 seconds
- Total lines: 1903
- Cluster size: 4 nodes
- Provider: AWS"

# Push to share with team
git push
```

## Calibration Strategy

### What to Calibrate

**Operations:**
- `deploy`: Infrastructure provisioning and software installation
- `start`: Cluster startup from stopped state
- `stop`: Cluster shutdown
- `destroy`: Infrastructure cleanup
- `health`: Health checks and diagnostics

**Cluster Sizes:**
- Start with common sizes: 1, 2, 4, 8 nodes
- Calibrate for your most used configurations
- Consider both minimum and maximum supported sizes

**Providers:**
- `aws`: Amazon Web Services
- `azure`: Microsoft Azure
- `gcp`: Google Cloud Platform
- `libvirt`: Local KVM/libvirt
- `digitalocean`: DigitalOcean
- `hetzner`: Hetzner Cloud

### Best Practices

**Multiple Runs:**
```bash
# Run calibration 3 times and average results
for i in {1..3}; do
  PROGRESS_CALIBRATE=true ./exasol deploy --deployment-dir ./test-deployment
  mv metrics/aws.deploy.4.txt metrics/aws.deploy.4.run$i.txt
done

# Manually average the results or use the most representative run
```

**Realistic Scenarios:**
- Use actual cloud instances (not just local testing)
- Include realistic network conditions
- Test during typical load periods
- Account for cloud provider rate limiting

**Data Quality:**
- Ensure operations complete successfully
- Check for outliers in timing data
- Validate that total_lines matches expected output volume
- Verify provider and operation names are correct (not "unknown")

### Troubleshooting

**"unknown" Provider:**
If metrics show `unknown.deploy.Xnodes.txt`, the state file wasn't found:
```bash
# Check state file exists
ls -la .exasol.json

# Verify cloud_provider field
jq -r '.cloud_provider' .exasol.json
```

**Missing Metrics:**
If no metrics file is created:
```bash
# Check PROGRESS_CALIBRATE is set
echo $PROGRESS_CALIBRATE

# Verify deployment directory has metrics subdir
ls -la metrics/
```

**Inaccurate Timings:**
If ETAs seem wrong:
```bash
# Check calibration data format
cat lib/metrics/aws.deploy.4.txt

# Verify line count matches actual operation output
wc -l <(./exasol deploy --deployment-dir ./test 2>&1)
```

## Advanced Usage

### Custom Calibration Scripts

Create reusable calibration scripts:

```bash
#!/bin/bash
# calibrate.sh
set -e

PROVIDER=$1
OPERATION=$2
NODES=$3
DEPLOY_DIR="./calibration-${PROVIDER}-${OPERATION}-${NODES}"

# Setup
mkdir -p "$DEPLOY_DIR"
cd "$DEPLOY_DIR"
../exasol init --cloud-provider "$PROVIDER" --deployment-dir .

# Configure for N nodes
echo "node_count = $NODES" > variables.auto.tfvars

# Calibrate
PROGRESS_CALIBRATE=true ../exasol "$OPERATION" --deployment-dir .

# Copy results
cp metrics/*.txt ../lib/metrics/
echo "Calibration complete: ${PROVIDER}.${OPERATION}.${NODES}nodes.txt"
```

Usage:
```bash
./calibrate.sh aws deploy 4
./calibrate.sh libvirt start 2
```

### Regression Testing

After calibration updates, verify progress tracking works:

```bash
# Test progress display
./exasol deploy --deployment-dir ./test-deployment 2>&1 | head -20

# Should show: [XX%] [ETA: Xm] detailed progress messages
```

### Metrics Maintenance

**Update Existing Metrics:**
```bash
# Remove outdated metrics
rm lib/metrics/aws.deploy.old.txt

# Recalibrate with new infrastructure
PROGRESS_CALIBRATE=true ./exasol deploy --deployment-dir ./test

# Update repository
git commit -m "Update AWS deploy metrics for new instance types"
```

**Clean Up:**
```bash
# Remove deployment-specific metrics after merging
rm -rf test-deployment/metrics/
```

## Technical Details

### Metrics File Format

```
provider=aws
operation=deploy
nodes=4
timestamp=2025-01-18T10:30:45Z
total_lines=1903
duration=420
line_offset_1=0
line_offset_2=1
line_offset_3=2
...
```

**Fields:**
- `provider`: Cloud provider identifier
- `operation`: Operation type (deploy/start/stop/destroy/health)
- `nodes`: Cluster size
- `timestamp`: ISO 8601 timestamp of calibration
- `total_lines`: Total output lines produced
- `duration`: Total operation time in seconds
- `line_offset_N`: Approximate time offset for line N (used for ETA calculation)

### Loading Logic

Metrics are loaded in this priority order:

1. **Deployment-specific**: `<deployment-dir>/metrics/` (highest priority)
2. **Global metrics**: `lib/metrics/` (version-controlled)
3. **Fallback**: Maximum known lines from all metrics
4. **Default**: Hardcoded fallback (100 lines, 50 per additional node)

### ETA Calculation

The system uses calibration data to provide accurate ETAs:

- **With calibration**: Uses actual timing data for precise estimates
- **Without calibration**: Falls back to line-based rate calculation
- **Unknown operations**: Shows "???" for ETA

## Contributing

When contributing calibration data:

1. **Test thoroughly**: Ensure operations complete successfully
2. **Document conditions**: Note any special test conditions
3. **Use descriptive commit messages**: Include duration, line count, and configuration details
4. **Share with team**: Push calibration data to enable better progress tracking for all users

## See Also

- [Progress Tracking Implementation](../lib/progress_tracker.sh)
- [Metrics Data](../lib/metrics/)
- [Cloud Setup Guides](../docs/CLOUD_SETUP_*.md)