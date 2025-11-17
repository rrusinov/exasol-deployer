#!/usr/bin/env bash
# Unit tests for progress tracking system

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/progress_pipe.sh"

# Test estimate_lines function
test_estimate_lines_scaling() {
    echo ""
    echo "Test: estimate_lines calculates correct scaling"

    # Test init (no scaling)
    local init_1node init_4node
    init_1node=$(estimate_lines "init" 1)
    init_4node=$(estimate_lines "init" 4)
    assert_equals "26" "$init_1node" "Init with 1 node should be 26 lines"
    assert_equals "26" "$init_4node" "Init with 4 nodes should be 26 lines (no scaling)"

    # Test deploy (with scaling)
    local deploy_1node deploy_4node deploy_8node
    deploy_1node=$(estimate_lines "deploy" 1)
    deploy_4node=$(estimate_lines "deploy" 4)
    deploy_8node=$(estimate_lines "deploy" 8)
    assert_equals "994" "$deploy_1node" "Deploy with 1 node should be 994 lines"
    assert_equals "1912" "$deploy_4node" "Deploy with 4 nodes should be 1912 lines (994 + 306*3)"
    assert_equals "3136" "$deploy_8node" "Deploy with 8 nodes should be 3136 lines (994 + 306*7)"

    # Test destroy (with scaling)
    local destroy_1node destroy_4node destroy_8node
    destroy_1node=$(estimate_lines "destroy" 1)
    destroy_4node=$(estimate_lines "destroy" 4)
    destroy_8node=$(estimate_lines "destroy" 8)
    assert_equals "808" "$destroy_1node" "Destroy with 1 node should be 808 lines"
    assert_equals "1789" "$destroy_4node" "Destroy with 4 nodes should be 1789 lines (808 + 327*3)"
    assert_equals "3097" "$destroy_8node" "Destroy with 8 nodes should be 3097 lines (808 + 327*7)"
}

# Test progress_prefix_cumulative output format
test_progress_output_format() {
    echo ""
    echo "Test: progress_prefix_cumulative produces correct output format"

    # Initialize cumulative progress
    progress_init_cumulative 100

    # Generate some test output and pipe through progress tracker
    local output
    output=$(echo -e "line1\nline2\nline3" | progress_prefix_cumulative 100)

    # Check that each line has the format: "XX% | <text>"
    local line_count=0
    while IFS= read -r line; do
        line_count=$((line_count + 1))

        # Check format: starts with percentage
        if ! echo "$line" | grep -qE '^\s*[0-9]+%\s+\|'; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Line $line_count does not match progress format: $line"
            return 1
        fi
    done <<< "$output"

    assert_equals "3" "$line_count" "Should have 3 output lines"
    TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} All lines match progress format (XX% | text)"
}

# Test progress percentage calculation
test_progress_percentage_calculation() {
    echo ""
    echo "Test: progress percentages are calculated correctly"

    # Test single batch progress calculation
    # Initialize with 100 total lines
    progress_init_cumulative 100

    # Process 10 lines (should be 10%)
    local output
    output=$(seq 1 10 | progress_prefix_cumulative 100)

    # Extract the last percentage
    local last_percent
    last_percent=$(echo "$output" | tail -1 | grep -oE '^\s*[0-9]+' | tr -d ' ')

    assert_equals "10" "$last_percent" "10 out of 100 lines should show 10%"

    # Test that 50 lines shows 50%
    progress_init_cumulative 100
    output=$(seq 1 50 | progress_prefix_cumulative 100)
    last_percent=$(echo "$output" | tail -1 | grep -oE '^\s*[0-9]+' | tr -d ' ')

    assert_equals "50" "$last_percent" "50 out of 100 lines should show 50%"
}

# Test progress capping at 100%
test_progress_caps_at_100() {
    echo ""
    echo "Test: progress caps at 100% even with more lines"

    # Initialize with 10 total lines
    progress_init_cumulative 10

    # Process 20 lines (more than estimated)
    local output
    output=$(seq 1 20 | progress_prefix_cumulative 10)

    # Extract all percentages and check none exceed 100
    local max_percent=0
    while IFS= read -r line; do
        local percent
        percent=$(echo "$line" | grep -oE '^\s*[0-9]+' | tr -d ' ')
        if [[ $percent -gt $max_percent ]]; then
            max_percent=$percent
        fi
        if [[ $percent -gt 100 ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Progress exceeded 100%: $percent"
            return 1
        fi
    done <<< "$output"

    assert_equals "100" "$max_percent" "Progress should cap at 100%"
}

# Test that command output validation helper
validate_output_format() {
    local output="$1"
    local command_name="$2"

    local line_num=0
    local valid=true
    local invalid_lines=""

    while IFS= read -r line; do
        line_num=$((line_num + 1))

        # Check if line matches either:
        # 1. Progress format: "XX% | <text>"
        # 2. Log format: "[INFO]", "[WARN]", "[ERROR]" (with optional ANSI color codes)
        # 3. Empty line
        if [[ -z "$line" ]]; then
            continue
        fi

        # Strip ANSI color codes for validation
        local clean_line
        clean_line=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g')

        if ! echo "$clean_line" | grep -qE '(^\s*[0-9]+%\s+\||^\[INFO\]|^\[WARN\]|^\[ERROR\]|^Are you sure)'; then
            valid=false
            invalid_lines="${invalid_lines}Line $line_num: $clean_line\n"
        fi
    done <<< "$output"

    if [[ "$valid" == false ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $command_name output contains invalid format lines:"
        echo -e "$invalid_lines"
        return 1
    fi

    TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} All $command_name output lines match expected format"
    return 0
}

# Integration test: init command output format
test_init_output_format() {
    echo ""
    echo "Test: init command output format"

    local deploy_dir
    deploy_dir=$(setup_test_dir)

    # Capture init output
    local output
    output=$(bash "$TEST_DIR/../exasol" init --cloud-provider libvirt --deployment-dir "$deploy_dir" 2>&1)

    validate_output_format "$output" "init"

    cleanup_test_dir "$deploy_dir"
}

# Run tests
test_estimate_lines_scaling
test_progress_output_format
test_progress_percentage_calculation
test_progress_caps_at_100
test_init_output_format

test_summary
