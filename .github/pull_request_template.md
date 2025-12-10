# Pull Request

## Summary

<!-- Provide a brief summary of the changes in this PR -->

## Type of Change

<!-- Mark the relevant option with an "x" -->

- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Code refactoring (no functional changes)
- [ ] Performance improvement
- [ ] Test coverage improvement
- [ ] CI/CD pipeline changes

## Related Issues

<!-- Link to related issues using keywords like "Closes #123" or "Fixes #456" -->

- Closes #
- Related to #

## Changes Made

<!-- Describe the changes made in detail -->

### Core Changes
- 
- 
- 

### Files Modified
- 
- 
- 

## Cloud Provider Impact

<!-- Mark all cloud providers affected by this change -->

- [ ] AWS
- [ ] Azure
- [ ] GCP
- [ ] Hetzner Cloud
- [ ] DigitalOcean
- [ ] libvirt/KVM
- [ ] All providers
- [ ] Provider-agnostic change

## Testing

### Test Coverage

<!-- Describe the testing performed -->

- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] E2E tests added/updated
- [ ] Manual testing performed

### Test Results

<!-- Provide details about test execution -->

```bash
# Unit tests
./tests/run_tests.sh
# Result: 

# Shell linting
find ./lib -type f -name '*.sh' -print0 | xargs -0 shellcheck
# Result: 

# E2E tests (manual execution for critical changes only)
# Note: E2E tests are expensive and should only be run manually for:
# - Major releases, new cloud providers, or core deployment changes
./tests/run_e2e.sh --provider <provider>
# Result: 
```

### Manual Testing

<!-- Describe manual testing performed -->

**Test Environment:**
- OS: 
- Cloud Provider: 
- Database Version: 
- Cluster Size: 

**Test Scenarios:**
1. 
2. 
3. 

**Results:**
- [ ] All test scenarios passed
- [ ] Some scenarios failed (explain below)

## Breaking Changes

<!-- If this is a breaking change, describe the impact and migration path -->

### Impact
- 

### Migration Guide
- 

### Backward Compatibility
- [ ] Fully backward compatible
- [ ] Backward compatible with deprecation warnings
- [ ] Breaking change (requires user action)

## Documentation

<!-- Mark all documentation that has been updated -->

- [ ] README.md updated
- [ ] Cloud setup guides updated (clouds/)
- [ ] Contributing guidelines updated
- [ ] Code comments added/updated
- [ ] Script documentation updated (scripts/README.md)
- [ ] Template documentation updated (templates/README.md)
- [ ] No documentation changes needed

## Security Considerations

<!-- Address any security implications -->

- [ ] No security implications
- [ ] Security review completed
- [ ] Credentials handling reviewed
- [ ] Network security reviewed
- [ ] Access control reviewed

**Security Notes:**
<!-- Describe any security considerations or changes -->

## Performance Impact

<!-- Describe any performance implications -->

- [ ] No performance impact
- [ ] Performance improvement
- [ ] Potential performance regression (explain below)

**Performance Notes:**
<!-- Describe performance changes or considerations -->

## Deployment Considerations

<!-- Consider impact on existing deployments -->

- [ ] No impact on existing deployments
- [ ] Requires redeployment for full benefit
- [ ] May affect existing deployments (explain below)

**Deployment Notes:**
<!-- Describe any deployment considerations -->

## Checklist

### Code Quality

- [ ] Code follows project style guidelines
- [ ] Self-review of code completed
- [ ] Code is properly commented
- [ ] No debugging code or console logs left
- [ ] Error handling is appropriate
- [ ] Resource cleanup is handled properly

### Testing

- [ ] All existing tests pass
- [ ] New tests cover the changes
- [ ] Tests are properly documented
- [ ] Edge cases are covered
- [ ] Error conditions are tested

### Documentation

- [ ] Documentation is updated and accurate
- [ ] Examples are provided where appropriate
- [ ] Breaking changes are documented
- [ ] Migration guide provided (if needed)

### Security and Compliance

- [ ] No sensitive information exposed
- [ ] Credentials are handled securely
- [ ] Input validation is appropriate
- [ ] Security best practices followed

### Review Readiness

- [ ] PR title is clear and descriptive
- [ ] PR description is complete
- [ ] All required sections are filled out
- [ ] Ready for maintainer review

## Additional Notes

<!-- Any additional information for reviewers -->

## Screenshots (if applicable)

<!-- Include screenshots for UI changes or visual improvements -->

## Reviewer Notes

<!-- Specific areas where you'd like reviewer focus -->

**Please pay special attention to:**
- 
- 
- 

**Questions for reviewers:**
- 
- 
- 