# Infrastructure Abstractions

## Extract Common Firewall Rules into Shared Templates

### Problem
Each cloud provider reimplements the same firewall port definitions (SSH 22, Database 8563, Admin UI 8443, etc.) but with different syntax, leading to code duplication and maintenance overhead.

### Solution
Create shared firewall rule definitions that can be referenced by all providers.

### Implementation Steps
- Extract common port definitions into terraform-common
- Create standardized firewall rule structure
- Update each provider to reference shared definitions
- Maintain provider-specific syntax adapters

### Files to Modify
- templates/terraform-common/common-firewall.tf (new)
- templates/terraform-aws/main.tf (update)
- templates/terraform-azure/main.tf (update)
- templates/terraform-gcp/main.tf (update)
- templates/terraform-hetzner/main.tf (update)
- templates/terraform-digitalocean/main.tf (update)

### Priority
High

### Estimated Time
3-5 days

## Create Provider Abstraction Layer for Volume Management

### Problem
Volume attachment logic is similar across providers but uses provider-specific APIs, leading to duplicated patterns.

### Solution
Create abstraction layer for volume management operations.

### Implementation Steps
- Define common volume interface in terraform-common
- Create provider-specific implementations
- Standardize volume attachment patterns
- Extract common volume validation logic

### Files to Modify
- templates/terraform-common/volume-interface.tf (new)
- Provider-specific volume implementations (update)
- Common validation functions (extract)

### Priority
High

### Estimated Time
4-6 days

## Combined Implementation Plan

### Phase 1: Common Firewall Rules
1. Create `templates/terraform-common/common-firewall.tf` with standardized port definitions
2. Define common variables for firewall rules
3. Implement provider-specific adapters for syntax differences

### Phase 2: Volume Management Abstraction
1. Create `templates/terraform-common/volume-interface.tf` with common volume operations
2. Define standardized volume attachment patterns
3. Implement provider-specific volume implementations
4. Extract common validation logic

### Phase 3: Integration and Testing
1. Update all provider templates to use shared abstractions
2. Test firewall rules across all providers
3. Test volume management across all providers
4. Validate backward compatibility

### Benefits
- **Reduced Code Duplication**: Common patterns extracted to shared templates
- **Easier Maintenance**: Changes to common rules apply to all providers
- **Consistency**: Standardized interfaces across providers
- **Faster Development**: New providers can reuse existing abstractions

### Success Criteria
- All providers use shared firewall rule definitions
- Volume management abstracted with provider-specific implementations
- No breaking changes to existing deployments
- Comprehensive testing across all providers