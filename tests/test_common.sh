#!/usr/bin/env bash
# Unit tests for lib/common.sh

# Get script directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

# Source the libraries we're testing
LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"

echo "Testing common.sh functions"
echo "========================================="

# Test validate_directory
test_validate_directory() {
    echo ""
    echo "Test: validate_directory"

    # Test with valid directory
    local test_dir=$(setup_test_dir)
    local result
    result=$(validate_directory "$test_dir")
    assert_equals "$test_dir" "$result" "Should validate existing directory"

    # Test with relative path
    (cd /tmp && result=$(validate_directory "./exasol-test-$$"))
    assert_contains "$result" "/tmp/exasol-test-$$" "Should convert relative to absolute path"

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

    local test_dir=$(setup_test_dir)
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

    local test_dir=$(setup_test_dir)
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

    local test_dir=$(setup_test_dir)

    # Create mock state file
    cat > "$test_dir/.exasol.json" << 'EOF'
{
  "status": "initialized",
  "db_version": "exasol-2025.1.4",
  "architecture": "x86_64",
  "cloud_provider": "aws"
}
EOF

    # Create mock variables file
    cat > "$test_dir/variables.auto.tfvars" << 'EOF'
instance_type = "m6idn.large"
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

    # Check if INFO.json was created
    if [[ -f "$test_dir/INFO.json" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should create INFO.json file"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should create INFO.json file"
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

        local status_cmd="exasol status --deployment-dir $test_dir"
        if [[ "$content" == *"$status_cmd"* ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} INFO.txt should reference status command"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} INFO.txt should reference status command"
        fi

        local tofu_cmd="tofu -chdir='$test_dir' output"
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

    # Check INFO.json content
    if [[ -f "$test_dir/INFO.json" ]]; then
        local status_cmd_json
        status_cmd_json=$(jq -r '.commands.status' "$test_dir/INFO.json")
        if [[ "$status_cmd_json" == "exasol status --deployment-dir $test_dir" ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} INFO.json should expose status command"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} INFO.json should expose status command"
        fi

        local creds_file
        creds_file=$(jq -r '.files.credentials' "$test_dir/INFO.json")
        if [[ "$creds_file" == ".credentials.json" ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} INFO.json should list credentials file"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} INFO.json should list credentials file"
       	fi
    fi

    cleanup_test_dir "$test_dir"
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

# Show summary
test_summary
