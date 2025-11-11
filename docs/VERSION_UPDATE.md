# Version Configuration Update

## Summary

Updated the `versions.conf` file to use the correct download URLs from the Go reference implementation and adjusted the version format to match the official Exasol releases.

## Changes Made

### 1. Updated versions.conf

**New version naming convention**: `exasol-YYYY.M.P-ARCH`
- Matches the official Go implementation
- Example: `exasol-2025.1.0-x86_64`

**Updated c4 download URL pattern**:
```
https://x-up.s3.amazonaws.com/releases/c4/linux/{arch}/{version}/c4
```

**Current c4 version**: `4.28.3` (from Go reference)

**Current Exasol version**: `@exasol-2025.1.0` (as used in c4 config)

### 2. Available Versions

The updated configuration provides:

1. **exasol-2025.1.0-x86_64** (default)
   - Architecture: x86_64
   - DB Version: `@exasol-2025.1.0`
   - C4 Version: 4.28.3
   - C4 URL: `https://x-up.s3.amazonaws.com/releases/c4/linux/x86_64/4.28.3/c4`
   - Instance Type: c7a.16xlarge

2. **exasol-2025.1.0-arm64**
   - Architecture: arm64
   - DB Version: `@exasol-2025.1.0`
   - C4 Version: 4.28.3
   - C4 URL: `https://x-up.s3.amazonaws.com/releases/c4/linux/arm64/4.28.3/c4`
   - Instance Type: c8g.16xlarge

3. **exasol-8.0.0-x86_64** (older version, for reference)
   - Architecture: x86_64
   - DB Version: `@exasol-8.0.0`
   - C4 Version: 4.28.3
   - C4 URL: `https://x-up.s3.amazonaws.com/releases/c4/linux/x86_64/4.28.3/c4`
   - Instance Type: r6i.xlarge

### 3. Updated Version Validation

Modified [`lib/versions.sh`](lib/versions.sh) to accept the new version format:

**Previous regex**: `^[0-9]+\.[0-9]+\.[0-9]+-(x86_64|arm64)$`
- Only accepted: `8.0.0-x86_64`

**New regex**: `^([a-z]+-)?[0-9]+\.[0-9]+\.[0-9]+-(x86_64|arm64)(-[a-z]+)?$`
- Accepts:
  - `8.0.0-x86_64` (legacy format)
  - `exasol-2025.1.0-x86_64` (new format)
  - `exasol-2025.1.0-x86_64-local` (with suffix)

### 4. DB_VERSION Field Clarification

**Important**: The `DB_VERSION` field now contains the c4 version string (e.g., `@exasol-2025.1.0`), not just a simple version number.

This is because c4 uses this format to download and install the database:
```bash
CCC_PLAY_WORKING_COPY=@exasol-2025.1.0
```

The `DB_DOWNLOAD_URL` field is kept for compatibility but is not actively used in c4-based deployments, as c4 handles the download internally.

## Reference Sources

All URLs and versions extracted from:
- [`references/personal-edition-source-code/assets/tofu_config/aws/post_deployment/prepareExasol.sh.tftpl`](references/personal-edition-source-code/assets/tofu_config/aws/post_deployment/prepareExasol.sh.tftpl)
  - c4 version: `4.28.3`
  - c4 URL pattern: `https://x-up.s3.amazonaws.com/releases/c4/linux/x86_64/${c4_version}/c4`

- [`references/personal-edition-source-code/assets/tofu_config/aws/post_deployment/installExasol.sh.tftpl`](references/personal-edition-source-code/assets/tofu_config/aws/post_deployment/installExasol.sh.tftpl)
  - Exasol version: `@exasol-2025.1.0`
  - Used in: `CCC_PLAY_WORKING_COPY=@exasol-2025.1.0`

## Testing

All functionality verified:

```bash
# List versions
$ ./exasol init --list-versions
exasol-2025.1.0-x86_64
exasol-2025.1.0-arm64
exasol-8.0.0-x86_64

# Initialize with default version
$ ./exasol init --deployment-dir ./test
Using default version: exasol-2025.1.0-x86_64
...
✅ Deployment directory initialized successfully!

# Check generated credentials
$ cat ./test/.credentials.json | jq .
{
  "db_password": "...",
  "adminui_password": "...",
  "db_download_url": "https://x-up.s3.amazonaws.com/releases/exasol/exasol-2025.1.0.tar.gz",
  "c4_download_url": "https://x-up.s3.amazonaws.com/releases/c4/linux/x86_64/4.28.3/c4",
  "created_at": "2025-11-11T14:15:56Z"
}
```

## Backward Compatibility

The changes maintain backward compatibility:
- Old version format `X.Y.Z-ARCH` still works
- New version format `name-X.Y.Z-ARCH` is now supported
- Existing deployments continue to function

## File:// URL Support

The configuration also supports local files using `file://` URLs:

```ini
[exasol-2025.1.0-x86_64-local]
ARCHITECTURE=x86_64
DB_VERSION=@exasol-2025.1.0
DB_DOWNLOAD_URL=file:///Users/username/releases/exasol-2025.1.0.tar.gz
C4_VERSION=4.28.3
C4_DOWNLOAD_URL=file:///Users/username/releases/c4
C4_CHECKSUM=sha256:placeholder
DEFAULT_INSTANCE_TYPE=c7a.16xlarge
```

## URL Pattern Documentation

### C4 Binary
```
Pattern: https://x-up.s3.amazonaws.com/releases/c4/linux/{ARCH}/{VERSION}/c4
Example: https://x-up.s3.amazonaws.com/releases/c4/linux/x86_64/4.28.3/c4
         https://x-up.s3.amazonaws.com/releases/c4/linux/arm64/4.28.3/c4
```

### Exasol Database (Hypothetical, c4 downloads internally)
```
Pattern: https://x-up.s3.amazonaws.com/releases/exasol/exasol-{VERSION}.tar.gz
Example: https://x-up.s3.amazonaws.com/releases/exasol/exasol-2025.1.0.tar.gz
         https://x-up.s3.amazonaws.com/releases/exasol/exasol-2025.1.0-arm64.tar.gz
```

Note: The database tarball URL is included for completeness, but c4-based deployments use the `@exasol-VERSION` string and c4 handles the download internally.

## Next Steps

To use the updated configuration:

1. **Initialize with new version** (automatic, as it's now the default):
   ```bash
   ./exasol init --deployment-dir ./my-deployment
   ```

2. **Or specify version explicitly**:
   ```bash
   ./exasol init --db-version exasol-2025.1.0-x86_64 --deployment-dir ./my-deployment
   ```

3. **For ARM64**:
   ```bash
   ./exasol init --db-version exasol-2025.1.0-arm64 --deployment-dir ./my-deployment
   ```

4. **Deploy as usual**:
   ```bash
   ./exasol deploy --deployment-dir ./my-deployment
   ```

The Ansible playbook will automatically download the correct c4 binary based on the architecture and use it to install Exasol with the specified version string.
