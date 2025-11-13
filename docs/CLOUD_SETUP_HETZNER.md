# Hetzner Cloud Setup Guide

This guide provides detailed instructions for setting up Hetzner Cloud credentials and deploying Exasol on Hetzner.

## Prerequisites

- Hetzner Cloud account
- OpenTofu (or Terraform) installed
- Ansible installed
- jq installed

## Why Hetzner Cloud?

Hetzner Cloud is a European cloud provider offering:
- **Cost-effective**: Generally 30-50% cheaper than AWS/Azure/GCP
- **Simple pricing**: No complex pricing tiers
- **Good performance**: Modern AMD EPYC and Intel Xeon CPUs
- **European data centers**: Strong GDPR compliance
- **No bandwidth charges**: Generous included traffic
- **Fast provisioning**: Servers ready in seconds

Best for: Development, testing, and European deployments with budget constraints.

## Step 1: Create Hetzner Cloud Account

1. Go to https://www.hetzner.com/cloud
2. Click "Sign Up" or "Register"
3. Complete registration form
4. Verify email address
5. Add payment method (credit card or PayPal)

### Important Notes

- No free tier (but very affordable pricing)
- Billing is per-hour, charged monthly
- Minimum charge is €0.01
- First servers usually available immediately

## Step 2: Create Hetzner Cloud Project

1. **Login to Hetzner Cloud Console**: https://console.hetzner.cloud/
2. **Create Project**:
   - Click "New Project"
   - Name: "exasol-deployment" (or your preference)
   - Click "Add Project"

Projects help organize resources and billing.

## Step 3: Generate API Token

1. **Navigate to Project**: Select your project from dashboard
2. **Go to Security**:
   - Click on "Security" in left sidebar
   - Click on "API tokens" tab
3. **Create Token**:
   - Click "Generate API Token"
   - Description: "Exasol Deployer"
   - Permissions: "Read & Write" (required for creating resources)
   - Click "Generate API Token"
4. **Save Token**: Copy the token immediately - it won't be shown again!

**Important**: Keep this token secure! Anyone with this token can create/delete resources in your project.

### Secure Token Storage

```bash
# Store token securely in environment variable
export HETZNER_TOKEN="your-token-here"

# Or store in a secure file
echo "your-token-here" > ~/.hetzner_token
chmod 600 ~/.hetzner_token

# Use in deployment
export HETZNER_TOKEN=$(cat ~/.hetzner_token)
```

## Step 4: Choose Hetzner Location

Hetzner has three datacenter locations in Germany and one in Finland:

| Location Code | City | Country | Notes |
|--------------|------|---------|-------|
| `nbg1` | Nuremberg | Germany | Default, original datacenter |
| `fsn1` | Falkenstein | Germany | High availability |
| `hel1` | Helsinki | Finland | Nordics, alternative routing |

All locations offer:
- Same pricing
- Same server types
- Same features
- Low latency within Europe

### Check Server Availability

```bash
# Install hcloud CLI (optional)
brew install hcloud  # macOS
# or
snap install hcloud  # Linux

# Login
hcloud context create exasol-deployer

# List server types in location
hcloud server-type list
hcloud location list
```

## Step 5: Initialize Exasol Deployment

### Basic Deployment

Single-node deployment with defaults:

```bash
./exasol init \
  --cloud-provider hetzner \
  --hetzner-token "$HETZNER_TOKEN" \
  --deployment-dir ./my-hetzner-deployment
```

**Warning**: Never commit the token to version control. Use environment variables.

### Production Deployment

Multi-node cluster with specific configuration:

```bash
./exasol init \
  --cloud-provider hetzner \
  --hetzner-token "$HETZNER_TOKEN" \
  --deployment-dir ./prod-cluster \
  --hetzner-location fsn1 \
  --db-version exasol-2025.1.4 \
  --cluster-size 4 \
  --instance-type cx41 \
  --data-volume-size 500 \
  --owner "production-team" \
  --allowed-cidr "203.0.113.0/24"
```

### Development Deployment

Cost-effective small cluster:

```bash
./exasol init \
  --cloud-provider hetzner \
  --hetzner-token "$HETZNER_TOKEN" \
  --deployment-dir ./dev-cluster \
  --cluster-size 2 \
  --instance-type cpx21 \
  --data-volume-size 100 \
  --hetzner-location hel1 \
  --owner "dev-team"
```

## Hetzner-Specific Options

| Flag | Description | Default |
|------|-------------|---------|
| `--hetzner-location` | Datacenter location | `nbg1` |
| `--hetzner-token` | Hetzner API token (required) | - |

**Note**: Hetzner does not support spot instances - all instances are on-demand.

## Server Types (Instance Types)

Hetzner offers simple, well-defined server types with predictable pricing.

### Shared vCPU (CPX) - Development/Testing

| Server Type | vCPUs | Memory | Disk | Traffic | Price/month* | Use Case |
|------------|-------|--------|------|---------|--------------|----------|
| `cpx11` | 2 | 2 GB | 40 GB | 20 TB | ~€5 | Small dev |
| `cpx21` | 3 | 4 GB | 80 GB | 20 TB | ~€10 | Dev/test |
| `cpx31` | 4 | 8 GB | 160 GB | 20 TB | ~€18 | Small production |
| `cpx41` | 8 | 16 GB | 240 GB | 20 TB | ~€33 | Medium production |
| `cpx51` | 16 | 32 GB | 360 GB | 20 TB | ~€63 | Large production |

*Approximate prices, check https://www.hetzner.com/cloud for current pricing

### Dedicated vCPU (CCX) - Production (Recommended for Exasol)

| Server Type | vCPUs | Memory | Disk | Traffic | Price/month* | Use Case |
|------------|-------|--------|------|---------|--------------|----------|
| `ccx13` | 2 | 8 GB | 80 GB | 20 TB | ~€13 | Small production |
| `ccx23` | 4 | 16 GB | 160 GB | 20 TB | ~€25 | Medium production |
| `ccx33` | 8 | 32 GB | 240 GB | 20 TB | ~€48 | Large production |
| `ccx43` | 16 | 64 GB | 360 GB | 20 TB | ~€95 | Very large production |
| `ccx53` | 32 | 128 GB | 600 GB | 20 TB | ~€188 | Enterprise production |
| `ccx63` | 48 | 192 GB | 960 GB | 20 TB | ~€280 | Maximum performance |

### ARM (CAX) - Cost-Effective Alternative

| Server Type | vCPUs | Memory | Disk | Traffic | Price/month* | Use Case |
|------------|-------|--------|------|---------|--------------|----------|
| `cax11` | 2 | 4 GB | 40 GB | 20 TB | ~€4 | Small dev (ARM) |
| `cax21` | 4 | 8 GB | 80 GB | 20 TB | ~€8 | Dev/test (ARM) |
| `cax31` | 8 | 16 GB | 160 GB | 20 TB | ~€15 | Production (ARM) |
| `cax41` | 16 | 32 GB | 320 GB | 20 TB | ~€30 | Large production (ARM) |

### Choosing Server Types

- **CPX (Shared)**: Development, testing, non-critical workloads
- **CCX (Dedicated)**: Production databases (recommended for Exasol)
- **CAX (ARM)**: Budget-friendly alternative with good performance

CCX series provides:
- Dedicated CPU cores (no noisy neighbors)
- AMD EPYC processors
- Better and more consistent performance
- Ideal for database workloads

## Storage Configuration

### Volumes

```bash
--data-volume-size 500        # 500 GB per volume
--data-volumes-per-node 2     # 2 volumes per node
```

This creates 2x 500 GB = 1 TB total data storage per node.

Hetzner volume characteristics:
- **SSD-based**: Fast performance
- **Scalable**: 10 GB to 10 TB per volume
- **Attached storage**: Network-attached block storage
- **Snapshots available**: Can create backups
- **Pricing**: ~€0.05/GB per month

### Local Storage

Each server includes local SSD storage:
- Fast, low-latency
- Included in server price
- Data persists across reboots
- Not as reliable as volumes for critical data

For Exasol, use volumes for database storage, local disk for temp/cache.

## Networking and Security

### CIDR Configuration

**WARNING**: Default `0.0.0.0/0` allows access from anywhere. Always restrict:

```bash
# Single IP
--allowed-cidr "203.0.113.42/32"

# Office network
--allowed-cidr "203.0.113.0/24"

# Multiple networks (requires manual firewall configuration)
--allowed-cidr "10.0.0.0/8"
```

### Firewall Rules

The deployer creates firewall with these rules:
- **Port 22**: SSH access (restricted to allowed_cidr)
- **Port 8563**: Exasol database (restricted to allowed_cidr)
- **Port 443**: Admin UI (restricted to allowed_cidr)
- **Internal traffic**: Between cluster nodes (unrestricted)

### Networking Features

Hetzner provides:
- **Public IPv4**: One per server (included)
- **Public IPv6**: /64 subnet per server (included)
- **Private networks**: Create isolated networks (€0.50/month per network)
- **Floating IPs**: Move IPs between servers (€1.20/month)
- **No bandwidth charges**: 20 TB included per server/month
- **DDoS protection**: Basic protection included

## Cost Optimization

### No Spot Instances

Hetzner doesn't offer spot/preemptible instances, but:
- Base prices are already very competitive
- Simple hourly billing
- No surprise charges
- Free traffic (20 TB/month included)

### Cost Comparison Example

4-node production cluster (CCX33 = 8 vCPU, 32 GB):
- **Servers**: 4 × ~€48 = ~€192/month
- **Volumes**: 4 nodes × 500 GB × €0.05 = ~€100/month
- **Total**: ~€292/month

Comparable AWS setup would be 2-3x more expensive.

### Snapshots and Backups

Volume snapshots:
- €0.02/GB per month
- Charged for stored size, not volume size
- Create before risky operations

Server backups:
- 20% of server price per month
- Automated daily backups
- 7 daily backups retained

## Step 6: Deploy

After initialization, deploy the infrastructure:

```bash
./exasol deploy --deployment-dir ./my-hetzner-deployment
```

This will:
1. Create private network
2. Launch servers in specified location
3. Attach volumes
4. Configure firewall rules
5. Install and configure Exasol

Deployment takes approximately 10-15 minutes (Hetzner is fast!).

## Step 7: Verify Deployment

Check deployment status:

```bash
./exasol status --deployment-dir ./my-hetzner-deployment
```

Expected output:
```json
{
  "status": "database_ready",
  "db_version": "exasol-2025.1.4",
  "architecture": "x86_64",
  "terraform_state_exists": true,
  "created_at": "2025-01-15T10:30:00Z",
  "updated_at": "2025-01-15T10:35:00Z"
}
```

## Accessing Your Cluster

### SSH Access

```bash
# Using generated SSH config
ssh -F ./my-hetzner-deployment/ssh_config n11

# Direct SSH
ssh -i ./my-hetzner-deployment/exasol-key.pem root@<public-ip>
```

**Note**: Hetzner uses `root` user by default, not `ubuntu`.

### Database Connection

Find connection details:
```bash
cd ./my-hetzner-deployment
tofu output -json | jq -r '.server_ips.value'
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

### Hetzner Console

View resources in Hetzner Console:
1. Go to https://console.hetzner.cloud/
2. Select your project
3. View:
   - Servers
   - Volumes
   - Networks
   - Firewalls

## Troubleshooting

### Common Issues

**Error: "Invalid authentication credentials"**
- Solution: Check API token is correct
- Verify: Token has Read & Write permissions
- Try: Generate new token

**Error: "Server type not available in location"**
- Solution: Try different location
- Check: `hcloud server-type list`
- Alternative: Use different server type

**Error: "Resource limit reached"**
- Solution: Hetzner has default limits for new accounts
- Contact: Hetzner support to increase limits
- Initial limits: ~10 servers, depends on account age

**Error: "IP address exhausted"**
- Solution: Rare, but try different location
- Alternative: Wait and retry

**Error: "Volume limit reached"**
- Solution: Default limit is 50 volumes per project
- Contact: Support for increase if needed

### Debugging Tips

Enable debug logging:
```bash
./exasol --log-level debug deploy --deployment-dir ./my-hetzner-deployment
```

Use hcloud CLI:
```bash
# Login
hcloud context create exasol-deployer
# Enter your token when prompted

# List servers
hcloud server list

# Describe server
hcloud server describe SERVER_NAME

# List volumes
hcloud volume list

# View firewall
hcloud firewall list
hcloud firewall describe FIREWALL_NAME
```

View Terraform state:
```bash
cd ./my-hetzner-deployment
tofu show
tofu output -json | jq
```

## Cleanup

Destroy all Hetzner resources:

```bash
./exasol destroy --deployment-dir ./my-hetzner-deployment
```

Verify in Hetzner Console that all resources are deleted:
- Servers (should be empty)
- Volumes (should be empty)
- Networks (should be empty or only default)
- Firewall rules (should be empty)

**Important**: Billing stops immediately when resources are deleted.

## Additional Resources

- [Hetzner Cloud Documentation](https://docs.hetzner.com/cloud/)
- [Hetzner Cloud API](https://docs.hetzner.cloud/)
- [hcloud CLI](https://github.com/hetznercloud/cli)
- [Hetzner Pricing](https://www.hetzner.com/cloud)
- [OpenTofu Hetzner Provider](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs)
- [Hetzner Status Page](https://status.hetzner.com/)

## Security Best Practices

1. **Protect API Token**: Never commit to version control
2. **Use Environment Variables**: Store token securely
3. **Restrict CIDR**: Always limit access to known IPs
4. **Enable Firewall**: Use Hetzner's firewall feature
5. **Regular Backups**: Enable automated backups for production
6. **Use Private Networks**: Isolate cluster communication
7. **Rotate Tokens**: Regenerate API tokens periodically
8. **Monitor Access**: Check server logs for suspicious activity
9. **Enable 2FA**: On Hetzner account
10. **Limit Token Scope**: Use Read-only tokens where possible

## Hetzner-Specific Features

### Volume Snapshots

Create volume backups:
```bash
# Using hcloud CLI
hcloud volume create-snapshot VOLUME_ID --description "backup-$(date +%Y%m%d)"

# List snapshots
hcloud volume list-snapshots VOLUME_ID
```

In Hetzner Console:
1. Go to Volumes
2. Click on volume
3. Click "Snapshots" tab
4. Click "Create Snapshot"

### Server Backups

Enable automated backups:
```bash
# Using hcloud CLI
hcloud server enable-backup SERVER_NAME

# Disable backups
hcloud server disable-backup SERVER_NAME
```

In Console:
1. Go to server
2. Click "Backups" tab
3. Toggle "Enable Backups"

Cost: 20% of server price (e.g., €10/month server = €2/month for backups)

### Floating IPs

For high availability (advanced):
```bash
# Create floating IP
hcloud floating-ip create --type ipv4 --home-location nbg1

# Assign to server
hcloud floating-ip assign FLOATING_IP_ID SERVER_ID
```

Allows moving IP between servers during maintenance.

### Private Networks

For enhanced security:
```bash
# Create private network
hcloud network create --name exasol-private --ip-range 10.0.0.0/16

# Attach servers to network
hcloud server attach-to-network SERVER_NAME --network exasol-private --ip 10.0.1.2
```

Keeps cluster communication off public internet.

## Performance Tips

1. **Use CCX series**: Dedicated CPUs for consistent performance
2. **Volumes in same location**: Ensure volumes and servers are co-located
3. **Private networks**: Use for inter-node communication (lower latency)
4. **Local SSD**: Use for temporary/cache data
5. **Network optimization**: Hetzner provides excellent network performance within same location

## Cost Monitoring

View costs in Hetzner Console:
1. Go to Billing
2. View current month costs
3. Download invoices
4. Set up billing alerts (in account settings)

Hetzner provides:
- Transparent hourly pricing
- Monthly invoices
- No hidden costs
- Simple, predictable billing

## Next Steps

- [Return to Cloud Setup Guide](CLOUD_SETUP.md)
- [Main README](../README.md)
- Consider enabling automated backups for production
- Set up private networks for enhanced security
- Create volume snapshots before major changes
