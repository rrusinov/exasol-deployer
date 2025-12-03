#!/usr/bin/env bash
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

    result=$(get_version_config "exasol-2025.1.4" "C4_VERSION")
    assert_equals "4.28.4" "$result" "Should get C4 version from config"
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

test_list_versions_with_architecture_output() {
    echo ""
    echo "Test: list_versions_with_availability includes architecture"

    local test_dir
    test_dir=$(setup_test_dir)
    local fake_db="$test_dir/db.tar.gz"
    local fake_c4="$test_dir/c4"
    touch "$fake_db" "$fake_c4"

    local versions_override="$test_dir/versions.conf"
    cat > "$versions_override" <<EOF
[exasol-test-arch]
ARCHITECTURE=arm64
DB_VERSION=@exasol-test-arch
DB_DOWNLOAD_URL=file://$fake_db
DB_CHECKSUM=sha256:$(sha256sum "$fake_db" | awk '{print $1}')
C4_VERSION=dev
C4_DOWNLOAD_URL=file://$fake_c4
C4_CHECKSUM=sha256:$(sha256sum "$fake_c4" | awk '{print $1}')

[default]
VERSION=exasol-test-arch
EOF

    local previous_versions_config="${EXASOL_VERSIONS_CONFIG:-}"
    EXASOL_VERSIONS_CONFIG="$versions_override"

    local output
    output=$(list_versions_with_availability)

    if [[ -n "$previous_versions_config" ]]; then
        EXASOL_VERSIONS_CONFIG="$previous_versions_config"
    else
        unset EXASOL_VERSIONS_CONFIG
    fi

    assert_contains "$output" "[+] exasol-test-arch [arm64]" "Should show architecture in list output"

    cleanup_test_dir "$test_dir"
}

# Test get_instance_types_config_path
test_get_instance_types_config_path() {
    echo ""
    echo "Test: get_instance_types_config_path"

    local result
    result=$(get_instance_types_config_path)

    # Should return path to instance-types.conf in script root
    if [[ "$result" == */instance-types.conf ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should return path to instance-types.conf"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should return path to instance-types.conf, got: $result"
    fi
}

# Test get_instance_type_default
test_get_instance_type_default() {
    echo ""
    echo "Test: get_instance_type_default"

    local result

    # Test AWS x86_64
    result=$(get_instance_type_default "aws" "x86_64")
    assert_equals "t3a.medium" "$result" "Should get AWS x86_64 default instance type"

    # Test AWS arm64
    result=$(get_instance_type_default "aws" "arm64")
    assert_equals "t4g.medium" "$result" "Should get AWS arm64 default instance type"

    # Test DigitalOcean x86_64
    result=$(get_instance_type_default "digitalocean" "x86_64")
    assert_equals "s-2vcpu-4gb" "$result" "Should get DigitalOcean x86_64 default instance type"

    # Test libvirt x86_64
    result=$(get_instance_type_default "libvirt" "x86_64")
    assert_equals "libvirt-custom" "$result" "Should get libvirt x86_64 default instance type"

    # Test non-existent provider
    result=$(get_instance_type_default "nonexistent" "x86_64")
    assert_equals "" "$result" "Should return empty for non-existent provider"
}

# Run all tests
test_validate_version_format
test_parse_version
test_version_exists
test_get_version_config
test_get_default_version
test_list_versions
test_get_instance_types_config_path
test_get_instance_type_default

# Show summary
test_summary
