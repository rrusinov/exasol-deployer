#!/bin/bash
# Unit tests for lib/versions.sh

# Get script directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

# Source the libraries
LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/versions.sh"

echo "Testing versions.sh functions"
echo "========================================="

# Test validate_version_format
test_validate_version_format() {
    echo ""
    echo "Test: validate_version_format"

    # Valid formats
    validate_version_format "exasol-2025.1.4" 2>/dev/null
    assert_success $? "Should accept valid version format: exasol-2025.1.4"

    validate_version_format "exasol-2025.1.4-arm64" 2>/dev/null
    assert_success $? "Should accept valid ARM64 version format: exasol-2025.1.4-arm64"

    validate_version_format "exasol-2025.1.4-local" 2>/dev/null
    assert_success $? "Should accept valid local version format: exasol-2025.1.4-local"

    validate_version_format "exasol-2025.1.4-arm64-local" 2>/dev/null
    assert_success $? "Should accept valid ARM64 local version format: exasol-2025.1.4-arm64-local"

    # Invalid formats
    validate_version_format "8.0.0" 2>/dev/null
    assert_failure $? "Should reject version without name prefix"

    validate_version_format "8.0-x86_64" 2>/dev/null
    assert_failure $? "Should reject invalid version number"

    validate_version_format "exasol-2025.1.4-x86_64" 2>/dev/null
    assert_failure $? "Should reject explicit x86_64 suffix (should be implicit)"
}

# Test parse_version (Note: parse_version logic may need updates based on new format)
test_parse_version() {
    echo ""
    echo "Test: parse_version"

    # Note: This test demonstrates the current parse_version behavior
    # The function may need updating to work with the new naming convention
    local result

    # These tests check current behavior - update if parse_version logic changes
    result=$(parse_version "exasol-2025.1.4" "db_version")
    assert_equals "exasol" "$result" "Should extract first component as db_version"

    result=$(parse_version "exasol-2025.1.4" "architecture")
    assert_equals "2025.1.4" "$result" "Should extract second component"
}

# Test version_exists (using actual versions.conf)
test_version_exists() {
    echo ""
    echo "Test: version_exists"

    # This test depends on actual versions.conf content
    if version_exists "exasol-2025.1.4"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should find existing version in versions.conf"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should find existing version in versions.conf"
    fi

    if ! version_exists "nonexistent-1.0.0"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should not find non-existent version"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should not find non-existent version"
    fi
}

# Test get_version_config
test_get_version_config() {
    echo ""
    echo "Test: get_version_config"

    local result

    result=$(get_version_config "exasol-2025.1.4" "ARCHITECTURE")
    assert_equals "x86_64" "$result" "Should get architecture from version config"

    result=$(get_version_config "exasol-2025.1.4" "DEFAULT_INSTANCE_TYPE")
    assert_equals "m6idn.large" "$result" "Should get default instance type from version config"

    result=$(get_version_config "exasol-2025.1.4" "C4_VERSION")
    assert_equals "4.28.3" "$result" "Should get C4 version from config"
}

# Test get_default_version
test_get_default_version() {
    echo ""
    echo "Test: get_default_version"

    local result
    result=$(get_default_version)

    assert_equals "exasol-2025.1.4" "$result" "Should return default version from config"
}

# Test list_versions
test_list_versions() {
    echo ""
    echo "Test: list_versions"

    local versions
    versions=$(list_versions)

    assert_contains "$versions" "exasol-2025.1.4" "Should list available version"
}

# Run all tests
test_validate_version_format
test_parse_version
test_version_exists
test_get_version_config
test_get_default_version
test_list_versions

# Show summary
test_summary
