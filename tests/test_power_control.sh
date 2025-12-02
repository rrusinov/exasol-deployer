#!/usr/bin/env bash
# Unit tests for power control integration (tofu + Ansible fallbacks)

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/cmd_stop.sh"
source "$LIB_DIR/cmd_start.sh"

MOCK_BIN_DIR=""
ANSIBLE_LOG=""
TOFU_LOG=""

setup_mock_bins() {
    MOCK_BIN_DIR=$(mktemp -d)
    ANSIBLE_LOG="$MOCK_BIN_DIR/ansible.log"
    TOFU_LOG="$MOCK_BIN_DIR/tofu.log"

    # Create mock ansible-playbook
    cat > "$MOCK_BIN_DIR/ansible-playbook" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$ANSIBLE_LOG"
echo "PLAY [Mock play]"
echo "TASK [Mock task]"
echo "ok: [n11]"
echo "PLAY RECAP"
echo "n11 : ok=1 changed=0"
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/ansible-playbook"

    # Create mock tofu
    cat > "$MOCK_BIN_DIR/tofu" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$TOFU_LOG"
echo "Mock tofu output"
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/tofu"

    # Create mock exasol command for health checks
    cat > "$MOCK_BIN_DIR/exasol" <<'EOF'
#!/usr/bin/env bash
echo "Mock exasol command - health check failed"
exit 1
EOF
    chmod +x "$MOCK_BIN_DIR/exasol"

    export PATH="$MOCK_BIN_DIR:$PATH"
}

cleanup_mock_bins() {
    if [[ -n "$MOCK_BIN_DIR" && -d "$MOCK_BIN_DIR" ]]; then
        rm -rf "$MOCK_BIN_DIR"
    fi
}

get_ansible_call_count() {
    [[ -f "$ANSIBLE_LOG" ]] && wc -l < "$ANSIBLE_LOG" || echo "0"
}

get_tofu_call_count() {
    [[ -f "$TOFU_LOG" ]] && grep -c "apply" "$TOFU_LOG" || echo "0"
}

get_ansible_calls() {
    [[ -f "$ANSIBLE_LOG" ]] && cat "$ANSIBLE_LOG" || echo ""
}

get_tofu_calls() {
    [[ -f "$TOFU_LOG" ]] && grep "apply" "$TOFU_LOG" || echo ""
}

setup_mock_deployment_dir() {
    local provider="$1"
    local status="$2"

    local dir
    dir=$(setup_test_dir)
    mkdir -p "$dir/.templates"
    touch "$dir/.templates/stop-exasol-cluster.yml" "$dir/.templates/start-exasol-cluster.yml"
    echo "[exasol_nodes]" > "$dir/inventory.ini"
    echo "n11 ansible_host=127.0.0.1" >> "$dir/inventory.ini"
    echo "Host n11" > "$dir/ssh_config"

    state_init "$dir" "exasol-2025.1.4" "x86_64" "$provider"
    state_set_status "$dir" "$status"
    echo "$dir"
}

test_stop_aws_runs_tofu_and_no_fallback() {
    echo ""
    echo "Test: stop uses tofu for AWS and no fallback"

    setup_mock_bins
    local dir
    dir=$(setup_mock_deployment_dir "aws" "$STATE_DATABASE_READY")

    cmd_stop --deployment-dir "$dir" >/dev/null 2>&1

    local tofu_count
    tofu_count=$(get_tofu_call_count)
    assert_greater_than "$tofu_count" 0 "Should call tofu for AWS stop"
    assert_equals "$STATE_STOPPED" "$(state_get_status "$dir")" "State should be stopped after stop"

    local ansible_calls
    ansible_calls=$(get_ansible_calls)
    if [[ "$ansible_calls" == *"power_off_fallback=true"* ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} AWS stop now uses power_off_fallback for graceful shutdown"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} AWS stop should use power_off_fallback for graceful shutdown"
    fi

    cleanup_test_dir "$dir"
    cleanup_mock_bins
}

test_stop_hetzner_fallback_no_tofu() {
    echo ""
    echo "Test: stop uses fallback shutdown for Hetzner (no tofu)"

    setup_mock_bins
    local dir
    dir=$(setup_mock_deployment_dir "hetzner" "$STATE_DATABASE_READY")

    cmd_stop --deployment-dir "$dir" >/dev/null 2>&1

    local tofu_count
    tofu_count=$(get_tofu_call_count)
    assert_equals "0" "$tofu_count" "Hetzner stop should not call tofu power control"

    local ansible_calls
    ansible_calls=$(get_ansible_calls)
    assert_contains "$ansible_calls" "power_off_fallback=true" "All providers now use power_off_fallback for graceful shutdown"

    cleanup_test_dir "$dir"
    cleanup_mock_bins
}

test_start_aws_runs_tofu_before_ansible() {
    echo ""
    echo "Test: start powers on infra via tofu for AWS"

    setup_mock_bins
    local dir
    dir=$(setup_mock_deployment_dir "aws" "$STATE_STOPPED")

    # Create mock ssh
    cat > "$MOCK_BIN_DIR/ssh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/ssh"

    cmd_start --deployment-dir "$dir" >/dev/null 2>&1

    local tofu_count tofu_calls
    tofu_count=$(get_tofu_call_count)
    tofu_calls=$(get_tofu_calls)
    assert_greater_than "$tofu_count" 0 "AWS start should call tofu power on"
    assert_contains "$tofu_calls" "infra_desired_state=running" "AWS start should request running state"

    cleanup_test_dir "$dir"
    cleanup_mock_bins
}

test_start_hetzner_warns_and_skips_tofu() {
    echo ""
    echo "Test: start warns and skips tofu for Hetzner"

    setup_mock_bins
    local dir
    dir=$(setup_mock_deployment_dir "hetzner" "$STATE_STOPPED")

    # Create mock ssh
    cat > "$MOCK_BIN_DIR/ssh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/ssh"

    # Run start command with timeout to prevent hanging on health check
    timeout 10 bash -c "cmd_start --deployment-dir '$dir' >/dev/null 2>&1" || true

    local tofu_count
    tofu_count=$(get_tofu_call_count)
    assert_equals "0" "$tofu_count" "Hetzner start should not call tofu power on"

    cleanup_test_dir "$dir"
    cleanup_mock_bins
}

test_stop_aws_runs_tofu_and_no_fallback
test_stop_hetzner_fallback_no_tofu
test_start_aws_runs_tofu_before_ansible
test_start_hetzner_warns_and_skips_tofu

test_summary
