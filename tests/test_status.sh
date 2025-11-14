#!/usr/bin/env bash
# Tests for status command enhancements

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/cmd_status.sh"

ORIGINAL_PATH="$PATH"
MOCK_BIN_DIR=""

setup_mock_env() {
    MOCK_BIN_DIR="$(mktemp -d)"
    PATH="$MOCK_BIN_DIR:$ORIGINAL_PATH"

    cat > "$MOCK_BIN_DIR/tofu" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-chdir="* ]]; then
    shift
fi
cmd="${1:-}"
shift || true
case "$cmd" in
  output)
    if [[ "${1:-}" == "-json" ]]; then
        cat <<'JSON'
{
  "instance_details": {
    "value": {
      "n11": {
        "public_ip": "98.84.105.66"
      }
    }
  },
  "summary": {
    "value": "ok"
  }
}
JSON
    else
        echo "summary"
    fi
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

test_status_includes_empty_details_without_flag() {
    echo ""
    echo "Test: status output includes empty details when not requested"

    local deploy_dir
    deploy_dir=$(setup_test_dir)

    cat > "$deploy_dir/$STATE_FILE" <<'EOF'
{
  "status": "initialized",
  "db_version": "test",
  "architecture": "x86_64",
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z"
}
EOF

    local status_output
    status_output=$(cmd_status --deployment-dir "$deploy_dir")

    local has_details
    has_details=$(echo "$status_output" | jq 'has("details")')
    assert_equals "false" "$has_details" "Details should be omitted when not requested"

    cleanup_test_dir "$deploy_dir"
}

test_status_show_details_outputs_details_object() {
    echo ""
    echo "Test: status --show-details populates details dictionary"

    local deploy_dir
    deploy_dir=$(setup_test_dir)

    cat > "$deploy_dir/$STATE_FILE" <<'EOF'
{
  "status": "initialized",
  "db_version": "test",
  "architecture": "x86_64",
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z"
}
EOF

    setup_mock_env

    local status_output
    status_output=$(cmd_status --deployment-dir "$deploy_dir" --show-details)

    local has_details
    has_details=$(echo "$status_output" | jq 'has("details")')
    assert_equals "true" "$has_details" "Details should be present when --show-details is used"

    local summary_present
    summary_present=$(echo "$status_output" | jq '.details | has("summary")')
    assert_equals "false" "$summary_present" "Summary output should be removed from details"

    local instance_count
    instance_count=$(echo "$status_output" | jq -r '.details.instance_count')
    assert_equals "1" "$instance_count" "Details should include instance count"

    local node_ip
    node_ip=$(echo "$status_output" | jq -r '.details.instance_details.n11.public_ip')
    assert_equals "98.84.105.66" "$node_ip" "Instance details should contain flattened data"

    cleanup_mock_env
    cleanup_test_dir "$deploy_dir"
}

test_status_includes_empty_details_without_flag
test_status_show_details_outputs_details_object

test_summary
