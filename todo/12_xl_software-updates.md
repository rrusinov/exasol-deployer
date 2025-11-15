# Implement Software Updates, Deploying New Exasol Version

Add functionality to update Exasol software to a new version without redeploying the entire infrastructure. This enables seamless upgrades while preserving data and configuration.

## Requirements

- Support updating Exasol from one version to another
- Preserve existing data and configurations
- Minimal downtime during update process
- Rollback capability in case of update failure
- Integration with existing deployment and state management

## Implementation Phases

### Phase 1: Update Command Structure
1. Add `exasol update` command to main script
2. Implement `lib/cmd_update.sh` with version specification
3. Add version validation and compatibility checks

### Phase 2: Update Logic
1. Download new Exasol version packages
2. Backup current configuration and data
3. Stop services gracefully
4. Apply update via Ansible playbooks
5. Restart services and validate

### Phase 3: Testing & Documentation
1. Unit tests for update logic
2. Integration tests on test deployments
3. Update README with update command usage</content>
<parameter name="filePath">todo/12_xl_software-updates.md