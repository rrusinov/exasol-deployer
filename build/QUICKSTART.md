# Build System Quick Start

## Build a Release

```bash
./build/create_release.sh
```

Output: `build/exasol-installer.sh` (~620KB)

## Test the Installer

```bash
# Show version
./build/exasol-installer.sh --version

# Show help
./build/exasol-installer.sh --help

# Extract to inspect
./build/exasol-installer.sh --extract-only /tmp/test

# Test install
./build/exasol-installer.sh --install /tmp/test-install --no-path --force
```

## Distribute

### Option 1: Direct Download
```bash
curl -fsSL https://example.com/exasol-installer.sh -o exasol-installer.sh
chmod +x exasol-installer.sh
./exasol-installer.sh
```

### Option 2: One-Liner
```bash
curl -fsSL https://example.com/exasol-installer.sh -o /tmp/i.sh && bash /tmp/i.sh && rm /tmp/i.sh
```

## End User Installation

```bash
# Interactive (recommended)
./exasol-installer.sh

# Non-interactive
./exasol-installer.sh --force

# Custom path
./exasol-installer.sh --install /opt/exasol

# Skip PATH config
./exasol-installer.sh --no-path
```

## Version Strategy

- **Git tag**: `v1.0.0` → installer version `v1.0.0`
- **Git tag + commits**: `v1.0.0-5-g1234abc` → installer version `v1.0.0-5-g1234abc`
- **No tags**: `20251208-a9a5f25` (timestamp + short hash)

## What Gets Bundled

✅ Included:
- `exasol` (main CLI)
- `lib/` (shell libraries)
- `templates/` (Terraform/Ansible)
- `versions.conf`
- `instance-types.conf`

❌ Excluded:
- Documentation (*.md)
- Tests (tests/)
- Build scripts (build/)
- Dev files (.git/, .venv/)
- Deployment artifacts

## Troubleshooting

**Build fails**: Check git is available and you're in the project root

**Installer too large**: Normal size is ~620KB; check for unexpected files in bundle

**Installation fails**: Verify bash 4.0+, tar, base64 are available

**PATH not updated**: Source shell config or restart shell

## CI/CD Integration

```yaml
# GitHub Actions example
- name: Build installer
  run: ./build/create_release.sh

- name: Upload release
  uses: actions/upload-artifact@v3
  with:
    name: exasol-installer
    path: build/exasol-installer.sh
```

## More Info

- Full documentation: `build/README.md`
- Implementation details: `build/IMPLEMENTATION.md`
