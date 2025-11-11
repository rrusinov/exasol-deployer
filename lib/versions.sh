#!/bin/bash
# Version management functions

# Include guard
if [[ -n "${__EXASOL_VERSIONS_SH_INCLUDED__:-}" ]]; then
    return 0
fi
readonly __EXASOL_VERSIONS_SH_INCLUDED__=1

# Source common functions
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/common.sh"

# Get versions config file path
get_versions_config_path() {
    local script_root
    script_root="$(cd "$LIB_DIR/.." && pwd)"
    echo "$script_root/versions.conf"
}

# List all available versions
list_versions() {
    local config_file
    config_file=$(get_versions_config_path)

    if [[ ! -f "$config_file" ]]; then
        die "Versions config file not found: $config_file"
    fi

    get_config_sections "$config_file" | grep -v "^default$"
}

# Get default version
get_default_version() {
    local config_file
    config_file=$(get_versions_config_path)

    parse_config_file "$config_file" "default" "VERSION"
}

# Check if version exists
version_exists() {
    local version="$1"
    local config_file
    config_file=$(get_versions_config_path)

    get_config_sections "$config_file" | grep -q "^${version}$"
}

# Get version configuration value
get_version_config() {
    local version="$1"
    local key="$2"

    local config_file
    config_file=$(get_versions_config_path)

    if ! version_exists "$version"; then
        log_error "Version not found: $version"
        return 1
    fi

    parse_config_file "$config_file" "$version" "$key"
}

# Validate version format
validate_version_format() {
    local version="$1"

    # Expected formats:
    # - name-X.Y.Z (e.g., exasol-2025.1.4) - default x86_64
    # - name-X.Y.Z-arm64 (e.g., exasol-2025.1.4-arm64) - ARM64 variant
    # - name-X.Y.Z-local (e.g., exasol-2025.1.4-local) - local variant
    # - name-X.Y.Z-arm64-local (e.g., exasol-2025.1.4-arm64-local) - local ARM64
    if [[ ! "$version" =~ ^[a-z]+-[0-9]+\.[0-9]+\.[0-9]+(-arm64)?(-local)?$ ]]; then
        log_error "Invalid version format: $version"
        log_error "Expected format: name-X.Y.Z[-arm64][-local]"
        log_error "Examples:"
        log_error "  - exasol-2025.1.4 (x86_64, default)"
        log_error "  - exasol-2025.1.4-arm64 (ARM64 variant)"
        log_error "  - exasol-2025.1.4-local (local x86_64 variant)"
        log_error "  - exasol-2025.1.4-arm64-local (local ARM64 variant)"
        return 1
    fi
}

# Parse version into components
parse_version() {
    local version="$1"
    local component="$2"

    case "$component" in
        db_version)
            echo "$version" | cut -d'-' -f1
            ;;
        architecture)
            echo "$version" | cut -d'-' -f2
            ;;
        *)
            log_error "Unknown version component: $component"
            return 1
            ;;
    esac
}

# Download file with progress
download_file() {
    local url="$1"
    local dest="$2"

    log_info "Downloading: $url"

    if command_exists curl; then
        curl -L -# -o "$dest" "$url" || return 1
    elif command_exists wget; then
        wget --progress=bar:force -O "$dest" "$url" || return 1
    else
        log_error "Neither curl nor wget found. Please install one of them."
        return 1
    fi

    log_info "Downloaded to: $dest"
}

# Verify file checksum
verify_checksum() {
    local file="$1"
    local expected_checksum="$2"

    if [[ "$expected_checksum" == "placeholder" ]] || [[ "$expected_checksum" == "sha256:placeholder" ]]; then
        log_warn "Checksum verification skipped (placeholder checksum)"
        return 0
    fi

    # Extract hash type and value
    local hash_type="${expected_checksum%%:*}"
    local hash_value="${expected_checksum#*:}"

    log_debug "Verifying $hash_type checksum..."

    local actual_checksum
    case "$hash_type" in
        sha256)
            if command_exists shasum; then
                actual_checksum=$(shasum -a 256 "$file" | awk '{print $1}')
            elif command_exists sha256sum; then
                actual_checksum=$(sha256sum "$file" | awk '{print $1}')
            else
                log_warn "No SHA256 tool found, skipping checksum verification"
                return 0
            fi
            ;;
        *)
            log_warn "Unsupported hash type: $hash_type"
            return 0
            ;;
    esac

    if [[ "$actual_checksum" != "$hash_value" ]]; then
        log_error "Checksum verification failed!"
        log_error "Expected: $hash_value"
        log_error "Got:      $actual_checksum"
        return 1
    fi

    log_info "Checksum verified successfully"
}

# Download and verify version files
download_version_files() {
    local version="$1"
    local dest_dir="$2"

    ensure_directory "$dest_dir"

    # Get version configuration
    local db_version architecture db_url db_checksum c4_url c4_checksum
    db_version=$(get_version_config "$version" "DB_VERSION")
    architecture=$(get_version_config "$version" "ARCHITECTURE")
    db_url=$(get_version_config "$version" "DB_DOWNLOAD_URL")
    db_checksum=$(get_version_config "$version" "DB_CHECKSUM")
    c4_url=$(get_version_config "$version" "C4_DOWNLOAD_URL")
    c4_checksum=$(get_version_config "$version" "C4_CHECKSUM")

    # Download database tarball
    local db_filename="exasol-${db_version}.tar.gz"
    local db_path="$dest_dir/$db_filename"

    if [[ ! -f "$db_path" ]]; then
        log_info "Downloading Exasol database version $db_version ($architecture)..."
        download_file "$db_url" "$db_path" || return 1
        verify_checksum "$db_path" "$db_checksum" || return 1
    else
        log_info "Database tarball already exists: $db_path"
    fi

    # Download c4 binary
    local c4_filename="c4"
    local c4_path="$dest_dir/$c4_filename"

    if [[ ! -f "$c4_path" ]]; then
        log_info "Downloading c4 binary..."
        download_file "$c4_url" "$c4_path" || return 1
        verify_checksum "$c4_path" "$c4_checksum" || return 1
        chmod +x "$c4_path"
    else
        log_info "c4 binary already exists: $c4_path"
    fi

    log_info "All version files downloaded successfully"
}
