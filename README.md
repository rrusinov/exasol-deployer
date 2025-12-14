# Exasol Deployment

[![CI - Comprehensive Quality Checks](https://github.com/rrusinov/exasol-deployer/actions/workflows/ci-comprehensive.yml/badge.svg)](https://github.com/rrusinov/exasol-deployer/actions/workflows/ci-comprehensive.yml)
[![Pull Request Tests](https://github.com/rrusinov/exasol-deployer/actions/workflows/pr-tests.yml/badge.svg)](https://github.com/rrusinov/exasol-deployer/actions/workflows/pr-tests.yml)
[![Build and Release Installer](https://github.com/rrusinov/exasol-deployer/actions/workflows/release.yml/badge.svg)](https://github.com/rrusinov/exasol-deployer/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Cloud Providers](https://img.shields.io/badge/Cloud-AWS%20%7C%20Azure%20%7C%20GCP%20%7C%20Hetzner%20%7C%20DigitalOcean%20%7C%20libvirt-orange.svg)](#cloud-provider-setup)

Deploy Exasol database clusters across multiple cloud providers with a single command.

## Features

- **Multi-Cloud Support**: AWS, Azure, GCP, Hetzner Cloud, DigitalOcean, libvirt/KVM
- **Multiple Database Versions**: Support for multiple Exasol versions and architectures (x86_64, arm64)
- **Spot/Preemptible Instances**: Cost optimization with spot instances on AWS, Azure, and GCP
- **Infrastructure as Code**: Uses OpenTofu for reproducible infrastructure provisioning
- **Automated Configuration**: Ansible playbooks for complete cluster setup
- **State Management**: Tracks deployment state with file-based locking for safe operations

## Quick Start

### 1. Install

```bash
# Standard installation
curl -fsSL https://xsol.short.gy/sh | bash

# Self-contained with all dependencies (no system requirements)
curl -fsSL https://xsol.short.gy/sh | bash -s -- --install-dependencies

# Or use full URL
curl -fsSL https://github.com/rrusinov/exasol-deployer/releases/latest/download/exasol-deployer.sh | bash
```

**For overwrite an existing installation, add --yes:**
```bash
curl -fsSL https://github.com/rrusinov/exasol-deployer/releases/latest/download/exasol-deployer.sh | bash -s -- --yes
```

See [Installation Guide](INSTALLATION.md) for detailed instructions and prerequisites.

### 2. Setup Cloud Provider

Configure credentials for your chosen cloud provider:

- **[AWS](clouds/CLOUD_SETUP_AWS.md)** - Most feature-complete
- **[Azure](clouds/CLOUD_SETUP_AZURE.md)** - Full support with spot instances  
- **[GCP](clouds/CLOUD_SETUP_GCP.md)** - Full support with preemptible instances
- **[Hetzner](clouds/CLOUD_SETUP_HETZNER.md)** - Cost-effective European provider
- **[DigitalOcean](clouds/CLOUD_SETUP_DIGITALOCEAN.md)** - Simple and affordable
- **[libvirt/KVM](clouds/CLOUD_SETUP_LIBVIRT.md)** - Local testing and development

See [Cloud Provider Setup Guide](clouds/CLOUD_SETUP.md) for detailed instructions.

### 3. Initialize Deployment

```bash
# AWS example
./exasol init \
  --cloud-provider aws \
  --deployment-dir ./my-deployment \
  --cluster-size 3 \
  --aws-region us-east-1 \
  --aws-spot-instance

# Azure example  
./exasol init \
  --cloud-provider azure \
  --deployment-dir ./my-deployment \
  --azure-region eastus \
  --azure-subscription <subscription-id> \
  --azure-spot-instance

# GCP example
./exasol init \
  --cloud-provider gcp \
  --deployment-dir ./my-deployment \
  --gcp-project my-project-id \
  --gcp-region us-central1 \
  --gcp-spot-instance
```

### 4. Deploy

```bash
./exasol deploy --deployment-dir ./my-deployment
```

### 5. Connect

```bash
# SSH to first node
ssh -F ./my-deployment/ssh_config n11

# Check status
./exasol status --deployment-dir ./my-deployment
```

### 6. Stop/Start (Cost Optimization)

```bash
# Stop database (powers off VMs, saves ~75% costs)
./exasol stop --deployment-dir ./my-deployment

# Start database again
./exasol start --deployment-dir ./my-deployment
```

### 7. Cleanup

```bash
./exasol destroy --deployment-dir ./my-deployment --auto-approve
```

## Documentation

- **[Installation Guide](INSTALLATION.md)** - Installation and prerequisites
- **[Command Reference](COMMANDS.md)** - Complete command documentation
- **[Cloud Setup](clouds/CLOUD_SETUP.md)** - Cloud provider setup guides
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions
- **[Testing](tests/README.md)** - Unit and E2E testing framework
- **[Templates](templates/README.md)** - OpenTofu and Ansible templates
- **[Scripts](scripts/README.md)** - Utility scripts for resource management

## Resource Management

### Check Limits Before Deploying

```bash
# Generate HTML report with all providers and regions
./scripts/generate-limits-report.sh --output limits-report.html

# Check specific provider
./scripts/generate-limits-report.sh --provider azure --output azure-report.html
```

### Bulk Cleanup

```bash
# List all resources without deleting (dry run)
./scripts/cleanup-resources.sh --provider azure --dry-run

# Delete all resources with confirmation
./scripts/cleanup-resources.sh --provider hetzner --yes
```

## Testing

```bash
# Run unit tests
./tests/run_tests.sh

# Run E2E tests for specific provider
./tests/run_e2e.sh --provider libvirt

# List available tests
./tests/run_e2e.sh --list-tests
```

## Project Notes

**Why bash?**
- Zero build toolchain required; bash is ubiquitous on Linux/macOS
- Tight integration with existing shell/Ansible/OpenTofu workflows
- Fast iteration for cloud releases without cross-compilation
- Proven portability for scripts and test harness

**Support & Community**
- Open-source community project, not officially supported by Exasol AG
- Contributions welcome via issues and pull requests

## Trademark Notice

