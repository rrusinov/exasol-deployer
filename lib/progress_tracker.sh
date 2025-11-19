#!/usr/bin/env bash
# External Progress Tracking Module
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

    local total_lines provider operation nodes duration timestamp
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

# Calculate regression formula from multiple measurements
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

    # Simple linear regression: lines = base + (nodes - 1) * per_node
    # If only one sample, use it as base with default per_node
    if [[ ${#nodes_array[@]} -eq 1 ]]; then
        local base="${lines_array[0]}"
        local per_node=50  # Default scaling
        echo "$base $per_node"
        return 0
    fi

    # For multiple samples, calculate per_node as average slope
    # Find min nodes sample as base
    local min_nodes="${nodes_array[0]}"
    local min_idx=0
    for i in "${!nodes_array[@]}"; do
        if [[ "${nodes_array[$i]}" -lt "$min_nodes" ]]; then
            min_nodes="${nodes_array[$i]}"
            min_idx=$i
        fi
    done

    local base_lines="${lines_array[$min_idx]}"

    # Calculate per_node from all other samples
    local total_per_node=0
    local count_per_node=0
    for i in "${!nodes_array[@]}"; do
        if [[ $i -ne $min_idx ]]; then
            local nodes_diff=$((nodes_array[i] - min_nodes))
            local lines_diff=$((lines_array[i] - base_lines))
            if [[ $nodes_diff -gt 0 ]]; then
                local per_node=$((lines_diff / nodes_diff))
                total_per_node=$((total_per_node + per_node))
                count_per_node=$((count_per_node + 1))
            fi
        fi
    done

    local avg_per_node=50
    if [[ $count_per_node -gt 0 ]]; then
        avg_per_node=$((total_per_node / count_per_node))
    fi

    echo "$base_lines $avg_per_node"
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

    # Parse metrics to get durations for similar node counts
    local total_duration=0
    local count=0
    local closest_duration=0
    local closest_diff=999

    for file in "${metric_files[@]}"; do
        local metric_nodes metric_duration
        eval "$(progress_parse_metric_file "$file")"

        if [[ -n "$metric_nodes" && -n "$metric_duration" ]]; then
            # Track all durations for averaging
            total_duration=$((total_duration + metric_duration))
            count=$((count + 1))

            # Track closest match by node count
            local diff=$((metric_nodes > nodes ? metric_nodes - nodes : nodes - metric_nodes))
            if [[ $diff -lt $closest_diff ]]; then
                closest_diff=$diff
                closest_duration=$metric_duration
            fi
        fi
    done

    if [[ $count -eq 0 ]]; then
        echo "0"
        return 1
    fi

    # If we have an exact or close match (within 2 nodes), use it
    # Otherwise use average of all samples
    if [[ $closest_diff -le 2 ]]; then
        echo "$closest_duration"
    else
        echo $((total_duration / count))
    fi
}

# ==============================================================================
# PROGRESS DISPLAY WITH ETA
# ==============================================================================

# Display progress with ETA
# Usage: command 2>&1 | progress_display_with_eta <estimated_lines> <estimated_duration>
progress_display_with_eta() {
    local estimated_lines="${1:-1000}"
    local estimated_duration="${2:-0}"
    local start_time
    start_time=$(date +%s)

    awk -v estimated="$estimated_lines" \
        -v est_duration="$estimated_duration" \
        -v start_time="$start_time" \
        '
    BEGIN {
        line_count = 0
    }
    {
        line_count++
        percent = int((line_count * 100) / estimated)
        if (percent > 100) percent = 100

        # Calculate ETA
        current_time = systime()
        elapsed = current_time - start_time

        eta_str = "   ???"

        # Method 1: If we have estimated duration from metrics, use it
        if (est_duration > 0 && percent > 0) {
            # ETA based on percentage completion and known duration
            total_expected = est_duration
            eta_seconds = int(total_expected - (total_expected * percent / 100))

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
        # Method 2: Fallback to line-based rate if no duration data AND
        # the operation is calibrated. If not calibrated, always show ???
        else if (ENVIRON["PROGRESS_CALIBRATED"] == "true" && line_count > 10 && elapsed > 0) {
            lines_per_sec = line_count / elapsed
            if (lines_per_sec > 0) {
                remaining_lines = estimated - line_count
                eta_seconds = int(remaining_lines / lines_per_sec)

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
        }
        else {
            eta_str = "   ???"
        }

        printf "[%3d%%] [ETA: %6s] %s\n", percent, eta_str, $0
        fflush()
    }
    END {
        if (ENVIRON["PROGRESS_RECORD_FILE"] != "") {
            # Record final stats for calibration
            final_time = systime()
            duration = final_time - start_time
            print "total_lines=" line_count > ENVIRON["PROGRESS_RECORD_FILE"]
            print "duration=" duration >> ENVIRON["PROGRESS_RECORD_FILE"]
            # Also write per-line offsets: line_offset_<n>=<seconds_since_start>
            for (i = 1; i <= line_count; i++) {
                # Store approximate offset as fraction of duration
                # We do not have per-line timestamps here; approximate by linear spacing
                offset = int((i - 1) * (duration / (line_count > 1 ? (line_count - 1) : 1)))
                printf("line_offset_%d=%d\n", i, offset) >> ENVIRON["PROGRESS_RECORD_FILE"]
            }
            close(ENVIRON["PROGRESS_RECORD_FILE"])
        }
    }
    '
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

    # Get estimated duration from metrics. Use an if-guarded command
    # substitution so `set -e` does not abort the script when there
    # are no metrics (the function may return non-zero).
    local estimated_duration
    if estimated_duration=$(progress_get_estimated_duration "$provider" "$operation" "$nodes" 2>/dev/null); then
        :
    else
        estimated_duration=0
    fi

    # Determine whether this operation is calibrated for provider:
    # Calibration criteria: at least two metric files exist for this
    # provider+operation and they include at least one single-node (nodes=1)
    # and at least one multi-node (nodes>1) sample.
    local -a _metrics
    mapfile -t _metrics < <(progress_load_metrics "$provider" "$operation" 2>/dev/null || true)
    local _has_single=0
    local _has_multi=0
    if [[ ${#_metrics[@]} -ge 2 ]]; then
        for _m in "${_metrics[@]}"; do
            local metric_nodes
            eval "$(progress_parse_metric_file "$_m")" >/dev/null 2>&1 || true
            if [[ -n "${metric_nodes:-}" ]]; then
                if [[ "${metric_nodes}" -eq 1 ]]; then
                    _has_single=1
                else
                    _has_multi=1
                fi
            fi
        done
    fi
    if [[ "$_has_single" -eq 1 && "$_has_multi" -eq 1 ]]; then
        export PROGRESS_CALIBRATED=true
    else
        export PROGRESS_CALIBRATED=false
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

    # Execute command with progress tracking inside a subshell so that
    # the top-level `set -e` and `pipefail` do not cause the whole script
    # to exit before we can capture the wrapped command's exit code.
    # We still use PIPESTATUS within the subshell to obtain the left-side
    # command exit code, and then return it from this function.
    (
        # Run the command piped into the progress display. Capture pipe status
        # immediately in a variable so it isn't overwritten by other commands.
        "$@" 2>&1 | progress_display_with_eta "$estimated_lines" "$estimated_duration"
        subs_exit_code=${PIPESTATUS[0]}
        # Exit the subshell with the wrapped command's exit code so the
        # parent can capture it via $?.
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

# Build a timeline mapping from observed metrics.
# Output format: line_start line_end percent_start percent_end
# Usage: progress_build_timeline <provider> <operation>
progress_build_timeline() {
    local provider="$1"
    local operation="$2"

    local -a metric_files
    mapfile -t metric_files < <(progress_load_metrics "$provider" "$operation" 2>/dev/null || true)

    if [[ ${#metric_files[@]} -eq 0 ]]; then
        return 1
    fi

    # Collect normalized per-line offsets for each metric
    # We'll aggregate by percentiles: convert line offsets to percent (0..100)
    # and then compute average line ranges per percentile bucket.

    # Temp file to hold per-line percent entries: percent line
    local tmpfile
    tmpfile=$(mktemp)
    for mf in "${metric_files[@]}"; do
        # Read total_lines and duration
        local metric_total_lines metric_duration
        eval "$(progress_parse_metric_file "$mf")" >/dev/null 2>&1 || true
        metric_total_lines=${metric_total_lines:-0}
        metric_duration=${metric_duration:-0}
        if [[ $metric_total_lines -le 0 ]]; then
            continue
        fi

        # Read per-line offsets if available
        while IFS='=' read -r key value; do
            case "$key" in
                line_offset_*)
                    # extract line number
                    ln=${key#line_offset_}
                    # percent through run (approx)
                    if [[ $metric_duration -gt 0 ]]; then
                        pct=$(( (value * 100) / metric_duration ))
                    else
                        # fallback: linear mapping by line
                        pct=$(( (ln * 100) / metric_total_lines ))
                    fi
                    echo "$pct $ln" >> "$tmpfile"
                    ;;
            esac
        done < <(grep -E '^line_offset_[0-9]+=' "$mf" 2>/dev/null || true)
    done

    if [[ ! -s "$tmpfile" ]]; then
        rm -f "$tmpfile"
        return 1
    fi

    # Aggregate: for each percentile bucket (0..100) find min/max line
    for p in $(seq 0 100); do
        # find lines for this percentile
        lines=$(awk -v P="$p" '$1==P{print $2}' "$tmpfile" | sort -n | tr '\n' ' ')
        if [[ -n "$lines" ]]; then
            # min and max line for this percentile
            # Safely split the whitespace-separated list into an array
            read -r -a __lines_array <<< "$lines"
            minl=${__lines_array[0]}
            maxl=${__lines_array[${#__lines_array[@]}-1]}
            printf "%s %s %s %s\n" "$minl" "$maxl" "$p" "$p"
        fi
    done

    rm -f "$tmpfile"
    return 0
}
