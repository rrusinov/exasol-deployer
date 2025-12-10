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

# Test 2: Non-existent config validation
test_feature "Non-existent config validation"
output=$("${RUN_E2E_BASE[@]}" --configs nonexistent 2>&1 || true)
if echo "$output" | grep -q "The following config files do not exist: nonexistent"; then
    test_pass
else
    test_fail "Non-existent config not detected. Output: $output"
fi

# Test 3: Non-existent provider validation
test_feature "Non-existent provider validation"
output=$("${RUN_E2E_BASE[@]}" --provider nonexistent 2>&1 || true)
if echo "$output" | grep -q "The following providers do not exist: nonexistent"; then
    test_pass
else
    test_fail "Non-existent provider not detected. Output: $output"
fi

# Test 4: Empty config validation
test_feature "Empty config validation"
output=$("${RUN_E2E_BASE[@]}" --configs "" 2>&1 || true)
if echo "$output" | grep -q "Error: --configs cannot be empty"; then
    test_pass
else
    test_fail "Empty config not detected. Output: $output"
fi

# Test 5: Empty provider validation
test_feature "Empty provider validation"
output=$("${RUN_E2E_BASE[@]}" --provider "" 2>&1 || true)
if echo "$output" | grep -q "Error: --provider cannot be empty"; then
    test_pass
else
    test_fail "Empty provider not detected. Output: $output"
fi

# Test 6: Invalid parallel value validation
test_feature "Invalid parallel value validation"
output=$("${RUN_E2E_BASE[@]}" --parallel abc 2>&1 || true)
if echo "$output" | grep -q "Error: --parallel must be a non-negative integer"; then
    test_pass
else
    test_fail "Invalid parallel value not detected. Output: $output"
fi

# Test 7: Multiple non-existent configs validation
test_feature "Multiple non-existent configs validation"
output=$("${RUN_E2E_BASE[@]}" --configs aws,nonexistent1,nonexistent2 2>&1 || true)
if echo "$output" | grep -q "The following config files do not exist: nonexistent1 nonexistent2"; then
    test_pass
else
    test_fail "Multiple non-existent configs not detected properly. Output: $output"
fi

# Test 8: Mixed valid and invalid configs validation
test_feature "Mixed valid and invalid configs validation"
output=$("${RUN_E2E_BASE[@]}" --configs aws,badconfig 2>&1 || true)
if echo "$output" | grep -q "The following config files do not exist: badconfig" && echo "$output" | grep -q "Available configs:"; then
    test_pass
else
    test_fail "Mixed valid/invalid configs not handled properly"
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

# Test 2b: --list-tests all shows all providers
test_feature "--list-tests all shows all providers"
output=$("${RUN_E2E_BASE[@]}" --list-tests all 2>&1)
if echo "$output" | grep -q "Provider: LIBVIRT" && \
   echo "$output" | grep -q "Total:.*tests"; then
    test_pass
else
    test_fail "--list-tests all didn't show expected providers"
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
if echo "$output" | grep -q "The following providers do not exist: nonexistent"; then
    test_pass
else
    test_fail "--list-tests didn't show error for invalid provider. Output: $output"
fi

# Test 8: --configs option filters correctly
test_feature "--configs option filters correctly"
output=$("${RUN_E2E_BASE[@]}" --configs libvirt --list-tests 2>&1)
if echo "$output" | grep -q "Provider: LIBVIRT" && \
   echo "$output" | grep -q "libvirt-" && \
   ! echo "$output" | grep -q "Provider: AWS"; then
    test_pass
else
    test_fail "--configs libvirt didn't filter correctly"
fi

# Test 9: --configs with multiple configs
test_feature "--configs with multiple configs"
output=$("${RUN_E2E_BASE[@]}" --configs libvirt,aws --list-tests 2>&1)
if echo "$output" | grep -q "Provider: LIBVIRT" && \
   echo "$output" | grep -q "Provider: AWS"; then
    test_pass
else
    test_fail "--configs libvirt,aws didn't show both providers"
fi

# Test 10: --configs with invalid config shows error
test_feature "--configs with invalid config shows error"
output=$("${RUN_E2E_BASE[@]}" --configs nonexistent 2>&1 || true)
if echo "$output" | grep -q "The following config files do not exist: nonexistent" && \
   echo "$output" | grep -q "Available configs:"; then
    test_pass
else
    test_fail "--configs didn't show error for invalid config. Output: $output"
fi

# Test 11: --provider and --configs mutual exclusion
test_feature "--provider and --configs mutual exclusion"
output=$("${RUN_E2E_BASE[@]}" --provider aws --configs libvirt 2>&1 || true)
if echo "$output" | grep -q "Error: --provider and --configs cannot be used together"; then
    test_pass
else
    test_fail "--provider and --configs didn't show mutual exclusion error"
fi

# Test 12: --configs aws-arm64 shows ARM64 tests
test_feature "--configs aws-arm64 shows ARM64 tests"
output=$("${RUN_E2E_BASE[@]}" --configs aws-arm64 --list-tests 2>&1)
if echo "$output" | grep -q "aws-arm64-" && \
   echo "$output" | grep -q "t4g"; then
    test_pass
else
    test_fail "--configs aws-arm64 didn't show ARM64 tests"
fi

# Test 13: Suite names can be resolved via e2e_framework
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
