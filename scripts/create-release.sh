#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC2155
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2155
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly BUILD_DIR="$PROJECT_ROOT/build"
readonly OUTPUT_NAME="exasol-deployer.sh"

# Generate version from git or fallback to timestamp
generate_version() {
    if git describe --tags --exact-match 2>/dev/null; then
        git describe --tags --exact-match
    elif git describe --tags 2>/dev/null; then
        git describe --tags
    else
        echo "$(date +%Y%m%d)-$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
    fi
}

# Create payload tarball with deterministic ordering
create_payload() {
    local temp_dir="$1"
    local payload_tar="$2"
    local version="$3"
    
    cd "$PROJECT_ROOT"
    
    # Create temp staging directory
    local stage_dir="$temp_dir/stage"
    mkdir -p "$stage_dir"
    
    # Copy files to staging
    cp -r lib templates versions.conf instance-types.conf "$stage_dir/"
    
    # Remove all .md files from staging
    find "$stage_dir" -name "*.md" -type f -delete
    
    # Copy exasol script and inject version
    sed "s/__EXASOL_VERSION__/$version/g" exasol > "$stage_dir/exasol"
    chmod +x "$stage_dir/exasol"
    
    # Create tarball from staging directory
    cd "$stage_dir"
    tar --create \
        --file="$payload_tar" \
        --sort=name \
        --mtime='2025-01-01 00:00:00' \
        --owner=0 --group=0 \
        --mode='a+rX,u+w' \
        .
}

# Generate self-extracting installer
create_installer() {
    local version="$1"
    local payload_tar="$2"
    local output_file="$3"
    local checksum
    
    checksum=$(sha256sum "$payload_tar" | awk '{print $1}')
    
    # Read installer template and payload
    cat > "$output_file" << 'INSTALLER_HEADER'
#!/usr/bin/env bash
set -euo pipefail

# Handle piped execution FIRST (before any other code)
if [[ ! -f "$0" ]] || [[ "$0" == "bash" ]] || [[ "$0" == "-bash" ]] || [[ "$0" == "sh" ]]; then
    TEMP_INSTALLER=$(mktemp)
    cat > "$TEMP_INSTALLER"
    chmod +x "$TEMP_INSTALLER"
    exec "$TEMP_INSTALLER" "$@"
fi

readonly INSTALLER_VERSION="__VERSION__"
readonly PAYLOAD_CHECKSUM="__CHECKSUM__"
readonly BUILD_DATE="__BUILD_DATE__"

# Colors and basic functions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

die() { echo -e "${RED}Error: $*${NC}" >&2; exit 1; }
log_info() { echo -e "${GREEN}$*${NC}"; }
log_warn() { echo -e "${YELLOW}$*${NC}"; }

readonly SCRIPT_SELF="$0"

show_version() {
    echo "Exasol Deployer Installer $INSTALLER_VERSION"
    echo "Build date: $BUILD_DATE"
    echo "Payload checksum: $PAYLOAD_CHECKSUM"
}

show_help() {
    cat << EOF
Exasol Deployer Installer $INSTALLER_VERSION

Usage: $0 [OPTIONS]

Options:
  --install [PATH]     Install to specified path (default: auto-detect)
  --prefix PATH        Custom installation prefix
  --no-path            Skip PATH configuration
  --yes              Overwrite existing installation without prompting
  --extract-only PATH  Extract files without installing
  --uninstall [PATH]   Uninstall from specified path (default: auto-detect)
  --version            Show installer version and exit
  --help               Display this help message

Installation paths (auto-detected):
  Linux/WSL: ~/.local/bin
  macOS:     ~/bin or /usr/local/bin

Examples:
  # Download and install
  curl -fsSL URL -o exasol-deployer.sh
  chmod +x exasol-deployer.sh
  ./exasol-deployer.sh

  # Install to specific path
  ./exasol-deployer.sh --install ~/.local/bin

  # Force reinstall
  ./exasol-deployer.sh --yes

  # Uninstall
  ./exasol-deployer.sh --uninstall

  # One-liner (download, execute, cleanup)
  curl -fsSL URL -o /tmp/install.sh && bash /tmp/install.sh --yes && rm /tmp/install.sh
  
  # Pipe pattern (requires --yes for non-interactive)
  curl -fsSL URL | bash -s -- --yes
  
  # Pipe with custom path
  curl -fsSL URL | bash -s -- --install ~/.local/bin --yes
EOF
}

uninstall_exasol() {
    local uninstall_path="$1"
    local yes="$2"
    
    local platform
    platform=$(detect_platform)
    
    # Use provided path or detect default
    if [[ -z "$uninstall_path" ]]; then
        uninstall_path=$(get_default_install_path "$platform")
    fi
    
    local install_dir="$uninstall_path/exasol-deployer"
    local symlink_path="$uninstall_path/exasol"
    
    # Check if installation exists
    if [[ ! -d "$install_dir" ]] && [[ ! -L "$symlink_path" ]]; then
        die "No installation found at: $uninstall_path"
    fi
    
    # Get version if possible
    local version="unknown"
    if [[ -f "$symlink_path" ]]; then
        version=$("$symlink_path" version 2>/dev/null | head -1 || echo "unknown")
    fi
    
    # Confirm uninstallation
    if [[ "$yes" != "true" ]]; then
        if [[ ! -t 0 ]]; then
            die "Non-interactive mode detected. Use --yes for non-interactive uninstallation."
        fi
        echo ""
        log_info "Found installation: $version"
        log_info "Installation directory: $install_dir"
        if [[ -L "$symlink_path" ]]; then
            log_info "Symlink: $symlink_path"
        fi
        echo ""
        log_warn "This will permanently remove all files!"
        read -p "Proceed with uninstallation? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            die "Uninstallation cancelled by user"
        fi
    fi
    
    # Remove installation
    log_info "Removing installation..."
    
    if [[ -L "$symlink_path" ]]; then
        rm -f "$symlink_path"
        log_info "Removed symlink: $symlink_path"
    fi
    
    if [[ -d "$install_dir" ]]; then
        rm -rf "$install_dir"
        log_info "Removed directory: $install_dir"
    fi
    
    log_info "✓ Uninstallation complete!"
}

check_requirements() {
    local missing=()
    for cmd in tar base64 mkdir chmod; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    
    [[ ${#missing[@]} -eq 0 ]] || die "Missing required commands: ${missing[*]}"
    
    # Check bash version
    if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
        die "Bash 4.0+ required (found ${BASH_VERSION})"
    fi
}

detect_platform() {
    local os
    os="$(uname -s)"
    case "$os" in
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        Darwin*) echo "macos" ;;
        *) die "Unsupported OS: $os" ;;
    esac
}

detect_shell() {
    local shell_name
    shell_name="$(basename "$SHELL")"
    case "$shell_name" in
        bash|zsh|fish) echo "$shell_name" ;;
        *) echo "bash" ;;
    esac
}

get_default_install_path() {
    local platform="$1"
    case "$platform" in
        linux|wsl)
            echo "$HOME/.local/bin"
            ;;
        macos)
            if [[ -d "$HOME/bin" ]] || [[ ! -w /usr/local/bin ]]; then
                echo "$HOME/bin"
            else
                echo "/usr/local/bin"
            fi
            ;;
    esac
}

get_shell_config() {
    local shell_type="$1"
    case "$shell_type" in
        bash)
            [[ -f "$HOME/.bashrc" ]] && echo "$HOME/.bashrc" || echo "$HOME/.bash_profile"
            ;;
        zsh) echo "$HOME/.zshrc" ;;
        fish) echo "$HOME/.config/fish/config.fish" ;;
    esac
}

check_existing_installation() {
    local install_path="$1"
    local exasol_bin="$install_path/exasol"
    
    if [[ -f "$exasol_bin" ]]; then
        local current_version
        current_version=$("$exasol_bin" version 2>/dev/null | head -1 || echo "unknown")
        echo "$current_version"
    fi
}

extract_payload() {
    local extract_dir="$1"
    local temp_archive="$2"
    
    # Extract embedded payload
    local archive_line
    archive_line=$(awk '/^__ARCHIVE_BELOW__/ {print NR + 1; exit}' "$SCRIPT_SELF")
    
    tail -n +"$archive_line" "$SCRIPT_SELF" | base64 -d > "$temp_archive"
    
    # Verify checksum
    local actual_checksum
    actual_checksum=$(sha256sum "$temp_archive" | awk '{print $1}')
    [[ "$actual_checksum" == "$PAYLOAD_CHECKSUM" ]] || die "Checksum mismatch"
    
    # Extract tarball
    tar -xf "$temp_archive" -C "$extract_dir"
}

configure_path() {
    local install_path="$1"
    local shell_type="$2"
    local config_file
    
    config_file=$(get_shell_config "$shell_type")
    
    # Check if already in PATH
    if echo "$PATH" | grep -q "$install_path"; then
        log_info "✓ $install_path already in PATH"
        return 0
    fi
    
    # Check if already configured in shell config using marker
    local marker="# Added by Exasol Deployer installer"
    if [[ -f "$config_file" ]] && grep -q "$marker" "$config_file"; then
        log_info "✓ PATH already configured in $config_file"
        return 0
    fi
    
    # Add to shell config
    mkdir -p "$(dirname "$config_file")"
    
    case "$shell_type" in
        fish)
            echo "" >> "$config_file"
            echo "$marker" >> "$config_file"
            echo "fish_add_path $install_path" >> "$config_file"
            ;;
        *)
            echo "" >> "$config_file"
            echo "$marker" >> "$config_file"
            echo "export PATH=\"$install_path:\$PATH\"" >> "$config_file"
            ;;
    esac
    
    log_info "✓ Added $install_path to $config_file"
    log_warn "  Run: source $config_file"
}

install_exasol() {
    local install_path="$1"
    local yes="$2"
    local skip_path="$3"
    
    check_requirements
    
    local platform shell_type
    platform=$(detect_platform)
    shell_type=$(detect_shell)
    
    log_info "Platform: $platform, Shell: $shell_type"
    
    # Use provided path or detect default
    if [[ -z "$install_path" ]]; then
        install_path=$(get_default_install_path "$platform")
    fi
    
    # Create subdirectory for installation
    local install_dir="$install_path/exasol-deployer"
    local symlink_path="$install_path/exasol"
    
    # Check if this is a fresh install (directory doesn't exist or is empty)
    local is_fresh_install=false
    if [[ ! -d "$install_dir" ]] || [[ -z "$(ls -A "$install_dir" 2>/dev/null)" ]]; then
        is_fresh_install=true
    fi
    
    # Confirm installation directory (unless --yes or fresh install in non-interactive mode)
    if [[ "$yes" != "true" ]]; then
        if [[ ! -t 0 ]]; then
            # Non-interactive mode
            if [[ "$is_fresh_install" == "true" ]]; then
                # Fresh install - proceed without confirmation
                log_info "Fresh installation to: $install_dir"
            else
                # Existing installation - require --yes
                die "Existing installation detected. Use 'bash -s -- --yes' to overwrite non-interactively."
            fi
        else
            # Interactive mode - always ask
            echo ""
            log_info "Installation directory: $install_dir"
            log_info "Symlink will be created: $symlink_path"
            echo ""
            read -p "Proceed with installation? [Y/n] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                die "Installation cancelled by user"
            fi
        fi
    else
        log_info "Install directory: $install_dir"
    fi
    
    # Check existing installation
    local existing_version=""
    if [[ -f "$symlink_path" ]]; then
        existing_version=$("$symlink_path" version 2>/dev/null | head -1 || echo "unknown")
    fi
    
    if [[ -n "$existing_version" ]]; then
        log_info "Found existing installation: $existing_version"
        if [[ "$yes" != "true" ]]; then
            read -p "Overwrite? [y/N] " -n 1 -r
            echo
            [[ $REPLY =~ ^[Yy]$ ]] || die "Installation cancelled"
        fi
    fi
    
    # Create temp directory
    local temp_dir temp_archive backup_dir
    temp_dir=$(mktemp -d)
    temp_archive="$temp_dir/payload.tar"
    # shellcheck disable=SC2064
    trap "rm -rf '$temp_dir'" EXIT
    
    # Backup existing installation
    if [[ -d "$install_dir" ]]; then
        backup_dir="$install_dir/.backup-$(date +%s)"
        mkdir -p "$backup_dir"
        cp -r "$install_dir"/{exasol,lib,templates,versions.conf,instance-types.conf} "$backup_dir/" 2>/dev/null || true
        log_info "Backed up to: $backup_dir"
    fi
    
    # Extract payload
    log_info "Extracting files..."
    extract_payload "$temp_dir" "$temp_archive"
    
    # Install files to subdirectory
    mkdir -p "$install_dir"
    cp -r "$temp_dir"/{exasol,lib,templates,versions.conf,instance-types.conf} "$install_dir/"
    chmod +x "$install_dir/exasol"
    
    # Create symlink
    rm -f "$symlink_path"
    ln -s "$install_dir/exasol" "$symlink_path"
    log_info "Created symlink: $symlink_path -> $install_dir/exasol"
    
    # Configure PATH
    if [[ "$skip_path" != "true" ]]; then
        configure_path "$install_path" "$shell_type"
    fi
    
    # Verify installation
    if "$symlink_path" version >/dev/null 2>&1; then
        log_info "✓ Installation successful!"
        log_info ""
        log_info "Exasol Deployer $INSTALLER_VERSION installed to: $install_dir"
        log_info "Symlink created: $symlink_path"
        log_info ""
        log_info "Next steps:"
        log_info "  1. Reload shell: source $(get_shell_config "$shell_type")"
        log_info "  2. Verify: exasol version"
        log_info "  3. Get started: exasol help"
    else
        die "Installation verification failed"
    fi
}

# Parse arguments
INSTALL_PATH=""
UNINSTALL_PATH=""
UNINSTALL_MODE=false
YES=false
SKIP_PATH=false
EXTRACT_ONLY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) show_version; exit 0 ;;
        --help) show_help; exit 0 ;;
        --install)
            INSTALL_PATH="${2:-}"
            [[ -n "$INSTALL_PATH" ]] && shift
            shift
            ;;
        --prefix)
            INSTALL_PATH="$2"
            shift 2
            ;;
        --uninstall)
            UNINSTALL_MODE=true
            UNINSTALL_PATH="${2:-}"
            [[ -n "$UNINSTALL_PATH" ]] && shift
            shift
            ;;
        --yes) YES=true; shift ;;
        --no-path) SKIP_PATH=true; shift ;;
        --extract-only)
            EXTRACT_ONLY="$2"
            shift 2
            ;;
        *) die "Unknown option: $1 (use --help)" ;;
    esac
done

# Handle uninstall mode
if [[ "$UNINSTALL_MODE" == "true" ]]; then
    uninstall_exasol "$UNINSTALL_PATH" "$YES"
    exit 0
fi

# Handle extract-only mode
if [[ -n "$EXTRACT_ONLY" ]]; then
    check_requirements
    mkdir -p "$EXTRACT_ONLY"
    temp_archive=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$temp_archive'" EXIT
    log_info "Extracting to: $EXTRACT_ONLY"
    extract_payload "$EXTRACT_ONLY" "$temp_archive"
    log_info "✓ Extraction complete"
    exit 0
fi

# Run installation
install_exasol "$INSTALL_PATH" "$YES" "$SKIP_PATH"

exit 0
__ARCHIVE_BELOW__
INSTALLER_HEADER

    # Replace placeholders
    sed -i "s/__VERSION__/$version/g" "$output_file"
    sed -i "s/__CHECKSUM__/$checksum/g" "$output_file"
    sed -i "s/__BUILD_DATE__/$(date -u +%Y-%m-%dT%H:%M:%SZ)/g" "$output_file"
    
    # Append base64-encoded payload
    base64 "$payload_tar" >> "$output_file"
    
    chmod +x "$output_file"
}

main() {
    local version output_file temp_dir payload_tar
    
    version=$(generate_version)
    mkdir -p "$BUILD_DIR"
    output_file="$BUILD_DIR/$OUTPUT_NAME"
    temp_dir=$(mktemp -d)
    payload_tar="$temp_dir/payload.tar"
    
    # shellcheck disable=SC2064
    trap "rm -rf '$temp_dir'" EXIT
    
    echo "Building Exasol Deployer installer..."
    echo "Version: $version"
    
    # Create payload
    echo "Creating payload..."
    create_payload "$temp_dir" "$payload_tar" "$version"
    
    # Generate installer
    echo "Generating installer..."
    create_installer "$version" "$payload_tar" "$output_file"
    
    echo ""
    echo "✓ Build complete: $output_file"
    echo "  Size: $(du -h "$output_file" | cut -f1)"
    echo ""
    echo "Test installation:"
    echo "  $output_file --extract-only /tmp/test-extract"
    echo "  $output_file --install ~/.local/bin --yes"
}

main "$@"
