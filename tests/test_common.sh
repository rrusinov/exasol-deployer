#!/usr/bin/env bash
# Unit tests for lib/common.sh

# Get script directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "$TEST_DIR/test_helper.sh"

# Source the libraries we're testing
LIB_DIR="$TEST_DIR/../lib"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=lib/state.sh
source "$LIB_DIR/state.sh"

echo "Testing common.sh functions"
echo "========================================="

# Test validate_directory
test_validate_directory() {
    echo ""
    echo "Test: validate_directory"

    # Test with valid directory
    local test_dir
    test_dir=$(setup_test_dir)
    local result
    result=$(validate_directory "$test_dir")
    assert_equals "$test_dir" "$result" "Should validate existing directory"

    # Test with relative path
    test_dir=$(setup_test_dir)
    local relative_dir="./$(basename "$test_dir")"
    pushd /var/tmp > /dev/null || return 1
    result=$(validate_directory "$relative_dir")
    popd > /dev/null || return 1
    # Check that the result has the expected pattern (username + random ID)
    local username
    username=$(whoami)
    local normalized_result="${result//\/.\//\/}"
    local expected_pattern="^/(var/tmp|tmp)/exasol-deployer-utest-${username}-[a-zA-Z0-9]{6}-[a-zA-Z0-9]{6}$"
    if [[ "$normalized_result" =~ $expected_pattern ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should validate relative directory path"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should validate relative directory path"
        echo "  String: $normalized_result"
        echo "  Expected pattern: /var/tmp/exasol-deployer-utest-${username}-XXXXXX-XXXXXX (or /tmp/... fallback)"
    fi

    cleanup_test_dir "$test_dir"
}

# Test ensure_directory
test_ensure_directory() {
    echo ""
    echo "Test: ensure_directory"

    local test_dir="/tmp/exasol-test-ensure-$$"
    ensure_directory "$test_dir"
    assert_dir_exists "$test_dir" "Should create directory if it doesn't exist"

    # Test that it doesn't fail if directory exists
    ensure_directory "$test_dir"
    assert_dir_exists "$test_dir" "Should not fail if directory already exists"

    rm -rf "$test_dir"
}

# Test command_exists
test_command_exists() {
    echo ""
    echo "Test: command_exists"

    # Test with existing command
    if command_exists bash; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should find existing command (bash)"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should find existing command (bash)"
    fi

    # Test with non-existing command
    if ! command_exists nonexistent_command_xyz; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should not find non-existing command"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should not find non-existing command"
    fi
}

# Test get_timestamp
test_get_timestamp() {
    echo ""
    echo "Test: get_timestamp"

    local timestamp
    timestamp=$(get_timestamp)

    # Check format (ISO 8601-ish)
    if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should return timestamp in correct format"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should return timestamp in correct format"
        echo -e "  Got: ${YELLOW}$timestamp${NC}"
    fi
}

# Test generate_password
test_generate_password() {
    echo ""
    echo "Test: generate_password"

    local password
    password=$(generate_password 16)

    # Check length
    local length=${#password}
    assert_equals "16" "$length" "Should generate password of correct length"

    # Check that two passwords are different (randomness)
    local password2
    password2=$(generate_password 16)
    if [[ "$password" != "$password2" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should generate different passwords"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should generate different passwords"
    fi
}

# Test parse_config_file
test_parse_config_file() {
    echo ""
    echo "Test: parse_config_file"

    local test_dir
    test_dir=$(setup_test_dir)
    local config_file="$test_dir/test.conf"

    cat > "$config_file" << 'EOF'
[section1]
KEY1=value1
KEY2=value2

[section2]
KEY1=different_value
EOF

    local result
    result=$(parse_config_file "$config_file" "section1" "KEY1")
    assert_equals "value1" "$result" "Should parse config value from section1"

    result=$(parse_config_file "$config_file" "section2" "KEY1")
    assert_equals "different_value" "$result" "Should parse config value from section2"

    cleanup_test_dir "$test_dir"
}

# Test get_config_sections
test_get_config_sections() {
    echo ""
    echo "Test: get_config_sections"

    local test_dir
    test_dir=$(setup_test_dir)
    local config_file="$test_dir/test.conf"

    cat > "$config_file" << 'EOF'
[section1]
KEY=value

[section2]
KEY=value

[section3]
KEY=value
EOF

    local sections
    sections=$(get_config_sections "$config_file")

    assert_contains "$sections" "section1" "Should find section1"
    assert_contains "$sections" "section2" "Should find section2"
    assert_contains "$sections" "section3" "Should find section3"

    cleanup_test_dir "$test_dir"
}

# Test generate_info_files
test_generate_info_files() {
    echo ""
    echo "Test: generate_info_files"

    local test_dir
    test_dir=$(setup_test_dir)

    # Create mock state file
    cat > "$test_dir/.exasol.json" << 'EOF'
{
  "status": "initialized",
  "db_version": "exasol-2025.1.8",
  "architecture": "x86_64",
  "cloud_provider": "aws"
}
EOF

    # Create mock variables file
    cat > "$test_dir/variables.auto.tfvars" << 'EOF'
instance_type = "t3a.large"
node_count = 2
data_volume_size = 100
EOF

    # Generate info files
    generate_info_files "$test_dir"

    # Check if INFO.txt was created
    if [[ -f "$test_dir/INFO.txt" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should create INFO.txt file"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should create INFO.txt file"
    fi

    # Check INFO.txt content
    if [[ -f "$test_dir/INFO.txt" ]]; then
        local content
        content=$(cat "$test_dir/INFO.txt")

        if [[ "$content" == *"Exasol Deployment Entry Point"* ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} INFO.txt should mention entry point"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} INFO.txt should mention entry point"
        fi

        local cd_cmd="cd $test_dir"
        if [[ "$content" == *"$cd_cmd"* ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} INFO.txt should include cd command"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} INFO.txt should include cd command"
        fi

        local status_cmd="exasol status --show-details"
        if [[ "$content" == *"$status_cmd"* ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} INFO.txt should reference status command"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} INFO.txt should reference status command"
        fi

        local deploy_cmd="exasol deploy"
        if [[ "$content" == *"$deploy_cmd"* ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} INFO.txt should reference deploy command"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} INFO.txt should reference deploy command"
        fi

        local destroy_cmd="exasol destroy"
        if [[ "$content" == *"$destroy_cmd"* ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} INFO.txt should reference destroy command"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} INFO.txt should reference destroy command"
        fi

        local tofu_cmd="tofu output"
        if [[ "$content" == *"$tofu_cmd"* ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} INFO.txt should reference terraform outputs command"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} INFO.txt should reference terraform outputs command"
        fi

        if [[ "$content" == *".credentials.json"* ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} INFO.txt should mention credentials file"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} INFO.txt should mention credentials file"
        fi
    fi

    cleanup_test_dir "$test_dir"
}

test_categorize_ansible_phase() {
    echo ""
    echo "Test: categorize_ansible_phase"

    local phase
    phase=$(categorize_ansible_phase "Download Exasol database tarball")
    assert_equals "download" "$phase" "Should detect download tasks"

    phase=$(categorize_ansible_phase "Install required system packages via apt")
    assert_equals "install" "$phase" "Should detect install tasks"

    phase=$(categorize_ansible_phase "Gathering Facts")
    assert_equals "prepare" "$phase" "Should default to prepare for other tasks"
}

test_extract_plan_total_resources() {
    echo ""
    echo "Test: extract_plan_total_resources"

    local total
    total=$(extract_plan_total_resources "Plan: 3 to add, 2 to change, 1 to destroy.")
    assert_equals "6" "$total" "Should sum add+change+destroy"

    total=$(extract_plan_total_resources "Plan: 0 to add, 0 to change, 4 to destroy.")
    assert_equals "4" "$total" "Should handle destroy-only plan"

    if extract_plan_total_resources "No changes. Infrastructure is up-to-date." >/dev/null; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Non-plan line should not return success"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Non-plan line should not return success"
    fi
}

# Run all tests
test_validate_directory
test_ensure_directory
test_command_exists
test_get_timestamp
test_generate_password
test_parse_config_file
test_get_config_sections
test_generate_info_files
test_categorize_ansible_phase
test_extract_plan_total_resources

# Show summary
test_summary
