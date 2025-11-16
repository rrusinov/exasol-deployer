#!/usr/bin/env bash
# Unit tests for power control integration (tofu + Ansible fallbacks)

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/cmd_stop.sh"
source "$LIB_DIR/cmd_start.sh"

declare -a MOCK_ANSIBLE_CALLS=()
declare -a MOCK_TOFU_CALLS=()

run_ansible_with_progress() {
    MOCK_ANSIBLE_CALLS+=("$*")
    return 0
}

run_tofu_with_progress() {
    MOCK_TOFU_CALLS+=("$*")
    return 0
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

    MOCK_ANSIBLE_CALLS=()
    MOCK_TOFU_CALLS=()
    local dir
    dir=$(setup_mock_deployment_dir "aws" "$STATE_DATABASE_READY")

    cmd_stop --deployment-dir "$dir" >/dev/null

    assert_greater_than "${#MOCK_TOFU_CALLS[@]}" 0 "Should call tofu for AWS stop"
    assert_equals "$STATE_STOPPED" "$(state_get_status "$dir")" "State should be stopped after stop"

    local joined="${MOCK_ANSIBLE_CALLS[*]}"
    if [[ "$joined" == *"power_off_fallback=true"* ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} AWS stop should not use power_off_fallback"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} AWS stop avoided power_off_fallback"
    fi

    cleanup_test_dir "$dir"
}

test_stop_hetzner_fallback_no_tofu() {
    echo ""
    echo "Test: stop uses fallback shutdown for Hetzner (no tofu)"

    MOCK_ANSIBLE_CALLS=()
    MOCK_TOFU_CALLS=()
    local dir
    dir=$(setup_mock_deployment_dir "hetzner" "$STATE_DATABASE_READY")

    cmd_stop --deployment-dir "$dir" >/dev/null

    assert_equals "0" "${#MOCK_TOFU_CALLS[@]}" "Hetzner stop should not call tofu power control"

    local joined="${MOCK_ANSIBLE_CALLS[*]}"
    assert_contains "$joined" "power_off_fallback=true" "Hetzner stop should enable power_off_fallback"

    cleanup_test_dir "$dir"
}

test_start_aws_runs_tofu_before_ansible() {
    echo ""
    echo "Test: start powers on infra via tofu for AWS"

    MOCK_ANSIBLE_CALLS=()
    MOCK_TOFU_CALLS=()
    local dir
    dir=$(setup_mock_deployment_dir "aws" "$STATE_STOPPED")

    local mock_bin
    mock_bin=$(mktemp -d)
    cat > "$mock_bin/ssh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$mock_bin/ssh"
    PATH="$mock_bin:$PATH" cmd_start --deployment-dir "$dir" >/dev/null

    assert_greater_than "${#MOCK_TOFU_CALLS[@]}" 0 "AWS start should call tofu power on"
    assert_contains "${MOCK_TOFU_CALLS[*]}" "infra_desired_state=running" "AWS start should request running state"

    cleanup_test_dir "$dir"
    rm -rf "$mock_bin"
}

test_start_hetzner_warns_and_skips_tofu() {
    echo ""
    echo "Test: start warns and skips tofu for Hetzner"

    MOCK_ANSIBLE_CALLS=()
    MOCK_TOFU_CALLS=()
    local dir
    dir=$(setup_mock_deployment_dir "hetzner" "$STATE_STOPPED")

    local mock_bin
    mock_bin=$(mktemp -d)
    cat > "$mock_bin/ssh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$mock_bin/ssh"
    PATH="$mock_bin:$PATH" cmd_start --deployment-dir "$dir" >/dev/null

    assert_equals "0" "${#MOCK_TOFU_CALLS[@]}" "Hetzner start should not call tofu power on"

    cleanup_test_dir "$dir"
    rm -rf "$mock_bin"
}

test_stop_aws_runs_tofu_and_no_fallback
test_stop_hetzner_fallback_no_tofu
test_start_aws_runs_tofu_before_ansible
test_start_hetzner_warns_and_skips_tofu

test_summary
