# Scripts and Build System

This directory contains operational and development utility scripts for the Exasol Deployer project, plus the automated release build system.

**Note:** These scripts are for development and operational use only. **They are not included in packaged releases** because they require cloud provider CLI tools (aws, az, gcloud, hcloud, doctl, virsh) to be installed on the system.

## Quick Reference

| Script | Purpose |
|--------|---------|
| `create-release.sh` | Build self-contained bash installer |
| `generate-limits-report.sh` | Generate HTML report of cloud limits across all regions |
| `cleanup-resources.sh` | Bulk cleanup of cloud resources |

## Build System

Automated release build system that generates self-contained bash installers for Exasol Deployer.

### Quick Start

```bash
# Build release
./scripts/create-release.sh

# Test installer
./build/exasol_deployer.sh --version
./build/exasol_deployer.sh --extract-only /tmp/test
```

Output: `build/exasol_deployer.sh` (~620KB)

### Building a Release

```bash
./scripts/create-release.sh
```

The build process:
1. Auto-generates version from git tags or timestamp+hash
2. Bundles runtime files (lib/, templates/, exasol, configs)
3. Excludes development files (tests/, docs/, .git/)
4. Creates deterministic tarball payload
5. Generates self-extracting installer with embedded payload

### Version Generation

- **Git tag (exact match)**: `v1.0.0` → `v1.0.0`
- **Git tag (with commits)**: `v1.0.0-5-g1234abc`
- **No tags**: `20251208-a9a5f25` (timestamp + short hash)

### Installer Usage

#### Installation Modes

```bash
# Interactive (prompts for confirmation)
./exasol_deployer.sh

# Non-interactive
./exasol_deployer.sh --yes

# Custom path
./exasol_deployer.sh --install /opt/exasol

# Skip PATH configuration
./exasol_deployer.sh --no-path

# Extract only (no installation)
./exasol_deployer.sh --extract-only /tmp/exasol

# Uninstall
./exasol_deployer.sh --uninstall
./exasol_deployer.sh --uninstall --yes

# Show version/help
./exasol_deployer.sh --version
./exasol_deployer.sh --help
```

#### Platform Support

- **Linux**: `~/.local/bin/exasol-deployer` with symlink at `~/.local/bin/exasol`
- **macOS**: `~/bin/exasol-deployer` or `/usr/local/bin/exasol-deployer` with symlink
- **WSL**: `~/.local/bin/exasol-deployer` with symlink

Installation structure:
```
~/.local/bin/
├── exasol -> exasol-deployer/exasol  (symlink)
└── exasol-deployer/                   (installation directory)
    ├── exasol
    ├── lib/
    ├── templates/
    ├── versions.conf
    └── instance-types.conf
```

#### Shell Support

Automatically configures PATH for bash, zsh, and fish shells.

### Distribution

#### Direct Download

```bash
curl -fsSL https://example.com/exasol_deployer.sh -o exasol_deployer.sh
chmod +x exasol_deployer.sh
./exasol_deployer.sh
```

#### One-Liner

```bash
curl -fsSL https://example.com/exasol_deployer.sh -o /tmp/i.sh && \
  bash /tmp/i.sh && \
  rm /tmp/i.sh
```

**Note**: The installer does NOT support `curl | bash` pattern due to the self-extracting archive format.

### Bundled Files

**Included:**
- `exasol` - Main CLI script
- `lib/` - Shell libraries
- `templates/` - Terraform and Ansible templates
- `versions.conf` - Database version configurations
- `instance-types.conf` - Cloud instance type mappings

**Excluded:**
- Documentation (*.md)
- Tests (tests/)
- Build scripts (build/)
- Development files (.git/, .venv/, __pycache__)
- Deployment artifacts (.terraform*, terraform.tfstate*, .exasol.json)
- Credentials (*.pem, *.key, .credentials.json)

### Technical Details

#### Self-Extracting Archive Format

```
#!/usr/bin/env bash
# Installer header with metadata and functions
# Version, checksum, build date embedded
# Installation logic
__ARCHIVE_BELOW__
<base64-encoded tarball>
```

#### Payload Creation

- Deterministic tarball (sorted, fixed mtime, normalized permissions)
- SHA256 checksum for integrity verification
- Base64 encoding for safe embedding in shell script
- All .md files excluded from payload

#### Installation Process

1. Preflight checks (bash version, required commands)
2. Platform and shell detection
3. Installation path selection
4. Existing installation check and backup
5. Payload extraction to temp directory
6. Checksum verification
7. File copy to installation directory
8. Permission setting (755 for executables)
9. PATH configuration (unless --no-path)
10. Post-install verification
11. Cleanup temp files

#### Features

- Preflight checks (bash 4.0+, required commands)
- Update detection and version comparison
- Atomic updates with backup
- Rollback support on failure
- Checksum verification
- Idempotent (safe to run multiple times)
- Non-interactive mode for automation

### CI/CD Integration

```yaml
# GitHub Actions example
- name: Build release installer
  run: ./scripts/create-release.sh

- name: Upload artifact
  uses: actions/upload-artifact@v3
  with:
    name: exasol_deployer
    path: build/exasol_deployer.sh
```

### Testing

```bash
# Run installer tests
./tests/test_installer.sh

# Manual testing
./build/exasol_deployer.sh --version
./build/exasol_deployer.sh --extract-only /tmp/test
./build/exasol_deployer.sh --install /tmp/test-install --no-path --yes
/tmp/test-install/exasol version
```

### Troubleshooting

**Checksum mismatch**: Payload corrupted during download. Re-download the installer.

**Bash 4.0+ required**: Install bash 4.0 or later.

**Missing required commands**: Install missing dependencies: `tar`, `base64`, `mkdir`, `chmod`

**Permission denied**: Installation directory not writable. Use `--prefix` to specify a different path.

**PATH not updated**: Source shell config (`source ~/.bashrc`) or restart shell.

## Prerequisites

These scripts require cloud provider CLI tools to be installed:

- **AWS**: `aws` CLI ([installation](https://aws.amazon.com/cli/))
- **Azure**: `az` CLI ([installation](https://docs.microsoft.com/cli/azure/install-azure-cli))
- **GCP**: `gcloud` CLI ([installation](https://cloud.google.com/sdk/docs/install))
- **Hetzner**: `hcloud` CLI ([installation](https://github.com/hetznercloud/cli))
- **DigitalOcean**: `doctl` CLI ([installation](https://docs.digitalocean.com/reference/doctl/))
- **libvirt**: `virsh` command (part of libvirt-client package)

The scripts will skip providers whose CLI tools are not installed.

## Quick Start

### Generate Limits Report

```bash
# Full report for all providers (scans all regions)
./scripts/generate-limits-report.sh --output report.html

# Specific provider
./scripts/generate-limits-report.sh --provider azure --output azure.html

# Open in browser (Linux)
xdg-open report.html
```

**Features:**
- Scans all major regions automatically
- Shows running instances with tags (owner, creator, project)
- Displays resource quotas and usage percentages
- Interactive expandable sections

### Cleanup Resources

```bash
# Dry run (preview only)
./scripts/cleanup-resources.sh --provider aws --dry-run

# Actually delete
./scripts/cleanup-resources.sh --provider aws --yes
```

## Testing

All scripts have unit tests in the `tests/` directory:

```bash
# Run all tests
./tests/run_tests.sh

# Run specific script tests
./tests/test_generate_limits_report.sh
```

## Development

When adding new scripts:

1. Follow the code style in [AGENTS.md](../AGENTS.md)
2. Add unit tests in `tests/test_<script_name>.sh`
3. Link tests in `tests/run_tests.sh`
4. Update this README

## Support

For issues or questions, see the [main project README](../README.md).
