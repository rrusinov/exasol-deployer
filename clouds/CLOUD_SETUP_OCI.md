# Oracle Cloud Infrastructure (OCI) Setup Guide

This guide covers setting up Oracle Cloud Infrastructure (OCI) for Exasol database deployments.

## Prerequisites

- OCI account with sufficient credits/budget
- OCI CLI installed (optional, for easier setup)
- Compartment with appropriate permissions

## 1. Account Setup

### Create OCI Account
1. Sign up at [cloud.oracle.com](https://cloud.oracle.com)
2. Complete identity verification
3. Add payment method or use free tier credits

### Get Compartment OCID
1. Navigate to **Identity & Security** → **Compartments**
2. Find your target compartment (or create one)
3. Copy the **OCID** - you'll need this for deployment

**To add compartment OCID to your existing config:**
```bash
echo "compartment=ocid1.compartment.oc1..your-compartment-ocid" >> ~/.oci/config
```

## 2. API Credentials Setup

### Option A: Using OCI CLI (Recommended)
```bash
# Install OCI CLI
pip install oci-cli

# Configure credentials interactively
oci setup config

# Test configuration
oci iam region list
```

This creates `~/.oci/config` with your credentials.

### Option B: Manual Setup
1. **Generate API Key Pair**:
   ```bash
   mkdir -p ~/.oci
   openssl genrsa -out ~/.oci/oci_api_key.pem 2048
   openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
   chmod 600 ~/.oci/oci_api_key.pem
   ```

2. **Add Public Key to OCI**:
   - Go to **Identity & Security** → **Users** → Your User
   - Click **API Keys** → **Add API Key**
   - Upload `~/.oci/oci_api_key_public.pem`
   - Copy the fingerprint

3. **Create Config File** (`~/.oci/config`):
   ```ini
   [DEFAULT]
   user=ocid1.user.oc1..your-user-ocid
   fingerprint=your-key-fingerprint
   key_file=~/.oci/oci_api_key.pem
   tenancy=ocid1.tenancy.oc1..your-tenancy-ocid
   region=us-ashburn-1
   compartment=ocid1.compartment.oc1..your-compartment-ocid
   ```

   **Note**: The `compartment` field is optional. If not specified, you must provide `--oci-compartment-ocid` during deployment.

## 3. Required Permissions

Your user needs these IAM policies in the target compartment:

```
Allow group <your-group> to manage compute-management-family in compartment <compartment-name>
Allow group <your-group> to manage instance-family in compartment <compartment-name>
Allow group <your-group> to manage volume-family in compartment <compartment-name>
Allow group <your-group> to manage virtual-network-family in compartment <compartment-name>
Allow group <your-group> to manage security-lists in compartment <compartment-name>
Allow group <your-group> to use subnets in compartment <compartment-name>
Allow group <your-group> to use vnics in compartment <compartment-name>
```

## 4. Region Selection

Choose a region based on:
- **Latency**: Closest to your users
- **Compliance**: Data residency requirements
- **Availability**: Instance types and capacity

Popular regions:
- `us-ashburn-1` (US East)
- `us-phoenix-1` (US West)
- `eu-frankfurt-1` (Europe)
- `ap-tokyo-1` (Asia Pacific)

## 5. Instance Types

OCI supports both x86_64 and ARM64 architectures:

**x86_64 (Intel/AMD)**:
- `VM.Standard.E4.Flex` - Flexible shapes (recommended)
- `VM.Standard3.Flex` - Previous generation flexible
- `BM.Standard.E4.128` - Bare metal (high performance)

**ARM64 (Ampere)**:
- `VM.Standard.A1.Flex` - ARM-based flexible shapes (cost-effective)

## 6. Deployment Examples

### Basic Single Node
```bash
./exasol init \
  --cloud-provider oci \
  --deployment-dir ./my-oci-deployment \
  --oci-region us-ashburn-1 \
  --oci-compartment-ocid ocid1.compartment.oc1..your-compartment-ocid
```

### Multi-Node Cluster
```bash
./exasol init \
  --cloud-provider oci \
  --deployment-dir ./my-oci-cluster \
  --cluster-size 3 \
  --oci-region us-ashburn-1 \
  --oci-compartment-ocid ocid1.compartment.oc1..your-compartment-ocid \
  --instance-type VM.Standard.E4.Flex \
  --data-volumes-per-node 2 \
  --data-volume-size 100
```

### ARM64 Deployment (Cost-Optimized)
```bash
./exasol init \
  --cloud-provider oci \
  --deployment-dir ./my-oci-arm \
  --oci-region us-ashburn-1 \
  --oci-compartment-ocid ocid1.compartment.oc1..your-compartment-ocid \
  --instance-type VM.Standard.A1.Flex \
  --db-version exasol-2025.1.8-arm64
```

## 7. Cost Optimization

### Always Free Tier
- 2x AMD VM.Standard.E2.1.Micro instances
- 4x ARM Ampere A1 cores + 24GB RAM
- 200GB block storage

### Flexible Shapes
Use `.Flex` instance types to customize CPU/memory:
```bash
# Will be configured with 2 OCPUs and 8GB RAM by default
--instance-type VM.Standard.E4.Flex
```

### Power Control
OCI supports automatic start/stop:
```bash
# Stop instances to save ~75% costs
./exasol stop --deployment-dir ./my-oci-deployment

# Start instances when needed
./exasol start --deployment-dir ./my-oci-deployment
```

## 8. Networking

### Default Configuration
- Creates dedicated VCN (Virtual Cloud Network)
- Public subnet with internet gateway
- Security list with required ports (22, 443, 8563, 20002, 20003, 2581)
- VXLAN overlay for multicast (if enabled)

### Custom CIDR
```bash
--allowed-cidr 10.0.0.0/8  # Restrict access to private networks
```

## 9. Storage

### Block Volumes
- **iSCSI attachment** (default)
- **Persistent device names**: `/dev/oracleoci/oraclevd*`
- **Performance**: Up to 32,000 IOPS per volume
- **Backup**: Automatic backups available

### Boot Volumes
- **Default**: 50GB
- **Customizable**: `--root-volume-size 100`
- **Performance**: High-performance by default

## 10. Troubleshooting

### Common Issues

**"Compartment OCID required"**:
```bash
# Get compartment OCID from OCI Console
oci iam compartment list --all
```

**"Authentication failed" or "NotAuthenticated"**:

*Issue 1: Passphrase-protected private key*
```bash
# OCI CLI requires unencrypted private keys
# If you get "Private key passphrase:" prompt, regenerate without passphrase:
cd ~/.oci
openssl genrsa -out oci_api_key_new.pem 2048
openssl rsa -pubout -in oci_api_key_new.pem -out oci_api_key_new_public.pem

# Add the new public key to OCI Console and update fingerprint in ~/.oci/config
```

*Issue 2: API key propagation delay*
```bash
# After adding a new API key to OCI Console, wait 30-60 seconds
# The key needs time to propagate through OCI's authentication system
# Test with: oci iam region list
```

*Issue 3: File permissions*
```bash
# Verify OCI config
oci setup repair-file-permissions --file ~/.oci/config
oci iam region list
```

**"Shape not available"**:
```bash
# Check available shapes in region
oci compute shape list --compartment-id <compartment-ocid>
```

**"Service limit exceeded"**:
- Request service limit increase in OCI Console
- Try different availability domain
- Use different instance type

### Logs and Debugging
```bash
# Check deployment logs
./exasol health --deployment-dir ./my-oci-deployment

# SSH to instances
ssh -F ./my-oci-deployment/ssh_config n11

# Check iSCSI connections
sudo iscsiadm -m session -P 3
```

## 11. Security Best Practices

1. **Use dedicated compartment** for Exasol resources
2. **Restrict CIDR blocks** to known networks
3. **Enable OCI Security Zones** for additional protection
4. **Regular key rotation** for API keys
5. **Monitor with OCI Audit** service

## 12. Support and Resources

- **OCI Documentation**: [docs.oracle.com](https://docs.oracle.com/iaas/)
- **OCI CLI Reference**: [docs.oracle.com/iaas/tools/oci-cli/](https://docs.oracle.com/en-us/iaas/tools/oci-cli/)
- **Community**: [community.oracle.com](https://community.oracle.com/customerconnect/)
- **Support**: [support.oracle.com](https://support.oracle.com/)

---

**Next Steps**: After setup, proceed with [deployment](../README.md#quick-start) using the examples above.
