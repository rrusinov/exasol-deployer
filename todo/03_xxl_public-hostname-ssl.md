# Implement Public Hostname with SSL Certificates for All Cloud Providers

Create a comprehensive solution for exposing Exasol AdminUI and database ports with valid SSL certificates through public hostnames, with load balancer support where appropriate.

## Phase 1: Research & Analysis (Investigation Phase)

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

## Phase 2: Implementation Planning (Design Phase)

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

## Phase 3: Implementation (Development Phase)

1. **Terraform Template Updates**: Update all provider templates to support public hostname configuration
2. **Ansible Playbook Updates**: Add certificate installation and configuration tasks
3. **Command Line Integration**: Add new CLI options to `exasol init` for enabling public access
4. **Testing & Validation**: Test certificate installation and public access for each provider

## Phase 4: Documentation & Deployment (Completion Phase)

1. **Update Documentation**: Add public hostname configuration to README and cloud-specific docs
2. **Create Examples**: Provide example commands for enabling public access
3. **Security Considerations**: Document security implications and best practices

## Success Criteria

- All cloud providers support public hostname with SSL certificates
- Consistent CLI interface across all providers
- Valid certificates installed and configured on Exasol nodes
- Load balancer support where available
- Comprehensive documentation with examples

## Note

Certificate installation on Exasol nodes will use: `ssh cos confd_client cert_update ca: '"{< /root/tls_ca}"' cert: '"{< /root/tls_cert}"' key: '"{< /root/tls_key}"' || true`