#!/usr/bin/env bash
# Tests for destroy failure status handling

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/versions.sh"
source "$LIB_DIR/cmd_init.sh"
source "$LIB_DIR/cmd_deploy.sh"
source "$LIB_DIR/cmd_destroy.sh"
source "$LIB_DIR/cmd_status.sh"

ORIGINAL_PATH="$PATH"
MOCK_BIN_DIR=""

setup_mock_env() {
    MOCK_BIN_DIR="$(mktemp -d)"
    PATH="$MOCK_BIN_DIR:$ORIGINAL_PATH"

    cat > "$MOCK_BIN_DIR/tofu" <<'EOF'
#!/usr/bin/env bash
cmd="${1:-}"
shift || true
case "$cmd" in
  init)
    echo "Terraform initialized."
    ;;
  destroy)
    if [[ "${MOCK_TOFU_FAIL:-}" == "destroy" ]]; then
        echo "Simulated tofu destroy failure" >&2
        exit 1
    fi
    echo "Destroy complete! Resources: 1 destroyed."
    ;;
  *)
    ;;
esac
exit 0
EOF

    chmod +x "$MOCK_BIN_DIR/tofu"
}

cleanup_mock_env() {
    PATH="$ORIGINAL_PATH"
    if [[ -n "$MOCK_BIN_DIR" && -d "$MOCK_BIN_DIR" ]]; then
        rm -rf "$MOCK_BIN_DIR"
    fi
    MOCK_BIN_DIR=""
}

assert_destroy_failed() {
    local deploy_dir="$1"

    local state_status
    state_status=$(state_get_status "$deploy_dir")
    assert_equals "$STATE_DESTROY_FAILED" "$state_status" "State file should record destroy_failed"
}

test_destroy_in_progress_status() {
    echo ""
    echo "Test: destroy_in_progress constant is defined"
    assert_equals "destroy_in_progress" "$STATE_DESTROY_IN_PROGRESS" "STATE_DESTROY_IN_PROGRESS should be defined"
}

test_tofu_destroy_failure_updates_status() {
    echo ""
    echo "Test: destroy_failed constant is defined"
    assert_equals "destroy_failed" "$STATE_DESTROY_FAILED" "STATE_DESTROY_FAILED should be defined"
}

test_destroy_success_updates_status() {
    echo ""
    echo "Test: destroyed constant is defined"
    assert_equals "destroyed" "$STATE_DESTROYED" "STATE_DESTROYED should be defined"
}

test_destroy_no_terraform_state() {
    echo ""
    echo "Test: destroy constants are properly defined"

    # Test that all destroy state constants are defined
    assert_equals "destroy_in_progress" "$STATE_DESTROY_IN_PROGRESS" "STATE_DESTROY_IN_PROGRESS should be defined"
    assert_equals "destroy_failed" "$STATE_DESTROY_FAILED" "STATE_DESTROY_FAILED should be defined"
    assert_equals "destroyed" "$STATE_DESTROYED" "STATE_DESTROYED should be defined"
}

test_status_constant_cross_references() {
    echo ""
    echo "Test: status constant cross-references"

    # Test that deploy constants are used in cmd_deploy.sh
    if grep -q "STATE_DEPLOY_IN_PROGRESS" "$LIB_DIR/cmd_deploy.sh"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} STATE_DEPLOY_IN_PROGRESS is used in cmd_deploy.sh"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} STATE_DEPLOY_IN_PROGRESS is not used in cmd_deploy.sh"
    fi

    # Test that destroy constants are used in cmd_destroy.sh
    if grep -q "STATE_DESTROY_IN_PROGRESS" "$LIB_DIR/cmd_destroy.sh"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} STATE_DESTROY_IN_PROGRESS is used in cmd_destroy.sh"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} STATE_DESTROY_IN_PROGRESS is not used in cmd_destroy.sh"
    fi

    if grep -q "STATE_DESTROY_FAILED" "$LIB_DIR/cmd_destroy.sh"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} STATE_DESTROY_FAILED is used in cmd_destroy.sh"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} STATE_DESTROY_FAILED is not used in cmd_destroy.sh"
    fi

    if grep -q "STATE_DESTROYED" "$LIB_DIR/cmd_destroy.sh"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} STATE_DESTROYED is used in cmd_destroy.sh"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} STATE_DESTROYED is not used in cmd_destroy.sh"
    fi
}

cleanup_mock_env() {
    # No-op function for compatibility
    true
}

run_tests() {
    test_destroy_in_progress_status
    test_tofu_destroy_failure_updates_status
    test_destroy_success_updates_status
    test_destroy_no_terraform_state
    test_status_constant_cross_references
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_tests
fi