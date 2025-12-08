# Version Feature Implementation

## Summary

Added version support to the main `exasol` script with automatic version injection during the build process.

## Changes Made

### 1. Main Script (`exasol`)

Added version detection logic that:
- Shows `dev` for local development (when `__EXASOL_VERSION__` placeholder is present)
- Shows actual version when built and installed
- Supports `EXASOL_VERSION` environment variable override

```bash
readonly SCRIPT_VERSION_RAW="${EXASOL_VERSION:-__EXASOL_VERSION__}"
if [[ "$SCRIPT_VERSION_RAW" =~ ^__.*__$ ]]; then
    readonly SCRIPT_VERSION="dev"
else
    readonly SCRIPT_VERSION="$SCRIPT_VERSION_RAW"
fi
```

### 2. Build Script (`build/create_release.sh`)

Modified `create_payload()` to:
- Copy `exasol` script to staging directory
- Inject version using sed: `sed "s/__EXASOL_VERSION__/$version/g"`
- Preserve executable permissions

### 3. Unit Tests (`tests/test_version.sh`)

Created comprehensive test suite covering:
- Local development version shows 'dev'
- Version command executes successfully
- Version output format validation
- Environment variable override
- Build process version injection

## Usage

### Local Development
```bash
$ ./exasol version
Exasol Cloud Deployer vdev
Built with OpenTofu and Ansible
```

### With Environment Variable
```bash
$ EXASOL_VERSION="1.2.3" ./exasol version
Exasol Cloud Deployer v1.2.3
Built with OpenTofu and Ansible
```

### After Installation
```bash
$ exasol version
Exasol Cloud Deployer v20251208-a9a5f25
Built with OpenTofu and Ansible
```

## Testing

Run unit tests:
```bash
./tests/test_version.sh
```

All tests pass:
- ✓ Local development version shows 'dev'
- ✓ Version command executes
- ✓ Version output has correct format
- ✓ Version output includes build info
- ✓ Environment variable override works
- ✓ Version injected into built script

## Technical Details

### Version Flow

1. **Local Development**:
   - Placeholder `__EXASOL_VERSION__` remains in script
   - Regex check `^__.*__$` matches placeholder
   - Version set to `dev`

2. **Build Process**:
   - `generate_version()` creates version from git tags or timestamp+hash
   - `sed` replaces `__EXASOL_VERSION__` with actual version
   - Regex check fails (no placeholder pattern)
   - Version set to actual version string

3. **Runtime Override**:
   - `EXASOL_VERSION` environment variable takes precedence
   - Useful for testing or custom deployments

### Why Regex Instead of Exact Match?

Using `[[ "$SCRIPT_VERSION_RAW" =~ ^__.*__$ ]]` instead of exact string match prevents issues when:
- sed replaces ALL occurrences of `__EXASOL_VERSION__` (including in if statement)
- Version string might accidentally match placeholder in future

## Integration

The version feature integrates seamlessly with:
- Build system (`build/create_release.sh`)
- Installer (`exasol-installer.sh`)
- Main CLI (`exasol`)
- Test suite (`tests/test_version.sh`)

Both installer and exasol versions are synchronized and derived from the same source (git tags or timestamp).
