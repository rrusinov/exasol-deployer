# Exoscale Cloud Setup Guide

This guide covers setting up credentials and permissions for deploying Exasol on Exoscale.

## Prerequisites

- Exoscale account with billing enabled
- Access to the Exoscale Console (https://portal.exoscale.com/)

## Optional: Install Exoscale CLI

The Exoscale CLI (`exo`) is optional but useful for:
- Running cleanup scripts (`scripts/cleanup-resources.sh`)
- Generating cloud resource reports (`scripts/generate-limits-report.sh`)
- Manual resource management and troubleshooting

### Installation Methods

**macOS (Homebrew)**
```bash
brew install exoscale/tap/exoscale-cli
```

**Linux (Direct Download)**
```bash
# Download v1.80.0 (recommended - v1.88.0 has API compatibility issues)
wget https://github.com/exoscale/cli/releases/download/v1.80.0/exoscale-cli_1.80.0_linux_amd64.tar.gz

# Extract and install
tar -xzf exoscale-cli_1.80.0_linux_amd64.tar.gz
sudo mv exo /usr/local/bin/
chmod +x /usr/local/bin/exo

# Verify installation
exo version  # Should show v1.80.0
```

**From Source (Go)**
```bash
go install github.com/exoscale/cli/cmd/exo@latest
```

### Configure CLI

After installation, configure with your API credentials. You need to create the initial config file manually:

```bash
# Create config directory and initial file
mkdir -p ~/.config/exoscale
cat > ~/.config/exoscale/exoscale.toml << 'EOF'
defaultaccount = "default"

[[accounts]]
name = "default"
account = ""
defaultzone = "ch-gva-2"
endpoint = "https://api.exoscale.com/v1"
key = "YOUR_API_KEY"
secret = "YOUR_API_SECRET"
EOF

# Replace YOUR_API_KEY and YOUR_API_SECRET with actual credentials
# Get these from the Exoscale Console (see step 1 below)

# Verify configuration
exo config show default
```

**To reset/clean the config:**
```bash
rm -rf ~/.config/exoscale
```

**Alternative**: Use environment variables (same as for deployer)
```bash
export EXOSCALE_API_KEY="your-api-key"
export EXOSCALE_API_SECRET="your-api-secret"
```

**Note**: The deployer works without the CLI tool installed. The CLI is only required for optional management scripts.

**Known Issue**: The exo CLI (v1.88.0) may have compatibility issues with Exoscale's v2 API endpoints when listing resources. If you encounter "Not Found" or "404" errors:
- Use `./exasol destroy` from your deployment directory instead of the cleanup script
- The Exoscale Terraform provider uses the v2 API directly and works correctly

For more information, see the [Exoscale CLI documentation](https://github.com/exoscale/cli).

## Quick Setup

### 1. Create API Credentials

1. **Log in to Exoscale Console**:
   - Go to https://portal.exoscale.com/
   - Sign in with your Exoscale account

2. **Navigate to API Keys**:
   - Click on your profile in the top right
   - Select "API Keys" from the dropdown menu

3. **Create New API Key**:
   - Click "Add API Key"
   - Enter a name (e.g., "exasol-deployer")
   - Select the required operations:
     - `compute` (for instances and security groups)
     - `block-storage` (for data volumes)
     - `ssh-key` (for SSH key management)
   - Click "Create"

4. **Save Credentials**:
   - Copy the API Key and Secret Key
   - Store them securely (you won't be able to see the secret again)

### 2. Configure Credentials

**Option A: Environment Variables (Recommended)**
```bash
export EXOSCALE_API_KEY="your-api-key"
export EXOSCALE_API_SECRET="your-api-secret"
```

**Option B: Credential Files**
```bash
# Create API key file
echo "your-api-key" > ~/.exoscale_api_key
chmod 600 ~/.exoscale_api_key

# Create API secret file
echo "your-api-secret" > ~/.exoscale_api_secret
chmod 600 ~/.exoscale_api_secret
```

**Option C: Command Line Flags**
```bash
./exasol init \
  --cloud-provider exoscale \
  --exoscale-api-key "your-api-key" \
  --exoscale-api-secret "your-api-secret" \
  --deployment-dir ./my-exoscale-deployment
```

### 3. Verify Setup

Test your credentials:
```bash
# Using environment variables
./exasol init \
  --cloud-provider exoscale \
  --deployment-dir ./test-deployment \
  --exoscale-zone ch-gva-2

# Check if initialization succeeds
ls -la ./test-deployment/
```

## Available Zones

Exoscale operates in multiple zones across Europe:

- **ch-gva-2** (Geneva, Switzerland) - Default
- **ch-dk-2** (Zurich, Switzerland)
- **de-fra-1** (Frankfurt, Germany)
- **de-muc-1** (Munich, Germany)
- **at-vie-1** (Vienna, Austria)
- **bg-sof-1** (Sofia, Bulgaria)

## Instance Types

Common Exoscale instance types suitable for Exasol:

### Standard Instances
- **standard.medium** - 2 vCPU, 4GB RAM
- **standard.large** - 4 vCPU, 8GB RAM (default)
- **standard.xlarge** - 8 vCPU, 16GB RAM
- **standard.2xlarge** - 16 vCPU, 32GB RAM
- **standard.4xlarge** - 32 vCPU, 64GB RAM

### High Memory Instances
- **highmem.large** - 4 vCPU, 32GB RAM
- **highmem.xlarge** - 8 vCPU, 64GB RAM
- **highmem.2xlarge** - 16 vCPU, 128GB RAM

### CPU Optimized Instances
- **cpu.large** - 4 vCPU, 4GB RAM
- **cpu.xlarge** - 8 vCPU, 8GB RAM
- **cpu.2xlarge** - 16 vCPU, 16GB RAM

## Deployment Examples

### Single Node Development
```bash
./exasol init \
  --cloud-provider exoscale \
  --deployment-dir ./exoscale-dev \
  --exoscale-zone ch-gva-2 \
  --instance-type standard.large \
  --data-volume-size 100
```

### Multi-Node Production Cluster
```bash
./exasol init \
  --cloud-provider exoscale \
  --deployment-dir ./exoscale-prod \
  --exoscale-zone ch-gva-2 \
  --cluster-size 4 \
  --instance-type standard.4xlarge \
  --data-volume-size 500 \
  --data-volumes-per-node 2
```

### High Memory Configuration
```bash
./exasol init \
  --cloud-provider exoscale \
  --deployment-dir ./exoscale-highmem \
  --exoscale-zone de-fra-1 \
  --cluster-size 3 \
  --instance-type highmem.2xlarge \
  --data-volume-size 1000
```

## Cost Optimization

### Instance Pricing
- Exoscale uses hourly billing
- No long-term commitments required
- Pricing varies by zone (Geneva typically most expensive)

### Storage Costs
- Block storage is billed separately from compute
- Consider data volume size vs. performance requirements
- Multiple smaller volumes can provide better I/O performance

### Network Costs
- Inbound traffic is free
- Outbound traffic is charged per GB
- Internal traffic between instances in same zone is free

## Networking

### Security Groups
The deployer automatically creates security groups with:
- SSH access (port 22) from allowed CIDR
- Exasol database port (8563) from allowed CIDR
- Admin UI HTTPS (port 443) from allowed CIDR
- Full internal communication between cluster nodes

### Private Networking
- All instances get both public and private IP addresses
- Internal cluster communication uses private IPs
- Private network is automatically configured

## Troubleshooting

### Common Issues

**API Authentication Errors**:
```
Error: authentication failed
```
- Verify API key and secret are correct
- Check that API key has required permissions
- Ensure credentials are not expired

**Zone Availability**:
```
Error: instance type not available in zone
```
- Try a different zone (e.g., ch-dk-2 instead of ch-gva-2)
- Check instance type availability in Exoscale console
- Use a different instance type

**Quota Limits**:
```
Error: quota exceeded
```
- Check your account limits in Exoscale console
- Contact Exoscale support to increase quotas
- Use smaller instance types or fewer nodes

### Getting Help

1. **Exoscale Documentation**: https://community.exoscale.com/
2. **Support Portal**: https://portal.exoscale.com/support
3. **Community Forum**: https://community.exoscale.com/

## Security Best Practices

1. **API Key Management**:
   - Use environment variables in production
   - Rotate API keys regularly
   - Limit API key permissions to minimum required

2. **Network Security**:
   - Restrict `--allowed-cidr` to your IP ranges
   - Use VPN or bastion hosts for production access
   - Enable logging and monitoring

3. **Instance Security**:
   - Keep OS and software updated
   - Use strong passwords (auto-generated by default)
   - Monitor access logs

## Power Control

Exoscale supports automatic power control:
- **Start/Stop**: Automatic via cloud API
- **Cost Savings**: Stopped instances only charge for storage
- **Resume Time**: Typically 30-60 seconds to start

Use the deployer's start/stop commands:
```bash
# Stop cluster (saves costs)
./exasol stop --deployment-dir ./my-deployment

# Start cluster
./exasol start --deployment-dir ./my-deployment
```

## Known Issues

### Exoscale CLI Version Compatibility

**Issue**: The `exo` CLI v1.88.0 has API compatibility issues.

**Root Cause**: Version 1.88.0 migrated to the egoscale v3 library, but Exoscale's API only provides v2 endpoints (https://api-{zone}.exoscale.com/v2). This causes CLI commands to fail with 404 errors when trying to access non-existent v3 endpoints.

**Solution**: Use v1.80.0 (October 2024) instead. The installation instructions above have been updated to use this version.

**Workaround for cleanup**: If you accidentally installed v1.88.0, you can still clean up resources using:
```bash
# From deployment directory
./exasol destroy --deployment-dir ./my-deployment
```

The Terraform provider works correctly (it uses the v2 API) so deployment/destroy operations through the deployer are not affected.

## Next Steps

After setup:
1. Deploy your first cluster: `./exasol deploy --deployment-dir ./my-deployment`
2. Monitor costs in the Exoscale console
3. Set up monitoring and alerting
4. Configure backups for production workloads
