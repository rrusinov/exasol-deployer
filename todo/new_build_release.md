# Create Automated Release Build System

Create a build script that generates a single self-contained bash installer executable following best practices for shell script installers.

## Phase 1: Build Process (Executed on CI/Build Machine)

### Build Script (`build/create_release.sh`)

1. **Version Generation**: Auto-generate version from git tags or timestamp + git hash (format: v1.2.3 or YYYYMMDD-GITSHORT)
2. **Payload Preparation**: 
   - Bundle essential runtime files (lib/, templates/, exasol main script, versions.conf, instance-types.conf)
   - Exclude development files (.md docs, tests/, .git/, .venv/, build/, todo/)
   - Create tarball payload with deterministic ordering
3. **Self-Extracting Archive**: Generate installer using makeself-style approach:
   - Installer header (bash script with installation logic)
   - Embedded base64-encoded tarball payload
   - Extraction and installation functions
4. **Metadata Embedding**: Include version, checksum, build date in installer header
5. **Executable Output**: Produce `exasol-installer.sh` with +x permissions

### Installer Structure
```
#!/usr/bin/env bash
# Installer header with metadata and functions
# __ARCHIVE_BELOW__
# <base64-encoded tarball>
```

## Phase 2: Installation Process (Executed on End-User Machine)

### Installer Modes

**Direct Execution**: `./exasol-installer.sh [OPTIONS]`
**Pipe Installation**: `curl -fsSL https://... | bash -s -- [OPTIONS]`

### Installation Options

- `--install [PATH]`: Install to specified path (default: auto-detect)
- `--prefix PATH`: Custom installation prefix
- `--no-path`: Skip PATH configuration
- `--force`: Overwrite existing installation without prompting
- `--extract-only PATH`: Extract files without installing
- `--version`: Show installer version and exit
- `--help`: Display usage information

### Installation Flow

1. **Preflight Checks**:
   - Verify bash version (4.0+)
   - Check required commands (tar, base64, mkdir, chmod)
   - Validate disk space availability
   - Check write permissions

2. **Platform Detection**:
   - OS detection (Linux/macOS/WSL/BSD)
   - Shell detection (bash/zsh/fish)
   - XDG Base Directory compliance on Linux

3. **Installation Path Selection**:
   - Linux: `~/.local/bin` (XDG standard)
   - macOS: `~/bin` or `/usr/local/bin` (with sudo)
   - WSL: `~/.local/bin`
   - Custom: User-specified via `--prefix`

4. **Update Detection**:
   - Check for existing installation
   - Compare versions (semantic or timestamp)
   - Prompt for confirmation unless `--force`
   - Backup existing installation before update

5. **Extraction & Installation**:
   - Create temporary directory (mktemp)
   - Extract embedded tarball to temp location
   - Verify extraction integrity
   - Copy files to installation directory
   - Set proper permissions (755 for executables)
   - Clean up temporary files

6. **PATH Configuration** (unless `--no-path`):
   - Detect shell config files (~/.bashrc, ~/.zshrc, ~/.config/fish/config.fish)
   - Check if PATH already configured
   - Add PATH export with idempotent guards
   - Prompt user to reload shell or source config

7. **Post-Install Verification**:
   - Verify exasol executable is accessible
   - Run basic health check (`exasol --version`)
   - Display success message with next steps

### Error Handling

- Trap EXIT/ERR for cleanup
- Rollback on installation failure
- Preserve existing installation on update failure
- Clear error messages with troubleshooting hints
- Non-zero exit codes for scripting

## Success Criteria

- Single self-contained executable (no external dependencies except bash/tar/base64)
- Idempotent installation (safe to run multiple times)
- Atomic updates (rollback on failure)
- XDG Base Directory compliance
- Works with `curl | bash` pattern
- Supports both interactive and non-interactive modes
- Proper exit codes for automation
- Clear, actionable error messages
- Minimal user interaction with sensible defaults
- Respects user environment (no sudo required for user install)