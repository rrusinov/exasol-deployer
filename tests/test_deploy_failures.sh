#!/usr/bin/env bash
# Tests for deployment failure status handling

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/versions.sh"
source "$LIB_DIR/cmd_init.sh"
source "$LIB_DIR/cmd_deploy.sh"
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
    if [[ "${MOCK_TOFU_FAIL:-}" == "init" ]]; then
        echo "Simulated tofu init failure" >&2
        exit 1
    fi
    echo "Terraform initialized."
    ;;
  plan)
    if [[ "${MOCK_TOFU_FAIL:-}" == "plan" ]]; then
        echo "Simulated tofu plan failure" >&2
        exit 1
    fi
    echo "Plan: 0 to add, 0 to change, 0 to destroy."
    ;;
  apply)
    if [[ "${MOCK_TOFU_FAIL:-}" == "apply" ]]; then
        echo "Simulated tofu apply failure" >&2
        exit 1
    fi
    echo "aws_instance.exasol_node[0]: Creating..."
    echo "aws_instance.exasol_node[0]: Creation complete"
    echo "Apply complete! Resources: 1 added, 0 changed, 0 destroyed."
    ;;
  output)
    if [[ "${MOCK_TOFU_FAIL:-}" == "output" ]]; then
        echo "Simulated tofu output failure" >&2
        exit 1
    fi
    if [[ "$1" == "-json" ]]; then
        echo '{"summary":{"value":"ok"}}'
    else
        echo "Summary output"
    fi
    ;;
  *)
    ;;
esac
exit 0
EOF

    cat > "$MOCK_BIN_DIR/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

    chmod +x "$MOCK_BIN_DIR/tofu" "$MOCK_BIN_DIR/sleep"
}

cleanup_mock_env() {
    PATH="$ORIGINAL_PATH"
    if [[ -n "$MOCK_BIN_DIR" && -d "$MOCK_BIN_DIR" ]]; then
        rm -rf "$MOCK_BIN_DIR"
    fi
    MOCK_BIN_DIR=""
}

write_ansible_stub() {
    local behavior="$1"
    cat > "$MOCK_BIN_DIR/ansible-playbook" <<EOF
#!/usr/bin/env bash
echo "TASK [Mock configuration] ***************************************************"
if [[ "$behavior" == "fail" ]]; then
    echo "fatal: [n11]: FAILED! => {}"
    echo "PLAY RECAP *****************************************************************"
    echo "n11 : ok=0   changed=0   failed=1"
    exit 1
fi
echo "ok: [n11]"
echo "PLAY RECAP *****************************************************************"
echo "n11 : ok=1   changed=0   failed=0"
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/ansible-playbook"
}

assert_deployment_failed() {
    local deploy_dir="$1"
    local expected_step="$2"

    local state_status
    state_status=$(state_get_status "$deploy_dir")
    assert_equals "$STATE_DEPLOYMENT_FAILED" "$state_status" "State file should record deployment_failed"

    local status_output
    status_output=$(cmd_status "$deploy_dir")
    local reported_status
    reported_status=$(echo "$status_output" | jq -r '.status')
    assert_equals "$STATE_DEPLOYMENT_FAILED" "$reported_status" "cmd_status should report deployment_failed"

    local progress_file="$deploy_dir/.exasol-progress.jsonl"
    assert_file_exists "$progress_file" "Progress log should exist"
    local last_line
    last_line=$(tail -n 1 "$progress_file")
    local progress_status
    progress_status=$(echo "$last_line" | jq -r '.status')
    assert_equals "failed" "$progress_status" "Progress file should record failure"
    local progress_step
    progress_step=$(echo "$last_line" | jq -r '.step')
    assert_equals "$expected_step" "$progress_step" "Failure step should be $expected_step"

    assert_file_exists "$deploy_dir/INFO.txt" "INFO.txt should be generated"
    local info_txt_content
    info_txt_content=$(cat "$deploy_dir/INFO.txt")
    assert_contains "$info_txt_content" "Exasol Deployment Entry Point" "INFO.txt should mention entry point"
    assert_contains "$info_txt_content" "exasol status --show-details" "INFO.txt should mention status command"
}

test_tofu_init_failure_updates_status() {
    echo ""
    echo "Test: tofu init failure updates status"

    local deploy_dir
    deploy_dir=$(setup_test_dir)

    setup_mock_env
    write_ansible_stub "success"
    export MOCK_TOFU_FAIL="init"

    cmd_init --cloud-provider aws --deployment-dir "$deploy_dir" >/dev/null 2>&1

    # Simulate Terraform output files to allow Ansible stage to run
    cat > "$deploy_dir/inventory.ini" <<'EOF'
[exasol_nodes]
n11 ansible_host=127.0.0.1
EOF

    local exit_code
    if ( cmd_deploy --deployment-dir "$deploy_dir" >/dev/null 2>&1 ); then
        exit_code=0
    else
        exit_code=$?
    fi
    assert_failure $exit_code "cmd_deploy should fail during tofu init"

    assert_deployment_failed "$deploy_dir" "tofu_init"

    cleanup_mock_env
    cleanup_test_dir "$deploy_dir"
}

test_ansible_failure_updates_status() {
    echo ""
    echo "Test: ansible failure updates status"

    local deploy_dir
    deploy_dir=$(setup_test_dir)

    setup_mock_env
    write_ansible_stub "fail"
    unset MOCK_TOFU_FAIL

    local stub_exit
    ansible-playbook >/dev/null 2>&1
    stub_exit=$?
    assert_failure $stub_exit "Mock ansible should fail"

    cmd_init --cloud-provider aws --deployment-dir "$deploy_dir" >/dev/null 2>&1

    cat > "$deploy_dir/inventory.ini" <<'EOF'
[exasol_nodes]
n11 ansible_host=127.0.0.1
EOF

    local exit_code
    if ( cmd_deploy --deployment-dir "$deploy_dir" >/dev/null 2>&1 ); then
        exit_code=0
    else
        exit_code=$?
    fi
    assert_failure $exit_code "cmd_deploy should fail during ansible execution"

    assert_deployment_failed "$deploy_dir" "ansible_config"

    cleanup_mock_env
    cleanup_test_dir "$deploy_dir"
}

test_tofu_init_failure_updates_status
test_ansible_failure_updates_status

test_summary
