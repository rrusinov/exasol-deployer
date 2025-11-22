#!/usr/bin/env bash
# Add metrics command implementation

# Source dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"

# Show help for add-metrics command
show_add_metrics_help() {
    cat <<'EOF'
Copy freshly calibrated metrics from a deployment directory to the global metrics repository.

This command helps integrate newly calibrated progress tracking metrics into the shared
repository, making them available for all users and deployments.

Usage:
  exasol add-metrics [flags]

Flags:
  --deployment-dir <path>        Directory with deployment files and metrics (default: ".")
  --dry-run                      Show what would be copied without actually copying
  -h, --help                     Show help

Examples:
  # Copy metrics from current deployment
  exasol add-metrics --deployment-dir ./my-deployment

  # Preview what would be copied
  exasol add-metrics --deployment-dir ./my-deployment --dry-run

  # Copy from current directory
  exasol add-metrics
EOF
}

# Validate deployment directory has metrics
validate_metrics_dir() {
    local deploy_dir="$1"

    if [[ ! -d "$deploy_dir" ]]; then
        log_error "Deployment directory does not exist: $deploy_dir"
        return 1
    fi

    if [[ ! -d "$deploy_dir/metrics" ]]; then
        log_error "No metrics directory found in deployment: $deploy_dir/metrics"
        log_error "Run calibration first with: PROGRESS_CALIBRATE=true exasol deploy --deployment-dir $deploy_dir"
        return 1
    fi

    local metrics_count
    metrics_count=$(find "$deploy_dir/metrics" -name "*.txt" -type f | wc -l)

    if [[ $metrics_count -eq 0 ]]; then
        log_error "No metric files found in: $deploy_dir/metrics"
        log_error "Run calibration first with: PROGRESS_CALIBRATE=true exasol deploy --deployment-dir $deploy_dir"
        return 1
    fi

    return 0
}

# Copy metrics to global repository
copy_metrics() {
    local deploy_dir="$1"
    local dry_run="$2"
    local global_metrics_dir="$LIB_DIR/metrics"

    log_info "Copying metrics from: $deploy_dir/metrics/"
    log_info "Copying metrics to: $global_metrics_dir/"

    local copied_count=0
    local skipped_count=0
    local total_count=0

    # Find all metric files
    while IFS= read -r -d '' metric_file; do
        local filename
        filename=$(basename "$metric_file")
        ((total_count++))

        # Check if file already exists in global metrics
        local exists=""
        if [[ -f "$global_metrics_dir/$filename" ]]; then
            exists="(overwriting existing)"
        fi

        if [[ "$dry_run" == "true" ]]; then
            log_info "Would copy: $filename $exists"
            ((copied_count++))
        else
            if cp "$metric_file" "$global_metrics_dir/"; then
                log_info "Copied: $filename $exists"
                ((copied_count++))
            else
                log_error "Failed to copy: $filename"
                return 1
            fi
        fi
    done < <(find "$deploy_dir/metrics" -name "*.txt" -type f -print0)

    if [[ "$dry_run" == "true" ]]; then
        log_info "Dry run complete. Would copy $total_count files."
    else
        log_info "Copy complete. Copied $copied_count files."
    fi

    return 0
}

# Main add-metrics command
cmd_add_metrics() {
    local deploy_dir="."
    local dry_run="false"

    # Parse command-specific flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --deployment-dir)
                deploy_dir="$2"
                shift 2
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            -h|--help)
                show_add_metrics_help
                return 0
                ;;
            *)
                log_error "Unknown flag: $1"
                log_error "Use 'exasol add-metrics --help' for usage information"
                return 1
                ;;
        esac
    done

    # Validate deployment directory
    if ! validate_metrics_dir "$deploy_dir"; then
        return 1
    fi

    # Copy metrics
    if ! copy_metrics "$deploy_dir" "$dry_run"; then
        return 1
    fi

    return 0
}