#!/usr/bin/env bash
# Unit tests for run_e2e.sh wrapper script

if [[ -n "${__TEST_RUN_E2E_SH_INCLUDED__:-}" ]]; then return 0; fi
readonly __TEST_RUN_E2E_SH_INCLUDED__=1

set -euo pipefail

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_E2E_SCRIPT="${SCRIPT_DIR}/run_e2e.sh"
RESULTS_DIR_OVERRIDE="${SCRIPT_DIR}/tmp/test-results"
mkdir -p "$RESULTS_DIR_OVERRIDE"
RUN_E2E_BASE=("$RUN_E2E_SCRIPT" --results-dir "$RESULTS_DIR_OVERRIDE")
FRAMEWORK_RESULTS_DIR="${RESULTS_DIR_OVERRIDE}/framework"
mkdir -p "$FRAMEWORK_RESULTS_DIR"

# Source test helper
source "${SCRIPT_DIR}/test_helper.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_feature() {
    local test_name="$1"
    echo "Testing: $test_name"
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ PASS"
}

test_fail() {
    local message="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ FAIL: $message"
}

# Test 1: Help is shown when no arguments provided
test_feature "Help shown with no arguments"
if "${RUN_E2E_BASE[@]}" 2>&1 | grep -q "Usage:"; then
    test_pass
else
    test_fail "Help not shown when no arguments provided"
fi

# Test 2: --list-tests shows all providers
test_feature "--list-tests shows all providers"
output=$("${RUN_E2E_BASE[@]}" --list-tests 2>&1)
if echo "$output" | grep -q "Provider: LIBVIRT" && \
   echo "$output" | grep -q "Total:.*tests"; then
    test_pass
else
    test_fail "--list-tests didn't show expected providers"
fi

# Test 3: --list-tests with provider filter
test_feature "--list-tests libvirt filters correctly"
output=$("${RUN_E2E_BASE[@]}" --list-tests libvirt 2>&1)
if echo "$output" | grep -q "Provider: LIBVIRT" && \
   echo "$output" | grep -q "libvirt-"; then
    test_pass
else
    test_fail "--list-tests libvirt didn't filter correctly"
fi

# Test 4: --list-tests shows suite names as IDs
test_feature "--list-tests shows suite names"
output=$("${RUN_E2E_BASE[@]}" --list-tests libvirt 2>&1)
if echo "$output" | grep -q "libvirt-1n_simple" && \
   echo "$output" | grep -q "Suite.*Resources.*Workflow"; then
    test_pass
else
    test_fail "--list-tests didn't show suite names in table"
fi

# Test 5: --list-tests shows workflow steps
test_feature "--list-tests shows workflow steps"
output=$("${RUN_E2E_BASE[@]}" --list-tests libvirt 2>&1)
if echo "$output" | grep -q "init → deploy"; then
    test_pass
else
    test_fail "--list-tests didn't show workflow steps"
fi

# Test 6: --list-tests shows resource parameters
test_feature "--list-tests shows resource parameters"
output=$("${RUN_E2E_BASE[@]}" --list-tests libvirt 2>&1)
if echo "$output" | grep -q "8GB, 4cpu"; then
    test_pass
else
    test_fail "--list-tests didn't show resource parameters"
fi

# Test 7: --list-tests with invalid provider shows error
test_feature "--list-tests with invalid provider shows error"
output=$("${RUN_E2E_BASE[@]}" --list-tests nonexistent 2>&1 || true)
if echo "$output" | grep -q "No tests found for provider"; then
    test_pass
else
    test_fail "--list-tests didn't show error for invalid provider"
fi

# Test 8: Suite names can be resolved via e2e_framework
test_feature "Suite names resolve correctly via framework"
output=$(python3 -c "
import sys
sys.path.insert(0, 'tests/e2e')
from pathlib import Path
from e2e_framework import E2ETestFramework

framework = E2ETestFramework('tests/e2e/configs/libvirt.json', Path('${FRAMEWORK_RESULTS_DIR}'))
tests_filter = {'libvirt-2n_basic'}
plan = framework.generate_test_plan(only_tests=tests_filter)
print(f'Found {len(plan)} test(s)')
if plan:
    print(f'Suite: {plan[0][\"suite\"]}')
" 2>&1)
if echo "$output" | grep -q "Found 1 test" && echo "$output" | grep -q "Suite: libvirt-2n_basic"; then
    test_pass
else
    test_fail "Suite name didn't resolve via framework: $output"
fi

# Print summary
echo ""
echo "======================================"
echo "Test Summary:"
echo "  Total:  $TESTS_RUN"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "======================================"

if [[ $TESTS_FAILED -gt 0 ]]; then
    rm -rf "$RESULTS_DIR_OVERRIDE"
    exit 1
else
    echo "All tests passed!"
    rm -rf "$RESULTS_DIR_OVERRIDE"
    exit 0
fi
