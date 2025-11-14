#!/usr/bin/env bash
# shellcheck disable=SC2155
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    if [[ -n "${__EXASOL_RUN_E2E_SH_INCLUDED__:-}" ]]; then
        return 0
    fi
    readonly __EXASOL_RUN_E2E_SH_INCLUDED__=1
fi

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: tests/run_e2e.sh [options]

Options:
  --provider <name[,name...]>   Run only tests for the specified cloud provider(s)
  --parallel <n>                Override parallelism (0 = auto/all tests)
  --results-dir <path>          Directory where e2e results are stored (default: tmp/e2e-results)
  --rerun <failed|DEPLOYMENT>   Rerun all failed tests from the latest results or a specific deployment id
  --results-file <path>         Use this results file when selecting tests to rerun
  --list-test(s)                List all known tests grouped by provider
  --run-test <id[,id...]>       Execute only the specified tests (ids from --list-test)
  -h, --help                    Show this help

Examples:
  tests/run_e2e.sh --provider aws
  tests/run_e2e.sh --rerun failed
  tests/run_e2e.sh --rerun aws-basic-c1-m6idn-large
  tests/run_e2e.sh --list-tests
  tests/run_e2e.sh --run-test aws-basic-aws-cluster-size_1-...
EOF
}

RESULTS_DIR="tmp/e2e-results"
PROVIDER_FILTER=""
PARALLEL=0
RERUN_MODE=""
RERUN_RESULTS_FILE=""
SPECIFIC_RERUN_IDS=""
LIST_TESTS=0
RUN_TEST_IDS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --provider)
            PROVIDER_FILTER="$2"
            shift 2
            ;;
        --parallel)
            PARALLEL="$2"
            shift 2
            ;;
        --results-dir)
            RESULTS_DIR="$2"
            shift 2
            ;;
        --rerun)
            if [[ "$2" == "failed" ]]; then
                RERUN_MODE="failed"
            else
                RERUN_MODE="custom"
                SPECIFIC_RERUN_IDS="$2"
            fi
            shift 2
            ;;
        --results-file)
            RERUN_RESULTS_FILE="$2"
            shift 2
            ;;
        --list-test|--list-tests)
            LIST_TESTS=1
            shift
            ;;
        --run-test|--run--test)
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

mkdir -p "$RESULTS_DIR"

discover_configs() {
    find tests/e2e/configs -maxdepth 1 -type f -name '*.json' | sort
}

count_result_files() {
    find "$RESULTS_DIR" -maxdepth 1 -type f -name 'test_results_*.json' 2>/dev/null | wc -l | tr -d ' '
}

latest_results_file() {
    if compgen -G "$RESULTS_DIR/test_results_*.json" > /dev/null; then
        ls -t "$RESULTS_DIR"/test_results_*.json | head -n 1
    elif [[ -f "$RESULTS_DIR/latest_results.json" ]]; then
        echo "$RESULTS_DIR/latest_results.json"
    else
        echo ""
    fi
}

collect_rerun_tests() {
    local mode="$1"
    local ids="$2"
    local source_file="$3"
    python3 - <<PY "$source_file" "$mode" "$ids"
import json
import sys

path = sys.argv[1]
mode = sys.argv[2]
ids = {entry.strip() for entry in sys.argv[3].split(',') if entry.strip()}

with open(path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)

for result in data.get('results', []):
    deployment_id = result.get('deployment_id')
    if not deployment_id:
        continue
    if mode == 'failed' and result.get('success'):
        continue
    if mode == 'custom' and deployment_id not in ids:
        continue
    config = result.get('config_path')
    if not config:
        continue
    print(f"{config}|{deployment_id}")
PY
}

run_framework() {
    local config_file="$1"
    shift
    python3 tests/e2e/e2e_framework.py run \
        --config "$config_file" \
        --results-dir "$RESULTS_DIR" \
        --parallel "$PARALLEL" \
        "$@"
}

print_failures() {
    local results_file="$1"
    python3 - <<'PY' "$results_file"
import json
import sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)

failed = []
for result in data.get('results', []):
    if not result.get('success'):
        failed.append({
            'id': result.get('deployment_id'),
            'suite': result.get('suite'),
            'provider': result.get('provider'),
            'log_file': result.get('log_file'),
            'retained_dir': result.get('retained_deployment_dir')
        })

print(json.dumps(failed))
PY
}

tail_failed_logs() {
    local results_file="$1"
    local failures_json
    failures_json="$(print_failures "$results_file")"
    if [[ "$failures_json" == "[]" ]]; then
        return 0
    fi
    python3 - <<'PY' "$failures_json"
import json
import subprocess
import os
import sys

failures = json.loads(sys.argv[1])
for entry in failures:
    identifier = entry["id"]
    provider = entry.get("provider")
    suite = entry.get("suite")
    log_path = entry.get("log_file")
    retained_dir = entry.get("retained_dir")
    header = f"[{identifier}] provider={provider} suite={suite}"
    print("=" * len(header))
    print(header)
    print("=" * len(header))
    if log_path and os.path.isfile(log_path):
        print(f"-- Last 100 log lines from {log_path} --")
        subprocess.run(["tail", "-n", "100", log_path], check=False)
    else:
        print(f"No log file found at {log_path}")
    if retained_dir:
        print(f"Retained deployment directory: {retained_dir}")
    else:
        print("Deployment directory was cleaned up.")
    print()
PY
}

list_tests_for_configs() {
    local results_dir="$1"
    shift
    python3 - "$results_dir" "$@" <<'PY'
import sys
from pathlib import Path
from collections import defaultdict
from tests.e2e.e2e_framework import E2ETestFramework

results_dir = Path(sys.argv[1])
configs = sys.argv[2:]

if not configs:
    print("No e2e configuration files found.", file=sys.stderr)
    sys.exit(1)

tests_by_provider = defaultdict(list)
for cfg in configs:
    framework = E2ETestFramework(cfg, results_dir)
    for test in framework.generate_test_plan():
        tests_by_provider[test.get('provider', 'unknown')].append({
            'deployment_id': test.get('deployment_id'),
            'suite': test.get('suite'),
            'config': cfg
        })

if not tests_by_provider:
    print("No tests available.")
    sys.exit(0)

for provider in sorted(tests_by_provider):
    print(f"Provider: {provider}")
    for entry in sorted(tests_by_provider[provider], key=lambda item: item['deployment_id']):
        print(f"  - {entry['deployment_id']} (suite={entry['suite']}, config={entry['config']})")
    print()
PY
}

resolve_selected_tests() {
    local results_dir="$1"
    local ids="$2"
    shift 2
    python3 - "$results_dir" "$ids" "$@" <<'PY'
import sys
from pathlib import Path
from tests.e2e.e2e_framework import E2ETestFramework

results_dir = Path(sys.argv[1])
requested = {value.strip() for value in sys.argv[2].split(',') if value.strip()}
configs = sys.argv[3:]

if not requested:
    sys.exit(0)

found = set()
for cfg in configs:
    framework = E2ETestFramework(cfg, results_dir)
    for test in framework.generate_test_plan():
        deployment_id = test.get('deployment_id')
        if deployment_id in requested:
            provider = test.get('provider', '')
            suite = test.get('suite', '')
            print(f"FOUND|{deployment_id}|{cfg}|{provider}|{suite}")
            found.add(deployment_id)

for missing in sorted(requested - found):
    print(f"MISSING|{missing}")
PY
}

overall_status=0

mapfile -t configs < <(discover_configs)

if [[ "$LIST_TESTS" -eq 1 ]]; then
    if [[ ${#configs[@]} -eq 0 ]]; then
        echo "No e2e configuration files found." >&2
        exit 1
    fi
    list_tests_for_configs "$RESULTS_DIR" "${configs[@]}"
    exit 0
fi

if [[ -n "$RUN_TEST_IDS" ]]; then
    if [[ ${#configs[@]} -eq 0 ]]; then
        echo "No e2e configuration files found." >&2
        exit 1
    fi

    declare -A manual_groups=()
    missing_tests=()

    while IFS='|' read -r status test_id cfg provider suite; do
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
        before_count="$(count_result_files)"
        run_framework "$cfg" --tests "${manual_groups[$cfg]}"
        after_count="$(count_result_files)"
        if [[ "$after_count" -le "$before_count" ]]; then
            continue
        fi
        newest="$(latest_results_file)"
        if [[ -n "$newest" ]]; then
            failures="$(print_failures "$newest")"
            if [[ "$failures" != "[]" ]]; then
                overall_status=1
                tail_failed_logs "$newest" || true
            fi
        fi
    done
elif [[ -n "$RERUN_MODE" ]]; then
    rerun_file="$RERUN_RESULTS_FILE"
    if [[ -z "$rerun_file" ]]; then
        rerun_file="$(latest_results_file)"
    fi
    if [[ -z "$rerun_file" || ! -f "$rerun_file" ]]; then
        echo "No results file available for rerun." >&2
        exit 1
    fi

    declare -A rerun_groups=()
    while IFS='|' read -r cfg test_id; do
        [[ -z "$cfg" || -z "$test_id" ]] && continue
        if [[ -n "${rerun_groups[$cfg]:-}" ]]; then
            rerun_groups["$cfg"]="${rerun_groups[$cfg]},$test_id"
        else
            rerun_groups["$cfg"]="$test_id"
        fi
    done < <(collect_rerun_tests "$RERUN_MODE" "$SPECIFIC_RERUN_IDS" "$rerun_file")

    if [[ ${#rerun_groups[@]} -eq 0 ]]; then
        echo "No tests matched rerun criteria."
        exit 0
    fi

    for cfg in "${!rerun_groups[@]}"; do
        tests_filter="${rerun_groups[$cfg]}"
        echo "Re-running ${tests_filter} from $cfg"
        before_count="$(count_result_files)"
        run_framework "$cfg" --tests "$tests_filter"
        after_count="$(count_result_files)"
        if [[ "$after_count" -le "$before_count" ]]; then
            continue
        fi
        newest="$(latest_results_file)"
        if [[ -n "$newest" ]]; then
            failures="$(print_failures "$newest")"
            if [[ "$failures" != "[]" ]]; then
                tail_failed_logs "$newest" || true
                overall_status=1
            fi
        fi
    done
else
    if [[ ${#configs[@]} -eq 0 ]]; then
        echo "No e2e configuration files found." >&2
        exit 1
    fi
    provider_args=()
    if [[ -n "$PROVIDER_FILTER" ]]; then
        provider_args=(--providers "$PROVIDER_FILTER")
    fi

    for cfg in "${configs[@]}"; do
        echo "Running e2e tests for config: $cfg"
        before_count="$(count_result_files)"
        run_framework "$cfg" "${provider_args[@]}"
        after_count="$(count_result_files)"
        if [[ "$after_count" -le "$before_count" ]]; then
            continue
        fi
        newest="$(latest_results_file)"
        if [[ -n "$newest" ]]; then
            failures="$(print_failures "$newest")"
            if [[ "$failures" != "[]" ]]; then
                overall_status=1
                tail_failed_logs "$newest" || true
            fi
        fi
    done
fi

exit "$overall_status"
