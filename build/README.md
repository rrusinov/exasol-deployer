# Build System

Automated release build system that generates self-contained bash installers for Exasol Deployer.

## Quick Start

```bash
# Build release
./build/create_release.sh

# Test installer
./build/exasol-installer.sh --version
./build/exasol-installer.sh --extract-only /tmp/test
```

Output: `build/exasol-installer.sh` (~620KB)

## Building a Release

```bash
./build/create_release.sh
```

The build process:
1. Auto-generates version from git tags or timestamp+hash
2. Bundles runtime files (lib/, templates/, exasol, configs)
3. Excludes development files (tests/, docs/, .git/)
4. Creates deterministic tarball payload
5. Generates self-extracting installer with embedded payload

## Version Generation

- **Git tag (exact match)**: `v1.0.0` → `v1.0.0`
- **Git tag (with commits)**: `v1.0.0-5-g1234abc`
- **No tags**: `20251208-a9a5f25` (timestamp + short hash)

## Installer Usage

### Installation Modes

```bash
# Interactive (prompts for confirmation)
./exasol-installer.sh

# Non-interactive
./exasol-installer.sh --yes

# Custom path
./exasol-installer.sh --install /opt/exasol

# Skip PATH configuration
./exasol-installer.sh --no-path

# Extract only (no installation)
./exasol-installer.sh --extract-only /tmp/exasol

# Uninstall
./exasol-installer.sh --uninstall
./exasol-installer.sh --uninstall --yes

# Show version/help
./exasol-installer.sh --version
./exasol-installer.sh --help
```

### Platform Support

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

### Shell Support

Automatically configures PATH for bash, zsh, and fish shells.

## Distribution

### Direct Download

```bash
curl -fsSL https://example.com/exasol-installer.sh -o exasol-installer.sh
chmod +x exasol-installer.sh
./exasol-installer.sh
```

### One-Liner

```bash
curl -fsSL https://example.com/exasol-installer.sh -o /tmp/i.sh && \
  bash /tmp/i.sh && \
  rm /tmp/i.sh
```

**Note**: The installer does NOT support `curl | bash` pattern due to the self-extracting archive format.

## Bundled Files

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
- All .md files excluded from payload

### Installation Process

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

### Features

- Preflight checks (bash 4.0+, required commands)
- Update detection and version comparison
- Atomic updates with backup
- Rollback support on failure
- Checksum verification
- Idempotent (safe to run multiple times)
- Non-interactive mode for automation

## CI/CD Integration

```yaml
# GitHub Actions example
- name: Build release installer
  run: ./build/create_release.sh

- name: Upload artifact
  uses: actions/upload-artifact@v3
  with:
    name: exasol-installer
    path: build/exasol-installer.sh
```

## Testing

```bash
# Run installer tests
./tests/test_installer.sh

# Manual testing
./build/exasol-installer.sh --version
./build/exasol-installer.sh --extract-only /tmp/test
./build/exasol-installer.sh --install /tmp/test-install --no-path --yes
/tmp/test-install/exasol version
```

## Troubleshooting

**Checksum mismatch**: Payload corrupted during download. Re-download the installer.

**Bash 4.0+ required**: Install bash 4.0 or later.

**Missing required commands**: Install missing dependencies: `tar`, `base64`, `mkdir`, `chmod`

**Permission denied**: Installation directory not writable. Use `--prefix` to specify a different path.

**PATH not updated**: Source shell config (`source ~/.bashrc`) or restart shell.
