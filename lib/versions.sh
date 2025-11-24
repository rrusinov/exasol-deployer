#!/usr/bin/env bash
# Version management functions

# Include guard
if [[ -n "${__EXASOL_VERSIONS_SH_INCLUDED__:-}" ]]; then
    return 0
fi
readonly __EXASOL_VERSIONS_SH_INCLUDED__=1

# Source common functions
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"

# Get versions config file path
get_versions_config_path() {
    if [[ -n "${EXASOL_VERSIONS_CONFIG:-}" ]]; then
        echo "$EXASOL_VERSIONS_CONFIG"
        return
    fi

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
        log_error ""
        log_error "Available versions:"
        local available_versions
        available_versions=$(list_versions 2>/dev/null)
        if [[ -n "$available_versions" ]]; then
            echo "$available_versions" | while read -r v; do
                log_error "  - $v"
            done
        else
            log_error "  (No versions configured)"
        fi
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

# Get instance types config file path
get_instance_types_config_path() {
    if [[ -n "${EXASOL_INSTANCE_TYPES_CONFIG:-}" ]]; then
        echo "$EXASOL_INSTANCE_TYPES_CONFIG"
        return
    fi

    local script_root
    script_root="$(cd "$LIB_DIR/.." && pwd)"
    echo "$script_root/instance-types.conf"
}

# Get default instance type for provider and architecture
get_instance_type_default() {
    local provider="$1"
    local architecture="$2"

    local config_file
    config_file=$(get_instance_types_config_path)

    if [[ ! -f "$config_file" ]]; then
        log_error "Instance types config file not found: $config_file"
        return 1
    fi

    parse_config_file "$config_file" "$provider" "$architecture"
}
