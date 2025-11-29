# Azure (Microsoft Azure) Setup Guide

This guide provides detailed instructions for setting up Azure credentials and deploying Exasol on Microsoft Azure.

## Prerequisites

- Azure account with active subscription
- Azure CLI installed (`az`)
- OpenTofu (or Terraform) installed
- Ansible installed
- jq installed

## Step 1: Create Azure Account

If you don't have an Azure account:

1. Go to https://azure.microsoft.com/
2. Click "Start free" or "Try Azure for free"
3. Sign in with Microsoft account or create one
4. Complete verification process
5. Set up billing information

Free tier includes:
- $200 credit for first 30 days
- 12 months of free services
- Always-free services

## Step 2: Install Azure CLI

### On macOS

```bash
brew update && brew install azure-cli
```

### On Linux (Ubuntu/Debian)

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### On Linux (RPM-based)

```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf install -y azure-cli
```

### Verify Installation

```bash
az --version
```

## Step 3: Login to Azure

```bash
# Interactive login (opens browser)
az login

# For systems without browser
az login --use-device-code
```

This will:
1. Open browser for authentication
2. List your available subscriptions
3. Set default subscription

### Verify Login

```bash
# Show current account
az account show

# List all subscriptions
az account list --output table
```

## Step 4: Get Subscription ID

Your subscription ID is required for deployment:

```bash
# Get default subscription ID
az account show --query id -o tsv

# List all subscriptions with IDs
az account list --query '[].{Name:name, ID:id, State:state}' -o table
```

Save this ID - you'll need it for deployment.

### Set Default Subscription

If you have multiple subscriptions:

```bash
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

## Step 5: Create Service Principal Credential File

Create a service principal and store the JSON output in `~/.azure_credentials`
(this is the default location the deployer reads):

```bash
az ad sp create-for-rbac \
  --name "exasol-deployer" \
  --role contributor \
  --scopes /subscriptions/YOUR_SUBSCRIPTION_ID \
  > ~/.azure_credentials
chmod 600 ~/.azure_credentials
```

Output looks like:
```json
{
  "appId": "...",
  "displayName": "exasol-deployer",
  "password": "...",
  "tenant": "..."
}
```

You can optionally add your subscription ID to this file:
```json
{
  "appId": "...",
  "password": "...",
  "tenant": "...",
  "subscriptionId": "YOUR_SUBSCRIPTION_ID"
}
```

The deployer automatically reads this file during `exasol init`. To use a custom
path, pass `--azure-credentials-file /path/to/creds.json`.

## Step 6: Choose Azure Region

Select a region close to your users. Common regions:

| Region Code | Location | Notes |
|------------|----------|-------|
| `eastus` | East US (Virginia) | Default, well-established |
| `eastus2` | East US 2 (Virginia) | Alternative to eastus |
| `westus` | West US (California) | US West Coast |
| `westus2` | West US 2 (Washington) | US West Coast |
| `centralus` | Central US (Iowa) | US Central |
| `northeurope` | North Europe (Ireland) | Europe |
| `westeurope` | West Europe (Netherlands) | Europe |
| `uksouth` | UK South (London) | United Kingdom |
| `southeastasia` | Southeast Asia (Singapore) | Asia Pacific |
| `japaneast` | Japan East (Tokyo) | Asia Pacific |

Full list: https://azure.microsoft.com/en-us/global-infrastructure/geographies/

### Check Regional Availability

```bash
# List all regions
az account list-locations --output table

# Check if specific VM size is available in region
az vm list-skus --location eastus --size Standard_D --output table
```

## Step 6.5: Azure Free Trial Limitations

### ⚠️ **Public IP Address Quota**

**Azure free trial accounts are limited to 3 Public IP addresses per region.** Each Exasol node requires one Public IP for SSH access, so you cannot deploy more than 3 nodes on a free trial account.

**Symptoms of hitting this limit:**
```
Error: PublicIPCountLimitReached: Cannot create more than 3 public IP addresses for this subscription in this region.
```

**Solutions:**
1. **Deploy 3 nodes maximum** (recommended for free tier):
   ```bash
   ./exasol init --cloud-provider azure --cluster-size 3 [other flags]
   ```

2. **Upgrade to a paid subscription** for higher limits and more features

3. **Use a different region** (each region has its own quota)

4. **Switch to AWS or GCP** which offer more generous free tiers

### ℹ️ **Other Free Trial Limits**
- **CPU Cores**: Limited to 4 cores per region (may require smaller VM sizes)
- **Virtual Machines**: Limited to certain series and sizes
- **Storage**: Limited disk space and IOPS
- **Support**: Limited technical support options

**Symptoms of CPU core quota limit:**
```
OperationNotAllowed: Operation could not be completed as it results in exceeding approved Total Regional Cores quota.
```

**Solutions for CPU limits:**
- Use smaller instance types: `Standard_B1s` (1 vCPU), `Standard_B1ms` (1 vCPU)
- Request core quota increase (same process as Public IPs)
- Use fewer nodes

## Step 7: Initialize Exasol Deployment

`exasol init` automatically loads Azure service principal credentials from
`~/.azure_credentials` (or from the path passed via `--azure-credentials-file`).
It also looks for your subscription ID in this order:
1. `--azure-subscription` flag
2. `AZURE_SUBSCRIPTION_ID` environment variable
3. `subscriptionId` field in the credentials file

### Basic Deployment

Single-node deployment with defaults (assuming subscription ID is configured):

```bash
./exasol init \
  --cloud-provider azure \
  --deployment-dir ./my-azure-deployment
```

Or explicitly passing it:

```bash
./exasol init \
  --cloud-provider azure \
  --azure-subscription YOUR_SUBSCRIPTION_ID \
  --deployment-dir ./my-azure-deployment
```

### Production Deployment

Multi-node cluster with specific configuration:

```bash
./exasol init \
  --cloud-provider azure \
  --deployment-dir ./prod-cluster \
  --azure-subscription YOUR_SUBSCRIPTION_ID \
  --azure-region eastus \
  --db-version exasol-2025.1.4 \
  --cluster-size 4 \
  --instance-type Standard_D32s_v5 \
  --data-volume-size 1000 \
  --owner "production-team" \
  --allowed-cidr "10.0.0.0/8"
```

### Development with Spot Instances

Save up to 90% with spot instances (suitable for dev/test):

```bash
./exasol init \
  --cloud-provider azure \
  --azure-subscription YOUR_SUBSCRIPTION_ID \
  --deployment-dir ./dev-cluster \
  --cluster-size 2 \
  --azure-spot-instance \
  --azure-region westus2 \
  --owner "dev-team"
```

## Azure-Specific Options

| Flag | Description | Default |
|------|-------------|---------|
| `--azure-region` | Azure region for deployment | `eastus` |
| `--azure-subscription` | Azure subscription ID (required if not in env/file) | - |
| `--azure-credentials-file` | Path to service principal JSON (`appId`, `password`, `tenant`, `subscriptionId`) | `~/.azure_credentials` |
| `--azure-spot-instance` | Enable spot instances | `false` |

## VM Sizes (Instance Types)

The deployer defaults to `Standard_B2als_v2` (x86_64) or `Standard_D2pls_v5` (ARM64), which are cost-effective options for development. For production, consider larger sizes.

### Recommended VM Sizes (x86_64)

| VM Size | vCPUs | Memory | Temp Storage | Network | Use Case |
|---------|-------|--------|--------------|---------|----------|
| `Standard_B2als_v2` | 2 | 4 GB | Remote | Moderate | Default / Minimal |
| `Standard_D4s_v5` | 4 | 16 GB | Remote | Moderate | Small dev/test |
| `Standard_D8s_v5` | 8 | 32 GB | Remote | Moderate | Small production |
| `Standard_D16s_v5` | 16 | 64 GB | Remote | High | Medium production |
| `Standard_D32s_v5` | 32 | 128 GB | Remote | High | Large production |
| `Standard_D64s_v5` | 64 | 256 GB | Remote | Very High | Very large production |

### Compute-Optimized (Recommended for Exasol)

| VM Size | vCPUs | Memory | Network | Use Case |
|---------|-------|--------|---------|----------|
| `Standard_F8s_v2` | 8 | 16 GB | Moderate | Small production |
| `Standard_F16s_v2` | 16 | 32 GB | High | Medium production |
| `Standard_F32s_v2` | 32 | 64 GB | Very High | Large production |
| `Standard_F64s_v2` | 64 | 128 GB | Extremely High | Very large production |

### Recommended VM Sizes (ARM64 - Ampere)

| VM Size | vCPUs | Memory | Network | Use Case |
|---------|-------|--------|---------|----------|
| `Standard_D2pls_v5` | 2 | 4 GB | Moderate | Default / Minimal |
| `Standard_D4ps_v5` | 4 | 16 GB | Moderate | Small production |
| `Standard_D8ps_v5` | 8 | 32 GB | High | Medium production |
| `Standard_D16ps_v5` | 16 | 64 GB | High | Large production |
| `Standard_D32ps_v5` | 32 | 128 GB | Very High | Very large production |

### Choosing VM Sizes

- **B-series**: Burstable, cost-effective for development (default)
- **D-series**: General purpose, good for most workloads
- **F-series**: Compute-optimized, best for Exasol
- **s suffix**: Premium storage support (recommended)
- **v5**: Latest generation, best price/performance

Full VM sizes: https://azure.microsoft.com/en-us/pricing/details/virtual-machines/

## Storage Configuration

### Data Disks

```bash
--data-volume-size 500        # 500 GB per disk
--data-volumes-per-node 2     # 2 disks per node
```

This creates 2x 500 GB = 1 TB total data storage per node.

Azure disk types used:
- **Premium SSD (P series)**: High performance, low latency
- Automatic performance scaling based on disk size
- P20 (512 GB): 2,300 IOPS, 150 MB/s
- P30 (1 TB): 5,000 IOPS, 200 MB/s

### OS Disks

```bash
--root-volume-size 100        # 100 GB for OS
```

Uses Premium SSD for OS disk (better performance than Standard).

## Networking and Security

### CIDR Configuration

**WARNING**: Default `0.0.0.0/0` allows access from anywhere. Always restrict:

```bash
# Single IP
--allowed-cidr "203.0.113.42/32"

# Subnet
--allowed-cidr "203.0.113.0/24"

# Corporate network
--allowed-cidr "10.0.0.0/8"
```

### Network Security Groups (NSG)

The deployer creates NSG with these rules:
- **Port 22**: SSH access (restricted to allowed_cidr)
- **Port 8563**: Exasol database (restricted to allowed_cidr)
- **Port 443**: Admin UI (restricted to allowed_cidr)
- **All internal traffic**: Between cluster nodes (unrestricted)

### Virtual Network Configuration

The deployer automatically creates:
- New Virtual Network (VNet) with address space `10.0.0.0/16`
- Subnet for Exasol VMs: `10.0.1.0/24`
- Network Security Group
- Public IP addresses for each VM
- Network interfaces with accelerated networking

All resources are tagged with owner tag for cost tracking.

## Cost Optimization

### Spot VMs

Enable spot instances to save up to 90%:

```bash
./exasol init --cloud-provider azure --azure-spot-instance
```

**Important Notes**:
- Spot VMs can be evicted with 30-second notice
- Eviction based on capacity and price
- Best for development, testing, and fault-tolerant workloads
- Not recommended for production databases
- Price cap set to standard VM price (you never pay more)

### Azure Reserved Instances

For production, consider 1 or 3-year reserved instances:
- Save up to 72% compared to pay-as-you-go
- Purchase in Azure Portal → Reservations
- Most effective for stable, long-running workloads

### Cost Monitoring

Enable cost management:

```bash
# Set owner tag for tracking
./exasol init --owner "team-name-project"
```

View costs in Azure Portal:
- Cost Management + Billing
- Filter by tags: owner = team-name-project

### Hybrid Benefit

If you have Windows Server licenses with Software Assurance:
- Can reduce costs by 40% or more
- Apply in Azure Portal for existing VMs
- (Exasol uses Linux, but applies if you run Windows components)

## Step 8: Deploy

After initialization, deploy the infrastructure:

```bash
./exasol deploy --deployment-dir ./my-azure-deployment
```

This will:
1. Create Resource Group
2. Create Virtual Network and subnet
3. Create Network Security Group
4. Launch VMs
5. Attach managed disks
6. Configure networking and public IPs
7. Install and configure Exasol

Deployment takes approximately 15-20 minutes.

## Step 9: Verify Deployment

Check deployment status:

```bash
./exasol status --deployment-dir ./my-azure-deployment
```

Expected output:
```json
{
  "status": "database_ready",
  "db_version": "exasol-2025.1.4",
  "architecture": "x86_64",
  "terraform_state_exists": true,
  "created_at": "2025-01-15T10:30:00Z",
  "updated_at": "2025-01-15T10:45:00Z"
}
```

## Accessing Your Cluster

### SSH Access

```bash
# Recommended: Using generated SSH config
ssh -F ./my-azure-deployment/ssh_config n11

# Alternative: Direct SSH (initial access or troubleshooting)
ssh -i ./my-azure-deployment/exasol-key.pem exasol@<public-ip>
```

**Note:** The generated SSH config uses the `exasol` user and is the recommended way to access your cluster. Cloud-init automatically copies your SSH keys to the exasol user during deployment.

### Database Connection

Find connection details:
```bash
cd ./my-azure-deployment
tofu output -json | jq -r '.public_ips.value'
```

Get credentials:
```bash
cat .credentials.json | jq -r '.db_password'
```

Connect with your SQL client:
- Host: `<public-ip>`
- Port: `8563`
- Username: `sys`
- Password: From `.credentials.json`

### Azure Portal

View resources in Azure Portal:
1. Go to https://portal.azure.com/
2. Navigate to Resource Groups
3. Find your deployment resource group (tagged with owner)
4. View all created resources

## Troubleshooting

### Common Issues

**Error: "The subscription is not registered to use namespace 'Microsoft.Compute'"**
```bash
# Solution: Register resource provider
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Storage

# Check registration status
az provider show -n Microsoft.Compute --query "registrationState"
```

**Error: "QuotaExceeded: Operation could not be completed as it results in exceeding approved cores quota"**
- Solution: Request quota increase in Azure Portal
- Navigate to: Subscriptions → Usage + quotas
- Search for the VM family
- Click "Request increase"

**Error: "AllocationFailed: Allocation failed. We do not have sufficient capacity"**
- Solution: Try different region or VM size
- Some regions have better availability
- Alternative: Use availability zones

**Error: "AuthorizationFailed: The client does not have authorization"**
- Solution: Check subscription permissions
- Verify: `az account show`
- Ensure Contributor role on subscription

**Error: Spot VM evicted during deployment**
- Solution: Redeploy without spot instances
- Spot VMs not suitable for initial deployment

### Debugging Tips

Enable debug logging:
```bash
./exasol --log-level debug deploy --deployment-dir ./my-azure-deployment
```

Check Azure resources:
```bash
# List resource groups
az group list --output table

# List VMs in resource group
az vm list --resource-group exasol-* --output table

# Show VM details
az vm show --resource-group <rg-name> --name <vm-name>
```

View Terraform state:
```bash
cd ./my-azure-deployment
tofu show
tofu output -json | jq
```

## Cleanup

Destroy all Azure resources:

```bash
./exasol destroy --deployment-dir ./my-azure-deployment
```

Verify in Azure Portal that resource group is deleted:
- Portal → Resource Groups
- Ensure your deployment RG is gone

**Note**: Resource group deletion removes ALL resources in it.

## Additional Resources

- [Azure VM Documentation](https://docs.microsoft.com/en-us/azure/virtual-machines/)
- [Azure CLI Reference](https://docs.microsoft.com/en-us/cli/azure/)
- [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/)
- [Azure Free Account](https://azure.microsoft.com/en-us/free/)
- [OpenTofu Azure Provider](https://opentofu.org/docs/language/providers/requirements/)
- [Azure Spot VMs](https://azure.microsoft.com/en-us/products/virtual-machines/spot/)

## Security Best Practices

1. **Use Managed Identities**: When deploying from Azure VMs, use managed identities
2. **Enable Azure AD Authentication**: Integrate with your organization's directory
3. **Use Key Vault**: Store secrets in Azure Key Vault
4. **Enable Azure Security Center**: Monitor security posture
5. **Restrict Network Access**: Use NSG rules and private endpoints
6. **Enable Diagnostic Logging**: Track all operations
7. **Use Azure Policy**: Enforce compliance requirements
8. **Rotate Credentials**: Regularly update service principal secrets

## Azure-Specific Features

### Availability Zones

For high availability, consider using availability zones:
- Protect against datacenter failures
- Available in most regions
- Slight cost increase
- Requires Terraform configuration customization

### Azure Backup

For production deployments:
1. Go to Azure Portal → Backup center
2. Configure backup for managed disks
3. Set backup policy (daily, weekly, etc.)
4. Define retention period

### Azure Monitor

Monitor VM performance:
```bash
# Enable VM insights
az vm extension set \
  --resource-group <rg-name> \
  --vm-name <vm-name> \
  --name AzureMonitorLinuxAgent \
  --publisher Microsoft.Azure.Monitor
```

View metrics in Azure Portal → Monitor.

## Next Steps

- [Return to Cloud Setup Guide](CLOUD_SETUP.md)
- [Main README](../README.md)
- Set up Azure Backup for production deployments
- Configure Azure Monitor for performance tracking
