#!/usr/bin/env bash
# Common functions and utilities for Exasol deployer

# Include guard
if [[ -n "${__EXASOL_COMMON_SH_INCLUDED__:-}" ]]; then
    return 0
fi
readonly __EXASOL_COMMON_SH_INCLUDED__=1

# Get default region/location for a provider from instance-types.conf
get_instance_type_region_default() {
    local provider="$1"
    local key="${2:-region}"
    local config_file
    config_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)/instance-types.conf"
    local section=""
    local in_section=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line%%;*}"
        line="${line//[$'\t\r\n ']}" # trim whitespace
        if [[ -z "$line" ]]; then continue; fi
        if [[ "$line" =~ ^\[(.*)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            in_section=0
            if [[ "$section" == "$provider" ]]; then
                in_section=1
            fi
            continue
        fi
        if [[ $in_section -eq 1 && "$line" =~ ^$key= ]]; then
            echo "${line#*=}"
            return 0
        fi
    done < "$config_file"
    echo ""
}

# Source progress tracking utilities
_COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./progress_tracker.sh
if [[ -f "${_COMMON_LIB_DIR}/progress_tracker.sh" ]]; then
    source "${_COMMON_LIB_DIR}/progress_tracker.sh"
fi

# Colors for output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_RESET='\033[0m'

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# Current log level (default: INFO, can be overridden via EXASOL_LOG_LEVEL env)
case "${EXASOL_LOG_LEVEL:-}" in
    debug|DEBUG|0) CURRENT_LOG_LEVEL=${LOG_LEVEL_DEBUG} ;;
    info|INFO|1) CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO} ;;
    warn|WARN|warning|WARNING|2) CURRENT_LOG_LEVEL=${LOG_LEVEL_WARN} ;;
    error|ERROR|3) CURRENT_LOG_LEVEL=${LOG_LEVEL_ERROR} ;;
    *) CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO} ;;
esac

# Progress system: keyword-based step tracking (no calibration or ETA)

# ==============================================================================
# TEMP FILE HELPERS
# ==============================================================================

# Determine runtime temp directory (per deployment when possible)
get_runtime_temp_dir() {
    local base_dir
    if [[ -n "${EXASOL_DEPLOY_DIR:-}" ]]; then
        base_dir="$EXASOL_DEPLOY_DIR"
    else
        base_dir="/tmp/exasol-deployer"
    fi

    local tmp_dir="$base_dir/.tmp"
    mkdir -p "$tmp_dir" 2>/dev/null || true
    echo "$tmp_dir"
}

# Build a temp file path for the current process
get_runtime_temp_file() {
    local name="${1:-temp}"
    local tmp_dir
    tmp_dir=$(get_runtime_temp_dir)
    echo "$tmp_dir/${name}_$$"
}

# Set log level from string
set_log_level() {
    local level="$1"
    case "$level" in
        debug) CURRENT_LOG_LEVEL=${LOG_LEVEL_DEBUG} ;;
        info)  CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO} ;;
        warn)  CURRENT_LOG_LEVEL=${LOG_LEVEL_WARN} ;;
        error) CURRENT_LOG_LEVEL=${LOG_LEVEL_ERROR} ;;
        *)     CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO} ;;
    esac
}

# Logging functions
log_debug() {
    if [[ ${CURRENT_LOG_LEVEL} -le ${LOG_LEVEL_DEBUG} ]]; then
        echo -e "${COLOR_BLUE}[DEBUG]${COLOR_RESET} $*" >&2
    fi
}

log_info() {
    if [[ ${CURRENT_LOG_LEVEL} -le ${LOG_LEVEL_INFO} ]]; then
        echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $*" >&2
    fi
}

log_warn() {
    if [[ ${CURRENT_LOG_LEVEL} -le ${LOG_LEVEL_WARN} ]]; then
        echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*" >&2
    fi
}

log_error() {
    if [[ ${CURRENT_LOG_LEVEL} -le ${LOG_LEVEL_ERROR} ]]; then
        echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
    fi
}

# Fatal error - log and exit
die() {
    log_error "$*"
    exit 1
}

# ==============================================================================
# OPENTofu/Terraform plugin cache setup
# ==============================================================================

setup_plugin_cache() {
    local cache_dir="${TF_PLUGIN_CACHE_DIR:-${HOME}/.cache/exasol-tofu-plugins}"
    export TF_PLUGIN_CACHE_DIR="$cache_dir"

    if [[ ! -d "$cache_dir" ]]; then
        mkdir -p "$cache_dir" 2>/dev/null || true
    fi

    # Create rc files if missing so Terraform/OpenTofu know about the cache
    for rc_file in "${HOME}/.tofurc" "${HOME}/.terraformrc"; do
        if [[ ! -f "$rc_file" ]]; then
            cat > "$rc_file" <<EOF
plugin_cache_dir = "${cache_dir}"
EOF
            log_debug "Created provider cache config: $rc_file -> $cache_dir"
        fi
    done
}

# Initialize provider cache on load so all commands share it
setup_plugin_cache

log_plugin_cache_dir() {
    log_info "Using provider cache directory: ${TF_PLUGIN_CACHE_DIR}"
}

# Registry client retry defaults (honor user overrides)
setup_registry_retries() {
    if [[ -z "${TF_REGISTRY_CLIENT_RETRY_MAX:-}" ]]; then
        export TF_REGISTRY_CLIENT_RETRY_MAX=6
    fi
    if [[ -z "${TF_REGISTRY_CLIENT_TIMEOUT:-}" ]]; then
        export TF_REGISTRY_CLIENT_TIMEOUT=30
    fi
}

# Initialize registry retry defaults
setup_registry_retries

# ==============================================================================
# OPERATION GUARD
# ==============================================================================
# Sets a trap that marks the operation as failed (state) and removes lock unless
# a success variable is set to "true" by the caller before exit.
# Usage: setup_operation_guard <deploy_dir> <fail_status> <success_var_name>
# The success variable must be declared in the caller's scope.

# Global variables for trap cleanup (set by setup_operation_guard)
_OPERATION_GUARD_DEPLOY_DIR=""
_OPERATION_GUARD_FAIL_STATUS=""
_OPERATION_GUARD_SUCCESS="false"

# Cleanup function called by trap
cleanup_operation_guard() {
    if [[ "$_OPERATION_GUARD_SUCCESS" != "true" ]]; then
        state_set_status "$_OPERATION_GUARD_DEPLOY_DIR" "$_OPERATION_GUARD_FAIL_STATUS"
    fi
    lock_remove "$_OPERATION_GUARD_DEPLOY_DIR"
}

setup_operation_guard() {
    local deploy_dir="$1"
    local fail_status="$2"
    # shellcheck disable=SC2034
    local success_var_name="$3"  # Kept for compatibility but not used

    # Set global variables for the cleanup function
    _OPERATION_GUARD_DEPLOY_DIR="$deploy_dir"
    _OPERATION_GUARD_FAIL_STATUS="$fail_status"
    _OPERATION_GUARD_SUCCESS="false"

    # Set trap to call the cleanup function
    trap 'cleanup_operation_guard' EXIT INT TERM
}

# Function to mark operation as successful
operation_success() {
    _OPERATION_GUARD_SUCCESS="true"
}

# ==============================================================================
# HELPER FUNCTIONS FOR TESTS
# ==============================================================================

# Extract total resources from a Terraform/Tofu plan summary line
extract_plan_total_resources() {
    local line="$1"

    if [[ ! "$line" =~ ^Plan: ]]; then
        return 1
    fi

    local add=0
    local change=0
    local destroy=0

    if [[ "$line" =~ ([0-9]+)\ to\ add ]]; then
        add=${BASH_REMATCH[1]}
    fi
    if [[ "$line" =~ ([0-9]+)\ to\ change ]]; then
        change=${BASH_REMATCH[1]}
    fi
    if [[ "$line" =~ ([0-9]+)\ to\ destroy ]]; then
        destroy=${BASH_REMATCH[1]}
    fi

    echo $((add + change + destroy))
}

# Categorize Ansible tasks into phases for more informative progress output
categorize_ansible_phase() {
    local task_name="$1"
    local lower_task
    lower_task=$(printf '%s' "$task_name" | tr '[:upper:]' '[:lower:]')

    if [[ "$lower_task" =~ (download|fetch|get|transfer|artifact|tarball) ]]; then
        echo "download"
    elif [[ "$lower_task" =~ (install|configure|setup|enable|start|service|systemd|extract|untar|unpack|symlink|directory) ]]; then
        echo "install"
    else
        echo "prepare"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check required commands
check_required_commands() {
    local missing_commands=()
    local version_issues=()

    # Check bash version (>= 4.0)
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        version_issues+=("bash (version ${BASH_VERSION} too old, need >= 4.0)")
    fi

    # Check essential tools
    if ! command_exists tofu; then
        missing_commands+=("tofu (OpenTofu)")
    fi

    if ! command_exists ansible-playbook; then
        missing_commands+=("ansible-playbook")
    fi

    if ! command_exists jq; then
        missing_commands+=("jq")
    fi

    # Check standard Unix tools
    local required_tools=("grep" "sed" "awk" "sort" "uniq" "curl" "ssh" "cat" "dirname" "basename" "mktemp" "date" "find" "tr" "cut" "wc")
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_commands+=("$tool")
        fi
    done

    # Check for GNU date (BSD date doesn't support date +%s reliably in older versions)
    if command_exists date; then
        if ! date +%s >/dev/null 2>&1; then
            version_issues+=("date (command 'date +%s' failed, may need GNU date)")
        fi
    fi

    # Check for mktemp with -d support
    if command_exists mktemp; then
        local mktemp_dir
        if ! mktemp_dir=$(mktemp -d -t "exasol-test-XXXXXX" 2>/dev/null); then
            version_issues+=("mktemp (mktemp -d failed, ensure GNU coreutils is installed)")
        else
            rm -rf "$mktemp_dir"
        fi
    fi

    # Report errors
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands:"
        for cmd in "${missing_commands[@]}"; do
            log_error "  - $cmd"
        done
    fi

    if [[ ${#version_issues[@]} -gt 0 ]]; then
        log_error "Incompatible tool versions detected:"
        for issue in "${version_issues[@]}"; do
            log_error "  - $issue"
        done
        log_error ""
        log_error "This tool requires GNU versions of standard utilities."
        log_error "On macOS, install GNU tools via Homebrew:"
        log_error "  brew install coreutils findutils gnu-sed gawk grep bash"
        log_error "  # Add to PATH: export PATH=\"/usr/local/opt/coreutils/libexec/gnubin:\$PATH\""
    fi

    if [[ ${#missing_commands[@]} -gt 0 ]] || [[ ${#version_issues[@]} -gt 0 ]]; then
        die "Please install missing dependencies and try again."
    fi
}

# Check provider-specific required commands
check_provider_requirements() {
    local provider="$1"
    local missing_commands=()
    local warnings=()



    case "$provider" in
        libvirt)
            if ! command_exists virsh; then
                missing_commands+=("virsh (libvirt-client)")
            fi
            if ! command_exists mkisofs && ! command_exists genisoimage; then
                missing_commands+=("mkisofs/genisoimage (install genisoimage package or 'brew install cdrtools' on macOS)")
            fi

            # Check for qemu.conf dynamic_ownership setting
            local qemu_conf="/etc/libvirt/qemu.conf"
            if [[ -f "$qemu_conf" ]] && [[ -r "$qemu_conf" ]]; then
                # Check if dynamic_ownership is explicitly set to 0
                if grep -qE "^dynamic_ownership\s*=\s*0" "$qemu_conf" 2>/dev/null; then
                    warnings+=("dynamic_ownership is disabled in $qemu_conf")
                    warnings+=("This may cause 'Permission denied' errors when creating VMs")
                    warnings+=("See clouds/CLOUD_SETUP_LIBVIRT.md for troubleshooting")
                fi
            fi

            # Check for AppArmor enforcement on libvirt
            if command_exists aa-status; then
                if sudo aa-status 2>/dev/null | grep -q "libvirtd$"; then
                    # libvirtd is in enforce mode
                    warnings+=("AppArmor is enforcing libvirtd profile")
                    warnings+=("This may block QEMU from accessing base images (Permission denied)")
                    warnings+=("Recommended: Run 'sudo aa-complain /usr/sbin/libvirtd' for development")
                    warnings+=("See clouds/CLOUD_SETUP_LIBVIRT.md for details")
                fi
            fi
            ;;
    esac

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands for provider '$provider':"
        for cmd in "${missing_commands[@]}"; do
            log_error "  - $cmd"
        done
        log_error ""
        log_error "For libvirt/KVM setup instructions, see:"
        log_error "  clouds/CLOUD_SETUP_LIBVIRT.md"
        die "Please install missing dependencies and try again."
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        log_warn "Potential configuration issues detected for provider '$provider':"
        for warning in "${warnings[@]}"; do
            log_warn "  - $warning"
        done
        log_warn ""
    fi
}

# Parse INI-style config file
parse_config_file() {
    local config_file="$1"
    local section="$2"
    local key="$3"

    if [[ ! -f "$config_file" ]]; then
        return 1
    fi

    awk -F= -v section="[$section]" -v key="$key" '
        $0 == section { in_section=1; next }
        /^\[/ { in_section=0 }
        in_section && $1 == key { print $2; exit }
    ' "$config_file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Get all sections from INI file
get_config_sections() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        return 1
    fi

    grep '^\[' "$config_file" | sed 's/^\[\(.*\)\]$/\1/'
}

# Validate directory path
validate_directory() {
    local dir="$1"

    if [[ -z "$dir" ]]; then
        die "Directory path cannot be empty"
    fi

    # Convert to absolute path
    if [[ ! "$dir" = /* ]]; then
        dir="$(pwd)/$dir"
    fi

    # Normalize any ./ or // sequences to keep test patterns predictable
    dir=${dir//\/.\//\/}
    dir=${dir//\/\//\/}

    echo "$dir"
}

# Create directory if it doesn't exist
ensure_directory() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || die "Failed to create directory: $dir"
    fi
}

# Generate random password
generate_password() {
    local length="${1:-16}"
    # Generate more characters than needed and take exactly what we want
    # This ensures we always get the requested length even if tr processes fewer chars
    local password
    password=$(head -c 200 < /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')
    # Take exactly the requested length
    echo "${password:0:$length}"
}

# Check if directory is a valid deployment directory
is_deployment_directory() {
    local dir="$1"

    [[ -f "$dir/.exasol.json" ]]
}

# Get timestamp in ISO 8601 format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Generate INFO.txt file for deployment directory

generate_info_files() {
    local deploy_dir="$1"
    local normalized_dir
    normalized_dir="$(cd "$deploy_dir" && pwd)" || die "Failed to normalize deployment directory: $deploy_dir"
    local info_txt_file="$deploy_dir/INFO.txt"

    local cd_cmd="cd $normalized_dir"
    local status_cmd="exasol status --show-details"
    local deploy_cmd="exasol deploy"
    local destroy_cmd="exasol destroy"
    local tofu_cmd="tofu output"

    cat > "$info_txt_file" <<EOF
Exasol Deployment Entry Point
============================

Deployment Directory: $normalized_dir

Essential Commands:
- Change to the deployment directory:
        $cd_cmd
- Check status:
        $status_cmd
- Deploy infrastructure:
        $deploy_cmd
- Destroy infrastructure:
        $destroy_cmd
- Terraform outputs:
        $tofu_cmd

Important Files:
- .exasol.json          (deployment state - do not edit)
- variables.auto.tfvars (configuration parameters)
- .credentials.json     (passwords - keep secure)
- ssh_config            (SSH access)
- inventory.ini         (Ansible inventory)
- README.md             (deployment instructions)

Notes:
- INFO.txt is a static entry point generated during initialization.
- Run the commands above inside the deployment directory for live updates.
- Review configuration and credentials using the files referenced here.
EOF
}
