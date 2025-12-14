# Command Reference

## `init`

Initialize a new deployment directory with configuration files.

```bash
./exasol init [flags]
```

### Required Flags
- `--cloud-provider string`: Cloud provider (`aws`, `azure`, `gcp`, `hetzner`, `digitalocean`, `libvirt`)

### Common Flags
- `--deployment-dir string`: Directory for deployment files (default: current directory)
- `--db-version string`: Database version (e.g., `exasol-2025.1.8`)
- `--list-versions`: List available database versions and exit
- `--list-providers`: List supported cloud providers and exit
- `--show-permissions`: Show required cloud permissions and exit
- `--cluster-size number`: Number of nodes (default: 1)
- `--instance-type string`: Instance/VM type (auto-detected if omitted)
- `--data-volume-size number`: Data volume size in GB (default: 100)
- `--owner string`: Owner tag for resources (default: `exasol-deployer`)
- `--allowed-cidr string`: CIDR block access (default: `0.0.0.0/0`)

### Cloud-Specific Flags

**AWS**
- `--aws-region string`: AWS region (default: `us-east-1`)
- `--aws-spot-instance`: Enable spot instances

**Azure**
- `--azure-region string`: Azure region (default: `eastus`)
- `--azure-subscription string`: Azure subscription ID
- `--azure-spot-instance`: Enable spot instances

**GCP**
- `--gcp-region string`: GCP region (default: `us-central1`)
- `--gcp-project string`: GCP project ID
- `--gcp-spot-instance`: Enable preemptible instances

**Hetzner**
- `--hetzner-location string`: Location (default: `nbg1`)
- `--hetzner-token string`: API token

**DigitalOcean**
- `--digitalocean-region string`: Region (default: `nyc3`)
- `--digitalocean-token string`: API token

**libvirt**
- `--libvirt-memory integer`: Memory per VM in GB (default: 4)
- `--libvirt-vcpus integer`: vCPUs per VM (default: 2)

## `deploy`

Deploy infrastructure using an existing deployment directory.

```bash
./exasol deploy --deployment-dir ./my-deployment
```

## `start`

Start a stopped deployment. Powers on instances and waits for database to be ready.

```bash
./exasol start --deployment-dir ./my-deployment
```

## `stop`

Stop a running deployment. Gracefully stops services and powers off instances.

```bash
./exasol stop --deployment-dir ./my-deployment
```

## `status`

Get deployment status in JSON format.

```bash
./exasol status --deployment-dir ./my-deployment
```

**Status Values:**
- `initialized`: Ready to deploy
- `deploy_in_progress`: Deployment running
- `database_ready`: Deployment complete and ready
- `stopped`: Services stopped, instances powered off
- `start_failed`: Start operation failed
- `destroy_in_progress`: Destroy operation running

## `health`

Run health checks and optionally wait for specific status.

```bash
# Basic health check
./exasol health --deployment-dir ./my-deployment

# Refresh metadata if IPs changed
./exasol health --deployment-dir ./my-deployment --update

# Wait for database to be ready
./exasol health --deployment-dir ./my-deployment --wait-for database_ready,15m
```

## `destroy`

Destroy all resources.

```bash
./exasol destroy --deployment-dir ./my-deployment [--auto-approve]
```

## `version`

Print deployer version.

```bash
./exasol version
```

## `help`

Show help information.

```bash
./exasol help
./exasol [command] --help
```

## Credentials

Database, AdminUI, and host OS credentials are stored in `.credentials.json`. Access host password with:

```bash
cat .credentials.json | jq -r '.host_password'
```
