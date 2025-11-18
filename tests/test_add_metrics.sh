#!/usr/bin/env bash
# Tests for add-metrics command

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/cmd_add_metrics.sh"

ORIGINAL_PATH="$PATH"

# Test: add-metrics command succeeds with valid metrics
test_add_metrics_success() {
    echo ""
    echo "Test: add-metrics command succeeds with valid metrics"

    # Create test deployment with metrics
    local deploy_dir
    deploy_dir=$(setup_test_dir)

    # Create metrics directory and file
    mkdir -p "$deploy_dir/metrics"
    cat > "$deploy_dir/metrics/test.deploy.1.txt" <<'EOF'
provider=test
operation=deploy
nodes=1
timestamp=2025-01-18T10:00:00Z
total_lines=100
duration=60
EOF

    # Test dry-run
    local output
    output=$(cmd_add_metrics --deployment-dir "$deploy_dir" --dry-run 2>&1)
    assert_contains "$output" "Would copy: test.deploy.1.txt" "Dry-run should show what would be copied"

    # Test actual copy
    output=$(cmd_add_metrics --deployment-dir "$deploy_dir" 2>&1)
    assert_contains "$output" "Copied: test.deploy.1.txt" "Should successfully copy metrics file"

    # Verify file was copied to global repository
    assert_file_exists "$LIB_DIR/metrics/test.deploy.1.txt" "Metrics file should exist in global repository"

    # Clean up
    rm -f "$LIB_DIR/metrics/test.deploy.1.txt"
    cleanup_test_dir "$deploy_dir"
}

# Test: add-metrics overwrites existing files
test_add_metrics_overwrites_existing() {
    echo ""
    echo "Test: add-metrics overwrites existing files"

    # Create test deployment with metrics
    local deploy_dir
    deploy_dir=$(setup_test_dir)

    # Create metrics directory and file
    mkdir -p "$deploy_dir/metrics"
    cat > "$deploy_dir/metrics/aws.deploy.1.txt" <<'EOF'
provider=aws
operation=deploy
nodes=1
timestamp=2025-01-18T10:00:00Z
total_lines=994
duration=180
EOF

    # Create a different file in global metrics first (simulate existing file)
    cat > "$LIB_DIR/metrics/aws.deploy.1.txt" <<'EOF'
provider=aws
operation=deploy
nodes=1
timestamp=2025-01-17T10:00:00Z
total_lines=999
duration=200
EOF

    # Test that it overwrites existing file
    local output
    output=$(cmd_add_metrics --deployment-dir "$deploy_dir" 2>&1)
    assert_contains "$output" "Copied: aws.deploy.1.txt (overwriting existing)" "Should overwrite existing files"

    # Verify the content was updated
    local new_content
    new_content=$(grep "total_lines" "$LIB_DIR/metrics/aws.deploy.1.txt")
    assert_contains "$new_content" "total_lines=994" "Should have updated content"

    # Clean up
    rm -f "$LIB_DIR/metrics/aws.deploy.1.txt"
    cleanup_test_dir "$deploy_dir"
}

# Test: add-metrics fails with no metrics directory
test_add_metrics_no_metrics_dir() {
    echo ""
    echo "Test: add-metrics fails with no metrics directory"

    # Create test deployment without metrics directory
    local deploy_dir
    deploy_dir=$(setup_test_dir)

    # Test that it fails
    local output
    output=$(cmd_add_metrics --deployment-dir "$deploy_dir" 2>&1)
    local exit_code=$?

    assert_greater_than "$exit_code" 0 "Should fail when no metrics directory exists"
    assert_contains "$output" "No metrics directory found" "Should show appropriate error message"

    cleanup_test_dir "$deploy_dir"
}

# Test: add-metrics fails with empty metrics directory
test_add_metrics_empty_metrics_dir() {
    echo ""
    echo "Test: add-metrics fails with empty metrics directory"

    # Create test deployment with empty metrics directory
    local deploy_dir
    deploy_dir=$(setup_test_dir)
    mkdir -p "$deploy_dir/metrics"

    # Test that it fails
    local output
    output=$(cmd_add_metrics --deployment-dir "$deploy_dir" 2>&1)
    local exit_code=$?

    assert_greater_than "$exit_code" 0 "Should fail when metrics directory is empty"
    assert_contains "$output" "No metric files found" "Should show appropriate error message"

    cleanup_test_dir "$deploy_dir"
}

# Test: add-metrics fails with invalid deployment directory
test_add_metrics_invalid_deployment_dir() {
    echo ""
    echo "Test: add-metrics fails with invalid deployment directory"

    # Test with non-existent directory
    local output
    output=$(cmd_add_metrics --deployment-dir "/non/existent/directory" 2>&1)
    local exit_code=$?

    assert_greater_than "$exit_code" 0 "Should fail with invalid deployment directory"
    assert_contains "$output" "Deployment directory does not exist" "Should show appropriate error message"
}

# Run tests
test_add_metrics_success
test_add_metrics_overwrites_existing
test_add_metrics_no_metrics_dir
test_add_metrics_empty_metrics_dir
test_add_metrics_invalid_deployment_dir

test_summary