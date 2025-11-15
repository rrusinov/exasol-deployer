# E2E Test Recommendations for Health Check Feature

## Overview

This document provides recommendations for end-to-end testing of the enhanced `exasol health` command in live AWS/Azure/GCP deployments. These tests should be run after the deployment framework is fully operational.

## Test Environment Setup

### Prerequisites
- Active AWS/Azure/GCP account with permissions to create/destroy resources
- Exasol deployer configured and tested
- SSH access to deployed instances
- AWS CLI / Azure CLI / gcloud CLI installed and configured

### Test Deployment
Create a test deployment using the standard process:
```bash
./exasol init --deployment-dir ./health-test --cloud-provider aws
./exasol deploy --deployment-dir ./health-test
```

## Test Scenarios

### 1. Basic Health Check (Healthy State)

**Objective**: Verify health check passes on a healthy deployment

**Steps**:
1. Deploy a fresh cluster
2. Wait for database to be ready
3. Run health check:
   ```bash
   ./exasol health --deployment-dir ./health-test
   ```

**Expected Results**:
- Exit code: 0
- All SSH checks: OK
- All COS SSH checks: OK
- All services (c4.service, c4_cloud_command.service, exasol-admin-ui.service, exasol-data-symlinks.service): active
- Cloud metadata: OK
- Volume check: OK
- Cluster state: OK
- No IP mismatches
- No issues reported

**Validation**:
```bash
echo $?  # Should be 0
cat .health-test/.exasol.json | jq '.health_status'  # Should be "healthy"
cat .health-test/.exasol.json | jq '.last_health_check'  # Should show recent timestamp
```

---

### 2. JSON Output Format

**Objective**: Verify JSON output is properly formatted and contains all data

**Steps**:
1. Run health check with JSON output:
   ```bash
   ./exasol health --deployment-dir ./health-test --output-format json > health.json
   ```
2. Validate JSON structure

**Expected Results**:
- Valid JSON output
- Contains: status, exit_code, timestamp, deployment_dir, checks, issues_count, issues, remediation

**Validation**:
```bash
jq . health.json  # Should parse without errors
jq '.status' health.json  # Should be "healthy"
jq '.exit_code' health.json  # Should be 0
jq '.checks.ssh.passed' health.json  # Should match node count
jq '.checks.services.active' health.json  # Should be 4 * node_count
jq '.issues | length' health.json  # Should be 0
```

---

### 3. Spontaneous IP Change Detection

**Objective**: Detect when instance IPs change (simulating provider-initiated reboot)

**Steps**:
1. Note current instance IP from inventory.ini
2. **Simulate IP change** (AWS):
   ```bash
   # Stop and start instance (changes public IP in AWS)
   aws ec2 stop-instances --instance-ids <instance-id>
   aws ec2 wait instance-stopped --instance-ids <instance-id>
   aws ec2 start-instances --instance-ids <instance-id>
   aws ec2 wait instance-running --instance-ids <instance-id>
   ```
3. Run health check WITHOUT --update:
   ```bash
   ./exasol health --deployment-dir ./health-test
   ```
4. Run health check WITH --update:
   ```bash
   ./exasol health --deployment-dir ./health-test --update
   ```

**Expected Results (without --update)**:
- Exit code: 1
- IP mismatch detected
- Suggestion to run with --update
- Backup files NOT created

**Expected Results (with --update)**:
- Exit code: 0 (if no other issues)
- IP mismatch detected and fixed
- Backup files created in `.backups/health/<timestamp>/`
- inventory.ini updated
- ssh_config updated
- INFO.txt updated
- terraform.tfstate note shown (manual refresh required)

**Validation**:
```bash
# After --update
ls -la ./health-test/.backups/health/  # Should show timestamped backup directory
grep -r "<new-ip>" ./health-test/inventory.ini  # Should find new IP
grep -r "<old-ip>" ./health-test/.backups/health/*/inventory.ini  # Should find old IP in backup
```

---

### 4. Service Failure and Auto-Remediation

**Objective**: Detect failed services and restart them with --try-fix

**Steps**:
1. SSH into a node and stop a service:
   ```bash
   ssh -F ./health-test/ssh_config n11 sudo systemctl stop exasol-admin-ui.service
   ```
2. Run health check WITHOUT --try-fix:
   ```bash
   ./exasol health --deployment-dir ./health-test
   ```
3. Run health check WITH --try-fix:
   ```bash
   ./exasol health --deployment-dir ./health-test --try-fix
   ```
4. Verify service is running:
   ```bash
   ssh -F ./health-test/ssh_config n11 sudo systemctl is-active exasol-admin-ui.service
   ```

**Expected Results (without --try-fix)**:
- Exit code: 1
- Service failure detected
- Issue reported

**Expected Results (with --try-fix)**:
- Exit code: 0
- Service detected as failed
- Service restarted successfully
- Service shown as active after restart

**Edge Case - Remediation Failure**:
1. Stop a service and make it fail to start (e.g., corrupt config)
2. Run with --try-fix
3. Should return exit code 2 (remediation failed)

---

### 5. Cloud Metadata Validation (AWS)

**Objective**: Verify cloud provider instance count matches expected

**Steps**:
1. Deploy multi-node cluster (e.g., 3 nodes)
2. Run health check (should pass)
3. **Manually terminate one instance** (via AWS console or CLI):
   ```bash
   aws ec2 terminate-instances --instance-ids <instance-id>
   ```
4. Run health check

**Expected Results**:
- Exit code: 1
- Cloud metadata check fails
- Instance count mismatch reported (expected=3, found=2)
- Issue type: "cloud_instance_count_mismatch"

**Validation**:
```bash
./exasol health --deployment-dir ./health-test --output-format json | \
  jq '.issues[] | select(.type == "cloud_instance_count_mismatch")'
```

---

### 6. Multiple Concurrent Issues

**Objective**: Test detection of multiple simultaneous problems

**Steps**:
1. Create multiple issues:
   - Stop 2 services on different nodes
   - Simulate IP change on one node
   - (Optional) Detach a volume
2. Run health check with JSON output

**Expected Results**:
- Exit code: 1
- Multiple issues detected in issues array
- Each issue has correct type and severity
- Overall issue count matches number of problems

**Validation**:
```bash
./exasol health --deployment-dir ./health-test --output-format json > multi-issue.json
jq '.issues_count' multi-issue.json  # Should be >= 3
jq '.issues[] | .type' multi-issue.json  # Should show multiple types
jq '.issues[] | select(.severity == "critical")' multi-issue.json  # Should filter critical issues
```

---

### 7. Backup and Rollback

**Objective**: Verify backups are created and can be used for rollback

**Steps**:
1. Note current state of inventory.ini, ssh_config, INFO.txt
2. Trigger IP change
3. Run health check with --update
4. Verify backups created
5. Manually restore from backup if needed

**Expected Results**:
- Backup directory created: `.backups/health/<timestamp>/`
- All three files backed up before modification
- Backup files contain original content
- Modified files contain new content
- Can restore by copying backup files back

**Validation**:
```bash
# Check backup exists
BACKUP_DIR=$(ls -dt ./health-test/.backups/health/* | head -1)
echo "Backup directory: $BACKUP_DIR"

# Verify backup files exist
ls -la "$BACKUP_DIR"/inventory.ini
ls -la "$BACKUP_DIR"/ssh_config
ls -la "$BACKUP_DIR"/INFO.txt

# Compare backup with current (should differ if IPs changed)
diff "$BACKUP_DIR"/inventory.ini ./health-test/inventory.ini

# Restore if needed
cp "$BACKUP_DIR"/inventory.ini ./health-test/inventory.ini
```

---

### 8. State Management and Locking

**Objective**: Verify health check integrates with state management

**Steps**:
1. Start a health check in background:
   ```bash
   ./exasol health --deployment-dir ./health-test &
   HEALTH_PID=$!
   ```
2. Immediately try to run another command:
   ```bash
   ./exasol deploy --deployment-dir ./health-test
   ```
3. Wait for health check to complete:
   ```bash
   wait $HEALTH_PID
   ```
4. Verify state file updated

**Expected Results**:
- Second command blocked while health check running
- Lock file created during health check
- Lock file removed after health check
- State file contains last_health_check timestamp
- State file contains health_status

**Validation**:
```bash
# During health check
ls -la ./health-test/.exasol.lock  # Should exist

# After health check
ls -la ./health-test/.exasol.lock  # Should not exist
jq '.last_health_check' ./health-test/.exasol.json
jq '.health_status' ./health-test/.exasol.json
```

---

### 9. Progress Tracking

**Objective**: Verify progress events are logged

**Steps**:
1. Run health check
2. Check progress log

**Expected Results**:
- `.exasol-progress.jsonl` contains health check events
- Events include: progress_start, progress_complete (or progress_fail)

**Validation**:
```bash
# Check progress log
grep '"operation":"health"' ./health-test/.exasol-progress.jsonl

# Parse events
jq -s '.[] | select(.operation == "health")' ./health-test/.exasol-progress.jsonl
```

---

### 10. Volume Attachments Check

**Objective**: Verify volume detection works correctly

**Steps**:
1. Run health check on deployment with data volumes
2. Check volume check output
3. (Advanced) Detach a data volume and rerun

**Expected Results**:
- With volumes: "Volume check: OK (X disk(s) found)"
- Without volumes: "Volume check: WARNING - No additional data disks detected"

**Validation**:
```bash
# SSH to node and check disks
ssh -F ./health-test/ssh_config n11 "lsblk -ndo NAME,TYPE,MOUNTPOINT | grep disk"
```

---

### 11. Cluster State Validation

**Objective**: Verify c4 cluster status check works

**Steps**:
1. Run health check on fully deployed cluster
2. Verify cluster state check passes
3. (Advanced) Cause cluster issue and rerun

**Expected Results**:
- Healthy cluster: "Cluster state: OK (cluster online)"
- Unhealthy/unavailable: "Cluster state: Unable to verify (c4 cluster status unavailable)"

**Validation**:
```bash
# Manually check cluster status
ssh -F ./health-test/ssh_config n11 \
  "cd /home/exasol/exasol-release && sudo -u exasol ./c4 cluster status"
```

---

### 12. Long-Running Deployment Testing

**Objective**: Test health check on deployment over time

**Steps**:
1. Deploy cluster
2. Run health check every 6 hours for several days
3. Monitor for false positives/negatives
4. Check if spontaneous provider reboots are detected

**Expected Results**:
- Consistent results for stable deployment
- Detects actual issues when they occur
- No false positives during normal operation
- Captures state changes (last_health_check updated each time)

**Validation**:
```bash
# Schedule periodic health checks
while true; do
    ./exasol health --deployment-dir ./health-test --output-format json >> health-history.jsonl
    sleep 21600  # 6 hours
done

# Analyze history
jq -s '.[] | {timestamp, status, issues_count}' health-history.jsonl
```

---

## Test Matrix

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

**Legend**:
- ✓ = Fully supported/testable
- ⚠️ = Cloud metadata check not yet implemented for Azure/GCP
- - = Not applicable for this test

---

## Automated Test Script Template

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

---

## Performance Benchmarks

### Expected Execution Times
- Single-node cluster: 5-10 seconds
- 3-node cluster: 15-30 seconds
- 10-node cluster: 1-2 minutes

### Factors Affecting Performance
- SSH connection establishment
- Cloud provider API calls
- Number of services checked
- Network latency

### Performance Test
```bash
# Measure health check performance
time ./exasol health --deployment-dir ./health-test

# Measure with different output formats
time ./exasol health --deployment-dir ./health-test --output-format text
time ./exasol health --deployment-dir ./health-test --output-format json
```

---

## Integration with CI/CD

### Scheduled Health Checks
```yaml
# GitHub Actions example
name: Scheduled Health Check
on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours

jobs:
  health-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run health check
        run: |
          ./exasol health \
            --deployment-dir ${{ secrets.DEPLOYMENT_DIR }} \
            --output-format json > health-report.json
      - name: Check for issues
        run: |
          ISSUES=$(jq '.issues_count' health-report.json)
          if [[ "$ISSUES" -gt 0 ]]; then
            echo "Health check detected $ISSUES issue(s)"
            exit 1
          fi
```

---

## Monitoring Integration

### Prometheus Metrics (Future Enhancement)
```bash
# Example: Export health check results as Prometheus metrics
./exasol health --deployment-dir ./prod --output-format json | \
  jq -r '
    "exasol_health_status{deployment=\"prod\"} \(.exit_code)",
    "exasol_health_issues_total{deployment=\"prod\"} \(.issues_count)",
    "exasol_health_ssh_passed{deployment=\"prod\"} \(.checks.ssh.passed)",
    "exasol_health_services_active{deployment=\"prod\"} \(.checks.services.active)"
  ' > /var/lib/node_exporter/textfile_collector/exasol_health.prom
```

---

## Troubleshooting Test Failures

### Common Issues

**1. SSH Connection Failures**
```bash
# Verify SSH config
cat ./health-test/ssh_config
ssh -F ./health-test/ssh_config n11 echo "OK"

# Check security groups/firewall
# AWS: Ensure port 22 is open in security group
# Azure: Check NSG rules
# GCP: Check firewall rules
```

**2. Cloud Metadata Check Failures**
```bash
# Verify AWS CLI credentials
aws sts get-caller-identity

# Test AWS EC2 query manually
aws ec2 describe-instances --filters "Name=tag:deployment,Values=health-test"
```

**3. Service Check Failures**
```bash
# SSH to node and check services manually
ssh -F ./health-test/ssh_config n11
sudo systemctl status c4.service
sudo systemctl status exasol-admin-ui.service
sudo journalctl -u c4.service -n 50
```

**4. State File Issues**
```bash
# Check state file format
jq . ./health-test/.exasol.json

# Verify lock file cleanup
ls -la ./health-test/.exasol.lock  # Should not exist when no operation running
```

---

## Success Criteria for E2E Tests

All tests must pass with the following criteria:
- ✅ Basic health check returns exit code 0 on healthy deployment
- ✅ JSON output is valid and contains all required fields
- ✅ IP changes are detected and can be fixed with --update
- ✅ Backups are created before file modifications
- ✅ Service failures are detected and can be fixed with --try-fix
- ✅ Failed remediation returns exit code 2
- ✅ Cloud metadata checks work on AWS (instance count validation)
- ✅ Volume and cluster state checks function correctly
- ✅ State file and progress log are updated correctly
- ✅ Lock mechanism prevents concurrent operations
- ✅ Multiple concurrent issues are all detected and reported

---

## Next Steps

1. **Immediate**: Run basic health check tests on test deployments
2. **Short-term**: Implement automated test script for CI/CD
3. **Long-term**: Set up scheduled health checks on production deployments
4. **Future**: Integrate with monitoring/alerting systems
