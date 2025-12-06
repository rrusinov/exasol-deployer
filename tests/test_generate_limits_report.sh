#!/usr/bin/env bash
# Unit tests for scripts/generate-limits-report.sh

if [[ -n "${__TEST_GENERATE_REPORT_INCLUDED__:-}" ]]; then return 0; fi
readonly __TEST_GENERATE_REPORT_INCLUDED__=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPORT_SCRIPT="$PROJECT_ROOT/scripts/generate-limits-report.sh"

readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_RESET='\033[0m'

test_count=0
pass_count=0
fail_count=0

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist: $file}"
    
    ((test_count++))
    if [[ -f "$file" ]]; then
        ((pass_count++))
        echo -e "${COLOR_GREEN}✓${COLOR_RESET} $message"
        return 0
    else
        ((fail_count++))
        echo -e "${COLOR_RED}✗${COLOR_RESET} $message"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    
    ((test_count++))
    if [[ "$haystack" == *"$needle"* ]]; then
        ((pass_count++))
        echo -e "${COLOR_GREEN}✓${COLOR_RESET} $message"
        return 0
    else
        ((fail_count++))
        echo -e "${COLOR_RED}✗${COLOR_RESET} $message"
        return 1
    fi
}

test_script_exists() {
    assert_file_exists "$REPORT_SCRIPT" "generate-limits-report.sh exists"
}

test_script_executable() {
    ((test_count++))
    if [[ -x "$REPORT_SCRIPT" ]]; then
        ((pass_count++))
        echo -e "${COLOR_GREEN}✓${COLOR_RESET} generate-limits-report.sh is executable"
        return 0
    else
        ((fail_count++))
        echo -e "${COLOR_RED}✗${COLOR_RESET} generate-limits-report.sh is not executable"
        return 1
    fi
}

test_help_option() {
    local output
    output=$("$REPORT_SCRIPT" --help 2>&1 || true)
    assert_contains "$output" "Usage:" "Help shows usage"
    assert_contains "$output" "--output" "Help shows --output option"
}

test_html_generation() {
    local temp_file="/tmp/test-limits-report-$$.html"
    
    "$REPORT_SCRIPT" --provider azure --output "$temp_file" >/dev/null 2>&1 || true
    
    assert_file_exists "$temp_file" "HTML report file created"
    
    if [[ -f "$temp_file" ]]; then
        local content
        content=$(cat "$temp_file")
        assert_contains "$content" "<!DOCTYPE html>" "HTML has DOCTYPE"
        assert_contains "$content" "<title>Cloud Resource Limits Report</title>" "HTML has title"
        assert_contains "$content" "toggleProvider" "HTML has JavaScript"
        assert_contains "$content" "quota-table" "HTML has quota table"
        assert_contains "$content" "Resource Quotas" "HTML has resource quotas section"
        
        rm -f "$temp_file"
    fi
}

test_all_regions_option() {
    local temp_file="/tmp/test-all-regions-$$.html"
    
    "$REPORT_SCRIPT" --provider azure --all-regions --output "$temp_file" >/dev/null 2>&1 || true
    
    ((test_count++))
    if [[ -f "$temp_file" ]]; then
        local region_count
        region_count=$(grep -c "Location:" "$temp_file" 2>/dev/null || echo "0")
        if [[ "$region_count" -gt 1 ]]; then
            ((pass_count++))
            echo -e "${COLOR_GREEN}✓${COLOR_RESET} All regions option works (found $region_count regions)"
        else
            ((fail_count++))
            echo -e "${COLOR_RED}✗${COLOR_RESET} All regions option failed"
        fi
        rm -f "$temp_file"
    else
        ((fail_count++))
        echo -e "${COLOR_RED}✗${COLOR_RESET} All regions file not created"
    fi
}

run_all_tests() {
    echo "Running generate-limits-report.sh tests..."
    echo "=========================================="
    
    test_script_exists
    test_script_executable
    test_help_option
    test_html_generation
    
    echo ""
    echo "=========================================="
    echo "Tests: $test_count, Passed: $pass_count, Failed: $fail_count"
    
    if [[ $fail_count -eq 0 ]]; then
        echo -e "${COLOR_GREEN}All tests passed!${COLOR_RESET}"
        return 0
    else
        echo -e "${COLOR_RED}Some tests failed!${COLOR_RESET}"
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
