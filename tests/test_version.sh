#!/bin/bash
# Unit tests for version functionality
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo "[PASS] $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo "[FAIL] $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo "========================================"
echo "  Version Functionality Tests"
echo "========================================"
echo

# Test 1: Local dev version shows 'dev'
echo "TEST: Local development version shows 'dev'"
TESTS_RUN=$((TESTS_RUN + 1))
output=$(./exasol version </dev/null)
if [[ "$output" == *"vdev"* ]]; then
    pass "Local version shows 'dev'"
else
    fail "Expected 'vdev' in output"
fi

# Test 2: Version command works
echo "TEST: Version command executes successfully"
TESTS_RUN=$((TESTS_RUN + 1))
if ./exasol version </dev/null >/dev/null 2>&1; then
    pass "Version command executes"
else
    fail "Version command failed"
fi

# Test 3: Version output format
echo "TEST: Version output has correct format"
TESTS_RUN=$((TESTS_RUN + 1))
output=$(./exasol version </dev/null)
if [[ "$output" == *"Exasol Cloud Deployer v"* ]]; then
    pass "Version output has correct format"
else
    fail "Version output format incorrect"
fi
if [[ "$output" == *"Built with OpenTofu and Ansible"* ]]; then
    pass "Version output includes build info"
else
    fail "Version output missing build info"
fi

# Test 4: Environment variable override
echo "TEST: EXASOL_VERSION environment variable overrides version"
TESTS_RUN=$((TESTS_RUN + 1))
output=$(EXASOL_VERSION="test-override" ./exasol version </dev/null)
if [[ "$output" == *"vtest-override"* ]]; then
    pass "Environment variable override works"
else
    fail "Environment variable override failed"
fi

# Test 5: --version flag works
echo "TEST: --version flag works"
TESTS_RUN=$((TESTS_RUN + 1))
output=$(./exasol --version </dev/null)
if [[ "$output" == *"Exasol Cloud Deployer"* ]]; then
    pass "--version flag works"
else
    fail "--version flag failed"
fi

# Test 6: version command and --version flag produce same output
echo "TEST: version command and --version flag produce same output"
TESTS_RUN=$((TESTS_RUN + 1))
version_output=$(./exasol version </dev/null)
flag_output=$(./exasol --version </dev/null)
if [[ "$version_output" == "$flag_output" ]]; then
    pass "Both produce identical output"
else
    fail "Output differs"
fi

# Test 7: Build injects version
echo "TEST: Build process injects version into exasol script"
TESTS_RUN=$((TESTS_RUN + 1))
if [[ ! -f "build/exasol-deployer.sh" ]]; then
    echo "  (Skipping - no pre-built installer found)"
else
    temp_dir=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$temp_dir'" EXIT
    
    extract_dir="$temp_dir/extract"
    if ./build/exasol-deployer.sh --extract-only "$extract_dir" >/dev/null 2>&1; then
        version_line=$(grep "readonly SCRIPT_VERSION_RAW=" "$extract_dir/exasol" || true)
        if [[ "$version_line" == *"__EXASOL_VERSION__"* ]]; then
            fail "Version placeholder not replaced"
        else
            pass "Version injected into built script"
        fi
    else
        fail "Failed to extract installer"
    fi
fi

echo
echo "========================================"
echo "  Test Results"
echo "========================================"
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi
