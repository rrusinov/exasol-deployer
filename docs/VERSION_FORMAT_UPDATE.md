# Version Format Update - 2025.1.4

## Summary

Updated the `versions.conf` to use the correct version format for different architectures and set the current version to exasol-2025.1.4 (x86_64 only).

## Version Format Rules

### For x86_64 (Intel/AMD)
```
DB_VERSION=@[name]-X.Y.Z
Example: @exasol-2025.1.4
```

### For ARM64 (Graviton/ARM)
```
DB_VERSION=@[name]-X.Y.Z~linux-arm64
Example: @exasol-2025.1.4~linux-arm64
```

The `~linux-arm64` suffix is required for ARM64 architectures to tell c4 to download the ARM64-specific database build.

## Current Configuration

### Active Version

**exasol-2025.1.4-x86_64** (default)
- Architecture: x86_64
- DB Version: `@exasol-2025.1.4`
- C4 Version: 4.28.3
- C4 URL: `https://x-up.s3.amazonaws.com/releases/c4/linux/x86_64/4.28.3/c4`
- Default Instance: c7a.16xlarge

### Commented Out Examples

**ARM64 Version** (for future use):
```ini
[exasol-2025.1.4-arm64]
ARCHITECTURE=arm64
DB_VERSION=@exasol-2025.1.4~linux-arm64  # Note the ~linux-arm64 suffix
DB_DOWNLOAD_URL=https://x-up.s3.amazonaws.com/releases/exasol/exasol-2025.1.4-arm64.tar.gz
C4_VERSION=4.28.3
C4_DOWNLOAD_URL=https://x-up.s3.amazonaws.com/releases/c4/linux/arm64/4.28.3/c4
DEFAULT_INSTANCE_TYPE=c8g.16xlarge
```

**Local Files** (for testing/development):
```ini
[exasol-2025.1.4-x86_64-local]
ARCHITECTURE=x86_64
DB_VERSION=@exasol-2025.1.4
DB_DOWNLOAD_URL=file:///Users/username/releases/exasol-2025.1.4.tar.gz
C4_VERSION=4.28.3
C4_DOWNLOAD_URL=file:///Users/username/releases/c4
DEFAULT_INSTANCE_TYPE=c7a.16xlarge
```

## Changes from Previous Configuration

| Aspect | Before | After |
|--------|--------|-------|
| Version | 2025.1.0 | 2025.1.4 |
| Active Versions | 3 (x86_64, arm64, 8.0.0) | 1 (x86_64 only) |
| ARM64 Format | `@exasol-2025.1.0` | `@exasol-2025.1.4~linux-arm64` |
| x86_64 Format | `@exasol-2025.1.0` | `@exasol-2025.1.4` (unchanged) |

## How c4 Uses Version Strings

The c4 installer uses these version strings to download the appropriate Exasol database package:

```bash
# In the Ansible config (generated):
CCC_PLAY_WORKING_COPY=@exasol-2025.1.4

# Or for ARM64:
CCC_PLAY_WORKING_COPY=@exasol-2025.1.4~linux-arm64
```

c4 interprets these strings and downloads the matching database release from its repository.

## Usage

### Default (x86_64)
```bash
./exasol init --deployment-dir ./my-cluster
# Uses: exasol-2025.1.4-x86_64
# DB_VERSION in c4 config: @exasol-2025.1.4
```

### Explicit Version
```bash
./exasol init --db-version exasol-2025.1.4-x86_64 --deployment-dir ./my-cluster
```

### ARM64 (when uncommented)
```bash
./exasol init --db-version exasol-2025.1.4-arm64 --deployment-dir ./my-cluster
# DB_VERSION in c4 config: @exasol-2025.1.4~linux-arm64
```

## Testing

Verified functionality:

```bash
# List available versions
$ ./exasol init --list-versions
exasol-2025.1.4-x86_64

# Initialize with default version
$ ./exasol init --deployment-dir ./test
Using default version: exasol-2025.1.4-x86_64
✅ Deployment directory initialized successfully!

# Check generated credentials
$ cat ./test/.credentials.json | jq .
{
  "db_password": "...",
  "adminui_password": "...",
  "db_download_url": "https://x-up.s3.amazonaws.com/releases/exasol/exasol-2025.1.4.tar.gz",
  "c4_download_url": "https://x-up.s3.amazonaws.com/releases/c4/linux/x86_64/4.28.3/c4",
  "created_at": "2025-11-11T14:30:03Z"
}

# Check state file
$ cat ./test/.exasol.json | jq .db_version
"exasol-2025.1.4-x86_64"
```

## Adding New Versions

To add a new version, copy the template:

### For x86_64:
```ini
[exasol-X.Y.Z-x86_64]
ARCHITECTURE=x86_64
DB_VERSION=@exasol-X.Y.Z
DB_DOWNLOAD_URL=https://x-up.s3.amazonaws.com/releases/exasol/exasol-X.Y.Z.tar.gz
DB_CHECKSUM=sha256:actual_checksum_here
C4_VERSION=4.28.3
C4_DOWNLOAD_URL=https://x-up.s3.amazonaws.com/releases/c4/linux/x86_64/4.28.3/c4
C4_CHECKSUM=sha256:actual_checksum_here
DEFAULT_INSTANCE_TYPE=c7a.16xlarge
```

### For ARM64:
```ini
[exasol-X.Y.Z-arm64]
ARCHITECTURE=arm64
DB_VERSION=@exasol-X.Y.Z~linux-arm64  # ← Don't forget the suffix!
DB_DOWNLOAD_URL=https://x-up.s3.amazonaws.com/releases/exasol/exasol-X.Y.Z-arm64.tar.gz
DB_CHECKSUM=sha256:actual_checksum_here
C4_VERSION=4.28.3
C4_DOWNLOAD_URL=https://x-up.s3.amazonaws.com/releases/c4/linux/arm64/4.28.3/c4
C4_CHECKSUM=sha256:actual_checksum_here
DEFAULT_INSTANCE_TYPE=c8g.16xlarge
```

## Architecture Suffix Summary

| Architecture | Version Format | Example |
|--------------|----------------|---------|
| x86_64 | `@exasol-X.Y.Z` | `@exasol-2025.1.4` |
| arm64 | `@exasol-X.Y.Z~linux-arm64` | `@exasol-2025.1.4~linux-arm64` |

The `~linux-arm64` suffix is **mandatory** for ARM64 builds. Without it, c4 will attempt to download the x86_64 version which will fail on ARM64 instances.

## Ansible Integration

The Ansible playbook will use the DB_VERSION value from `.credentials.json` (via state file) when creating the c4 configuration:

```yaml
- name: Create final Exasol config file from template
  ansible.builtin.template:
    src: "{{ playbook_dir }}/config.j2"
  vars:
    exa_release_version: "exasol-2025.1.4"  # From tarball filename
```

The actual c4 config file uses the version string:
```bash
CCC_PLAY_WORKING_COPY=@exasol-2025.1.4
```

## File Locations

- Configuration: [`versions.conf`](versions.conf)
- Validation: [`lib/versions.sh`](lib/versions.sh) (version format validation)
- Ansible config template: [`templates/ansible/config.j2`](templates/ansible/config.j2)

## Documentation

Updated documentation:
- [versions.conf](versions.conf) - Inline comments explaining format
- [VERSION_FORMAT_UPDATE.md](VERSION_FORMAT_UPDATE.md) - This document
