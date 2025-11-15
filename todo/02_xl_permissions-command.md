# Implement Cloud Permissions Analysis Command

Enhance the  `exasol init` command to print in .permissions.json  the needed permisions to deploy the infrastructure with the giffen arguments. The permissions for each option should be previously generated  with helper script build/generate_permissions.h and stored for each cloud in lib/permissions/<cloud>/permission-for-the-specific-init-selected-tasks.json or similar. The command should return empty json if no permissions were generated before. An analyzes of the different terraform templates for the specific option groups are needeb before and displays the required cloud permissions for deployment, helping users configure their cloud accounts correctly.

## Phase 1: Tool Integration & Setup (Foundation Phase)

1. **Pike Tool Integration**: Integrate the pike tool (https://github.com/JamesWoolfenden/pike) for permission analysis:
   - Add pike as a build dependency or runtime download
   - Support both Docker and Podman execution environments
   - Implement fallback mechanisms for different container runtimes
   - Handle pike installation and version management

2. **Command Structure Design**: Design the CLI interface for the permissions command:
   - `exasol permissions [--deployment-dir <dir>] [--cloud-provider <provider>] [--format json|table]`
   - Default to analyzing all providers if no specific provider given
   - Support both deployment-specific analysis and general template analysis

3. **Permission Data Structure**: Define the output format for permissions:
   - JSON structure with categorized permissions (compute, networking, storage, etc.)
   - Human-readable table format for CLI display
   - Include permission descriptions and rationale

## Phase 2: Template Analysis Implementation (Core Development Phase)

1. **Terraform Template Scanning**: Implement template analysis for each cloud provider:
   - AWS: Scan EC2, VPC, EBS, IAM, ELB permissions from terraform-aws/ templates
   - Azure: Scan VM, Network, Storage, Resource Group permissions from terraform-azure/
   - GCP: Scan Compute, Network, Storage permissions from terraform-gcp/
   - Hetzner: Scan Server, Network, Volume permissions from terraform-hetzner/
   - DigitalOcean: Scan Droplet, Network, Volume permissions from terraform-digitalocean/

2. **Permission Categorization**: Group permissions by service and operation type:
   - Compute resources (instances, VMs, droplets)
   - Networking (VPC, subnets, security groups, firewalls)
   - Storage (volumes, disks, buckets)
   - Load balancing and DNS (where applicable)
   - Identity and access management

3. **Dynamic Analysis**: Implement real-time permission analysis:
   - Use pike to scan actual Terraform configurations
   - Parse terraform plan output for required permissions
   - Cross-reference with provider documentation for accuracy

## Phase 3: Command Implementation & Integration (CLI Development Phase)

1. **Command Handler Creation**: Create `lib/cmd_permissions.sh` with:
   - Argument parsing for deployment directory and cloud provider
   - Container runtime detection (Docker/Podman)
   - Pike execution and output parsing
   - Error handling for missing tools or failed analysis

2. **Output Formatting**: Implement multiple output formats:
   - Table format for human-readable CLI output
   - JSON format for programmatic consumption
   - Markdown format for documentation generation

3. **Main Script Integration**: Add permissions command to main exasol script:
   - Register new command in command routing
   - Add help text and usage examples
   - Handle global flags (--log-level, etc.)

## Phase 4: Testing & Documentation (Validation Phase)

1. **Unit Testing**: Create comprehensive tests for permission analysis:
   - Test pike tool integration and fallback mechanisms
   - Validate permission categorization for each provider
   - Test output formatting in different formats
   - Mock pike output for consistent testing

2. **Integration Testing**: Test with real deployment directories:
   - Verify analysis works with initialized deployments
   - Test cross-provider permission differences
   - Validate accuracy against cloud provider documentation

3. **Documentation Updates**: Update project documentation:
   - Add permissions command to README with examples
   - Document permission requirements for each cloud provider
   - Create troubleshooting guide for permission issues

## Phase 5: Build Integration (Release Phase)

1. **Build Script Integration**: Integrate permission generation into release build:
   - Pre-generate permission data during build process
   - Include permission data in release artifacts
   - Support both online pike analysis and offline cached data

2. **CI/CD Integration**: Add permission validation to CI pipeline:
   - Automated permission checking on template changes
   - Permission drift detection and alerts
   - Documentation auto-update on permission changes

## Success Criteria

- `exasol permissions` command works for all supported cloud providers
- Accurate permission analysis using pike tool with Docker/Podman fallback
- Multiple output formats (table, JSON, markdown)
- Comprehensive documentation of required permissions
- Integration with build process for automated permission updates
- Clear error messages when permissions are insufficient

## Example Usage

```bash
# Analyze permissions for a specific deployment
exasol permissions --deployment-dir ./my-aws-deployment

# Analyze permissions for a specific cloud provider
exasol permissions --cloud-provider aws --format json

# Get permissions in markdown format for documentation
exasol permissions --cloud-provider azure --format markdown
```