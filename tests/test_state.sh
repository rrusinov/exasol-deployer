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

    state_set_status "$test_dir" "deploy_in_progress"
    local status=$(state_read "$test_dir" "status")
    assert_equals "deploy_in_progress" "$status" "Should update status"

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

# Test status constant consistency
test_status_constant_consistency() {
    echo ""
    echo "Test: status constant consistency"

    # Test that all status constants follow naming conventions
    assert_equals "initialized" "$STATE_INITIALIZED" "STATE_INITIALIZED should be 'initialized'"
    assert_equals "deploy_in_progress" "$STATE_DEPLOY_IN_PROGRESS" "STATE_DEPLOY_IN_PROGRESS should be 'deploy_in_progress'"
    assert_equals "deployment_failed" "$STATE_DEPLOYMENT_FAILED" "STATE_DEPLOYMENT_FAILED should be 'deployment_failed'"
    assert_equals "database_connection_failed" "$STATE_DATABASE_CONNECTION_FAILED" "STATE_DATABASE_CONNECTION_FAILED should be 'database_connection_failed'"
    assert_equals "database_ready" "$STATE_DATABASE_READY" "STATE_DATABASE_READY should be 'database_ready'"
    assert_equals "destroy_in_progress" "$STATE_DESTROY_IN_PROGRESS" "STATE_DESTROY_IN_PROGRESS should be 'destroy_in_progress'"
    assert_equals "destroy_failed" "$STATE_DESTROY_FAILED" "STATE_DESTROY_FAILED should be 'destroy_failed'"
    assert_equals "destroyed" "$STATE_DESTROYED" "STATE_DESTROYED should be 'destroyed'"
    assert_equals "stopped" "$STATE_STOPPED" "STATE_STOPPED should be 'stopped'"
    assert_equals "start_in_progress" "$STATE_START_IN_PROGRESS" "STATE_START_IN_PROGRESS should be 'start_in_progress'"
    assert_equals "start_failed" "$STATE_START_FAILED" "STATE_START_FAILED should be 'start_failed'"
    assert_equals "stop_in_progress" "$STATE_STOP_IN_PROGRESS" "STATE_STOP_IN_PROGRESS should be 'stop_in_progress'"
    assert_equals "stop_failed" "$STATE_STOP_FAILED" "STATE_STOP_FAILED should be 'stop_failed'"

    # Test that in_progress status values follow ${command}_in_progress pattern
    assert_contains "$STATE_DEPLOY_IN_PROGRESS" "_in_progress" "Deploy in-progress status should contain '_in_progress'"
    assert_contains "$STATE_DESTROY_IN_PROGRESS" "_in_progress" "Destroy in-progress status should contain '_in_progress'"
    assert_contains "$STATE_START_IN_PROGRESS" "_in_progress" "Start in-progress status should contain '_in_progress'"
    assert_contains "$STATE_STOP_IN_PROGRESS" "_in_progress" "Stop in-progress status should contain '_in_progress'"

    # Test that in_progress status values start with command name
    local deploy_prefix="${STATE_DEPLOY_IN_PROGRESS%_in_progress}"
    local destroy_prefix="${STATE_DESTROY_IN_PROGRESS%_in_progress}"
    local start_prefix="${STATE_START_IN_PROGRESS%_in_progress}"
    local stop_prefix="${STATE_STOP_IN_PROGRESS%_in_progress}"
    assert_equals "deploy" "$deploy_prefix" "Deploy in-progress status should start with 'deploy'"
    assert_equals "destroy" "$destroy_prefix" "Destroy in-progress status should start with 'destroy'"
    assert_equals "start" "$start_prefix" "Start in-progress status should start with 'start'"
    assert_equals "stop" "$stop_prefix" "Stop in-progress status should start with 'stop'"
}

# Test status command integration consistency
test_status_command_integration() {
    echo ""
    echo "Test: status command integration consistency"

    local test_dir=$(setup_test_dir)
    state_init "$test_dir" "exasol-2025.1.4" "x86_64"

    # Test that get_deployment_status returns expected values
    local status=$(get_deployment_status "$test_dir")
    assert_equals "initialized" "$status" "get_deployment_status should return 'initialized' for new deployment"

    # Test with lock file (simulating in-progress operation)
    lock_create "$test_dir" "deploy"
    status=$(get_deployment_status "$test_dir")
    assert_equals "deploy_in_progress" "$status" "get_deployment_status should return 'deploy_in_progress' with deploy lock"

    lock_remove "$test_dir"
    lock_create "$test_dir" "destroy"
    status=$(get_deployment_status "$test_dir")
    assert_equals "destroy_in_progress" "$status" "get_deployment_status should return 'destroy_in_progress' with destroy lock"

    lock_remove "$test_dir"

    # Test that status matches constants when set directly
    state_set_status "$test_dir" "$STATE_DEPLOY_IN_PROGRESS"
    status=$(get_deployment_status "$test_dir")
    assert_equals "$STATE_DEPLOY_IN_PROGRESS" "$status" "Direct status setting should match constant"

    state_set_status "$test_dir" "$STATE_DESTROY_IN_PROGRESS"
    status=$(get_deployment_status "$test_dir")
    assert_equals "$STATE_DESTROY_IN_PROGRESS" "$status" "Direct status setting should match constant"

    cleanup_test_dir "$test_dir"
}

# Test validate_start_transition with valid states
test_validate_start_transition_valid() {
    echo ""
    echo "Test: validate_start_transition with valid states"

    # Should allow start from 'stopped' state
    if validate_start_transition "$STATE_STOPPED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should allow start from stopped state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should allow start from stopped state"
    fi

    # Should allow start from 'start_failed' state (retry)
    if validate_start_transition "$STATE_START_FAILED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should allow start from start_failed state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should allow start from start_failed state"
    fi
}

# Test validate_start_transition with invalid states
test_validate_start_transition_invalid() {
    echo ""
    echo "Test: validate_start_transition with invalid states"

    # Should reject start from 'database_ready' state
    if ! validate_start_transition "$STATE_DATABASE_READY"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should reject start from database_ready state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should reject start from database_ready state"
    fi

    # Should reject start from 'deploy_in_progress' state
    if ! validate_start_transition "$STATE_DEPLOY_IN_PROGRESS"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should reject start from deploy_in_progress state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should reject start from deploy_in_progress state"
    fi

    # Should reject start from 'destroyed' state
    if ! validate_start_transition "$STATE_DESTROYED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should reject start from destroyed state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should reject start from destroyed state"
    fi

    # Should reject start from 'initialized' state
    if ! validate_start_transition "$STATE_INITIALIZED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should reject start from initialized state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should reject start from initialized state"
    fi
}

# Test validate_stop_transition with valid states
test_validate_stop_transition_valid() {
    echo ""
    echo "Test: validate_stop_transition with valid states"

    # Should allow stop from 'database_ready' state
    if validate_stop_transition "$STATE_DATABASE_READY"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should allow stop from database_ready state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should allow stop from database_ready state"
    fi

    # Should allow stop from 'database_connection_failed' state
    if validate_stop_transition "$STATE_DATABASE_CONNECTION_FAILED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should allow stop from database_connection_failed state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should allow stop from database_connection_failed state"
    fi

    # Should allow stop from 'stop_failed' state (retry)
    if validate_stop_transition "$STATE_STOP_FAILED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should allow stop from stop_failed state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should allow stop from stop_failed state"
    fi
}

# Test validate_stop_transition with invalid states
test_validate_stop_transition_invalid() {
    echo ""
    echo "Test: validate_stop_transition with invalid states"

    # Should reject stop from 'stopped' state
    if ! validate_stop_transition "$STATE_STOPPED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should reject stop from stopped state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should reject stop from stopped state"
    fi

    # Should reject stop from 'deploy_in_progress' state
    if ! validate_stop_transition "$STATE_DEPLOY_IN_PROGRESS"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should reject stop from deploy_in_progress state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should reject stop from deploy_in_progress state"
    fi

    # Should reject stop from 'destroyed' state
    if ! validate_stop_transition "$STATE_DESTROYED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should reject stop from destroyed state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should reject stop from destroyed state"
    fi

    # Should reject stop from 'initialized' state
    if ! validate_stop_transition "$STATE_INITIALIZED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should reject stop from initialized state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should reject stop from initialized state"
    fi
}

# Test complete deployment lifecycle workflow
test_complete_deployment_lifecycle() {
    echo ""
    echo "Test: complete deployment lifecycle workflow"

    local test_dir=$(setup_test_dir)
    state_init "$test_dir" "exasol-2025.1.4" "x86_64"

    # 1. Start: initialized → deploy → database_ready
    local status=$(state_get_status "$test_dir")
    assert_equals "initialized" "$status" "Should start in initialized state"

    state_set_status "$test_dir" "$STATE_DATABASE_READY"
    status=$(state_get_status "$test_dir")
    assert_equals "database_ready" "$status" "Should transition to database_ready after deploy"

    # 2. Normal stop/start cycle
    if validate_stop_transition "$status"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Can stop from database_ready state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Can stop from database_ready state"
    fi

    state_set_status "$test_dir" "$STATE_STOPPED"
    status=$(state_get_status "$test_dir")
    assert_equals "stopped" "$status" "Should transition to stopped"

    if validate_start_transition "$status"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Can start from stopped state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Can start from stopped state"
    fi

    state_set_status "$test_dir" "$STATE_DATABASE_READY"
    status=$(state_get_status "$test_dir")
    assert_equals "database_ready" "$status" "Should transition back to database_ready after start"

    # 3. Multiple stop/start cycles
    for i in {1..3}; do
        state_set_status "$test_dir" "$STATE_STOPPED"
        status=$(state_get_status "$test_dir")
        assert_equals "stopped" "$status" "Cycle $i: Should be stopped"

        state_set_status "$test_dir" "$STATE_DATABASE_READY"
        status=$(state_get_status "$test_dir")
        assert_equals "database_ready" "$status" "Cycle $i: Should be database_ready"
    done

    # 4. Final destroy
    state_set_status "$test_dir" "$STATE_DESTROYED"
    status=$(state_get_status "$test_dir")
    assert_equals "destroyed" "$status" "Should transition to destroyed"

    cleanup_test_dir "$test_dir"
}

# Test failure and retry scenarios
test_failure_and_retry_scenarios() {
    echo ""
    echo "Test: failure and retry scenarios"

    local test_dir=$(setup_test_dir)
    state_init "$test_dir" "exasol-2025.1.4" "x86_64"

    # Scenario 1: Start fails, retry succeeds
    state_set_status "$test_dir" "$STATE_STOPPED"
    state_set_status "$test_dir" "$STATE_START_FAILED"

    if validate_start_transition "$STATE_START_FAILED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Can retry start after start_failed"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Can retry start after start_failed"
    fi

    state_set_status "$test_dir" "$STATE_DATABASE_READY"
    local status=$(state_get_status "$test_dir")
    assert_equals "database_ready" "$status" "Should be database_ready after successful retry"

    # Scenario 2: Stop fails, retry succeeds
    state_set_status "$test_dir" "$STATE_STOP_FAILED"

    if validate_stop_transition "$STATE_STOP_FAILED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Can retry stop after stop_failed"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Can retry stop after stop_failed"
    fi

    state_set_status "$test_dir" "$STATE_STOPPED"
    status=$(state_get_status "$test_dir")
    assert_equals "stopped" "$status" "Should be stopped after successful retry"

    # Scenario 3: Connection failure → can still stop
    state_set_status "$test_dir" "$STATE_DATABASE_CONNECTION_FAILED"

    if validate_stop_transition "$STATE_DATABASE_CONNECTION_FAILED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Can stop from database_connection_failed state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Can stop from database_connection_failed state"
    fi

    cleanup_test_dir "$test_dir"
}

# Test invalid operation sequences
test_invalid_operation_sequences() {
    echo ""
    echo "Test: invalid operation sequences"

    local test_dir=$(setup_test_dir)
    state_init "$test_dir" "exasol-2025.1.4" "x86_64"

    # Cannot start from initialized (never deployed)
    if ! validate_start_transition "$STATE_INITIALIZED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Cannot start from initialized state (never deployed)"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Cannot start from initialized state (never deployed)"
    fi

    # Cannot stop from initialized
    if ! validate_stop_transition "$STATE_INITIALIZED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Cannot stop from initialized state"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Cannot stop from initialized state"
    fi

    # Cannot start/stop during other operations
    if ! validate_start_transition "$STATE_DEPLOY_IN_PROGRESS"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Cannot start during deploy_in_progress"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Cannot start during deploy_in_progress"
    fi

    if ! validate_stop_transition "$STATE_DESTROY_IN_PROGRESS"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Cannot stop during destroy_in_progress"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Cannot stop during destroy_in_progress"
    fi

    # Cannot operate on destroyed deployment
    if ! validate_start_transition "$STATE_DESTROYED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Cannot start destroyed deployment"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Cannot start destroyed deployment"
    fi

    if ! validate_stop_transition "$STATE_DESTROYED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Cannot stop destroyed deployment"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Cannot stop destroyed deployment"
    fi

    # Double operations (already in target state)
    if ! validate_start_transition "$STATE_DATABASE_READY"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Cannot start when already running"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Cannot start when already running"
    fi

    if ! validate_stop_transition "$STATE_STOPPED"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Cannot stop when already stopped"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Cannot stop when already stopped"
    fi

    cleanup_test_dir "$test_dir"
}

test_lock_permission_denied() {
    echo ""
    echo "Test: lock_create fails on non-writable directory"

    local test_dir
    test_dir=$(setup_test_dir)

    chmod 500 "$test_dir"

    if lock_create "$test_dir" "nop"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} lock_create should fail when directory not writable"
        lock_remove "$test_dir"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} lock_create fails on permission error"
    fi

    chmod 700 "$test_dir"
    cleanup_test_dir "$test_dir"
}

test_lock_race_and_cleanup() {
    echo ""
    echo "Test: lock contention and cleanup across processes"

    local test_dir
    test_dir=$(setup_test_dir)

    # Hold lock in background
    (
        lock_create "$test_dir" "proc1" || exit 1
        sleep 3
    ) &
    local holder=$!
    sleep 1

    # While lock held, second acquisition should fail
    if lock_create "$test_dir" "proc2"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Second lock acquisition should fail while held"
        lock_remove "$test_dir"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Second lock blocked while held"
    fi

    # Terminate holder and clean stale lock, then acquire
    kill "$holder" 2>/dev/null || true
    wait "$holder" 2>/dev/null || true

    # Simulate stale lock with an unreachable PID to avoid PID reuse issues
    local fake_pid
    fake_pid=$(( $(cat /proc/sys/kernel/pid_max 2>/dev/null || echo 4194304) + 1000 ))
    cat > "$test_dir/$LOCK_FILE" <<EOF
{"operation":"proc1","pid":$fake_pid,"started_at":"","hostname":""}
EOF

    cleanup_stale_lock "$test_dir"

    if lock_create "$test_dir" "proc3"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Lock acquired after stale cleanup"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Lock should be acquirable after cleanup"
    fi

    lock_remove "$test_dir"
    cleanup_test_dir "$test_dir"
}

test_lock_retry_after_manual_stale() {
    echo ""
    echo "Test: lock_create retries after cleaning manual stale lock"

    local test_dir
    test_dir=$(setup_test_dir)

    # Write a manual stale lock with dead PID
    local fake_pid
    fake_pid=$(( $(cat /proc/sys/kernel/pid_max 2>/dev/null || echo 4194304) + 123 ))
    cat > "$test_dir/$LOCK_FILE" <<EOF
{"operation":"manual","pid":$fake_pid,"started_at":"","hostname":""}
EOF

    if lock_create "$test_dir" "retry-op"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} lock_create succeeded after cleaning manual stale lock"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} lock_create should succeed after cleaning manual stale lock"
    fi

    lock_remove "$test_dir"
    cleanup_test_dir "$test_dir"
}

test_lock_contention_transient() {
    echo ""
    echo "Test: lock_create fails while another process holds lock, then succeeds after release"

    local test_dir
    test_dir=$(setup_test_dir)

    (
        lock_create "$test_dir" "holder" || exit 1
        sleep 2
        lock_remove "$test_dir"
    ) &
    local holder=$!
    sleep 0.5

    # Should fail while held
    if lock_create "$test_dir" "contender"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Lock should block while another process holds it"
        lock_remove "$test_dir"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Lock blocked while held"
    fi

    wait "$holder" 2>/dev/null || true
    cleanup_stale_lock "$test_dir"

    # Should succeed after release
    if lock_create "$test_dir" "after_release"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Lock acquired after holder released"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Lock should be acquirable after holder released"
    fi

    lock_remove "$test_dir"
    cleanup_test_dir "$test_dir"
}

# Run all tests
test_state_init
test_is_deployment_directory
test_state_set_status
test_lock_operations
test_stale_lock_cleanup
test_lock_race_and_cleanup
test_lock_retry_after_manual_stale
test_lock_contention_transient
test_write_variables_file
test_status_constant_consistency
test_status_command_integration
test_validate_start_transition_valid
test_validate_start_transition_invalid
test_validate_stop_transition_valid
test_validate_stop_transition_invalid
test_complete_deployment_lifecycle
test_failure_and_retry_scenarios
test_invalid_operation_sequences
test_lock_permission_denied

# Show summary
test_summary
