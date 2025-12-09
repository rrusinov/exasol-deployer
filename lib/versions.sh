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

# Help for update-versions command
show_update_versions_help() {
    cat <<'EOF'
Discover and append the latest Exasol/C4 versions to versions.conf.

Usage:
  exasol update-versions

Behavior:
  - Uses the highest non-local version in versions.conf as the baseline.
  - Probes newer versions by incrementing:
      * Patch:   +1 … +10
      * Minor:   +1 … +5
      * Major:   +1 … +3
  - The same probing logic is applied separately to the C4 version.
  - The first reachable newest DB and C4 versions are downloaded to /var/tmp
    to compute SHA256 checksums.
  - A single new version entry is appended to versions.conf with the resolved
    URLs and checksums.

Notes:
  - Local (-local) and dev versions are ignored as baselines.
  - Requires curl and sha256sum; network access must be available to reach
    the release URLs.
EOF
}

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
    # Intentionally combine local+assignment to prevent set -e exit on command substitution failure
    # shellcheck disable=SC2155
    local config_file=$(get_versions_config_path)

    if [[ ! -f "$config_file" ]]; then
        die "Versions config file not found: $config_file"
    fi

    get_config_sections "$config_file" | grep -v "^default"
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
            echo "ok|$label available"
            return 0
        fi

        echo "missing|$label not found"
        return 1
    fi

    if ! command_exists curl; then
        echo "unknown|Cannot check $label URL (curl not installed)"
        return 1
    fi

    if curl --head --silent --fail --location --max-time 10 "$url" >/dev/null 2>&1; then
        echo "ok|$label available"
        return 0
    fi

    echo "missing|$label not reachable"
    return 1
}

list_versions_with_availability() {
    # Intentionally combine local+assignment to prevent set -e exit on command substitution failure
    # shellcheck disable=SC2155
    local config_file=$(get_versions_config_path)

    if [[ ! -f "$config_file" ]]; then
        die "Versions config file not found: $config_file"
    fi

    # Intentionally combine local+assignment to prevent set -e exit on command substitution failure
    # shellcheck disable=SC2155
    local default_version=$(get_default_version)
    
    # Intentionally combine local+assignment to prevent set -e exit on command substitution failure
    # shellcheck disable=SC2155
    local default_local_version=$(parse_config_file "$config_file" "default-local" "VERSION")

    # Intentionally combine local+assignment to prevent set -e exit on command substitution failure
    # shellcheck disable=SC2155
    local versions=$(get_config_sections "$config_file" | grep -v "^default")

    if [[ -z "$versions" ]]; then
        log_info "  (no versions configured)"
        return 0
    fi

    while IFS= read -r version; do
        [[ -z "$version" ]] && continue

        # Intentionally combine local+assignment to prevent set -e exit on command substitution failure
        # shellcheck disable=SC2155
        local db_url=$(parse_config_file "$config_file" "$version" "DB_DOWNLOAD_URL")
        # shellcheck disable=SC2155
        local c4_url=$(parse_config_file "$config_file" "$version" "C4_DOWNLOAD_URL")
        # shellcheck disable=SC2155
        local architecture=$(parse_config_file "$config_file" "$version" "ARCHITECTURE")

        local has_error=0
        local comments=()

        if [[ -z "$architecture" ]]; then
            has_error=1
            comments+=("Architecture not set")
        fi

        # Intentionally combine local+assignment to prevent set -e exit on command substitution failure
        # shellcheck disable=SC2155
        local db_result=$(check_download_target_availability "$db_url" "DB package")
        db_status="${db_result%%|*}"
        db_comment="${db_result#*|}"
        if [[ "$db_status" != "ok" ]]; then
            has_error=1
            comments+=("$db_comment")
        fi

        # Intentionally combine local+assignment to prevent set -e exit on command substitution failure
        # shellcheck disable=SC2155
        local c4_result=$(check_download_target_availability "$c4_url" "c4 binary")
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
        elif [[ -n "$default_local_version" && "$version" == "$default_local_version" ]]; then
            suffix=" (default-local)"
        fi

        local arch_display="$architecture"
        if [[ -z "$arch_display" ]]; then
            arch_display="unknown"
        fi

        local comment_text=""
        if [[ ${#comments[@]} -gt 0 ]]; then
            comment_text=$(printf ", %s" "${comments[@]}")
            comment_text=" (${comment_text:2})"
        fi

        log_info "  $marker $version [$arch_display]$suffix$comment_text"
    done <<< "$versions"
}

# Get default version
get_default_version() {
    # Intentionally combine local+assignment to prevent set -e exit on command substitution failure
    # shellcheck disable=SC2155
    local config_file=$(get_versions_config_path)

    parse_config_file "$config_file" "default" "VERSION"
}

# Resolve version alias to actual version name
resolve_version_alias() {
    local version="$1"
    
    # If version starts with "default", resolve it
    if [[ "$version" =~ ^default ]]; then
        # Intentionally combine local+assignment to prevent set -e exit on command substitution failure
        # shellcheck disable=SC2155
        local config_file=$(get_versions_config_path)
        
        # Check if this alias exists in config
        if get_config_sections "$config_file" | grep -q "^${version}$"; then
            # Get the actual version from the alias section
            local resolved
            resolved=$(parse_config_file "$config_file" "$version" "VERSION")
            if [[ -n "$resolved" ]]; then
                echo "$resolved"
                return 0
            fi
        fi
    fi
    
    # Not an alias or couldn't resolve, return as-is
    echo "$version"
}

# Check if version exists
version_exists() {
    local version="$1"
    # Intentionally combine local+assignment to prevent set -e exit on command substitution failure
    # shellcheck disable=SC2155
    local config_file=$(get_versions_config_path)

    get_config_sections "$config_file" | grep -q "^${version}$"
}

# Get version configuration value
get_version_config() {
    local version="$1"
    local key="$2"

    # Intentionally combine local+assignment to prevent set -e exit on command substitution failure
    # shellcheck disable=SC2155
    local config_file=$(get_versions_config_path)

    if ! version_exists "$version"; then
        log_error "Version not found: $version"
        return 1
    fi

    parse_config_file "$config_file" "$version" "$key"
}

parse_version_components() {
    local version="$1"
    if [[ "$version" =~ ^[a-zA-Z]+-([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
        return 0
    fi
    return 1
}

# Compare two semantic versions (X Y Z); returns 0 if v1 > v2, 1 otherwise
version_greater() {
    local a_major="$1" a_minor="$2" a_patch="$3"
    local b_major="$4" b_minor="$5" b_patch="$6"
    if (( a_major > b_major )); then return 0; fi
    if (( a_major < b_major )); then return 1; fi
    if (( a_minor > b_minor )); then return 0; fi
    if (( a_minor < b_minor )); then return 1; fi
    if (( a_patch > b_patch )); then return 0; fi
    return 1
}

find_highest_non_local_version() {
    local config_file
    config_file=$(get_versions_config_path)
    local best_version="" best_major=0 best_minor=0 best_patch=0
    while IFS= read -r section; do
        [[ -z "$section" ]] && continue
        [[ "$section" == default* ]] && continue
        [[ "$section" == *-local ]] && continue
        # Skip dev builds
        if [[ "$section" =~ dev ]]; then
            continue
        fi
        local comps
        if comps=$(parse_version_components "$section"); then
            read -r major minor patch <<<"$comps"
            if [[ -z "$best_version" ]] || version_greater "$major" "$minor" "$patch" "$best_major" "$best_minor" "$best_patch"; then
                best_version="$section"
                best_major=$major
                best_minor=$minor
                best_patch=$patch
            fi
        fi
    done < <(get_config_sections "$config_file")

    if [[ -z "$best_version" ]]; then
        die "No suitable non-local version found in $config_file"
    fi

    echo "$best_version|$best_major|$best_minor|$best_patch"
}

build_url_for_version() {
    local template_url="$1"
    local old_version="$2"
    local new_version="$3"
    local updated
    updated="${template_url//$old_version/$new_version}"

    # Also replace the numeric version segment if it appears elsewhere in the URL path
    local old_numeric new_numeric
    old_numeric="${old_version#*-}"
    old_numeric="${old_numeric%%-*}"
    new_numeric="${new_version#*-}"
    new_numeric="${new_numeric%%-*}"

    if [[ -n "$old_numeric" && -n "$new_numeric" && "$old_numeric" != "$new_numeric" ]]; then
        updated="${updated//$old_numeric/$new_numeric}"
    fi

    echo "$updated"
}

probe_version_url() {
    local url="$1"
    if curl --head --silent --fail --location --max-time 10 "$url" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

discover_latest_version() {
    local base_version="$1"
    local start_major="$2"
    local start_minor="$3"
    local start_patch="$4"
    local template_url="$5"
    local label="${6:-version}"

    local best_major="$start_major"
    local best_minor="$start_minor"
    local best_patch="$start_patch"

    # Split base_version into prefix + numeric core + suffix (e.g., exasol- + 2025.1.8 + -arm64)
    local base_prefix=""
    local base_core=""
    local base_suffix=""
    if [[ "$base_version" =~ ^([a-zA-Z0-9_-]*-)?([0-9]+\.[0-9]+\.[0-9]+)(.*)$ ]]; then
        base_prefix="${BASH_REMATCH[1]}"
        base_core="${BASH_REMATCH[2]}"
        base_suffix="${BASH_REMATCH[3]}"
    else
        die "Unsupported version format for update-versions: $base_version"
    fi

    local major_offset minor_offset patch_offset
    local probe_idx=0
    local found_new=0
    local stop_search=0

    for major_offset in {0..3}; do
        local major=$((start_major + major_offset))
        local minor_start=$start_minor
        # When bumping major, start probing at the current minor to avoid imaginary 0.x if it doesn't exist
        if (( major_offset > 0 )); then
            minor_start=$start_minor
        fi

        for minor_offset in $(seq 0 5); do
            local minor=$((minor_start + minor_offset))
            local patch_start=$start_patch
            if (( major_offset > 0 || minor_offset > 0 )); then
                patch_start=0
            fi

            local break_minor=0

            for patch_offset in $(seq 0 10); do
                local patch=$((patch_start + patch_offset))
                probe_idx=$((probe_idx + 1))
                local candidate="${base_prefix}${major}.${minor}.${patch}${base_suffix}"
                local candidate_url
                candidate_url=$(build_url_for_version "$template_url" "$base_version" "$candidate")

                if probe_version_url "$candidate_url"; then
                    best_major=$major
                    best_minor=$minor
                    best_patch=$patch
                    found_new=1
                    log_info "[update-versions][$label] Probe #$probe_idx: $candidate (reachable)"
                    log_debug "[update-versions][$label]   URL: $candidate_url"
                else
                    log_info "[update-versions][$label] Probe #$probe_idx: $candidate (unreachable)"
                    log_debug "[update-versions][$label]   URL: $candidate_url"
                    if (( patch_offset == 0 )) && (( major_offset > 0 || minor_offset > 0 )); then
                        log_info "[update-versions][$label] First candidate for this increment missing ($candidate); stopping this increment range."
                        log_debug "[update-versions][$label]   URL: $candidate_url"
                        break_minor=1
                        break
                    fi
                fi
            done

            if (( break_minor == 1 )); then
                # If we just bumped major and the first minor candidate is missing, stop searching entirely
                if (( major_offset > 0 )); then
                    log_info "[update-versions][$label] First candidate for new major $major missing; stopping search."
                    stop_search=1
                fi
                break
            fi
        done

        if (( stop_search == 1 )); then
            break
        fi
    done

    local latest="${base_prefix}${best_major}.${best_minor}.${best_patch}${base_suffix}"

    if (( found_new == 0 )) && [[ "$latest" == "$base_version" ]]; then
        log_info "[update-versions][$label] No newer version found; keeping baseline $base_version"
    fi

    echo "$latest"
}

download_and_checksum() {
    local url="$1"
    local dest_dir="/var/tmp"
    local filename
    filename="$(basename "$url")"
    local dest_path="$dest_dir/$filename"

    curl --fail --location --silent --show-error --output "$dest_path" "$url"
    local checksum
    checksum=$(sha256sum "$dest_path" | awk '{print $1}')
    echo "$checksum|$dest_path"
}

build_version_entry() {
    local version_name="$1"
    local architecture="$2"
    local db_version_field="$3"
    local db_url="$4"
    local db_checksum="$5"
    local c4_version="$6"
    local c4_url="$7"
    local c4_checksum="$8"

    cat <<EOF
[${version_name}]
ARCHITECTURE=$architecture
DB_VERSION=$db_version_field
DB_DOWNLOAD_URL=$db_url
DB_CHECKSUM=sha256:$db_checksum
C4_VERSION=$c4_version
C4_DOWNLOAD_URL=$c4_url
C4_CHECKSUM=sha256:$c4_checksum
EOF
}

insert_entries_at_top() {
    local config_file="$1"
    local entries="$2"

    local tmp
    tmp=$(mktemp)

    local first_section
    first_section=$(grep -n '^\[' "$config_file" | head -n1 | cut -d: -f1 || true)

    if [[ -z "$first_section" ]]; then
        {
            printf "%s\n\n" "$entries"
        } >"$tmp"
    else
        {
            if (( first_section > 1 )); then
                head -n $((first_section - 1)) "$config_file"
            fi
            printf "%s\n\n" "$entries"
            tail -n +"$first_section" "$config_file"
        } >"$tmp"
    fi

    mv "$tmp" "$config_file"
}

update_default_sections() {
    local config_file="$1"
    local default_version="$2"
    local default_local_version="$3"

    local tmp
    tmp=$(mktemp)

    awk -v nd="$default_version" -v nl="$default_local_version" '
        BEGIN{section="";found_d=0;found_l=0}
        /^\[default\]/{section="default"; print; next}
        /^\[default-local\]/{section="default-local"; print; next}
        /^\[/{section=""}
        {
            if(section=="default" && $0 ~ /^VERSION=/){
                print "VERSION=" nd
                found_d=1
                next
            }
            if(section=="default-local" && $0 ~ /^VERSION=/){
                print "VERSION=" nl
                found_l=1
                next
            }
        }
        {print}
        END{
            if(found_d==0){
                print ""
                print "[default]"
                print "VERSION=" nd
            }
            if(found_l==0){
                print ""
                print "[default-local]"
                print "VERSION=" nl
            }
        }
    ' "$config_file" > "$tmp"

    mv "$tmp" "$config_file"
}

cmd_update_versions() {
    if ! command_exists curl; then
        die "curl is required for update-versions"
    fi
    if ! command_exists sha256sum; then
        die "sha256sum is required for update-versions"
    fi

    local config_file
    config_file=$(get_versions_config_path)
    local baseline
    baseline=$(find_highest_non_local_version)
    IFS="|" read -r base_version base_major base_minor base_patch <<<"$baseline"

    local architecture
    architecture=$(parse_config_file "$config_file" "$base_version" "ARCHITECTURE")
    local db_url_template
    db_url_template=$(parse_config_file "$config_file" "$base_version" "DB_DOWNLOAD_URL")
    local c4_url_template
    c4_url_template=$(parse_config_file "$config_file" "$base_version" "C4_DOWNLOAD_URL")
    local c4_version_base
    c4_version_base=$(parse_config_file "$config_file" "$base_version" "C4_VERSION")

    log_info "Baseline version: $base_version ($architecture)"

    local latest_db
    latest_db=$(discover_latest_version "$base_version" "$base_major" "$base_minor" "$base_patch" "$db_url_template" "db")
    local c4_major c4_minor c4_patch
    if ! [[ "$c4_version_base" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        die "C4_VERSION is not numeric (cannot probe): $c4_version_base"
    fi
    c4_major=${BASH_REMATCH[1]}
    c4_minor=${BASH_REMATCH[2]}
    c4_patch=${BASH_REMATCH[3]}
    local latest_c4
    latest_c4=$(discover_latest_version "$c4_version_base" "$c4_major" "$c4_minor" "$c4_patch" "$c4_url_template" "c4")

    if [[ "$latest_db" == "$base_version" && "$latest_c4" == "$c4_version_base" ]]; then
        log_info "No newer DB or C4 versions found."
        return 0
    fi

    log_info "Latest DB: $latest_db"
    log_info "Latest C4: $latest_c4"

    local db_url
    db_url=$(build_url_for_version "$db_url_template" "$base_version" "$latest_db")
    local c4_url
    c4_url=$(build_url_for_version "$c4_url_template" "$c4_version_base" "$latest_c4")

    log_info "Downloading DB package to compute checksum..."
    local db_checksum_info
    db_checksum_info=$(download_and_checksum "$db_url")
    local db_checksum db_path
    IFS="|" read -r db_checksum db_path <<<"$db_checksum_info"
    log_info "DB downloaded to $db_path"

    log_info "Downloading C4 binary to compute checksum..."
    local c4_checksum_info
    c4_checksum_info=$(download_and_checksum "$c4_url")
    local c4_checksum c4_path
    IFS="|" read -r c4_checksum c4_path <<<"$c4_checksum_info"
    log_info "C4 downloaded to $c4_path"

    local db_version_field="@${latest_db}"
    if [[ "$architecture" == "arm64" ]]; then
        db_version_field="@${latest_db}~linux-arm64"
    fi

    local new_version_entry
    new_version_entry=$(build_version_entry "$latest_db" "$architecture" "$db_version_field" "$db_url" "$db_checksum" "$latest_c4" "$c4_url" "$c4_checksum")

    local local_version="${latest_db}-local"
    local local_db_url="file://$db_path"
    local local_c4_url="file://$c4_path"
    local local_entry
    local_entry=$(build_version_entry "$local_version" "$architecture" "$db_version_field" "$local_db_url" "$db_checksum" "$latest_c4" "$local_c4_url" "$c4_checksum")

    local entries
    entries="$new_version_entry"$'\n\n'"$local_entry"

    insert_entries_at_top "$config_file" "$entries"
    update_default_sections "$config_file" "$latest_db" "$local_version"

    log_info "Inserted new version $latest_db (and local variant) at top of $config_file"
    log_info "Updated default -> $latest_db, default-local -> $local_version"
}
# Validate version format
validate_version_format() {
    local version="$1"

    # Allow alias formats (default, default-local, default-arm64, etc.)
    if [[ "$version" =~ ^default(-[a-z0-9]+)?$ ]]; then
        return 0
    fi

    # Expected formats:
    # - name-X.Y.Z (e.g., exasol-2025.1.8) - default x86_64
    # - name-X.Y.Z-arm64 (e.g., exasol-2025.1.8-arm64) - ARM64 variant
    # - name-X.Y.Z-local (e.g., exasol-2025.1.8-local) - local variant
    # - name-X.Y.Z-arm64-local (e.g., exasol-2025.1.8-arm64-local) - local ARM64
    # - name-X.Y.Z-arm64dev.N (e.g., exasol-2025.2.0-arm64dev.0) - dev versions
    if [[ ! "$version" =~ ^[a-z]+-[0-9]+\.[0-9]+\.[0-9]+(-arm64(dev\.[0-9]+)?)?(-local)?$ ]]; then
        log_error "Invalid version format: $version"
        log_error "Expected format: name-X.Y.Z[-arm64][-local]"
        log_error "Examples:"
        log_error "  - exasol-2025.1.8 (x86_64, default)"
        log_error "  - exasol-2025.1.8-arm64 (ARM64 variant)"
        log_error "  - exasol-2025.1.8-local (local x86_64 variant)"
        log_error "  - exasol-2025.1.8-arm64-local (local ARM64 variant)"
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

    # Intentionally combine local+assignment to prevent set -e exit on command substitution failure
    # shellcheck disable=SC2155
    local config_file=$(get_instance_types_config_path)

    if [[ ! -f "$config_file" ]]; then
        log_error "Instance types config file not found: $config_file"
        return 1
    fi

    parse_config_file "$config_file" "$provider" "$architecture"
}
