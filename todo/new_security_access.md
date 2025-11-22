# Security and Access Management

## Implement Cloud Permissions Analysis Command

Enhance the `exasol init` command to print in .permissions.json the needed permissions to deploy the infrastructure with the given arguments. The permissions for each option should be previously generated with helper script build/generate_permissions.h and stored for each cloud in lib/permissions/<cloud>/permission-for-the-specific-init-selected-tasks.json or similar. The command should return empty json if no permissions were generated before. An analysis of the different terraform templates for the specific option groups are needed before and displays the required cloud permissions for deployment, helping users configure their cloud accounts correctly.

### Phase 1: Tool Integration & Setup (Foundation Phase)

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

### Phase 2: Template Analysis Implementation (Core Development Phase)

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

### Phase 3: Command Implementation & Integration (CLI Development Phase)

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

### Phase 4: Testing & Documentation (Validation Phase)

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

### Phase 5: Build Integration (Release Phase)

1. **Build Script Integration**: Integrate permission generation into release build:
   - Pre-generate permission data during build process
   - Include permission data in release artifacts
   - Support both online pike analysis and offline cached data

2. **CI/CD Integration**: Add permission validation to CI pipeline:
   - Automated permission checking on template changes
   - Permission drift detection and alerts
   - Documentation auto-update on permission changes

### Success Criteria
- `exasol permissions` command works for all supported cloud providers
- Accurate permission analysis using pike tool with Docker/Podman fallback
- Multiple output formats (table, JSON, markdown)
- Comprehensive documentation of required permissions
- Integration with build process for automated permission updates
- Clear error messages when permissions are insufficient

### Example Usage
```bash
# Analyze permissions for a specific deployment
exasol permissions --deployment-dir ./my-aws-deployment

# Analyze permissions for a specific cloud provider
exasol permissions --cloud-provider aws --format json

# Get permissions in markdown format for documentation
exasol permissions --cloud-provider azure --format markdown
```

## Implement Public Hostname with SSL Certificates for All Cloud Providers

Create a comprehensive solution for exposing Exasol AdminUI and database ports with valid SSL certificates through public hostnames, with load balancer support where appropriate.

### Phase 1: Research & Analysis (Investigation Phase)

1. **Cloud Provider Capabilities Assessment**: For each cloud provider (AWS, Azure, GCP, Hetzner, DigitalOcean), research and document:
   - Load balancer services available (ALB/NLB for AWS, Azure Load Balancer, GCP Load Balancer, etc.)
   - SSL/TLS certificate management options (ACM for AWS, Key Vault for Azure, etc.)
   - DNS management capabilities
   - Static IP allocation options
   - Health check mechanisms

2. **Certificate Strategy Evaluation**: Evaluate options for each provider:
   - Provider-managed certificates (Let's Encrypt integration, managed certificates)
   - Self-signed certificates with custom CA
   - Third-party certificate providers
   - Certificate installation mechanisms on Exasol nodes

3. **Network Architecture Design**: Design optimal network setup for each provider:
   - Public subnet configuration
   - Security group/firewall rules for AdminUI (9090) and database ports
   - Load balancer health checks for Exasol services
   - DNS record management

### Phase 2: Implementation Planning (Design Phase)

1. **Unified Interface Design**: Design consistent Terraform variables and Ansible tasks that work across all providers:
   - `enable_public_hostname` (boolean)
   - `ssl_certificate_source` (enum: provider-managed, self-signed, custom)
   - `adminui_public_port` (default: 443)
   - `database_public_port` (default: 8563)

2. **Provider-Specific Modules**: Create provider-specific implementations:
   - AWS: ALB with ACM certificates
   - Azure: Load Balancer with Key Vault certificates
   - GCP: Load Balancer with managed certificates
   - Hetzner: Floating IPs with reverse proxy
   - DigitalOcean: Load Balancer with Let's Encrypt

3. **Certificate Management**: Implement certificate installation on Exasol nodes:
   - Generate self-signed certificates during deployment
   - Configure Exasol to use certificates via confd_client
   - Update Ansible playbooks to install certificates

### Phase 3: Implementation (Development Phase)

1. **Terraform Template Updates**: Update all provider templates to support public hostname configuration
2. **Ansible Playbook Updates**: Add certificate installation and configuration tasks
3. **Command Line Integration**: Add new CLI options to `exasol init` for enabling public access
4. **Testing & Validation**: Test certificate installation and public access for each provider

### Phase 4: Documentation & Deployment (Completion Phase)

1. **Update Documentation**: Add public hostname configuration to README and cloud-specific docs
2. **Create Examples**: Provide example commands for enabling public access
3. **Security Considerations**: Document security implications and best practices

### Success Criteria
- All cloud providers support public hostname with SSL certificates
- Consistent CLI interface across all providers
- Valid certificates installed and configured on Exasol nodes
- Load balancer support where available
- Comprehensive documentation with examples

### Note
Certificate installation on Exasol nodes will use: `ssh cos confd_client cert_update ca: '"{< /root/tls_ca}"' cert: '"{< /root/tls_cert}"' key: '"{< /root/tls_key}"' || true`

## Combined Implementation Strategy

### Phase 1: Unified Security Framework
1. **Common Security Variables**: Define shared variables for permissions and certificates
2. **Provider Capability Matrix**: Document security features across all providers
3. **Certificate Management Strategy**: Standardize certificate handling across providers

### Phase 2: Permissions Command Implementation
1. **Pike Integration**: Set up pike tool for permission analysis
2. **Template Scanning**: Implement scanning for all provider templates
3. **Command Development**: Build the permissions CLI command

### Phase 3: Public Access Implementation
1. **Load Balancer Setup**: Configure load balancers for each provider
2. **Certificate Installation**: Implement certificate management on Exasol nodes
3. **DNS Configuration**: Set up public hostnames and DNS records

### Phase 4: Integration and Testing
1. **Security Testing**: Test permissions analysis and certificate installation
2. **Cross-Provider Validation**: Ensure consistent behavior across providers
3. **Documentation**: Update all security-related documentation

### Benefits
- **Comprehensive Security Coverage**: Both permissions analysis and secure public access
- **Unified User Experience**: Consistent security configuration across providers
- **Automated Certificate Management**: SSL certificates handled automatically
- **Clear Permission Requirements**: Users know exactly what permissions are needed

### Success Criteria
- Permissions command provides accurate analysis for all providers
- Public hostname with SSL works on all supported cloud providers
- Certificates are properly installed and configured on Exasol nodes
- Load balancers provide high availability where supported
- Comprehensive security documentation for all features