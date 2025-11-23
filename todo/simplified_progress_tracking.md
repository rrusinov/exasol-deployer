# Simplified Progress Tracking System

## Objective
Replace the current line-count based progress tracking with a keyword-based system that:
- Works across all cloud providers without calibration
- Shows simple step progress (e.g., [01/10], [02/10])
- Removes ETA calculations
- Automatically detects current operation step based on sample log outputs for each operation.

## Current Issues
1. Line-count based tracking requires calibration per cloud provider
2. ETA calculations add complexity and require maintenance
3. Progress tracking changes needed for each new provider
4. Hard to maintain as operations evolve

## Proposed Solution

### Keyword-Based Step Detection
Instead of counting lines, detect steps by matching keywords/patterns in command output:
- Terraform/Tofu output patterns (e.g., "Creating...", "Provisioning...")
- Ansible task names and output
- Custom script log messages

### Step Definitions Per Operation
Define fixed steps for each operation that apply universally:

#### Deploy Operation Steps
1. Infrastructure planning
2. Network setup
3. Instance creation
4. Storage provisioning
5. Ansible connection setup
6. Exasol installation
7. Cluster configuration
8. Service startup
9. Health checks
10. Deployment validation

#### Stop Operation Steps
1. Stopping Exasol services
2. Verifying service shutdown
3. Powering off instances
4. Verification

#### Start Operation Steps
1. Powering on instances
2. Waiting for boot
3. Starting Exasol services
4. Health checks

#### Destroy Operation Steps
1. Infrastructure planning
2. Destroying instances
3. Destroying storage
4. Destroying network
5. Cleanup verification

## Implementation Plan

### Phase 1: Analysis (Steps 1-3)
- [ ] Analyze tmp/*.log files from 2-node libvirt deployment
- [ ] Extract all tofu/terraform output patterns
- [ ] Extract all ansible task patterns
- [ ] Document operation flow for each command

### Phase 2: Design (Step 4)
- [ ] Create keyword/regex patterns for each step
- [ ] Define step progression logic
- [ ] Handle missing/skipped steps gracefully
- [ ] Design fallback for unmatched output

### Phase 3: Step Definitions (Steps 5-8)
- [ ] Map deploy operation to keyword patterns
- [ ] Map stop operation to keyword patterns
- [ ] Map start operation to keyword patterns
- [ ] Map destroy operation to keyword patterns

### Phase 4: Implementation (Steps 9-12)
- [ ] Create new progress detection module
- [ ] Replace line-count tracking in progress.sh
- [ ] Remove ETA calculation code
- [ ] Update output format to [##/##]

### Phase 5: Testing (Steps 13-14)
- [ ] Test with libvirt provider
- [ ] Verify works with AWS/Azure/GCP/Hetzner without changes

## Technical Approach

### Progress Detection Module
```bash
# New file: lib/progress_keywords.sh

# Step definitions with keyword patterns
declare -A DEPLOY_STEPS=(
    [1]="Planning infrastructure|Initializing|terraform init"
    [2]="Creating network|VPC|subnet|network_interface"
    [3]="Creating instances|Creating VM|aws_instance|libvirt_domain"
    [4]="Creating storage|Creating volume|aws_ebs_volume|libvirt_volume"
    [5]="Generating inventory|SSH config|ansible"
    [6]="Installing Exasol|PLAY.*Setup|setup-exasol-cluster"
    [7]="Configuring cluster|TASK.*Configure|c4 conf"
    [8]="Starting services|c4.service|systemd"
    [9]="Health check|Verifying|connection test"
    [10]="Deployment complete|✓|SUCCESS"
)

detect_current_step() {
    local operation="$1"
    local log_line="$2"
    # Match log_line against step patterns
    # Return current step number
}
```

### Output Format
```
[01/10] Planning infrastructure...
[02/10] Creating network resources...
[03/10] Creating instances...
```

## Benefits
1. **No calibration needed** - Works across all providers
2. **Self-maintaining** - Keywords stable across provider changes
3. **Simple to understand** - Clear step progression
4. **Easy to extend** - Add new steps by adding patterns
5. **Robust** - Handles variations in output gracefully

## Files to Modify
- `lib/progress.sh` - Main progress tracking logic
- `lib/progress_keywords.sh` - New file for step definitions
- `lib/cmd_deploy.sh` - Remove line estimates
- `lib/cmd_stop.sh` - Remove line estimates
- `lib/cmd_start.sh` - Remove line estimates
- `lib/cmd_destroy.sh` - Remove line estimates

## Log Analysis TODO
1. Check `tmp/*.log` for libvirt 2-node deployment logs
2. Extract terraform/tofu output patterns
3. Extract ansible task patterns
4. Document actual operation flow
5. Identify stable keywords that appear in all providers
