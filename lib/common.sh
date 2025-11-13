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
    ["deploy:begin"]=2
    ["deploy:tofu_init"]=5
    ["deploy:tofu_plan"]=8
    ["deploy:tofu_apply"]=30
    ["deploy:wait_instances"]=5
    ["deploy:ansible_config"]=45
    ["deploy:complete"]=5

    # Destroy stage weights (total: 100)
    ["destroy:begin"]=5
    ["destroy:confirm"]=5
    ["destroy:tofu_destroy"]=80
    ["destroy:cleanup"]=5
    ["destroy:complete"]=5

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

    # Iterate through steps in order and sum up completed weights
    for key in "${!_STEP_WEIGHTS[@]}"; do
        if [[ "$key" =~ ^${stage}: ]]; then
            local step_name="${key#*:}"
            local weight="${_STEP_WEIGHTS[$key]}"

            # If we haven't reached current step yet, count as fully completed
            if [[ "$found_current" -eq 0 ]]; then
                if [[ "$step_name" == "$current_step" ]]; then
                    # This is the current step - add partial completion
                    found_current=1
                    total_completed=$((total_completed + (weight * step_percent / 100)))
                else
                    # Previous step - count as 100% complete
                    total_completed=$((total_completed + weight))
                fi
            fi
        fi
    done

    # Return overall percentage (capped at 100)
    if [[ $total_completed -gt 100 ]]; then
        echo "100"
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
{"timestamp":"$(date -u +"%Y-%m-%dT%H:%M:%SZ")","stage":"${stage}","step":"${step}","status":"${status}","message":"${message}"${percent:+,"percent":${percent}},"overall_percent":${overall_percent}}
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

    # Run tofu command and capture output line by line
    # Use process substitution to preserve exit code
    local exit_code=0
    while IFS= read -r line; do
        # Print the line to stderr for human consumption
        echo "$line" >&2

        # Parse Terraform/Tofu output for progress
        # Count total resources from plan output (for apply operations)
        if [[ "$line" =~ Plan:.*([0-9]+)\ to\ add ]]; then
            total_resources=${BASH_REMATCH[1]}
        elif [[ "$line" =~ ([0-9]+)\ to\ change ]]; then
            ((total_resources += ${BASH_REMATCH[1]}))
        # For destroy operations
        elif [[ "$line" =~ Plan:.*([0-9]+)\ to\ destroy ]]; then
            total_resources=${BASH_REMATCH[1]}
        fi

        # Track resource creation/modification/destruction
        # Match patterns like: "aws_instance.example: Creating..." or "aws_instance.example[0]: Destroying..."
        if [[ "$line" =~ ^([a-z0-9_]+\.[a-z0-9_-]+(\[[^]]+\])?):\ (Creating|Modifying|Destroying|Reading) ]]; then
            current_resource="${BASH_REMATCH[1]}"
            local action="${BASH_REMATCH[3]}"
            progress_update "$stage" "$step" "$base_message ($action: $current_resource)"
        # Match completion patterns
        elif [[ "$line" =~ ^([a-z0-9_]+\.[a-z0-9_-]+(\[[^]]+\])?):\ (Creation\ complete|Modifications\ complete|Destruction\ complete|Read\ complete) ]]; then
            current_resource="${BASH_REMATCH[1]}"
            ((completed_resources++))

            # Calculate percentage
            if [[ $total_resources -gt 0 ]]; then
                local percent=$((completed_resources * 100 / total_resources))
                progress_update "$stage" "$step" "$base_message ($completed_resources/$total_resources resources)" "$percent"
            else
                progress_update "$stage" "$step" "$base_message ($completed_resources resources)"
            fi
        fi
    done < <("$@" 2>&1; echo "${PIPESTATUS[0]}" > /tmp/tofu_exit_code_$$)

    # Get the exit code
    exit_code=$(cat /tmp/tofu_exit_code_$$)
    rm -f /tmp/tofu_exit_code_$$

    return $exit_code
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

    # Track task weights for better progress estimation
    declare -A task_weights

    # Run ansible command and capture output line by line
    local exit_code=0
    while IFS= read -r line; do
        # Print the line to stderr for human consumption
        echo "$line" >&2

        # Parse Ansible output for progress
        # Task headers: "TASK [task name]"
        if [[ "$line" =~ ^TASK\ \[([^\]]+)\] ]]; then
            # Save previous task if exists
            if [[ -n "$current_task" ]]; then
                task_weights["$current_task"]="$current_task_weight"
                ((total_weight += current_task_weight))
            fi

            current_task="${BASH_REMATCH[1]}"
            ((total_tasks++))
            task_start_time=$(date +%s)

            # Estimate weight for this task
            current_task_weight=$(estimate_task_weight "$current_task")
        fi

        # Task completion indicators: "ok:", "changed:", "failed:"
        if [[ "$line" =~ ^(ok|changed|skipping|failed): ]]; then
            ((completed_tasks++))

            # Calculate task duration
            local task_duration=""
            if [[ $task_start_time -gt 0 ]]; then
                local task_end_time=$(date +%s)
                local duration=$((task_end_time - task_start_time))
                task_duration=" (${duration}s)"
            fi

            # Add completed task weight
            if [[ -n "$current_task" ]]; then
                ((completed_weight += current_task_weight))
            fi

            # Calculate percentage based on weighted progress
            if [[ $total_weight -gt 0 ]]; then
                local percent=$((completed_weight * 100 / (total_weight + 30)))  # +30 for estimated remaining
                if [[ $percent -gt 95 ]]; then
                    percent=95  # Cap at 95% until truly complete
                fi
                progress_update "$stage" "$step" "$base_message (task: $current_task${task_duration})" "$percent"
            else
                progress_update "$stage" "$step" "$base_message (task: $current_task${task_duration})"
            fi
        fi

        # Play recap indicates completion
        if [[ "$line" =~ ^PLAY\ RECAP ]]; then
            progress_update "$stage" "$step" "$base_message (finalizing)" 98
        fi
    done < <("$@" 2>&1; echo "${PIPESTATUS[0]}" > /tmp/ansible_exit_code_$$)

    # Get the exit code
    exit_code=$(cat /tmp/ansible_exit_code_$$)
    rm -f /tmp/ansible_exit_code_$$

    return $exit_code
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

# Generate INFO.md file for deployment directory
generate_info_md() {
    local deploy_dir="$1"
    local info_file="$deploy_dir/INFO.md"

    # Get current state
    local status
    status=$(state_read "$deploy_dir" "status")

    # Get basic deployment info
    local db_version architecture cloud_provider
    db_version=$(state_read "$deploy_dir" "db_version")
    architecture=$(state_read "$deploy_dir" "architecture")
    cloud_provider=$(state_read "$deploy_dir" "cloud_provider")

    # Start building the INFO.md content
    cat > "$info_file" <<EOF
# Exasol Deployment Information

**Status**: $status
**Database Version**: $db_version
**Architecture**: $architecture
**Cloud Provider**: $cloud_provider
**Deployment Directory**: $deploy_dir
**Last Updated**: $(get_timestamp)

EOF

    # Add deployment-specific information based on status
    case "$status" in
        "$STATE_INITIALIZED")
            cat >> "$info_file" <<EOF
## Status: Initialized

The deployment has been initialized but not yet deployed.

### Next Steps

1. Review configuration in \`variables.auto.tfvars\`
2. Run deployment: \`exasol deploy --deployment-dir $deploy_dir\`
3. Check status: \`exasol status --deployment-dir $deploy_dir\`

EOF
            ;;

        "$STATE_DEPLOYMENT_IN_PROGRESS")
            cat >> "$info_file" <<EOF
## Status: Deployment in Progress

The deployment is currently running. Please wait for completion.

### Check Progress

Run: \`exasol status --deployment-dir $deploy_dir\`

EOF
            ;;

        "$STATE_DEPLOYMENT_FAILED")
            cat >> "$info_file" <<EOF
## Status: Deployment Failed

The deployment failed. Check logs and try again.

### Troubleshooting

1. Check status: \`exasol status --deployment-dir $deploy_dir\`
2. Review Terraform logs in deployment directory
3. Fix any issues and retry: \`exasol deploy --deployment-dir $deploy_dir\`

EOF
            ;;

        "$STATE_DATABASE_CONNECTION_FAILED")
            cat >> "$info_file" <<EOF
## Status: Database Connection Failed

Infrastructure deployed but database connection failed.

### Troubleshooting

1. Check Ansible logs in deployment directory
2. Verify network connectivity
3. Check database logs on nodes

EOF
            ;;

        "$STATE_DATABASE_READY")
            cat >> "$info_file" <<EOF
## Status: Database Ready

The Exasol cluster is deployed and ready to use!

### Connection Information

#### Open Ports

- **SSH (22)**: Open to allowed CIDR
- **Exasol Database (8563)**: Open to allowed CIDR
- **AdminUI HTTPS (4444)**: Open to allowed CIDR

#### AdminUI Access

Access the AdminUI via HTTPS:
- **URL**: https://<node-ip>:4444
- **Username**: admin
- **Password**: Stored in \`.credentials.json\`

#### SSH Access to Nodes

SSH config file: \`ssh_config\` (generated after deployment)

Connect to nodes:
- \`ssh -F ssh_config n11\` (first node)
- \`ssh -F ssh_config n12\` (second node)
- etc.

#### COS (Container Operating System) Access

COS is the container runtime environment. Access it via SSH through nodes:
- \`ssh -F ssh_config n11 ssh cos\` (first node)
- \`ssh -F ssh_config n12 ssh cos\` (second node)
- etc.

### Detailed Connection Info

For detailed connection information including actual IP addresses, run:
\`\`\`bash
cd $deploy_dir
tofu output
\`\`\`

### Credentials

Database and AdminUI passwords are stored in \`.credentials.json\`.

### Important Files

- \`.exasol.json\` - Deployment state
- \`variables.auto.tfvars\` - Terraform variables
- \`.credentials.json\` - Passwords (keep secure)
- \`terraform.tfstate\` - Terraform state
- \`ssh_config\` - SSH configuration
- \`inventory.ini\` - Ansible inventory

EOF
            ;;
    esac

    log_debug "Generated INFO.md file: $info_file"
}
