#!/usr/bin/env bash
# shellcheck disable=SC2155
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    if [[ -n "${__EXASOL_RUN_E2E_SH_INCLUDED__:-}" ]]; then
        return 0
    fi
    readonly __EXASOL_RUN_E2E_SH_INCLUDED__=1
fi

set -euo pipefail

# Check bash version (requires 4.0+ for associative arrays and mapfile)
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "Error: This script requires Bash 4.0 or higher (current: ${BASH_VERSION})" >&2
    echo "Please upgrade bash or use a system with bash 4.0+" >&2
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Track background processes and deployment directories for cleanup
declare -a BACKGROUND_PIDS=()
declare -a DEPLOYMENT_DIRS=()

# shellcheck disable=SC2317,SC2329
cleanup_on_interrupt() {
    # Disable trap to prevent recursive calls
    trap - SIGINT SIGTERM
    
    echo ""
    echo "=========================================="
    echo "Interrupt received - cleaning up..."
    echo "=========================================="
    
    # Kill all background test processes
    if [[ ${#BACKGROUND_PIDS[@]} -gt 0 ]]; then
        echo "Terminating ${#BACKGROUND_PIDS[@]} background test process(es)..."
        for pid in "${BACKGROUND_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                echo "  Killing process $pid"
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
        # Wait a moment for graceful termination
        sleep 10
        # Force kill any remaining processes
        for pid in "${BACKGROUND_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                echo "  Force killing process $pid"
                kill -KILL "$pid" 2>/dev/null || true
            fi
        done
    fi
    
    # Destroy all active deployments with retry logic
    if [[ ${#DEPLOYMENT_DIRS[@]} -gt 0 ]]; then
        echo ""
        echo "Destroying ${#DEPLOYMENT_DIRS[@]} active deployment(s)..."
        
        # Try up to 3 times
        for attempt in 1 2 3 4 5 6; do
            declare -a failed_dirs=()
            
            # Launch destroy operations in parallel with timeout
            declare -a destroy_pids=()
            for deploy_dir in "${DEPLOYMENT_DIRS[@]}"; do
                if [[ -d "$deploy_dir" && -f "$deploy_dir/.exasol.json" ]]; then
                    if [[ $attempt -eq 1 ]]; then
                        echo "  Destroying: $deploy_dir"
                    else
                        echo "  Retry $attempt: $deploy_dir"
                        sleep 10
                    fi
                    (
                        output=$(timeout 300 ./exasol destroy --auto-approve --deployment-dir "$deploy_dir" 2>&1)
                        exit_code=$?
                        echo "$output" | grep -E "INFO|ERROR|WARN|Destroy" || true
                        # Check if destroy failed or timed out
                        if [[ $exit_code -eq 124 ]]; then
                            echo "  ERROR: Destroy timed out after 300 seconds"
                            exit 1
                        elif echo "$output" | grep -qE "ERROR|Another operation is in progress"; then
                            exit 1
                        fi
                    ) &
                    pid=$!
                    destroy_pids+=("$pid")
                    echo "    [PID: $pid]"
                fi
            done
            
            # Wait for all destroy operations with timeout
            if [[ ${#destroy_pids[@]} -gt 0 ]]; then
                echo "  Waiting for destroy operations to complete..."
                for pid in "${destroy_pids[@]}"; do
                    wait "$pid" 2>/dev/null || true
                done
            fi
            
            # Check which deployments still exist
            for deploy_dir in "${DEPLOYMENT_DIRS[@]}"; do
                if [[ -d "$deploy_dir" && -f "$deploy_dir/.exasol.json" ]]; then
                    # Check if terraform state still exists
                    if [[ -f "$deploy_dir/terraform.tfstate" ]] && grep -q '"resources":' "$deploy_dir/terraform.tfstate" 2>/dev/null; then
                        failed_dirs+=("$deploy_dir")
                    fi
                fi
            done
            
            # If all succeeded, break
            if [[ ${#failed_dirs[@]} -eq 0 ]]; then
                echo "  All deployments destroyed successfully"
                break
            fi
            
            # Update list for retry
            DEPLOYMENT_DIRS=("${failed_dirs[@]}")
            
            if [[ $attempt -lt 3 ]]; then
                echo "  ${#failed_dirs[@]} deployment(s) still active, retrying in 3 seconds..."
                sleep 3
            else
                echo "  Warning: ${#failed_dirs[@]} deployment(s) could not be destroyed after 3 attempts"
                for dir in "${failed_dirs[@]}"; do
                    echo "    - $dir"
                done
            fi
        done
    fi
    
    echo ""
    echo "Cleanup complete"
    exit 130
}

# Set up trap for SIGINT (Ctrl+C) and SIGTERM
trap cleanup_on_interrupt SIGINT SIGTERM

usage() {
    cat <<'EOF'
Usage: tests/run_e2e.sh [options]

Options:
  --provider <name[,name...]>   Run only tests for the specified cloud provider(s)
  --configs <name[,name...]>    Run only the specified config files (e.g. aws,libvirt,aws-arm64)
  --parallel <n>                Override parallelism (0 = auto/all tests)
  --stop-on-error               Stop execution on first test failure (for debugging)
  --db-version <version>        Database version to use (e.g. 8.0.0-x86_64, overrides config)
  --results-dir <path>          Use specific execution directory (default: auto-generated)
  --rerun <exec-dir> <suite>    Rerun specific suite from execution directory
  --list-test(s) [provider]     List all known tests grouped by provider (optionally filter by provider)
  --run-tests <id[,id...]>      Execute only the specified tests (ids from --list-tests)
  -h, --help                    Show this help

Examples:
  tests/run_e2e.sh --provider aws
  tests/run_e2e.sh --configs libvirt,aws-arm64
  tests/run_e2e.sh --db-version 8.0.0-x86_64
  tests/run_e2e.sh --rerun ./tmp/tests/e2e-20251203-120000 aws-1n_basic
  tests/run_e2e.sh --list-tests
  tests/run_e2e.sh --list-tests libvirt
  tests/run_e2e.sh --run-tests aws-1n-basic
EOF
}

RESULTS_DIR=""
PROVIDER_FILTER=""
PROVIDER_SPECIFIED=0
CONFIGS_FILTER=""
CONFIGS_SPECIFIED=0
PARALLEL=0
STOP_ON_ERROR=0
DB_VERSION=""
RERUN_EXEC_DIR=""
RERUN_SUITE=""
LIST_TESTS=0
RUN_TEST_IDS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --provider)
            if [[ $# -lt 2 ]]; then
                echo "Error: Missing value for --provider" >&2
                usage
                exit 1
            fi
            if [[ -z "$2" || "$2" =~ ^[[:space:]]*$ ]]; then
                echo "Error: --provider cannot be empty" >&2
                usage
                exit 1
            fi
            PROVIDER_FILTER="$2"
            PROVIDER_SPECIFIED=1
            shift 2
            ;;
        --configs)
            if [[ $# -lt 2 ]]; then
                echo "Error: Missing value for --configs" >&2
                usage
                exit 1
            fi
            if [[ -z "$2" || "$2" =~ ^[[:space:]]*$ ]]; then
                echo "Error: --configs cannot be empty" >&2
                usage
                exit 1
            fi
            CONFIGS_FILTER="$2"
            CONFIGS_SPECIFIED=1
            shift 2
            ;;
        --parallel)
            if [[ $# -lt 2 ]]; then
                echo "Error: Missing value for --parallel" >&2
                usage
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --parallel must be a non-negative integer (got: $2)" >&2
                usage
                exit 1
            fi
            PARALLEL="$2"
            shift 2
            ;;
        --stop-on-error)
            STOP_ON_ERROR=1
            shift
            ;;
        --db-version)
            if [[ $# -lt 2 ]]; then
                echo "Error: Missing value for --db-version" >&2
                usage
                exit 1
            fi
            DB_VERSION="$2"
            shift 2
            ;;
        --results-dir)
            if [[ $# -lt 2 ]]; then
                echo "Error: Missing value for --results-dir" >&2
                usage
                exit 1
            fi
            RESULTS_DIR="$2"
            shift 2
            ;;
        --rerun)
            if [[ $# -lt 3 ]]; then
                echo "Error: Missing value(s) for --rerun <exec-dir> <suite>" >&2
                usage
                exit 1
            fi
            RERUN_EXEC_DIR="$2"
            RERUN_SUITE="$3"
            shift 3
            ;;
        --results-file)
            # Deprecated, kept for compatibility
            shift 2
            ;;
        --list-test|--list-tests)
            LIST_TESTS=1
            # Check if next argument is a provider name (not starting with --)
            if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
                PROVIDER_FILTER="$2"
                shift
            fi
            shift
            ;;
        --run-tests|--run-test)
            if [[ $# -lt 2 ]]; then
                echo "Error: Missing value for --run-tests" >&2
                usage
                exit 1
            fi
            RUN_TEST_IDS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# Validate mutually exclusive options
if [[ "$PROVIDER_SPECIFIED" -eq 1 && "$CONFIGS_SPECIFIED" -eq 1 ]]; then
    echo "Error: --provider and --configs cannot be used together" >&2
    exit 1
fi

# Normalize provider filter
if [[ -n "$PROVIDER_FILTER" && "${PROVIDER_FILTER,,}" == "all" ]]; then
    PROVIDER_FILTER=""
fi

# Normalize configs filter
if [[ -n "$CONFIGS_FILTER" && "${CONFIGS_FILTER,,}" == "all" ]]; then
    CONFIGS_FILTER=""
fi

# Only create results directory if explicitly provided
if [[ -n "$RESULTS_DIR" ]]; then
    mkdir -p "$RESULTS_DIR"
fi

discover_configs() {
    find "$SCRIPT_DIR/e2e/configs" -maxdepth 1 -type f -name '*.json' | sort
}

run_framework() {
    local config_file="$1"
    shift
    local db_version_args=()
    if [[ -n "$DB_VERSION" ]]; then
        db_version_args=(--db-version "$DB_VERSION")
    fi
    local results_dir_args=()
    if [[ -n "$RESULTS_DIR" ]]; then
        results_dir_args=(--results-dir "$RESULTS_DIR")
    fi
    local stop_on_error_args=()
    if [[ "$STOP_ON_ERROR" -eq 1 ]]; then
        stop_on_error_args=(--stop-on-error)
    fi
    
    # Run the framework without capturing output so progress bar is visible
    python3 "$SCRIPT_DIR/e2e/e2e_framework.py" run \
        --config "$config_file" \
        "${results_dir_args[@]}" \
        --parallel "$PARALLEL" \
        "${stop_on_error_args[@]}" \
        "${db_version_args[@]}" \
        "$@"
    
    # If RESULTS_DIR was not set, find the most recent execution directory
    if [[ -z "$RESULTS_DIR" ]]; then
        RESULTS_DIR="$(find ./tmp/tests -maxdepth 1 -type d -name 'e2e-*' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
    fi
}

print_failures() {
    local results_file="$1"
    python3 "$SCRIPT_DIR/e2e/e2e_shell_helpers.py" print_failures "$results_file"
}

tail_failed_logs() {
    local results_file="$1"
    local failures_json
    failures_json="$(print_failures "$results_file")"
    if [[ "$failures_json" == "[]" ]]; then
        return 0
    fi
    python3 "$SCRIPT_DIR/e2e/e2e_shell_helpers.py" tail_failed_logs "$failures_json"
}

list_tests_for_configs() {
    local results_dir="$1"
    local provider_filter="$2"
    shift 2
    python3 "$SCRIPT_DIR/e2e/e2e_shell_helpers.py" list_tests "$results_dir" "$provider_filter" "$@"
}

resolve_selected_tests() {
    local results_dir="$1"
    local ids="$2"
    shift 2
    python3 "$SCRIPT_DIR/e2e/e2e_shell_helpers.py" resolve_tests "$results_dir" "$ids" "$@"
}

overall_status=0

# Check if no arguments provided - show help and exit
if [[ "$LIST_TESTS" -eq 0 && -z "$RUN_TEST_IDS" && -z "$RERUN_EXEC_DIR" && -z "$PROVIDER_FILTER" && "$PROVIDER_SPECIFIED" -eq 0 && "$CONFIGS_SPECIFIED" -eq 0 ]]; then
    usage
    exit 0
fi

mapfile -t configs < <(discover_configs)

if [[ "$LIST_TESTS" -eq 1 ]]; then
    if [[ ${#configs[@]} -eq 0 ]]; then
        echo "No e2e configuration files found." >&2
        exit 1
    fi
    
    # Apply same filtering logic as main execution
    filtered_configs=("${configs[@]}")
    if [[ -n "$PROVIDER_FILTER" ]]; then
        IFS=',' read -ra provider_list <<< "$PROVIDER_FILTER"
        filtered_configs=()
        missing_providers=()
        
        # Get list of available providers
        available_providers=()
        for cfg in "${configs[@]}"; do
            cfg_provider=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1])).get('provider', ''))" "$cfg")
            if [[ -n "$cfg_provider" ]]; then
                # Check if provider is already in array
                provider_exists=0
                for existing in "${available_providers[@]}"; do
                    if [[ "$existing" == "$cfg_provider" ]]; then
                        provider_exists=1
                        break
                    fi
                done
                if [[ $provider_exists -eq 0 ]]; then
                    available_providers+=("$cfg_provider")
                fi
            fi
        done
        
        # Validate that all requested providers exist
        for requested_provider in "${provider_list[@]}"; do
            found=0
            for cfg in "${configs[@]}"; do
                cfg_provider=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1])).get('provider', ''))" "$cfg")
                if [[ "$cfg_provider" == "$requested_provider" ]]; then
                    filtered_configs+=("$cfg")
                    found=1
                    break
                fi
            done
            if [[ $found -eq 0 ]]; then
                missing_providers+=("$requested_provider")
            fi
        done
        
        # Report missing providers and exit
        if [[ ${#missing_providers[@]} -gt 0 ]]; then
            echo "Error: The following providers do not exist: ${missing_providers[*]}" >&2
            echo "Available providers: ${available_providers[*]}" >&2
            exit 1
        fi
    elif [[ -n "$CONFIGS_FILTER" ]]; then
        IFS=',' read -ra config_list <<< "$CONFIGS_FILTER"
        filtered_configs=()
        missing_configs=()
        
        # Validate that all requested configs exist
        for requested_config in "${config_list[@]}"; do
            found=0
            for cfg in "${configs[@]}"; do
                cfg_basename=$(basename "$cfg" .json)
                if [[ "$cfg_basename" == "$requested_config" ]]; then
                    filtered_configs+=("$cfg")
                    found=1
                    break
                fi
            done
            if [[ $found -eq 0 ]]; then
                missing_configs+=("$requested_config")
            fi
        done
        
        # Report missing configs and exit
        if [[ ${#missing_configs[@]} -gt 0 ]]; then
            echo "Error: The following config files do not exist: ${missing_configs[*]}" >&2
            available_configs=""
            for cfg in "${configs[@]}"; do
                available_configs+="$(basename "$cfg" .json) "
            done
            echo "Available configs: ${available_configs% }" >&2
            exit 1
        fi
    fi
    
    if [[ ${#filtered_configs[@]} -eq 0 ]]; then
        echo "No e2e configuration files match the specified filter." >&2
        exit 1
    fi
    
    list_tests_for_configs "$RESULTS_DIR" "$PROVIDER_FILTER" "${filtered_configs[@]}"
    exit 0
fi

if [[ -n "$RUN_TEST_IDS" ]]; then
    if [[ ${#configs[@]} -eq 0 ]]; then
        echo "No e2e configuration files found." >&2
        exit 1
    fi

    declare -A manual_groups=()
    missing_tests=()

    while IFS='|' read -r status test_id cfg _ _; do
        [[ -z "$status" ]] && continue
        if [[ "$status" == "FOUND" ]]; then
            if [[ -n "${manual_groups[$cfg]:-}" ]]; then
                manual_groups["$cfg"]+=",${test_id}"
            else
                manual_groups["$cfg"]="$test_id"
            fi
        elif [[ "$status" == "MISSING" ]]; then
            missing_tests+=("$test_id")
        fi
    done < <(resolve_selected_tests "$RESULTS_DIR" "$RUN_TEST_IDS" "${configs[@]}")

    if [[ ${#missing_tests[@]} -gt 0 ]]; then
        echo "Unknown test ids: ${missing_tests[*]}" >&2
        exit 1
    fi

    if [[ ${#manual_groups[@]} -eq 0 ]]; then
        echo "No matching tests found for ids: $RUN_TEST_IDS" >&2
        exit 1
    fi

    for cfg in "${!manual_groups[@]}"; do
        echo "Running selected tests (${manual_groups[$cfg]}) from $cfg"
        run_framework "$cfg" --tests "${manual_groups[$cfg]}"
        
        # Check results in the execution directory
        if [[ -n "$RESULTS_DIR" && -f "$RESULTS_DIR/results.json" ]]; then
            failures="$(print_failures "$RESULTS_DIR/results.json")"
            if [[ "$failures" != "[]" ]]; then
                overall_status=1
                tail_failed_logs "$RESULTS_DIR/results.json" || true
            fi
        fi
    done
elif [[ -n "$RERUN_EXEC_DIR" ]]; then
    # Rerun specific suite from execution directory
    if [[ ! -d "$RERUN_EXEC_DIR" ]]; then
        echo "Error: Execution directory not found: $RERUN_EXEC_DIR" >&2
        exit 1
    fi

    results_file="$RERUN_EXEC_DIR/results.json"
    if [[ ! -f "$results_file" ]]; then
        echo "Error: results.json not found in $RERUN_EXEC_DIR" >&2
        exit 1
    fi

    # Extract config path and provider for the specified suite
    suite_info="$(python3 "$SCRIPT_DIR/e2e/e2e_shell_helpers.py" get_suite_info "$results_file" "$RERUN_SUITE")" || {
        echo "Error: Suite '$RERUN_SUITE' not found in $results_file" >&2
        exit 1
    }

    IFS='|' read -r cfg_path _ <<< "$suite_info"
    
    echo "Re-running suite: $RERUN_SUITE from $cfg_path"
    # Use the existing execution directory
    run_framework "$cfg_path" --tests "$RERUN_SUITE" --results-dir "$RERUN_EXEC_DIR"
    
    # Check for failures
    if [[ -f "$results_file" ]]; then
        failures="$(print_failures "$results_file")"
        if [[ "$failures" != "[]" ]]; then
            overall_status=1
            tail_failed_logs "$results_file" || true
        fi
    fi
else
    if [[ ${#configs[@]} -eq 0 ]]; then
        echo "No e2e configuration files found." >&2
        exit 1
    fi
    provider_args=()
    filtered_configs=("${configs[@]}")
    if [[ -n "$PROVIDER_FILTER" ]]; then
        provider_args=(--providers "$PROVIDER_FILTER")
        IFS=',' read -ra provider_list <<< "$PROVIDER_FILTER"
        filtered_configs=()
        missing_providers=()
        
        # Get list of available providers
        available_providers=()
        for cfg in "${configs[@]}"; do
            cfg_provider=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1])).get('provider', ''))" "$cfg")
            if [[ -n "$cfg_provider" ]]; then
                # Check if provider is already in array
                provider_exists=0
                for existing in "${available_providers[@]}"; do
                    if [[ "$existing" == "$cfg_provider" ]]; then
                        provider_exists=1
                        break
                    fi
                done
                if [[ $provider_exists -eq 0 ]]; then
                    available_providers+=("$cfg_provider")
                fi
            fi
        done
        
        # Validate that all requested providers exist
        for requested_provider in "${provider_list[@]}"; do
            found=0
            for cfg in "${configs[@]}"; do
                cfg_provider=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1])).get('provider', ''))" "$cfg")
                if [[ "$cfg_provider" == "$requested_provider" ]]; then
                    filtered_configs+=("$cfg")
                    found=1
                    break
                fi
            done
            if [[ $found -eq 0 ]]; then
                missing_providers+=("$requested_provider")
            fi
        done
        
        # Report missing providers and exit before starting any tests
        if [[ ${#missing_providers[@]} -gt 0 ]]; then
            echo "Error: The following providers do not exist: ${missing_providers[*]}" >&2
            echo "Available providers: ${available_providers[*]}" >&2
            exit 1
        fi
        
        if [[ ${#filtered_configs[@]} -eq 0 ]]; then
            echo "No e2e configuration files match provider filter: $PROVIDER_FILTER" >&2
            echo "Available providers: ${available_providers[*]}" >&2
            exit 1
        fi
    elif [[ -n "$CONFIGS_FILTER" ]]; then
        IFS=',' read -ra config_list <<< "$CONFIGS_FILTER"
        filtered_configs=()
        missing_configs=()
        
        # Validate that all requested configs exist before starting any tests
        for requested_config in "${config_list[@]}"; do
            found=0
            for cfg in "${configs[@]}"; do
                cfg_basename=$(basename "$cfg" .json)
                if [[ "$cfg_basename" == "$requested_config" ]]; then
                    filtered_configs+=("$cfg")
                    found=1
                    break
                fi
            done
            if [[ $found -eq 0 ]]; then
                missing_configs+=("$requested_config")
            fi
        done
        
        # Report missing configs and exit before starting any tests
        if [[ ${#missing_configs[@]} -gt 0 ]]; then
            echo "Error: The following config files do not exist: ${missing_configs[*]}" >&2
            available_configs=""
            for cfg in "${configs[@]}"; do
                available_configs+="$(basename "$cfg" .json) "
            done
            echo "Available configs: ${available_configs% }" >&2
            exit 1
        fi
        
        if [[ ${#filtered_configs[@]} -eq 0 ]]; then
            echo "No e2e configuration files match config filter: $CONFIGS_FILTER" >&2
            available_configs=""
            for cfg in "${configs[@]}"; do
                available_configs+="$(basename "$cfg" .json) "
            done
            echo "Available configs: ${available_configs% }" >&2
            exit 1
        fi
    fi
    # Parallel execution across provider configs (if safe)
    if [[ -n "$RESULTS_DIR" ]]; then
        # Sequential when sharing a results dir to avoid collisions
        for cfg in "${filtered_configs[@]}"; do
            echo "Running e2e tests for config: $cfg"
            run_framework "$cfg" "${provider_args[@]}"
            
            if [[ -f "$RESULTS_DIR/results.json" ]]; then
                failures="$(print_failures "$RESULTS_DIR/results.json")"
                if [[ "$failures" != "[]" ]]; then
                    overall_status=1
                    tail_failed_logs "$RESULTS_DIR/results.json" || true
                fi
            fi
        done
    else
        # Default: parallel across configs with isolated results directories
        parallel_root="./tmp/tests/e2e-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$parallel_root"
        declare -A cfg_pids=()
        declare -A cfg_results=()

        # Determine parallelism limit (all configs)
        effective_parallel=${#filtered_configs[@]}
        current_jobs=0

        for cfg in "${filtered_configs[@]}"; do
            cfg_name="$(basename "$cfg" .json)"
            cfg_results_dir="${parallel_root}/${cfg_name}"
            mkdir -p "$cfg_results_dir"

            while [[ $current_jobs -ge $effective_parallel ]]; do
                wait -n
                current_jobs=$((current_jobs - 1))
            done

            # Launch Python process directly without subshell to get correct PID
            db_version_args=()
            if [[ -n "$DB_VERSION" ]]; then
                db_version_args=(--db-version "$DB_VERSION")
            fi
            stop_on_error_args=()
            if [[ "$STOP_ON_ERROR" -eq 1 ]]; then
                stop_on_error_args=(--stop-on-error)
            fi
            
            python3 "$SCRIPT_DIR/e2e/e2e_framework.py" run \
                --config "$cfg" \
                --results-dir "$cfg_results_dir" \
                --parallel "$PARALLEL" \
                "${stop_on_error_args[@]}" \
                "${db_version_args[@]}" \
                "${provider_args[@]}" \
                >"$cfg_results_dir/run.log" 2>&1 &

            pid=$!
            cfg_pids["$pid"]="$cfg"
            cfg_results["$pid"]="$cfg_results_dir"
            current_jobs=$((current_jobs + 1))
            
            # Track for cleanup on interrupt
            BACKGROUND_PIDS+=("$pid")
            
            # Track deployment directories for cleanup
            if [[ -d "$cfg_results_dir/deployments" ]]; then
                for deploy_dir in "$cfg_results_dir/deployments"/*; do
                    if [[ -d "$deploy_dir" ]]; then
                        DEPLOYMENT_DIRS+=("$deploy_dir")
                    fi
                done
            fi
            
            echo "Started $cfg (pid $pid), results: $cfg_results_dir"
        done

        # Monitor progress while jobs are running
        echo ""
        echo "Monitoring progress across ${#cfg_pids[@]} provider(s)..."
        echo "(Press Ctrl+C to interrupt and clean up all deployments)"
        echo ""
        echo "📊 View detailed results in your browser:"
        echo "   file://$(pwd)/tmp/tests/index.html"
        echo ""
        
        # Track completion
        # CRITICAL: This monitoring loop has a common failure mode where processes
        # crash early (e.g., during E2ETestFramework.__init__) but get marked as
        # "COMPLETE" instead of "FAILED". Always check run.log for errors when
        # kill -0 returns false to distinguish between success and crash.
        declare -A completed_pids=()
        total_providers=${#cfg_pids[@]}
        first_iteration=1
        
        while [[ ${#completed_pids[@]} -lt $total_providers ]]; do
            # Update deployment directories list for cleanup
            DEPLOYMENT_DIRS=()
            for cfg_results_dir in "${cfg_results[@]}"; do
                if [[ -d "$cfg_results_dir/deployments" ]]; then
                    # Use nullglob to handle empty directories
                    shopt -s nullglob
                    for deploy_dir in "$cfg_results_dir/deployments"/*; do
                        if [[ -d "$deploy_dir" && -f "$deploy_dir/.exasol.json" ]]; then
                            DEPLOYMENT_DIRS+=("$deploy_dir")
                        fi
                    done
                    shopt -u nullglob
                fi
            done
            
            # Build progress summary for all providers
            progress_lines=()
            
            for pid in "${!cfg_pids[@]}"; do
                cfg="${cfg_pids[$pid]}"
                cfg_name="$(basename "$cfg" .json)"
                cfg_results_dir="${cfg_results[$pid]}"
                results_file="$cfg_results_dir/results.json"
                
                # Check if process completed
                if [[ -n "${completed_pids[$pid]:-}" ]]; then
                    progress_lines+=("  $cfg_name: COMPLETE")
                    continue
                fi
                
                # Check if process is still running
                if ! kill -0 "$pid" 2>/dev/null; then
                    completed_pids["$pid"]=1
                    
                    # CRITICAL: Check if process failed by examining run.log for errors
                    # This prevents false "COMPLETE" status when processes crash early
                    run_log="$cfg_results_dir/run.log"
                    if [[ -f "$run_log" ]] && grep -q "Traceback\|Error:\|RuntimeError\|Exception:" "$run_log" 2>/dev/null; then
                        progress_lines+=("  $cfg_name: FAILED (process crashed)")
                    else
                        progress_lines+=("  $cfg_name: COMPLETE")
                    fi
                    continue
                fi
                
                # Show progress from results.json or run.log
                if [[ -f "$results_file" ]]; then
                    progress_info=$(python3 -c "
import json
try:
    with open('$results_file', 'r') as f:
        data = json.load(f)
        results = data.get('results', [])
        total = len(results)
        completed = sum(1 for r in results if 'success' in r)
        if total > 0:
            print(f'{completed}/{total}')
        else:
            print('0/0')
except:
    print('initializing')
" 2>/dev/null || echo "initializing")
                    progress_lines+=("  $cfg_name: $progress_info")
                else
                    # Parse run.log for progress
                    run_log="$cfg_results_dir/run.log"
                    if [[ -f "$run_log" ]]; then
                        # Count completed tests from log using grep + wc to avoid grep -c issues with leading zeros
                        # shellcheck disable=SC2126
                        completed_count=$(grep "COMPLETED duration:\|FAILED duration:" "$run_log" 2>/dev/null | wc -l || echo "0")
                        # Trim all whitespace including newlines and ensure it's a number
                        completed_count=$(echo "$completed_count" | tr -d ' \n\r\t')
                        completed_count=${completed_count:-0}
                        
                        # Check if tests are running
                        if grep -q "STARTED workflow" "$run_log" 2>/dev/null || true; then
                            if [[ "$completed_count" != "0" && "$completed_count" -gt 0 ]]; then
                                progress_lines+=("  $cfg_name: $completed_count completed, running...")
                            else
                                progress_lines+=("  $cfg_name: running...")
                            fi
                        else
                            progress_lines+=("  $cfg_name: starting...")
                        fi
                    else
                        progress_lines+=("  $cfg_name: initializing...")
                    fi
                fi
            done
            
            # Display progress - each provider on its own line
            if [[ ${#completed_pids[@]} -lt $total_providers ]]; then
                # Move cursor up to overwrite previous lines (skip on first iteration)
                if [[ ${#progress_lines[@]} -gt 0 && $first_iteration -eq 0 ]]; then
                    printf "\033[%dA" "${#progress_lines[@]}"
                fi
                first_iteration=0
                
                # Display each provider status on its own line
                for line in "${progress_lines[@]}"; do
                    printf "\r\033[K%s\n" "$line"
                done
                
                # Regenerate index if new results are available
                python3 "$SCRIPT_DIR/e2e/generate_results_index.py" ./tmp/tests >/dev/null 2>&1 || true
                
                sleep 2
            else
                # Final display
                echo ""
                if [[ ${#progress_lines[@]} -gt 0 ]]; then
                    for line in "${progress_lines[@]}"; do
                        echo "$line"
                    done
                fi
            fi
        done
        
        echo ""
        echo "All providers completed"
        echo ""

        # Wait for jobs and aggregate status
        # CRITICAL: This section determines the final exit status of the script
        # Common failure modes to avoid:
        # 1. Process crashes early -> wait returns non-zero exit code
        # 2. Process succeeds but tests fail -> check results.json for failures
        # 3. Process hangs -> timeout handling in monitoring loop above
        # 4. Log file indicates errors -> check run.log for Python tracebacks
        for pid in "${!cfg_pids[@]}"; do
            cfg="${cfg_pids[$pid]}"
            cfg_results_dir="${cfg_results[$pid]}"
            
            # Wait for the process to finish and capture exit status
            # This is necessary even if kill -0 already detected the process exited
            # to properly reap the zombie process and get the exit code
            wait "$pid" 2>/dev/null
            process_exit_code=$?
            
            # Initialize status as the process exit code
            status=$process_exit_code
            
            # Additional error detection: Check run.log for Python crashes
            # This catches cases where the process exits with code 0 but had internal errors
            run_log="$cfg_results_dir/run.log"
            if [[ -f "$run_log" ]] && grep -q "Traceback\|RuntimeError\|Exception:" "$run_log" 2>/dev/null; then
                echo "Detected Python error in $run_log:"
                grep -A3 -B1 "Traceback\|RuntimeError\|Exception:" "$run_log" | head -10
                status=1
            fi

            # Check results.json for test failures (if it exists)
            results_file="$cfg_results_dir/results.json"
            if [[ -f "$results_file" ]]; then
                failures="$(print_failures "$results_file")"
                if [[ "$failures" != "[]" ]]; then
                    status=1
                    tail_failed_logs "$results_file" || true
                fi
            elif [[ $process_exit_code -eq 0 ]]; then
                # Process exited successfully but no results.json - this is suspicious
                echo "Warning: Process exited with code 0 but no results.json found for $cfg"
                echo "This usually indicates the process crashed during initialization"
                status=1
            fi

            if [[ $status -ne 0 ]]; then
                overall_status=1
                echo "Config failed: $cfg (results: $cfg_results_dir)"
                echo "  Process exit code: $process_exit_code"
                echo "  Check logs: $run_log"
            else
                echo "Config succeeded: $cfg (results: $cfg_results_dir)"
            fi
        done
    fi
fi

# Generate results index page
echo ""
echo "Generating results index..."
if python3 "$SCRIPT_DIR/e2e/generate_results_index.py" ./tmp/tests 2>/dev/null; then
    echo "Results index: file://$(pwd)/tmp/tests/index.html"
    echo ""
    echo "=========================================="
    echo "E2E Test Run Complete"
    echo "=========================================="
    echo ""
    echo "📊 View detailed results in your browser:"
    echo "   file://$(pwd)/tmp/tests/index.html"
    echo ""
else
    echo "Warning: Failed to generate results index" >&2
fi

exit "$overall_status"
