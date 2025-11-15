# Create Automated Release Build System

Create a build script that generates a single self-contained bash installer executable with the following sequential workflow:

## Phase 1: Build Process (Executed on CI/Build Machine)

1. **Generate Version Information**: Create automatic versioning using timestamp + git hash (format: YYYYMMDD-HHMMSS-GITSHORT)
2. **Regenerate Cloud Permissions**: Use pike tool to scan all Terraform templates and update REQUIRED_PERMISSIONS for each cloud provider
3. **Create Production Artifact**: Bundle only essential files (exclude .md docs, tests, development files) into a single self-contained bash script
4. **Make Executable**: Ensure the final artifact is a standalone bash script that can be executed directly
5. **Full Functionality**: This standalone release artifact should be fully functional (contain all templates, sub scripts, etc)
6. **Install Option**: The new option `--install` (with optional arguments) should do the Installation Process from Phase 2.

## Phase 2: Installation Process (Executed on End-User Machine)

1. **One-Line Installation**: Support `curl https://... | bash` execution pattern
2. **Platform Detection**: Auto-detect OS (Linux/macOS/WSL) and shell environment (bash/zsh/fish)
3. **Rootless Installation**: Install to appropriate user directory (~/.local/bin/exasol on Linux, ~/bin/exasol on macOS)
4. **User Confirmation**: Prompt user to confirm installation location and PATH modifications
5. **Update Detection**: Check if exasol is already installed and prompt for update confirmation
6. **PATH Configuration**: Automatically add exasol to PATH for all detected shells (bash, zsh, fish) with user confirmation
7. **Cross-Platform Compatibility**: Ensure works on Linux distributions, macOS Terminal, WSL, and other Unix-like systems

## Success Criteria

- Single executable file that handles complete installation
- No external dependencies beyond curl/bash
- Graceful handling of existing installations
- Clear user prompts with sensible defaults
- Automatic PATH setup for all common shells