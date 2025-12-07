# Exasol Deployment

This directory contains a deployment configuration for Exasol database.

## Features

- **Multi-Cloud Support**:
  - [AWS] Amazon Web Services
  - [AZR] Microsoft Azure
  - [GCP] Google Cloud Platform
  - [HTZ] Hetzner Cloud
  - [DO] DigitalOcean
  - [LAB] libvirt/KVM (local or remote over SSH for Linux hosts)
- **Multiple Database Versions**: Support for multiple Exasol database versions and architectures (x86_64, arm64)
- **Cloud-Init Integration**: OS-agnostic user provisioning works across all Linux distributions
- **Spot/Preemptible Instances**: Cost optimization with spot instances on AWS, Azure, and GCP
- **Configurable Deployments**: Customize cluster size, instance types, storage, and network settings
- **State Management**: Tracks deployment state with file-based locking for safe concurrent operations
- **Infrastructure as Code**: Uses OpenTofu/Terraform for reproducible infrastructure provisioning
- **Automated Configuration**: Ansible playbooks for complete cluster setup
- **Credential Management**: Secure password generation and storage for database, AdminUI, and host OS access
- **Dynamic Configuration**: All Terraform variables generated from command-line parameters and version configurations
- **Permission Analysis**: Static permission analysis for cloud provider templates to help configure cloud accounts

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

# List available database versions (shows availability and architecture)
./exasol init --list-versions
```

### 1.5 Check Required Permissions (Optional)

Before deploying, you can check the required cloud permissions:

```bash
# Show required permissions for a cloud provider
./exasol init --cloud-provider aws --show-permissions
```

If permissions are not available, generate them (only needed when templates change):

```bash
# Generate permissions tables for all providers
./build/generate_permissions.sh
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
  --db-version exasol-2025.1.8 \
  --cluster-size 4 \
  --instance-type c7a.16xlarge \
  --data-volume-size 500 \
  --aws-region us-east-1 \
  --aws-spot-instance
```

#### Azure Deployment

```bash
# Create (or reuse) service principal credentials file (default path)
az ad sp create-for-rbac \
  --name "exasol-deployer" \
  --role contributor \
  --scopes /subscriptions/<your-subscription-id> \
  > ~/.azure_credentials
chmod 600 ~/.azure_credentials

# Initialize deployment (reads ~/.azure_credentials automatically)
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

#### Local libvirt/KVM Deployment (Linux host, system libvirt only)

```bash
# Initialize with default settings (single-node, 4GB RAM, 2 vCPUs)
./exasol init \
  --cloud-provider libvirt \
  --deployment-dir ./my-libvirt-deployment

# Initialize with custom resources for testing (system libvirt URI required)
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

Perfect for local development, testing, and CI/CD pipelines without cloud costs. Libvirt support requires a Linux host with a system libvirtd (`qemu:///system` locally or `qemu+ssh://user@host/system` remotely). Session daemons and macOS/HVF are not supported.

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
  "db_version": "exasol-2025.1.8",
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
- `--db-version string`: Database version (format: name-X.Y.Z[-arm64][-local], e.g., `exasol-2025.1.8`; x86_64 is implicit).
- `--list-versions`: List all available database versions (with availability and architecture) and exit.
- `--list-providers`: List all supported cloud providers and exit.
- `--show-permissions`: Show required cloud permissions for the specified provider and exit.
- `--cluster-size number`: Number of nodes (default: 1).
- `--instance-type string`: Instance/VM type (auto-detected from version if omitted).
- `--data-volume-size number`: Data volume size in GB (default: 100).
- `--data-volumes-per-node number`: Number of data volumes per node (default: 1).
- `--root-volume-size number`: Root volume size in GB (default: 50).
- `--db-password string`: Database password (random if not specified).
- `--adminui-password string`: Admin UI password (random if not specified).
- `--host-password string`: Host OS password for the `exasol` user (random if not specified).
- `--owner string`: Owner tag for resources (default: `exasol-deployer`).
- `--allowed-cidr string`: CIDR block that can reach the cluster (default: `0.0.0.0/0`).
- `--enable-multicast-overlay`: Enable the multicast overlay network (VXLAN) for providers that can run without it by default.
- `-h, --help`: Show inline help for the `init` command and exit.

**AWS-Specific Flags**
- `--aws-region string`: AWS region (default: `us-east-1`).
- `--aws-profile string`: AWS CLI profile (default: `default`).
- `--aws-spot-instance`: Enable AWS spot instances.

**Azure-Specific Flags**
- `--azure-region string`: Azure region (default: `eastus`).
- `--azure-subscription string`: Azure subscription ID.
- `--azure-credentials-file string`: Path to Azure service principal credentials JSON (default: `~/.azure_credentials`).
- `--azure-spot-instance`: Enable Azure spot instances.

**GCP-Specific Flags**
- `--gcp-region string`: GCP region (default: `us-central1`).
- `--gcp-zone string`: GCP zone (default: `<region>-a`).
- `--gcp-project string`: GCP project ID.
- `--gcp-spot-instance`: Enable GCP spot (preemptible) instances.
- `--gcp-credentials-file string`: Path to GCP service account credentials JSON (default: `~/.gcp_credentials.json`).

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
- `--libvirt-uri string`: Libvirt URI (auto-detected when omitted).

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

### `update-versions`

Discover the latest Exasol database and C4 binaries, download them to compute checksums, and append a new entry to `versions.conf`.

```bash
./exasol update-versions
```

**How it works:**
- Starts from the highest non-local version already in `versions.conf` and probes newer patch, minor, and major versions (patch +10, minor +5, major +3).
- Applies the same probing window to the bundled C4 binary.
- Picks the highest reachable DB/C4 pair, downloads both to `/var/tmp`, computes SHA256 checksums, and appends a single new version entry (including the architecture-aware DB version field).
- Requires `curl` and `sha256sum` plus network access to the release URLs.

### `add-metrics`

Copy calibrated metrics (progress line counts and durations) from a deployment back into the shared metrics repository. Useful when you've run with `PROGRESS_CALIBRATE=true` and want to persist improved estimates for future runs.

```bash
PROGRESS_CALIBRATE=true ./exasol deploy --deployment-dir ./my-deployment
./exasol add-metrics --deployment-dir ./my-deployment
```

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

- **Cloud Provider**: Local libvirt/KVM deployment
- **Database Version**: exasol-2025.1.8
- **Architecture**: arm64
- **Cluster Size**: 1 nodes
- **Instance Type**: libvirt-custom
- **Local KVM Deployment**
- **Memory**: 4GB per VM
- **vCPUs**: 2 per VM
- **Network**: default
- **Storage Pool**: default

## Credentials

Database, AdminUI, and host OS credentials are stored in `.credentials.json` (protected file). The host password (`host_password`) is used for OS-level access to the `exasol` user (for example, `ssh exasol@n11`) and can be retrieved with `cat .credentials.json | jq -r '.host_password'`.

## Next Steps

1. Review and customize `variables.auto.tfvars` if needed
2. Run `./exasol deploy --deployment-dir /Users/ruslan.rusinov/work/exasol-deployer/.` to deploy
3. Run `./exasol status --deployment-dir /Users/ruslan.rusinov/work/exasol-deployer/.` to check status
4. Run `./exasol destroy --deployment-dir /Users/ruslan.rusinov/work/exasol-deployer/.` to tear down

## Cleanup and Resource Management

### Resource Limit Checking

Before deploying, check your cloud provider resource limits and current usage:

```bash
# Generate HTML report with all providers and regions
./scripts/generate-limits-report.sh --output limits-report.html

# Check specific provider
./scripts/generate-limits-report.sh --provider azure --output azure-report.html
```

### Bulk Resource Cleanup

If you have orphaned resources or want to clean up multiple deployments at once, use the unified cleanup script:

```bash
# List all resources without deleting (dry run)
./scripts/cleanup-resources.sh --provider azure --dry-run

# Delete all resources with confirmation prompt
./scripts/cleanup-resources.sh --provider hetzner

# Delete resources without confirmation
./scripts/cleanup-resources.sh --provider gcp --yes

# Use custom prefix filter
./scripts/cleanup-resources.sh --provider aws --prefix myapp --yes
```

**Supported providers:** aws, azure, gcp, hetzner, digitalocean, libvirt

**Note:** The scripts in `scripts/` directory are not included in packaged releases as they require cloud provider CLI tools (aws, az, gcloud, hcloud, doctl, virsh) to be installed. See [Scripts README](scripts/README.md) for prerequisites and detailed information.

See [scripts/README.md](scripts/README.md) for detailed documentation.

### Per-Deployment Cleanup

To destroy a specific deployment:

```bash
./exasol destroy --deployment-dir ./my-deployment
```

## Troubleshooting

### Manual Power Control (Hetzner, DigitalOcean, libvirt)

Some cloud providers don't support automatic power on/off via API. When you run `exasol start` on these providers, you'll see instructions for manual power-on:

#### Hetzner
```bash
# Web Console
# Go to: https://console.hetzner.cloud/
# Navigate to your server and click "Power On"

# CLI (requires hcloud CLI)
hcloud server list  # Find your server name
hcloud server poweron <server-name>
```

#### DigitalOcean
```bash
# Web Console
# Go to: https://cloud.digitalocean.com/droplets
# Find your droplet and click "Power On"

# CLI (requires doctl CLI)
doctl compute droplet list  # Find your droplet ID
doctl compute droplet-action power-on <droplet-id>
```

#### libvirt (Local VMs)
```bash
# List all VMs
virsh list --all

# Start a specific VM
virsh start <vm-name>

# Alternative: Use virt-manager GUI
virt-manager
```

**Note:** After manually powering on, the `start` command will automatically detect when the servers are online and continue with database startup.

### Common Issues

#### "Provider X does not support automatic power control"
This is expected behavior for Hetzner, DigitalOcean, and libvirt. Follow the manual power-on instructions displayed.

#### Start command times out waiting for health
- Check that servers are powered on and reachable via SSH
- Verify network connectivity between nodes
- Check system logs: `journalctl -u exasol-overlay` and `journalctl -u c4_cloud_command`

#### Overlay network issues
- VXLAN port 4789 is used internally for cluster communication between nodes (not required in firewall rules for external access)
- Check overlay service status: `systemctl status exasol-overlay`
- Verify bridge interface exists: `ip addr show vxlan-br0`

## Important Files

- `.exasol.json` - Deployment state (do not modify)
- `variables.auto.tfvars` - Terraform variables
- `.credentials.json` - Passwords (DB/AdminUI/host; keep secure)
- `terraform.tfstate` - Terraform state (created after deployment)

## Testing

This project includes comprehensive test coverage:

- **Unit Tests**: Shell script tests for core functionality
  ```bash
  # Run all tests
  ./tests/run_tests.sh
  
  # Run specific test
  ./tests/test_common.sh
  ```

- **E2E Tests**: End-to-end integration tests across cloud providers
  - See [E2E Test Framework Documentation](docs/E2E-README.md) for details
  - Resource-aware scheduling prevents local memory exhaustion
  - Supports workflow-based testing with validation
  ```bash
  # Run E2E tests for libvirt
  ./tests/run_e2e.sh --provider libvirt
  
  # List available tests
  ./tests/run_e2e.sh --list-tests
  ```

## Project Notes

**Why bash and not Go/another compiled binary?**
- Zero build toolchain required on the operator side; bash is ubiquitous on Linux/macOS runners and CI agents.
- Tight integration with existing shell/Ansible/OpenTofu workflows (no cross-language shims needed).
- Easier to vendor and tweak in-line with the Terraform/Ansible templates without rebuilding binaries.
- Fast iteration for cloud releases; no cross-compilation or packaging pipeline to maintain for each platform.
- Proven portability for the surrounding scripts (init/deploy/destroy/status) and test harness.

**Support & Community**
- This is an open-source community project and is not officially supported by Exasol.
- Contributions and community support are welcome via issues and pull requests.
