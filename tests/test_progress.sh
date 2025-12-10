#!/usr/bin/env bash
# Unit tests for keyword-based progress tracking system

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/progress_tracker.sh"

test_progress_display_steps_deploy_sequence() {
    echo ""
    echo "Test: deploy progress advances through defined steps"

    local input output
    input=$(
        cat <<'EOF'
Creating cloud infrastructure...
aws_vpc.exasol_vpc: Creating...
aws_instance.exasol_node[0]: Creating...
aws_ebs_volume.data_volume[0]: Creating...
local_file.ansible_inventory: Creation complete after 0s
PLAY [Play 2 - Setup and Configure Exasol Cluster] *****************************
Create final Exasol config file from template
Start Exasol database deployment
Wait for database to boot (stage 'd')
Exasol cluster deployment completed!
EOF
    )

    output=$(printf "%s" "$input" | progress_display_steps "deploy")

    local first_line last_line
    first_line=$(echo "$output" | head -n1)
    last_line=$(echo "$output" | tail -n1)

    assert_contains "$first_line" "[01/19]" "First deploy step should start at 1"
    assert_contains "$first_line" "Terraform Init" "Step 1 label should be Terraform Init"

    assert_contains "$last_line" "[19/19]" "Last deploy step should reach 19"
    assert_contains "$last_line" "Deploy Complete" "Final label should be Deploy Complete"
}

test_progress_display_steps_unknown_operation_passthrough() {
    echo ""
    echo "Test: unknown operation falls back to pass-through output"

    local input output
    input=$(
        cat <<'EOF'
line one
line two
EOF
    )

    output=$(printf "%s" "$input" | progress_display_steps "unknown-op")

    assert_equals "$input" "$output" "Unknown operations should not add progress prefixes"
}

test_progress_step_does_not_regress() {
    echo ""
    echo "Test: progress does not move backwards when later lines match earlier steps"

    local input output second_line third_line
    input=$(
        cat <<'EOF'
tofu init
aws_vpc.exasol_vpc: Creating...
aws_volume.data_volume[0]: Creating...
EOF
    )

    output=$(printf "%s" "$input" | progress_display_steps "deploy")
    second_line=$(echo "$output" | sed -n '2p')
    third_line=$(echo "$output" | sed -n '3p')

    assert_contains "$second_line" "[02/19]" "Second line should show step 2 for network"
    assert_contains "$second_line" "Network Creation" "Second line should show Network Creation"
    assert_contains "$third_line" "[04/19]" "Third line should advance to step 4 for volume"
    assert_contains "$third_line" "Volume Provisioning" "Third line should show Volume Provisioning"
}

test_progress_start_steps_sequence() {
    echo ""
    echo "Test: start progress advances across all steps"

    local input output last_line
    input=$(
        cat <<'EOF'
Starting Exasol database cluster...
Waiting for status 'database_ready' (timeout: 15m)...
All cluster nodes reached stage 'd' (database ready)
Exasol database cluster started successfully on all nodes
EOF
    )

    output=$(printf "%s" "$input" | progress_display_steps "start")
    last_line=$(echo "$output" | tail -n1)

    assert_contains "$last_line" "[6/6]" "Start should reach final step"
    assert_contains "$last_line" "Start Complete" "Start final label should be Start Complete"
}

test_progress_stop_steps_sequence() {
    echo ""
    echo "Test: stop progress advances across all steps"

    local input output fourth_line last_line
    input=$(
        cat <<'EOF'
Database shutdown complete
Stopping Exasol database cluster...
Verify all services are stopped
Power off hosts via in-guest shutdown (fallback for unsupported providers)
PLAY RECAP *********************************************************************
Exasol database cluster stopped successfully
EOF
    )

    output=$(printf "%s" "$input" | progress_display_steps "stop")
    fourth_line=$(echo "$output" | sed -n '4p')
    last_line=$(echo "$output" | tail -n1)

    assert_contains "$fourth_line" "[4/6]" "Stop should reach power-off step"
    assert_contains "$fourth_line" "Infrastructure Power-Off" "Step 4 label should be Infrastructure Power-Off"
    assert_contains "$last_line" "[6/6]" "Stop should reach final verification step"
    assert_contains "$last_line" "Stop Complete" "Stop final label should be Stop Complete"
}

test_progress_display_steps_deploy_sequence
test_progress_display_steps_unknown_operation_passthrough
test_progress_step_does_not_regress
test_progress_start_steps_sequence
test_progress_stop_steps_sequence

# Summary is printed by test_helper via test_summary
test_summary
