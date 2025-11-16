#!/usr/bin/env bash
# Tests for the health command

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/cmd_health.sh"

ORIGINAL_PATH="$PATH"
MOCK_BIN_DIR=""

setup_mock_env() {
    MOCK_BIN_DIR="$(mktemp -d)"
    PATH="$MOCK_BIN_DIR:$ORIGINAL_PATH"

    cat > "$MOCK_BIN_DIR/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

args=("$@")
host=""
cmd_index=${#args[@]}
skip_next=0
for idx in "${!args[@]}"; do
    if [[ $skip_next -eq 1 ]]; then
        skip_next=0
        continue
    fi
    arg="${args[$idx]}"
    case "$arg" in
        -F|-i|-o|-p|-l|-S)
            skip_next=1
            continue
            ;;
    esac
    if [[ "$arg" == -* ]]; then
        continue
    fi
    if [[ "$arg" == *=* ]]; then
        continue
    fi
    host="$arg"
    cmd_index=$((idx + 1))
    break
done

cmd=()
for ((i=cmd_index; i<${#args[@]}; i++)); do
    cmd+=("${args[$i]}")
done

joined="${cmd[*]}"

case "${cmd[0]:-}" in
    true)
        exit 0
        ;;
    sudo)
        if [[ "${cmd[1]:-}" == "systemctl" ]]; then
            exit 0
        fi
        ;;
esac

if [[ "$joined" == *"hostname -I"* ]]; then
    if [[ "${MOCK_HEALTH_MODE:-stable}" == "ip-change" && -n "${MOCK_HEALTH_NEW_PRIVATE_IP:-}" ]]; then
        echo "${MOCK_HEALTH_NEW_PRIVATE_IP}"
    else
        echo "${MOCK_HEALTH_REMOTE_PRIVATE_IP:-${MOCK_HEALTH_ORIGINAL_IP:-127.0.0.1}}"
    fi
    exit 0
fi

if [[ "$joined" == *"latest/meta-data/public-ipv4"* ]]; then
    if [[ "${MOCK_HEALTH_MODE:-stable}" == "ip-change" ]]; then
        echo "${MOCK_HEALTH_NEW_IP:-5.6.7.8}"
    else
        echo "${MOCK_HEALTH_ORIGINAL_IP:-1.2.3.4}"
    fi
    exit 0
fi

if [[ "$joined" == *"/dev/exasol_data_"* ]]; then
    echo "2|"
    exit 0
fi

if [[ "$joined" == *"cluster status"* ]]; then
    echo "1"
    exit 0
fi

exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/ssh"

    cat > "$MOCK_BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo "200|text/html"
EOF
    chmod +x "$MOCK_BIN_DIR/curl"

    cat > "$MOCK_BIN_DIR/openssl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/openssl"
}

cleanup_mock_env() {
    PATH="$ORIGINAL_PATH"
    if [[ -n "$MOCK_BIN_DIR" && -d "$MOCK_BIN_DIR" ]]; then
        rm -rf "$MOCK_BIN_DIR"
    fi
    MOCK_BIN_DIR=""
}

create_deployment_dir() {
    local public_ip="$1"
    local deploy_dir
    deploy_dir=$(setup_test_dir)

    cat > "$deploy_dir/inventory.ini" <<EOF
[exasol_nodes]
n11 ansible_host=$public_ip
EOF

    cat > "$deploy_dir/ssh_config" <<EOF
Host n11
    HostName $public_ip
    User exasol
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host n11-cos
    HostName $public_ip
    User root
    Port 20002
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

    cat > "$deploy_dir/INFO.txt" <<EOF
Deployment created for IP $public_ip
EOF

    cat > "$deploy_dir/$STATE_FILE" <<'EOF'
{
  "status": "database_ready",
  "cloud_provider": "aws",
  "cluster_size": 1
}
EOF

    cat > "$deploy_dir/variables.auto.tfvars" <<'EOF'
node_count = 1
EOF

    echo "$deploy_dir"
}

test_health_succeeds_when_all_checks_pass() {
    echo ""
    echo "Test: health command succeeds when SSH/service checks pass"

    setup_mock_env
    local deploy_dir
    deploy_dir=$(create_deployment_dir "1.2.3.4")

    export MOCK_HEALTH_MODE="stable"
    export MOCK_HEALTH_ORIGINAL_IP="1.2.3.4"
    export MOCK_HEALTH_REMOTE_PRIVATE_IP="10.0.0.11"

    if cmd_health --deployment-dir "$deploy_dir" >/dev/null; then
        assert_success 0 "Health command should succeed"
    else
        assert_success $? "Health command should succeed"
    fi

    cleanup_mock_env
    cleanup_test_dir "$deploy_dir"
    unset MOCK_HEALTH_MODE MOCK_HEALTH_ORIGINAL_IP MOCK_HEALTH_REMOTE_PRIVATE_IP
}

test_health_updates_metadata_when_ip_changes() {
    echo ""
    echo "Test: health --update refreshes metadata when IP changes"

    setup_mock_env
    local deploy_dir
    deploy_dir=$(create_deployment_dir "1.2.3.4")

    export MOCK_HEALTH_MODE="ip-change"
    export MOCK_HEALTH_ORIGINAL_IP="1.2.3.4"
    export MOCK_HEALTH_NEW_IP="5.6.7.8"
    export MOCK_HEALTH_REMOTE_PRIVATE_IP="10.0.0.12"
    export MOCK_HEALTH_NEW_PRIVATE_IP="10.0.0.22"

    if ! cmd_health --deployment-dir "$deploy_dir" --update >/dev/null; then
        assert_success $? "Health --update should succeed when updating metadata"
    else
        assert_success 0 "Health --update should succeed when updating metadata"
    fi

    local inventory_line
    inventory_line=$(grep "n11" "$deploy_dir/inventory.ini")
    assert_contains "$inventory_line" "ansible_host=5.6.7.8" "Inventory should be updated after --update"

    local ssh_host_line
    ssh_host_line=$(awk '/Host n11/{getline; print}' "$deploy_dir/ssh_config")
    assert_contains "$ssh_host_line" "5.6.7.8" "ssh_config should be updated after --update"

    local info_contents
    info_contents=$(cat "$deploy_dir/INFO.txt")
    assert_contains "$info_contents" "5.6.7.8" "INFO.txt should be updated after --update"

    cleanup_mock_env
    cleanup_test_dir "$deploy_dir"
    unset MOCK_HEALTH_MODE MOCK_HEALTH_ORIGINAL_IP MOCK_HEALTH_NEW_IP MOCK_HEALTH_REMOTE_PRIVATE_IP MOCK_HEALTH_NEW_PRIVATE_IP
}

test_health_json_output_with_ssh_failure() {
    echo ""
    echo "Test: JSON output correctly counts SSH failures"

    MOCK_BIN_DIR="$(mktemp -d)"
    PATH="$MOCK_BIN_DIR:$ORIGINAL_PATH"

    # Mock SSH that fails for n12
    cat > "$MOCK_BIN_DIR/ssh" <<'EOF'
#!/usr/bin/env bash
args=("$@")
host=""
cmd_index=${#args[@]}
skip_next=0

# Parse to find hostname
for idx in "${!args[@]}"; do
    if [[ $skip_next -eq 1 ]]; then
        skip_next=0
        continue
    fi
    arg="${args[$idx]}"
    case "$arg" in
        -F|-i|-o|-p|-l|-S)
            skip_next=1
            continue
            ;;
    esac
    if [[ "$arg" == -* ]]; then
        continue
    fi
    if [[ "$arg" == *=* ]]; then
        continue
    fi
    host="$arg"
    cmd_index=$((idx + 1))
    break
done

# Build command
cmd=()
for ((i=cmd_index; i<${#args[@]}; i++)); do
    cmd+=("${args[$i]}")
done
joined="${cmd[*]}"

# n11 succeeds, n12 fails
if [[ "$host" == "n12" ]]; then
    exit 1
fi

# For n11, handle different commands
if [[ "$joined" == *"true"* ]]; then
    exit 0
elif [[ "$joined" == *"systemctl"* ]]; then
    exit 0
elif [[ "$joined" == *"hostname -I"* ]]; then
    echo "10.0.0.11"
elif [[ "$joined" == *"ip.me"* ]]; then
    echo "1.2.3.4"
elif [[ "$joined" == *"/dev/exasol_data_"* ]]; then
    echo "2||100GB,200GB"
elif [[ "$joined" == *"cluster status"* ]]; then
    echo "1"
elif [[ "$joined" == *"curl"* ]] && [[ "$joined" == *"8563"* ]]; then
    echo '{"status":"error"}'
else
    exit 0
fi
EOF
    chmod +x "$MOCK_BIN_DIR/ssh"

    # Create deployment with 2 hosts
    local deploy_dir
    deploy_dir=$(setup_test_dir)

    cat > "$deploy_dir/inventory.ini" <<'EOF'
[exasol_nodes]
n11 ansible_host=1.2.3.4
n12 ansible_host=1.2.3.5
EOF

    cat > "$deploy_dir/ssh_config" <<'EOF'
Host n11
    HostName 1.2.3.4
Host n12
    HostName 1.2.3.5
EOF

    cat > "$deploy_dir/$STATE_FILE" <<'EOF'
{
  "status": "database_ready",
  "cloud_provider": "aws",
  "cluster_size": 2
}
EOF

    cat > "$deploy_dir/variables.auto.tfvars" <<'EOF'
node_count = 2
EOF

    # Run health check with JSON output
    local json_output
    json_output=$(cmd_health --deployment-dir "$deploy_dir" --output-format json 2>/dev/null || true)

    # Parse JSON using real jq
    local issues_count
    issues_count=$(/usr/bin/jq -r '.issues_count' <<< "$json_output" 2>/dev/null || echo "")
    local issues_array_length
    issues_array_length=$(/usr/bin/jq '.issues | length' <<< "$json_output" 2>/dev/null || echo "")
    local status
    status=$(/usr/bin/jq -r '.status' <<< "$json_output" 2>/dev/null || echo "")
    local ssh_failed
    ssh_failed=$(/usr/bin/jq -r '.checks.ssh.failed' <<< "$json_output" 2>/dev/null || echo "")

    # Validate counts
    assert_equals "$issues_count" "$issues_array_length" "issues_count should match issues array length"
    assert_greater_than "$issues_count" 0 "Should have detected at least 1 issue"
    assert_equals "$status" "issues_detected" "Status should be 'issues_detected'"
    assert_equals "$ssh_failed" "1" "Should have 1 SSH failure"

    # Verify issues array contains ssh_unreachable
    local has_ssh_issue
    has_ssh_issue=$(/usr/bin/jq '[.issues[] | select(.type == "ssh_unreachable")] | length' <<< "$json_output" 2>/dev/null || echo "0")
    assert_greater_than "$has_ssh_issue" 0 "Should have ssh_unreachable issue in array"

    PATH="$ORIGINAL_PATH"
    rm -rf "$MOCK_BIN_DIR"
    cleanup_test_dir "$deploy_dir"
}

test_health_json_output_with_service_failures() {
    echo ""
    echo "Test: JSON output correctly counts service failures"

    MOCK_BIN_DIR="$(mktemp -d)"
    PATH="$MOCK_BIN_DIR:$ORIGINAL_PATH"

    # Mock SSH where systemctl returns failure for one service
    cat > "$MOCK_BIN_DIR/ssh" <<'EOF'
#!/usr/bin/env bash
cmd="${args[*]}"
if [[ "$*" == *"systemctl"* && "$*" == *"exasold.service"* ]]; then
    exit 1  # exasold service is failed
fi
if [[ "$*" == *"true"* ]]; then
    exit 0
elif [[ "$*" == *"systemctl"* ]]; then
    exit 0  # other services OK
elif [[ "$*" == *"hostname -I"* ]]; then
    echo "10.0.0.11"
elif [[ "$*" == *"ip.me"* ]]; then
    echo "1.2.3.4"
elif [[ "$*" == *"/dev/exasol_data_"* ]]; then
    echo "2||100GB,200GB"
fi
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/ssh"

    local deploy_dir
    deploy_dir=$(setup_test_dir)

    cat > "$deploy_dir/inventory.ini" <<'EOF'
[exasol_nodes]
n11 ansible_host=1.2.3.4
EOF

    cat > "$deploy_dir/ssh_config" <<'EOF'
Host n11
    HostName 1.2.3.4
EOF

    cat > "$deploy_dir/$STATE_FILE" <<'EOF'
{
  "status": "database_ready",
  "cloud_provider": "aws",
  "cluster_size": 1
}
EOF

    cat > "$deploy_dir/variables.auto.tfvars" <<'EOF'
node_count = 1
EOF

    local json_output
    json_output=$(cmd_health --deployment-dir "$deploy_dir" --output-format json 2>/dev/null || true)

    local issues_count
    issues_count=$(/usr/bin/jq -r '.issues_count' <<< "$json_output" 2>/dev/null || echo "")
    local issues_array_length
    issues_array_length=$(/usr/bin/jq '.issues | length' <<< "$json_output" 2>/dev/null || echo "")
    local services_failed
    services_failed=$(/usr/bin/jq -r '.checks.services.failed' <<< "$json_output" 2>/dev/null || echo "")

    assert_equals "$issues_count" "$issues_array_length" "issues_count should match issues array length"
    assert_greater_than "$services_failed" 0 "Should have at least 1 service failure"

    local has_service_issue
    has_service_issue=$(/usr/bin/jq '[.issues[] | select(.type == "service_failed")] | length' <<< "$json_output" 2>/dev/null || echo "0")
    assert_greater_than "$has_service_issue" 0 "Should have service_failed issue in array"

    PATH="$ORIGINAL_PATH"
    rm -rf "$MOCK_BIN_DIR"
    cleanup_test_dir "$deploy_dir"
}

test_health_json_output_healthy_state() {
    echo ""
    echo "Test: JSON output shows healthy when no issues"

    setup_mock_env
    local deploy_dir
    deploy_dir=$(create_deployment_dir "1.2.3.4")

    export MOCK_HEALTH_MODE="stable"
    export MOCK_HEALTH_ORIGINAL_IP="1.2.3.4"
    export MOCK_HEALTH_REMOTE_PRIVATE_IP="10.0.0.11"

    local json_output
    json_output=$(cmd_health --deployment-dir "$deploy_dir" --output-format json 2>/dev/null || true)

    local issues_count
    issues_count=$(echo "$json_output" | jq -r '.issues_count' 2>/dev/null || echo "")
    local status
    status=$(echo "$json_output" | jq -r '.status' 2>/dev/null || echo "")
    local exit_code
    exit_code=$(echo "$json_output" | jq -r '.exit_code' 2>/dev/null || echo "")

    assert_equals "$issues_count" "0" "Healthy deployment should have 0 issues"
    assert_equals "$status" "healthy" "Status should be 'healthy'"
    assert_equals "$exit_code" "0" "Exit code should be 0"

    cleanup_mock_env
    cleanup_test_dir "$deploy_dir"
    unset MOCK_HEALTH_MODE MOCK_HEALTH_ORIGINAL_IP MOCK_HEALTH_REMOTE_PRIVATE_IP
}

test_health_multihost_mixed_results() {
    echo ""
    echo "Test: Multi-host deployment with mixed success/failure"

    MOCK_BIN_DIR="$(mktemp -d)"
    PATH="$MOCK_BIN_DIR:$ORIGINAL_PATH"

    # Mock SSH: n11 OK, n12 fails SSH, n13 has service failure
    cat > "$MOCK_BIN_DIR/ssh" <<'EOF'
#!/usr/bin/env bash
args=("$@")
host=""
for arg in "${args[@]}"; do
    if [[ "$arg" != -* && "$arg" != *=* ]]; then
        host="$arg"
        break
    fi
done

if [[ "$host" == "n12" ]]; then
    exit 1  # SSH fails for n12
fi

cmd="${args[*]}"
if [[ "$host" == "n13" ]] && [[ "$cmd" == *"systemctl"* ]] && [[ "$cmd" == *"exasold.service"* ]]; then
    exit 1  # exasold fails on n13
fi

# Default successful responses
if [[ "$cmd" == *"true"* ]]; then
    exit 0
elif [[ "$cmd" == *"systemctl"* ]]; then
    exit 0
elif [[ "$cmd" == *"hostname -I"* ]]; then
    echo "10.0.0.11"
elif [[ "$cmd" == *"ip.me"* ]]; then
    echo "1.2.3.4"
elif [[ "$cmd" == *"/dev/exasol_data_"* ]]; then
    echo "2||100GB"
elif [[ "$cmd" == *"cluster status"* ]]; then
    echo "1"
fi
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/ssh"

    local deploy_dir
    deploy_dir=$(setup_test_dir)

    cat > "$deploy_dir/inventory.ini" <<'EOF'
[exasol_nodes]
n11 ansible_host=1.2.3.4
n12 ansible_host=1.2.3.5
n13 ansible_host=1.2.3.6
EOF

    cat > "$deploy_dir/ssh_config" <<'EOF'
Host n11
    HostName 1.2.3.4
Host n12
    HostName 1.2.3.5
Host n13
    HostName 1.2.3.6
EOF

    cat > "$deploy_dir/$STATE_FILE" <<'EOF'
{
  "status": "database_ready",
  "cloud_provider": "aws",
  "cluster_size": 3
}
EOF

    cat > "$deploy_dir/variables.auto.tfvars" <<'EOF'
node_count = 3
EOF

    # Test with text output
    local text_output
    text_output=$(cmd_health --deployment-dir "$deploy_dir" 2>/dev/null || true)
    assert_contains "$text_output" "✗" "Text output should contain failure markers"

    # Test with JSON output
    local json_output
    json_output=$(cmd_health --deployment-dir "$deploy_dir" --output-format json 2>/dev/null || true)

    local issues_count
    issues_count=$(/usr/bin/jq -r '.issues_count' <<< "$json_output" 2>/dev/null || echo "")
    local issues_array_length
    issues_array_length=$(/usr/bin/jq '.issues | length' <<< "$json_output" 2>/dev/null || echo "")
    local ssh_passed
    ssh_passed=$(/usr/bin/jq -r '.checks.ssh.passed' <<< "$json_output" 2>/dev/null || echo "")
    local ssh_failed
    ssh_failed=$(/usr/bin/jq -r '.checks.ssh.failed' <<< "$json_output" 2>/dev/null || echo "")

    assert_equals "$issues_count" "$issues_array_length" "issues_count should match issues array length"
    assert_greater_than "$issues_count" 1 "Should have multiple issues (SSH + service)"
    assert_equals "$ssh_passed" "2" "Should have 2 passed SSH checks (n11, n13)"
    assert_equals "$ssh_failed" "1" "Should have 1 failed SSH check (n12)"

    PATH="$ORIGINAL_PATH"
    rm -rf "$MOCK_BIN_DIR"
    cleanup_test_dir "$deploy_dir"
}

test_health_succeeds_when_all_checks_pass
test_health_updates_metadata_when_ip_changes
test_health_json_output_with_ssh_failure
test_health_json_output_with_service_failures
test_health_json_output_healthy_state
test_health_multihost_mixed_results

test_summary
