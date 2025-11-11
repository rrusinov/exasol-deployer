# Exasol Cloud Deployer

A bash-based cloud deployer for Exasol database that uses OpenTofu (Terraform) and Ansible to provision and configure Exasol clusters on AWS. This tool simulates the interface of the binary Exasol deployer while providing full control over the deployment process.

## Features

- **Multiple Database Versions**: Support for multiple Exasol database versions and architectures (x86_64, arm64)
- **Configurable Deployments**: Customize cluster size, instance types, storage, and network settings
- **State Management**: Tracks deployment state with file-based locking for safe concurrent operations
- **Infrastructure as Code**: Uses OpenTofu/Terraform for reproducible infrastructure provisioning
- **Automated Configuration**: Ansible playbooks for complete cluster setup
- **Credential Management**: Secure password generation and storage

## Prerequisites

Before using this deployer, ensure you have the following installed:

- **OpenTofu** or Terraform (>= 1.0)
- **Ansible** (>= 2.9)
- **jq** (for JSON processing)
- **AWS CLI** (configured with appropriate credentials)
- **bash** (>= 4.0)

### Installation on macOS

```bash
# Install OpenTofu
brew install opentofu

# Install Ansible
brew install ansible

# Install jq
brew install jq

# Configure AWS CLI
aws configure --profile default
```

### Installation on Linux

```bash
# Install OpenTofu
# See: https://opentofu.org/docs/intro/install/

# Install Ansible
sudo apt-get update
sudo apt-get install -y ansible

# Install jq
sudo apt-get install -y jq

# Configure AWS CLI
aws configure --profile default
```

## Quick Start

### 1. List Available Database Versions

```bash
./exasol init --list-versions
```

Output:
```
8.0.0-x86_64
8.0.0-arm64
7.1.0-x86_64
```

### 2. Initialize a Deployment

```bash
# Initialize with default settings (single-node, default version)
./exasol init --deployment-dir ./my-deployment

# Initialize with specific version and cluster size
./exasol init \
  --deployment-dir ./my-deployment \
  --db-version 8.0.0-x86_64 \
  --cluster-size 4 \
  --instance-type c7a.16xlarge \
  --data-volume-size 500 \
  --aws-region us-east-1
```

### 3. Deploy the Infrastructure

```bash
./exasol deploy --deployment-dir ./my-deployment
```

This will:
1. Download required database files and binaries
2. Initialize OpenTofu/Terraform
3. Create AWS infrastructure (VPC, subnets, security groups, EC2 instances, EBS volumes)
4. Configure instances with Ansible
5. Set up the Exasol cluster

### 4. Check Deployment Status

```bash
./exasol status --deployment-dir ./my-deployment
```

Output (JSON):
```json
{
  "status": "database_ready",
  "db_version": "8.0.0-x86_64",
  "architecture": "x86_64",
  "terraform_state_exists": true,
  "created_at": "2025-01-15T10:30:00Z",
  "updated_at": "2025-01-15T10:45:00Z"
}
```

### 5. Destroy the Deployment

```bash
./exasol destroy --deployment-dir ./my-deployment
```

**Warning**: This will destroy all resources including data volumes. Make sure to backup any important data first.

## Commands

### `init`

Initialize a new deployment directory with configuration files.

```bash
./exasol init [flags]
```

**Flags:**
- `--db-version string`: Database version (format: X.Y.Z-ARCH, e.g., 8.0.0-x86_64)
- `--list-versions`: List all available database versions
- `--cluster-size number`: Number of nodes (default: 1)
- `--instance-type string`: EC2 instance type (auto-detected if not specified)
- `--data-volume-size number`: Data volume size in GB (default: 100)
- `--db-password string`: Database password (randomly generated if not specified)
- `--adminui-password string`: Admin UI password (randomly generated if not specified)
- `--owner string`: Owner tag for resources (default: "exasol-default")
- `--aws-region string`: AWS region (default: "us-east-1")
- `--aws-profile string`: AWS profile to use (default: "default")
- `--allowed-cidr string`: CIDR block for access (default: "0.0.0.0/0")

### `deploy`

Deploy infrastructure using an existing deployment directory.

```bash
./exasol deploy --deployment-dir ./my-deployment
```

### `status`

Get the current status of a deployment in JSON format.

```bash
./exasol status --deployment-dir ./my-deployment
```

**Status Values:**
- `initialized`: Deployment directory created, ready to deploy
- `deployment_in_progress`: Deployment is currently running
- `deployment_failed`: Deployment failed (check logs)
- `database_connection_failed`: Infrastructure deployed but database connection failed
- `database_ready`: Deployment complete and database is ready

### `destroy`

Destroy all resources associated with a deployment.

```bash
./exasol destroy --deployment-dir ./my-deployment
```

**Flags:**
- `--auto-approve`: Skip confirmation prompt

### `version`

Print the deployer version.

```bash
./exasol version
```

### `help`

Show help information.

```bash
./exasol help
./exasol [command] --help
```

## Configuration

### Database Versions

Database versions are configured in [`versions.conf`](versions.conf). Each version entry includes:

- Architecture (x86_64 or arm64)
- Database version number
- Download URLs for database tarball and c4 binary
- Checksums for verification
- Default instance type

Example entry:
```ini
[8.0.0-x86_64]
ARCHITECTURE=x86_64
DB_VERSION=8.0.0
DB_DOWNLOAD_URL=https://...
DB_CHECKSUM=sha256:...
C4_VERSION=24.1.0
C4_DOWNLOAD_URL=https://...
C4_CHECKSUM=sha256:...
DEFAULT_INSTANCE_TYPE=c7a.16xlarge
```

### Deployment Directory Structure

After initialization, a deployment directory contains:

```
my-deployment/
├── .exasol.json              # State file (do not modify)
├── .credentials.json         # Passwords (keep secure, chmod 600)
├── .templates/              # Terraform and Ansible templates
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── inventory.tftpl
│   ├── setup-exasol-cluster.yml
│   └── config.j2
├── variables.auto.tfvars    # Terraform variables
├── README.md                # Deployment-specific documentation
└── (generated during deployment):
    ├── .version-files/      # Downloaded database files
    ├── terraform.tfstate    # Terraform state
    ├── inventory.ini        # Ansible inventory
    ├── ssh_config           # SSH configuration
    └── exasol-key.pem       # SSH private key
```

### Customization

You can customize the deployment by editing [`variables.auto.tfvars`](variables.auto.tfvars) in your deployment directory before running `deploy`:

```hcl
aws_region = "us-west-2"
instance_type = "c7a.16xlarge"
node_count = 4
data_volume_size = 1000
allowed_cidr = "10.0.0.0/8"
```

## Architecture

### Components

1. **Main Script** ([`exasol`](exasol)): Entry point that handles command routing and global flags
2. **Libraries** ([`lib/`](lib/)):
   - `common.sh`: Shared utilities, logging, validation
   - `state.sh`: State management and locking
   - `versions.sh`: Version configuration and file downloads
   - `cmd_*.sh`: Command implementations
3. **Templates** ([`templates/`](templates/)):
   - Terraform configurations for AWS infrastructure
   - Ansible playbooks for cluster setup
4. **Configuration** ([`versions.conf`](versions.conf)): Database version definitions

### State Management

The deployer uses a file-based state system:

- **`.exasol.json`**: Tracks deployment status, version, timestamps
- **`.exasolLock.json`**: Prevents concurrent operations on the same deployment
- **Terraform state**: Manages infrastructure resources

### Locking Mechanism

The deployer creates lock files to prevent concurrent operations:
- Lock is created at the start of deploy/destroy operations
- Lock contains: operation type, PID, timestamp, hostname
- Lock is automatically removed on completion or error
- Stale locks can be manually removed if needed

## Advanced Usage

### Multi-Node Cluster

Deploy a 4-node Exasol cluster:

```bash
./exasol init \
  --deployment-dir ./prod-cluster \
  --db-version 8.0.0-x86_64 \
  --cluster-size 4 \
  --instance-type c7a.16xlarge \
  --data-volume-size 1000 \
  --owner "production-team" \
  --aws-region us-east-1

./exasol deploy --deployment-dir ./prod-cluster
```

### ARM64 Deployment

Deploy on ARM64 (Graviton) instances:

```bash
./exasol init \
  --deployment-dir ./arm-cluster \
  --db-version 8.0.0-arm64 \
  --instance-type c8g.16xlarge \
  --cluster-size 2

./exasol deploy --deployment-dir ./arm-cluster
```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
./exasol --log-level debug deploy --deployment-dir ./my-deployment
```

### Custom AWS Profile

Use a specific AWS profile:

```bash
./exasol init \
  --deployment-dir ./dev-cluster \
  --aws-profile dev-account \
  --aws-region eu-west-1
```

## Troubleshooting

### Deployment Fails

1. Check deployment status:
   ```bash
   ./exasol status --deployment-dir ./my-deployment
   ```

2. Enable debug logging:
   ```bash
   ./exasol --log-level debug deploy --deployment-dir ./my-deployment
   ```

3. Check Terraform state:
   ```bash
   cd ./my-deployment
   tofu show
   ```

### Lock File Issues

If a lock file is stale (process crashed):

```bash
rm ./my-deployment/.exasolLock.json
```

### Missing Dependencies

Check for required commands:
```bash
which tofu ansible-playbook jq
```

### AWS Credentials

Verify AWS credentials:
```bash
aws sts get-caller-identity --profile default
```

## Unsupported Features

The following features from the binary deployer are not yet implemented:

- `connect`: Open SQL connection to database
- `diag`: Diagnostic tools
- `completion`: Shell autocompletion

These commands will display "Feature not supported" messages.

## Differences from Binary Deployer

### Advantages

- **Transparent**: All Terraform and Ansible code is visible and customizable
- **Version Control Friendly**: Configuration files can be tracked in git
- **Extensible**: Easy to add custom Terraform resources or Ansible tasks
- **No Binary Dependencies**: Pure bash script, runs anywhere

### Limitations

- **No Built-in SQL Client**: Use external SQL clients to connect
- **Manual Diagnostics**: No automated diagnostic tools
- **Requires External Tools**: OpenTofu/Terraform and Ansible must be installed

## Contributing

To add a new database version:

1. Edit [`versions.conf`](versions.conf)
2. Add a new section with version details:
   ```ini
   [9.0.0-x86_64]
   ARCHITECTURE=x86_64
   DB_VERSION=9.0.0
   DB_DOWNLOAD_URL=https://...
   DB_CHECKSUM=sha256:...
   C4_VERSION=25.0.0
   C4_DOWNLOAD_URL=https://...
   C4_CHECKSUM=sha256:...
   DEFAULT_INSTANCE_TYPE=c7a.16xlarge
   ```

## Security Considerations

- **Credentials**: Stored in `.credentials.json` with chmod 600
- **SSH Keys**: Generated per-deployment, stored in deployment directory
- **AWS Access**: Uses your AWS profile credentials
- **Network Security**: Configure `--allowed-cidr` to restrict access
- **State Files**: Contain sensitive information, protect them

## License

This project is based on the Exasol open-source deployment tools.

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review deployment logs with `--log-level debug`
3. Check Terraform state and Ansible output

## Related Resources

- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Ansible Documentation](https://docs.ansible.com/)
- [Exasol Documentation](https://docs.exasol.com/)
- [AWS EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/)
