#!/usr/bin/env bash
# Simplified Progress Tracking Module
# Provides provider/operation-aware progress tracking with ETA calculation

# ==============================================================================
# METRIC MANAGEMENT
# ==============================================================================

# Load all metrics for a given provider and operation
# Returns: Array of metric files matching pattern
# Usage: progress_load_metrics <provider> <operation>
progress_load_metrics() {
    local provider="$1"
    local operation="$2"
    local metrics_dir="${SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")/..}/lib/metrics"

    # Find all metric files matching provider.operation.*.txt
    local -a metric_files=()
    if [[ -d "$metrics_dir" ]]; then
        while IFS= read -r -d '' file; do
            metric_files+=("$file")
        done < <(find "$metrics_dir" -name "${provider}.${operation}.*.txt" -print0 2>/dev/null)
    fi

    # Also check deployment-dir metrics if EXASOL_DEPLOY_DIR is set
    if [[ -n "${EXASOL_DEPLOY_DIR:-}" && -d "${EXASOL_DEPLOY_DIR}/metrics" ]]; then
        while IFS= read -r -d '' file; do
            metric_files+=("$file")
        done < <(find "${EXASOL_DEPLOY_DIR}/metrics" -name "${provider}.${operation}.*.txt" -print0 2>/dev/null)
    fi

    printf '%s\n' "${metric_files[@]}"
}

# Parse a metric file and extract values
# Returns: Associative array-like output (key=value per line)
# Usage: eval "$(progress_parse_metric_file <file>)"
progress_parse_metric_file() {
    local file="$1"
    [[ ! -f "$file" ]] && return 1

    while IFS='=' read -r key value; do
        case "$key" in
            total_lines) echo "metric_total_lines='$value'" ;;
            provider) echo "metric_provider='$value'" ;;
            operation) echo "metric_operation='$value'" ;;
            nodes) echo "metric_nodes='$value'" ;;
            duration) echo "metric_duration='$value'" ;;
            timestamp) echo "metric_timestamp='$value'" ;;
        esac
    done < "$file"
}

# Calculate simple average from multiple measurements
# Returns: base_lines per_node_lines (space-separated)
# Usage: read base per_node < <(progress_calculate_regression <provider> <operation>)
progress_calculate_regression() {
    local provider="$1"
    local operation="$2"

    local -a metric_files
    mapfile -t metric_files < <(progress_load_metrics "$provider" "$operation")

    if [[ ${#metric_files[@]} -eq 0 ]]; then
        # No metrics found - return default
        echo "100 50"
        return 1
    fi

    # Parse all metrics to get (nodes, total_lines) pairs
    local -a nodes_array=()
    local -a lines_array=()

    for file in "${metric_files[@]}"; do
        local metric_total_lines metric_nodes
        eval "$(progress_parse_metric_file "$file")"
        if [[ -n "$metric_nodes" && -n "$metric_total_lines" ]]; then
            nodes_array+=("$metric_nodes")
            lines_array+=("$metric_total_lines")
        fi
    done

    if [[ ${#nodes_array[@]} -eq 0 ]]; then
        echo "100 50"
        return 1
    fi

    # Simple averaging: calculate lines per node and average them
    local total_lines_per_node=0
    local count=0
    
    for i in "${!nodes_array[@]}"; do
        if [[ "${nodes_array[$i]}" -gt 0 ]]; then
            local lines_per_node=$((lines_array[i] / nodes_array[i]))
            total_lines_per_node=$((total_lines_per_node + lines_per_node))
            count=$((count + 1))
        fi
    done

    local avg_lines_per_node=50
    if [[ $count -gt 0 ]]; then
        avg_lines_per_node=$((total_lines_per_node / count))
    fi

    # Use the smallest sample as base for more accurate estimation
    local min_nodes="${nodes_array[0]}"
    local min_idx=0
    for i in "${!nodes_array[@]}"; do
        if [[ "${nodes_array[$i]}" -lt "$min_nodes" ]]; then
            min_nodes="${nodes_array[$i]}"
            min_idx=$i
        fi
    done

    local base_lines="${lines_array[$min_idx]}"
    echo "$base_lines $avg_lines_per_node"
}

# Get fallback estimate (max from all known metrics)
# Usage: progress_get_fallback_estimate
progress_get_fallback_estimate() {
    local metrics_dir="${SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")/..}/lib/metrics"
    local max_lines=1000  # Absolute default

    if [[ -d "$metrics_dir" ]]; then
        while IFS= read -r file; do
            local metric_total_lines
            eval "$(progress_parse_metric_file "$file")"
            if [[ -n "$metric_total_lines" && "$metric_total_lines" -gt "$max_lines" ]]; then
                max_lines="$metric_total_lines"
            fi
        done < <(find "$metrics_dir" -name "*.txt" -type f 2>/dev/null)
    fi

    echo "$max_lines"
}

# Calculate average duration for an operation from metrics
# Returns: estimated_duration_seconds (or 0 if no data)
# Usage: progress_get_estimated_duration <provider> <operation> <nodes>
progress_get_estimated_duration() {
    local provider="$1"
    local operation="$2"
    local nodes="${3:-1}"

    local -a metric_files
    mapfile -t metric_files < <(progress_load_metrics "$provider" "$operation")

    if [[ ${#metric_files[@]} -eq 0 ]]; then
        echo "0"
        return 1
    fi

    # Find the metric with the closest node count match
    local closest_duration=0
    local closest_diff=999
    for file in "${metric_files[@]}"; do
        local metric_nodes metric_duration
        eval "$(progress_parse_metric_file "$file")"
        if [[ -n "$metric_nodes" && -n "$metric_duration" ]]; then
            local diff=$((metric_nodes > nodes ? metric_nodes - nodes : nodes - metric_nodes))
            if [[ $diff -lt $closest_diff ]]; then
                closest_diff=$diff
                closest_duration=$metric_duration
            fi
        fi
    done

    echo "$closest_duration"
}

# ==============================================================================
# SIMPLIFIED PROGRESS DISPLAY WITH ETA
# ==============================================================================

# Display progress with simplified ETA calculation
# Usage: command 2>&1 | progress_display_with_eta <estimated_lines> <estimated_duration>
progress_display_with_eta() {
    local estimated_lines="${1:-1000}"
    local estimated_duration="${2:-0}"
    local start_time
    start_time=$(date +%s)

    # Use awk for better input handling
    awk -v total="$estimated_lines" \
        -v duration="$estimated_duration" \
        -v start="$start_time" \
        'BEGIN {
            line_count = 0
        }
        {
            line_count++
            percent = int((line_count * 100) / total)
            if (percent > 100) percent = 100
            
            # Get current time using external command
            "date +%s" | getline current_time
            close("date +%s")
            elapsed = current_time - start
            
            # Simple ETA calculation based on estimated duration
            eta_str = "   ???"
            if (duration > 0 && percent > 0) {
                eta_seconds = int(duration * (100 - percent) / 100)
                if (eta_seconds < 0) eta_seconds = 0
                
                # Format ETA
                if (eta_seconds < 60) {
                    eta_str = eta_seconds "s"
                } else if (eta_seconds < 3600) {
                    eta_min = int(eta_seconds / 60)
                    eta_str = eta_min "m"
                } else {
                    eta_hours = int(eta_seconds / 3600)
                    eta_min = int((eta_seconds % 3600) / 60)
                    eta_str = eta_hours "h" eta_min "m"
                }
            }
            
            printf "[%3d%%] [ETA: %6s] %s\n", percent, eta_str, $0
            fflush()
        }
        END {
            if (ENVIRON["PROGRESS_RECORD_FILE"] != "") {
                # Record final stats for calibration (simplified - no per-line offsets)
                "date +%s" | getline final_time
                close("date +%s")
                duration = final_time - start
                print "total_lines=" line_count > ENVIRON["PROGRESS_RECORD_FILE"]
                print "duration=" duration >> ENVIRON["PROGRESS_RECORD_FILE"]
                close(ENVIRON["PROGRESS_RECORD_FILE"])
            }
        }'
}

# ==============================================================================
# MAIN PROGRESS WRAPPER
# ==============================================================================

# Wrap command execution with progress tracking
# Usage: progress_wrap_command <operation> <deploy_dir> <command> [args...]
progress_wrap_command() {
    local operation="$1"
    local deploy_dir="$2"
    shift 2

    # Determine provider and node count from deployment
    local provider="unknown"
    local nodes=1

    if [[ -f "$deploy_dir/.exasol.json" ]]; then
        provider=$(jq -r '.cloud_provider // "unknown"' "$deploy_dir/.exasol.json" 2>/dev/null || echo "unknown")

        # Get cluster size by parsing variables.auto.tfvars
        local tfvars_file="$deploy_dir/variables.auto.tfvars"
        if [[ -f "$tfvars_file" ]]; then
            nodes=$(awk -F'=' '/^[[:space:]]*node_count[[:space:]]*=/{gsub(/[^0-9]/,"",$2); if($2!="") {print $2; exit}}' "$tfvars_file" 2>/dev/null)
        fi
        nodes=${nodes:-1}
    fi

    # Calculate estimated lines
    local estimated_lines
    local base_lines per_node_lines

    if read -r base_lines per_node_lines < <(progress_calculate_regression "$provider" "$operation" 2>/dev/null); then
        estimated_lines=$((base_lines + (nodes - 1) * per_node_lines))
    else
        # Fallback to max known metric
        estimated_lines=$(progress_get_fallback_estimate)
    fi

    # Get estimated duration from metrics
    local estimated_duration
    if estimated_duration=$(progress_get_estimated_duration "$provider" "$operation" "$nodes" 2>/dev/null); then
        :
    else
        estimated_duration=0
    fi

    # Setup calibration recording if requested
    local record_file=""
    if [[ "${PROGRESS_CALIBRATE:-}" == "true" ]]; then
        mkdir -p "$deploy_dir/metrics"
        record_file="$deploy_dir/metrics/${provider}.${operation}.${nodes}.txt"
        export PROGRESS_RECORD_FILE="$record_file"

        # Add metadata
        {
            echo "provider=$provider"
            echo "operation=$operation"
            echo "nodes=$nodes"
            echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        } > "$record_file"
    fi

    # Execute command with progress tracking inside a subshell
    (
        "$@" 2>&1 | progress_display_with_eta "$estimated_lines" "$estimated_duration"
        subs_exit_code=${PIPESTATUS[0]}
        exit "$subs_exit_code"
    )

    local exit_code=$?

    # Cleanup
    unset PROGRESS_RECORD_FILE

    return "$exit_code"
}

# ==============================================================================
# HELPER: Estimate lines for a specific configuration
# ==============================================================================

# Estimate total lines for an operation
# Usage: progress_estimate_lines <provider> <operation> <nodes>
progress_estimate_lines() {
    local provider="$1"
    local operation="$2"
    local nodes="${3:-1}"

    local base_lines per_node_lines
    if read -r base_lines per_node_lines < <(progress_calculate_regression "$provider" "$operation" 2>/dev/null); then
        echo $((base_lines + (nodes - 1) * per_node_lines))
    else
        progress_get_fallback_estimate
    fi
}
