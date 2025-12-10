#!/usr/bin/env bash
# Keyword-based progress tracking

# Include guard
if [[ -n "${__EXASOL_PROGRESS_TRACKER_SH_INCLUDED__:-}" ]]; then
    return 0
fi
readonly __EXASOL_PROGRESS_TRACKER_SH_INCLUDED__=1

# Use a unique name to avoid clashing with top-level SCRIPT_DIR defined by the entrypoint
PROGRESS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/progress_keywords.sh
source "${PROGRESS_LIB_DIR}/progress_keywords.sh"

# Arrays holding labels/patterns for current operation (kept global for Bash 3.x)
PROGRESS_STEP_LABELS=()
PROGRESS_STEP_PATTERNS=()

# Load step labels and patterns for an operation.
progress_load_steps() {
    local operation="$1"
    PROGRESS_STEP_LABELS=()
    PROGRESS_STEP_PATTERNS=()

    local definitions
    if ! definitions=$(progress_get_step_definitions "$operation"); then
        return 1
    fi

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local label="${line%%:::*}"
        local pattern="${line#*:::}"
        PROGRESS_STEP_LABELS+=("$label")
        PROGRESS_STEP_PATTERNS+=("$pattern")
    done <<< "$definitions"
}

# Return the highest matching step index (1-based) for a log line.
progress_match_step() {
    local line="$1"
    shift
    local -a patterns=("$@")

    local matched=0
    for idx in "${!patterns[@]}"; do
        local pattern="${patterns[$idx]}"
        if [[ -n "$pattern" && "$line" =~ $pattern ]]; then
            matched=$((idx + 1))
        fi
    done

    echo "$matched"
}

# Display progress in [##/##] Step Label | log line format.
progress_display_steps() {
    local operation="$1"
    shift || true

    if ! progress_load_steps "$operation"; then
        # Unknown operation: pass-through
        while IFS= read -r line || [[ -n "$line" ]]; do
            echo "$line"
        done
        return 0
    fi

    local -a step_labels=("${PROGRESS_STEP_LABELS[@]}")
    local -a step_patterns=("${PROGRESS_STEP_PATTERNS[@]}")
    local total_steps=${#step_labels[@]}
    local current_step=1
    local pad_width=${#total_steps}

    local had_nocase=0
    if shopt -q nocasematch; then
        had_nocase=1
    fi
    shopt -s nocasematch

    while IFS= read -r line || [[ -n "$line" ]]; do
        local detected_step
        detected_step=$(progress_match_step "$line" "${step_patterns[@]}")
        if [[ "$detected_step" -ge "$current_step" && "$detected_step" -ne 0 ]]; then
            current_step="$detected_step"
        fi

        local label="${step_labels[$((current_step - 1))]}"
        printf "[%0${pad_width}d/%0${pad_width}d] %s | %s\n" \
            "$current_step" "$total_steps" "$label" "$line"
    done

    if [[ "$had_nocase" -eq 0 ]]; then
        shopt -u nocasematch
    fi
}

# Wrap command execution with keyword-based progress tracking.
progress_wrap_command() {
    local operation="$1"
    local deploy_dir="$2"
    shift 2

    export EXASOL_DEPLOY_DIR="$deploy_dir"

    (
        "$@" 2>&1 | progress_display_steps "$operation"
        exit "${PIPESTATUS[0]}"
    )
    return $?
}
