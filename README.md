# Exasol Cloud Deployer

A bash-based multi-cloud deployer for Exasol database that uses OpenTofu (Terraform) and Ansible to provision and configure Exasol clusters. This tool provides a simple command-line interface for managing Exasol deployments with full control over the deployment process.

## Features

- **Multi-Cloud Support**: Deploy on AWS, Azure, GCP, Hetzner Cloud, and DigitalOcean
- **Multiple Database Versions**: Support for multiple Exasol database versions and architectures (x86_64, arm64)
- **Cloud-Init Integration**: OS-agnostic user provisioning works across all Linux distributions
- **Spot/Preemptible Instances**: Cost optimization with spot instances on AWS, Azure, and GCP
- **Configurable Deployments**: Customize cluster size, instance types, storage, and network settings
- **State Management**: Tracks deployment state with file-based locking for safe concurrent operations
- **Infrastructure as Code**: Uses OpenTofu/Terraform for reproducible infrastructure provisioning
- **Automated Configuration**: Ansible playbooks for complete cluster setup
- **Credential Management**: Secure password generation and storage
- **Dynamic Configuration**: All Terraform variables generated from command-line parameters and version configurations

## Prerequisites

Before using this deployer, ensure you have the following installed:

- **OpenTofu** or Terraform (>= 1.0)
- **Ansible** (>= 2.9)
- **jq** (for JSON processing)
- **bash** (>= 4.0)
- **AWS credentials** configured (see below)

**Note:** AWS CLI is **not required**. The tool uses OpenTofu's AWS provider which reads credentials directly from `~/.aws/credentials` and `~/.aws/config`.

### Installation on macOS

```bash
# Install OpenTofu
brew install opentofu

# Install Ansible
brew install ansible

# Install jq
brew install jq
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
```

### AWS Credentials Setup

You need to configure AWS credentials. You can do this in two ways:

**Option 1: Using AWS CLI (convenient but not required)**
```bash
# Install AWS CLI if you want to use it for credential setup
aws configure --profile default
```

**Option 2: Manual setup (no AWS CLI needed)**
```bash
# Create credentials file manually
mkdir -p ~/.aws
cat > ~/.aws/credentials <<EOF
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
EOF

# Create config file (optional)
cat > ~/.aws/config <<EOF
[default]
region = us-east-1
EOF

# Set proper permissions
chmod 600 ~/.aws/credentials
chmod 600 ~/.aws/config
```

## Quick Start

### 1. List Available Options

```bash
# List supported cloud providers
./exasol init --list-providers

# List available database versions
./exasol init --list-versions
```

Output:
```
Supported cloud providers:
  - aws: Amazon Web Services
  - azure: Microsoft Azure
  - gcp: Google Cloud Platform
  - hetzner: Hetzner Cloud
  - digitalocean: DigitalOcean

Available database versions:
exasol-2025.1.4
```

### 2. Initialize a Deployment

#### AWS Deployment

```bash
# Initialize with default settings (single-node, default version)
./exasol init \
  --cloud-provider aws \
  --deployment-dir ./my-aws-deployment

# Initialize with specific version, cluster size, and spot instances
./exasol init \
  --cloud-provider aws \
  --deployment-dir ./my-aws-deployment \
  --db-version exasol-2025.1.4 \
  --cluster-size 4 \
  --instance-type c7a.16xlarge \
  --data-volume-size 500 \
  --aws-region us-east-1 \
  --aws-spot-instance
```

#### Azure Deployment

```bash
./exasol init \
  --cloud-provider azure \
  --deployment-dir ./my-azure-deployment \
  --azure-region eastus \
  --azure-subscription <your-subscription-id> \
  --cluster-size 3 \
  --azure-spot-instance
```

#### GCP Deployment

```bash
./exasol init \
  --cloud-provider gcp \
  --deployment-dir ./my-gcp-deployment \
  --gcp-project my-project-id \
  --gcp-region us-central1 \
  --cluster-size 2 \
  --gcp-spot-instance
```

#### Hetzner Cloud Deployment

```bash
./exasol init \
  --cloud-provider hetzner \
  --deployment-dir ./my-hetzner-deployment \
  --hetzner-location nbg1 \
  --hetzner-token <your-api-token>
```

#### DigitalOcean Deployment

```bash
./exasol init \
  --cloud-provider digitalocean \
  --deployment-dir ./my-do-deployment \
  --digitalocean-region nyc3 \
  --digitalocean-token <your-api-token>
```

The init command will:
- Create the deployment directory structure
- Generate dynamic Terraform variables based on your parameters and database version
- Set default instance type from version configuration (can be overridden with `--instance-type`)
- Generate secure random passwords for database and AdminUI
- Copy Terraform and Ansible templates

### 3. Deploy the Infrastructure

```bash
./exasol deploy --deployment-dir ./my-deployment
```

This will:
1. Download required database files and c4 binary
2. Initialize OpenTofu/Terraform
3. Create AWS infrastructure (VPC, subnets, security groups, EC2 instances, EBS volumes)
4. Configure instances with Ansible
5. Set up the Exasol cluster

### 4. Connect to Your Cluster

After deployment, you can connect to nodes using the generated SSH config:

```bash
# Using SSH config
ssh -F ./my-deployment/ssh_config n11

# Or directly
ssh -i ./my-deployment/exasol-key.pem ubuntu@<public_ip>
```

Node naming convention:
- First node: `n11`
- Second node: `n12`
- Third node: `n13`
- And so on...

### 5. Check Deployment Status

```bash
./exasol status --deployment-dir ./my-deployment
```

Output (JSON):
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

### 6. Destroy the Deployment

```bash
# With confirmation prompts
./exasol destroy --deployment-dir ./my-deployment

# Auto-approve (no prompts, removes deployment directory)
./exasol destroy --deployment-dir ./my-deployment --auto-approve
```

**Warning**: This will destroy all resources including data volumes. Make sure to backup any important data first.

## Commands

### `init`

Initialize a new deployment directory with configuration files.

```bash
./exasol init [flags]
```

**Flags:**
- `--deployment-dir string`: Directory for deployment files (default: current directory)
- `--db-version string`: Database version (format: name-X.Y.Z[-arm64][-local], e.g., exasol-2025.1.4 (x86_64 is implicit))
- `--list-versions`: List all available database versions
- `--cluster-size number`: Number of nodes (default: 1)
- `--instance-type string`: EC2 instance type (uses version's DEFAULT_INSTANCE_TYPE if not specified)
- `--data-volume-size number`: Data volume size in GB (default: 100)
- `--db-password string`: Database password (randomly generated if not specified)
- `--adminui-password string`: Admin UI password (randomly generated if not specified)
- `--owner string`: Owner tag for resources (default: "exasol-default")
- `--aws-region string`: AWS region (default: "us-east-1")
- `--aws-profile string`: AWS profile to use (default: "default")
- `--allowed-cidr string`: CIDR block for access (default: "0.0.0.0/0")

**Configuration Flow:**
1. Parse command-line arguments
2. Load database version configuration from `versions.conf`
3. Extract architecture and default instance type from version config
4. Generate `variables.auto.tfvars` with all dynamic values
5. Create `.credentials.json` with passwords and download URLs

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
./exasol destroy --deployment-dir ./my-deployment [--auto-approve]
```

**Flags:**
- `--auto-approve`: Skip all confirmation prompts and automatically remove deployment directory

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

- **ARCHITECTURE**: x86_64 or arm64
- **DB_VERSION**: Version string for c4 (e.g., `@exasol-2025.1.4` or `@exasol-2025.1.4~linux-arm64`)
- **DB_DOWNLOAD_URL**: URL to database tarball (HTTP/HTTPS or file://)
- **DB_CHECKSUM**: SHA256 checksum for verification
- **C4_VERSION**: c4 binary version
- **C4_DOWNLOAD_URL**: URL to c4 binary (HTTP/HTTPS or file://)
- **C4_CHECKSUM**: SHA256 checksum for c4 binary
- **DEFAULT_INSTANCE_TYPE**: Default EC2 instance type for this version

Example entry:
```ini
[exasol-2025.1.4]
ARCHITECTURE=x86_64
DB_VERSION=@exasol-2025.1.4
DB_DOWNLOAD_URL=https://x-up.s3.amazonaws.com/releases/exasol/exasol-2025.1.4.tar.gz
DB_CHECKSUM=sha256:placeholder
C4_VERSION=4.28.3
C4_DOWNLOAD_URL=https://x-up.s3.amazonaws.com/releases/c4/linux/x86_64/4.28.3/c4
C4_CHECKSUM=sha256:placeholder
DEFAULT_INSTANCE_TYPE=m6idn.large
```

### Dynamic Variable Generation

Unlike traditional Terraform setups with hardcoded defaults, this deployer generates `variables.auto.tfvars` dynamically during initialization:

**variables.tf** (Template):
- Defines variable types and descriptions
- No hardcoded default values (except `root_volume_size`)
- All values set via `variables.auto.tfvars`

**variables.auto.tfvars** (Generated):
```hcl
aws_region = "us-east-1"
aws_profile = "default"
instance_type = "m6idn.large"          # From version config or --instance-type
instance_architecture = "x86_64"       # From version config
node_count = 1                         # From --cluster-size
data_volume_size = 100                 # From --data-volume-size
allowed_cidr = "0.0.0.0/0"            # From --allowed-cidr
owner = "exasol-default"               # From --owner
```

### Deployment Directory Structure

After initialization, a deployment directory contains:

```
my-deployment/
├── .exasol.json              # State file (do not modify)
├── .credentials.json         # Passwords and URLs (chmod 600)
├── .templates/               # Terraform and Ansible templates
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── inventory.tftpl
│   ├── setup-exasol-cluster.yml
│   └── config.j2
├── variables.auto.tfvars     # Generated Terraform variables
├── main.tf                   # Symlink to .templates/main.tf
├── variables.tf              # Symlink to .templates/variables.tf
├── outputs.tf                # Symlink to .templates/outputs.tf
├── README.md                 # Deployment-specific documentation
└── (generated during deployment):
    ├── .version-files/       # Downloaded database files
    ├── terraform.tfstate     # Terraform state
    ├── inventory.ini         # Ansible inventory
    ├── ssh_config            # SSH configuration
    └── exasol-key.pem        # SSH private key (chmod 400)
```

### Node Naming Convention

All nodes follow a consistent naming scheme:
- **Node 1**: `n11`
- **Node 2**: `n12`
- **Node 3**: `n13`
- And so on...

This naming is consistent across:
- EC2 instance tags
- SSH config hostnames
- Ansible inventory
- /etc/hosts entries
- Terraform outputs

## Architecture

### Components

1. **Main Script** ([`exasol`](exasol)): Entry point that handles command routing and global flags
2. **Libraries** ([`lib/`](lib/)):
   - `common.sh`: Shared utilities, logging, validation
   - `state.sh`: State management and locking
   - `versions.sh`: Version configuration and file downloads
   - `cmd_init.sh`: Initialize deployment directory
   - `cmd_deploy.sh`: Deploy infrastructure and cluster
   - `cmd_destroy.sh`: Destroy infrastructure
   - `cmd_status.sh`: Check deployment status
3. **Templates** ([`templates/`](templates/)):
   - Terraform configurations for AWS infrastructure
   - Ansible playbooks for cluster setup
4. **Configuration** ([`versions.conf`](versions.conf)): Database version definitions
5. **Tests** ([`tests/`](tests/)): Unit tests for core functionality

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

## Testing

### Running Unit Tests

The project includes a comprehensive unit test suite:

```bash
# Run all tests
./tests/run_tests.sh

# Run specific test file
./tests/test_common.sh
./tests/test_versions.sh
./tests/test_state.sh
```

Test coverage includes:
- Common utilities (validation, parsing, config management)
- Version management (version validation, config parsing)
- State management (initialization, locking, status updates)
- Variable file generation

### Continuous Integration

The project uses GitHub Actions for automated testing on pull requests:

- **Unit Tests**: Runs all unit tests
- **ShellCheck**: Lints shell scripts for common errors
- **Integration Tests**: Tests init and status commands
- **Terraform Validation**: Validates Terraform configurations

See [`.github/workflows/pr-tests.yml`](.github/workflows/pr-tests.yml) for details.

## Advanced Usage

### Multi-Node Cluster

Deploy a 4-node Exasol cluster:

```bash
./exasol init \
  --deployment-dir ./prod-cluster \
  --db-version exasol-2025.1.4 \
  --cluster-size 4 \
  --instance-type c7a.16xlarge \
  --data-volume-size 1000 \
  --owner "production-team" \
  --aws-region us-east-1

./exasol deploy --deployment-dir ./prod-cluster
```

### ARM64 Deployment

Deploy on ARM64 (Graviton) instances (when ARM64 version is available):

```bash
./exasol init \
  --deployment-dir ./arm-cluster \
  --db-version exasol-2025.1.4-arm64 \
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

### Customization After Init

You can edit `variables.auto.tfvars` in your deployment directory before running `deploy`:

```hcl
aws_region = "us-west-2"
instance_type = "c7a.16xlarge"
node_count = 4
data_volume_size = 1000
allowed_cidr = "10.0.0.0/8"
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

Verify AWS credentials are configured:
```bash
# Option 1: If you have AWS CLI installed
aws sts get-caller-identity --profile default

# Option 2: Without AWS CLI - check credential files exist
test -f ~/.aws/credentials && echo "✓ AWS credentials file exists"
test -f ~/.aws/config && echo "✓ AWS config file exists"
```

### Test Failures

If tests fail, check the detailed output:
```bash
./tests/run_tests.sh
```

## Contributing

### Adding a New Database Version

1. Edit [`versions.conf`](versions.conf)
2. Add a new section with version details:
   ```ini
   # x86_64 version (no architecture suffix)
   [exasol-2025.2.0]
   ARCHITECTURE=x86_64
   DB_VERSION=@exasol-2025.2.0
   DB_DOWNLOAD_URL=https://x-up.s3.amazonaws.com/releases/exasol/exasol-2025.2.0.tar.gz
   DB_CHECKSUM=sha256:...
   C4_VERSION=4.29.0
   C4_DOWNLOAD_URL=https://x-up.s3.amazonaws.com/releases/c4/linux/x86_64/4.29.0/c4
   C4_CHECKSUM=sha256:...
   DEFAULT_INSTANCE_TYPE=m6idn.large

   # ARM64 version (with -arm64 suffix)
   [exasol-2025.2.0-arm64]
   ARCHITECTURE=arm64
   DB_VERSION=@exasol-2025.2.0~linux-arm64
   DB_DOWNLOAD_URL=https://x-up.s3.amazonaws.com/releases/exasol/exasol-2025.2.0-arm64.tar.gz
   DB_CHECKSUM=sha256:...
   C4_VERSION=4.29.0
   C4_DOWNLOAD_URL=https://x-up.s3.amazonaws.com/releases/c4/linux/arm64/4.29.0/c4
   C4_CHECKSUM=sha256:...
   DEFAULT_INSTANCE_TYPE=c8g.16xlarge
   ```

### Running Tests Before PR

```bash
# Run all tests
./tests/run_tests.sh

# Verify init works
./exasol init --list-versions
./exasol init --deployment-dir /tmp/test --db-version exasol-2025.1.4

# Cleanup
rm -rf /tmp/test
```

## Differences from Binary Deployer

### Advantages

- **Transparent**: All Terraform and Ansible code is visible and customizable
- **Version Control Friendly**: Configuration files can be tracked in git
- **Extensible**: Easy to add custom Terraform resources or Ansible tasks
- **No Binary Dependencies**: Pure bash script, runs anywhere
- **Dynamic Configuration**: Variables generated from CLI parameters and version config

### Limitations

- **No Built-in SQL Client**: Use external SQL clients to connect
- **Manual Diagnostics**: No automated diagnostic tools
- **Requires External Tools**: OpenTofu/Terraform and Ansible must be installed

## Security Considerations

- **Credentials**: Stored in `.credentials.json` with chmod 600
- **SSH Keys**: Generated per-deployment, stored in deployment directory (chmod 400)
- **AWS Access**: Uses your AWS profile credentials
- **Network Security**: Configure `--allowed-cidr` to restrict access (recommended: use your IP address)
- **State Files**: Contain sensitive information, protect them
- **Passwords**: Auto-generated 16-character random passwords by default

## Project Structure

```
exasol-deployer/
├── exasol                    # Main executable
├── lib/                      # Core libraries
│   ├── common.sh
│   ├── state.sh
│   ├── versions.sh
│   ├── cmd_init.sh
│   ├── cmd_deploy.sh
│   ├── cmd_destroy.sh
│   └── cmd_status.sh
├── templates/                # Terraform and Ansible templates
│   ├── terraform/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── inventory.tftpl
│   └── ansible/
│       ├── setup-exasol-cluster.yml
│       └── config.j2
├── tests/                    # Unit tests
│   ├── run_tests.sh
│   ├── test_helper.sh
│   ├── test_common.sh
│   ├── test_versions.sh
│   └── test_state.sh
├── .github/
│   └── workflows/
│       └── pr-tests.yml      # CI/CD pipeline
├── versions.conf             # Database version configuration
└── README.md                 # This file
```

## License

This project is based on the Exasol open-source deployment tools.

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review deployment logs with `--log-level debug`
3. Check Terraform state and Ansible output
4. Run unit tests to verify system integrity

## Related Resources

- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Ansible Documentation](https://docs.ansible.com/)
- [Exasol Documentation](https://docs.exasol.com/)
- [AWS EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/)
