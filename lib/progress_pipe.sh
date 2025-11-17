#!/usr/bin/env bash
# Real-time progress tracking by counting output lines
# Much simpler than LOC-based tracking - just pipe command output through progress tracker

# ==============================================================================
# PROGRESS ESTIMATION
# Estimated output lines for common operations (calibrated from actual runs)
# ==============================================================================

declare -gA ESTIMATED_LINES=(
    # Measured from actual runs (lines of output)
    # Format: operation_1node = baseline, operation_per_node = increment per additional node
    # Based on measurements:
    # init:    26 lines (constant, no scaling)
    # deploy:  994 (1 node), 1903 (4 nodes), 3140 (8 nodes)
    # destroy: 808 (1 node), 1797 (4 nodes), 3099 (8 nodes)

    # Init operation (constant, no per-node scaling)
    [init_1node]=26
    [init_per_node]=0

    # Deploy operation (fitted from measurements)
    # Calculated: base=994, per_node=(3140-994)/7≈306
    [deploy_1node]=994
    [deploy_per_node]=306

    # Destroy operation (fitted from measurements)
    # Calculated: base=808, per_node=(3099-808)/7≈327
    [destroy_1node]=808
    [destroy_per_node]=327

    # Start/Stop operations (estimated, to be measured)
    [start_1node]=100
    [start_per_node]=50
    [stop_1node]=100
    [stop_per_node]=50
)

# ==============================================================================
# CORE PROGRESS FUNCTION
# ==============================================================================

# Global progress tracking variables
declare -g _PROGRESS_TOTAL_LINES=100
declare -g _PROGRESS_COMPLETED_LINES=0
declare -g _PROGRESS_BASE_PERCENT=0

# Initialize cumulative progress tracking for a multi-step operation
# Usage: progress_init_cumulative <total_lines_for_all_steps>
progress_init_cumulative() {
    _PROGRESS_TOTAL_LINES="${1:-100}"
    _PROGRESS_COMPLETED_LINES=0
    _PROGRESS_BASE_PERCENT=0
}

# Add progress prefix to each output line with cumulative tracking
# Calculates progress as: (base_percent + current_step_progress) / total
# Usage: command | progress_prefix_cumulative <estimated_lines_for_this_step>
progress_prefix_cumulative() {
    local estimated_lines="${1:-100}"

    # Pass the base and estimated to awk for calculation
    awk -v base_lines="$_PROGRESS_COMPLETED_LINES" \
        -v step_lines="$estimated_lines" \
        -v total_lines="$_PROGRESS_TOTAL_LINES" '
    {
        line_count++
        # Calculate cumulative progress: (completed + current) / total
        current_progress = base_lines + line_count
        percent = int((current_progress * 100) / total_lines)
        if (percent > 100) percent = 100
        printf "%3d%% | %s\n", percent, $0
        fflush()
    }
    END {
        # Export the final line count for next step (via temp file)
        if (ENVIRON["PROGRESS_STATE_FILE"] != "") {
            print base_lines + line_count > ENVIRON["PROGRESS_STATE_FILE"]
        }
    }
    '

    # Update completed lines for next step
    local state_file="/tmp/progress_state_$$"
    export PROGRESS_STATE_FILE="$state_file"
    if [[ -f "$state_file" ]]; then
        _PROGRESS_COMPLETED_LINES=$(cat "$state_file")
        rm -f "$state_file"
    else
        _PROGRESS_COMPLETED_LINES=$((_PROGRESS_COMPLETED_LINES + estimated_lines))
    fi
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Calculate estimated lines for an operation
# Usage: estimate_lines <operation> <node_count>
estimate_lines() {
    local operation="$1"
    local node_count="${2:-1}"

    local base_key="${operation}_1node"
    local per_node_key="${operation}_per_node"

    local base_lines="${ESTIMATED_LINES[$base_key]:-100}"
    local per_node_lines="${ESTIMATED_LINES[$per_node_key]:-0}"

    echo $((base_lines + per_node_lines * (node_count - 1)))
}
