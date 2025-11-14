# DigitalOcean Setup Guide

This guide provides detailed instructions for setting up DigitalOcean credentials and deploying Exasol on DigitalOcean.

## Prerequisites

- DigitalOcean account
- OpenTofu (or Terraform) installed
- Ansible installed
- jq installed

## Why DigitalOcean?

DigitalOcean is known for:
- **Simple and predictable pricing**: Easy to understand costs
- **Developer-friendly**: Great documentation and UI
- **Fast provisioning**: Droplets ready in under a minute
- **Global reach**: 14+ datacenter regions worldwide
- **Generous free credits**: Often offers promotional credits
- **All-SSD storage**: Fast disk performance included

Best for: Small to medium deployments, development, and teams wanting simplicity.

## Step 1: Create DigitalOcean Account

1. Go to https://www.digitalocean.com/
2. Click "Sign Up"
3. Register with email or GitHub account
4. Verify email address
5. Add payment method (credit card or PayPal)

### Free Credits

DigitalOcean frequently offers:
- $200 credit for new accounts (first 60 days)
- Check for current promotions at signup
- Various partner offers for extra credits

## Step 2: Generate API Token

1. **Login to DigitalOcean**: https://cloud.digitalocean.com/
2. **Navigate to API**:
   - Click on "API" in left sidebar
   - Or go directly to: https://cloud.digitalocean.com/account/api/tokens
3. **Generate New Token**:
   - Click "Generate New Token"
   - Token name: "Exasol Deployer"
   - Scopes: Select both "Read" and "Write" (required)
   - Click "Generate Token"
4. **Save Token**: Copy the token immediately - it won't be shown again!

**Important**: This token has full access to your DigitalOcean account. Keep it secure!

### Secure Token Storage

```bash
# Store token securely in environment variable
export DIGITALOCEAN_TOKEN="your-token-here"

# Or store in a secure file
echo "your-token-here" > ~/.digitalocean_token
chmod 600 ~/.digitalocean_token

# Use in deployment
export DIGITALOCEAN_TOKEN=$(cat ~/.digitalocean_token)
```

**Never commit tokens to version control!**

## Step 3: Choose DigitalOcean Region

DigitalOcean has datacenters worldwide. Choose based on latency requirements.

### Available Regions

| Region Code | Location | Notes |
|------------|----------|-------|
| `nyc1` | New York City, USA | East Coast US, well-established |
| `nyc3` | New York City, USA | Default, newer datacenter |
| `sfo3` | San Francisco, USA | West Coast US |
| `tor1` | Toronto, Canada | Canada |
| `lon1` | London, UK | United Kingdom |
| `ams3` | Amsterdam, Netherlands | Europe |
| `fra1` | Frankfurt, Germany | Central Europe |
| `sgp1` | Singapore | Asia Pacific |
| `blr1` | Bangalore, India | South Asia |
| `syd1` | Sydney, Australia | Australia/Oceania |

### Check Droplet Availability

```bash
# Install doctl CLI (optional but useful)
# macOS
brew install doctl

# Linux (snap)
snap install doctl

# Authenticate
doctl auth init
# Enter your API token when prompted

# List regions
doctl compute region list

# List droplet sizes
doctl compute size list
```

## Step 4: Initialize Exasol Deployment

### Basic Deployment

Single-node deployment with defaults:

```bash
./exasol init \
  --cloud-provider digitalocean \
  --digitalocean-token "$DIGITALOCEAN_TOKEN" \
  --deployment-dir ./my-do-deployment
```

**Warning**: Never commit the token to version control. Use environment variables.

**Architecture note**: DigitalOcean currently offers only x86_64 droplets. `exasol init` will reject `--db-version` values that target arm64 when `--cloud-provider digitalocean` is used.

### Production Deployment

Multi-node cluster with specific configuration:

```bash
./exasol init \
  --cloud-provider digitalocean \
  --digitalocean-token "$DIGITALOCEAN_TOKEN" \
  --deployment-dir ./prod-cluster \
  --digitalocean-region nyc3 \
  --db-version exasol-2025.1.4 \
  --cluster-size 4 \
  --instance-type c-8 \
  --data-volume-size 500 \
  --owner "production-team" \
  --allowed-cidr "203.0.113.0/24"
```

### Development Deployment

Cost-effective small cluster:

```bash
./exasol init \
  --cloud-provider digitalocean \
  --digitalocean-token "$DIGITALOCEAN_TOKEN" \
  --deployment-dir ./dev-cluster \
  --cluster-size 2 \
  --instance-type s-2vcpu-4gb \
  --data-volume-size 100 \
  --digitalocean-region sfo3 \
  --owner "dev-team"
```

## DigitalOcean-Specific Options

| Flag | Description | Default |
|------|-------------|---------|
| `--digitalocean-region` | Datacenter region | `nyc3` |
| `--digitalocean-token` | DigitalOcean API token (required) | - |

**Note**: DigitalOcean does not support spot instances - all droplets are on-demand.

## Droplet Sizes (Instance Types)

DigitalOcean offers simple, straightforward droplet types with all-SSD storage.

### Basic Droplets - Development

| Droplet Size | vCPUs | Memory | Disk | Transfer | Price/month* | Use Case |
|-------------|-------|--------|------|----------|--------------|----------|
| `s-1vcpu-1gb` | 1 | 1 GB | 25 GB | 1 TB | $6 | Small dev |
| `s-1vcpu-2gb` | 1 | 2 GB | 50 GB | 2 TB | $12 | Dev/test |
| `s-2vcpu-2gb` | 2 | 2 GB | 60 GB | 3 TB | $18 | Small apps |
| `s-2vcpu-4gb` | 2 | 4 GB | 80 GB | 4 TB | $24 | Dev cluster |
| `s-4vcpu-8gb` | 4 | 8 GB | 160 GB | 5 TB | $48 | Small production |

*Current pricing as of 2025, check https://www.digitalocean.com/pricing for latest

### General Purpose - Production

| Droplet Size | vCPUs | Memory | Disk | Transfer | Price/month* | Use Case |
|-------------|-------|--------|------|----------|--------------|----------|
| `g-2vcpu-8gb` | 2 | 8 GB | 25 GB | 4 TB | $60 | Small production |
| `g-4vcpu-16gb` | 4 | 16 GB | 50 GB | 5 TB | $120 | Medium production |
| `g-8vcpu-32gb` | 8 | 32 GB | 100 GB | 6 TB | $240 | Large production |
| `g-16vcpu-64gb` | 16 | 64 GB | 200 GB | 7 TB | $480 | Very large production |
| `g-32vcpu-128gb` | 32 | 128 GB | 400 GB | 8 TB | $960 | Enterprise |

### CPU-Optimized - Recommended for Exasol

| Droplet Size | vCPUs | Memory | Disk | Transfer | Price/month* | Use Case |
|-------------|-------|--------|------|----------|--------------|----------|
| `c-2` | 2 | 4 GB | 25 GB | 4 TB | $40 | Small production |
| `c-4` | 4 | 8 GB | 50 GB | 4 TB | $80 | Medium production |
| `c-8` | 8 | 16 GB | 100 GB | 5 TB | $160 | Large production |
| `c-16` | 16 | 32 GB | 200 GB | 6 TB | $320 | Very large production |
| `c-32` | 32 | 64 GB | 400 GB | 7 TB | $640 | Maximum performance |
| `c-48` | 48 | 90 GB | 600 GB | 8 TB | $960 | Enterprise |

### Memory-Optimized

| Droplet Size | vCPUs | Memory | Disk | Transfer | Price/month* | Use Case |
|-------------|-------|--------|------|----------|--------------|----------|
| `m-2vcpu-16gb` | 2 | 16 GB | 50 GB | 4 TB | $90 | Memory-intensive |
| `m-4vcpu-32gb` | 4 | 32 GB | 100 GB | 5 TB | $180 | High memory |
| `m-8vcpu-64gb` | 8 | 64 GB | 200 GB | 6 TB | $360 | Very high memory |
| `m-16vcpu-128gb` | 16 | 128 GB | 400 GB | 7 TB | $720 | Maximum memory |

### Choosing Droplet Sizes

- **Basic (s-*)**: Development, testing, small apps
- **General Purpose (g-*)**: Balanced workloads, production
- **CPU-Optimized (c-*)**: Best for Exasol, high-performance computing
- **Memory-Optimized (m-*)**: Large datasets, in-memory processing

**For Exasol**: CPU-Optimized droplets (c-*) provide best price/performance.

Full pricing: https://www.digitalocean.com/pricing

## Storage Configuration

### Block Storage Volumes

```bash
--data-volume-size 500        # 500 GB per volume
--data-volumes-per-node 2     # 2 volumes per node
```

This creates 2x 500 GB = 1 TB total data storage per node.

DigitalOcean volume characteristics:
- **SSD-based**: Fast performance
- **Scalable**: 1 GB to 16 TB per volume
- **High availability**: Replicated for durability
- **Snapshots available**: Point-in-time backups
- **Pricing**: $0.10/GB per month (~$10 per 100 GB)

### Droplet Storage

Each droplet includes SSD storage:
- Local to droplet
- Fast access
- Included in droplet price
- Not recommended for critical data
- Use volumes for database storage

## Networking and Security

### CIDR Configuration

**WARNING**: Default `0.0.0.0/0` allows access from anywhere. Always restrict:

```bash
# Single IP
--allowed-cidr "203.0.113.42/32"

# Office network
--allowed-cidr "203.0.113.0/24"

# VPN network
--allowed-cidr "10.0.0.0/8"
```

### Cloud Firewalls

The deployer creates firewall with these rules:
- **Port 22**: SSH access (restricted to allowed_cidr)
- **Port 8563**: Exasol database (restricted to allowed_cidr)
- **Port 443**: Admin UI (restricted to allowed_cidr)
- **Internal traffic**: Between cluster droplets (unrestricted)

### Networking Features

DigitalOcean provides:
- **Public IPv4**: One per droplet (included)
- **Public IPv6**: Available (free)
- **Private networking**: VPC for isolated communication (free)
- **Floating IPs**: Reserved, movable IPs ($4/month per IP)
- **Generous bandwidth**: Several TB included per droplet
- **DDoS protection**: Automatic protection included

## Cost Optimization

### No Spot Instances

DigitalOcean doesn't offer spot/preemptible instances, but:
- Competitive base pricing
- Simple, transparent billing
- Generous bandwidth included
- All-SSD storage included

### Cost Comparison Example

4-node production cluster (c-8 = 8 vCPU, 16 GB):
- **Droplets**: 4 × $160 = $640/month
- **Volumes**: 4 nodes × 500 GB × $0.10 = $200/month
- **Total**: ~$840/month

### Volume Snapshots

Volume snapshots for backups:
- $0.05/GB per month
- Charged only for used space (compressed)
- Good for disaster recovery

### Droplet Snapshots

Droplet snapshots:
- $0.05/GB per month
- Full droplet image
- Can create new droplets from snapshot

### Reserved Instances

DigitalOcean doesn't have reserved instances, but:
- Pricing is already competitive
- Hourly billing (charged monthly)
- No long-term commitments required

## Step 5: Deploy

After initialization, deploy the infrastructure:

```bash
./exasol deploy --deployment-dir ./my-do-deployment
```

This will:
1. Create VPC (private network)
2. Launch droplets in specified region
3. Attach block storage volumes
4. Configure cloud firewall
5. Install and configure Exasol

Deployment takes approximately 10-15 minutes (DigitalOcean is fast!).

## Step 6: Verify Deployment

Check deployment status:

```bash
./exasol status --deployment-dir ./my-do-deployment
```

Expected output:
```json
{
  "status": "database_ready",
  "db_version": "exasol-2025.1.4",
  "architecture": "x86_64",
  "terraform_state_exists": true,
  "created_at": "2025-01-15T10:30:00Z",
  "updated_at": "2025-01-15T10:40:00Z"
}
```

## Accessing Your Cluster

### SSH Access

```bash
# Using generated SSH config
ssh -F ./my-do-deployment/ssh_config n11

# Direct SSH
ssh -i ./my-do-deployment/exasol-key.pem root@<public-ip>
```

**Note**: DigitalOcean droplets use `root` user by default.

### Database Connection

Find connection details:
```bash
cd ./my-do-deployment
tofu output -json | jq -r '.droplet_ips.value'
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

### DigitalOcean Console

View resources in DigitalOcean Console:
1. Go to https://cloud.digitalocean.com/
2. View:
   - Droplets
   - Volumes
   - Networking → VPC
   - Networking → Firewalls

## Troubleshooting

### Common Issues

**Error: "Invalid authentication token"**
- Solution: Check API token is correct
- Verify: Token has Read & Write scopes
- Try: Generate new token from console

**Error: "Droplet limit reached"**
- Solution: DigitalOcean has default limits for new accounts
- New accounts: Usually 5-10 droplets initially
- Contact: Support to increase limits
- Note: Limits increase automatically over time

**Error: "Volume limit reached"**
- Solution: Default limit is ~100 volumes
- Contact: Support for increase if needed
- Alternative: Use larger volumes instead of many small ones

**Error: "Size is not available in this region"**
- Solution: Try different region
- Check: `doctl compute size list --region nyc3`
- Alternative: Use different droplet size

**Error: "Unable to attach volume"**
- Solution: Volumes must be in same region as droplet
- Check: Both volume and droplet in same region
- Note: Cannot move volumes between regions

### Debugging Tips

Enable debug logging:
```bash
./exasol --log-level debug deploy --deployment-dir ./my-do-deployment
```

Use doctl CLI:
```bash
# Authenticate
doctl auth init

# List droplets
doctl compute droplet list

# Get droplet details
doctl compute droplet get DROPLET_ID

# List volumes
doctl compute volume list

# List firewalls
doctl compute firewall list
doctl compute firewall get FIREWALL_ID
```

View Terraform state:
```bash
cd ./my-do-deployment
tofu show
tofu output -json | jq
```

View droplet console (from web UI):
1. Go to Droplets
2. Click on droplet
3. Click "Access" tab
4. Launch "Droplet Console" for emergency access

## Cleanup

Destroy all DigitalOcean resources:

```bash
./exasol destroy --deployment-dir ./my-do-deployment
```

Verify in DigitalOcean Console that all resources are deleted:
- Droplets (should be empty)
- Volumes (should be empty)
- VPC (may remain, safe to keep or delete manually)
- Firewall (should be removed)

**Important**: Billing stops immediately when resources are deleted.

## Additional Resources

- [DigitalOcean Documentation](https://docs.digitalocean.com/)
- [DigitalOcean API Docs](https://docs.digitalocean.com/reference/api/)
- [doctl CLI](https://docs.digitalocean.com/reference/doctl/)
- [DigitalOcean Pricing](https://www.digitalocean.com/pricing)
- [OpenTofu DigitalOcean Provider](https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs)
- [DigitalOcean Community Tutorials](https://www.digitalocean.com/community/tutorials)

## Security Best Practices

1. **Protect API Token**: Never commit to version control
2. **Use Environment Variables**: Store token securely
3. **Restrict Firewall Rules**: Limit access to known IPs
4. **Enable VPC**: Use private networking for cluster
5. **Regular Backups**: Create volume snapshots
6. **Enable Monitoring**: Use DigitalOcean monitoring
7. **Rotate Tokens**: Regenerate API tokens periodically
8. **Enable 2FA**: On DigitalOcean account
9. **Review Access Logs**: Check droplet authentication logs
10. **Use SSH Keys**: Disable password authentication

## DigitalOcean-Specific Features

### Volume Snapshots

Create volume backups:

Using doctl:
```bash
# Create snapshot
doctl compute volume snapshot create VOLUME_ID \
  --snapshot-name "exasol-backup-$(date +%Y%m%d)"

# List snapshots
doctl compute volume snapshot list
```

In Console:
1. Go to Volumes
2. Click on volume
3. Click "Snapshots" tab
4. Click "Create Snapshot"

### Droplet Snapshots

Create full droplet image:

```bash
# Power off droplet first (important!)
doctl compute droplet-action power-off DROPLET_ID

# Create snapshot
doctl compute droplet-action snapshot DROPLET_ID \
  --snapshot-name "exasol-server-backup"

# Power back on
doctl compute droplet-action power-on DROPLET_ID
```

**Note**: Droplet must be powered off for consistent snapshot.

### Floating IPs

For high availability (advanced):

```bash
# Reserve floating IP
doctl compute floating-ip create --region nyc3

# Assign to droplet
doctl compute floating-ip-action assign FLOATING_IP DROPLET_ID
```

Allows moving IP between droplets during maintenance or failover.

Cost: $4/month per floating IP (free if assigned to active droplet).

### VPC (Private Networking)

For enhanced security:

```bash
# Create VPC
doctl vpcs create \
  --name exasol-private \
  --region nyc3 \
  --ip-range 10.110.0.0/20

# Droplets in same VPC can communicate privately
```

Keeps cluster communication off public internet (better security and performance).

### Monitoring and Alerts

Enable monitoring in Console:
1. Go to Droplet
2. Click "Monitoring" tab
3. View CPU, memory, disk, network graphs
4. Set up alerts for critical metrics

Free monitoring included:
- CPU usage
- Memory usage
- Disk I/O
- Network bandwidth
- Uptime checks

## Performance Tips

1. **Use CPU-Optimized**: c-* droplets for best database performance
2. **Volumes in same region**: Ensure volumes and droplets are co-located
3. **Use VPC**: Private networking for inter-node traffic
4. **Enable monitoring**: Track performance metrics
5. **Right-size volumes**: Match volume IOPS to workload (larger = more IOPS)

## Cost Monitoring

View costs in DigitalOcean Console:
1. Go to Billing
2. View current month costs
3. See resource breakdown
4. Download invoices
5. Set up billing alerts

DigitalOcean provides:
- Transparent hourly pricing (billed monthly)
- Simple invoices with resource details
- Bandwidth included (no surprise charges)
- Predictable costs

## Getting Help

DigitalOcean has excellent support:
- **Community**: https://www.digitalocean.com/community/questions
- **Tutorials**: Extensive step-by-step guides
- **Support Tickets**: Available based on account level
- **Documentation**: Comprehensive and well-maintained

## Next Steps

- [Return to Cloud Setup Guide](CLOUD_SETUP.md)
- [Main README](../README.md)
- Consider enabling volume snapshots for backups
- Set up VPC for enhanced security
- Enable monitoring and set up alerts
- Explore DigitalOcean Community tutorials
