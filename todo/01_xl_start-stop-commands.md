# Implement Start/Stop Commands for Exasol Deployments

Add `exasol start` and `exasol stop` commands to allow stopping and starting Exasol database services without terminating cloud instances. This enables cost optimization by stopping database services when not needed while preserving the infrastructure.

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
1. **Service Management**: Implement Ansible playbooks to start/stop Exasol services on all nodes
2. **Health Checks**: Add validation that database is properly started/stopped
3. **Error Handling**: Handle partial failures and cleanup scenarios

### Phase 4: Testing & Documentation
1. **Unit Tests**: Test state transitions, validation logic, and error conditions
2. **Integration Tests**: Test actual start/stop operations on test deployments
3. **Documentation**: Update README with start/stop command usage and status values

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
- Full test coverage including edge cases
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
```