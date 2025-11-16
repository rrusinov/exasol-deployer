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

# Current log level (default: INFO, can be overridden via EXASOL_LOG_LEVEL env)
case "${EXASOL_LOG_LEVEL:-}" in
    debug|DEBUG|0) CURRENT_LOG_LEVEL=${LOG_LEVEL_DEBUG} ;;
    info|INFO|1) CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO} ;;
    warn|WARN|warning|WARNING|2) CURRENT_LOG_LEVEL=${LOG_LEVEL_WARN} ;;
    error|ERROR|3) CURRENT_LOG_LEVEL=${LOG_LEVEL_ERROR} ;;
    *) CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO} ;;
esac

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
# OPERATION GUARD
# ==============================================================================
# Sets a trap that marks the operation as failed (state) and removes lock unless
# a success variable is set to "true" by the caller before exit.
# Usage: setup_operation_guard <deploy_dir> <fail_status> <success_var_name>
# The success variable must be declared in the caller's scope.
setup_operation_guard() {
    local deploy_dir="$1"
    local fail_status="$2"
    local success_var_name="$3"

    # Use indirect expansion in the trap to read success_var_name at exit time
    trap '
        if [[ ${'"${success_var_name}"':-false} != "true" ]]; then
            state_set_status "'"$deploy_dir"'" "'"$fail_status"'"
        fi
        lock_remove "'"$deploy_dir"'"
    ' EXIT INT TERM
}

# ==============================================================================
# PROGRESS TRACKING FUNCTIONS
# These functions emit both human-readable and machine-parsable progress info
# ==============================================================================

# Global variable to track the last percentage per stage:step
declare -A _PROGRESS_LAST_PERCENT

# Step weights for overall progress calculation
# Format: stage:step=weight
declare -A _STEP_WEIGHTS=(
    # Deploy stage weights (total: 100)
    ["deploy:begin"]=1
    ["deploy:tofu_init"]=2
    ["deploy:tofu_plan"]=1
    ["deploy:tofu_apply"]=10
    ["deploy:wait_instances"]=5
    ["deploy:ansible_config"]=81
    ["deploy:complete"]=0

    # Destroy stage weights (total: 100)
    ["destroy:begin"]=1
    ["destroy:confirm"]=1
    ["destroy:tofu_destroy"]=97
    ["destroy:cleanup"]=1
    ["destroy:complete"]=0

    # Init stage weights (total: 100)
    ["init:validate_config"]=15
    ["init:create_directories"]=5
    ["init:initialize_state"]=10
    ["init:copy_templates"]=20
    ["init:generate_variables"]=15
    ["init:store_credentials"]=15
    ["init:generate_readme"]=10
    ["init:complete"]=10
)

# Ordered steps per stage so progress never regresses due to hash iteration order
declare -A _STAGE_STEP_ORDER=(
    ["deploy"]="begin tofu_init tofu_plan tofu_apply wait_instances ansible_config complete"
    ["destroy"]="begin confirm tofu_destroy cleanup complete"
    ["init"]="validate_config create_directories initialize_state copy_templates generate_variables store_credentials generate_readme complete"
)

# Get the progress file path for a deployment directory
# If EXASOL_DEPLOY_DIR is set, use it; otherwise no file output
get_progress_file() {
    if [[ -n "${EXASOL_DEPLOY_DIR:-}" ]]; then
        echo "${EXASOL_DEPLOY_DIR}/.exasol-progress.jsonl"
    fi
}

# Calculate overall stage progress based on step completion
# Usage: calculate_overall_progress <stage> <step> <step_percent>
calculate_overall_progress() {
    local stage="$1"
    local current_step="$2"
    local step_percent="${3:-0}"

    local total_completed=0
    local found_current=0
    local ordered_steps="${_STAGE_STEP_ORDER[$stage]:-}"

    # Fallback: build a deterministic order if not explicitly defined
    if [[ -z "$ordered_steps" ]]; then
        local collected_steps=()
        local key
        for key in "${!_STEP_WEIGHTS[@]}"; do
            if [[ "$key" == "${stage}:"* ]]; then
                collected_steps+=("${key#*:}")
            fi
        done
        if [[ ${#collected_steps[@]} -gt 0 ]]; then
            mapfile -t collected_steps < <(printf '%s\n' "${collected_steps[@]}" | sort)
            ordered_steps="${collected_steps[*]}"
        fi
    fi

    if [[ -z "$ordered_steps" ]]; then
        echo "${step_percent:-0}"
        return
    fi

    # Iterate through steps in order and sum up completed weights
    local step_name
    for step_name in $ordered_steps; do
        local weight="${_STEP_WEIGHTS[${stage}:${step_name}]:-0}"

        # If we haven't reached current step yet, count as fully completed
        if [[ "$step_name" == "$current_step" ]]; then
            # This is the current step - add partial completion
            found_current=1
            total_completed=$((total_completed + (weight * step_percent / 100)))
            break
        else
            total_completed=$((total_completed + weight))
        fi
    done

    if [[ "$found_current" -eq 0 ]]; then
        total_completed=100
    fi

    # Return overall percentage (capped at 100)
    if [[ $total_completed -gt 100 ]]; then
        echo "100"
    elif [[ $total_completed -lt 0 ]]; then
        echo "0"
    else
        echo "$total_completed"
    fi
}

# Emit progress information in JSON format (stored in .exasol-progress.jsonl)
# and human-readable messages (stderr).
# Usage: progress_emit <stage> <step> <status> <message> [percent]
progress_emit() {
    local stage="$1"      # e.g., "init", "deploy", "destroy"
    local step="$2"       # e.g., "validating", "creating_network", "deploying_database"
    local status="$3"     # e.g., "started", "in_progress", "completed", "failed"
    local message="$4"    # Human-readable message
    local percent="${5:-}" # Optional: completion percentage (0-100)
    local percent_fragment=""
    if [[ -n "$percent" ]]; then
        percent_fragment=$(printf ',\"percent\":%s' "$percent")
    fi

    # Prevent percentage from jumping backwards
    if [[ -n "$percent" ]]; then
        local key="${stage}:${step}"
        local last_percent="${_PROGRESS_LAST_PERCENT[$key]:-0}"

        # Only update if new percentage is higher or status is completed/failed
        if [[ "$status" == "completed" || "$status" == "failed" ]]; then
            # Always allow completed/failed status
            _PROGRESS_LAST_PERCENT[$key]="$percent"
        elif [[ $percent -lt $last_percent ]]; then
            # Don't emit if percentage would go backwards
            return
        else
            _PROGRESS_LAST_PERCENT[$key]="$percent"
        fi
    fi

    # Calculate overall progress
    local overall_percent
    if [[ "$status" == "completed" ]]; then
        # Step is complete, use 100% for this step
        overall_percent=$(calculate_overall_progress "$stage" "$step" 100)
    else
        # Step in progress, use current percentage
        overall_percent=$(calculate_overall_progress "$stage" "$step" "${percent:-0}")
    fi

    local json_output
    json_output=$(cat <<EOF
{"timestamp":"$(date -u +"%Y-%m-%dT%H:%M:%SZ")","stage":"${stage}","step":"${step}","status":"${status}","message":"${message}"${percent_fragment},"overall_percent":${overall_percent}}
EOF
    )

    # Also write to progress file if deployment directory is set
    local progress_file
    progress_file=$(get_progress_file)
    if [[ -n "$progress_file" ]]; then
        mkdir -p "$(dirname "$progress_file")" 2>/dev/null || true
        echo "$json_output" >> "$progress_file"
    fi

    # Also emit human-readable version to stderr based on status
    case "$status" in
        started)
            log_info "▶ ${message}"
            ;;
        in_progress)
            if [[ -n "$percent" ]]; then
                log_info "⏳ ${message} (${percent}%)"
            else
                log_info "⏳ ${message}"
            fi
            ;;
        completed)
            log_info "✅ ${message}"
            ;;
        failed)
            log_error "❌ ${message}"
            ;;
        *)
            log_info "${message}"
            ;;
    esac
}

# Progress helper: Mark a stage as started
progress_start() {
    local stage="$1"
    local step="$2"
    local message="$3"
    progress_emit "$stage" "$step" "started" "$message"
}

# Progress helper: Mark a stage as in progress (with optional percentage)
progress_update() {
    local stage="$1"
    local step="$2"
    local message="$3"
    local percent="${4:-}"
    progress_emit "$stage" "$step" "in_progress" "$message" "$percent"
}

# Progress helper: Mark a stage as completed
progress_complete() {
    local stage="$1"
    local step="$2"
    local message="$3"
    progress_emit "$stage" "$step" "completed" "$message" 100
}

# Progress helper: Mark a stage as failed
progress_fail() {
    local stage="$1"
    local step="$2"
    local message="$3"
    progress_emit "$stage" "$step" "failed" "$message"
}

# ==============================================================================
# PROGRESS PARSING HELPERS
# These functions parse output from tools and emit progress updates
# ==============================================================================

# Run OpenTofu/Terraform command with progress tracking
# Usage: run_tofu_with_progress <stage> <step> <base_message> <command> [args...]
run_tofu_with_progress() {
    local stage="$1"
    local step="$2"
    local base_message="$3"
    shift 3

    local total_resources=0
    local completed_resources=0
    local current_resource=""

    local exit_code=0
    local exit_file
    exit_file=$(get_runtime_temp_file "tofu_exit_code")
    export _EXASOL_TOFU_EXIT_FILE="$exit_file"

    # Run tofu command and capture output line by line
    # Use process substitution to preserve exit code
    while IFS= read -r line; do
        # Print the line to stderr for human consumption
        echo "$line" >&2

        # Parse Terraform/Tofu output for progress
        # Count total resources based on plan summary
        local plan_total=""
        if plan_total=$(extract_plan_total_resources "$line"); then
            if [[ -n "$plan_total" ]]; then
                total_resources="$plan_total"
            fi
        fi

        # Track resource creation/modification/destruction
        if [[ "$line" =~ ^([a-z0-9_]+\.[a-z0-9_-]+(\[[^]]+\])?):\ (Creating|Modifying|Destroying|Reading) ]]; then
            current_resource="${BASH_REMATCH[1]}"
            local action="${BASH_REMATCH[3]}"
            progress_update "$stage" "$step" "$base_message ($action: $current_resource)"
        elif [[ "$line" =~ ^([a-z0-9_]+\.[a-z0-9_-]+(\[[^]]+\])?):\ (Creation\ complete|Modifications\ complete|Destruction\ complete|Read\ complete) ]]; then
            current_resource="${BASH_REMATCH[1]}"
            ((completed_resources++))

            if [[ $total_resources -gt 0 ]]; then
                local percent=$((completed_resources * 100 / total_resources))
                progress_update "$stage" "$step" "$base_message ($completed_resources/$total_resources resources)" "$percent"
            else
                progress_update "$stage" "$step" "$base_message ($completed_resources resources)"
            fi
        fi
    done < <(
        set +e
        "$@" 2>&1
        echo "$?" > "$_EXASOL_TOFU_EXIT_FILE"
    )

    unset _EXASOL_TOFU_EXIT_FILE

    # Get the exit code
    if [[ -f "$exit_file" ]]; then
        exit_code=$(cat "$exit_file")
        rm -f "$exit_file"
    else
        exit_code=1
    fi

    return "$exit_code"
}

# Estimate task weight based on task name patterns
# Returns a weight multiplier (1-10) where higher = takes longer
estimate_task_weight() {
    local task_name="$1"

    # Heavy tasks (10x weight)
    if [[ "$task_name" =~ (Download|download|Install|install|Extract|extract|Unpack|unpack) ]]; then
        echo "10"
    # Medium-heavy tasks (5x weight)
    elif [[ "$task_name" =~ (Initialize|initialize|Setup|setup|Configure|configure|Build|build|Compile|compile) ]]; then
        echo "5"
    # Medium tasks (3x weight)
    elif [[ "$task_name" =~ (Copy|copy|Update|update|Start|start|Restart|restart) ]]; then
        echo "3"
    # Light tasks (1x weight)
    else
        echo "1"
    fi
}

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
    local lower_task="${task_name,,}"

    if [[ "$lower_task" =~ (download|fetch|get|transfer|artifact|tarball) ]]; then
        echo "download"
    elif [[ "$lower_task" =~ (install|configure|setup|enable|start|service|systemd|extract|untar|unpack|symlink|directory) ]]; then
        echo "install"
    else
        echo "prepare"
    fi
}

# Run Ansible command with progress tracking
# Usage: run_ansible_with_progress <stage> <step> <base_message> <command> [args...]
run_ansible_with_progress() {
    local stage="$1"
    local step="$2"
    local base_message="$3"
    shift 3

    local total_tasks=0
    local completed_tasks=0
    local current_task=""
    local task_start_time=0
    local total_weight=0
    local completed_weight=0
    local current_task_weight=1
    local current_phase="prepare"
    local task_accounted=0

    local -a phase_order=("prepare" "download" "install")
    declare -A phase_labels=(
        ["prepare"]="Prep"
        ["download"]="Download"
        ["install"]="Install"
    )
    declare -A phase_total_weights=(
        ["prepare"]=0
        ["download"]=0
        ["install"]=0
    )
    declare -A phase_completed_weights=(
        ["prepare"]=0
        ["download"]=0
        ["install"]=0
    )

    # Run ansible command and capture output line by line
    local exit_code=0
    local exit_file
    exit_file=$(get_runtime_temp_file "ansible_exit_code")
    export _EXASOL_ANSIBLE_EXIT_FILE="$exit_file"
    while IFS= read -r line; do
        # Print the line to stderr for human consumption
        echo "$line" >&2

        # Parse Ansible output for progress
        # Task headers: "TASK [task name]"
        if [[ "$line" =~ ^TASK\ \[([^\]]+)\] ]]; then
            current_task="${BASH_REMATCH[1]}"
            current_phase=$(categorize_ansible_phase "$current_task")
            ((total_tasks++))
            task_start_time=$(date +%s)
            task_accounted=0

            # Estimate weight for this task
            current_task_weight=$(estimate_task_weight "$current_task")
            ((total_weight += current_task_weight))
            ((phase_total_weights[$current_phase] += current_task_weight))
        fi

        # Task completion indicators: "ok:", "changed:", "failed:"
        if [[ "$line" =~ ^(ok|changed|skipping|failed): ]]; then
            ((completed_tasks++))

            # Calculate task duration
            local task_duration=""
            if [[ $task_start_time -gt 0 ]]; then
                local task_end_time
                task_end_time=$(date +%s)
                local duration=$((task_end_time - task_start_time))
                task_duration=" (${duration}s)"
            fi

            if [[ $task_accounted -eq 0 && -n "$current_task" ]]; then
                ((completed_weight += current_task_weight))
                ((phase_completed_weights[$current_phase] += current_task_weight))
                task_accounted=1
            fi

            # Build phase summary string
            local phase_summary_parts=()
            local phase
            for phase in "${phase_order[@]}"; do
                local total_phase_weight=${phase_total_weights[$phase]:-0}
                if [[ $total_phase_weight -eq 0 ]]; then
                    continue
                fi
                local done_weight=${phase_completed_weights[$phase]:-0}
                local phase_percent=$((done_weight * 100 / total_phase_weight))
                if [[ $phase_percent -gt 100 ]]; then
                    phase_percent=100
                fi
                phase_summary_parts+=("${phase_labels[$phase]} ${phase_percent}%")
            done
            local phase_summary=""
            if [[ ${#phase_summary_parts[@]} -gt 0 ]]; then
                phase_summary=$(IFS=' | ' ; echo "${phase_summary_parts[*]}")
            fi

            local message="$base_message"
            if [[ -n "$phase_summary" ]]; then
                message="$message [$phase_summary]"
            fi

            # Calculate percentage based on weighted progress with a buffer for upcoming tasks
            if [[ $total_weight -gt 0 ]]; then
                local percent_buffer=20
                local percent=$((completed_weight * 100 / (total_weight + percent_buffer)))
                if [[ $percent -gt 95 ]]; then
                    percent=95
                fi
                progress_update "$stage" "$step" "$message (task: $current_task${task_duration})" "$percent"
            else
                progress_update "$stage" "$step" "$message (task: $current_task${task_duration})"
            fi
        fi

        # Play recap indicates completion
        if [[ "$line" =~ ^PLAY\ RECAP ]]; then
            local recap_summary_parts=()
            local recap_phase
            for recap_phase in "${phase_order[@]}"; do
                local total_phase_weight=${phase_total_weights[$recap_phase]:-0}
                if [[ $total_phase_weight -eq 0 ]]; then
                    continue
                fi
                local done_weight=${phase_completed_weights[$recap_phase]:-0}
                local phase_percent=$((done_weight * 100 / total_phase_weight))
                if [[ $phase_percent -gt 100 ]]; then
                    phase_percent=100
                fi
                recap_summary_parts+=("${phase_labels[$recap_phase]} ${phase_percent}%")
            done
            local recap_summary=""
            if [[ ${#recap_summary_parts[@]} -gt 0 ]]; then
                recap_summary=$(IFS=' | ' ; echo "${recap_summary_parts[*]}")
            fi

            local recap_message="$base_message (finalizing)"
            if [[ -n "$recap_summary" ]]; then
                recap_message="$recap_message [$recap_summary]"
            fi
            progress_update "$stage" "$step" "$recap_message" 98
        fi
    done < <(
        set +e
        "$@" 2>&1
        echo "$?" > "$_EXASOL_ANSIBLE_EXIT_FILE"
    )

    unset _EXASOL_ANSIBLE_EXIT_FILE

    # Get the exit code
    if [[ -f "$exit_file" ]]; then
        exit_code=$(cat "$exit_file")
        rm -f "$exit_file"
    else
        exit_code=1
    fi

    return "$exit_code"
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
