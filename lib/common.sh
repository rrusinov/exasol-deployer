#!/usr/bin/env bash
# Common functions and utilities for Exasol deployer

# Include guard
if [[ -n "${__EXASOL_COMMON_SH_INCLUDED__:-}" ]]; then
    return 0
fi
readonly __EXASOL_COMMON_SH_INCLUDED__=1

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

# Current log level (default: INFO)
CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO}

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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check required commands
check_required_commands() {
    local missing_commands=()

    if ! command_exists tofu; then
        missing_commands+=("tofu (OpenTofu)")
    fi

    if ! command_exists ansible-playbook; then
        missing_commands+=("ansible-playbook")
    fi

    if ! command_exists jq; then
        missing_commands+=("jq")
    fi

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands:"
        for cmd in "${missing_commands[@]}"; do
            log_error "  - $cmd"
        done
        die "Please install missing dependencies and try again."
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
    # Use head first to avoid SIGPIPE with set -o pipefail
    head -c 100 < /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c "$length"
}

# JSON escape string
json_escape() {
    local string="$1"
    printf '%s' "$string" | jq -Rs .
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
