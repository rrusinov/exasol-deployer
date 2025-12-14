# Installation Guide

## Quick Install (Recommended)

```bash
# Standard installation
curl -fsSL https://xsol.short.gy/sh | bash

# Self-contained with all dependencies (no system requirements)
curl -fsSL https://xsol.short.gy/sh | bash -s -- --install-dependencies --yes
```

## Manual Installation

```bash
# Download installer
curl -fsSL https://xsol.short.gy/sh -o exasol-deployer.sh
chmod +x exasol-deployer.sh

# Install (standard or with dependencies)
./exasol-deployer.sh
./exasol-deployer.sh --install-dependencies
```

## Installation Options

- **Standard**: Requires system OpenTofu, Ansible, Python, jq
- **Self-contained**: Bundles all dependencies (~250MB), zero system requirements
- **Custom path**: Use `--prefix /custom/path`
- **Non-interactive**: Add `--yes` flag

## Non-Interactive Installation

For automation or CI/CD:

```bash
curl -fsSL https://github.com/rrusinov/exasol-deployer/releases/latest/download/exasol-deployer.sh | bash -s -- --yes
```

## Custom Installation Path

```bash
./exasol-deployer.sh --prefix /opt/exasol --yes
```

## Verify Installation

```bash
exasol version
```

## Prerequisites

### System Requirements

- **Operating System**: Linux (recommended) or macOS
- **Bash**: Version 4.0 or later
- **GNU Core Utilities**: Required for script compatibility
  - On Linux: Usually pre-installed
  - On macOS: BSD tools may cause issues, install GNU versions (see below)

### Required Software

**Option 1: Zero Dependencies (Recommended)**
Use the `--install-dependencies` flag to install everything locally:
```bash
curl -fsSL https://xsol.short.gy/sh | bash -s -- --install-dependencies --yes
```
This installs OpenTofu, Python, and Ansible in a local directory (~250MB) with no system dependencies.

**Option 2: System Installation**
- **OpenTofu** or Terraform (>= 1.0)
- **Ansible** (>= 2.9)
- **Python 3.6+** (required for Ansible)
- **jq** (for JSON processing)
- **Standard Unix tools**: grep, sed, awk, curl, ssh, date, mktemp, readlink/realpath
- **Cloud provider credentials** configured (see [Cloud Setup Guide](clouds/CLOUD_SETUP.md))

**For Development/Testing Only:**
- **Python 3.6+** (required only for running unit tests in `tests/` directory)
- **ShellCheck** (used by the shell lint test suite)

**Note:** Cloud provider CLI tools (aws, az, gcloud) are **not required** for deployment. OpenTofu reads credentials from standard configuration files or environment variables.

## Installation on macOS

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

## Installation on Linux

```bash
# Install OpenTofu
# See: https://opentofu.org/docs/intro/install/

# Install Ansible
sudo apt-get update
sudo apt-get install -y ansible

# Install jq
sudo apt-get install -y jq
```

For detailed build and installation documentation, see [Scripts and Build System Documentation](scripts/README.md).
