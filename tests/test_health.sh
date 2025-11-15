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

setup_mock_ssh() {
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

case "${cmd[0]:-}" in
    true)
        exit 0
        ;;
    hostname)
        if [[ "${cmd[1]:-}" == "-I" ]]; then
            if [[ "${MOCK_HEALTH_MODE:-stable}" == "ip-change" ]]; then
                echo "${MOCK_HEALTH_NEW_IP:-5.6.7.8}"
            else
                echo "${MOCK_HEALTH_ORIGINAL_IP:-1.2.3.4}"
            fi
            exit 0
        fi
        ;;
    sudo)
        if [[ "${cmd[1]:-}" == "systemctl" ]]; then
            case "${cmd[2]:-}" in
                is-active|restart)
                    exit 0
                    ;;
            esac
        fi
        ;;
esac

exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/ssh"
}

cleanup_mock_env() {
    PATH="$ORIGINAL_PATH"
    if [[ -n "$MOCK_BIN_DIR" && -d "$MOCK_BIN_DIR" ]]; then
        rm -rf "$MOCK_BIN_DIR"
    fi
    MOCK_BIN_DIR=""
}

create_deployment_dir() {
    local ip="$1"
    local deploy_dir
    deploy_dir=$(setup_test_dir)

    cat > "$deploy_dir/inventory.ini" <<EOF
[exasol_nodes]
n11 ansible_host=$ip
EOF

    cat > "$deploy_dir/ssh_config" <<EOF
Host n11
    HostName $ip
    User exasol
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host n11-cos
    HostName $ip
    User root
    Port 20002
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

    cat > "$deploy_dir/INFO.txt" <<EOF
Deployment created for IP $ip
EOF

    echo "$deploy_dir"
}

test_health_succeeds_when_all_checks_pass() {
    echo ""
    echo "Test: health command succeeds when SSH/service checks pass"

    setup_mock_ssh
    local deploy_dir
    deploy_dir=$(create_deployment_dir "1.2.3.4")

    export MOCK_HEALTH_MODE="stable"
    export MOCK_HEALTH_ORIGINAL_IP="1.2.3.4"

    local output
    if ! output=$(cmd_health --deployment-dir "$deploy_dir"); then
        assert_success $? "Health command should succeed"
    else
        assert_success 0 "Health command should succeed"
    fi

    cleanup_mock_env
    cleanup_test_dir "$deploy_dir"
}

test_health_updates_metadata_when_ip_changes() {
    echo ""
    echo "Test: health --update refreshes metadata when IP changes"

    setup_mock_ssh
    local deploy_dir
    deploy_dir=$(create_deployment_dir "1.2.3.4")

    export MOCK_HEALTH_MODE="ip-change"
    export MOCK_HEALTH_ORIGINAL_IP="1.2.3.4"
    export MOCK_HEALTH_NEW_IP="5.6.7.8"

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
}

test_health_succeeds_when_all_checks_pass
test_health_updates_metadata_when_ip_changes

test_summary
