# Testing Plan for Start/Stop Commands

This document outlines the integration and E2E tests that should be added for the start/stop functionality.

## Completed
- ✅ Unit tests for state transitions ([tests/test_state.sh](../tests/test_state.sh))
  - All 60 unit tests passing
  - Covers state constant validation
  - Tests validate_start_transition() function
  - Tests validate_stop_transition() function

## Integration Tests (To Be Added)

Integration tests should verify the commands work with real Ansible playbooks (but in test environments).

### Test Files to Create
- `tests/integration/test_start_stop.sh` - Basic start/stop integration tests

### Test Cases Needed
1. **Stop Command Integration**
   - Create mock deployment with proper structure
   - Verify stop command validates state correctly
   - Verify Ansible playbook is invoked correctly
   - Verify state transitions correctly on success
   - Verify state transitions correctly on failure
   - Verify lock is created and released properly

2. **Start Command Integration**
   - Create mock deployment with stopped state
   - Verify start command validates state correctly
   - Verify Ansible playbook is invoked correctly
   - Verify state transitions correctly on success
   - Verify state transitions correctly on failure
   - Verify lock is created and released properly

3. **State Transition Edge Cases**
   - Test stop from database_connection_failed state
   - Test start retry after start_failed
   - Test stop retry after stop_failed
   - Verify helpful error messages for invalid transitions

### Implementation Approach
```bash
#!/usr/bin/env bash
# tests/integration/test_start_stop.sh

# Setup mock deployment directory
setup_mock_deployment() {
    local deploy_dir="$1"
    mkdir -p "$deploy_dir/.templates"
    # Copy real Ansible playbooks
    cp templates/ansible/start-exasol-cluster.yml "$deploy_dir/.templates/"
    cp templates/ansible/stop-exasol-cluster.yml "$deploy_dir/.templates/"
    # Create mock inventory
    echo "[exasol_nodes]" > "$deploy_dir/inventory.ini"
    echo "test-node ansible_host=localhost" >> "$deploy_dir/inventory.ini"
    # Initialize state
    state_init "$deploy_dir" "8.0.0-x86_64" "x86_64"
}

# Test cases go here...
```

## E2E Tests (To Be Added to AWS E2E Framework)

E2E tests should verify the complete workflow on real cloud infrastructure.

### Test Files to Extend
- Extend existing AWS E2E framework in `tests/e2e/`
- Add test cases to the Python E2E test runner

### Test Scenarios Needed

#### 1. Basic Stop/Start Cycle
```python
def test_stop_start_cycle(self):
    """Test basic stop and start of a running deployment"""
    # Prerequisites: Running deployment from previous test
    # 1. exasol stop --deployment-dir <dir>
    # 2. Verify state is 'stopped'
    # 3. Verify c4.service is inactive via SSH
    # 4. exasol start --deployment-dir <dir>
    # 5. Verify state is 'database_ready'
    # 6. Verify c4.service is active via SSH
    # 7. Verify database is accessible
```

#### 2. Multiple Stop/Start Cycles
```python
def test_multiple_stop_start_cycles(self):
    """Test multiple stop/start cycles to verify reliability"""
    # Run stop/start 3 times in a row
    # Verify IP consistency after each cycle
    # Verify database state after each cycle
    # Verify no resource leaks
```

#### 3. Stop from Connection Failed State
```python
def test_stop_from_connection_failed(self):
    """Test stopping when database has connection issues"""
    # 1. Simulate connection failure (break connectivity)
    # 2. Verify state becomes 'database_connection_failed'
    # 3. exasol stop should still work
    # 4. Verify state is 'stopped'
```

#### 4. Start Retry After Failure
```python
def test_start_retry_after_failure(self):
    """Test start retry capability"""
    # 1. Stop database
    # 2. Intentionally cause start failure (e.g., remove config)
    # 3. Verify state is 'start_failed'
    # 4. Fix the issue
    # 5. Retry start
    # 6. Verify successful start and state is 'database_ready'
```

#### 5. IP Consistency Verification
```python
def test_ip_consistency_after_restart(self):
    """Verify IP addresses remain consistent after stop/start"""
    # 1. Record IPs before stop
    # 2. Stop database
    # 3. Start database
    # 4. Compare IPs in:
    #    - inventory.ini
    #    - INFO.txt
    #    - Terraform state
    #    - SSH config
    # 5. Verify all match original IPs
```

#### 6. Systemd Service Verification
```python
def test_systemd_services_after_start(self):
    """Verify all required systemd services are running after start"""
    # 1. Stop database
    # 2. Start database
    # 3. Via SSH, check services:
    #    - c4.service (active)
    #    - c4_cloud_command.service (active)
    #    - exasol-admin-ui.service (active)
    #    - exasol-data-symlinks.service (active)
    # 4. Check journalctl for Admin UI messages
    # 5. Verify services came up in correct order
```

### Integration with Existing E2E Framework

Add to `tests/e2e/test_runner.py`:
```python
# New test module
from test_modules import test_start_stop

# Register test module
TEST_MODULES = [
    # ... existing modules ...
    test_start_stop.StartStopTestModule(),
]
```

Create `tests/e2e/test_modules/test_start_stop.py`:
```python
class StartStopTestModule:
    def test_basic_stop_start(self, context):
        """Basic stop/start cycle test"""
        pass

    def test_multiple_cycles(self, context):
        """Multiple stop/start cycles"""
        pass

    # ... additional test methods ...
```

## Test Execution Plan

### Phase 1: Integration Tests (Can run immediately)
```bash
# Run integration tests
bash tests/integration/test_start_stop.sh
```

### Phase 2: E2E Tests (Requires AWS credentials)
```bash
# Run E2E tests with start/stop scenarios
cd tests/e2e
./test_runner.py --module test_start_stop

# Or run full E2E suite
./test_runner.py
```

## Success Criteria

- [ ] All integration tests pass
- [ ] All E2E tests pass on AWS
- [ ] Stop/start works reliably across multiple cycles
- [ ] IP addresses remain consistent
- [ ] All systemd services restart correctly
- [ ] Database is accessible after start
- [ ] Error handling works correctly for edge cases
- [ ] Lock mechanism prevents concurrent operations

## Next Steps

1. Implement integration tests in `tests/integration/test_start_stop.sh`
2. Extend E2E framework with start/stop test module
3. Run tests in CI/CD pipeline
4. Document any special considerations found during testing
5. Update this plan based on test results
