# Implement E2E Tests for All Providers

## Problem
Currently only AWS has basic E2E tests; other providers (Azure, GCP, Hetzner, DigitalOcean) are untested.

## Solution
Create comprehensive E2E test configurations for each provider.

## Implementation Steps
- Create provider-specific test configuration files
- Implement provider authentication setup
- Define test parameters for each provider
- Add validation checks for provider-specific resources
- Configure parallel test execution

## Files to Create
- tests/e2e/configs/azure-basic.json
- tests/e2e/configs/gcp-basic.json
- tests/e2e/configs/hetzner-basic.json
- tests/e2e/configs/digitalocean-basic.json

## Priority
High

## Estimated Time
2-3 weeks
