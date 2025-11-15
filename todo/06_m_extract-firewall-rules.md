# Extract Common Firewall Rules into Shared Templates

## Problem
Each cloud provider reimplements the same firewall port definitions (SSH 22, Database 8563, Admin UI 8443, etc.) but with different syntax, leading to code duplication and maintenance overhead.

## Solution
Create shared firewall rule definitions that can be referenced by all providers.

## Implementation Steps
- Extract common port definitions into terraform-common
- Create standardized firewall rule structure
- Update each provider to reference shared definitions
- Maintain provider-specific syntax adapters

## Files to Modify
- templates/terraform-common/common-firewall.tf (new)
- templates/terraform-aws/main.tf (update)
- templates/terraform-azure/main.tf (update)
- templates/terraform-gcp/main.tf (update)
- templates/terraform-hetzner/main.tf (update)
- templates/terraform-digitalocean/main.tf (update)

## Priority
High

## Estimated Time
3-5 days
