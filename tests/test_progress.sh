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

    assert_contains "$first_line" "[01/10]" "First deploy step should start at 1"
    assert_contains "$first_line" "Infrastructure planning" "Step 1 label should be Infrastructure planning"

    assert_contains "$last_line" "[10/10]" "Last deploy step should reach 10"
    assert_contains "$last_line" "Deployment validation" "Final label should be Deployment validation"
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

    local input output third_line
    input=$(
        cat <<'EOF'
Creating cloud infrastructure...
libvirt_volume.root_volume[0]: Creating...
aws_vpc.exasol_vpc: Creating...
EOF
    )

    output=$(printf "%s" "$input" | progress_display_steps "deploy")
    third_line=$(echo "$output" | sed -n '3p')

    assert_contains "$third_line" "[04/10]" "Progress should stay on step 4 after storage detection"
    assert_contains "$third_line" "Storage provisioning" "Label should remain at latest detected step"
}

test_progress_start_steps_sequence() {
    echo ""
    echo "Test: start progress advances across all steps"

    local input output last_line
    input=$(
        cat <<'EOF'
Starting Exasol database cluster...
Waiting for status 'database_ready' (timeout: 15m)...
Status reached: database_ready
Health report for /tmp/deploy
EOF
    )

    output=$(printf "%s" "$input" | progress_display_steps "start")
    last_line=$(echo "$output" | tail -n1)

    assert_contains "$last_line" "[4/4]" "Start should reach final step"
    assert_contains "$last_line" "Health checks" "Start final label should be Health checks"
}

test_progress_stop_steps_sequence() {
    echo ""
    echo "Test: stop progress advances across all steps"

    local input output third_line last_line
    input=$(
        cat <<'EOF'
Stopping Exasol database cluster...
Verify all services are stopped
Power off hosts via in-guest shutdown (fallback for unsupported providers)
PLAY RECAP *********************************************************************
EOF
    )

    output=$(printf "%s" "$input" | progress_display_steps "stop")
    third_line=$(echo "$output" | sed -n '3p')
    last_line=$(echo "$output" | tail -n1)

    assert_contains "$third_line" "[3/4]" "Stop should reach power-off step"
    assert_contains "$third_line" "Powering off instances" "Step 3 label should be Powering off instances"
    assert_contains "$last_line" "[4/4]" "Stop should reach final verification step"
}

test_progress_display_steps_deploy_sequence
test_progress_display_steps_unknown_operation_passthrough
test_progress_step_does_not_regress
test_progress_start_steps_sequence
test_progress_stop_steps_sequence

# Summary is printed by test_helper via test_summary
test_summary

test_summary
