# Improve Network Connectivity Handling for Stable Deployments

## Issue
Deployments occasionally fail due to network connectivity issues during the Ansible configuration phase, where instances are running but not yet reachable via SSH. This causes deployment failures that could be resolved with better handling.

## Goals
1. Create a more robust deployment process that handles network initialization delays
2. Provide better error messages and user guidance for connectivity issues
3. Implement automatic retries with backoff for transient network failures

## Implementation Plan

### Phase 1: Pre-Flight Network Verification
1. **Add connectivity verification step** after instance creation but before Ansible run
   - Implement ping/SSH connectivity test with timeout and retry logic
   - Add progress indication during wait periods
   - Set reasonable timeout (3-5 minutes for network initialization)

2. **Enhance instance readiness checks**
   - Verify SSH daemon is responding before attempting Ansible connection
   - Add health check endpoint if possible
   - Implement progressive wait with status updates

### Phase 2: Improved Error Handling
1. **Add specific error messages** for different failure scenarios:
   - Network connectivity issues
   - SSH key problems
   - Security group misconfigurations
   - Instance not running

2. **Implement automatic retry logic** with exponential backoff:
   - For SSH connection failures
   - For temporary network issues
   - Configurable retry count and timeout values

3. **Add diagnostic information** to error messages:
   - Show which specific check failed
   - Provide troubleshooting suggestions
   - Include relevant instance and network details

### Phase 3: User Experience Improvements
1. **Add progress indicators** during network wait periods:
   - Show elapsed time and timeout
   - Provide status updates
   - Indicate what is being checked

2. **Add diagnostic command** for connectivity testing:
   - `exasol diagnose --deployment-dir <dir>` command
   - Verify all components (instances, network, SSH, security groups)
   - Provide actionable feedback

### Phase 4: Documentation and Examples
1. **Update documentation** with:
   - Common network troubleshooting steps
   - Expected wait times for different cloud providers
   - Security group requirements verification
   - VPC/subnet configuration guidance

2. **Add examples** of:
   - Using the new diagnostic command
   - Interpreting connectivity error messages
   - Manual verification steps

## Success Criteria
- Deployments succeed even when instances take longer to initialize network services
- Clear error messages guide users to resolve connectivity issues
- Automatic retries handle transient network failures
- Diagnostic tools help identify root causes quickly
- Documentation provides sufficient guidance for common issues

## Example Usage
```bash
# Deployment automatically handles network delays
exasol deploy --deployment-dir ./my-deployment
# Output shows progress during network wait

# Diagnose connectivity issues
exasol diagnose --deployment-dir <dir>
# Output shows detailed connectivity status and suggestions
```

## Implementation Priority
1. Add basic connectivity verification with timeout
2. Implement retry logic for SSH connections
3. Add progress indicators and better error messages
4. Create diagnostic command
5. Enhance documentation with troubleshooting guide