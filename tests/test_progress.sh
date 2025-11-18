#!/usr/bin/env bash
# Unit tests for progress tracking system

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/progress_tracker.sh"

# Test progress_estimate_lines function
test_progress_estimate_lines_scaling() {
    echo ""
    echo "Test: progress_estimate_lines calculates correct scaling"

    # Test AWS deploy (with scaling) - based on actual metrics
    local deploy_1node deploy_4node deploy_8node
    deploy_1node=$(progress_estimate_lines "aws" "deploy" 1)
    deploy_4node=$(progress_estimate_lines "aws" "deploy" 4)
    deploy_8node=$(progress_estimate_lines "aws" "deploy" 8)
    
    # Based on actual metrics: 994 lines for 1 node, 1903 for 4 nodes
    # Scaling: (1903 - 994) / (4 - 1) = 303 per additional node
    assert_equals "994" "$deploy_1node" "AWS deploy with 1 node should be 994 lines"
    assert_equals "1903" "$deploy_4node" "AWS deploy with 4 nodes should be 1903 lines"
    assert_equals "3115" "$deploy_8node" "AWS deploy with 8 nodes should be 3115 lines (994 + 303*7)"

    # Test AWS destroy (with scaling) - based on actual metrics
    local destroy_1node destroy_4node destroy_8node
    destroy_1node=$(progress_estimate_lines "aws" "destroy" 1)
    destroy_4node=$(progress_estimate_lines "aws" "destroy" 4)
    destroy_8node=$(progress_estimate_lines "aws" "destroy" 8)
    
    # Based on actual metrics: 808 lines for 1 node, 1797 for 4 nodes
    # Scaling: (1797 - 808) / (4 - 1) = 330 per additional node
    assert_equals "808" "$destroy_1node" "AWS destroy with 1 node should be 808 lines"
    assert_equals "1795" "$destroy_4node" "AWS destroy with 4 nodes should be 1795 lines"
    assert_equals "3111" "$destroy_8node" "AWS destroy with 8 nodes should be 3111 lines (808 + 330*7)"

    # Test unknown provider fallback
    local fallback_1node fallback_4node
    fallback_1node=$(progress_estimate_lines "unknown" "deploy" 1)
    fallback_4node=$(progress_estimate_lines "unknown" "deploy" 4)
    
    # Should use regression defaults (base=100, per_node=50)
    assert_equals "100" "$fallback_1node" "Unknown provider should use regression default base=100"
    assert_equals "250" "$fallback_4node" "Unknown provider should use regression default for 4 nodes (100 + 50*3)"
}

# Test progress_load_metrics function
test_progress_load_metrics() {
    echo ""
    echo "Test: progress_load_metrics finds correct metric files"

    # Test loading AWS deploy metrics
    local aws_deploy_metrics
    mapfile -t aws_deploy_metrics < <(progress_load_metrics "aws" "deploy")
    
    assert_equals "2" "${#aws_deploy_metrics[@]}" "Should find 2 AWS deploy metric files"
    
    # Check that files contain expected node counts
    local found_1node=false found_4node=false
    for file in "${aws_deploy_metrics[@]}"; do
        if [[ "$file" == *"1node.txt" ]]; then
            found_1node=true
        elif [[ "$file" == *"4nodes.txt" ]]; then
            found_4node=true
        fi
    done
    
    if [[ "$found_1node" == true ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should find 1-node metric file"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should find 1-node metric file"
    fi

    if [[ "$found_4node" == true ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should find 4-node metric file"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should find 4-node metric file"
    fi

    # Test loading non-existent metrics (find command returns empty line, so array has 1 element)
    local unknown_metrics
    mapfile -t unknown_metrics < <(progress_load_metrics "nonexistent" "operation")
    # The find command returns an empty line, so we need to check if the first element is empty
    if [[ -z "${unknown_metrics[0]:-}" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should find no metrics for non-existent provider"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should find no metrics for non-existent provider"
        echo -e "  Found: ${YELLOW}${#unknown_metrics[@]}${NC} elements"
    fi
}

# Test progress_parse_metric_file function
test_progress_parse_metric_file() {
    echo ""
    echo "Test: progress_parse_metric_file extracts values correctly"

    # Parse a known metric file
    local metric_file="$LIB_DIR/metrics/aws.deploy.1node.txt"
    local parsed_output
    parsed_output=$(progress_parse_metric_file "$metric_file")
    
    # Check that all expected fields are present
    echo "$parsed_output" | grep -q "metric_total_lines='994'" || {
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should extract total_lines=994"
        return 1
    }
    
    echo "$parsed_output" | grep -q "metric_provider='aws'" || {
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should extract provider=aws"
        return 1
    }
    
    echo "$parsed_output" | grep -q "metric_operation='deploy'" || {
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should extract operation=deploy"
        return 1
    }
    
    echo "$parsed_output" | grep -q "metric_nodes='1'" || {
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should extract nodes=1"
        return 1
    }
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} All metric fields extracted correctly"
}

# Test progress_calculate_regression function
test_progress_calculate_regression() {
    echo ""
    echo "Test: progress_calculate_regression calculates scaling correctly"

    # Test AWS deploy regression
    local regression_result
    regression_result=$(progress_calculate_regression "aws" "deploy")
    local base_lines per_node_lines
    read -r base_lines per_node_lines <<< "$regression_result"
    
    # Should calculate base=994, per_node≈303 from the two data points
    assert_equals "994" "$base_lines" "AWS deploy base lines should be 994"
    # Allow some tolerance for integer division
    if [[ $per_node_lines -ge 300 && $per_node_lines -le 305 ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} AWS deploy per-node scaling is reasonable: $per_node_lines"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} AWS deploy per-node scaling should be ~303, got: $per_node_lines"
    fi

    # Test non-existent provider (should return defaults)
    local default_result
    default_result=$(progress_calculate_regression "nonexistent" "operation")
    read -r default_base default_per_node <<< "$default_result"
    
    assert_equals "100" "$default_base" "Non-existent provider should return base=100"
    assert_equals "50" "$default_per_node" "Non-existent provider should return per_node=50"
}

# Test progress_get_estimated_duration function
test_progress_get_estimated_duration() {
    echo ""
    echo "Test: progress_get_estimated_duration returns reasonable estimates"

    # Test AWS deploy duration estimation
    local duration_1node duration_4node
    duration_1node=$(progress_get_estimated_duration "aws" "deploy" 1)
    duration_4node=$(progress_get_estimated_duration "aws" "deploy" 4)
    
    # Based on metrics: 180s for 1 node, 420s for 4 nodes
    assert_equals "180" "$duration_1node" "AWS deploy 1-node duration should be 180s"
    assert_equals "420" "$duration_4node" "AWS deploy 4-node duration should be 420s"

    # Test non-existent operation (should return 0)
    local no_duration
    no_duration=$(progress_get_estimated_duration "nonexistent" "operation" 1)
    assert_equals "0" "$no_duration" "Non-existent operation should return duration=0"
}

# Test progress_display_with_eta output format
test_progress_display_format() {
    echo ""
    echo "Test: progress_display_with_eta produces correct output format"

    # Create test input and pipe through progress display
    printf "line1\nline2\nline3\nline4\nline5" | progress_display_with_eta 5 0 2>/dev/null
    
    local output
    output=$(printf "line1\nline2\nline3\nline4\nline5" | progress_display_with_eta 5 0 2>/dev/null)
    
    # Check that each line has the format: "[XX%] [ETA: ???] <text>"
    local line_count=0
    while IFS= read -r line; do
        line_count=$((line_count + 1))

        # Check format: starts with percentage in brackets (format: "[ XX%]" or "[100%]")
        if ! echo "$line" | grep -qE '^\[ ?[0-9]+%\] \[ETA:    [0-9?]+\] '; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Line $line_count does not match progress format: $line"
            return 1
        fi
    done <<< "$output"

    assert_equals "5" "$line_count" "Should have 5 output lines"
    TESTS_TOTAL=$((TESTS_TOTAL + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} All lines match progress format ([XX%] [ETA: time] text)"
}

# Test progress percentage calculation in display
test_progress_percentage_calculation() {
    echo ""
    echo "Test: progress percentages are calculated correctly"

    # Test with known input size
    local output
    output=$(printf "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10" | progress_display_with_eta 10 0 2>/dev/null)
    
    # Extract the last percentage
    local last_percent
    last_percent=$(echo "$output" | tail -1 | grep -oE '\[[0-9]+%\]' | grep -oE '[0-9]+')

    # 10 out of 10 lines should show 100%
    assert_equals "100" "$last_percent" "10 out of 10 lines should show 100%"
}

# Test progress capping at 100%
test_progress_caps_at_100() {
    echo ""
    echo "Test: progress caps at 100% even with more lines"

    # Process more lines than estimated
    local output
    output=$(printf "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\nline11\nline12\nline13\nline14\nline15\nline16\nline17\nline18\nline19\nline20" | progress_display_with_eta 10 0 2>/dev/null)

    # Extract all percentages and check none exceed 100
    local max_percent=0
    while IFS= read -r line; do
        local percent
        percent=$(echo "$line" | grep -oE '\[[0-9]+%\]' | grep -oE '[0-9]+')
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

        # Check if line matches progress format: "[XX%] [ETA: time] <text>"
        if [[ -z "$line" ]]; then
            continue
        fi

        # Strip ANSI color codes for validation
        local clean_line
        clean_line=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g; s/\x1b\[[0-9]*m//g')

        # For init command, we expect INFO logs, not progress format
        if ! echo "$clean_line" | grep -qE '^\[[0-9]+%\]\s*\[ETA:|^\[INFO\]|^\[WARN\]|^\[ERROR\]|^$'; then
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
test_progress_estimate_lines_scaling
test_progress_load_metrics
test_progress_parse_metric_file
test_progress_calculate_regression
test_progress_get_estimated_duration
test_progress_display_format
test_progress_percentage_calculation
test_progress_caps_at_100
test_init_output_format

test_summary