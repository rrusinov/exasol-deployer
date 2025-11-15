# Implement Start/Stop Commands for Exasol Deployments

Add `exasol start` and `exasol stop` commands to allow stopping and starting Exasol database services without terminating cloud instances. This enables cost optimization by stopping database services when not needed while preserving the infrastructure.

## Implementation Status (as of 2025-11-15)

**Current Status: NOT IMPLEMENTED**

Analysis shows that NONE of the start/stop functionality has been implemented yet. Below is a detailed status of each component:

### ❌ Phase 1: Core Command Structure - NOT IMPLEMENTED
- **Command Registration** (`exasol` lines 146-215): Only has `init`, `deploy`, `destroy`, `status`, `health`, `version`, `help` - missing `start` and `stop` cases
- **Command Files**: `lib/cmd_start.sh` and `lib/cmd_stop.sh` do NOT exist
- **Source Statements** (`exasol` lines 19-27): Not sourcing cmd_start.sh or cmd_stop.sh
- **Help Text** (`exasol` lines 47-54): Does not mention start/stop commands

### ❌ Phase 2: State Management - NOT IMPLEMENTED
- **Status Constants** (`lib/state.sh` lines 19-27): Missing all 5 required status values:
  - `STATE_STOPPED="stopped"`
  - `STATE_START_IN_PROGRESS="start_in_progress"`
  - `STATE_START_FAILED="start_failed"`
  - `STATE_STOP_IN_PROGRESS="stop_in_progress"`
  - `STATE_STOP_FAILED="stop_failed"`
- **Transition Validation**: No state transition validation functions exist anywhere
- **Lock Integration**: Lock infrastructure exists (`lib/state.sh` lines 117-214) but start/stop commands don't use it yet

### ❌ Phase 3: Database Operations - NOT IMPLEMENTED
- **Ansible Playbooks**: Missing `templates/ansible/start-exasol-cluster.yml` and `stop-exasol-cluster.yml`
- **C4 Commands**: Need to determine correct c4 commands for start/stop (likely `c4 host start`/`c4 host stop` based on patterns in `setup-exasol-cluster.yml` line 341)
- **Health Checks**: Database connectivity validation not implemented (though service check infrastructure exists in `lib/cmd_health.sh`)
- **Error Handling**: Pattern exists in other commands but not applied to start/stop

### ❌ Phase 4: Testing & Documentation - NOT IMPLEMENTED
- **Unit Tests**: None exist for start/stop
- **Integration Tests**: None exist for start/stop
- **E2E Tests**: AWS e2e tests not added yet
- **Documentation**: README not updated with start/stop commands

### ✅ Existing Infrastructure That Can Be Reused
- Lock management system (`lib/state.sh` lines 117-214): `lock_exists()`, `lock_create()`, `lock_remove()`, `lock_info()`
- Progress tracking functions: `progress_start()`, `progress_complete()`, `progress_fail()` used in `lib/common.sh`
- Health check infrastructure: `lib/cmd_health.sh` validates systemd services (c4.service, c4_cloud_command.service, exasol-admin-ui.service, exasol-data-symlinks.service)
- Ansible integration patterns: Established in `cmd_deploy.sh` and `templates/ansible/setup-exasol-cluster.yml`
- Error handling patterns: Examples in `cmd_deploy.sh` (lines 110-115) and `cmd_destroy.sh` (lines 143-156)
- Command structure pattern: All commands follow consistent structure with `show_*_help()` and `cmd_*()` functions

### Implementation Checklist

- [ ] Add status constants to `lib/state.sh` (lines ~27)
- [ ] Implement state transition validation functions in `lib/state.sh`
- [ ] Create `lib/cmd_start.sh` with full implementation
- [ ] Create `lib/cmd_stop.sh` with full implementation
- [ ] Register commands in main `exasol` script
- [ ] Research and document correct c4 commands for start/stop operations
- [ ] Create `templates/ansible/start-exasol-cluster.yml`
- [ ] Create `templates/ansible/stop-exasol-cluster.yml`
- [ ] Implement database connectivity validation
- [ ] Add unit tests for state transitions
- [ ] Add integration tests for start/stop
- [ ] Add AWS e2e tests
- [ ] Update README documentation

---

## New Status Fields

Add the following status values to `lib/state.sh`:
- `stopped` - Database services are stopped
- `start_in_progress` - Database start operation in progress
- `start_failed` - Database start operation failed
- `stop_in_progress` - Database stop operation in progress
- `stop_failed` - Database stop operation failed

## State Transition Constraints

### Valid Transitions:
- `start_in_progress` → `database_ready`
- `database_ready` → `stop_in_progress` (stop command)
- `database_connection_failed` → `stop_in_progress` (stop command from failed state)
- `stopped` → `start_in_progress` (start command)
- `start_failed` → `start_in_progress` (retry start)
- `start_failed` → `destroy_in_progress` (destroy deployment)
- `stop_failed` → `stop_in_progress` (retry stop)
- `stop_failed` → `destroy_in_progress` (destroy deployment)

### Invalid Transitions (should be rejected):
- Cannot start/stop during deployment: `deploy_in_progress`, `destroy_in_progress`
- Cannot start from non-stopped states (except `start_failed`)
- Cannot stop from invalid states (only allowed from `database_ready`, `database_connection_failed`, or `stop_failed`)
- Cannot start/stop destroyed deployments

### Workflow Integration:
- Commands should acquire deployment locks (like deploy/destroy)
- Status updates should follow the same pattern as existing operations
- Error handling should preserve state for debugging
- Progress logging should be implemented

## Implementation Phases

### Phase 1: Core Command Structure
1. **Command Registration**: Add `start` and `stop` commands to main `exasol` script routing
2. **CLI Interface**: Implement `lib/cmd_start.sh` and `lib/cmd_stop.sh` with consistent argument parsing
3. **Help Integration**: Add command help and usage examples

### Phase 2: State Management
1. **Status Constants**: Add new status values to `lib/state.sh`
2. **Transition Validation**: Implement state transition checks in command handlers
3. **Lock Integration**: Ensure commands respect existing locking mechanisms

### Phase 3: Database Operations
1. **Service Management**: First check Implement Ansible playbooks to start/stop Exasol services on all nodes
2. **Health Checks**: Add validation that database is properly started/stopped
3. **Error Handling**: Handle partial failures and cleanup scenarios

### Phase 4: Testing & Documentation
1. **Unit Tests**: Test state transitions, validation logic, and error conditions
2. **Integration Tests**: Test actual start/stop operations on test deployments
3. **Documentation**: Update README with start/stop command usage and status values
4. **IP Consistency Verification**: After stop/start cycles, verify that all configuration files (`inventory.ini`, `variables.auto.tfvars`, `INFO.txt`, Terraform state) and internal state references still point to the correct IP addresses

## Command Specifications

### `exasol start --deployment-dir <dir>`
- Validates deployment is in stoppable state
- Acquires deployment lock
- Sets status to `start_in_progress`
- Runs Ansible playbook to start Exasol services
- Validates database connectivity
- Sets final status to `database_ready` or `start_failed`

### `exasol stop --deployment-dir <dir>`
- Validates deployment is in stoppable state (`database_ready`, `database_connection_failed`, or `stop_failed`)
- Acquires deployment lock
- Sets status to `stop_in_progress`
- Runs Ansible playbook to stop Exasol services
- Sets final status to `stopped` or `stop_failed`

## Success Criteria

- `exasol start` and `exasol stop` commands work reliably
- Proper state transitions with validation
- Comprehensive error handling and logging
- Full unit test coverage including edge cases
- Added aws e2e tests for the new commands, extend the framework if needed. 
- Documentation updated with new commands and status values
- Integration with existing deployment workflow

## Example Usage

```bash
# Stop a running deployment
exasol stop --deployment-dir ./my-deployment

# Stop a deployment with connection issues
exasol stop --deployment-dir ./failed-deployment
# Works even if status is "database_connection_failed"

# Check status
exasol status --deployment-dir ./my-deployment
# Returns: {"status": "stopped", ...}

# Start the deployment again
exasol start --deployment-dir ./my-deployment

# Check status again
exasol status --deployment-dir ./my-deployment
# Returns: {"status": "database_ready", ...}

## Follow-up Todo: Implement Reboot Command

Add a new `exasol reboot --deployment-dir <dir>` command that performs a graceful stop followed by a start while reusing existing infrastructure. Requirements:
- Reuse the stop/start logic once both commands exist
- Acquire locks for the full reboot operation
- Preserve state transitions (`reboot_in_progress`, `reboot_failed`, etc.)
- Ensure IP addresses remain consistent before/after reboot across:
  - Terraform state and `.terraform` metadata
  - `inventory.ini`, `INFO.txt`, and `variables.auto.tfvars`
  - Any cached state/lock files
- Provide clear progress output (“Stopping…”, “Starting…”, “Validating IP consistency…”) and fail fast if discrepancies arise
- Verify that systemd services deployed by the c4 stack (e.g., `c4.service`, `c4_cloud_command.service`, `exasol-admin-ui.service`, `exasol-data-symlinks.service`) come back in the expected state after reboot. Collect their status via `systemctl` and ensure Admin UI messages in `journalctl` confirm a successful restart. If services fail, surface remediation steps in the reboot report.
```
