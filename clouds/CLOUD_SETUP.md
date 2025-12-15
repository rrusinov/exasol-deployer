# Cloud Provider Setup Guide

This guide provides instructions for setting up credentials and accounts for each supported cloud provider to deploy Exasol using this deployer tool.

## Prerequisites

**Option 1: Zero Dependencies (Recommended)**
Install with all dependencies bundled:
```bash
curl -fsSL https://xsol.short.gy/sh | bash -s -- --install-dependencies --yes
```

**Option 2: System Installation**
Ensure you have OpenTofu, Ansible, Python, and jq installed on your system.

## Permission Requirements

Before setting up cloud credentials, you can check the required permissions for your chosen cloud provider:

```bash
# Check required permissions for a specific provider
./exasol init --cloud-provider aws --show-permissions
./exasol init --cloud-provider azure --show-permissions
./exasol init --cloud-provider gcp --show-permissions
```

**Note:** The permission files are generated statically from the Terraform templates. If permissions are not available, you can generate them by running:

```bash
# Generate permission tables for all providers
./scripts/generate-permissions.sh
```

This requires either the [pike](https://github.com/JamesWoolfenden/pike) tool installed locally, or Docker/Podman to run the pike container.

## Supported Cloud Providers

The Exasol Cloud Deployer supports the following cloud providers:

- **[AWS (Amazon Web Services)](CLOUD_SETUP_AWS.md)** - Most feature-complete, includes spot instances
- **[Azure (Microsoft Azure)](CLOUD_SETUP_AZURE.md)** - Full support with spot instances
- **[GCP (Google Cloud Platform)](CLOUD_SETUP_GCP.md)** - Full support with preemptible instances
- **[Hetzner Cloud](CLOUD_SETUP_HETZNER.md)** - Cost-effective European provider
- **[DigitalOcean](CLOUD_SETUP_DIGITALOCEAN.md)** - Simple and affordable cloud provider
- **[Exoscale](CLOUD_SETUP_EXOSCALE.md)** - European cloud provider with automatic power control
- **[Libvirt/KVM](CLOUD_SETUP_LIBVIRT.md)** - Local development and testing with KVM virtualization

## Quick Start by Provider

### AWS
```bash
# Configure AWS credentials
mkdir -p ~/.aws
cat > ~/.aws/credentials <<EOF
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
EOF

# Initialize deployment
./exasol init --cloud-provider aws --deployment-dir ./my-aws-deployment
```

See [detailed AWS setup instructions](CLOUD_SETUP_AWS.md).

### Azure
```bash
# Login to Azure and capture subscription ID
az login
az account show --query id -o tsv

# Create service principal credentials file (default path the deployer reads)
az ad sp create-for-rbac \
  --name "exasol-deployer" \
  --role contributor \
  --scopes /subscriptions/<subscription-id> \
  > ~/.azure_credentials
chmod 600 ~/.azure_credentials

# Initialize deployment (reads ~/.azure_credentials automatically)
./exasol init \
  --cloud-provider azure \
  --azure-subscription <subscription-id> \
  --deployment-dir ./my-azure-deployment
```

See [detailed Azure setup instructions](CLOUD_SETUP_AZURE.md).

### GCP
```bash
# Login to GCP
gcloud auth application-default login

# Get project ID
gcloud config get-value project

# Initialize deployment
./exasol init \
  --cloud-provider gcp \
  --gcp-project <project-id> \
  --deployment-dir ./my-gcp-deployment
```

See [detailed GCP setup instructions](CLOUD_SETUP_GCP.md).

### Hetzner Cloud
```bash
# Get API token from https://console.hetzner.cloud/

# Initialize deployment
./exasol init \
  --cloud-provider hetzner \
  --hetzner-token <your-token> \
  --deployment-dir ./my-hetzner-deployment
```

See [detailed Hetzner setup instructions](CLOUD_SETUP_HETZNER.md).

### DigitalOcean
```bash
# Get API token from https://cloud.digitalocean.com/account/api/tokens

# Initialize deployment
./exasol init \
  --cloud-provider digitalocean \
  --digitalocean-token <your-token> \
  --deployment-dir ./my-do-deployment
```

See [detailed DigitalOcean setup instructions](CLOUD_SETUP_DIGITALOCEAN.md).

### Exoscale
```bash
# Get API credentials from https://portal.exoscale.com/

# Initialize deployment
./exasol init \
  --cloud-provider exoscale \
  --exoscale-api-key <your-api-key> \
  --exoscale-api-secret <your-api-secret> \
  --deployment-dir ./my-exoscale-deployment
```

See [detailed Exoscale setup instructions](CLOUD_SETUP_EXOSCALE.md).

## Common Configuration Options

All cloud providers support these common options:

| Flag | Description | Default |
|------|-------------|---------|
| `--cloud-provider` | Cloud provider name (required) | - |
| `--deployment-dir` | Directory for deployment files | `.` |
| `--db-version` | Database version | Latest available |
| `--cluster-size` | Number of nodes | `1` |
| `--instance-type` | Instance/VM type | Auto-detected from version |
| `--data-volume-size` | Data volume size in GB | `100` |
| `--data-volumes-per-node` | Data volumes per node | `1` |
| `--root-volume-size` | Root volume size in GB | `50` |
| `--db-password` | Database password | Random (16 chars) |
| `--adminui-password` | Admin UI password | Random (16 chars) |
| `--host-password` | Host OS password for the `exasol` user | Random (16 chars) |
| `--owner` | Owner tag for resources | `exasol-deployer` |
| `--allowed-cidr` | CIDR for access control | `0.0.0.0/0` |

## Feature Comparison

| Feature | AWS | Azure | GCP | Hetzner | DigitalOcean | Exoscale | libvirt |
|---------|-----|-------|-----|---------|--------------|----------|---------|
| Spot/Preemptible Instances | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | N/A |
| Automatic Power Control | ✅ | ✅ | ✅ | ❌ Manual | ❌ Manual | ✅ | ❌ Manual |
| Multiple Instance Types | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Custom VPC/Network | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Multiple Regions | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| ARM64 Support | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| Multiple Data Volumes | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

## Security Best Practices

### Network Security
- **Restrict CIDR blocks**: Always use `--allowed-cidr` to limit access to your IP addresses
  ```bash
  --allowed-cidr "203.0.113.0/24"  # Your office network
  ```
- **Avoid 0.0.0.0/0**: The default allows access from anywhere - only use for testing

### Credential Management
- **Never commit credentials**: Keep API tokens and passwords out of version control
- **Use environment variables/token files**: Export credentials instead of hardcoding. When `--hetzner-token`, `--digitalocean-token`, or `--exoscale-api-key`/`--exoscale-api-secret` are omitted, `exasol init` will try environment variables first and then credential files.
  ```bash
  export HETZNER_TOKEN="your-token"
  export EXOSCALE_API_KEY="your-key"
  export EXOSCALE_API_SECRET="your-secret"
  echo "$HETZNER_TOKEN" > ~/.hetzner_token
  echo "$EXOSCALE_API_KEY" > ~/.exoscale_api_key
  echo "$EXOSCALE_API_SECRET" > ~/.exoscale_api_secret
  ./exasol init --cloud-provider hetzner  # uses env/file automatically
  ./exasol init --cloud-provider exoscale  # uses env/file automatically
  ```
- **Host OS password**: The `host_password` for the `exasol` user is stored in `.credentials.json`. Retrieve it with `cat .credentials.json | jq -r '.host_password'` and rotate it regularly.
- **Rotate credentials regularly**: Update API tokens and passwords periodically
- **Use IAM roles when possible**: Especially for AWS/Azure/GCP

### File Permissions
The deployer automatically sets secure permissions on sensitive files:
- `.credentials.json` - chmod 600 (only owner can read/write)
- `exasol-key.pem` - chmod 400 (only owner can read)

Always verify these permissions remain secure.

## Cost Optimization

### Spot/Preemptible Instances
Save up to 70% using spot instances (AWS, Azure, GCP):
```bash
./exasol init \
  --cloud-provider aws \
  --aws-spot-instance \
  --deployment-dir ./spot-deployment
```

**Note**: Spot instances can be interrupted - only suitable for development/testing.

### Right-sizing
- Start with smaller instance types for testing
- Use `--cluster-size 1` for development
- Reduce `--data-volume-size` if you don't need large storage

### Resource Tagging
Use `--owner` to track costs by team:
```bash
./exasol init --owner "data-team-dev" ...
```

## Troubleshooting

### Authentication Errors

**AWS**: "Unable to locate credentials"
```bash
# Verify credentials file exists
cat ~/.aws/credentials

# Test with OpenTofu
cd /tmp && tofu init
```

**Azure**: "Failed to authenticate"
```bash
# Re-login
az login
az account show
```

**GCP**: "Application default credentials not found"
```bash
# Set up application default credentials
gcloud auth application-default login
```

**Hetzner/DigitalOcean/Exoscale**: "Invalid API token/credentials"
- Verify token/credentials are not expired
- Check token has correct permissions
- Generate new credentials from web console

### Network/Connectivity Issues
- Verify the cloud provider's API is accessible
- Check firewall rules on your local machine
- Ensure no VPN interfering with API calls

### Quota/Limit Errors
- Check your account limits in the cloud provider console
- Request quota increases if needed
- Try a different region with available capacity

## Next Steps

After setting up your cloud provider credentials:

1. **List available versions**:
   ```bash
   ./exasol init --list-versions
   ```
   (Shows availability and CPU architecture for each version)

2. **Initialize deployment**:
   ```bash
   ./exasol init --cloud-provider <provider> --deployment-dir ./my-deployment
   ```

3. **Review configuration**:
   ```bash
   cat ./my-deployment/variables.auto.tfvars
   ```

4. **Deploy**:
   ```bash
   ./exasol deploy --deployment-dir ./my-deployment
   ```

5. **Check status**:
   ```bash
   ./exasol status --deployment-dir ./my-deployment
   ```

For more information, see the [main README](../README.md).
