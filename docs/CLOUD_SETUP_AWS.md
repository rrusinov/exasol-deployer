# AWS (Amazon Web Services) Setup Guide

This guide provides detailed instructions for setting up AWS credentials and deploying Exasol on AWS.

## Prerequisites

- AWS account with appropriate permissions
- OpenTofu (or Terraform) installed
- Ansible installed
- jq installed

**Note**: AWS CLI is **not required**. OpenTofu reads credentials directly from `~/.aws/credentials` and `~/.aws/config`.

## Step 1: Create AWS Account

If you don't have an AWS account:

1. Go to https://aws.amazon.com/
2. Click "Create an AWS Account"
3. Follow the registration process
4. Complete billing information setup

## Step 2: Create IAM User

For security, create a dedicated IAM user for Exasol deployments instead of using your root account:

1. **Login to AWS Console**: https://console.aws.amazon.com/
2. **Navigate to IAM**: Services → IAM → Users
3. **Create User**:
   - Click "Add users"
   - User name: `exasol-deployer`
   - Select "Programmatic access"
   - Click "Next: Permissions"

4. **Set Permissions**:
   - Choose "Attach existing policies directly"
   - Attach these policies:
     - `AmazonEC2FullAccess` (for instances and networking)
     - `AmazonVPCFullAccess` (for VPC, subnets, security groups)
   - Click "Next: Tags"

5. **Add Tags** (optional):
   - Key: `Purpose`, Value: `Exasol Deployer`
   - Click "Next: Review"

6. **Create User**:
   - Review settings
   - Click "Create user"
   - **IMPORTANT**: Save the Access Key ID and Secret Access Key

## Step 3: Configure AWS Credentials

### Option 1: Manual Configuration (Recommended)

Create credentials file without AWS CLI:

```bash
# Create AWS directory
mkdir -p ~/.aws

# Create credentials file
cat > ~/.aws/credentials <<EOF
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
EOF

# Create config file (optional)
cat > ~/.aws/config <<EOF
[default]
region = us-east-1
output = json
EOF

# Set proper permissions
chmod 600 ~/.aws/credentials
chmod 600 ~/.aws/config
```

Replace `YOUR_ACCESS_KEY_ID` and `YOUR_SECRET_ACCESS_KEY` with values from Step 2.

### Option 2: Using AWS CLI (If Installed)

If you have AWS CLI installed:

```bash
aws configure --profile default
```

Enter:
- AWS Access Key ID: `YOUR_ACCESS_KEY_ID`
- AWS Secret Access Key: `YOUR_SECRET_ACCESS_KEY`
- Default region name: `us-east-1`
- Default output format: `json`

### Multiple AWS Profiles

To manage multiple AWS accounts:

```bash
# Add to ~/.aws/credentials
[production]
aws_access_key_id = PROD_ACCESS_KEY
aws_secret_access_key = PROD_SECRET_KEY

[development]
aws_access_key_id = DEV_ACCESS_KEY
aws_secret_access_key = DEV_SECRET_KEY
```

Use with deployer:
```bash
./exasol init --cloud-provider aws --aws-profile production
```

## Step 4: Verify Credentials

Test that credentials are working:

```bash
# If AWS CLI is installed
aws sts get-caller-identity --profile default

# Without AWS CLI - check files exist
test -f ~/.aws/credentials && echo "✓ AWS credentials file exists"
test -f ~/.aws/config && echo "✓ AWS config file exists"
```

## Step 5: Choose AWS Region

Select a region close to your users for lower latency. Common regions:

| Region Code | Location | Notes |
|-------------|----------|-------|
| `us-east-1` | N. Virginia | Default, cheapest |
| `us-east-2` | Ohio | Good for US Central |
| `us-west-1` | N. California | US West Coast |
| `us-west-2` | Oregon | US West Coast |
| `eu-west-1` | Ireland | Europe |
| `eu-central-1` | Frankfurt | Europe |
| `ap-southeast-1` | Singapore | Asia Pacific |
| `ap-northeast-1` | Tokyo | Asia Pacific |

Full list: https://docs.aws.amazon.com/general/latest/gr/rande.html

## Step 6: Initialize Exasol Deployment

### Basic Deployment

Single-node deployment with defaults:

```bash
./exasol init \
  --cloud-provider aws \
  --deployment-dir ./my-aws-deployment
```

### Production Deployment

Multi-node cluster with specific configuration:

```bash
./exasol init \
  --cloud-provider aws \
  --deployment-dir ./prod-cluster \
  --db-version exasol-2025.1.4 \
  --cluster-size 4 \
  --instance-type c7a.16xlarge \
  --data-volume-size 1000 \
  --aws-region us-east-1 \
  --aws-profile production \
  --owner "production-team" \
  --allowed-cidr "10.0.0.0/8"
```

### Development with Spot Instances

Save up to 70% with spot instances (suitable for dev/test):

```bash
./exasol init \
  --cloud-provider aws \
  --deployment-dir ./dev-cluster \
  --cluster-size 2 \
  --aws-spot-instance \
  --aws-region us-west-2 \
  --owner "dev-team"
```

## AWS-Specific Options

| Flag | Description | Default |
|------|-------------|---------|
| `--aws-region` | AWS region for deployment | `us-east-1` |
| `--aws-profile` | AWS profile from credentials | `default` |
| `--aws-spot-instance` | Enable spot instances | `false` |

## Instance Types

The deployer automatically selects appropriate instance types based on database version, but you can override:

### Recommended Instance Types (x86_64)

| Instance Type | vCPUs | Memory | Network | Use Case |
|---------------|-------|--------|---------|----------|
| `m6idn.large` | 2 | 8 GB | Up to 25 Gbps | Small dev/test |
| `m6idn.xlarge` | 4 | 16 GB | Up to 25 Gbps | Small production |
| `c7a.8xlarge` | 32 | 64 GB | 12.5 Gbps | Medium production |
| `c7a.16xlarge` | 64 | 128 GB | 25 Gbps | Large production |
| `c7a.48xlarge` | 192 | 384 GB | 50 Gbps | Very large production |

### Recommended Instance Types (ARM64 / Graviton)

| Instance Type | vCPUs | Memory | Network | Use Case |
|---------------|-------|--------|---------|----------|
| `c7g.2xlarge` | 8 | 16 GB | Up to 15 Gbps | Small production |
| `c7g.8xlarge` | 32 | 64 GB | 15 Gbps | Medium production |
| `c7g.16xlarge` | 64 | 128 GB | 30 Gbps | Large production |

Choose instances with:
- **Compute-optimized (C family)**: Best for Exasol workloads
- **Local NVMe storage (instances with 'dn' suffix)**: Best performance
- **Enhanced networking**: 10 Gbps+ recommended

Full instance types: https://aws.amazon.com/ec2/instance-types/

## Storage Configuration

### Data Volumes

```bash
--data-volume-size 500        # 500 GB per volume
--data-volumes-per-node 2     # 2 volumes per node
```

This creates 2x 500 GB = 1 TB total data storage per node.

AWS volume types used:
- **gp3** (General Purpose SSD): Default, good performance/cost balance
- 3000 IOPS baseline, burstable to 16000
- 125 MB/s baseline throughput

### Root Volumes

```bash
--root-volume-size 100        # 100 GB for OS and applications
```

## Networking and Security

### CIDR Configuration

**WARNING**: The default `0.0.0.0/0` allows access from anywhere. Always restrict:

```bash
# Single IP
--allowed-cidr "203.0.113.42/32"

# Subnet
--allowed-cidr "203.0.113.0/24"

# Corporate network
--allowed-cidr "10.0.0.0/8"
```

### Security Groups

The deployer creates security groups with these rules:
- **Port 22**: SSH access (restricted to allowed_cidr)
- **Port 8563**: Exasol database (restricted to allowed_cidr)
- **Port 443**: Admin UI (restricted to allowed_cidr)
- **All internal traffic**: Between cluster nodes (unrestricted)

### VPC Configuration

The deployer automatically creates:
- New VPC with CIDR `10.0.0.0/16`
- Public subnet for Exasol nodes
- Internet gateway for external access
- Route tables
- Security groups

All resources are tagged with the owner tag for tracking.

## Cost Optimization

### Spot Instances

Enable spot instances to save up to 70%:

```bash
./exasol init --cloud-provider aws --aws-spot-instance
```

**Important Notes**:
- Spot instances can be interrupted with 2-minute warning
- Best for development, testing, and fault-tolerant workloads
- Not recommended for production databases
- No additional charge for using spot instances

### Right-Sizing Strategy

1. **Start small**: Begin with `m6idn.large` for testing
2. **Monitor performance**: Use AWS CloudWatch
3. **Scale up**: Increase instance type if needed
4. **Optimize storage**: Use only required volume sizes

### Cost Monitoring

View costs by owner tag in AWS Cost Explorer:
```bash
./exasol init --owner "team-name-project"
```

Filter in AWS Console: Cost Explorer → Group by → Tag → owner

## Step 7: Deploy

After initialization, deploy the infrastructure:

```bash
./exasol deploy --deployment-dir ./my-aws-deployment
```

This will:
1. Create VPC, subnets, security groups
2. Launch EC2 instances
3. Attach EBS volumes
4. Configure networking
5. Install and configure Exasol

Deployment takes approximately 15-20 minutes.

## Step 8: Verify Deployment

Check deployment status:

```bash
./exasol status --deployment-dir ./my-aws-deployment
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
# Using generated SSH config
ssh -F ./my-aws-deployment/ssh_config n11

# Direct SSH (find IP in outputs)
ssh -i ./my-aws-deployment/exasol-key.pem ubuntu@<public-ip>
```

### Database Connection

Find connection details:
```bash
cd ./my-aws-deployment
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

## Troubleshooting

### Common Issues

**Error: "Error launching source instance: InsufficientInstanceCapacity"**
- Solution: Try different region or instance type
- Alternative: Wait and retry later

**Error: "UnauthorizedOperation: You are not authorized to perform this operation"**
- Solution: Check IAM permissions, ensure EC2FullAccess policy is attached
- Verify: `aws sts get-caller-identity --profile default`

**Error: "VpcLimitExceeded: The maximum number of VPCs has been reached"**
- Solution: Delete unused VPCs or request limit increase
- Check: AWS Console → VPC Dashboard

**Error: "RequestLimitExceeded: Request limit exceeded"**
- Solution: AWS API rate limiting, wait and retry
- Usually resolves automatically after a few minutes

### Debugging Tips

Enable debug logging:
```bash
./exasol --log-level debug deploy --deployment-dir ./my-aws-deployment
```

Check Terraform state:
```bash
cd ./my-aws-deployment
tofu show
```

View Terraform outputs:
```bash
tofu output -json | jq
```

## Cleanup

Destroy all AWS resources:

```bash
./exasol destroy --deployment-dir ./my-aws-deployment
```

Verify in AWS Console that all resources are deleted:
- EC2 Dashboard → Instances
- VPC Dashboard → Your VPCs
- EBS Dashboard → Volumes

## Additional Resources

- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [AWS Pricing Calculator](https://calculator.aws/)
- [AWS Free Tier](https://aws.amazon.com/free/)
- [OpenTofu AWS Provider](https://opentofu.org/docs/language/providers/requirements/)

## Security Best Practices

1. **Use IAM roles**: When deploying from EC2, use IAM roles instead of credentials
2. **Enable MFA**: Protect your AWS account with multi-factor authentication
3. **Rotate credentials**: Regularly update access keys
4. **Restrict CIDR**: Never use `0.0.0.0/0` in production
5. **Enable CloudTrail**: Audit all API calls
6. **Use separate accounts**: Different accounts for dev/staging/production

## Next Steps

- [Return to Cloud Setup Guide](CLOUD_SETUP.md)
- [Main README](../README.md)
- Deploy on another cloud provider for comparison
