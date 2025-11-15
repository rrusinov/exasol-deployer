#!/usr/bin/env bash
# Test helper functions for unit testing

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
        echo -e "  Expected: ${YELLOW}$expected${NC}"
        echo -e "  Actual:   ${YELLOW}$actual${NC}"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
        echo -e "  String: ${YELLOW}$haystack${NC}"
        echo -e "  Should contain: ${YELLOW}$needle${NC}"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist: $file}"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [[ -f "$file" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
        return 1
    fi
}

assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory should exist: $dir}"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [[ -d "$dir" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
        return 1
    fi
}

assert_success() {
    local exit_code=$1
    local message="${2:-Command should succeed}"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [[ $exit_code -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
        echo -e "  Exit code: ${YELLOW}$exit_code${NC}"
        return 1
    fi
}

assert_failure() {
    local exit_code=$1
    local message="${2:-Command should fail}"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [[ $exit_code -ne 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
        echo -e "  Exit code: ${YELLOW}$exit_code${NC}"
        return 1
    fi
}

assert_greater_than() {
    local actual="$1"
    local threshold="$2"
    local message="${3:-Value should be greater than threshold}"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [[ "$actual" -gt "$threshold" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
        echo -e "  Actual: ${YELLOW}$actual${NC}"
        echo -e "  Threshold: ${YELLOW}$threshold${NC}"
        return 1
    fi
}

# Test summary
test_summary() {
    echo ""
    echo "========================================="
    echo "Test Summary"
    echo "========================================="
    echo "Total:  $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}

# Setup and teardown helpers
setup_test_dir() {
    # Create unique test directory in /var/tmp for persistence
    local username=$(whoami)
    local test_id=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 8)
    local test_dir="/var/tmp/exasol-deployer-utest-${username}-${test_id}"
    mkdir -p "$test_dir"
    echo "$test_dir"
}

cleanup_test_dir() {
    local test_dir="$1"
    # Only cleanup directories that match our unit test pattern and belong to this user
    if [[ -n "$test_dir" && "$test_dir" =~ ^/var/tmp/exasol-deployer-utest-$(whoami)-[a-zA-Z0-9]{8}$ ]]; then
        rm -rf "$test_dir"
    fi
}

# Global cleanup for any test directories that might be left behind
global_cleanup() {
    local username=$(whoami)
    
    # Clean up any unit test directories in /var/tmp that belong to this user
    find /var/tmp -maxdepth 1 -name "exasol-deployer-utest-${username}-*" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Clean up any e2e test directories in /var/tmp that belong to this user
    find /var/tmp -maxdepth 1 -name "exasol-deployer-e2e-${username}-*" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Also clean up any old directories in /tmp (legacy cleanup)
    find /tmp -maxdepth 1 -name "exasol-test-${username}-*" -type d -exec rm -rf {} + 2>/dev/null || true
    find /tmp -maxdepth 1 -name "exasol_e2e_${username}_*" -type d -exec rm -rf {} + 2>/dev/null || true
    find /tmp -maxdepth 1 -name "exasol_test_results_*" -type d -exec rm -rf {} + 2>/dev/null || true
}

# Register global cleanup to run on script exit
trap global_cleanup EXIT

# Mock function helper
mock_command() {
    local cmd_name="$1"
    local return_value="${2:-0}"
    local output="${3:-}"

    eval "$cmd_name() { echo '$output'; return $return_value; }"
}

# Extract long options handled by a command function
extract_command_options() {
    local file="$1"
    local function_name="$2"
    
    # Get the directory where this script is located
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local python_helper="$script_dir/lib/python/extract_function_options.py"
    
    if [[ ! -f "$python_helper" ]]; then
        echo "Error: Python helper not found: $python_helper" >&2
        return 1
    fi
    
    python3 "$python_helper" "$file" "$function_name"
}
