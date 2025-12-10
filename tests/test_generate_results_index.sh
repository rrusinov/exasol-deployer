#!/usr/bin/env bash
# Test the e2e results index generator

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

test_generate_index_empty_directory() {
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Generate index for empty directory
    python3 "$TEST_DIR/e2e/generate_results_index.py" "$temp_dir" >/dev/null 2>&1
    
    # Check index.html was created
    assert_file_exists "$temp_dir/index.html"
    
    # Check it contains "No test results found"
    if grep -q "No test results found" "$temp_dir/index.html"; then
        assert_success 0 "Index shows no results message"
    else
        assert_success 1 "Index should show no results message"
    fi
    
    rm -rf "$temp_dir"
}

test_generate_index_with_results() {
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create mock e2e execution directory
    local exec_dir="$temp_dir/e2e-20251206-120000"
    mkdir -p "$exec_dir/aws"
    mkdir -p "$exec_dir/gcp"
    
    # Create mock results.json files
    cat > "$exec_dir/aws/results.json" <<'EOF'
{
  "total_tests": 3,
  "passed": 2,
  "failed": 1,
  "total_time": 1234.5
}
EOF
    
    cat > "$exec_dir/gcp/results.json" <<'EOF'
{
  "total_tests": 2,
  "passed": 2,
  "failed": 0,
  "total_time": 567.8
}
EOF
    
    # Create mock results.html files
    echo "<html>AWS Results</html>" > "$exec_dir/aws/results.html"
    echo "<html>GCP Results</html>" > "$exec_dir/gcp/results.html"
    
    # Generate index
    python3 "$TEST_DIR/e2e/generate_results_index.py" "$temp_dir" >/dev/null 2>&1
    
    # Check index.html was created
    assert_file_exists "$temp_dir/index.html"
    
    # Check it contains execution ID
    if grep -q "e2e-20251206-120000" "$temp_dir/index.html"; then
        assert_success 0 "Index contains execution ID"
    else
        assert_success 1 "Index should contain execution ID"
    fi
    
    # Check it contains provider names
    if grep -q "aws" "$temp_dir/index.html" && grep -q "gcp" "$temp_dir/index.html"; then
        assert_success 0 "Index contains provider names"
    else
        assert_success 1 "Index should contain provider names"
    fi
    
    # Check it contains statistics
    if grep -q "Total: 3" "$temp_dir/index.html" && grep -q "Passed: 2" "$temp_dir/index.html"; then
        assert_success 0 "Index contains statistics"
    else
        assert_success 1 "Index should contain statistics"
    fi
    
    # Check it contains links
    if grep -q "View Report" "$temp_dir/index.html"; then
        assert_success 0 "Index contains report links"
    else
        assert_success 1 "Index should contain report links"
    fi
    
    rm -rf "$temp_dir"
}

test_generate_index_multiple_executions() {
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create multiple mock executions
    for i in 1 2 3; do
        local exec_dir="$temp_dir/e2e-2025120$i-120000"
        mkdir -p "$exec_dir/aws"
        cat > "$exec_dir/aws/results.json" <<EOF
{
  "total_tests": $i,
  "passed": $i,
  "failed": 0,
  "total_time": 100.0
}
EOF
    done
    
    # Generate index
    local output
    output=$(python3 "$TEST_DIR/e2e/generate_results_index.py" "$temp_dir" 2>&1)
    
    # Check it found 3 executions
    if echo "$output" | grep -q "Found 3 test execution"; then
        assert_success 0 "Found 3 executions"
    else
        assert_success 1 "Should find 3 executions"
    fi
    
    # Check index contains all executions
    if grep -q "e2e-20251201-120000" "$temp_dir/index.html" && \
       grep -q "e2e-20251202-120000" "$temp_dir/index.html" && \
       grep -q "e2e-20251203-120000" "$temp_dir/index.html"; then
        assert_success 0 "Index contains all executions"
    else
        assert_success 1 "Index should contain all executions"
    fi
    
    rm -rf "$temp_dir"
}

test_generate_index_handles_missing_json() {
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create execution with only HTML, no JSON
    local exec_dir="$temp_dir/e2e-20251206-120000"
    mkdir -p "$exec_dir/aws"
    echo "<html>Results</html>" > "$exec_dir/aws/results.html"
    
    # Generate index (should not fail)
    python3 "$TEST_DIR/e2e/generate_results_index.py" "$temp_dir" >/dev/null 2>&1
    rc=$?
    
    assert_success $rc "Generator handles missing JSON"
    assert_file_exists "$temp_dir/index.html"
    
    # Should still show the provider
    if grep -q "aws" "$temp_dir/index.html"; then
        assert_success 0 "Index shows provider without JSON"
    else
        assert_success 1 "Index should show provider without JSON"
    fi
    
    rm -rf "$temp_dir"
}

# Run tests
test_generate_index_empty_directory
test_generate_index_with_results
test_generate_index_multiple_executions
test_generate_index_handles_missing_json

test_summary
