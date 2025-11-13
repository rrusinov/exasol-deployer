#!/usr/bin/env bash
# Unit tests for lib/state.sh

# Get script directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

# Source the libraries
LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"

echo "Testing state.sh functions"
echo "========================================="

# Test state_init
test_state_init() {
    echo ""
    echo "Test: state_init"

    local test_dir=$(setup_test_dir)

    state_init "$test_dir" "exasol-2025.1.4" "x86_64"
    assert_success $? "Should initialize state successfully"

    assert_file_exists "$test_dir/.exasol.json" "Should create state file"

    # Verify state file content
    local status=$(state_read "$test_dir" "status")
    assert_equals "initialized" "$status" "Should set initial status to 'initialized'"

    local version=$(state_read "$test_dir" "db_version")
    assert_equals "exasol-2025.1.4" "$version" "Should store db_version"

    local arch=$(state_read "$test_dir" "architecture")
    assert_equals "x86_64" "$arch" "Should store architecture"

    cleanup_test_dir "$test_dir"
}

# Test is_deployment_directory
test_is_deployment_directory() {
    echo ""
    echo "Test: is_deployment_directory"

    local test_dir=$(setup_test_dir)

    if ! is_deployment_directory "$test_dir"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should return false for non-deployment directory"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should return false for non-deployment directory"
    fi

    state_init "$test_dir" "exasol-2025.1.4" "x86_64"

    if is_deployment_directory "$test_dir"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should return true for deployment directory"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should return true for deployment directory"
    fi

    cleanup_test_dir "$test_dir"
}

# Test state_set_status
test_state_set_status() {
    echo ""
    echo "Test: state_set_status"

    local test_dir=$(setup_test_dir)
    state_init "$test_dir" "exasol-2025.1.4" "x86_64"

    state_set_status "$test_dir" "deployment_in_progress"
    local status=$(state_read "$test_dir" "status")
    assert_equals "deployment_in_progress" "$status" "Should update status"

    state_set_status "$test_dir" "database_ready"
    status=$(state_read "$test_dir" "status")
    assert_equals "database_ready" "$status" "Should update status again"

    cleanup_test_dir "$test_dir"
}

# Test lock_create and lock_exists
test_lock_operations() {
    echo ""
    echo "Test: lock operations"

    local test_dir=$(setup_test_dir)

    if ! lock_exists "$test_dir"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should not find lock initially"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should not find lock initially"
    fi

    lock_create "$test_dir" "test_operation"
    assert_success $? "Should create lock"

    if lock_exists "$test_dir"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should find lock after creation"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should find lock after creation"
    fi

    assert_file_exists "$test_dir/.exasolLock.json" "Should create lock file"

    local operation=$(lock_info "$test_dir" "operation")
    assert_equals "test_operation" "$operation" "Should store operation in lock"

    lock_remove "$test_dir"
    if ! lock_exists "$test_dir"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should not find lock after removal"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should not find lock after removal"
    fi

    cleanup_test_dir "$test_dir"
}

test_stale_lock_cleanup() {
    echo ""
    echo "Test: stale lock cleanup"

    local test_dir
    test_dir=$(setup_test_dir)
    state_init "$test_dir" "exasol-2025.1.4" "x86_64"
    state_set_status "$test_dir" "database_ready"

    local pid_max
    pid_max=$(cat /proc/sys/kernel/pid_max 2>/dev/null || echo 4194304)
    local fake_pid=$((pid_max + 1000))

    cat > "$test_dir/.exasolLock.json" <<EOF
{
  "operation": "deploy",
  "pid": $fake_pid,
  "started_at": "$(get_timestamp)",
  "hostname": "test-host"
}
EOF

    local status
    status=$(get_deployment_status "$test_dir")
    assert_equals "database_ready" "$status" "Should ignore stale lock and return actual status"

    if ! lock_exists "$test_dir"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should remove stale lock file"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should remove stale lock file"
    fi

    cleanup_test_dir "$test_dir"
}

# Test write_variables_file
test_write_variables_file() {
    echo ""
    echo "Test: write_variables_file"

    local test_dir=$(setup_test_dir)

    write_variables_file "$test_dir" \
        "aws_region=us-west-2" \
        "node_count=4" \
        "instance_type=c7a.16xlarge"

    assert_file_exists "$test_dir/variables.auto.tfvars" "Should create variables file"

    local content=$(cat "$test_dir/variables.auto.tfvars")
    assert_contains "$content" "aws_region = \"us-west-2\"" "Should write string variable"
    assert_contains "$content" "node_count = 4" "Should write numeric variable"
    assert_contains "$content" "instance_type = \"c7a.16xlarge\"" "Should write instance type"

    cleanup_test_dir "$test_dir"
}

# Run all tests
test_state_init
test_is_deployment_directory
test_state_set_status
test_lock_operations
test_stale_lock_cleanup
test_write_variables_file

# Show summary
test_summary
