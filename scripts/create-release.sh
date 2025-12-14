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
    local version
    # Check if working tree is clean
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        # Working tree has modifications, use dev version
        echo "dev-$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
    elif version=$(git describe --tags --exact-match 2>/dev/null); then
        echo "$version" | tr -d '\n'
    elif version=$(git describe --tags 2>/dev/null); then
        echo "$version" | tr -d '\n'
    else
        echo "dev-$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
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
    cp -r lib templates versions.conf instance-types.conf .tofurc "$stage_dir/"
    
    # Remove all .md files from staging
    find "$stage_dir" -name "*.md" -type f -delete
    
    # Copy exasol script and inject version
    sed "s|__EXASOL_VERSION__|$version|g" exasol > "$stage_dir/exasol"
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
  --install [PATH]         Install to specified path (default: auto-detect)
  --install-dependencies   Download and install OpenTofu, Python, and Ansible locally
  --dependencies-only      Install dependencies only (no main installation)
  --prefix PATH            Custom installation prefix
  --no-path                Skip PATH configuration
  --yes                    Overwrite existing installation without prompting
  --extract-only PATH      Extract files without installing
  --uninstall [PATH]       Uninstall from specified path (default: auto-detect)
  --version                Show installer version and exit
  --help                   Display this help message

Installation paths (auto-detected):
  Linux/WSL: ~/.local/bin
  macOS:     ~/bin or /usr/local/bin

Examples:
  # Download and install
  curl -fsSL URL -o exasol-deployer.sh
  chmod +x exasol-deployer.sh
  ./exasol-deployer.sh

  # Install with dependencies (self-contained)
  ./exasol-deployer.sh --install-dependencies

  # Install dependencies only
  ./exasol-deployer.sh --dependencies-only

  # Install to specific path
  ./exasol-deployer.sh --install ~/.local/bin

  # Force reinstall
  ./exasol-deployer.sh --yes

  # One-liner with dependencies
  curl -fsSL URL | bash -s -- --install-dependencies --yes

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

# Platform detection functions
detect_os() {
    case "$(uname -s)" in
        Linux*) echo "linux" ;;
        Darwin*) echo "darwin" ;;
        *) die "Unsupported operating system: $(uname -s)" ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *) die "Unsupported architecture: $(uname -m)" ;;
    esac
}

# Download and verify file
download_file() {
    local url="$1"
    local output="$2"
    local description="$3"
    local max_retries=10
    local retry_delay=5
    
    log_info "Downloading $description..."
    
    for attempt in $(seq 1 $max_retries); do
        if command -v curl >/dev/null 2>&1; then
            if curl -fsSL "$url" -o "$output"; then
                return 0
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget -q "$url" -O "$output"; then
                return 0
            fi
        else
            die "Neither curl nor wget found. Please install one of them."
        fi
        
        if [[ $attempt -lt $max_retries ]]; then
            log_info "Download failed (attempt $attempt/$max_retries), retrying in ${retry_delay}s..."
            sleep $retry_delay
        fi
    done
    
    die "Failed to download $description after $max_retries attempts"
}

# Install jq
install_jq() {
    local share_dir="$1"
    local os arch version url
    
    os=$(detect_os)
    arch=$(detect_arch)
    version="1.7.1"  # Latest stable
    
    # Convert arch for jq naming
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
    esac
    
    # jq uses different OS naming
    case "$os" in
        darwin) os="macos" ;;
    esac
    
    url="https://github.com/jqlang/jq/releases/download/jq-${version}/jq-${os}-${arch}"
    
    local jq_dir="$share_dir/jq"
    mkdir -p "$jq_dir"
    
    download_file "$url" "$jq_dir/jq" "jq v$version"
    chmod +x "$jq_dir/jq"
    
    log_info "✓ jq v$version installed"
}

# Install OpenTofu
install_opentofu() {
    local share_dir="$1"
    local os arch version url
    
    os=$(detect_os)
    arch=$(detect_arch)
    version="1.10.7"  # Latest stable
    
    # Convert arch for OpenTofu naming
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
    esac
    
    url="https://github.com/opentofu/opentofu/releases/download/v${version}/tofu_${version}_${os}_${arch}.zip"
    
    local tofu_dir="$share_dir/tofu"
    mkdir -p "$tofu_dir"
    
    local temp_zip=$(mktemp)
    trap "rm -f '$temp_zip'" EXIT
    
    download_file "$url" "$temp_zip" "OpenTofu v$version"
    
    log_info "Extracting OpenTofu..."
    if command -v unzip >/dev/null 2>&1; then
        unzip -q -o "$temp_zip" -d "$tofu_dir"
    else
        die "unzip command not found. Please install unzip."
    fi
    
    chmod +x "$tofu_dir/tofu"
    log_info "✓ OpenTofu v$version installed"
}

# Install portable Python + Ansible
install_python_ansible() {
    local share_dir="$1"
    local os arch python_version release_date triple url
    
    os=$(detect_os)
    arch=$(detect_arch)
    python_version="3.11.14"
    release_date="20251209"
    
    # Convert OS for python-build-standalone naming
    case "$os" in
        linux) triple="${arch}-unknown-linux-gnu" ;;
        darwin) triple="${arch}-apple-darwin" ;;
    esac
    
    url="https://github.com/astral-sh/python-build-standalone/releases/download/${release_date}/cpython-${python_version}+${release_date}-${triple}-install_only.tar.gz"
    
    local temp_tar=$(mktemp)
    trap "rm -f '$temp_tar'" EXIT
    
    download_file "$url" "$temp_tar" "Portable Python v$python_version"
    
    log_info "Extracting Python..."
    tar -xzf "$temp_tar" -C "$share_dir/"
    
    log_info "Installing Ansible..."
    "$share_dir/python/bin/python3" -m pip install --quiet ansible-core passlib cryptography
    
    log_info "Installing required Ansible collections..."
    "$share_dir/python/bin/ansible-galaxy" collection install community.crypto ansible.posix
    
    log_info "✓ Python v$python_version + Ansible + collections installed"
}

# Check system dependencies and provide guidance
check_system_dependencies() {
    local missing_tools=()
    local missing_portable=()
    local warnings=()
    
    # Check core tools (required)
    if ! command -v tofu >/dev/null 2>&1 && ! command -v terraform >/dev/null 2>&1; then
        missing_portable+=("OpenTofu/Terraform")
    fi
    
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        missing_portable+=("Ansible")
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_portable+=("jq")
    fi
    
    # Check basic system tools
    if ! command -v curl >/dev/null 2>&1; then
        missing_tools+=("curl")
    fi
    
    if ! command -v unzip >/dev/null 2>&1; then
        missing_tools+=("unzip")
    fi
    
    # Note: python3 warning is handled in show_dependency_guidance() which has portable detection
    
    # Return results
    if [[ ${#missing_tools[@]} -gt 0 || ${#missing_portable[@]} -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Check if a dependency is available (system or portable)
check_dependency_available() {
    local dep_name="$1"
    local install_dir="$2"
    
    case "$dep_name" in
        "tofu")
            [[ -n "$install_dir" && -x "$install_dir/share/tofu/tofu" ]] && return 0
            command -v tofu >/dev/null 2>&1 && return 0
            command -v terraform >/dev/null 2>&1 && return 0
            return 1
            ;;
        "ansible")
            [[ -n "$install_dir" && -x "$install_dir/share/python/bin/ansible-playbook" ]] && return 0
            command -v ansible-playbook >/dev/null 2>&1 && return 0
            return 1
            ;;
        "jq")
            [[ -n "$install_dir" && -x "$install_dir/share/jq/jq" ]] && return 0
            command -v jq >/dev/null 2>&1 && return 0
            return 1
            ;;
        "python")
            [[ -n "$install_dir" && -x "$install_dir/share/python/bin/python3" ]] && return 0
            command -v python3 >/dev/null 2>&1 && return 0
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Display dependency status and guidance
show_dependency_guidance() {
    local interactive="$1"
    local install_dir="$2"  # Optional: check for portable tools in this directory
    local missing_tools=()
    local missing_portable=()
    local warnings=()
    
    # Check portable dependencies using unified logic
    if ! check_dependency_available "tofu" "$install_dir"; then
        missing_portable+=("OpenTofu/Terraform")
    fi
    
    if ! check_dependency_available "ansible" "$install_dir"; then
        missing_portable+=("Ansible")
    fi
    
    if ! check_dependency_available "jq" "$install_dir"; then
        missing_portable+=("jq")
    fi
    
    # Check system tools
    if ! command -v curl >/dev/null 2>&1; then
        missing_tools+=("curl")
    fi
    
    if ! command -v unzip >/dev/null 2>&1; then
        missing_tools+=("unzip")
    fi
    
    # Show python warning only if neither system nor portable version available
    if ! check_dependency_available "python" "$install_dir"; then
        warnings+=("python3 not found - install with --install-dependencies or system package manager")
    fi
    
    # Show status
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "Error: Missing required system tools: ${missing_tools[*]}" >&2
        echo "Please install these tools using your system package manager:" >&2
        echo "  Ubuntu/Debian: sudo apt-get install ${missing_tools[*]}" >&2
        echo "  RHEL/CentOS: sudo yum install ${missing_tools[*]}" >&2
        echo "  macOS: brew install ${missing_tools[*]}" >&2
        return 1
    fi
    
    if [[ ${#missing_portable[@]} -gt 0 ]]; then
        if [[ "$interactive" == "true" ]]; then
            log_info "Missing tools: ${missing_portable[*]}"
            log_info "These can be installed automatically with --install-dependencies"
            log_info ""
            read -p "Install missing dependencies automatically? [y/N]: " -r
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                return 2  # Signal to install dependencies
            else
                log_info "You can install dependencies later with:"
                log_info "  $0 --install-dependencies --prefix $(dirname "$0")"
                return 3  # Signal interactive decline (different from non-interactive)
            fi
        else
            # Non-interactive mode - show specific missing tools
            echo "Error: Missing tools: ${missing_portable[*]}" >&2
            echo "Install with: bash -s -- --install-dependencies" >&2
            return 1
        fi
    fi
    
    if [[ ${#warnings[@]} -gt 0 ]]; then
        for warning in "${warnings[@]}"; do
            log_info "⚠ $warning"
        done
        log_info "✓ Required dependencies are available (portable versions will be used)"
    else
        log_info "✓ All required dependencies are available"
    fi
    return 0
}

# Install all dependencies
# Check if dependencies are available using absolute paths after installation
check_installed_dependencies() {
    local install_dir="$1"
    local share_dir="$install_dir/share"
    
    # Check OpenTofu/Terraform
    if [[ ! -x "$share_dir/tofu/tofu" ]] && ! command -v tofu >/dev/null 2>&1 && ! command -v terraform >/dev/null 2>&1; then
        return 1
    fi
    
    # Check jq
    if [[ ! -x "$share_dir/jq/jq" ]] && ! command -v jq >/dev/null 2>&1; then
        return 1
    fi
    
    # Check Ansible
    if [[ ! -x "$share_dir/python/bin/ansible-playbook" ]] && ! command -v ansible-playbook >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

install_dependencies() {
    local install_dir="$1"
    local share_dir="$install_dir/share"
    
    log_info ""
    log_info "Installing dependencies to: $share_dir"
    log_info ""
    
    mkdir -p "$share_dir"
    
    install_opentofu "$share_dir"
    install_jq "$share_dir"
    install_python_ansible "$share_dir"
    
    log_info ""
    log_info "✓ All dependencies installed successfully!"
    log_info ""
    log_info "Dependencies installed:"
    log_info "  OpenTofu: $share_dir/tofu/tofu"
    log_info "  jq:       $share_dir/jq/jq"
    log_info "  Python:   $share_dir/python/bin/python3"
    log_info "  Ansible:  $share_dir/python/bin/ansible-playbook"
    log_info ""
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

check_requirements_with_dependencies() {
    local interactive="$1"
    local install_dir="$2"  # Optional install directory for dependency installation
    
    # First check basic requirements
    check_requirements
    
    # Then check system dependencies
    local dep_result
    show_dependency_guidance "$interactive" "$install_dir"
    dep_result=$?
    
    case $dep_result in
        0) 
            # All dependencies available
            return 0
            ;;
        1)
            # Missing dependencies - specific error already shown by show_dependency_guidance
            return 1
            ;;
        2)
            # User wants to install dependencies
            if [[ -n "$install_dir" ]]; then
                log_info ""
                log_info "Installing dependencies first..."
                install_dependencies "$install_dir"
                log_info ""
                
                # Re-check dependencies using absolute paths after installation
                if ! check_installed_dependencies "$install_dir"; then
                    die "Dependency installation failed. Some tools are still missing."
                fi
                log_info "✓ All dependencies verified after installation"
                return 0  # Success after installation
            else
                return 2  # Return 2 if no install_dir provided (backward compatibility)
            fi
            ;;
        3)
            # Interactive user declined - message already shown
            die "Installation cancelled."
            ;;
    esac
}

detect_platform() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"
    case "$os" in
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl ($arch)"
            else
                echo "linux ($arch)"
            fi
            ;;
        Darwin*) echo "macos ($arch)" ;;
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
        linux*|wsl*)
            echo "$HOME/.local/bin"
            ;;
        macos*)
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
    local install_deps="$4"
    
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
    
    # STEP 1: Handle dependencies first (unless we're explicitly installing them separately)
    if [[ "$install_deps" != "true" ]]; then
        local interactive="false"
        if [[ -t 0 && "$yes" != "true" ]]; then
            interactive="true"
        fi
        
        if ! check_requirements_with_dependencies "$interactive" "$install_dir"; then
            die "Dependency check failed"
        fi
    else
        # Just check basic requirements when installing dependencies
        check_requirements
    fi
    
    # STEP 2: Handle main application installation
    # Check if this is a fresh install (no main application installed)
    local is_fresh_install=false
    if [[ ! -f "$symlink_path" ]] && [[ ! -f "$install_dir/exasol" ]]; then
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
            # Interactive mode - check for existing installation first
            local existing_version=""
            if [[ -f "$symlink_path" ]]; then
                existing_version=$("$symlink_path" version 2>/dev/null | head -1 || echo "unknown")
            fi
            
            echo ""
            log_info "Installation directory: $install_dir"
            log_info "Symlink will be created: $symlink_path"
            
            if [[ -n "$existing_version" ]]; then
                echo ""
                log_info "Found existing installation: $existing_version"
                echo ""
                read -p "Overwrite existing installation? [y/N] " -n 1 -r
            else
                echo ""
                read -p "Proceed with installation? [Y/n] " -n 1 -r
            fi
            
            echo
            if [[ -n "$existing_version" ]]; then
                # Existing installation - require explicit yes
                [[ $REPLY =~ ^[Yy]$ ]] || die "Installation cancelled by user"
            else
                # Fresh installation - default to yes
                [[ $REPLY =~ ^[Nn]$ ]] && die "Installation cancelled by user"
            fi
        fi
    else
        log_info "Install directory: $install_dir"
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
        cp -r "$install_dir"/{exasol,lib,templates,versions.conf,instance-types.conf,.tofurc} "$backup_dir/" 2>/dev/null || true
        log_info "Backed up to: $backup_dir"
    fi
    
    # Extract payload
    log_info "Extracting files..."
    extract_payload "$temp_dir" "$temp_archive"
    
    # Install files to subdirectory
    mkdir -p "$install_dir"
    cp -r "$temp_dir"/{exasol,lib,templates,versions.conf,instance-types.conf,.tofurc} "$install_dir/"
    chmod +x "$install_dir/exasol"
    
    # Create symlink
    rm -f "$symlink_path"
    ln -s "./exasol-deployer/exasol" "$symlink_path"
    log_info "Created symlink: $symlink_path -> ./exasol-deployer/exasol"
    
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
        
        # Detect if running interactively (must have both stdin/stdout as terminals AND not be piped)
        local is_interactive=false
        if [[ -t 0 && -t 1 && -z "${BASH_SUBSHELL:-}" && "${BASH_SOURCE[0]}" == "${0}" ]]; then
            is_interactive=true
        fi
        
        # Automatically source shell configuration if interactive
        local config_file
        config_file=$(get_shell_config "$shell_type")
        if [[ "$is_interactive" == "true" && -f "$config_file" ]]; then
            log_info "Reloading shell configuration..."
            # Source the config file to update PATH in current session
            if source "$config_file" 2>/dev/null; then
                log_info "✓ Shell configuration reloaded"
            else
                log_info "⚠ Could not reload shell configuration automatically"
                log_info "  Please run: source $config_file"
            fi
        else
            log_info "To use 'exasol' command, start a new shell or run:"
            log_info "  source $config_file"
        fi
        
        log_info ""
        log_info "Next steps:"
        if [[ "$is_interactive" == "true" ]]; then
            # Interactive mode - PATH should be updated
            log_info "  1. Verify: exasol version"
            log_info "  2. Get started: exasol help"
        else
            # Piped mode - need to reload shell or specify path
            local default_path
            default_path=$(get_default_install_path "$platform")
            log_info "  1. Reload shell: source $config_file"
            log_info "     OR use full path: $symlink_path"
            log_info "  2. Verify: exasol version"
            log_info "  3. Get started: exasol help"
            log_info ""
            log_info "Default install location: $default_path"
        fi
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
INSTALL_DEPENDENCIES=false
DEPENDENCIES_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) show_version; exit 0 ;;
        --help) show_help; exit 0 ;;
        --install)
            INSTALL_PATH="${2:-}"
            [[ -n "$INSTALL_PATH" ]] && shift
            shift
            ;;
        --install-dependencies) INSTALL_DEPENDENCIES=true; shift ;;
        --dependencies-only) DEPENDENCIES_ONLY=true; INSTALL_DEPENDENCIES=true; shift ;;
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

# Handle dependencies-only mode
if [[ "$DEPENDENCIES_ONLY" == "true" ]]; then
    check_requirements
    # Determine installation path if not set
    if [[ -z "$INSTALL_PATH" ]]; then
        INSTALL_PATH=$(get_default_install_path "$(detect_platform)")
    fi
    INSTALL_DIR="$INSTALL_PATH/exasol-deployer"
    install_dependencies "$INSTALL_DIR"
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

# Install dependencies first if requested
if [[ "$INSTALL_DEPENDENCIES" == "true" ]]; then
    # Determine installation path if not set
    if [[ -z "$INSTALL_PATH" ]]; then
        INSTALL_PATH=$(get_default_install_path "$(detect_platform)")
    fi
    INSTALL_DIR="$INSTALL_PATH/exasol-deployer"
    install_dependencies "$INSTALL_DIR"
fi

# Run installation
install_exasol "$INSTALL_PATH" "$YES" "$SKIP_PATH" "$INSTALL_DEPENDENCIES"

exit 0
__ARCHIVE_BELOW__
INSTALLER_HEADER

    # Replace placeholders
    sed -i "s|__VERSION__|$version|g" "$output_file"
    sed -i "s|__CHECKSUM__|$checksum|g" "$output_file"
    sed -i "s|__BUILD_DATE__|$(date -u +%Y-%m-%dT%H:%M:%SZ)|g" "$output_file"
    
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
