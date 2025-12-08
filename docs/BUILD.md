# Build System

This directory contains the automated release build system for Exasol Deployer.

## Overview

The build system generates a single self-contained bash installer (`exasol-installer.sh`) that bundles all runtime files and can be distributed as a standalone executable.

## Building a Release

```bash
./build/create_release.sh
```

This will:
1. Auto-generate version from git tags or timestamp+hash
2. Bundle essential runtime files (lib/, templates/, exasol, configs)
3. Exclude development files (tests/, docs/, .git/, etc.)
4. Create a deterministic tarball payload
5. Generate a self-extracting installer with embedded payload
6. Output: `build/exasol-installer.sh` (~620KB)

## Version Generation

The build script automatically determines the version:
- **Git tag (exact match)**: Uses the tag as-is (e.g., `v1.0.0`)
- **Git tag (with commits)**: Uses `git describe` (e.g., `v1.0.0-5-g1234abc`)
- **No tags**: Uses timestamp + short hash (e.g., `20251208-a9a5f25`)

## Installer Features

### Installation Modes

```bash
# Interactive installation (prompts for confirmation)
./exasol-installer.sh

# Install to specific path (still prompts)
./exasol-installer.sh --install ~/.local/bin

# Non-interactive (skip all prompts)
./exasol-installer.sh --yes

# Install with custom prefix
./exasol-installer.sh --prefix /opt/exasol

# Force overwrite existing installation
./exasol-installer.sh --yes

# Skip PATH configuration
./exasol-installer.sh --no-path

# Extract files only (no installation)
./exasol-installer.sh --extract-only /tmp/exasol

# Uninstall (prompts for confirmation)
./exasol-installer.sh --uninstall

# Uninstall from specific path
./exasol-installer.sh --uninstall ~/.local/bin

# Force uninstall (no prompt)
./exasol-installer.sh --uninstall --yes

# Show version
./exasol-installer.sh --version

# Show help
./exasol-installer.sh --help
```

**Interactive Behavior:**
- By default, the installer prompts to confirm the installation directory
- Uninstall prompts to confirm removal (shows what will be deleted)
- Use `--yes` to skip all prompts (useful for automation)
- Answer 'Y' to proceed or 'N' to cancel

### Platform Support

- **Linux**: Installs to `~/.local/bin/exasol-deployer` with symlink at `~/.local/bin/exasol`
- **macOS**: Installs to `~/bin/exasol-deployer` or `/usr/local/bin/exasol-deployer` with symlink
- **WSL**: Installs to `~/.local/bin/exasol-deployer` with symlink

The installer creates a subdirectory structure:
```
~/.local/bin/
├── exasol -> exasol-deployer/exasol  (symlink)
└── exasol-deployer/                   (installation directory)
    ├── exasol                         (main executable)
    ├── lib/                           (libraries)
    ├── templates/                     (Terraform/Ansible templates)
    ├── versions.conf
    └── instance-types.conf
```

This keeps all files organized in a subdirectory while providing a clean `exasol` command via symlink.

### Shell Support

Automatically configures PATH for:
- bash (`~/.bashrc` or `~/.bash_profile`)
- zsh (`~/.zshrc`)
- fish (`~/.config/fish/config.fish`)

### Features

- **Preflight checks**: Verifies bash 4.0+, required commands, disk space
- **Update detection**: Compares versions and prompts for confirmation
- **Atomic updates**: Backs up existing installation before updating
- **Rollback support**: Preserves backup on failure
- **Checksum verification**: Validates payload integrity
- **Idempotent**: Safe to run multiple times
- **Non-interactive mode**: Use `--yes` for automation

## Distribution

### Direct Download

```bash
# Download
curl -fsSL https://example.com/exasol-installer.sh -o exasol-installer.sh

# Make executable
chmod +x exasol-installer.sh

# Install
./exasol-installer.sh
```

### One-Liner

```bash
curl -fsSL https://example.com/exasol-installer.sh -o /tmp/install.sh && \
  bash /tmp/install.sh && \
  rm /tmp/install.sh
```

**Note**: The installer does NOT support `curl | bash` pattern due to the self-extracting archive format. The script must be saved to a file first.

## Testing

```bash
# Test version display
./build/exasol-installer.sh --version

# Test extraction
./build/exasol-installer.sh --extract-only /tmp/test

# Test installation
./build/exasol-installer.sh --install /tmp/test-install --no-path --yes

# Verify installation
/tmp/test-install/exasol version
```

## Bundled Files

The installer includes:
- `exasol` - Main CLI script
- `lib/` - Shell libraries
- `templates/` - Terraform and Ansible templates
- `versions.conf` - Database version configurations
- `instance-types.conf` - Cloud instance type mappings

Excluded from bundle:
- Documentation (*.md)
- Tests (tests/)
- Build scripts (build/)
- Development files (.git/, .venv/, __pycache__)
- Deployment artifacts (.terraform*, terraform.tfstate*, .exasol.json)
- Credentials (*.pem, *.key, .credentials.json)

## Technical Details

### Self-Extracting Archive Format

```
#!/usr/bin/env bash
# Installer header with metadata and functions
# Version, checksum, build date embedded
# Installation logic
__ARCHIVE_BELOW__
<base64-encoded tarball>
```

### Payload Creation

- Deterministic tarball (sorted, fixed mtime, normalized permissions)
- SHA256 checksum for integrity verification
- Base64 encoding for safe embedding in shell script

### Installation Process

1. Preflight checks (bash version, required commands)
2. Platform and shell detection
3. Installation path selection (auto or user-specified)
4. Existing installation check and backup
5. Payload extraction to temp directory
6. Checksum verification
7. File copy to installation directory
8. Permission setting (755 for executables)
9. PATH configuration (unless --no-path)
10. Post-install verification
11. Cleanup temp files

## CI/CD Integration

```yaml
# Example GitHub Actions workflow
- name: Build release installer
  run: ./build/create_release.sh

- name: Upload artifact
  uses: actions/upload-artifact@v3
  with:
    name: exasol-installer
    path: build/exasol-installer.sh
```

## Troubleshooting

### "Checksum mismatch"
The payload was corrupted during download or transfer. Re-download the installer.

### "Bash 4.0+ required"
Your system has an old bash version. Install bash 4.0 or later.

### "Missing required commands"
Install missing dependencies: `tar`, `base64`, `mkdir`, `chmod`

### "Permission denied"
The installation directory is not writable. Use `--prefix` to specify a different path or run with appropriate permissions.

### PATH not updated
- Manually source your shell config: `source ~/.bashrc`
- Or restart your shell
- Or use `--no-path` and add to PATH manually
