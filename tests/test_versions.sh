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

create_versions_fixture() {
    local tmp
    tmp=$(mktemp)
    cat >"$tmp" <<'EOF'
[exasol-2025.1.4]
ARCHITECTURE=x86_64
DB_VERSION=@exasol-2025.1.4
DB_DOWNLOAD_URL=https://example.com/releases/exasol-2025.1.4.tar.gz
DB_CHECKSUM=sha256:dummy-db
C4_VERSION=4.28.4
C4_DOWNLOAD_URL=https://example.com/releases/c4/4.28.4/c4
C4_CHECKSUM=sha256:dummy-c4

[default]
VERSION=exasol-2025.1.4

[default-local]
VERSION=exasol-2025.1.4-local
EOF
    echo "$tmp"
}

with_versions_fixture() {
    local fixture
    fixture=$(create_versions_fixture)
    local prev="${EXASOL_VERSIONS_CONFIG:-}"
    EXASOL_VERSIONS_CONFIG="$fixture"
    "$@"
    local rc=$?
    if [[ -n "$prev" ]]; then
        EXASOL_VERSIONS_CONFIG="$prev"
    else
        unset EXASOL_VERSIONS_CONFIG
    fi
    rm -f "$fixture"
    return $rc
}

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

    with_versions_fixture _test_version_exists_impl
}

_test_version_exists_impl() {
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

    with_versions_fixture _test_get_version_config_impl
}

_test_get_version_config_impl() {
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

    with_versions_fixture _test_get_default_version_impl
}

_test_get_default_version_impl() {
    local result
    result=$(get_default_version)

    assert_equals "exasol-2025.1.4" "$result" "Should return default version from config"
}

# Test list_versions
test_list_versions() {
    echo ""
    echo "Test: list_versions"

    with_versions_fixture _test_list_versions_impl
}

_test_list_versions_impl() {
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

test_discover_latest_version() {
    echo ""
    echo "Test: discover_latest_version prefers highest reachable"

    # Backup original function
    local original_probe_version_url
    original_probe_version_url=$(declare -f probe_version_url)

    # Mock probe_version_url to succeed only for patch 6 and 7
    probe_version_url() {
        case "$1" in
            *2025.1.6*|*2025.1.7*) return 0 ;;
            *) return 1 ;;
        esac
    }

    local result
    result=$(discover_latest_version "exasol-2025.1.4" 2025 1 4 "https://example.com/exasol-2025.1.4.tar.gz" "db")
    assert_equals "exasol-2025.1.7" "$result" "Should select highest reachable patch version"

    # Restore original
    eval "$original_probe_version_url"
}

test_discover_latest_version_for_c4() {
    echo ""
    echo "Test: discover_latest_version handles c4 numeric version format"

    # Backup original function
    local original_probe_version_url
    original_probe_version_url=$(declare -f probe_version_url)

    probe_version_url() {
        case "$1" in
            *4.28.5/c4) return 0 ;;
            *) return 1 ;;
        esac
    }

    local result
    result=$(discover_latest_version "4.28.4" 4 28 4 "https://example.com/releases/c4/4.28.4/c4" "c4")
    assert_equals "4.28.5" "$result" "Should increment c4 version without duplicating prefix"

    eval "$original_probe_version_url"
}

test_build_url_for_version_rewrites_path_and_file() {
    echo ""
    echo "Test: build_url_for_version updates folder and filename"

    local template="https://x-up.s3.eu-west-1.amazonaws.com/releases/exasol/linux/x86_64/2025.1.4/exasol-2025.1.4.tar.gz"
    local expected="https://x-up.s3.eu-west-1.amazonaws.com/releases/exasol/linux/x86_64/2025.1.5/exasol-2025.1.5.tar.gz"
    local result
    result=$(build_url_for_version "$template" "exasol-2025.1.4" "exasol-2025.1.5")
    assert_equals "$expected" "$result" "Should rewrite both path segment and filename to new version"
}

test_insert_entries_at_top_formats_cleanly() {
    echo ""
    echo "Test: insert_entries_at_top writes clean blocks and preserves defaults"

    local tmp
    tmp=$(mktemp)
    cat >"$tmp" <<'EOF'
# Header comment

[exasol-2025.1.4]
ARCHITECTURE=x86_64
DB_VERSION=@exasol-2025.1.4
DB_DOWNLOAD_URL=https://example.com/exasol-2025.1.4.tar.gz
DB_CHECKSUM=sha256:db
C4_VERSION=4.28.4
C4_DOWNLOAD_URL=https://example.com/c4/4.28.4/c4
C4_CHECKSUM=sha256:c4

[default]
VERSION=exasol-2025.1.4

[default-local]
VERSION=exasol-2025.1.4-local
EOF

    local new_entry
    new_entry=$(build_version_entry "exasol-2025.1.8" "x86_64" "@exasol-2025.1.8" "https://example.com/exasol-2025.1.8.tar.gz" "sha-db-new" "4.29.0" "https://example.com/c4/4.29.0/c4" "sha-c4-new")
    local local_entry
    local_entry=$(build_version_entry "exasol-2025.1.8-local" "x86_64" "@exasol-2025.1.8" "file:///tmp/exasol-2025.1.8.tar.gz" "sha-db-new" "4.29.0" "file:///tmp/c4" "sha-c4-new")
    local entries
    entries="$new_entry"$'\n\n'"$local_entry"

    insert_entries_at_top "$tmp" "$entries"
    update_default_sections "$tmp" "exasol-2025.1.8" "exasol-2025.1.8-local"

    # Assert order: header, blank, new entry, blank, local entry, blank, original first section...
    local head
    head=$(head -n 5 "$tmp")
    assert_contains "$head" "[exasol-2025.1.8]" "New version should be first after header"

    if grep -q '\\n' "$tmp"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} File should not contain literal \\n markers"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} File does not contain literal \\n markers"
    fi

    # Defaults updated
    local def
    def=$(awk '/^\[default\]/{flag=1;next}/^\[/{flag=0}flag' "$tmp" | tr -d '\r\n')
    local def_local
    def_local=$(awk '/^\[default-local\]/{flag=1;next}/^\[/{flag=0}flag' "$tmp" | tr -d '\r\n')
    assert_equals "VERSION=exasol-2025.1.8" "$def" "default should point to new version"
    assert_equals "VERSION=exasol-2025.1.8-local" "$def_local" "default-local should point to new local version"

    rm -f "$tmp"
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
test_discover_latest_version
test_discover_latest_version_for_c4
test_build_url_for_version_rewrites_path_and_file
test_insert_entries_at_top_formats_cleanly

# Show summary
test_summary
