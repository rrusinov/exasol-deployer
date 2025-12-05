# GCP (Google Cloud Platform) Setup Guide

This guide provides detailed instructions for setting up GCP credentials and deploying Exasol on Google Cloud Platform.

## Prerequisites

- Google Cloud account with billing enabled
- `gcloud` CLI installed
- OpenTofu (or Terraform) installed
- Ansible installed
- jq installed

## Step 1: Create Google Cloud Account

If you don't have a GCP account:

1. Go to https://cloud.google.com/
2. Click "Get started for free"
3. Sign in with Google account or create one
4. Complete verification process
5. Enter billing information

Free tier includes:
- $300 credit for first 90 days
- Always-free services (with usage limits)

## Step 2: Install gcloud CLI

### On macOS

```bash
# Install using Homebrew
brew install --cask google-cloud-sdk
```

### On Linux

```bash
# Add Cloud SDK distribution URI
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
  sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

# Import Google Cloud public key
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
  sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -

# Install gcloud
sudo apt-get update && sudo apt-get install google-cloud-cli
```

### Verify Installation

```bash
gcloud --version
```

## Step 3: Login to Google Cloud

```bash
# Interactive login (opens browser)
gcloud auth login

# Set up application default credentials (required for OpenTofu)
gcloud auth application-default login
```

This will:
1. Open browser for authentication
2. Grant permissions for gcloud and application default credentials
3. Store credentials locally

### Verify Login

```bash
# Show current account
gcloud auth list

# Show application default credentials
gcloud auth application-default print-access-token > /dev/null && \
  echo "✓ Application default credentials configured"
```

## Step 4: Create or Select Project

Every GCP deployment must be in a project.

### Create New Project

```bash
# Create project (project IDs must be globally unique)
gcloud projects create exasol-deployer-123 \
  --name="Exasol Deployer" \
  --set-as-default

# Enable billing (replace BILLING_ACCOUNT_ID with your billing account ID)
gcloud beta billing projects link exasol-deployer-123 \
  --billing-account=BILLING_ACCOUNT_ID
```

### Use Existing Project

```bash
# List projects
gcloud projects list

# Set default project
gcloud config set project YOUR_PROJECT_ID

# Check if billing is enabled
gcloud billing projects describe YOUR_PROJECT_ID

# If billing is not enabled, link billing account
gcloud beta billing projects link YOUR_PROJECT_ID \
  --billing-account=BILLING_ACCOUNT_ID
```

**Note**: The `--gcp-project` parameter is **optional**. The `exasol init` command will automatically detect your GCP project ID from the credentials file (`~/.gcp_credentials.json`) if you don't specify it explicitly. You can also set the `GOOGLE_CLOUD_PROJECT` environment variable.

### Get Project ID

```bash
# Get current project ID
gcloud config get-value project

# Or get project details
gcloud projects describe YOUR_PROJECT_ID
```

**Save this project ID** - you'll need it for deployment.

**Note**: GCP uses both project IDs (human-readable names like "my-project-123") and project numbers (numeric identifiers like "123456789012"). The project number appears in error messages and some API calls. You can find both by running `gcloud projects describe YOUR_PROJECT_ID`.

## Step 5: Enable Required APIs

**Important**: Before enabling APIs, ensure billing is enabled for your project. Some Google APIs charge for usage and require billing to be enabled first. If you haven't already enabled billing in Step 4, do so now before proceeding with API enablement.

Enable the Compute Engine API:

```bash
# Enable Compute Engine API
gcloud services enable compute.googleapis.com

# Verify API is enabled
gcloud services list --enabled | grep compute
```

Additional useful APIs:

```bash
# Enable Cloud Resource Manager API
gcloud services enable cloudresourcemanager.googleapis.com

# Enable Service Usage API
gcloud services enable serviceusage.googleapis.com
```

## Step 6: Create Service Account (Optional but Recommended)

For automated deployments, create a service account:

```bash
# Create service account (replace YOUR_PROJECT_ID with your actual project ID)
gcloud iam service-accounts create exasol-deployer \
  --project=YOUR_PROJECT_ID \
  --display-name="Exasol Deployer Service Account"

# Grant Compute Admin role
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:exasol-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.admin"

# Grant Service Account User role (needed to create instances)
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:exasol-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

# Create and download key
gcloud iam service-accounts keys create ~/.gcp_credentials.json \
  --project=YOUR_PROJECT_ID \
  --iam-account=exasol-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

### Use Service Account

```bash
# Set environment variable
export GOOGLE_APPLICATION_CREDENTIALS=~/.gcp_credentials.json

# Verify
gcloud auth activate-service-account --key-file=$GOOGLE_APPLICATION_CREDENTIALS
```

**Important**: Keep this key file secure! Add to `.gitignore`.

## Step 7: Choose GCP Region and Zone

Select a region close to your users for lower latency.

### Common Regions

| Region | Location | Zones | Notes |
|--------|----------|-------|-------|
| `us-central1` | Iowa, USA | a,b,c,f | Default, well-established |
| `us-east1` | South Carolina, USA | b,c,d | East Coast USA |
| `us-west1` | Oregon, USA | a,b,c | West Coast USA |
| `us-west2` | Los Angeles, USA | a,b,c | Low latency for California |
| `europe-west1` | Belgium | b,c,d | Western Europe |
| `europe-west2` | London, UK | a,b,c | United Kingdom |
| `europe-west3` | Frankfurt, Germany | a,b,c | Central Europe |
| `asia-east1` | Taiwan | a,b,c | Asia Pacific |
| `asia-northeast1` | Tokyo, Japan | a,b,c | Japan |
| `asia-southeast1` | Singapore | a,b,c | Southeast Asia |

Full list: https://cloud.google.com/compute/docs/regions-zones

Use the `--gcp-zone` flag during `exasol init` to target a specific zone (for example, `--gcp-zone europe-west3-b`). If you omit the flag, the deployer defaults to `<region>-a`.

### Check Machine Type Availability

```bash
# List available machine types in region
gcloud compute machine-types list --filter="zone:us-central1-a" | grep n2-standard

# Check specific machine type availability
gcloud compute machine-types describe n2-standard-8 --zone=us-central1-a
```

## Step 8: Initialize Exasol Deployment

### Basic Deployment

Single-node deployment with defaults:

```bash
./exasol init \
  --cloud-provider gcp \
  --gcp-project YOUR_PROJECT_ID \
  --deployment-dir ./my-gcp-deployment
```

### Production Deployment

Multi-node cluster with specific configuration:

```bash
./exasol init \
  --cloud-provider gcp \
  --deployment-dir ./prod-cluster \
  --gcp-project YOUR_PROJECT_ID \
  --gcp-region us-central1 \
  --db-version exasol-2025.1.8 \
  --cluster-size 4 \
  --instance-type n2-standard-32 \
  --data-volume-size 1000 \
  --owner "production-team" \
  --allowed-cidr "10.0.0.0/8"
```

### Development with Spot (Preemptible) Instances

Save up to 80% with preemptible instances (suitable for dev/test):

```bash
./exasol init \
  --cloud-provider gcp \
  --gcp-project YOUR_PROJECT_ID \
  --deployment-dir ./dev-cluster \
  --cluster-size 2 \
  --gcp-spot-instance \
  --gcp-region us-west1 \
  --owner "dev-team"
```

## GCP-Specific Options

| Flag | Description | Default |
|------|-------------|---------|
| `--gcp-region` | GCP region for deployment | `us-central1` |
| `--gcp-project` | GCP project ID (required) | - |
| `--gcp-spot-instance` | Enable spot/preemptible instances | `false` |

## Machine Types (Instance Types)

The deployer automatically selects appropriate machine types, but you can override:

### Recommended Machine Types (x86_64)

#### General Purpose (N2 Series)

| Machine Type | vCPUs | Memory | Network | Use Case |
|-------------|-------|--------|---------|----------|
| `n2-standard-4` | 4 | 16 GB | 10 Gbps | Small dev/test |
| `n2-standard-8` | 8 | 32 GB | 16 Gbps | Small production |
| `n2-standard-16` | 16 | 64 GB | 32 Gbps | Medium production |
| `n2-standard-32` | 32 | 128 GB | 32 Gbps | Large production |
| `n2-standard-64` | 64 | 256 GB | 32 Gbps | Very large production |

#### Compute Optimized (C2 Series - Recommended for Exasol)

| Machine Type | vCPUs | Memory | Network | Use Case |
|-------------|-------|--------|---------|----------|
| `c2-standard-8` | 8 | 32 GB | 16 Gbps | Small production |
| `c2-standard-16` | 16 | 64 GB | 32 Gbps | Medium production |
| `c2-standard-30` | 30 | 120 GB | 32 Gbps | Large production |
| `c2-standard-60` | 60 | 240 GB | 32 Gbps | Very large production |

#### High-CPU (N2 High-CPU)

| Machine Type | vCPUs | Memory | Network | Use Case |
|-------------|-------|--------|---------|----------|
| `n2-highcpu-16` | 16 | 16 GB | 32 Gbps | CPU-intensive, lower memory |
| `n2-highcpu-32` | 32 | 32 GB | 32 Gbps | CPU-intensive, lower memory |

### Recommended Machine Types (ARM64 - Tau T2A)

| Machine Type | vCPUs | Memory | Network | Use Case |
|-------------|-------|--------|---------|----------|
| `t2a-standard-4` | 4 | 16 GB | 10 Gbps | Small production |
| `t2a-standard-8` | 8 | 32 GB | 16 Gbps | Medium production |
| `t2a-standard-16` | 16 | 64 GB | 32 Gbps | Large production |
| `t2a-standard-32` | 32 | 128 GB | 32 Gbps | Very large production |

### Choosing Machine Types

- **N2**: Latest general-purpose, good all-around
- **C2**: Compute-optimized, best for Exasol workloads
- **T2A**: ARM-based, cost-effective with good performance
- **E2**: Budget-friendly, suitable for small dev environments

Full machine types: https://cloud.google.com/compute/docs/machine-types

## Storage Configuration

### Persistent Disks

```bash
--data-volume-size 500        # 500 GB per disk
--data-volumes-per-node 2     # 2 disks per node
```

This creates 2x 500 GB = 1 TB total data storage per node.

GCP disk types used:
- **pd-ssd** (SSD Persistent Disk): High performance
  - 30 IOPS per GB (up to 100,000 IOPS per disk)
  - 0.48 MB/s per GB throughput
- **pd-balanced**: Alternative for balanced performance/cost
- **pd-standard**: Budget option (HDD)

### Boot Disks

```bash
--root-volume-size 100        # 100 GB for OS
```

Uses pd-ssd for boot disk (better performance).

### Local SSD (Advanced)

For maximum performance, consider using local SSDs:
- 375 GB per local SSD
- Up to 3,000,000 IOPS
- Ephemeral (data lost on instance stop)
- Requires Terraform customization

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

### Firewall Rules

The deployer creates firewall rules:
- **SSH (port 22)**: Restricted to allowed_cidr
- **Exasol database (port 8563)**: Restricted to allowed_cidr
- **Admin UI (port 443)**: Restricted to allowed_cidr
- **Internal traffic**: Between cluster nodes (unrestricted)

### VPC Configuration

The deployer automatically creates:
- New VPC network (auto-mode)
- Subnetworks in the specified region
- Firewall rules
- External IP addresses for each instance

All resources are labeled with owner tag for cost tracking.

## Cost Optimization

### Spot (Preemptible) VMs

Enable spot instances to save up to 80%:

```bash
./exasol init --cloud-provider gcp --gcp-spot-instance
```

**Important Notes**:
- Preemptible VMs run for max 24 hours
- Can be preempted with 30-second notice
- Best for development, testing, and fault-tolerant workloads
- Not recommended for production databases
- Typically 60-80% cheaper than standard instances

### Committed Use Discounts

For production, consider committed use contracts:
- Save up to 57% for 1-year commitment
- Save up to 70% for 3-year commitment
- Purchase in GCP Console → Billing → Commitments
- Apply to specific machine families and regions

### Sustained Use Discounts

Automatic discounts for running instances:
- No commitment required
- Up to 30% discount for instances running > 25% of month
- Applied automatically to your bill

### Cost Monitoring

Enable cost tracking with labels:

```bash
# Set owner label for tracking
./exasol init --owner "team-name-project"
```

View costs in GCP Console:
- Billing → Reports
- Group by: Labels → owner

### Budget Alerts

Set up budget alerts:
```bash
# Create budget alert
gcloud billing budgets create \
  --billing-account=BILLING_ACCOUNT_ID \
  --display-name="Exasol Monthly Budget" \
  --budget-amount=1000
```

## Step 9: Deploy

After initialization, deploy the infrastructure:

```bash
./exasol deploy --deployment-dir ./my-gcp-deployment
```

This will:
1. Create VPC network and subnet
2. Create firewall rules
3. Launch Compute Engine instances
4. Attach persistent disks
5. Configure networking and external IPs
6. Install and configure Exasol

Deployment takes approximately 15-20 minutes.

## Step 10: Verify Deployment

Check deployment status:

```bash
./exasol status --deployment-dir ./my-gcp-deployment
```

Expected output:
```json
{
  "status": "database_ready",
  "db_version": "exasol-2025.1.8",
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
ssh -F ./my-gcp-deployment/ssh_config n11

# Alternative: Direct SSH (initial access or troubleshooting)
ssh -i ./my-gcp-deployment/exasol-key.pem exasol@<external-ip>
```

**Note:** The generated SSH config uses the `exasol` user and is the recommended way to access your cluster. Cloud-init automatically copies your SSH keys to the exasol user during deployment.

Host OS password for the `exasol` user (useful for console access or password-based SSH if enabled):
```bash
cat .credentials.json | jq -r '.host_password'
```

### Database Connection

Find connection details:
```bash
cd ./my-gcp-deployment
tofu output -json | jq -r '.external_ips.value'
```

Get credentials:
```bash
cat .credentials.json | jq -r '.db_password'
```

Connect with your SQL client:
- Host: `<external-ip>`
- Port: `8563`
- Username: `sys`
- Password: From `.credentials.json`

### GCP Console

View resources in GCP Console:
1. Go to https://console.cloud.google.com/
2. Select your project
3. Navigate to:
   - Compute Engine → VM instances
   - VPC network → Firewall
   - Compute Engine → Disks

## Troubleshooting

### Common Issues

**Error: "API [compute.googleapis.com] not enabled on project"**
```bash
# Solution: Enable Compute Engine API
gcloud services enable compute.googleapis.com

# Verify
gcloud services list --enabled
```

**Error: "Quota 'CPUS' exceeded. Limit: X in region"**
- Solution: Request quota increase in GCP Console
- Navigate to: IAM & Admin → Quotas
- Filter by metric: "CPUs"
- Select region and click "Edit Quotas"
- Request increase

**Error: "ZONE_RESOURCE_POOL_EXHAUSTED"**
- Solution: Try different zone or region
- Check availability: `gcloud compute zones list`
- Some zones have better capacity

**Error: "The user does not have permission to access project"**
- Solution: Verify project permissions
- Check: `gcloud projects get-iam-policy YOUR_PROJECT_ID`
- Ensure you have Compute Admin role

**Error: "Billing account not configured"**
```bash
# Check billing
gcloud billing accounts list

# Link billing account to project
gcloud beta billing projects link YOUR_PROJECT_ID \
  --billing-account=BILLING_ACCOUNT_ID
```

**Error: Preemptible instance preempted during deployment**
- Solution: Redeploy without preemptible instances
- Preemptible VMs not suitable for initial deployment

### Debugging Tips

Enable debug logging:
```bash
./exasol --log-level debug deploy --deployment-dir ./my-gcp-deployment
```

Check GCP resources:
```bash
# List VMs
gcloud compute instances list

# Describe specific instance
gcloud compute instances describe INSTANCE_NAME --zone=ZONE

# List disks
gcloud compute disks list

# View firewall rules
gcloud compute firewall-rules list
```

View Terraform state:
```bash
cd ./my-gcp-deployment
tofu show
tofu output -json | jq
```

Check logs:
```bash
# View instance serial console output
gcloud compute instances get-serial-port-output INSTANCE_NAME --zone=ZONE
```

## Cleanup

Destroy all GCP resources:

```bash
./exasol destroy --deployment-dir ./my-gcp-deployment
```

Verify in GCP Console that resources are deleted:
- Compute Engine → VM instances (should be empty)
- VPC network → Firewall rules
- Compute Engine → Disks

**Note**: OpenTofu will delete all resources it created.

## Additional Resources

- [GCP Compute Engine Documentation](https://cloud.google.com/compute/docs)
- [gcloud CLI Reference](https://cloud.google.com/sdk/gcloud/reference)
- [GCP Pricing Calculator](https://cloud.google.com/products/calculator)
- [GCP Free Tier](https://cloud.google.com/free)
- [OpenTofu GCP Provider](https://opentofu.org/docs/language/providers/requirements/)
- [Preemptible VMs](https://cloud.google.com/compute/docs/instances/preemptible)
- [Committed Use Discounts](https://cloud.google.com/compute/docs/instances/signing-up-committed-use-discounts)

## Security Best Practices

1. **Use Service Accounts**: For automated deployments
2. **Enable OS Login**: Better SSH key management
3. **Use IAM Roles**: Fine-grained access control
4. **Enable VPC Service Controls**: Protect against data exfiltration
5. **Restrict Network Access**: Use firewall rules effectively
6. **Enable Cloud Logging**: Track all operations
7. **Use Secret Manager**: Store sensitive data
8. **Rotate Credentials**: Regularly update service account keys
9. **Enable Security Command Center**: Monitor security posture
10. **Use Organization Policies**: Enforce security requirements

## GCP-Specific Features

### Snapshot Backups

Create disk snapshots for backups:
```bash
# Create snapshot
gcloud compute disks snapshot DISK_NAME \
  --zone=ZONE \
  --snapshot-names=exasol-backup-$(date +%Y%m%d)

# List snapshots
gcloud compute snapshots list
```

### Cloud Monitoring

Monitor instance performance:
1. GCP Console → Monitoring
2. Create dashboards for CPU, memory, disk I/O
3. Set up alerts for critical metrics

### Cloud Logging

View logs:
```bash
# View instance logs
gcloud logging read "resource.type=gce_instance" --limit=50

# Real-time log streaming
gcloud logging read "resource.type=gce_instance" --format=json --limit=1 --follow
```

### Metadata and Startup Scripts

Add custom metadata:
```bash
# Add metadata to instance
gcloud compute instances add-metadata INSTANCE_NAME \
  --zone=ZONE \
  --metadata=key=value
```

## Next Steps

- [Return to Cloud Setup Guide](CLOUD_SETUP.md)
- [Main README](../README.md)
- Set up snapshot schedules for backups
- Configure Cloud Monitoring for performance tracking
- Consider committed use discounts for production
