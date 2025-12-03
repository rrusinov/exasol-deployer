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

check_download_target_availability() {
    local url="$1"
    local label="$2"

    if [[ -z "$url" ]]; then
        echo "missing|No $label URL configured"
        return 1
    fi

    if [[ "$url" == file://* ]]; then
        local path="${url#file://}"
        if [[ $path == ~/* ]]; then
            path="${HOME}${path#~}"
        fi

        if [[ -r "$path" ]]; then
            echo "ok|$label file available: $path"
            return 0
        fi

        echo "missing|$label file not found: $path"
        return 1
    fi

    if ! command_exists curl; then
        echo "unknown|Cannot check $label URL (curl not installed)"
        return 1
    fi

    if curl --head --silent --fail --location --max-time 10 "$url" >/dev/null 2>&1; then
        echo "ok|$label reachable: $url"
        return 0
    fi

    echo "missing|$label not reachable: $url"
    return 1
}

list_versions_with_availability() {
    local config_file
    config_file=$(get_versions_config_path)

    if [[ ! -f "$config_file" ]]; then
        die "Versions config file not found: $config_file"
    fi

    local default_version
    default_version=$(get_default_version)

    local versions
    versions=$(get_config_sections "$config_file" | grep -v "^default$")

    if [[ -z "$versions" ]]; then
        log_info "  (no versions configured)"
        return 0
    fi

    while IFS= read -r version; do
        [[ -z "$version" ]] && continue

        local db_url c4_url
        db_url=$(parse_config_file "$config_file" "$version" "DB_DOWNLOAD_URL")
        c4_url=$(parse_config_file "$config_file" "$version" "C4_DOWNLOAD_URL")
        local architecture
        architecture=$(parse_config_file "$config_file" "$version" "ARCHITECTURE")

        local has_error=0
        local comments=()

        if [[ -z "$architecture" ]]; then
            has_error=1
            comments+=("Architecture not set")
        fi

        local db_result db_status db_comment
        db_result=$(check_download_target_availability "$db_url" "DB package")
        db_status="${db_result%%|*}"
        db_comment="${db_result#*|}"
        if [[ "$db_status" != "ok" ]]; then
            has_error=1
            comments+=("$db_comment")
        fi

        local c4_result c4_status c4_comment
        c4_result=$(check_download_target_availability "$c4_url" "c4 binary")
        c4_status="${c4_result%%|*}"
        c4_comment="${c4_result#*|}"
        if [[ "$c4_status" != "ok" ]]; then
            has_error=1
            comments+=("$c4_comment")
        fi

        local marker="[+]"
        if [[ $has_error -ne 0 ]]; then
            marker="[x]"
        fi

        local suffix=""
        if [[ "$version" == "$default_version" ]]; then
            suffix=" (default)"
        fi

        local arch_display
        arch_display="$architecture"
        if [[ -z "$arch_display" ]]; then
            arch_display="unknown"
        fi

        local comment_text=""
        if [[ ${#comments[@]} -gt 0 ]]; then
            comment_text=$(IFS='; '; echo "${comments[*]}")
            comment_text=" - $comment_text"
        fi

        log_info "  $marker $version [$arch_display]$suffix$comment_text"
    done <<< "$versions"
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
