# Exasol Cloud Deployer

A bash-based multi-cloud deployer for Exasol database that uses OpenTofu (Terraform) and Ansible to provision and configure Exasol clusters. This tool provides a simple command-line interface for managing Exasol deployments with full control over the deployment process.

**Why bash and not Go/another compiled binary?**
- Zero build toolchain required on the operator side; bash is ubiquitous on Linux/macOS runners and CI agents.
- Tight integration with existing shell/Ansible/OpenTofu workflows (no cross-language shims needed).
- Easier to vendor and tweak in-line with the Terraform/Ansible templates without rebuilding binaries.
- Fast iteration for cloud releases; no cross-compilation or packaging pipeline to maintain for each platform.
- Proven portability for the surrounding scripts (init/deploy/destroy/status) and test harness.

## Features

- **Multi-Cloud Support**: Deploy on AWS, Azure, GCP, Hetzner Cloud, DigitalOcean, and local libvirt/KVM
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

### System Requirements

- **Operating System**: Linux (recommended) or macOS
- **Bash**: Version 4.0 or later
- **GNU Core Utilities**: Required for script compatibility
  - On Linux: Usually pre-installed
  - On macOS: BSD tools may cause issues, install GNU versions (see below)

### Required Software

- **OpenTofu** or Terraform (>= 1.0)
- **Ansible** (>= 2.9)
- **jq** (for JSON processing)
- **Standard Unix tools**: grep, sed, awk, curl, ssh, date, mktemp, readlink/realpath
- **Cloud provider credentials** configured (see [Cloud Setup Guide](docs/CLOUD_SETUP.md))

**For Development/Testing Only:**
- **Python 3.6+** (required only for running unit tests in `tests/` directory)
- **ShellCheck** (used by the shell lint test suite)

**Note:** Cloud provider CLI tools (aws, az, gcloud) are **not required** for deployment. OpenTofu reads credentials from standard configuration files or environment variables.

### Installation on macOS

**Important:** macOS uses BSD versions of standard Unix tools, which have different behavior than GNU versions. You must install GNU tools:

```bash
# Install OpenTofu
brew install opentofu

# Install Ansible
brew install ansible

# Install jq
brew install jq

# Install GNU core utilities (REQUIRED on macOS)
brew install coreutils findutils gnu-sed gawk grep bash

# Add GNU tools to PATH (add to ~/.zshrc or ~/.bash_profile)
export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
export PATH="/usr/local/opt/findutils/libexec/gnubin:$PATH"
export PATH="/usr/local/opt/gnu-sed/libexec/gnubin:$PATH"
export PATH="/usr/local/opt/gawk/libexec/gnubin:$PATH"
export PATH="/usr/local/opt/grep/libexec/gnubin:$PATH"

# Use Homebrew bash (version 5.x)
sudo sh -c 'echo /usr/local/bin/bash >> /etc/shells'
chsh -s /usr/local/bin/bash
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

## Cloud Provider Setup

Before deploying, you need to set up credentials for your chosen cloud provider. We support:

- **[AWS (Amazon Web Services)](docs/CLOUD_SETUP_AWS.md)** - Most feature-complete
- **[Azure (Microsoft Azure)](docs/CLOUD_SETUP_AZURE.md)** - Full support with spot instances
- **[GCP (Google Cloud Platform)](docs/CLOUD_SETUP_GCP.md)** - Full support with preemptible instances
- **[Hetzner Cloud](docs/CLOUD_SETUP_HETZNER.md)** - Cost-effective European provider
- **[DigitalOcean](docs/CLOUD_SETUP_DIGITALOCEAN.md)** - Simple and affordable
- **[Local libvirt/KVM](docs/CLOUD_SETUP_LIBVIRT.md)** - Local testing and development

**See the [Cloud Provider Setup Guide](docs/CLOUD_SETUP.md) for detailed instructions.**

### Quick Setup Examples

**AWS** (Manual setup, no AWS CLI needed):
```bash
mkdir -p ~/.aws
cat > ~/.aws/credentials <<EOF
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
EOF
chmod 600 ~/.aws/credentials
```

**Azure**:
```bash
az login
az account show --query id -o tsv  # Get subscription ID
```

**GCP**:
```bash
gcloud auth application-default login
gcloud config get-value project  # Get project ID
```

**Hetzner** / **DigitalOcean**:
Get API token from provider console and use with `--hetzner-token` or `--digitalocean-token` flag.

**Local libvirt/KVM**:
Install libvirt and KVM, then ensure your user is in the `libvirt` and `kvm` groups. See [Libvirt Setup Guide](docs/CLOUD_SETUP_LIBVIRT.md).

## Quick Start

### 1. Choose Cloud Provider and List Options

```bash
# List supported cloud providers
./exasol init --list-providers

# List available database versions
./exasol init --list-versions
```

**For detailed cloud provider setup, see:**
- [AWS Setup Guide](docs/CLOUD_SETUP_AWS.md)
- [Azure Setup Guide](docs/CLOUD_SETUP_AZURE.md)
- [GCP Setup Guide](docs/CLOUD_SETUP_GCP.md)
- [Hetzner Setup Guide](docs/CLOUD_SETUP_HETZNER.md)
- [DigitalOcean Setup Guide](docs/CLOUD_SETUP_DIGITALOCEAN.md)
- [Libvirt Setup Guide](docs/CLOUD_SETUP_LIBVIRT.md)

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

Use `--gcp-zone` to pick a specific zone when the default (`<region>-a`) is not available for your instance type or quota setup.

#### Hetzner Cloud Deployment

```bash
./exasol init \
  --cloud-provider hetzner \
  --deployment-dir ./my-hetzner-deployment \
  --hetzner-location nbg1 \
  --hetzner-token <your-api-token>
```

Match `--hetzner-network-zone` to your chosen location (default `eu-central` works for `nbg1`, `fsn1`, and `hel1`; use `us-east`, `us-west`, or `ap-southeast` for the corresponding regions).

#### DigitalOcean Deployment

```bash
./exasol init \
  --cloud-provider digitalocean \
  --deployment-dir ./my-do-deployment \
  --digitalocean-region nyc3 \
  --digitalocean-token <your-api-token>
```

DigitalOcean currently provides only x86_64 droplets, so arm64 database versions are rejected during initialization for this provider.

#### Local libvirt/KVM Deployment

```bash
# Initialize with default settings (single-node, 4GB RAM, 2 vCPUs)
./exasol init \
  --cloud-provider libvirt \
  --deployment-dir ./my-libvirt-deployment

# Initialize with custom resources for testing
./exasol init \
  --cloud-provider libvirt \
  --deployment-dir ./my-libvirt-deployment \
  --cluster-size 2 \
  --libvirt-memory 8 \
  --libvirt-vcpus 4 \
  --libvirt-network default \
  --libvirt-pool default \
  --data-volume-size 200
```

Perfect for local development, testing, and CI/CD pipelines without cloud costs.

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

### 6. Run a Health Check

Use the health command to verify SSH connectivity, COS endpoints, critical c4-managed services, and metadata consistency. Optional flags allow the command to refresh local files or attempt basic remediation such as restarting failed services.

```bash
# Read-only checks (default)
./exasol health --deployment-dir ./my-deployment

# Update inventory/ssh_config/INFO.txt if the cloud provider reassigned IPs
./exasol health --deployment-dir ./my-deployment --update

# Try to restart failed services automatically
./exasol health --deployment-dir ./my-deployment --try-fix
```

### 7. Stop and Start the Database (Optional)

For cost optimization, you can stop the database. All providers follow the same workflow:

```bash
# Stop the database (powers off VMs)
./exasol stop --deployment-dir ./my-deployment

# Check status
./exasol status --deployment-dir ./my-deployment
# Status will be: "stopped"

# Start the database again
./exasol start --deployment-dir ./my-deployment
```

**How it works:**

**For AWS/Azure/GCP (Automatic Power Control):**
- `stop`: Powers off VMs via OpenTofu and verifies shutdown
- `start`: Powers on VMs via OpenTofu, waits for database to become healthy (15 min timeout)

**For DigitalOcean/Hetzner/libvirt (Manual Power Control):**
- `stop`: Issues in-guest shutdown command, displays restart instructions
- `start`: Displays power-on instructions (provider-specific commands), then waits for database to become healthy (15 min timeout)
  - You power on the machines while `start` command waits
  - The command automatically detects when machines are online and continues
  - If timeout occurs, status is set to `start_failed` and you can retry

**Cost Savings Example (AWS):**
- Running cluster: ~$2/hour (c7a.16xlarge x 4 nodes)
- Stopped cluster: ~$0.50/hour (EBS volumes + stopped instance charges)
- Savings: ~75% during non-working hours

### 8. Destroy the Deployment

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

**Required Flags**
- `--cloud-provider string`: Cloud provider to target (`aws`, `azure`, `gcp`, `hetzner`, or `digitalocean`).

**Common Flags**
- `--deployment-dir string`: Directory for deployment files (default: current directory).
- `--db-version string`: Database version (format: name-X.Y.Z[-arm64][-local], e.g., `exasol-2025.1.4`; x86_64 is implicit).
- `--list-versions`: List all available database versions and exit.
- `--list-providers`: List all supported cloud providers and exit.
- `--cluster-size number`: Number of nodes (default: 1).
- `--instance-type string`: Instance/VM type (auto-detected from version if omitted).
- `--data-volume-size number`: Data volume size in GB (default: 100).
- `--data-volumes-per-node number`: Number of data volumes per node (default: 1).
- `--root-volume-size number`: Root volume size in GB (default: 50).
- `--db-password string`: Database password (random if not specified).
- `--adminui-password string`: Admin UI password (random if not specified).
- `--owner string`: Owner tag for resources (default: `exasol-deployer`).
- `--allowed-cidr string`: CIDR block that can reach the cluster (default: `0.0.0.0/0`).
- `-h, --help`: Show inline help for the `init` command and exit.

**AWS-Specific Flags**
- `--aws-region string`: AWS region (default: `us-east-1`).
- `--aws-profile string`: AWS CLI profile (default: `default`).
- `--aws-spot-instance`: Enable AWS spot instances.

**Azure-Specific Flags**
- `--azure-region string`: Azure region (default: `eastus`).
- `--azure-subscription string`: Azure subscription ID.
- `--azure-spot-instance`: Enable Azure spot instances.

**GCP-Specific Flags**
- `--gcp-region string`: GCP region (default: `us-central1`).
- `--gcp-zone string`: GCP zone (default: `<region>-a`).
- `--gcp-project string`: GCP project ID.
- `--gcp-spot-instance`: Enable GCP spot (preemptible) instances.

**Hetzner-Specific Flags**
- `--hetzner-location string`: Hetzner location (default: `nbg1`).
- `--hetzner-network-zone string`: Hetzner network zone (default: `eu-central`).
- `--hetzner-token string`: Hetzner API token.

**DigitalOcean-Specific Flags**
- `--digitalocean-region string`: DigitalOcean region (default: `nyc3`).
- `--digitalocean-token string`: DigitalOcean API token.

**Libvirt-Specific Flags**
- `--libvirt-memory integer`: Memory per VM in GB (default: `4`).
- `--libvirt-vcpus integer`: vCPUs per VM (default: `2`).
- `--libvirt-network string`: Libvirt network name (default: `default`).
- `--libvirt-pool string`: Storage pool name (default: `default`).

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

### `start`

Start a stopped Exasol database deployment. This powers on cloud instances (if supported) and waits for the database to become healthy.

```bash
./exasol start --deployment-dir ./my-deployment
```

**Use Cases:**
- Restart database after a planned stop
- Resume operations after cost-saving stop period
- Recover from start_failed state (retry)

**Prerequisites:**
- Deployment must be in `stopped` or `start_failed` state

**What it does (unified flow for all providers):**

1. Sets status to `start_in_progress`
2. **Infrastructure start:**
   - **AWS/Azure/GCP:** Powers on instances automatically via `tofu apply -var infra_desired_state=running`
   - **DigitalOcean/Hetzner/libvirt:** Displays provider-specific power-on instructions (you power on manually)
3. Sets status to `started` and releases operation lock
4. Calls `health --update --wait-for database_ready,15m`:
   - Polls deployment status every 10 seconds
   - Refreshes inventory/SSH config when machines come online
   - Waits for database services to start and become healthy
   - Times out after 15 minutes if database doesn't become ready
5. **On success:** Sets status to `database_ready` and prints success message
6. **On timeout/failure:** Sets status to `start_failed` with diagnostic instructions

**Key Benefits:**
- Same workflow for all providers - just run `exasol start`
- For manual providers, you power on machines while the command waits
- Automatic detection when machines come online
- Can retry from `start_failed` state

### `stop`

Stop a running Exasol database deployment. This gracefully stops database services without terminating cloud instances, useful for cost optimization.

```bash
./exasol stop --deployment-dir ./my-deployment
```

**Use Cases:**
- Pause database during non-working hours to save costs
- Perform maintenance on the underlying infrastructure
- Troubleshoot database issues

**Prerequisites:**
- Deployment must be in `database_ready`, `database_connection_failed`, or `stop_failed` state

**What it does:**

**For all providers:**
1. Validates deployment state
2. Stops systemd services via Ansible:
   - `c4.service` (main database service, stops Admin UI via PartOf)
   - `c4_cloud_command.service`
   - `exasol-admin-ui.service` (explicit ensure-stop)

**For AWS/Azure/GCP:**
3. Powers off instances via `tofu apply -var infra_desired_state=stopped`
4. Verifies VMs are powered off via SSH connectivity check
5. Updates state to `stopped` or `stop_failed`

**For DigitalOcean/Hetzner/libvirt:**
3. Issues in-guest `shutdown -h` command to all nodes
4. Displays message that you need to manually power on machines via provider interface before running start
5. Reminds you to run `exasol health --update` after powering on
6. Verifies VMs are powered off via SSH connectivity check
7. Updates state to `stopped` or `stop_failed`

**Note:** Use `destroy` to terminate instances and release all resources.

### `status`

Get the current status of a deployment in JSON format.

```bash
./exasol status --deployment-dir ./my-deployment
```

**Status Values:**
- `initialized`: Deployment directory created, ready to deploy
- `deploy_in_progress`: Deployment is currently running
- `deployment_failed`: Deployment failed (check logs)
- `database_connection_failed`: Infrastructure deployed but database connection failed
- `database_ready`: Deployment complete and database is ready
- `stopped`: Database services are stopped (instances powered off)
- `started`: Infrastructure powered on, waiting for database to be ready
- `start_in_progress`: Database start operation in progress
- `start_failed`: Database start operation failed
- `stop_in_progress`: Database stop operation in progress
- `stop_failed`: Database stop operation failed
- `destroy_in_progress`: Destroy operation is currently running
- `destroy_failed`: Destroy operation failed (check logs)
- `destroyed`: All resources have been destroyed successfully

### `health`

Run connectivity and service health checks for an existing deployment. The command verifies SSH access to every node, COS endpoints, key systemd services (c4 stack, Admin UI, symlink initializer), cluster state, and IP consistency between live infrastructure and local metadata.

Use `--update` to refresh `inventory.ini`, `ssh_config`, and `INFO.txt` when IPs change, and to correct deployment status from failure states to `database_ready` if all health checks pass and the cluster is confirmed operational.

Use `--wait-for` to wait until the deployment reaches a specific status, useful when combined with the `start` command for providers without power control.

```bash
# Basic health check
./exasol health --deployment-dir ./my-deployment

# Refresh metadata and correct status if cluster is healthy
./exasol health --deployment-dir ./my-deployment --update

# Wait for database to be ready (used internally by start command)
./exasol health --deployment-dir ./my-deployment --update --wait-for database_ready,15m

# Wait with default timeout (15m)
./exasol health --deployment-dir ./my-deployment --update --wait-for database_ready
```

**Flags:**
- `--wait-for <status,timeout>`: Wait until deployment reaches status with timeout
  - Format: `status,timeout` (e.g., `database_ready,15m`)
  - If timeout omitted, defaults to 15m
  - Status values: `database_ready`, `stopped`, `started`
   - Timeout formats: `15m`, `1h`, `60s`

### `add-metrics`

Copy freshly calibrated progress tracking metrics from a deployment directory to the global metrics repository. This command helps integrate newly calibrated metrics into the shared repository, making them available for all users and deployments.

```bash
# Copy metrics from deployment to global repository
./exasol add-metrics --deployment-dir ./my-deployment

# Preview what would be copied (dry-run)
./exasol add-metrics --deployment-dir ./my-deployment --dry-run
```

**Flags:**
- `--deployment-dir string`: Directory with deployment files and metrics (default: ".")
- `--dry-run`: Show what would be copied without actually copying

**Use Cases:**
- After running `PROGRESS_CALIBRATE=true ./exasol deploy`
- To share calibration data with team members
- To update global metrics with new provider/operation data

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
owner = "exasol-deployer"               # From --owner
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
# Lint all shell scripts
./tests/test_shellcheck.sh
```

Test coverage includes:
- Common utilities (validation, parsing, config management)
- Version management (version validation, config parsing)
- State management (initialization, locking, status updates)
- Variable file generation
- ShellCheck linting for all bash scripts

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

## Documentation

### Cloud Provider Setup

Comprehensive setup guides for each supported cloud provider:
- [Cloud Setup Overview](docs/CLOUD_SETUP.md) - Compare all providers
- [AWS Setup Guide](docs/CLOUD_SETUP_AWS.md) - Amazon Web Services
- [Azure Setup Guide](docs/CLOUD_SETUP_AZURE.md) - Microsoft Azure
- [GCP Setup Guide](docs/CLOUD_SETUP_GCP.md) - Google Cloud Platform
- [Hetzner Setup Guide](docs/CLOUD_SETUP_HETZNER.md) - Hetzner Cloud
- [DigitalOcean Setup Guide](docs/CLOUD_SETUP_DIGITALOCEAN.md) - DigitalOcean

Each guide includes:
- Account setup instructions
- Credential configuration
- Region/location selection
- Instance type recommendations
- Cost optimization tips
- Security best practices
- Troubleshooting

## Related Resources

- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Ansible Documentation](https://docs.ansible.com/)
- [Exasol Documentation](https://docs.exasol.com/)
- [Cloud Provider Pricing Calculators](docs/CLOUD_SETUP.md#cost-optimization)
